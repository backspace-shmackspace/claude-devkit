# Red Team Analysis: Detached/Headless Skill Execution (Round 2)

**Plan:** `detached-skill-execution.md`
**Reviewed:** 2026-08-21
**Round:** 2 (revision review)
**Reviewer:** Red team critical review + Round 1 resolution verification

## Verdict: PASS

All Round 1 Critical and Major findings are resolved. No new Critical findings. Three new Minor findings and two Info items introduced by the revision. The plan is ready for implementation.

---

## Round 1 Finding Resolution

### From Red Team (Round 1)

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| F-01 | Critical | Watcher can never obtain real exit code | **Resolved** |
| F-02 | Major | `--detach` flag rejected by `validate_args()` | **Resolved** |
| F-03 | Major | File permissions not enforced as claimed | **Resolved** |
| F-04 | Major | Watcher meta.json update contradicts atomic writes | **Resolved** |
| F-05 | Major | Path traversal check described but not implemented | **Resolved** |
| -- | Major | Missing Repudiation in STRIDE analysis | **Resolved** |
| -- | Major | Trust boundaries not identified | **Resolved** |
| -- | Major | Mitigation specificity mismatches (5 claims without code) | **Resolved** |
| -- | Major | No failure mode analysis for security controls | **Resolved** |
| F-06 | Minor | Watcher f-string interpolation of path | **Resolved** |
| F-07 | Minor | File handle leak in `_spawn_detached()` | **Resolved** |
| F-08 | Minor | Watcher process invisible and unmanageable | **Partially Resolved** |
| F-09 | Minor | Test plan does not cover watcher completion lifecycle | **Resolved** |
| F-10 | Minor | No concurrency guardrails for same-project skill conflicts | **Not Resolved** (accepted as design choice) |

### From Feasibility Review (Round 1)

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| M-1 | Major | `os.waitpid` will never succeed (same root cause as F-01) | **Resolved** |
| M-2 | Major | `--detach` flag parsing conflicts (same as F-02) | **Resolved** |
| m-1 | Minor | File handle leak (same as F-07) | **Resolved** |
| m-2 | Minor | f-string interpolation (same as F-06) | **Resolved** |
| m-3 | Minor | `_status_color()` function referenced but not defined | **Resolved** |
| m-4 | Minor | Path traversal validation missing (same as F-05) | **Resolved** |
| m-5 | Minor | Command names shadow potential skill names | **Not Resolved** |
| m-6 | Minor | Time estimate optimistic | **Resolved** |
| m-7 | Minor | Version bump not specified | **Resolved** |
| m-8 | Minor | `cmd_clean` does not check PID liveness for "running" status | **Resolved** |

---

## Resolution Details

### F-01 / M-1: Watcher can never obtain real exit code (Critical / Major) -- Resolved

The process architecture was correctly restructured. The watcher now spawns Claude as its child:

```
devkit CLI (parent)
  -> Watcher process (detached child, start_new_session=True)
       -> Claude process (child of watcher)
```

The watcher calls `subprocess.Popen(invocation, ...)` to spawn Claude, then calls `os.waitpid(proc.pid, 0)` to block until Claude exits. Since the watcher IS the parent, `os.waitpid` succeeds and returns the real exit status. The `os.WEXITSTATUS` / `os.WIFEXITED` handling is correct for extracting the exit code.

The `ChildProcessError` fallback (with `exit_code = -1`) now only triggers if something unexpected happens with the child process tracking, which is an appropriate safety net.

### F-02 / M-2: `--detach` flag rejected by `validate_args()` (Major) -- Resolved

Change 1 now explicitly shows `--detach` being extracted from `skill_args` before `split_skill_args()` runs:

```python
detach = "--detach" in skill_args
if detach:
    skill_args = [a for a in skill_args if a != "--detach"]
```

This is clean and handles all positional variants. The flag never reaches `validate_args()`. References to the non-existent `KNOWN_FLAGS` have been removed.

### F-03: File permissions not enforced as claimed (Major) -- Resolved

