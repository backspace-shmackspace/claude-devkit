# Plan Review: detached-skill-execution.md

**Reviewer:** automated plan review
**Date:** 2026-08-21
**Round:** 2
**Verdict:** PASS

## Round 1 Finding Resolution

### Required Edit 1: Fix or scope the atomic writes claim
**Status:** RESOLVED

The Context Alignment section (line 21) now accurately states: "Atomic writes: Run metadata written atomically from the parent process via `_atomic_write_json()`. Watcher updates use inline atomic writes (`tempfile` + `os.rename`) since the watcher is a standalone snippet without access to `_atomic_write_json()`."

The watcher script (Change 2) implements its own `atomic_write_json()` using `os.open()` with 0o600 permissions and `os.rename()`. Both the claim and the implementation are now consistent.

### Required Edit 2: Eliminate f-string source interpolation in `_spawn_watcher()`
**Status:** RESOLVED

The watcher script is now a static string literal with no f-string interpolation. All variable values (`runs_dir`, `invocation`, `cwd`) are passed via `sys.argv` (lines 242-248). The watcher reads them as `sys.argv[1]`, `sys.argv[2]`, `sys.argv[3]`. The `invocation` list is serialized via `json.dumps()` and deserialized via `json.loads()` inside the watcher. The Context Alignment section (line 27) and Security Requirements (TB-4, lines 509-511) both explicitly document this design choice and its rationale.

### Required Edit 3: Add `devkit-defaults.json` configurability for clean retention
**Status:** RESOLVED

`cmd_clean()` reads `config.get("clean_retention_days", 7)` (line 369). The Modified Config Files table (line 440) explicitly adds `"clean_retention_days": 7` to `configs/devkit-defaults.json`. The `devkit clean` interface (line 411) documents the config key with hardcoded fallback.

### Required Edit 4: Explicitly note test count update in Task Breakdown
**Status:** RESOLVED

Work Group 1 (line 653) explicitly calls out: "scripts/test-integration.sh (modify -- add detached execution, watcher lifecycle, jobs, result, logs, clean, and security tests; update test count comment)". Line 654 similarly notes: "CLAUDE.md (modify -- add detached execution documentation under Quick Start step 5 and the Meta-Harness section; update test count)".

### Optional Suggestion 1: Close file handles in parent after Popen
**Status:** RESOLVED (by design change)

The revised architecture moves file handle creation into the watcher process, not the parent. The parent (`_spawn_detached()`) no longer opens stdout/stderr handles. The watcher opens them (lines 199-202), passes them to Claude's Popen, and closes them immediately after (lines 209-210). The concern no longer applies.

### Optional Suggestion 2: Surface active runs in `devkit status`
**Status:** Not addressed (optional, acceptable)

### Optional Suggestion 3: Consider `max_concurrent_runs` soft limit
**Status:** Not addressed (optional, acceptable)

## New Issues

### Observation 1: FALLBACK_DEFAULTS missing `clean_retention_days`

The existing pattern in `devkit_cli.py` mirrors every key from `configs/devkit-defaults.json` into `FALLBACK_DEFAULTS` (lines 41-52 in the current source). The plan adds `clean_retention_days` to `devkit-defaults.json` (line 440) and uses `config.get("clean_retention_days", 7)` in `cmd_clean()`, but the Work Group 1 task breakdown does not mention updating `FALLBACK_DEFAULTS` to include this key. The code works either way (the `.get()` call has its own fallback), but omitting the key from `FALLBACK_DEFAULTS` breaks the structural invariant that the two sources mirror each other.

**Severity:** Low. Non-blocking. The implementer should add `"clean_retention_days": 7` to `FALLBACK_DEFAULTS` during implementation.

### Observation 2: Null PID stale detection gap

When the watcher dies before spawning Claude, `meta.json` retains `pid: None`. The stale detection logic in `cmd_jobs()` (line 300) and `cmd_clean()` (line 390) uses `if pid and not _is_pid_alive(pid)`, which short-circuits when `pid` is falsy. A run orphaned this way stays "running" indefinitely and is never marked "stale" or cleaned.

The Risks section (line 487) claims "devkit jobs detects stale PIDs" for this scenario, but the code path does not cover the `pid: None` case.

**Severity:** Low. The failure mode (watcher dies between spawn and Claude launch) is extremely unlikely. A future enhancement could treat old runs with `pid: None` and no heartbeat as stale, but this does not block the plan.

### Observation 3: ANSI escape codes in column-aligned output

`cmd_jobs()` uses `{_status_color(meta.get('status','?')):<10}` for column alignment (line 322). ANSI escape sequences add invisible characters (~9 bytes) that the `<10` format specifier counts toward the field width, causing misaligned columns in terminal output.

**Severity:** Cosmetic. Non-blocking.

## Conflicts with CLAUDE.md

None found. The revised plan follows all established patterns:

- **Python stdlib only:** All imports are stdlib (`subprocess`, `os`, `signal`, `pathlib`, `json`, `time`, `tempfile`).
- **Atomic writes:** Both parent and watcher use atomic write patterns.
- **Validation tuples:** `_validate_run_id()` returns `(bool, error_msg)`.
- **Script placement:** All source changes in `scripts/devkit_cli.py` and `configs/devkit-defaults.json`.
- **State model:** Extends existing `~/.claude-devkit/` namespace and `.devkit/` conventions.
- **Test pattern:** New tests follow `test-integration.sh` `run_test()` harness.
- **Injection resistance:** Watcher receives values via `sys.argv`, no f-string interpolation, no `shell=True`, `_validate_run_id()` blocks path traversal.
- **Config pattern:** Tunable defaults in `devkit-defaults.json` with hardcoded fallback in `FALLBACK_DEFAULTS`.
- **`--` separator convention:** `--detach` is extracted before `split_skill_args()`/`validate_args()`, preserving the existing `--` separator passthrough.

## Historical Alignment

No conflicts with `mvp-meta-harness.md`. Detached execution is a natural extension of the existing `subprocess.run` pattern. The `runs/` directory under `~/.claude-devkit/` follows the established namespace. The prior plan's non-goals (no continuous operation, no checkpoint/resume) are respected by the fire-and-forget design and the explicit "No run resumption" non-goal.
