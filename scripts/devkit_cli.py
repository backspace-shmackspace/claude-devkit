#!/usr/bin/env python3
"""devkit -- Meta-harness CLI for claude-devkit.

Thin orchestration layer that validates a target git repository, manages
lightweight per-project and global registry state, and delegates actual
skill execution to Claude Code (the `claude` CLI). No workflow engine, no
DAGs -- skills remain SKILL.md files executed by Claude Code with CWD set
to the target project.

Usage:
    devkit init <target>                     Initialize project for devkit management
    devkit <skill> <target> [args...]        Run a skill non-interactively in target
    devkit shell <target>                    Open interactive Claude session in target
    devkit status [<target>]                 Show status of one or all projects
    devkit deploy [--validate]               Ensure skills are deployed (delegates to deploy.sh)
    devkit --version                         Show version
    devkit --help                            Show help

Stdlib only. Python 3.8+.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

VERSION = "0.1.0"

STATE_SCHEMA_VERSION = "1.0.0"
REGISTRY_SCHEMA_VERSION = "1.0.0"

# Hardcoded defaults matching configs/devkit-defaults.json schema.
# Used when the config file is missing or corrupt so a deleted/damaged
# config never breaks every devkit invocation.
FALLBACK_DEFAULTS = {
    "schema_version": "1.0.0",
    "registry_path": "~/.claude-devkit/registry.json",
    "state_dir_name": ".devkit",
    "state_file_name": "state.json",
    "allowed_roots": ["~/projects/", "~/workspaces/"],
    "gitignore_state_dir": True,
    "claude_command": "claude",
    "claude_print_flag": "--print",
    "max_state_file_bytes": 65536,
    "max_registry_file_bytes": 1048576,
}

# Skill names must be lowercase, start with a letter, and contain only
# letters/digits/hyphens. This blocks path traversal (`../../etc/passwd`),
# leading-dash flag confusion, and non-filesystem-safe characters.
SKILL_NAME_RE = re.compile(r'^[a-z][a-z0-9-]*$')

KNOWN_COMMANDS = ("init", "shell", "status", "deploy")


class Colors:
    """ANSI color codes for terminal output."""
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    RESET = '\033[0m'
    BOLD = '\033[1m'


# --- Helpers ---------------------------------------------------------------

def get_devkit_root():
    """Resolve the claude-devkit repository root from this script's location."""
    return Path(__file__).resolve().parent.parent