All file creation now uses explicit permission modes:
- Run directory: `os.makedirs(runs_dir, mode=0o700)` (line 138)
- meta.json: `os.chmod(runs_dir / "meta.json", 0o600)` after `_atomic_write_json` (line 155)
- Watcher log files: `os.open(..., os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)` (lines 199-200)
- result.json: `os.open(..., 0o600)` (line 230)
- Watcher's inline atomic_write_json: `os.open(..., 0o600)` (line 193)

The STRIDE Tampering and Information Disclosure mitigations now accurately reflect the code.

### F-04: Watcher meta.json update contradicts atomic writes (Major) -- Resolved

The watcher now includes an inline `atomic_write_json()` function that uses the tempfile-plus-rename pattern:

```python
def atomic_write_json(path, data):
    tmp_path = path.with_suffix(".tmp")
    fd = os.open(str(tmp_path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
    os.rename(str(tmp_path), str(path))
```

This function is used for both the PID update (line 216) and the finalization write (line 240). The `os.rename` on the same filesystem is atomic on POSIX, so readers never see partial content. The permissions on the temp file are set via `os.open(..., 0o600)`.

Note: The inline version uses `os.rename` rather than `os.replace`. On POSIX these are equivalent when the target exists (both are atomic), but `os.replace` is the portable choice and is what the parent's `_atomic_write_json` uses. This inconsistency is cosmetic -- both are correct on macOS/Linux.

### F-05: Path traversal check described but not implemented (Major) -- Resolved

`_validate_run_id()` is now defined (Change 3, lines 256-261) and called at the top of `cmd_result()` (line 331), `cmd_logs()` (line 348), and `cmd_clean()` (line 376). The check `Path(run_id).name != run_id` correctly rejects any run ID containing path separators or traversal sequences.

### Missing Repudiation in STRIDE (Major) -- Resolved

The STRIDE analysis now includes a Repudiation section (lines 528-533) covering:
- Audit trail via meta.json with timestamps, skill name, target, and exit code
- Accepted risk for result.json integrity with cross-check against stdout.log
- Future enhancement path for tamper-evident logging via `emit-audit-event.sh`

### Trust boundaries not identified (Major) -- Resolved

Four trust boundaries are now explicitly documented (lines 504-511), including TB-4 (inline code execution), which is the most important one for this design. The TB-4 mitigation is clearly stated: static string literal with sys.argv for all variable values.

### Mitigation specificity mismatches (Major) -- Resolved

All five mitigations cited in Round 1 now have matching code:

| Claim | Round 1 Status | Round 2 Status |
|-------|---------------|---------------|
| Log files 0o600 | Not implemented | Implemented via `os.open(..., 0o600)` |
| Run directories 0o700 | Not implemented | Implemented via `os.makedirs(mode=0o700)` |
| Atomic writes in watcher | Not implemented | Implemented via inline `atomic_write_json()` |
| Path traversal validation | Not implemented | Implemented via `_validate_run_id()` |
| No f-string interpolation in watcher | Partially true | Fully true -- all values via `sys.argv` |

### Failure mode analysis missing (Major) -- Resolved

Each of the five security controls now has documented failure modes and consequences (lines 556-566). The analysis covers file permission failures, future code changes introducing injection, missing validation calls, shell=True regressions, and atomic write failures.

### F-06 / m-2: Watcher f-string interpolation (Minor) -- Resolved

The watcher script is now a static string literal with zero interpolation. All variable values are passed via `sys.argv`:
- `sys.argv[1]` = runs_dir path
- `sys.argv[2]` = invocation as JSON
- `sys.argv[3]` = working directory

### F-07 / m-1: File handle leak (Minor) -- Resolved

The parent (`_spawn_detached`) no longer opens log files. Log file creation is entirely within the watcher script, which opens them via `os.open/os.fdopen` and closes them after passing to `subprocess.Popen`.

### F-08: Watcher process invisible (Minor) -- Partially Resolved

