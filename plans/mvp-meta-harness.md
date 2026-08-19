# MVP Meta-Harness for Claude Devkit

## Revision Log

| Rev | Date | Findings Addressed | Summary |
|-----|------|--------------------|---------|
| R1 | 2026-08-19 | RT-1,RT-2,RT-7; LR-1,LR-2,LR-3,LR-4; FR-M1,FR-M2,FR-M3 | Narrow allowed_roots to ~/projects/ + ~/workspaces/ (RT-1, LR-1, FR-m4). Move CLI from generators/ to scripts/ (LR-2). Add skill name regex and arg injection guard (RT-2). Add 5 security tests, total 13 new tests (RT-7, FR-M2). Document --print permission prompt limitation with pre-flight warning (FR-M1). Document shell state limitation (FR-M3, RT-4). Harmonize state.json to 0600 (LR-3, RT-9). Promote --print verification to Rollout step 1 (LR-4). Add TB-5 for devkit-defaults.json (RT Security-Analyst). Add hardcoded fallback defaults (RT missing failure mode). Adjust time estimate to 8-10 hours. |

**Type:** CLI + Configuration
**Archetype:** N/A (infrastructure, not a skill)
**Complexity:** Medium
**Estimated Time:** 8-10 hours

## Summary

Evolve claude-devkit from a skills-based toolkit that runs inside projects to an
external orchestrator that can target and manage workflows across multiple
repositories. The meta-harness is a thin CLI layer that validates targets, sets
CWD, manages lightweight state, and delegates to Claude Code for actual skill
execution. No workflow engine, no DAG definitions, no new abstraction layers.

**Core insight:** Every existing skill (architect, ship, audit, sync, etc.)
already works by assuming CWD is the target project. The meta-harness just needs
to set CWD correctly and ensure the environment is configured. Skills remain
SKILL.md files -- the harness is a front door, not a rebuild.

## Context Alignment

### CLAUDE.md Patterns Followed

- **Python generator patterns:** stdlib only, argparse, atomic writes via
  tempfile, `(bool, error_msg)` validation tuples, exit codes 0/1/2
- **Path validation:** Restricts to validated git repositories, rejects symlinks
  and path traversal. Default allowed_roots narrowed to `["~/projects/",
  "~/workspaces/"]` with devkit root and `/tmp/` always allowed, matching the
  existing `validate_target_dir()` patterns in `generate_agents.py` and
  `generate_skill.py`.
- **State-on-disk pattern:** JSON state files following the
  `emit-audit-event.sh` per-run state model (shell variables do not persist
  across Bash tool calls)
- **Install integration:** Follows install.sh pattern of appending to RC files
  with marker comments and backup
- **Test integration:** Follows test-integration.sh `run_test()` harness pattern
- **Script placement:** CLI placed in `scripts/devkit_cli.py` following the
  `codebase-scanner.py` precedent -- utility/orchestration scripts live in
  `scripts/`, code generation scripts live in `generators/`.

### Prior Plans This Builds Upon

- **codebase-symbol-index.md** -- Established the `$CLAUDE_DEVKIT` environment
  variable pattern for cross-project tool invocation (scanner script located via
  `${CLAUDE_DEVKIT:-./}/scripts/codebase-scanner.py`)
- **agentic-sdlc-security-skills.md** -- Established the security maturity model
  (L1/L2/L3) and per-project `.claude/settings.json` configuration pattern that
  the meta-harness reads and respects
- **scanner-instrumentation.md** -- Established the `compute-run-score.sh` and
  `score-reflector.sh` cross-run analysis pattern that the meta-harness `status`
  command could surface

### Deviations From Established Patterns

1. **New dotfile directory (`.devkit/`) in target projects.** Existing devkit
   state lives in `.claude/` or `plans/`. The `.devkit/` directory is chosen to
   avoid collision with Claude Code's own `.claude/` namespace and to clearly
   signal "this project is managed by devkit." The directory is gitignored by
   default.

2. **Global registry file (`~/.claude-devkit/registry.json`).** Existing devkit
   state is per-project. The registry is the minimum viable piece needed for
   fleet awareness ("which projects am I managing?"). It is informational only
   -- never authoritative. Every access re-validates against the filesystem.

## Goals

1. **External targeting:** Run any deployed skill against any git repository from
   any working directory, without `cd`-ing into the target first.
2. **Project initialization:** One command to prepare a repository for devkit
   management (validate, register, set up state).
3. **Cross-project visibility:** Show which projects are managed and their last
   invocation status.
4. **Environment integrity:** Guarantee that `CLAUDE_DEVKIT`, skill deployment,
   and target-project state are correct before invoking Claude Code.
5. **Security continuity:** Preserve the existing security maturity model,
   audit logging, and security gates without modification.

## Non-Goals

1. **Workflow engine replacement.** Skills remain prose SKILL.md files executed by
   Claude Code. No DAGs, typed nodes, or graph engines.