def utc_now_iso():
    """Timezone-aware UTC timestamp in ISO 8601 form (Z-suffixed)."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_config():
    """Load configs/devkit-defaults.json relative to the devkit root.

    Falls back to FALLBACK_DEFAULTS (with a stderr warning) if the file is
    missing, unreadable, or not a JSON object. This is a deliberate failure
    mode: a corrupted or deleted config file must never break every devkit
    invocation.
    """
    config_path = get_devkit_root() / "configs" / "devkit-defaults.json"
    try:
        with open(config_path, "r") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            raise ValueError("config file does not contain a JSON object")
        merged = dict(FALLBACK_DEFAULTS)
        merged.update(data)
        return merged
    except (OSError, ValueError, json.JSONDecodeError) as e:
        print(
            f"{Colors.YELLOW}Warning:{Colors.RESET} Cannot load {config_path} "
            f"({e}); using hardcoded fallback defaults.",
            file=sys.stderr,
        )
        return dict(FALLBACK_DEFAULTS)


def _atomic_write_json(path, data, mode=0o600):
    """Write JSON to `path` atomically via tempfile + os.replace().

    Returns (ok, error_msg).
    """
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        return False, f"Cannot create directory {path.parent}: {e}"

    tmp_path = None
    try:
        fd, tmp_path = tempfile.mkstemp(
            dir=str(path.parent), prefix=".devkit-", suffix=".tmp"
        )
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.chmod(tmp_path, mode)
        os.replace(tmp_path, str(path))
        return True, ""
    except OSError as e:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
        return False, f"Cannot write {path}: {e}"


# --- Validation --------------------------------------------------------

def get_allowed_roots(config):
    """Resolved allowed-root directories: configured roots + devkit root + /tmp/."""
    roots = []
    for raw in config.get("allowed_roots", FALLBACK_DEFAULTS["allowed_roots"]):
        try:
            roots.append(Path(raw).expanduser().resolve())
        except OSError:
            continue
    roots.append(get_devkit_root())
    try:
        roots.append(Path("/tmp").resolve())
    except OSError:
        roots.append(Path("/tmp"))
    return roots


def validate_target(path_str, config):
    """Validate a target path is a safe, real git repository.

    Checks (in order): non-empty, exists, not a symlink, resolves to a
    directory, contains .git/, and the resolved path falls under one of
    the allowed roots.

    Returns (True, resolved_path) on success, (False, error_msg) on failure.
    All subsequent operations must use the returned resolved_path, never the
    original string (closes the TOCTOU gap between validation and use).
    """
    if not path_str:
        return False, "Target path is required"

    original = Path(path_str).expanduser()

    if not original.exists():
        return False, f"Target path does not exist: {path_str}"

    if original.is_symlink():
        return False, f"Target path is a symlink and is not allowed: {path_str}"

    try:
        resolved = original.resolve(strict=True)
    except OSError as e:
        return False, f"Cannot resolve target path {path_str}: {e}"

    if not resolved.is_dir():
        return False, f"Target path is not a directory: {resolved}"

    if not (resolved / ".git").exists():
        return False, f"Target path is not a git repository (no .git found): {resolved}"

    allowed_roots = get_allowed_roots(config)
    for root in allowed_roots:
        try:
            resolved.relative_to(root)
            return True, resolved
        except ValueError:
            continue

    roots_display = ", ".join(str(r) for r in allowed_roots)
    return False, (
        f"Target path {resolved} is not under an allowed root ({roots_display}). "
        f"Edit configs/devkit-defaults.json to add additional allowed_roots."
    )


def validate_skill_name(name):
    """Validate a skill name against the naming regex and deployment state.

    Returns (True, "") on success, (False, error_msg) on failure.
    """
    if not SKILL_NAME_RE.match(name):
        return False, (
            f"Invalid skill name '{name}': must match ^[a-z][a-z0-9-]*$ "
            f"(lowercase letters, digits, hyphens; must start with a letter)"
        )

    skill_path = Path.home() / ".claude" / "skills" / name / "SKILL.md"
    if not skill_path.exists():
        return False, (
            f"Skill '{name}' is not deployed (expected {skill_path}). "
            f"Run 'devkit deploy' first."
        )

    return True, ""


def validate_args(args):
    """Reject any argument starting with '--' to prevent Claude CLI flag injection.

    Applies only to arguments *before* an explicit '--' separator (see
    split_skill_args()). This is defense-in-depth on the pre-separator
    portion; it is not the sole protection against CLI flag injection --
    subprocess.run() is always invoked in list form with the fully-assembled
    prompt as a single argv element, so no skill argument (before or after
    '--') can ever be parsed by `claude` as a separate CLI flag.

    Returns (True, "") on success, (False, error_msg) on failure.
    """
    for arg in args:
        if arg.startswith("--"):
            return False, (
                f"Argument '{arg}' starts with '--' and is rejected to prevent "
                f"Claude CLI flag injection. Use the '--' separator to forward "
                f"it verbatim, e.g.: devkit <skill> <target> -- {arg}"
            )
    return True, ""


def split_skill_args(skill_args):
    """Split skill_args on a literal '--' separator token.

    Returns (pre_sep_args, post_sep_args). Only pre_sep_args are passed
    through validate_args()'s '--'-prefix rejection; post_sep_args are
    forwarded verbatim into the assembled prompt string (see
    cmd_run_skill()). This mirrors standard '--' semantics (git, `npm run
    --`): everything after the separator is passed through untouched.
    """
    if "--" in skill_args:
        sep_idx = skill_args.index("--")
        return skill_args[:sep_idx], skill_args[sep_idx + 1:]
    return list(skill_args), []


# --- State management (.devkit/state.json in target projects) --------------

def _validate_state_schema(data):
    """Validate types and max lengths of a loaded state.json dict.

    Returns (True, "") on success, (False, error_msg) on failure. The state
    file may originate from an untrusted cloned repository (TB-4), so no
    field is used in shell commands or path construction, and every field
    is type- and length-checked before use.
    """
    if not isinstance(data, dict):
        return False, "state is not a JSON object"

    schema_version = data.get("schema_version")
    if not isinstance(schema_version, str) or len(schema_version) > 20:
        return False, "invalid or missing schema_version"
    if schema_version != STATE_SCHEMA_VERSION:
        print(
            f"{Colors.YELLOW}Warning:{Colors.RESET} state.json schema_version "
            f"'{schema_version}' does not match expected '{STATE_SCHEMA_VERSION}'; "
            f"proceeding with best-effort parsing.",
            file=sys.stderr,
        )

    project_name = data.get("project_name")
    if not isinstance(project_name, str) or len(project_name) > 255:
        return False, "invalid or missing project_name"

    initialized_at = data.get("initialized_at")
    if not isinstance(initialized_at, str) or len(initialized_at) > 30:
        return False, "invalid or missing initialized_at"

    devkit_version = data.get("devkit_version")
    if not isinstance(devkit_version, str) or len(devkit_version) > 20:
        return False, "invalid or missing devkit_version"

    last_invocation = data.get("last_invocation")
    if last_invocation is not None:
        if not isinstance(last_invocation, dict):
            return False, "invalid last_invocation"
        skill = last_invocation.get("skill")
        if not isinstance(skill, str) or len(skill) > 64:
            return False, "invalid last_invocation.skill"
        args_val = last_invocation.get("args", "")
        if not isinstance(args_val, str) or len(args_val) > 1024:
            return False, "invalid last_invocation.args"
        timestamp = last_invocation.get("timestamp")
        if not isinstance(timestamp, str) or len(timestamp) > 30:
            return False, "invalid last_invocation.timestamp"
        exit_code = last_invocation.get("exit_code")
        if exit_code is not None and not isinstance(exit_code, int):
            return False, "invalid last_invocation.exit_code"

    return True, ""


def _state_file_path(target_path, config):
    return target_path / config["state_dir_name"] / config["state_file_name"]


def read_state(target_path, config):
    """Read and validate .devkit/state.json for `target_path`.

    Returns the parsed dict on success, or None (with a stderr warning) on
    any error: missing file, oversize file, malformed JSON, or schema
    validation failure. State is informational only -- callers must treat
    None as "no state available" and proceed.
    """
    state_file = _state_file_path(target_path, config)
    if not state_file.exists():
        return None

    max_bytes = config.get("max_state_file_bytes", FALLBACK_DEFAULTS["max_state_file_bytes"])
    try:
        size = state_file.stat().st_size
        if size > max_bytes:
            print(
                f"{Colors.YELLOW}Warning:{Colors.RESET} {state_file} exceeds max size "
                f"({size} > {max_bytes} bytes); ignoring.",
                file=sys.stderr,
            )
            return None
        with open(state_file, "r") as f:
            raw = f.read(max_bytes + 1)
        data = json.loads(raw)
    except (OSError, json.JSONDecodeError) as e:
        print(
            f"{Colors.YELLOW}Warning:{Colors.RESET} Cannot read/parse {state_file}: {e}",
            file=sys.stderr,
        )
        return None

    ok, err = _validate_state_schema(data)
    if not ok:
        print(
            f"{Colors.YELLOW}Warning:{Colors.RESET} Invalid state schema in {state_file}: {err}",
            file=sys.stderr,
        )
        return None

    return data


def write_state(target_path, state_dict, config):
    """Atomically write .devkit/state.json for `target_path` (mode 0o600)."""
    state_file = _state_file_path(target_path, config)
    ok, err = _atomic_write_json(state_file, state_dict, mode=0o600)
    if not ok:
        print(f"{Colors.YELLOW}Warning:{Colors.RESET} {err}", file=sys.stderr)
    return ok, err


# --- Registry management (~/.claude-devkit/registry.json) ------------------

def get_registry_path(config):
    """Resolve the registry file path.

    Honors DEVKIT_REGISTRY_OVERRIDE (test-only hook) when set, so
    scripts/test-integration.sh can point the meta-harness tests at a
    throwaway registry file instead of the real
    ~/.claude-devkit/registry.json. Not documented as a user-facing feature.
    """
    override = os.environ.get("DEVKIT_REGISTRY_OVERRIDE")
    if override:
        return Path(override).expanduser()
    return Path(
        config.get("registry_path", FALLBACK_DEFAULTS["registry_path"])
    ).expanduser()


def _empty_registry():
    return {
        "schema_version": REGISTRY_SCHEMA_VERSION,
        "updated_at": utc_now_iso(),
        "projects": [],
    }


def read_registry(config):
    """Read ~/.claude-devkit/registry.json.

    Returns an empty registry (never raises) if the file is missing,
    oversize, or malformed. The registry is informational only -- never
    authoritative.
    """
    registry_path = get_registry_path(config)
    if not registry_path.exists():
        return _empty_registry()

    max_bytes = config.get("max_registry_file_bytes", FALLBACK_DEFAULTS["max_registry_file_bytes"])
    try:
        size = registry_path.stat().st_size
        if size > max_bytes:
            print(
                f"{Colors.YELLOW}Warning:{Colors.RESET} Registry {registry_path} exceeds "
                f"max size ({size} > {max_bytes} bytes); recreating empty registry.",
                file=sys.stderr,
            )
            return _empty_registry()
        with open(registry_path, "r") as f:
            raw = f.read(max_bytes + 1)
        data = json.loads(raw)
        if not isinstance(data, dict) or not isinstance(data.get("projects"), list):
            raise ValueError("malformed registry structure")
        return data
    except (OSError, ValueError, json.JSONDecodeError) as e:
        print(
            f"{Colors.YELLOW}Warning:{Colors.RESET} Cannot read registry {registry_path} "
            f"({e}); recreating empty registry. Previous entries are lost -- rebuild by "
            f"re-running 'devkit init' on each project.",
            file=sys.stderr,
        )
        return _empty_registry()


def write_registry(registry_dict, config):
    """Atomically write ~/.claude-devkit/registry.json (mode 0o600, dir 0o700)."""
    registry_path = get_registry_path(config)
    try:
        registry_path.parent.mkdir(parents=True, exist_ok=True)
        os.chmod(registry_path.parent, 0o700)
    except OSError as e:
        return False, f"Cannot prepare {registry_path.parent}: {e}"

    ok, err = _atomic_write_json(registry_path, registry_dict, mode=0o600)
    if not ok:
        print(f"{Colors.YELLOW}Warning:{Colors.RESET} {err}", file=sys.stderr)
    return ok, err


def update_registry(target_path, config, touch=True, register=True):
    """Add or update a project entry in the global registry.

    No file locking is implemented -- concurrent devkit invocations may
    lose an update to `last_touched`. Accepted limitation given the
    informational nature of the registry (see plan Design Decisions).
    """
    registry = read_registry(config)
    now = utc_now_iso()
    path_str = str(target_path)

    projects = registry.setdefault("projects", [])
    entry = next((p for p in projects if p.get("path") == path_str), None)

    if entry is None:
        if not register:
            return
        projects.append({
            "path": path_str,
            "name": target_path.name,
            "registered_at": now,
            "last_touched": now,
        })
    elif touch:
        entry["last_touched"] = now

    registry["schema_version"] = registry.get("schema_version", REGISTRY_SCHEMA_VERSION)
    registry["updated_at"] = now
    write_registry(registry, config)


# --- .gitignore management ---------------------------------------------

def ensure_gitignore_entry(target_path, state_dir_name):
    """Append `<state_dir_name>/` to target_path/.gitignore if not already present."""
    entry = f"{state_dir_name}/"
    bare_entry = state_dir_name
    gitignore_path = target_path / ".gitignore"

    try:
        if gitignore_path.exists():
            with open(gitignore_path, "r") as f:
                content = f.read()
            existing_lines = {line.strip() for line in content.splitlines()}
            if entry in existing_lines or bare_entry in existing_lines:
                return True, ""
            if content and not content.endswith("\n"):
                content += "\n"
            new_content = content + entry + "\n"
        else:
            new_content = entry + "\n"

        tmp_path = None
        try:
            fd, tmp_path = tempfile.mkstemp(
                dir=str(target_path), prefix=".gitignore-", suffix=".tmp"
            )
            with os.fdopen(fd, "w") as f:
                f.write(new_content)
            os.replace(tmp_path, str(gitignore_path))
        except OSError:
            if tmp_path and os.path.exists(tmp_path):
                os.unlink(tmp_path)
            raise
        return True, ""
    except OSError as e:
        return False, f"Cannot update .gitignore: {e}"


# --- Pre-flight checks ---------------------------------------------------

def preflight(skill, target_path, config):
    """Run pre-flight checks for a skill invocation or shell session.

    Returns a list of (level, message) tuples where level is "error" or
    "warning". Does not short-circuit -- all issues are collected. Callers
    treat any "error" as fatal and "warning" as advisory.
    """
    issues = []

    claude_cmd = config.get("claude_command", FALLBACK_DEFAULTS["claude_command"])
    if shutil.which(claude_cmd) is None:
        issues.append((
            "error",
            f"'{claude_cmd}' command not found on PATH. Install Claude Code CLI.",
        ))

    if skill is not None:
        skill_path = Path.home() / ".claude" / "skills" / skill / "SKILL.md"
        if not skill_path.exists():
            issues.append((
                "error",
                f"Skill '{skill}' is not deployed (expected {skill_path}). "
                f"Run 'devkit deploy' first.",
            ))

    devkit_root = get_devkit_root()
    if not (devkit_root / "skills").is_dir():
        issues.append((
            "warning",
            f"CLAUDE_DEVKIT ({devkit_root}) does not look like a valid devkit "
            f"installation (no skills/ directory).",
        ))

    state_file = _state_file_path(target_path, config)
    if not state_file.exists():
        issues.append((
            "warning",
            f"Project not initialized for devkit (no {state_file}). "
            f"Run 'devkit init {target_path}'.",
        ))

    if not _has_tool_allowlist(target_path):
        issues.append((
            "warning",
            "No tool permissions configured. Non-interactive skill execution "
            "may stall on permission prompts. See CLAUDE.md Tool Permissions section.",
        ))

    return issues


def _has_tool_allowlist(target_path):
    """Best-effort check for a configured tool permission allowlist.

    Checks project-level .claude/settings.json first, then falls back to
    the user's global ~/.claude/settings.json. Purely advisory -- errors
    are swallowed and treated as "not configured".
    """
    candidates = [
        target_path / ".claude" / "settings.json",
        target_path / ".claude" / "settings.local.json",
        Path.home() / ".claude" / "settings.json",
    ]
    for settings_path in candidates:
        if not settings_path.exists():
            continue
        try:
            with open(settings_path, "r") as f:
                settings = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        permissions = settings.get("permissions")
        if isinstance(permissions, dict) and permissions.get("allow"):
            return True
        if settings.get("allowedTools"):
            return True
    return False


# --- Commands -------------------------------------------------------------

def cmd_init(target_str, config):
    ok, result = validate_target(target_str, config)
    if not ok:
        print(f"{Colors.RED}Error:{Colors.RESET} {result}", file=sys.stderr)
        return 1
    resolved = result

    now = utc_now_iso()
    state = {
        "schema_version": STATE_SCHEMA_VERSION,
        "project_name": resolved.name,
        "initialized_at": now,
        "devkit_version": VERSION,
    }
    ok, err = write_state(resolved, state, config)
    if not ok:
        print(f"{Colors.RED}Error:{Colors.RESET} {err}", file=sys.stderr)
        return 1

    if config.get("gitignore_state_dir", True):
        ok, err = ensure_gitignore_entry(resolved, config["state_dir_name"])
        if not ok:
            print(f"{Colors.YELLOW}Warning:{Colors.RESET} {err}", file=sys.stderr)

    update_registry(resolved, config, touch=True, register=True)

    print(f"{Colors.GREEN}Initialized devkit for '{resolved.name}' at {resolved}{Colors.RESET}")
    return 0


def cmd_run_skill(skill, target_str, validated_args, passthrough_args, config):
    """Run a skill non-interactively against `target_str`.

    `validated_args` are checked by validate_args() (pre-'--'-separator
    tokens); `passthrough_args` are forwarded verbatim (post-separator
    tokens, see split_skill_args()). Both are joined into a single prompt
    string below -- subprocess.run() is always list-form, so neither group
    can ever reach `claude` as a separate CLI flag regardless of prefix.
    """
    ok, result = validate_target(target_str, config)
    if not ok:
        print(f"{Colors.RED}Error:{Colors.RESET} {result}", file=sys.stderr)
        return 1
    resolved = result

    ok, err = validate_skill_name(skill)
    if not ok:
        print(f"{Colors.RED}Error:{Colors.RESET} {err}", file=sys.stderr)
        return 1

    ok, err = validate_args(validated_args)
    if not ok:
        print(f"{Colors.RED}Error:{Colors.RESET} {err}", file=sys.stderr)
        return 1

    args = validated_args + passthrough_args

    issues = preflight(skill, resolved, config)
    fatal = False
    for level, msg in issues:
        if level == "error":
            print(f"{Colors.RED}Error:{Colors.RESET} {msg}", file=sys.stderr)
            fatal = True
        else:
            print(f"{Colors.YELLOW}Warning:{Colors.RESET} {msg}", file=sys.stderr)
    if fatal:
        return 1

    args_str = " ".join(args)
    existing_state = read_state(resolved, config) or {}
    base_state = {
        "schema_version": existing_state.get("schema_version", STATE_SCHEMA_VERSION),
        "project_name": resolved.name,
        "initialized_at": existing_state.get("initialized_at", utc_now_iso()),
        "devkit_version": VERSION,
    }

    # Pre-invocation state write: records that the invocation started, in
    # case the process is killed before the finally block below can update
    # it with the real exit code.
    pre_state = dict(base_state)
    pre_state["last_invocation"] = {
        "skill": skill,
        "args": args_str[:1024],
        "timestamp": utc_now_iso(),
        "exit_code": None,
    }
    write_state(resolved, pre_state, config)
    update_registry(resolved, config, touch=True, register=True)

    env = os.environ.copy()
    env["CLAUDE_DEVKIT"] = str(get_devkit_root())

    prompt = f"/{skill}"
    if args_str:
        prompt += f" {args_str}"

    claude_cmd = config.get("claude_command", FALLBACK_DEFAULTS["claude_command"])
    print_flag = config.get("claude_print_flag", FALLBACK_DEFAULTS["claude_print_flag"])
    invocation = [claude_cmd, print_flag, "--output-format", "json", prompt]

    # Pre-run banner
    print(
        f"{Colors.CYAN}devkit:{Colors.RESET} {resolved.name} | "
        f"/{skill} | {resolved}",
        file=sys.stderr,
    )

    exit_code = 1
    wall_start = time.monotonic()
    try:
        # List-form subprocess.run -- never shell=True. Capture stdout so
        # we can parse the JSON envelope for usage metadata.
        proc = subprocess.run(
            invocation, cwd=str(resolved), env=env,
            capture_output=True, text=True,
        )
        exit_code = proc.returncode

        # Print stderr passthrough (claude warnings, progress, etc.)
        if proc.stderr:
            print(proc.stderr, end="", file=sys.stderr)

        _print_run_result(proc.stdout, exit_code, wall_start)
    finally:
        final_state = dict(base_state)
        final_state["last_invocation"] = {
            "skill": skill,
            "args": args_str[:1024],
            "timestamp": utc_now_iso(),
            "exit_code": exit_code,
        }
        write_state(resolved, final_state, config)
        update_registry(resolved, config, touch=True, register=True)

    return exit_code


def _format_duration(seconds):
    """Format seconds into a human-readable duration string."""
    if seconds < 60:
        return f"{seconds:.1f}s"
    minutes = int(seconds // 60)
    secs = int(seconds % 60)
    return f"{minutes}m {secs}s"


def _format_tokens(n):
    """Format token count with k/M suffix."""
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}k"
    return str(n)


def _print_run_result(stdout, exit_code, wall_start):
    """Parse JSON output from claude --print, display result and summary."""
    elapsed = time.monotonic() - wall_start

    # Try to parse JSON envelope
    result_text = None
    usage_line = None
    try:
        data = json.loads(stdout)
        result_text = data.get("result", "")
        cost = data.get("total_cost_usd")
        usage = data.get("usage", {})
        input_tok = usage.get("input_tokens", 0)
        output_tok = usage.get("output_tokens", 0)
        cache_read = usage.get("cache_read_input_tokens", 0)
        num_turns = data.get("num_turns", 0)

        parts = [_format_duration(elapsed)]
        if input_tok or output_tok:
            parts.append(
                f"{_format_tokens(input_tok)} in / "
                f"{_format_tokens(output_tok)} out"
            )
        if cache_read:
            parts.append(f"{_format_tokens(cache_read)} cached")
        if cost is not None:
            parts.append(f"${cost:.4f}")
        if num_turns:
            parts.append(f"{num_turns} turn{'s' if num_turns != 1 else ''}")
        usage_line = " | ".join(parts)
    except (json.JSONDecodeError, TypeError, KeyError):
        # Not valid JSON -- fall back to raw output
        result_text = stdout

    # Print the actual result
    if result_text:
        print(result_text)

    # Post-run summary
    status = (
        f"{Colors.GREEN}completed{Colors.RESET}"
        if exit_code == 0
        else f"{Colors.RED}failed (exit {exit_code}){Colors.RESET}"
    )
    summary = f"{Colors.CYAN}devkit:{Colors.RESET} {status}"
    if usage_line:
        summary += f" | {usage_line}"
    else:
        summary += f" | {_format_duration(elapsed)}"
    print(summary, file=sys.stderr)


def cmd_shell(target_str, config):
    ok, result = validate_target(target_str, config)
    if not ok:
        print(f"{Colors.RED}Error:{Colors.RESET} {result}", file=sys.stderr)
        return 1
    resolved = result

    issues = preflight(None, resolved, config)
    fatal = False
    for level, msg in issues:
        if level == "error":
            print(f"{Colors.RED}Error:{Colors.RESET} {msg}", file=sys.stderr)
            fatal = True
        else:
            print(f"{Colors.YELLOW}Warning:{Colors.RESET} {msg}", file=sys.stderr)
    if fatal:
        return 1

    # State/registry are updated before execvp because the harness process
    # is replaced and never regains control (known limitation: exit_code
    # remains null for interactive sessions -- see plan State Model section).
    now = utc_now_iso()
    existing_state = read_state(resolved, config) or {}
    state = {
        "schema_version": existing_state.get("schema_version", STATE_SCHEMA_VERSION),
        "project_name": resolved.name,
        "initialized_at": existing_state.get("initialized_at", now),
        "devkit_version": VERSION,
        "last_invocation": {
            "skill": "shell",
            "args": "",
            "timestamp": now,
            "exit_code": None,
        },
    }
    write_state(resolved, state, config)
    update_registry(resolved, config, touch=True, register=True)

    claude_cmd = config.get("claude_command", FALLBACK_DEFAULTS["claude_command"])

    # Mutate os.environ (not a local copy) so os.execvp's replacement
    # process inherits CLAUDE_DEVKIT via the real process environment.
    os.environ["CLAUDE_DEVKIT"] = str(get_devkit_root())

    try:
        os.chdir(str(resolved))
    except OSError as e:
        print(f"{Colors.RED}Error:{Colors.RESET} Cannot chdir to {resolved}: {e}", file=sys.stderr)
        return 1

    try:
        os.execvp(claude_cmd, [claude_cmd])
    except OSError as e:
        print(f"{Colors.RED}Error:{Colors.RESET} Cannot exec '{claude_cmd}': {e}", file=sys.stderr)
        return 1
    return 0  # unreachable if execvp succeeds


def cmd_status(target_str, config):
    if target_str:
        ok, result = validate_target(target_str, config)
        if not ok:
            print(f"{Colors.RED}Error:{Colors.RESET} {result}", file=sys.stderr)
            return 1
        resolved = result

        print(f"Project: {resolved.name}")
        print(f"Path: {resolved}")

        state = read_state(resolved, config)
        if state is None:
            print(f"Status: not initialized (run 'devkit init {resolved}')")
        else:
            print(f"Initialized: {state.get('initialized_at', 'unknown')}")
            print(f"Devkit version at init: {state.get('devkit_version', 'unknown')}")
            last = state.get("last_invocation")
            if last:
                print(f"Last invocation: /{last.get('skill')} (args: {last.get('args', '')})")
                print(f"  Timestamp: {last.get('timestamp')}")
                print(f"  Exit code: {last.get('exit_code')}")
            else:
                print("Last invocation: none")

        settings_path = resolved / ".claude" / "settings.json"
        maturity = "L1 (default, no .claude/settings.json)"
        if settings_path.exists():
            try:
                with open(settings_path, "r") as f:
                    settings = json.load(f)
                maturity = settings.get("security_maturity", "L1 (not set in settings.json)")
            except (OSError, json.JSONDecodeError):
                maturity = "unknown (settings.json unreadable)"
        print(f"Security maturity: {maturity}")

        audit_log_dir = resolved / "plans" / "audit-logs"
        log_count = len(list(audit_log_dir.glob("*.jsonl"))) if audit_log_dir.is_dir() else 0
        print(f"Audit logs: {log_count}")
        return 0

    registry = read_registry(config)
    projects = registry.get("projects", [])
    if not projects:
        print("No projects registered. Run 'devkit init <target>' to register a project.")
        return 0

    print(f"{'NAME':<30} {'LAST TOUCHED':<25} {'STATUS':<10} PATH")
    for project in projects:
        path = project.get("path", "")
        name = project.get("name", "")
        last_touched = project.get("last_touched", "")
        status = "ok" if Path(path).is_dir() else "[STALE]"
        print(f"{name:<30} {last_touched:<25} {status:<10} {path}")
    return 0


def cmd_deploy(args, config):
    deploy_sh = get_devkit_root() / "scripts" / "deploy.sh"
    if not deploy_sh.exists():
        print(f"{Colors.RED}Error:{Colors.RESET} deploy.sh not found at {deploy_sh}", file=sys.stderr)
        return 1
    try:
        result = subprocess.run(["bash", str(deploy_sh)] + list(args))
        return result.returncode
    except OSError as e:
        print(f"{Colors.RED}Error:{Colors.RESET} Cannot run deploy.sh: {e}", file=sys.stderr)
        return 1


# --- Argument parsing / entry point ----------------------------------------

def print_help():
    print(f"""devkit {VERSION} -- Meta-harness CLI for claude-devkit