The new architecture reduces the severity: since the watcher is Claude's parent, killing Claude (whose PID is in meta.json) causes the watcher to receive the `waitpid` result, finalize meta.json, and exit. Users can effectively manage runs by targeting Claude's PID.

However, the watcher's own PID is still not recorded. If the watcher itself hangs (unlikely but possible), there is no way to discover or kill it except through `ps aux | grep python`. A `devkit cancel <run-id>` command that kills Claude's PID and waits for the watcher to finalize would be a useful future addition but is not needed for MVP.

### F-09: Test plan missing watcher lifecycle tests (Minor) -- Resolved

Three watcher lifecycle tests are now included (lines 590-595): `test_watcher_completes_run` (mock Claude exit 0), `test_watcher_records_failure` (mock non-zero exit), and `test_watcher_handles_empty_stdout` (no crash on empty output).

### m-3: `_status_color()` not defined (Minor) -- Resolved

Now defined as Change 4 (lines 266-278) with ANSI color codes for running (yellow), completed (green), failed (red), and stale (gray).

### m-6: Time estimate optimistic (Minor) -- Resolved

Revised from 6-8 hours to 10-14 hours (line 8).

### m-7: Version bump not specified (Minor) -- Resolved

Now explicitly called out in Phase 2 (line 471) and Task Breakdown (line 651).

### m-8: `cmd_clean` doesn't check PID liveness (Minor) -- Resolved

`cmd_clean` now calls `_is_pid_alive()` for runs with `status == "running"` (lines 386-391). Dead PIDs transition to "stale" and become eligible for cleaning.

### F-10: No concurrency guardrails (Minor) -- Not Resolved

The plan deliberately scopes this out: "user responsibility, same as today" (Risks table, line 489). This is an acceptable design choice for MVP. Two concurrent `/ship` runs on the same project could conflict, but this is the same risk as running two `claude` sessions manually. Documenting this in the help text would be a low-cost improvement.

### m-5: Command names shadow potential skill names (Minor) -- Not Resolved

`jobs`, `result`, `logs`, and `clean` are now reserved command names. A user cannot create skills with these names. The plan does not document this as a known limitation. Low impact -- these are unlikely skill names -- but should be noted somewhere (e.g., in help text or CLAUDE.md).

---

## New Findings

### N-01: Detached runs and state.json interaction is under-specified (Minor)

The plan says `cmd_run_skill()` is modified with a `detach` parameter that dispatches to `_spawn_detached()` when True. The existing `cmd_run_skill()` has two important side effects before the subprocess call:

1. **Pre-invocation state write** (line 684-694): Records `last_invocation` with `exit_code: None` in the project's `state.json`
2. **Registry update** (line 695): Registers/touches the project in `registry.json`

And a **finally block** (lines 731-740) that writes the final exit code to `state.json`.

The plan does not specify where the detach dispatch occurs relative to these operations. Three outcomes are possible depending on placement:

| Dispatch location | state.json behavior | Registry behavior |
|---|---|---|
| Before state writes (cleanest) | Not updated for detached runs | Not updated |
| After state writes, before try/finally | Stuck with `exit_code: None` | Updated |
| Inside try block | Finally writes `exit_code: 1` (default) | Updated |

The most natural implementation dispatches before the state writes, which means `devkit status <target>` would not show detached runs and `last_invocation` would reflect only synchronous runs. This is likely the correct behavior, but the plan should state this explicitly so the implementer does not accidentally place the dispatch inside the try/finally block (which would write incorrect exit code data).

**Recommendation:** Add a note to the `cmd_run_skill()` modification description specifying that the detach dispatch occurs after validation and preflight but before the pre-invocation state write and try/finally block.

### N-02: ANSI color codes break column alignment in `devkit jobs` output (Minor)

`_status_color()` wraps status strings in ANSI escape sequences (e.g., `\033[32mcompleted\033[0m`). The format specifier `{_status_color(...):<10}` counts all characters including escape sequences for padding. An ANSI-wrapped status string like `\033[32mcompleted\033[0m` is 22 characters but only 9 display columns. The `:<10` padding adds 0 spaces (22 > 10), causing the STARTED column to shift right by ~12 characters.

