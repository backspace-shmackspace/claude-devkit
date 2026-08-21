# Feasibility Review: Detached/Headless Skill Execution for devkit CLI

**Reviewer:** Feasibility analyst (Round 2)
**Plan:** `.devkit/plans/detached-skill-execution.md`
**Date:** 2026-08-21
**Round:** 2 (previous review: 2026-08-21)
**Verdict:** PASS

---

## Assessment Summary

All Round 1 findings (2 Major, 8 Minor) have been addressed in the revised plan. The most significant revision -- restructuring the process tree so the watcher spawns Claude as its child rather than as a sibling -- correctly fixes the `os.waitpid` failure (M-1) and is the right design. The `--detach` flag extraction (M-2) is now shown with explicit code and handles all positional variants. The remaining new concerns are all Minor and none block implementation. The plan is ready for implementation.

---

## Round 1 Finding Resolution Status

### Major Findings

| ID | Finding | Status | Notes |
|----|---------|--------|-------|
| **M-1** | `os.waitpid` will always fail because watcher is sibling, not parent of Claude process | **RESOLVED** | Process tree restructured: watcher spawns Claude as its child via `subprocess.Popen`, then calls `os.waitpid(proc.pid, 0)`. The parent devkit CLI spawns only the watcher (with `start_new_session=True`), which in turn spawns Claude. Correctly documented in the Process Architecture diagram. |
| **M-2** | `--detach` flag parsing conflicts with `validate_args()` rejection of `--` prefixes | **RESOLVED** | Change 1 shows explicit extraction of `--detach` from `skill_args` before `split_skill_args()` and `validate_args()` run. Handles all positional variants (flag before args, after args, before `--` separator). Clean integration with the existing `main()` flow at line 1027 of `devkit_cli.py`. |

### Minor Findings

| ID | Finding | Status | Notes |
|----|---------|--------|-------|
| **m-1** | File handles leaked in parent `_spawn_detached()` | **RESOLVED** | File opening moved entirely into the watcher script. The parent no longer opens log file handles. Files opened with `os.open(..., 0o600)` for proper permissions, closed after `Popen`. |
| **m-2** | Watcher script uses f-string interpolation for path values | **RESOLVED** | All variable values now passed via `sys.argv` (`str(runs_dir)`, `json.dumps(invocation)`, `cwd`). Watcher receives them via `Path(sys.argv[1])`, `json.loads(sys.argv[2])`, `sys.argv[3]`. Documented in TB-4 trust boundary analysis and the `_spawn_watcher` docstring. |
| **m-3** | `_status_color()` function referenced but not defined | **RESOLVED** | Change 4 provides full implementation with ANSI color codes for running/completed/failed/stale states. |
| **m-4** | `cmd_result()` and `cmd_logs()` lack path traversal validation | **RESOLVED** | Change 3 provides `_validate_run_id()` using `Path(run_id).name != run_id` check. Called at the top of `cmd_result()`, `cmd_logs()`, and `cmd_clean()`. Follows the project's `(bool, error_msg)` validation tuple pattern. |
| **m-5** | New command names shadow potential skill names | **Acknowledged (not blocking)** | `jobs`, `result`, `logs`, `clean` added to `KNOWN_COMMANDS`. The plan does not explicitly document the shadowing trade-off. These are unlikely to collide with real skill names in practice. See m-NEW-5 below for a minor documentation suggestion. |
| **m-6** | Time estimate is optimistic (6-8 hours) | **RESOLVED** | Revised to 10-14 hours. |
| **m-7** | Version bump not specified | **RESOLVED** | Task Breakdown and Rollout Phase 2 both specify bumping `VERSION` to `"0.2.0"`. |
| **m-8** | `cmd_clean` does not check PID liveness for "running" status | **RESOLVED** | `cmd_clean` now includes `_is_pid_alive()` check for any run with `status == "running"`, marking dead-PID runs as `"stale"` before applying the age-based cleanup. |

---

## New Concerns (Round 2)

### No Critical or Major concerns.

### Minor

**m-NEW-1: `_is_pid_alive()` and `_generate_run_id()` listed but not implemented.**

The "New Functions" table lists both functions, and they are called in the plan's code, but neither has an implementation shown in any Change section. Both are trivial (`os.kill(pid, 0)` with `ProcessLookupError` handling; `datetime.now()` + `random.choices()`), and the run ID format is clearly specified. This is a documentation gap, not a design gap -- the implementer has unambiguous guidance from the function names, the meta.json schema, and the existing `utc_now_iso()` pattern.

**Recommendation:** Add their implementations to the plan (2 lines each), or note them as "implementation left to implementer" so the gap is intentional.

**m-NEW-2: ANSI escape codes break column alignment in `cmd_jobs()`.**

The `cmd_jobs()` format string uses `:<10` width on the return value of `_status_color()`:

```python
f"{_status_color(meta.get('status','?')):<10} "
```

