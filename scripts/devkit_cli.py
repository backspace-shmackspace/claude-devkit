#!/usr/bin/env python3
"""devkit -- Meta-harness CLI for claude-devkit.

Thin orchestration layer that validates a target git repository, manages
lightweight per-project and global registry state, and delegates actual
skill execution to Claude Code (the `claude` CLI). No workflow engine, no
DAGs -- skills remain SKILL.md files executed by Claude Code with CWD set
to the target project.

All devkit artifacts (state, plans, audit logs, archives) live under
~/.claude-devkit/projects/<project-id>/, never inside the target project.
Skills locate this directory via the DEVKIT_PROJECT_DIR environment
variable, which this CLI sets before every skill invocation.

Usage:
    devkit init <target>                     Initialize project for devkit management
    devkit <skill> <target> [args...]        Run a skill non-interactively in target
    devkit <skill> <target> --detach         Run skill in background, return run ID
    devkit shell <target>                    Open interactive Claude session in target
    devkit status [<target>]                 Show status of one or all projects
    devkit migrate <target>                  Migrate legacy .devkit/ artifacts to central storage
    devkit relink <old-path> <new-path>      Recover artifacts after a project rename/move
    devkit path <target> [subpath]           Print the central artifact directory path
    devkit jobs [<target>]                   List background runs (all or filtered)
    devkit result <run-id>                   Print result of a completed run
    devkit logs <run-id>                     Print stderr logs of a run
    devkit clean [--days N]                  Remove old runs (default: 7 days)
    devkit deploy [--validate]               Ensure skills are deployed (delegates to deploy.sh)
    devkit --version                         Show version
    devkit --help                            Show help

Stdlib only. Python 3.8+.
"""

import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

VERSION = "0.3.0"

STATE_SCHEMA_VERSION = "1.1.0"
REGISTRY_SCHEMA_VERSION = "1.0.0"
PLAN_REF_SCHEMA_VERSION = "1.0.0"

# Hardcoded defaults matching configs/devkit-defaults.json schema.
# Used when the config file is missing or corrupt so a deleted/damaged
# config never breaks every devkit invocation.
FALLBACK_DEFAULTS = {
    "schema_version": "1.0.0",
    "registry_path": "~/.claude-devkit/registry.json",
    "state_file_name": "state.json",
    "allowed_roots": ["~/projects/", "~/workspaces/"],
    "scripts_dir_name": "scripts",
    "claude_command": "claude",
    "claude_print_flag": "--print",
    "max_state_file_bytes": 65536,
    "max_registry_file_bytes": 1048576,
    "clean_retention_days": 7,
    "max_cross_repo_targets": 10,
}

# Skill names must be lowercase, start with a letter, and contain only
# letters/digits/hyphens. This blocks path traversal (`../../etc/passwd`),
# leading-dash flag confusion, and non-filesystem-safe characters.
SKILL_NAME_RE = re.compile(r'^[a-z][a-z0-9-]*$')

# Project IDs are <basename>-<12-hex-chars> computed from SHA-256 of resolved paths.
# Used by resolve_devkit_uri() and validate_plan_targets() for format validation.
PROJECT_ID_RE = re.compile(r'^[a-zA-Z0-9._-]+-[0-9a-f]{12}$')

KNOWN_COMMANDS = (
    "init", "shell", "status", "deploy", "jobs", "result", "logs", "clean",
    "migrate", "relink", "path",
)


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


# --- Project identity (zero-project-footprint) ------------------------------

def compute_project_id(resolved_path):
    """Compute a stable, filesystem-safe project ID from an absolute path.

    Returns '<sanitized-basename>-<sha256[:12]>'. The basename prefix is for
    human navigation only; the hash suffix guarantees uniqueness. Case is
    normalized before hashing on case-insensitive platforms (macOS, Windows)
    so the same physical directory always maps to the same ID regardless of
    how it is cased when referenced.

    Raises ValueError if the path's basename is empty (e.g., filesystem
    root) -- callers must reject such targets before reaching this point
    (see validate_target()'s root guard).
    """
    canonical = str(resolved_path)
    if sys.platform == 'darwin' or sys.platform == 'win32':
        canonical = canonical.lower()

    basename = os.path.basename(canonical)
    if not basename:
        raise ValueError("Cannot use filesystem root as a project target")

    # Sanitize basename: keep only alphanumeric, dot, hyphen, underscore.
    sanitized = re.sub(r'[^a-zA-Z0-9._-]', '-', basename)
    sanitized = re.sub(r'-+', '-', sanitized)  # collapse runs of hyphens
    sanitized = sanitized.strip('-')[:64]       # truncate to reasonable length
    if not sanitized:
        sanitized = 'project'  # fallback for all-special-char names

    hash_val = hashlib.sha256(canonical.encode()).hexdigest()[:12]
    return f"{sanitized}-{hash_val}"