2. **Fleet operations.** Batch operations across multiple repos (e.g., "audit all
   registered projects") are out of scope. The registry enables this later.
3. **Continuous operation.** Looping, tmux integration, checkpoint/resume, and
   dashboard are out of scope.
4. **Runner abstraction.** The harness targets Claude Code only. No Codex, no
   OpenCode, no pluggable backends.
5. **Per-project skill deployment.** Skills remain globally deployed to
   `~/.claude/skills/`. Per-project skill overrides are not in scope.
6. **Agent generation.** The existing `gen-agent` / `gen-agents` commands already
   handle this. The harness does not replace them.

## Assumptions

1. Claude Code CLI is installed and on PATH as `claude`.
2. Claude Code supports a `-p` (or `--print`) flag for non-interactive prompt
   execution. If this flag does not exist or has different semantics, the
   `_invoke_claude()` function is the single point to update. **This is the
   highest-risk assumption and is verified first in the Rollout Plan.**
3. Python 3.8+ is available (same requirement as existing generators).
4. `~/.claude-devkit/` directory already exists (created by `install.sh` for the
   scanner venv). The harness reuses this namespace for the registry.
5. Target repositories use git. Non-git directories are rejected.
6. Skills are already deployed via `deploy.sh`. The harness checks but does not
   auto-deploy (explicit is better than implicit).
7. Non-interactive skill execution (`--print` mode) requires adequate tool
   permission allowlists in `~/.claude/settings.json`. Without allowlists,
   permission prompts will block execution. See Pre-Flight Checks.

## Proposed Design

### Architecture

```
User
  |
  v
devkit CLI  (scripts/devkit_cli.py)
  |
  +-- validate target path (is git repo? exists? no symlinks?)
  +-- validate skill name (regex: ^[a-z][a-z0-9-]*$)
  +-- validate args (reject --prefixed args to prevent CLI flag injection)
  +-- read/create .devkit/state.json in target project
  +-- update ~/.claude-devkit/registry.json
  +-- check skill deployment (~/.claude/skills/<skill>/SKILL.md exists?)
  +-- set CLAUDE_DEVKIT env var
  +-- warn if no tool permission allowlists configured
  |
  v
subprocess.run(["claude", "--print", "/<skill> <args>"], cwd=<target>)
  |
  v
Claude Code (existing behavior -- reads CWD, runs skill, writes artifacts)
  |
  v
devkit CLI  (post-execution)
  +-- update state.json with outcome
  +-- update registry with last-touched timestamp
```

### Command Interface

```
devkit init <target>                     Initialize project for devkit management
devkit <skill> <target> [args...]        Run a skill non-interactively in target
devkit shell <target>                    Open interactive Claude session in target
devkit status [<target>]                 Show status of one or all projects
devkit deploy [--validate]               Ensure skills are deployed (delegates to deploy.sh)
devkit --version                         Show version
devkit --help                            Show help
```

**Examples:**

```bash
# Initialize a project
devkit init ~/projects/my-app

# Run audit in a project (from anywhere)
devkit audit ~/projects/my-app

# Plan a feature
devkit architect ~/projects/my-app "add user authentication"

# Implement a plan
devkit ship ~/projects/my-app plans/add-user-auth.md

# Start interactive session
devkit shell ~/projects/my-app

# Check fleet status
devkit status

# Check one project
devkit status ~/projects/my-app
```

### State Model

#### Per-Project State (`.devkit/state.json`)

Created by `devkit init`. Minimal metadata about devkit's relationship to this
project. Gitignored by default.

```json
{
  "schema_version": "1.0.0",
  "project_name": "my-app",
  "initialized_at": "2026-08-19T18:00:00Z",
  "devkit_version": "0.1.0",
  "last_invocation": {
    "skill": "audit",
    "args": "",
    "timestamp": "2026-08-19T18:30:00Z",
    "exit_code": 0
  }
}
```

**Design decisions:**
- Security maturity is NOT duplicated here. It already lives in
  `.claude/settings.json` or `.claude/settings.local.json` and is read by skills
  at runtime. The harness reads it for display in `status` but does not write it.
- Audit logs are NOT moved here. They remain in `plans/audit-logs/` where
  existing query tools expect them.
- The state file is informational. No skill reads it. It exists solely for the
  harness's pre-flight and status commands.
- File permissions: 0600 (owner-only read/write), consistent with registry.json.
  Both files contain the same class of data (project paths, timestamps, skill
  invocation metadata).

**Known limitation:** The `shell` command uses `os.execvp()`, which replaces the
harness process. `last_invocation` is not updated after an interactive session
ends because the harness never regains control. Users running `devkit status`
will see a stale `last_touched` timestamp for projects primarily accessed via
`shell`. The pre-invocation timestamp is written before `execvp` so the registry
records that the project was accessed, but exit_code is recorded as `null`.

**Schema migration policy:** If `schema_version` does not match the expected
version, warn to stderr and proceed with best-effort parsing (same pattern as
existing audit event schema).

#### Global Registry (`~/.claude-devkit/registry.json`)

A flat list of known projects. Updated on every `init` and `run` invocation.
Never authoritative -- paths are re-validated on access.

```json
{
  "schema_version": "1.0.0",
  "updated_at": "2026-08-19T18:30:00Z",
  "projects": [
    {
      "path": "/Users/imurphy/projects/my-app",
      "name": "my-app",
      "registered_at": "2026-08-19T18:00:00Z",
      "last_touched": "2026-08-19T18:30:00Z"
    }
  ]
}
```

**Design decisions:**
- No security maturity stored in registry. Reading it requires accessing each
  project's `.claude/settings.json`, which `status` does on demand.
- Stale entries (deleted projects) are detected by path validation and reported
  with a `[STALE]` marker in `status` output. Not auto-pruned (user might have
  unmounted a volume).
- File permissions: 0600 (user-only read/write). The `~/.claude-devkit/`
  directory is already 0700 (set by `install.sh`).
- **Concurrent access:** No file locking is implemented. `tempfile + os.replace()`
  prevents partial writes but not lost updates. If two `devkit` commands run
  simultaneously, the second writer overwrites the first writer's `last_touched`
  update. Accepted as a known limitation given the informational nature of the
  registry.

### Invocation Model

The harness delegates to Claude Code for all skill execution. Two modes:

**Non-interactive (`devkit <skill> <target> [args]`):**
```python
result = subprocess.run(
    ["claude", "--print", f"/{skill} {' '.join(args)}"],
    cwd=str(resolved_target_path),  # Always use resolved absolute path
    env=env,
)
```

Note: The resolved path (from `Path.resolve()`) is always passed to
`subprocess.run(cwd=...)`, not the user-provided string. This closes the TOCTOU
gap between validation and invocation.

**Interactive (`devkit shell <target>`):**
```python
# Update state/registry before execvp (harness loses control after)
update_state_pre_shell(resolved_target_path)
update_registry(resolved_target_path, touch=True)

os.chdir(str(resolved_target_path))
os.execvp("claude", ["claude"])
```

The `shell` command replaces the devkit process with Claude Code (via `execvp`),
so the user gets a normal interactive session. State is updated before `execvp`
with `exit_code: null` to indicate an interactive session. The exit code is never
captured because the process is replaced. This is a known limitation.

### Pre-Flight Checks

Every `devkit <skill>` invocation runs these checks before spawning Claude Code:

1. **Target validation:** Path exists, is a directory, is a git repository, is
   not a symlink. The resolved absolute path must be under one of the configured
   `allowed_roots` or the devkit root or `/tmp/`.
2. **Claude Code availability:** `claude` command is on PATH.
3. **Skill deployment check:** `~/.claude/skills/<skill>/SKILL.md` exists.
4. **CLAUDE_DEVKIT set:** Environment variable points to a valid devkit
   installation (has `skills/` directory).
5. **Project initialized:** `.devkit/state.json` exists. If not, warn and
   suggest `devkit init <target>`. (Warning, not hard block -- skills work
   without it.)
6. **Permission allowlist check:** Read `~/.claude/settings.json` and check for
   `allowedTools` configuration. If empty or missing, emit warning:
   "No tool permissions configured. Non-interactive skill execution may stall on
   permission prompts. See CLAUDE.md Tool Permissions section." (Warning, not
   hard block -- the user's allowlists may be in a project-level settings file.)

Any failure in checks 1-3 is fatal (exit 1). Checks 4-6 produce warnings.

### Input Validation

**Skill name validation:** Skill names must match `^[a-z][a-z0-9-]*$`. This
prevents:
- Path traversal attempts (`../../etc/passwd`)
- Names starting with dashes that could be parsed as flags
- Unicode or special characters that could cause filesystem issues

**Argument sanitization:** Arguments passed after the target path are forwarded
as part of the `--print` prompt string. To prevent Claude CLI flag injection:
- Any argument starting with `--` is rejected with an error message suggesting
  the `--` separator syntax: `devkit architect ~/foo -- --fast`.
- This is validated before the prompt string is constructed.

The `--` separator is treated as a delimiter: arguments before `--` are parsed by
devkit; arguments after `--` are forwarded verbatim as skill arguments (but still
cannot start with `--` as they become part of the prompt string, not CLI flags).

## Interfaces / Schema Changes

### New Files

| File | Purpose |
|------|---------|
| `scripts/devkit_cli.py` | Main CLI implementation (Python 3.8+, stdlib only) |
| `scripts/devkit` | Bash entry point wrapper (thin -- calls Python script) |
| `configs/devkit-defaults.json` | Default configuration (allowed roots, registry path) |

### Modified Files

| File | Change |
|------|--------|
| `scripts/install.sh` | Add `devkit` alias and `scripts/` to PATH |
| `scripts/test-integration.sh` | Add meta-harness integration tests |
| `CLAUDE.md` | Document meta-harness in Overview, Quick Start, Directory Reference |

### Schema: `configs/devkit-defaults.json`

```json
{
  "schema_version": "1.0.0",
  "registry_path": "~/.claude-devkit/registry.json",
  "state_dir_name": ".devkit",
  "state_file_name": "state.json",
  "allowed_roots": ["~/projects/", "~/workspaces/"],
  "gitignore_state_dir": true,
  "claude_command": "claude",
  "claude_print_flag": "--print",
  "max_state_file_bytes": 65536,
  "max_registry_file_bytes": 1048576
}
```

The `allowed_roots` field restricts which directories the harness will accept as
targets. Default is `["~/projects/", "~/workspaces/"]`, matching the existing
generator validation patterns. Additionally, the devkit root (`$CLAUDE_DEVKIT`)
and `/tmp/` are always allowed regardless of this setting (hardcoded in
`validate_target()`, matching `generate_agents.py` behavior). Values are
expanded with `Path.expanduser()`.

Users who need broader access can edit `configs/devkit-defaults.json` to add
additional roots. Setting `["~/"]` restores the broad behavior, but this is
not the default.

**Hardcoded fallback defaults:** If `configs/devkit-defaults.json` is missing or
corrupt, the CLI uses hardcoded fallback values identical to the schema above.
This prevents a deleted or corrupted config file from breaking all devkit
invocations. The fallback is logged as a warning to stderr.

### Schema: `.devkit/state.json` (in target projects)

See State Model section above. Fields:

| Field | Type | Required | Max Length | Description |
|-------|------|----------|------------|-------------|
| `schema_version` | string | yes | 20 | Schema version (semver) |
| `project_name` | string | yes | 255 | Directory basename |
| `initialized_at` | string | yes | 30 | ISO 8601 timestamp |
| `devkit_version` | string | yes | 20 | CLI version at init time |
| `last_invocation` | object | no | -- | Last skill invocation details |
| `last_invocation.skill` | string | yes | 64 | Skill name |
| `last_invocation.args` | string | yes | 1024 | Arguments passed |
| `last_invocation.timestamp` | string | yes | 30 | ISO 8601 timestamp |
| `last_invocation.exit_code` | integer or null | yes | -- | Process exit code (null for shell sessions) |

### Schema: `~/.claude-devkit/registry.json`

See State Model section above. Fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schema_version` | string | yes | Schema version (semver) |
| `updated_at` | string | yes | ISO 8601 timestamp of last update |
| `projects` | array | yes | List of project entries |
| `projects[].path` | string | yes | Absolute path to project root |
| `projects[].name` | string | yes | Directory basename |
| `projects[].registered_at` | string | yes | ISO 8601 when first registered |
| `projects[].last_touched` | string | yes | ISO 8601 of last devkit invocation |

## Security Requirements

### Assets

| Asset | Classification | Integrity | Availability | Notes |
|-------|---------------|-----------|-------------- |-------|
| Source code in target repos | Confidential-Restricted | High | Medium | The harness executes Claude Code in these directories |
| Project metadata (state.json) | Internal | Medium | Low | Informational only, no authorization decisions |
| Registry (registry.json) | Internal | Medium | Low | Contains local filesystem paths |
| Audit logs (plans/audit-logs/) | Internal | High (L2/L3) | Medium | Existing asset, harness does not modify |
| CLAUDE_DEVKIT path | Internal | Medium | Medium | Points to devkit installation |
| Claude Code session context | Confidential | High | High | Harness spawns Claude Code with full access to target repo |
| devkit-defaults.json | Internal | High | Medium | Controls allowed_roots, claude_command, and claude_print_flag. Integrity depends on git history and code review of the devkit repo. |

### Trust Boundaries

```
                    TB-1                          TB-2
User input -----> [CLI arg parser] -----> [Target path resolver] -----> [Filesystem]
  (untrusted)        (validated)              (validated)                (trusted)

                    TB-3
devkit CLI -----> [subprocess.run] -----> Claude Code
  (trusted)          (process boundary)     (trusted, CWD-scoped)

                    TB-4
.devkit/state.json <----> devkit CLI
  (semi-trusted)          (validates on read)

                    TB-5
configs/devkit-defaults.json -----> devkit CLI
  (trusted, same repo)               (loads at startup)
```

- **TB-1 (CLI argument boundary):** User-provided arguments (target path, skill
  name, args) are untrusted input. All inputs are validated before use. Skill
  names are validated against `^[a-z][a-z0-9-]*$`. Arguments starting with `--`
  are rejected to prevent Claude CLI flag injection.
  - **Authentication:** N/A (local CLI, runs as current user)
  - **Authorization:** Filesystem permissions (user can only target directories
    they own)

- **TB-2 (Path resolution boundary):** The target path crosses from string to
  filesystem access. Path traversal, symlinks, and non-git directories are
  rejected here. Resolved absolute paths are used for all subsequent operations.
  - **Authentication:** N/A
  - **Authorization:** Path must resolve under `allowed_roots` (default:
    `~/projects/`, `~/workspaces/`, plus always-allowed devkit root and `/tmp/`)
    and be a git repo

- **TB-3 (Process boundary):** devkit spawns Claude Code as a subprocess with
  CWD set to the target. Claude Code has full access to the target repo (same as
  if the user had `cd`-ed manually).
  - **Authentication:** N/A (same user, same permissions)
  - **Authorization:** Claude Code applies its own permission model

- **TB-4 (State file boundary):** `.devkit/state.json` is read from target
  projects that may have been cloned from untrusted sources. A malicious repo
  could include a crafted state file.
  - **Mitigation:** State is parsed with `json.loads()`, all fields are validated
    for type and max length (see schema table above), and no field is used in
    shell commands or path construction. State is informational only.

- **TB-5 (Configuration file boundary):** `configs/devkit-defaults.json` is
  loaded from the devkit repository at startup. It controls security-critical
  settings including `allowed_roots` and `claude_command`. This file is trusted
  at the same level as any other code in the devkit repo -- integrity depends on
  git history and code review. If the file is missing or corrupt, hardcoded
  fallback defaults are used.

### STRIDE Analysis

| Threat | Category | Vector | Mitigation | Residual Risk |
|--------|----------|--------|-----------|---------------|
| Attacker crafts malicious target path | **Spoofing** | CLI argument with `../`, symlinks, or absolute paths to sensitive directories | Resolve to absolute, reject symlinks, validate git repo, check against `allowed_roots` (default: ~/projects/, ~/workspaces/) | Low -- filesystem permissions still apply |
| Malicious `.devkit/state.json` in cloned repo | **Tampering** | State file contains unexpected values (huge strings, nested objects, script injection) | Validate all fields for type and max length on read. Never use state values in shell commands. Size limit on file read (64 KB). | Low -- state is informational only |
| User denies running a skill on a project | **Repudiation** | No record of invocation | Existing JSONL audit logs capture skill invocations inside Claude Code. Harness also updates state.json and registry with timestamps. | Low |
| Registry leaks project paths | **Info Disclosure** | Registry file readable by other users | File permissions 0600. Parent directory 0700 (already set by install.sh). | Low -- local filesystem, single user |
| Huge state/registry files cause OOM | **DoS** | Attacker places multi-GB state.json in a cloned repo | Size limit on file reads: state.json max 64 KB, registry.json max 1 MB. Reject and warn on oversize. | Low |
| Path traversal escalates to code execution in unintended directory | **Elevation of Privilege** | Target path resolves to system directory or another user's home | `allowed_roots` validation (default: ~/projects/, ~/workspaces/). Only directories under allowed roots accepted. Git repo validation adds a second gate. | Low -- defense in depth with two independent checks |
| Skill name or args inject Claude CLI flags | **Tampering** | User passes `--system-prompt` or similar as args | Skill name validated with `^[a-z][a-z0-9-]*$`. Args starting with `--` are rejected. Subprocess uses list form (no shell=True). | Low |

### Security Controls

- **Input Validation:** All CLI arguments validated before use. Skill names
  validated with `^[a-z][a-z0-9-]*$` regex. Arguments starting with `--`
  rejected to prevent Claude CLI flag injection. Target paths resolved and
  validated against `allowed_roots`.
- **No shell interpolation:** Subprocess invocation uses list form
  (`["claude", "--print", "..."]`), never `shell=True`. No string formatting of
  user input into shell commands.
- **File permissions:** Registry 0600, state.json 0600, parent directory 0700.
  Both data files use owner-only read/write for consistency.
- **Atomic writes:** State and registry files use tempfile + `os.replace()`
  pattern (same as existing generators).
- **Size limits:** 64 KB for state.json reads, 1 MB for registry.json reads.
- **Field length limits:** project_name max 255 chars, skill max 64 chars,
  schema_version max 20 chars, timestamps max 30 chars, args max 1024 chars.
- **Configuration fallback:** If `configs/devkit-defaults.json` is missing or
  corrupt, hardcoded fallback defaults are used. This prevents a corrupted
  config from breaking the tool or widening security boundaries.
- **Existing security model preserved:** Maturity levels (L1/L2/L3), security
  gates (secrets-scan, secure-review, dependency-audit), and JSONL audit logging
  all function unchanged because they are implemented in skills, not in the
  harness.

### Failure Modes

- **If target validation fails:** Exit 1 with descriptive error. No subprocess
  spawned.
- **If Claude Code not found:** Exit 1 with "claude command not found" message
  and installation link.
- **If skill not deployed:** Exit 1 with specific skill name and
  `devkit deploy` suggestion.
- **If state.json is corrupt/oversize:** Warn to stderr, continue without state.
  Skills work without it.
- **If registry.json is corrupt/oversize:** Warn to stderr, recreate empty
  registry. Previous entries are lost (rebuild by running `devkit init` on each
  project).
- **If subprocess fails:** Propagate Claude Code's exit code. Update state with
  the failed exit code.
- **If configs/devkit-defaults.json is missing or corrupt:** Warn to stderr, use
  hardcoded fallback defaults. All devkit invocations continue to work.
- **If skill name fails regex validation:** Exit 1 with message showing the
  invalid name and expected format.
- **If args contain `--` prefixed values:** Exit 1 with message explaining the
  restriction and suggesting `--` separator syntax.

## Data Migration

None. This is a new capability. No existing data structures are modified.

Existing installations will gain the `devkit` command after re-running
`install.sh`. Projects are not retroactively initialized -- users run
`devkit init <target>` for each project they want to manage.

## Rollout Plan

1. **Verify `--print` flag:** Run `claude --print "echo hello"` to confirm
   non-interactive execution works with expected semantics. This is the
   highest-risk assumption. If this fails, stop and reassess the invocation
   model before any implementation.
2. **Implementation:** Build CLI, wrapper, config, and tests per the Work Groups
   below.
3. **Self-test:** Run `bash scripts/test-integration.sh` -- all existing 42 tests
   plus new harness tests must pass.
4. **Manual validation:** Run `devkit init .` on claude-devkit itself, then
   `devkit audit .` and `devkit architect . "test feature"` to verify end-to-end
   flow including multi-step skill execution.
5. **Install update:** Re-run `./scripts/install.sh` to register the `devkit`
   alias.
6. **Documentation:** CLAUDE.md updates are part of the work groups.
7. **Deploy:** Commit, push, announce.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Claude Code `--print` flag semantics differ from assumption | Medium | High -- CLI cannot invoke skills | Single function (`_invoke_claude()`) isolates the invocation. Easy to update flag or approach. **Verified first in Rollout step 1.** |
| Permission prompts block non-interactive execution | Medium | High -- skill stalls indefinitely | Pre-flight warning when no allowlists detected. Documented as known limitation. Users must configure `~/.claude/settings.json` allowlists (see CLAUDE.md Tool Permissions section). Future: `--permission-mode` forwarding. |
| Users forget to run `devkit init` before `devkit <skill>` | High | Low -- skills still work, just no state tracking | Pre-flight check warns but does not block. Auto-init could be added later. |
| Registry grows unbounded with stale entries | Low | Low -- informational only, `status` marks stale | Could add `devkit prune` later. Size limit prevents OOM. |
| `.devkit/` directory conflicts with another tool | Low | Medium -- naming collision | Name is unique enough. Can be changed via `configs/devkit-defaults.json`. |
| Subprocess inherits environment variables that affect Claude Code | Low | Medium -- unexpected behavior | Environment is explicitly constructed from `os.environ.copy()` with `CLAUDE_DEVKIT` guaranteed set. |

## Test Plan

### Test Command

```bash
bash scripts/test-integration.sh
```

All existing 42 tests must continue to pass. New tests (13 tests) are added for
the meta-harness:

### New Integration Tests

| # | Test Name | What It Validates |
|---|-----------|-------------------|
| 43 | devkit --help exits 0 | CLI entry point works, help text renders |
| 44 | devkit --version exits 0 | Version string format matches `\d+\.\d+\.\d+` |
| 45 | devkit init on valid git repo | Creates `.devkit/state.json`, valid JSON, required fields present |
| 46 | devkit init adds .gitignore entry | `.devkit/` appears in target's `.gitignore` |
| 47 | devkit init on non-git directory exits 1 | Rejects non-git targets |
| 48 | devkit init on nonexistent path exits 1 | Rejects missing paths |
| 49 | devkit status after init shows project | Project name and path appear in output |
| 50 | devkit deploy delegates to deploy.sh | Exit code matches deploy.sh behavior |
| 51 | devkit init on symlink-to-git-repo exits 1 | Symlink rejection (security: TB-2) |
| 52 | devkit init on path outside allowed_roots exits 1 | allowed_roots enforcement (security: STRIDE Elevation) |
| 53 | oversized state.json produces warning, status works | DoS protection (security: STRIDE DoS). Create 100KB state file, verify warning on stderr, verify `devkit status <target>` still exits 0 |
| 54 | invalid skill name rejected | Skill name regex enforcement (security: TB-1). Try `devkit ../../etc/passwd <target>`, expect exit 1 |
| 55 | arg starting with -- rejected | Argument injection guard (security: STRIDE Tampering). Try `devkit audit <target> --system-prompt foo`, expect exit 1 |

### Manual Testing Steps

1. Run `devkit init ~/projects/claude-devkit` -- verify `.devkit/state.json`
   created and `.gitignore` updated.
2. Run `devkit status` -- verify claude-devkit appears in project list.
3. Run `devkit audit ~/projects/claude-devkit` -- verify Claude Code launches
   with CWD in claude-devkit and `/audit` executes.
4. Run `devkit shell ~/projects/claude-devkit` -- verify interactive Claude
   session starts with correct CWD.
5. Run `devkit architect ~/projects/claude-devkit "test feature"` -- verify
   `/architect test feature` runs non-interactively (tests multi-step skill in
   `--print` mode).
6. Run `devkit status ~/projects/claude-devkit` -- verify `last_invocation`
   updated.

## Acceptance Criteria

1. `devkit init ~/projects/<any-git-repo>` creates `.devkit/state.json` with
   valid schema, adds `.devkit/` to `.gitignore`, and updates
   `~/.claude-devkit/registry.json`.
2. `devkit <skill> <target> [args]` invokes Claude Code with CWD set to target
   and `/<skill> [args]` as the prompt. Pre-flight checks validate target,
   skill deployment, and Claude Code availability.
3. `devkit shell <target>` launches an interactive Claude Code session with CWD
   set to target. State is updated pre-invocation with `exit_code: null`.
4. `devkit status` lists all registered projects with name, path, and
   last-touched timestamp. Stale entries (deleted paths) are marked `[STALE]`.
5. `devkit deploy` delegates to `scripts/deploy.sh` with passthrough arguments.
6. All 55 integration tests pass (42 existing + 13 new).
7. No external Python dependencies. stdlib only.
8. Path traversal, symlink, and non-git-repo inputs are rejected with clear
   error messages.
9. State and registry files are written atomically (tempfile + `os.replace()`).
10. File permissions: registry.json 0600, `.devkit/` directory 0755,
    `state.json` 0600.
11. Skill names validated with `^[a-z][a-z0-9-]*$`. Arguments starting with
    `--` are rejected.
12. If `configs/devkit-defaults.json` is missing, hardcoded fallback defaults
    are used with a warning.

## Task Breakdown

### Shared Dependencies

**`configs/devkit-defaults.json`** (create)

Default configuration consumed by `scripts/devkit_cli.py`. Must be created first
because the CLI reads it at startup. If this file is absent, the CLI falls back
to identical hardcoded defaults.

```json
{
  "schema_version": "1.0.0",
  "registry_path": "~/.claude-devkit/registry.json",
  "state_dir_name": ".devkit",
  "state_file_name": "state.json",
  "allowed_roots": ["~/projects/", "~/workspaces/"],
  "gitignore_state_dir": true,
  "claude_command": "claude",
  "claude_print_flag": "--print",
  "max_state_file_bytes": 65536,
  "max_registry_file_bytes": 1048576
}
```

### Work Groups

#### Work Group A: CLI Core and Tests

**Files:**
- `scripts/devkit_cli.py` (create)
- `scripts/test-integration.sh` (modify)

**`scripts/devkit_cli.py`** -- Main CLI implementation (~400-500 lines).

Structure:

```
#!/usr/bin/env python3
"""devkit -- Meta-harness CLI for claude-devkit."""

VERSION = "0.1.0"

# --- Constants and Fallback Defaults ---
# Hardcoded defaults matching configs/devkit-defaults.json schema.
# Used when config file is missing or corrupt.
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

SKILL_NAME_RE = re.compile(r'^[a-z][a-z0-9-]*$')

# Load configs/devkit-defaults.json relative to script location.
# If missing or corrupt, use FALLBACK_DEFAULTS and warn to stderr.

# --- Validation Functions ---
# validate_target(path) -> (bool, error_msg)
#   - Resolve to absolute via Path.resolve()
#   - Reject symlinks via Path(original).is_symlink()
#   - Require .git/ directory
#   - Check resolved path against allowed_roots + devkit root + /tmp/
#   - Return resolved path on success (used for all subsequent operations)
#
# validate_skill_name(name) -> (bool, error_msg)
#   - Check name matches SKILL_NAME_RE (^[a-z][a-z0-9-]*$)
#   - Check ~/.claude/skills/<name>/SKILL.md exists
#
# validate_args(args) -> (bool, error_msg)
#   - Reject any arg starting with "--"
#   - Return descriptive error suggesting -- separator syntax

# --- State Management ---
# read_state(target_path) -> dict or None
#   - Read .devkit/state.json with size limit
#   - Validate schema_version and field types + max lengths
#   - Return None on any error (warn to stderr)
#
# write_state(target_path, state_dict)
#   - Atomic write: tempfile in .devkit/, os.replace()
#   - Set permissions 0o600
#
# read_registry() -> dict
#   - Read ~/.claude-devkit/registry.json with size limit
#   - Return empty registry on any error
#
# write_registry(registry_dict)
#   - Atomic write: tempfile in ~/.claude-devkit/, os.replace()
#   - Set permissions 0o600
#
# update_registry(target_path, touch=True)
#   - Add or update project entry in registry
#   - Set last_touched to now

# --- Pre-Flight Checks ---
# preflight(skill, target_path) -> list of (level, message)
#   level: "error" | "warning"
#   Returns all issues found (does not short-circuit)
#   Errors are fatal. Warnings are printed but do not block.
#   Includes permission allowlist check (warning if no allowlists configured)

# --- Commands ---
# cmd_init(target_path)
#   1. Validate target
#   2. Create .devkit/ directory
#   3. Write state.json (atomic, 0o600)
#   4. Add .devkit/ to .gitignore (if gitignore_state_dir config is true)
#   5. Update registry
#   6. Print success message with project name
#
# cmd_run_skill(skill, target_path, args)
#   1. Validate target (get resolved path)
#   2. Validate skill name (regex + deployment check)
#   3. Validate args (reject --prefixed)
#   4. Run pre-flight checks (print warnings, exit on errors)
#   5. Update state (pre-invocation)
#   6. Build invocation: ["claude", "--print", "/<skill> <args>"]
#   7. try:
#        result = subprocess.run(invocation, cwd=resolved_path, env=env)
#      finally:
#        Update state with exit_code
#        Update registry last_touched
#   8. sys.exit(result.returncode)
#
# cmd_shell(target_path)
#   1. Validate target (get resolved path)
#   2. Run pre-flight checks (warnings only, no skill check)
#   3. Update state pre-invocation (exit_code: null)
#   4. Update registry last_touched
#   5. os.chdir(resolved_path)
#   6. os.execvp("claude", ["claude"])
#   Note: Steps 3-4 run before execvp because the harness never regains
#   control after process replacement. exit_code remains null.
#
# cmd_status(target_path=None)
#   If target_path:
#     - Show detailed status for one project
#     - Read .devkit/state.json for last invocation
#     - Read .claude/settings.json for security_maturity
#     - Show audit log count from plans/audit-logs/
#   Else:
#     - Read registry
#     - For each project: validate path still exists
#     - Print table: NAME | PATH | LAST TOUCHED | STATUS
#     - STATUS: "ok" if path exists, "[STALE]" if not
#
# cmd_deploy(args)
#   1. Locate deploy.sh relative to script
#   2. subprocess.run(["bash", deploy_sh_path] + args)
#   3. Propagate exit code

# --- Argument Parsing ---
# argparse with subcommands:
#   parser = argparse.ArgumentParser(prog="devkit")
#   subparsers = parser.add_subparsers()
#
#   # init
#   init_parser = subparsers.add_parser("init")
#   init_parser.add_argument("target")
#
#   # shell
#   shell_parser = subparsers.add_parser("shell")
#   shell_parser.add_argument("target")
#
#   # status
#   status_parser = subparsers.add_parser("status")
#   status_parser.add_argument("target", nargs="?")
#
#   # deploy
#   deploy_parser = subparsers.add_parser("deploy")
#   deploy_parser.add_argument("args", nargs="*")
#
#   # Skill commands (dynamic -- any unknown subcommand is treated as a skill)
#   # Use parse_known_args() to catch skill names that aren't subcommands
#   # Skill name is validated with SKILL_NAME_RE before dispatch
#
# Entry point:
#   if __name__ == "__main__":
#       main()
```

Key implementation details:

- **Dynamic skill dispatch:** The CLI does not hardcode skill names. If the first
  argument is not a known subcommand (init/shell/status/deploy), it is treated as
  a skill name. The second argument becomes the target path. The skill name is
  validated with `SKILL_NAME_RE` before any dispatch. This means
  `devkit audit ~/projects/foo` works the same as `devkit ship ~/projects/foo`.

- **Argument parsing strategy:** Use `argparse` with subparsers for known
  commands. For skill dispatch, check if `sys.argv[1]` matches a known
  subcommand. If not, validate against `SKILL_NAME_RE` first, then parse as
  `<skill> <target> [args...]` manually. This avoids needing to enumerate all
  skill names in argparse.

- **Environment construction:** `env = os.environ.copy()` then set
  `CLAUDE_DEVKIT` to the devkit root (resolved from script location:
  `Path(__file__).resolve().parent.parent`).

- **Gitignore management:** `ensure_gitignore_entry()` reads the target's
  `.gitignore`, checks if `.devkit/` is already present, and appends it if not.
  If `.gitignore` does not exist, creates it with just `.devkit/\n`. Uses atomic
  write.

- **Colors:** Reuse the `Colors` class pattern from `generate_skill.py` for
  terminal output.

- **Exit codes:** 0 = success, 1 = validation error or pre-flight failure,
  2 = invalid arguments. For skill invocation, propagate Claude Code's exit code.

- **Signal handling:** The `subprocess.run()` call in `cmd_run_skill` is wrapped
  in `try/finally` to ensure state and registry updates execute even if the
  process receives SIGINT during skill execution.

- **Path usage:** All operations after `validate_target()` use the resolved
  absolute path, never the user-provided string.

**`scripts/test-integration.sh`** (modify) -- Add 13 new tests after existing
test 42.

Tests use a temporary git repo created in `/tmp/devkit-harness-test/`:
```bash
# Setup
HARNESS_TEST_DIR="/tmp/devkit-harness-test"
mkdir -p "$HARNESS_TEST_DIR"
git -C "$HARNESS_TEST_DIR" init
```

Test implementations:
- Tests 43-44: Direct CLI invocation (`python3 scripts/devkit_cli.py --help`,
  `--version`)
- Tests 45-46: `devkit init` on the temp git repo, verify state.json and
  gitignore
- Tests 47-48: `devkit init` on `/tmp/devkit-not-git/` (no .git) and
  `/tmp/devkit-nonexistent/` -- expect exit 1
- Test 49: `devkit status` after init -- grep for project name in output
- Test 50: `devkit deploy --help` -- verify it delegates (exit 0 from deploy.sh
  help)
- Test 51: Create symlink to temp git repo, `devkit init <symlink>` -- expect
  exit 1
- Test 52: `devkit init /etc` (or `/System`) -- expect exit 1 (outside
  allowed_roots)
- Test 53: Write 100KB to `.devkit/state.json`, run `devkit status <target>` --
  expect warning on stderr, exit 0
- Test 54: `devkit ../../etc/passwd <target>` -- expect exit 1 (invalid skill
  name)
- Test 55: `devkit audit <target> --system-prompt foo` -- expect exit 1 (arg
  injection rejected)

Cleanup: `rm -rf "$HARNESS_TEST_DIR"` in the existing trap handler.

#### Work Group B: Shell Integration and Documentation

**Files:**
- `scripts/devkit` (create)
- `scripts/install.sh` (modify)
- `CLAUDE.md` (modify)

**`scripts/devkit`** -- Bash entry point wrapper (~20 lines).

```bash
#!/usr/bin/env bash
# devkit -- Meta-harness CLI for claude-devkit
# Thin wrapper that delegates to scripts/devkit_cli.py

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_SCRIPT="$REPO_DIR/scripts/devkit_cli.py"

if [[ ! -f "$CLI_SCRIPT" ]]; then
    echo "ERROR: devkit_cli.py not found at $CLI_SCRIPT" >&2
    echo "Is claude-devkit installed correctly?" >&2
    exit 1
fi

exec python3 "$CLI_SCRIPT" "$@"
```

Mark executable: `chmod +x scripts/devkit`.

**`scripts/install.sh`** (modify) -- Add devkit alias and scripts/ to PATH.

After the existing alias block (line ~127), add:

```bash
alias devkit="bash $REPO_DIR/scripts/devkit"
```

Also add `scripts/` to PATH for direct `devkit` invocation:

```bash
export PATH="\$PATH:$REPO_DIR/scripts"
```

**`CLAUDE.md`** (modify) -- Add meta-harness documentation.

Updates needed in these sections:

1. **Overview** -- Add "Meta-Harness" to "What's Inside" list.

2. **Architecture / Three-Tier Structure** -- Add to the tree:
   ```
   ├── scripts/
   │   ├── devkit_cli.py             # Meta-harness CLI
   │   ├── devkit                    # Meta-harness entry point
   ```

3. **Quick Start** -- Add section "5. Use the Meta-Harness":
   ```
   ### 5. Use the Meta-Harness (Optional)
   
   # Initialize a project for devkit management
   devkit init ~/projects/my-app
   
   # Run skills from anywhere
   devkit audit ~/projects/my-app
   devkit architect ~/projects/my-app "add feature"
   
   # Open interactive session
   devkit shell ~/projects/my-app
   
   # Check status of all managed projects
   devkit status
   ```

4. **Directory Reference / /scripts** -- Add `devkit_cli.py` and `devkit`
   entries to scripts list.

5. **Directory Reference / /configs** -- Add devkit-defaults.json.

6. **Integration Patterns** -- Add "With Meta-Harness" subsection describing
   the external targeting model.

7. **Troubleshooting** -- Add entries for common devkit CLI issues:
   - "Permission prompts block non-interactive execution" -- configure allowlists
   - "devkit init rejects valid project path" -- check allowed_roots
   - "devkit shell shows stale status" -- known limitation with execvp

## Validation Checklist

- [ ] `scripts/devkit_cli.py` uses stdlib only (no pip dependencies)
- [ ] All inputs validated before filesystem operations
- [ ] Skill names validated with `^[a-z][a-z0-9-]*$`
- [ ] Arguments starting with `--` rejected
- [ ] Atomic writes for state.json and registry.json (tempfile + os.replace)
- [ ] Symlinks rejected in target path validation
- [ ] Path traversal prevented (resolve + allowed_roots check)
- [ ] Resolved paths used for all post-validation operations
- [ ] No `shell=True` in subprocess calls
- [ ] State file reads have size limits
- [ ] Field length limits enforced on state.json reads
- [ ] File permissions set correctly (registry 0600, state.json 0600)
- [ ] Hardcoded fallback defaults used when config is missing
- [ ] Exit codes follow convention (0/1/2 + passthrough)
- [ ] All 55 integration tests pass (including 5 security tests)
- [ ] CLAUDE.md updated with meta-harness documentation
- [ ] install.sh adds devkit alias
- [ ] scripts/devkit is executable
- [ ] configs/devkit-defaults.json is valid JSON
- [ ] Pre-flight warns about missing permission allowlists
- [ ] Shell command updates state/registry before execvp

## Status: APPROVED

<!-- Context Metadata
discovered_at: 2026-08-19T18:02:36Z
claude_md_exists: true
recent_plans_consulted: agentic-sdlc-security-skills.md, audit-remove-mcp-deps.md, codebase-symbol-index.md
archived_plans_consulted: none
-->