ANSI escape codes are non-printing characters that add to the string's byte length but consume no visual width. A status like `"running"` (7 visible characters) with `\033[33m` prefix (5 bytes) and `\033[0m` suffix (4 bytes) becomes a 16-byte string. Python's `:<10` formatter counts all bytes, so it adds no padding (16 > 10), and the STARTED column shifts right by ~6 characters. This produces visually misaligned output for all statuses.

**Recommendation:** Pad the visible status text before wrapping in ANSI codes, or compute the padding width as `10 + len(escape_codes)`. The simplest fix is to pad inside `_status_color()`:

```python
def _status_color(status):
    colors = {"running": "\033[33m", ...}
    reset = "\033[0m"
    color = colors.get(status, "")
    padded = f"{status:<10}"
    return f"{color}{padded}{reset}" if color else padded
```

**m-NEW-3: Watcher uses `os.waitpid(proc.pid, 0)` instead of `proc.wait()`.**

The watcher creates a `subprocess.Popen` object `proc` but then calls `os.waitpid(proc.pid, 0)` directly, bypassing Popen's internal state management. This works correctly (the watcher is the parent process), but it means `proc.returncode` is never set. If any future watcher code references `proc.returncode`, it would be `None`. Using `proc.wait()` (which calls `os.waitpid` internally and sets `proc.returncode`) would be more idiomatic, equivalent in behavior, and more resilient to future maintenance.

**Recommendation:** Replace `os.waitpid(proc.pid, 0)` / `os.WEXITSTATUS` block with:

```python
exit_code = proc.wait()
```

This is a single-line replacement that eliminates the `WIFEXITED`/`WEXITSTATUS` handling, the `ChildProcessError` catch, and the manual PID tracking.

**m-NEW-4: `cmd_jobs` truncates at 20 rows with no indicator.**

`cmd_jobs()` displays `runs[:20]` but does not tell the user when there are more than 20 runs. A user with 50 accumulated runs would see the 20 most recent and have no indication that 30 more exist.

**Recommendation:** Add a footer line when truncation occurs:

```python
if len(runs) > 20:
    print(f"  ... and {len(runs) - 20} more (use 'devkit clean' to remove old runs)")
```

**m-NEW-5: Command name shadowing not documented as a conscious decision.**

Round 1's m-5 noted that `jobs`, `result`, `logs`, and `clean` could shadow future skill names. The revised plan adds them to `KNOWN_COMMANDS` (the correct mechanism) but does not document this as a known limitation or a deliberate trade-off. While these names are unlikely to collide with real skills, the decision should be explicit.

**Recommendation:** Add a one-line note under "Deviations From Established Patterns" or "Non-Goals" acknowledging that these command names are reserved and cannot be used as skill names.

---

## Integration Assessment

**Integration with `devkit_cli.py` is clean.** Verified against the current source (1043 lines):

1. **`--detach` extraction** (Change 1) slots cleanly into `main()` at line 1027-1033, between `skill_args = rest[1:]` and `split_skill_args(skill_args)`. No conflicts with existing code.

2. **New command dispatch** (`jobs`, `result`, `logs`, `clean`) follows the existing if/elif pattern in `main()` at lines 1001-1019. Should be inserted between the `deploy` dispatch and the dynamic skill dispatch section.

3. **`cmd_run_skill()` modification** (adding `detach` parameter) extends the existing function signature at line 637. The detach path would short-circuit after preflight checks, calling `_spawn_detached()` instead of `subprocess.run()`.

4. **`_atomic_write_json()`** (line 111) is reusable for the parent's initial `meta.json` write. The watcher correctly implements its own inline version since it cannot import from `devkit_cli.py`.

5. **`configs/devkit-defaults.json`** currently has 10 keys. Adding `"clean_retention_days": 7` is a clean extension with no schema conflicts.

6. **Existing `KNOWN_COMMANDS`** (line 59) is a tuple of 4 entries. Extending it with 4 more is straightforward.

7. **Test integration** aligns with the existing `test-integration.sh` pattern (730 lines, 54 tests). The 17 new test cases follow the `run_test()` harness convention.

---

## Backward Compatibility

No breaking changes. The `--detach` flag is additive. New commands are new dispatch paths. Existing `devkit init|shell|status|deploy` and dynamic skill execution are unchanged. The only compatibility consideration is the command name shadowing noted in m-NEW-5.

---

## Recommended Adjustments

1. **(m-NEW-2)** Fix ANSI column alignment in `_status_color()` by padding the visible text before wrapping in escape codes.
2. **(m-NEW-3)** Replace `os.waitpid(proc.pid, 0)` with `proc.wait()` in the watcher script for idiomatic usage.
3. **(m-NEW-1)** Add 2-line implementations for `_is_pid_alive()` and `_generate_run_id()`, or mark them as intentionally left to the implementer.
4. **(m-NEW-4)** Add a truncation indicator to `cmd_jobs()` when more than 20 runs exist.
5. **(m-NEW-5)** Document the command name reservation as a conscious design decision.