def get_project_dir(resolved_path):
    """Return the central artifact directory Path for a resolved project path.

    ~/.claude-devkit/projects/<project-id>/ -- never inside the target
    project itself. Raises ValueError (propagated from compute_project_id)
    if resolved_path is the filesystem root.
    """
    project_id = compute_project_id(resolved_path)
    return Path.home() / ".claude-devkit" / "projects" / project_id


def get_scripts_dir(config):
    """Return the deployed helper-scripts directory (~/.claude-devkit/<scripts_dir_name>)."""
    scripts_dir_name = config.get(
        "scripts_dir_name", FALLBACK_DEFAULTS.get("scripts_dir_name", "scripts")
    )
    return Path.home() / ".claude-devkit" / scripts_dir_name


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
    directory, not the filesystem root, contains .git/, and the resolved
    path falls under one of the allowed roots.

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

    if not os.path.basename(str(resolved)):
        return False, "Cannot use filesystem root as a project target"

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


# --- State management (~/.claude-devkit/projects/<id>/state.json) ----------

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

    # project_id / project_path were introduced in schema 1.1.0. Older
    # (1.0.0) state files legitimately omit them -- read_state() fills
    # them in on first read (schema migration). Only type/length-check
    # when present.
    project_id = data.get("project_id")
    if project_id is not None and (not isinstance(project_id, str) or len(project_id) > 128):
        return False, "invalid project_id"

    project_path = data.get("project_path")
    if project_path is not None and (not isinstance(project_path, str) or len(project_path) > 4096):
        return False, "invalid project_path"

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
    """Return the central state.json path for a resolved target project path.

    Location is always derived from the *current* resolved target path
    (via get_project_dir()), never from a cached project ID -- this is what
    makes a renamed/moved project's old artifacts appear "orphaned" until
    `devkit relink` is run (see plan Directory Rename/Move Handling).
    """
    project_dir = get_project_dir(target_path)
    return project_dir / config.get("state_file_name", FALLBACK_DEFAULTS["state_file_name"])