Example output (actual alignment):
```
RUN ID                       SKILL        PROJECT              STATUS     STARTED
20260821-143052-a1b2c3       architect    my-app               completed  2026-08-21T14:30:52Z
```
The "completed" cell would visually overflow its column, pushing STARTED out of alignment.

**Fix:** Calculate visible width (status string length without ANSI codes) and adjust padding. Alternatively, apply color after padding: `f"{status:<10}" -> color + padded_status + reset`.

### N-03: Corrupt `meta.json` crashes entire `devkit jobs` listing (Minor)

`cmd_jobs()` reads meta.json for every run directory (line 296):

```python
meta = json.loads(meta_path.read_text())
```

If any single meta.json is corrupt (e.g., the watcher's inline `atomic_write_json` failed mid-rename on a filesystem that does not guarantee atomic rename, or disk corruption), `json.loads()` throws `JSONDecodeError` and the entire `devkit jobs` command crashes. One bad run directory prevents the user from seeing any run status.

**Recommendation:** Wrap the meta.json read in try/except, skip entries that fail to parse, and optionally print a warning. This is consistent with the defensive pattern used elsewhere in the codebase (e.g., `load_config` falls back to defaults on parse failure).

### N-04: Watcher does not install signal handlers for graceful shutdown (Info)

If the watcher process receives SIGTERM (e.g., system shutdown, `kill <watcher-pid>`), it terminates without finalizing meta.json. Claude, as a child process in the same session, may or may not receive the signal depending on how it was sent:

- `kill <watcher-pid>`: Only the watcher dies. Claude becomes an orphan (re-parented to init/launchd) and continues running. meta.json stays "running" indefinitely until `devkit jobs` marks it "stale" (but Claude is actually still alive with a different parent -- PID check would show it as "running").
- System shutdown (SIGTERM to session): Both watcher and Claude receive SIGTERM.

A signal handler in the watcher that finalizes meta.json on SIGTERM would improve robustness, but this is an edge case and acceptable for MVP.

### N-05: `os.rename` vs `os.replace` inconsistency in watcher's atomic write (Info)

The parent process uses `os.replace()` (via `_atomic_write_json` at line 130 of devkit_cli.py) for atomic file replacement. The watcher's inline `atomic_write_json` uses `os.rename()` (line 195 of the plan).

On POSIX, both are atomic when source and target are on the same filesystem, and `os.rename` replaces an existing target file. On Windows (not in scope per the plan's assumptions), `os.rename` raises `FileExistsError` if the target exists while `os.replace` does not. Since the plan explicitly scopes out Windows support, this is correct but inconsistent. Using `os.replace` in the watcher would align with the parent's pattern at zero cost.

---

## Security Supplement: Residual Risk Assessment

The revised plan's security posture is materially improved from Round 1. All claimed mitigations now have corresponding code. The key residual risks are:

| Residual Risk | Severity | Notes |
|---|---|---|
| Watcher script executed via `python -c` (TB-4) | Low | Mitigated by static string literal + sys.argv. Well-documented in trust boundary analysis. |
| PID reuse causing false "running" status | Very Low | Standard limitation of PID-based liveness checks. Window is very small on modern systems. |
| No integrity verification of result.json | Low | Accepted risk for MVP. Cross-check against stdout.log is available. |
| Orphaned Claude process if watcher killed | Low | Claude finishes normally and exits; meta.json stays "running" until `devkit jobs` marks it stale. |

None of these residual risks warrant blocking implementation.

---

## Summary

The revision is thorough. The critical process architecture flaw (F-01) was fixed by restructuring the watcher to be Claude's parent -- a clean and correct solution. All five Round 1 "claim vs code" mismatches (permissions, atomic writes, path traversal, f-string injection, failure modes) have been resolved with matching implementations. The three new Minor findings (N-01 state.json interaction, N-02 column alignment, N-03 error handling) are implementation-time fixes that do not require plan revision, though N-01 should ideally be clarified in the plan to prevent implementer error.