Usage:
  devkit init <target>                     Initialize project for devkit management
  devkit <skill> <target> [args...]        Run a skill non-interactively in target
  devkit shell <target>                    Open interactive Claude session in target
  devkit status [<target>]                 Show status of one or all projects
  devkit deploy [--validate]               Ensure skills are deployed (delegates to deploy.sh)
  devkit --version                         Show version
  devkit --help                            Show help

Examples:
  devkit init ~/projects/my-app
  devkit audit ~/projects/my-app
  devkit architect ~/projects/my-app "add user authentication"
  devkit ship ~/projects/my-app .devkit/plans/add-user-auth.md
  devkit shell ~/projects/my-app
  devkit status
  devkit status ~/projects/my-app

Notes:
  Skill arguments starting with '--' are rejected unless they come after a
  '--' separator, which forwards everything following it verbatim (standard
  '--' semantics, as in `git` or `npm run --`). Use this to pass skill flags
  like `--fast`:
    devkit architect ~/foo -- --fast

  Target paths must resolve under an allowed root (default: ~/projects/,
  ~/workspaces/, plus the devkit installation and /tmp/). Edit
  configs/devkit-defaults.json to widen allowed_roots.
""")


def main():
    argv = sys.argv[1:]

    if not argv:
        print_help()
        return 0

    if argv[0] in ("-h", "--help"):
        print_help()
        return 0

    if argv[0] in ("-v", "--version"):
        print(f"devkit {VERSION}")
        return 0

    config = load_config()
    command, rest = argv[0], argv[1:]

    # Known subcommands are dispatched directly. Anything else is treated as
    # a dynamic skill name (see validate_skill_name for the safety gate) --
    # this avoids hardcoding the list of deployed skills. Parsing is done
    # manually rather than via argparse subparsers because argparse cannot
    # express "any unrecognized token is a valid subcommand" cleanly.
    if command == "init":
        if not rest:
            print(f"{Colors.RED}Error:{Colors.RESET} devkit init requires a target path", file=sys.stderr)
            return 2
        return cmd_init(rest[0], config)

    if command == "shell":
        if not rest:
            print(f"{Colors.RED}Error:{Colors.RESET} devkit shell requires a target path", file=sys.stderr)
            return 2
        return cmd_shell(rest[0], config)

    if command == "status":
        target = rest[0] if rest else None
        return cmd_status(target, config)

    if command == "deploy":
        return cmd_deploy(rest, config)

    # Dynamic skill dispatch.
    skill = command
    if not rest:
        print(f"{Colors.RED}Error:{Colors.RESET} devkit {skill} requires a target path", file=sys.stderr)
        return 2
    target = rest[0]
    skill_args = rest[1:]

    # "--" separates devkit-parsed tokens (subject to validate_args()'s
    # '--'-prefix rejection) from skill arguments forwarded verbatim after
    # it -- see split_skill_args() and validate_args() docstrings.
    pre_sep_args, post_sep_args = split_skill_args(skill_args)

    return cmd_run_skill(skill, target, pre_sep_args, post_sep_args, config)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Interrupted.{Colors.RESET}", file=sys.stderr)
        sys.exit(130)