def read_state(target_path, config):
    """Read and validate the central state.json for `target_path`.

    Returns the parsed dict on success, or None (with a stderr warning) on
    any error: missing file, oversize file, malformed JSON, or schema
    validation failure. State is informational only -- callers must treat
    None as "no state available" and proceed.

    Schema migration: state files written before schema 1.1.0 lack
    `project_id`/`project_path`. Those fields are computed from
    `target_path` and written back on first read -- a forward-compatible
    migration that requires no explicit user action.
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

    if "project_id" not in data or "project_path" not in data:
        try:
            data["project_id"] = compute_project_id(target_path)
        except ValueError:
            pass
        data["project_path"] = str(target_path)
        data["schema_version"] = STATE_SCHEMA_VERSION
        write_state(target_path, data, config)

    return data


def write_state(target_path, state_dict, config):
    """Atomically write the central state.json for `target_path` (mode 0o600).

    Ensures the parent project directory exists with 0o700 permissions
    before writing -- this is what enforces the 0o700 invariant even when
    a skill is invoked without a prior explicit `devkit init` (see plan
    Security Controls: Directory permissions).
    """
    state_file = _state_file_path(target_path, config)
    try:
        state_file.parent.mkdir(parents=True, exist_ok=True)
        os.chmod(state_file.parent, 0o700)
    except OSError as e:
        print(
            f"{Colors.YELLOW}Warning:{Colors.RESET} Cannot prepare {state_file.parent}: {e}",
            file=sys.stderr,
        )
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


def update_registry(target_path, config, touch=True, register=True, project_id=None):
    """Add or update a project entry in the global registry.

    `project_id` is stamped onto the entry when provided (e.g., by
    cmd_init/cmd_migrate/cmd_relink, which already computed it). When
    omitted, it is computed from `target_path` on a best-effort basis so
    entries created via older call sites still gain the field.

    No file locking is implemented -- concurrent devkit invocations may
    lose an update to `last_touched`. Accepted limitation given the
    informational nature of the registry (see plan Design Decisions).
    """
    registry = read_registry(config)
    now = utc_now_iso()
    path_str = str(target_path)

    if project_id is None:
        try:
            project_id = compute_project_id(target_path)
        except ValueError:
            project_id = None

    projects = registry.setdefault("projects", [])
    entry = next((p for p in projects if p.get("path") == path_str), None)

    if entry is None:
        if not register:
            return
        new_entry = {
            "path": path_str,
            "name": target_path.name,
            "registered_at": now,
            "last_touched": now,
        }
        if project_id:
            new_entry["project_id"] = project_id
        projects.append(new_entry)
    else:
        if touch:
            entry["last_touched"] = now
        if project_id:
            entry["project_id"] = project_id

    registry["schema_version"] = registry.get("schema_version", REGISTRY_SCHEMA_VERSION)
    registry["updated_at"] = now
    write_registry(registry, config)


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

    # Central project directory permission check -- if it already exists
    # (e.g., from a prior run or explicit `devkit init`), it must be 0o700.
    # write_state()/cmd_init() always create it with 0o700; a mismatch here
    # means something else modified it after the fact (see plan Security
    # Controls: Directory permissions).
    try:
        project_dir = get_project_dir(target_path)
    except ValueError:
        project_dir = None
    if project_dir is not None and project_dir.exists():
        try:
            mode = stat.S_IMODE(project_dir.stat().st_mode)
        except OSError as e:
            issues.append(("error", f"Cannot stat {project_dir}: {e}"))
        else:
            if mode != 0o700:
                issues.append((
                    "error",
                    f"{project_dir} has insecure permissions ({oct(mode)}). "
                    f"Expected 0o700. Fix with: chmod 700 {project_dir}",
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


# --- Run ID / PID helpers -------------------------------------------------

def _generate_run_id():
    """Generate a timestamped random run ID (YYYYMMDD-HHMMSS-<6-hex>)."""
    now = datetime.now(timezone.utc)
    timestamp = now.strftime("%Y%m%d-%H%M%S")
    random_suffix = os.urandom(3).hex()
    return f"{timestamp}-{random_suffix}"


def _validate_run_id(run_id):
    """Validate run ID contains no path separators or traversal."""
    if Path(run_id).name != run_id:
        return False, f"Invalid run ID (path traversal rejected): {run_id}"
    return True, ""


def _is_pid_alive(pid):
    """Check if a PID is still running (POSIX only)."""
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        # Process exists but we don't own it
        return True
    except OSError:
        return False


def _status_color(status):
    """Return status string with ANSI color for terminal display."""
    colors = {
        "running": "\033[33m",   # yellow
        "completed": "\033[32m", # green
        "failed": "\033[31m",    # red
        "stale": "\033[90m",     # gray
    }
    reset = "\033[0m"
    color = colors.get(status, "")
    return f"{color}{status}{reset}" if color else status


# --- Commands -------------------------------------------------------------

def _spawn_watcher(runs_dir, invocation, cwd, env):
    """Spawn a background watcher that launches Claude and finalizes on completion.

    The watcher receives all variable values via sys.argv -- no f-string
    interpolation into source code. This prevents injection if path values
    ever contain Python string metacharacters.

    The watcher process itself is spawned with `env=env` below, so its own
    `os.environ` (and therefore `os.environ.copy()` inside the inline
    script) already reflects `env` -- including DEVKIT_PROJECT_DIR and
    DEVKIT_SCRIPTS. This is how those variables reach the Claude subprocess
    the watcher spawns as its own child.
    """
    watcher_script = '''
import os, json, sys, subprocess
from pathlib import Path
from datetime import datetime, timezone

run_dir = Path(sys.argv[1])
invocation = json.loads(sys.argv[2])
cwd = sys.argv[3]
meta_path = run_dir / "meta.json"

def atomic_write_json(path, data):
    """Inline atomic write (tempfile + rename). The watcher cannot import
    _atomic_write_json() from devkit_cli since it runs as a standalone snippet."""
    import tempfile
    fd, tmp_path = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
    os.chmod(tmp_path, 0o600)
    os.rename(tmp_path, str(path))

# Open log files with restricted permissions (0o600)
stdout_fd = os.open(str(run_dir / "stdout.log"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
stderr_fd = os.open(str(run_dir / "stderr.log"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
stdout_log = os.fdopen(stdout_fd, "w")
stderr_log = os.fdopen(stderr_fd, "w")

# Spawn Claude as our child -- os.waitpid() works because we are its parent.
# env=os.environ.copy() forwards this watcher process's own environment
# (which the parent devkit_cli.py already populated with DEVKIT_PROJECT_DIR
# and DEVKIT_SCRIPTS via the env= kwarg used to spawn this watcher).
proc = subprocess.Popen(
    invocation, cwd=cwd, env=os.environ.copy(),
    stdout=stdout_log, stderr=stderr_log,
)
stdout_log.close()
stderr_log.close()

# Update meta.json with Claude PID (atomic)
with open(meta_path) as f:
    meta = json.load(f)
meta["pid"] = proc.pid
atomic_write_json(meta_path, meta)

# Wait for Claude -- we ARE its parent, so waitpid succeeds
try:
    _, status = os.waitpid(proc.pid, 0)
    exit_code = os.WEXITSTATUS(status) if os.WIFEXITED(status) else -1
except ChildProcessError:
    exit_code = -1

# Parse result from stdout
try:
    stdout_data = (run_dir / "stdout.log").read_text()
    data = json.loads(stdout_data)
    result_path = run_dir / "result.json"
    result_fd = os.open(str(result_path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(result_fd, "w") as f:
        json.dump(data, f, indent=2)
except Exception:
    pass

# Finalize meta.json (atomic)
meta["completed_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
meta["exit_code"] = exit_code
meta["status"] = "completed" if exit_code == 0 else "failed"
atomic_write_json(meta_path, meta)
'''
    subprocess.Popen(
        [sys.executable, "-c", watcher_script,
         str(runs_dir), json.dumps(invocation), cwd],
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=env,
    )


def _spawn_detached(skill, resolved, args_str, config, run_id):
    """Spawn a detached Claude Code session with output capture."""
    runs_dir = Path.home() / ".claude-devkit" / "runs" / run_id
    os.makedirs(runs_dir, mode=0o700)

    meta = {
        "schema_version": "1.0.0",
        "run_id": run_id,
        "skill": skill,
        "target": str(resolved),
        "project_name": resolved.name,
        "args": args_str[:1024],
        "pid": None,
        "status": "running",
        "started_at": utc_now_iso(),
        "completed_at": None,
        "exit_code": None,
        "devkit_version": VERSION,
    }
    _atomic_write_json(runs_dir / "meta.json", meta)
    try:
        os.chmod(runs_dir / "meta.json", 0o600)
    except OSError as e:
        print(
            f"{Colors.YELLOW}Warning:{Colors.RESET} Cannot set permissions on "
            f"meta.json: {e}",
            file=sys.stderr,
        )

    claude_cmd = config.get("claude_command", FALLBACK_DEFAULTS["claude_command"])
    print_flag = config.get("claude_print_flag", FALLBACK_DEFAULTS["claude_print_flag"])
    prompt = f"/{skill}" + (f" {args_str}" if args_str else "")
    invocation = [claude_cmd, print_flag, "--output-format", "json", prompt]

    env = os.environ.copy()
    env["CLAUDE_DEVKIT"] = str(get_devkit_root())
    # Propagate the same artifact/script locations a synchronous invocation
    # would get -- without this, detached runs fall through to tier-2/3
    # path resolution in skills and can recreate .devkit/ in the project
    # (see plan "Changes to Detached Execution").
    env["DEVKIT_PROJECT_DIR"] = str(get_project_dir(resolved))
    env["DEVKIT_SCRIPTS"] = str(get_scripts_dir(config))

    # Spawn watcher -- the watcher itself spawns Claude as its child,
    # so it can use os.waitpid() to obtain the real exit code.
    _spawn_watcher(runs_dir, invocation, str(resolved), env)

    return run_id


def cmd_init(target_str, config):
    ok, result = validate_target(target_str, config)
    if not ok:
        print(f"{Colors.RED}Error:{Colors.RESET} {result}", file=sys.stderr)
        return 1
    resolved = result

    try:
        project_id = compute_project_id(resolved)
    except ValueError as e:
        print(f"{Colors.RED}Error:{Colors.RESET} {e}", file=sys.stderr)
        return 1

    # Collision detection: an existing central directory for this ID that
    # belongs to a *different* resolved path indicates a genuine project ID
    # collision (see plan STRIDE Spoofing analysis). read_state() already
    # resolves the same project dir via get_project_dir(resolved), so this
    # naturally finds only state that lives at this exact ID.
    existing_state = read_state(resolved, config)
    if existing_state is not None:
        existing_path = existing_state.get("project_path")
        if existing_path and existing_path != str(resolved):
            print(
                f"{Colors.RED}Error:{Colors.RESET} project ID collision detected. "
                f"Existing project at {existing_path} has the same ID ({project_id}). "
                f"This should not happen; please report this as a bug.",
                file=sys.stderr,
            )
            return 1

    project_dir = get_project_dir(resolved)
    try:
        os.makedirs(project_dir, mode=0o700, exist_ok=True)
        os.chmod(project_dir, 0o700)
        plans_dir = project_dir / "plans"
        os.makedirs(plans_dir, mode=0o700, exist_ok=True)
        os.chmod(plans_dir, 0o700)
    except OSError as e:
        print(f"{Colors.RED}Error:{Colors.RESET} Cannot create {project_dir}: {e}", file=sys.stderr)
        return 1

    now = utc_now_iso()
    state = {
        "schema_version": STATE_SCHEMA_VERSION,
        "project_name": resolved.name,
        "project_id": project_id,
        "project_path": str(resolved),
        "initialized_at": (existing_state or {}).get("initialized_at", now),
        "devkit_version": VERSION,
    }
    ok, err = write_state(resolved, state, config)
    if not ok:
        print(f"{Colors.RED}Error:{Colors.RESET} {err}", file=sys.stderr)
        return 1

    update_registry(resolved, config, touch=True, register=True, project_id=project_id)

    print(f"{Colors.GREEN}Initialized devkit for '{resolved.name}'{Colors.RESET}")
    print(f"  Project path: {resolved}")
    print(f"  Artifact dir: {project_dir}")
    return 0


def cmd_run_skill(skill, target_str, validated_args, passthrough_args, config,
                   detach=False):
    """Run a skill non-interactively against `target_str`.

    `validated_args` are checked by validate_args() (pre-'--'-separator
    tokens); `passthrough_args` are forwarded verbatim (post-separator
    tokens, see split_skill_args()). Both are joined into a single prompt
    string below -- subprocess.run() is always list-form, so neither group
    can ever reach `claude` as a separate CLI flag regardless of prefix.

    When `detach` is True, spawns Claude in the background via
    _spawn_detached() and returns immediately with a run ID.
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

    if detach:
        run_id = _generate_run_id()
        _spawn_detached(skill, resolved, args_str, config, run_id)
        print(f"{Colors.GREEN}Detached:{Colors.RESET} {run_id}")
        print(f"  Check status: devkit jobs")
        print(f"  View result:  devkit result {run_id}")
        print(f"  View logs:    devkit logs {run_id}")
        return 0

    existing_state = read_state(resolved, config) or {}
    project_id = existing_state.get("project_id")
    if not project_id:
        try:
            project_id = compute_project_id(resolved)
        except ValueError:
            project_id = None
    base_state = {
        "schema_version": STATE_SCHEMA_VERSION,
        "project_name": resolved.name,
        "project_id": project_id,
        "project_path": str(resolved),
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
    update_registry(resolved, config, touch=True, register=True, project_id=project_id)

    env = os.environ.copy()
    env["CLAUDE_DEVKIT"] = str(get_devkit_root())
    env["DEVKIT_PROJECT_DIR"] = str(get_project_dir(resolved))
    env["DEVKIT_SCRIPTS"] = str(get_scripts_dir(config))

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
        update_registry(resolved, config, touch=True, register=True, project_id=project_id)

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
    try:
        project_id = existing_state.get("project_id") or compute_project_id(resolved)
    except ValueError:
        project_id = None
    state = {
        "schema_version": STATE_SCHEMA_VERSION,
        "project_name": resolved.name,
        "project_id": project_id,
        "project_path": str(resolved),
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
    update_registry(resolved, config, touch=True, register=True, project_id=project_id)

    claude_cmd = config.get("claude_command", FALLBACK_DEFAULTS["claude_command"])

    # Mutate os.environ (not a local copy) so os.execvp's replacement
    # process inherits CLAUDE_DEVKIT/DEVKIT_PROJECT_DIR/DEVKIT_SCRIPTS via
    # the real process environment.
    os.environ["CLAUDE_DEVKIT"] = str(get_devkit_root())
    os.environ["DEVKIT_PROJECT_DIR"] = str(get_project_dir(resolved))
    os.environ["DEVKIT_SCRIPTS"] = str(get_scripts_dir(config))

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
            try:
                project_dir = get_project_dir(resolved)
                print(f"Artifact directory: {project_dir}")
            except ValueError:
                pass
            print(f"Initialized: {state.get('initialized_at', 'unknown')}")
            print(f"Devkit version at init: {state.get('devkit_version', 'unknown')}")

            stored_path = state.get("project_path")
            if stored_path and stored_path != str(resolved):
                print(
                    f"{Colors.YELLOW}Warning:{Colors.RESET} project was previously at "
                    f"{stored_path}. Artifacts from the old location may still exist "
                    f"under ~/.claude-devkit/projects/<old-id>/. Use "
                    f"'devkit relink {stored_path} {resolved}' to migrate them."
                )

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

        try:
            audit_log_dir = get_project_dir(resolved) / "plans" / "audit-logs"
            log_count = len(list(audit_log_dir.glob("*.jsonl"))) if audit_log_dir.is_dir() else 0
        except ValueError:
            log_count = 0
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


def cmd_migrate(target_str, config):
    """Migrate legacy .devkit/ artifacts to ~/.claude-devkit/projects/<id>/.

    Non-destructive (copies, not moves) and rolls back the partially
    created central directory if any copy step fails.
    """
    ok, result = validate_target(target_str, config)
    if not ok:
        print(f"{Colors.RED}Error:{Colors.RESET} {result}", file=sys.stderr)
        return 1
    resolved = result

    try:
        project_id = compute_project_id(resolved)
    except ValueError as e:
        print(f"{Colors.RED}Error:{Colors.RESET} {e}", file=sys.stderr)
        return 1

    central_dir = get_project_dir(resolved)
    old_devkit = resolved / ".devkit"

    if not old_devkit.is_dir():
        print(f"No .devkit/ directory found in {resolved}. Nothing to migrate.")
        return 0

    if central_dir.exists():
        print(f"{Colors.RED}Error:{Colors.RESET} Central directory already exists at {central_dir}.", file=sys.stderr)
        print("Manual merge may be needed. Aborting.", file=sys.stderr)
        return 1

    try:
        os.makedirs(central_dir, mode=0o700)
        os.chmod(central_dir, 0o700)
    except OSError as e:
        print(f"{Colors.RED}Error:{Colors.RESET} Cannot create {central_dir}: {e}", file=sys.stderr)
        return 1

    try:
        old_state = old_devkit / "state.json"
        if old_state.exists():
            shutil.copy2(str(old_state), str(central_dir / "state.json"))
            os.chmod(central_dir / "state.json", 0o600)

        old_plans = old_devkit / "plans"
        if old_plans.is_dir():
            shutil.copytree(str(old_plans), str(central_dir / "plans"))
        else:
            os.makedirs(central_dir / "plans", mode=0o700, exist_ok=True)
            os.chmod(central_dir / "plans", 0o700)

        # Normalize the migrated state: ensure project_id/project_path are
        # correct for the *current* resolved path (read_state()'s schema
        # migration handles this if the copied file predates schema 1.1.0;
        # if no state.json existed at all, seed a minimal one).
        migrated_state = read_state(resolved, config)
        if migrated_state is None:
            migrated_state = {
                "schema_version": STATE_SCHEMA_VERSION,
                "project_name": resolved.name,
                "project_id": project_id,
                "project_path": str(resolved),
                "initialized_at": utc_now_iso(),
                "devkit_version": VERSION,
            }
            write_state(resolved, migrated_state, config)

        update_registry(resolved, config, touch=True, register=True, project_id=project_id)
    except (OSError, shutil.Error) as e:
        shutil.rmtree(str(central_dir), ignore_errors=True)
        print(f"{Colors.RED}Error:{Colors.RESET} during migration: {e}", file=sys.stderr)
        print("Rolled back. Central directory removed.", file=sys.stderr)
        return 1

    print(f"{Colors.GREEN}Migrated{Colors.RESET} {resolved} artifacts to {central_dir}")
    print("Verify migration, then remove old directory:")
    print(f"  rm -rf {old_devkit}")
    print("  # Also remove .devkit/ from .gitignore if present")
    return 0


def cmd_relink(old_path_str, new_path_str, config):
    """Recover centralized artifacts after a project directory rename/move.

    Renames ~/.claude-devkit/projects/<old-id>/ to <new-id>/ and updates
    state.json + the registry entry accordingly. The old path need not
    still exist on disk (that is the whole point -- it usually doesn't).
    """
    if not old_path_str or not new_path_str:
        print(f"{Colors.RED}Error:{Colors.RESET} devkit relink requires <old-path> <new-path>", file=sys.stderr)
        return 2

    try:
        old_resolved = Path(old_path_str).expanduser().resolve(strict=False)
    except OSError as e:
        print(f"{Colors.RED}Error:{Colors.RESET} Cannot resolve old path {old_path_str}: {e}", file=sys.stderr)
        return 1

    ok, new_resolved = validate_target(new_path_str, config)
    if not ok:
        print(f"{Colors.RED}Error:{Colors.RESET} {new_resolved}", file=sys.stderr)
        return 1

    try:
        old_id = compute_project_id(old_resolved)
        new_id = compute_project_id(new_resolved)
    except ValueError as e:
        print(f"{Colors.RED}Error:{Colors.RESET} {e}", file=sys.stderr)
        return 1

    if old_id == new_id:
        print("Old and new paths resolve to the same project ID; nothing to relink.")
        return 0

    old_dir = Path.home() / ".claude-devkit" / "projects" / old_id
    new_dir = Path.home() / ".claude-devkit" / "projects" / new_id

    if not old_dir.is_dir():
        print(
            f"{Colors.RED}Error:{Colors.RESET} No central project directory found for "
            f"old path (expected {old_dir}).",
            file=sys.stderr,
        )
        return 1
    if new_dir.exists():
        print(
            f"{Colors.RED}Error:{Colors.RESET} Central project directory already exists "
            f"at {new_dir}. Aborting to avoid overwrite.",
            file=sys.stderr,
        )
        return 1

    try:
        os.rename(str(old_dir), str(new_dir))
    except OSError as e:
        print(f"{Colors.RED}Error:{Colors.RESET} Cannot rename {old_dir} to {new_dir}: {e}", file=sys.stderr)
        return 1

    state = read_state(new_resolved, config) or {}
    state["schema_version"] = STATE_SCHEMA_VERSION
    state["project_id"] = new_id
    state["project_path"] = str(new_resolved)
    state.setdefault("project_name", new_resolved.name)
    state.setdefault("initialized_at", utc_now_iso())
    state.setdefault("devkit_version", VERSION)
    write_state(new_resolved, state, config)

    registry = read_registry(config)
    projects = [p for p in registry.get("projects", []) if p.get("path") != str(old_resolved)]
    registry["projects"] = projects
    registry["updated_at"] = utc_now_iso()
    write_registry(registry, config)
    update_registry(new_resolved, config, touch=True, register=True, project_id=new_id)

    print(f"{Colors.GREEN}Relinked:{Colors.RESET} {old_resolved} -> {new_resolved}")
    print(f"  Central directory: {old_dir} -> {new_dir}")
    return 0


def cmd_path(target_str, config, subpath=None):
    """Print the central artifact directory path for a project."""
    ok, result = validate_target(target_str, config)
    if not ok:
        print(f"{Colors.RED}Error:{Colors.RESET} {result}", file=sys.stderr)
        return 1
    resolved = result

    try:
        project_dir = get_project_dir(resolved)
    except ValueError as e:
        print(f"{Colors.RED}Error:{Colors.RESET} {e}", file=sys.stderr)
        return 1

    if subpath:
        print(str(project_dir / subpath))
    else:
        print(str(project_dir))
    return 0


def cmd_jobs(target_str, config):
    """List all runs, optionally filtered by target project."""
    runs_dir = Path.home() / ".claude-devkit" / "runs"
    if not runs_dir.is_dir():
        print("No runs found.")
        return 0

    runs = []
    for run_dir in sorted(runs_dir.iterdir(), reverse=True):
        meta_path = run_dir / "meta.json"
        if not meta_path.exists():
            continue
        try:
            meta = json.loads(meta_path.read_text())
        except (OSError, json.JSONDecodeError):
            continue

        # Check liveness for "running" status
        if meta.get("status") == "running":
            pid = meta.get("pid")
            if pid and not _is_pid_alive(pid):
                meta["status"] = "stale"

        if target_str:
            ok, resolved = validate_target(target_str, config)
            if ok and meta.get("target") != str(resolved):
                continue

        runs.append(meta)

    if not runs:
        print("No runs found.")
        return 0

    print(f"{'RUN ID':<28} {'SKILL':<12} {'PROJECT':<20} {'STATUS':<10} {'STARTED'}")
    for meta in runs[:20]:
        print(
            f"{meta['run_id']:<28} "
            f"{meta.get('skill','?'):<12} "
            f"{meta.get('project_name','?'):<20} "
            f"{_status_color(meta.get('status','?')):<10} "
            f"{meta.get('started_at','?')}"
        )
    return 0


def cmd_result(run_id, config):
    """Print the result of a completed run."""
    ok, err = _validate_run_id(run_id)
    if not ok:
        print(err)
        return 1
    run_dir = Path.home() / ".claude-devkit" / "runs" / run_id
    result_path = run_dir / "result.json"
    if result_path.exists():
        try:
            data = json.loads(result_path.read_text())
            print(data.get("result", "(no result text)"))
        except (OSError, json.JSONDecodeError):
            print(f"Cannot parse result for run {run_id}")
            return 1
    elif (run_dir / "stdout.log").exists():
        print((run_dir / "stdout.log").read_text())
    else:
        print(f"No result found for run {run_id}")
        return 1
    return 0


def cmd_logs(run_id, config):
    """Print stderr logs of a run."""
    ok, err = _validate_run_id(run_id)
    if not ok:
        print(err)
        return 1
    log_path = Path.home() / ".claude-devkit" / "runs" / run_id / "stderr.log"
    if not log_path.exists():
        print(f"No logs found for run {run_id}")
        return 1
    print(log_path.read_text())
    return 0


def cmd_clean(max_age_days, config):
    """Remove completed/failed runs older than max_age_days."""
    if max_age_days is None:
        max_age_days = config.get("clean_retention_days",
                                  FALLBACK_DEFAULTS.get("clean_retention_days", 7))
    if max_age_days < 0:
        print(f"{Colors.RED}Error:{Colors.RESET} --days must be non-negative", file=sys.stderr)
        return 2
    runs_dir = Path.home() / ".claude-devkit" / "runs"
    if not runs_dir.is_dir():
        print("Cleaned 0 run(s)")
        return 0
    cutoff = time.time() - (max_age_days * 86400)
    removed = 0
    for run_dir in list(runs_dir.iterdir()):
        ok, _ = _validate_run_id(run_dir.name)
        if not ok:
            continue
        meta_path = run_dir / "meta.json"
        if not meta_path.exists():
            shutil.rmtree(run_dir, ignore_errors=True)
            removed += 1
            continue
        try:
            meta = json.loads(meta_path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        status = meta.get("status")
        # Check PID liveness for runs still marked "running"
        # (handles case where watcher died before finalizing)
        if status == "running":
            pid = meta.get("pid")
            if pid and not _is_pid_alive(pid):
                status = "stale"
        if status in ("completed", "failed", "stale"):
            try:
                mtime = meta_path.stat().st_mtime
            except OSError:
                continue
            if mtime < cutoff:
                shutil.rmtree(run_dir, ignore_errors=True)
                removed += 1
    print(f"Cleaned {removed} run(s)")
    return 0


# --- Argument parsing / entry point ----------------------------------------

def print_help():
    print(f"""devkit {VERSION} -- Meta-harness CLI for claude-devkit

Usage:
  devkit init <target>                     Initialize project for devkit management
  devkit <skill> <target> [args...]        Run a skill non-interactively in target
  devkit <skill> <target> --detach         Run skill in background, return run ID
  devkit shell <target>                    Open interactive Claude session in target
  devkit status [<target>]                 Show status of one or all projects
  devkit migrate <target>                  Migrate legacy .devkit/ artifacts to central storage
  devkit relink <old-path> <new-path>      Recover artifacts after a project rename/move
  devkit path <target> [subpath]           Print the central artifact directory path
  devkit jobs [<target>]                   List background runs (all or filtered)
  devkit result <run-id>                   Print result of a completed run
  devkit logs <run-id>                     Print stderr logs of a run
  devkit clean [--days N]                  Remove old runs (default: 7 days)
  devkit deploy [--validate]               Ensure skills are deployed
  devkit --version                         Show version
  devkit --help                            Show help

Examples:
  devkit init ~/projects/my-app
  devkit audit ~/projects/my-app
  devkit architect ~/projects/my-app "add user authentication"
  devkit architect ~/projects/my-app "add feature" --detach
  devkit path ~/projects/my-app
  devkit ship ~/projects/my-app "$(devkit path ~/projects/my-app plans/add-user-auth.md)"
  devkit jobs
  devkit result 20260821-143052-a1b2c3
  devkit logs 20260821-143052-a1b2c3
  devkit clean --days 14
  devkit shell ~/projects/my-app
  devkit status
  devkit status ~/projects/my-app
  devkit migrate ~/projects/my-app
  devkit relink ~/projects/old-name ~/projects/new-name

Notes:
  All artifacts (state, plans, audit logs, archives) live under
  ~/.claude-devkit/projects/<project-id>/ -- devkit never writes into the
  target project directory itself (see 'devkit path' and 'devkit status').

  --detach spawns the skill in the background and returns a run ID immediately.
  Use 'devkit jobs' to check status, 'devkit result <id>' to see the output.

  Skill arguments starting with '--' are rejected unless they come after a
  '--' separator, which forwards everything following it verbatim (standard
  '--' semantics, as in `git` or `npm run --`). Use this to pass skill flags
  like `--fast`:
    devkit architect ~/foo -- --fast
    devkit architect ~/foo --detach -- --fast

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

    if command == "migrate":
        if not rest:
            print(f"{Colors.RED}Error:{Colors.RESET} devkit migrate requires a target path", file=sys.stderr)
            return 2
        return cmd_migrate(rest[0], config)

    if command == "relink":
        if len(rest) < 2:
            print(f"{Colors.RED}Error:{Colors.RESET} devkit relink requires <old-path> <new-path>", file=sys.stderr)
            return 2
        return cmd_relink(rest[0], rest[1], config)

    if command == "path":
        if not rest:
            print(f"{Colors.RED}Error:{Colors.RESET} devkit path requires a target path", file=sys.stderr)
            return 2
        subpath = rest[1] if len(rest) > 1 else None
        return cmd_path(rest[0], config, subpath)

    if command == "deploy":
        return cmd_deploy(rest, config)

    if command == "jobs":
        target = rest[0] if rest else None
        return cmd_jobs(target, config)

    if command == "result":
        if not rest:
            print(f"{Colors.RED}Error:{Colors.RESET} devkit result requires a run ID", file=sys.stderr)
            return 2
        return cmd_result(rest[0], config)

    if command == "logs":
        if not rest:
            print(f"{Colors.RED}Error:{Colors.RESET} devkit logs requires a run ID", file=sys.stderr)
            return 2
        return cmd_logs(rest[0], config)

    if command == "clean":
        max_age_days = None
        if "--days" in rest:
            idx = rest.index("--days")
            if idx + 1 < len(rest):
                try:
                    max_age_days = int(rest[idx + 1])
                except ValueError:
                    print(f"{Colors.RED}Error:{Colors.RESET} --days requires an integer value", file=sys.stderr)
                    return 2
            else:
                print(f"{Colors.RED}Error:{Colors.RESET} --days requires a value", file=sys.stderr)
                return 2
        return cmd_clean(max_age_days, config)

    # Dynamic skill dispatch.
    skill = command
    if not rest:
        print(f"{Colors.RED}Error:{Colors.RESET} devkit {skill} requires a target path", file=sys.stderr)
        return 2
    target = rest[0]
    skill_args = rest[1:]

    # Extract --detach before the split/validate pipeline
    detach = "--detach" in skill_args
    if detach:
        skill_args = [a for a in skill_args if a != "--detach"]

    # "--" separates devkit-parsed tokens (subject to validate_args()'s
    # '--'-prefix rejection) from skill arguments forwarded verbatim after
    # it -- see split_skill_args() and validate_args() docstrings.
    pre_sep_args, post_sep_args = split_skill_args(skill_args)

    return cmd_run_skill(skill, target, pre_sep_args, post_sep_args, config,
                         detach=detach)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Interrupted.{Colors.RESET}", file=sys.stderr)
        sys.exit(130)
