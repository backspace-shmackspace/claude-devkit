# Feasibility Review: Devkit Hygiene Improvements

**Plan:** `plans/devkit-hygiene-improvements.md` (Rev 2, 2026-03-27)
**Reviewer:** Feasibility Analyst
**Date:** 2026-03-27
**Round:** 2
**Verdict:** PASS

---

## Executive Summary

The revised plan (Rev 2) addresses both Major concerns from Round 1. The test count discrepancy is now documented accurately (44 runtime tests, not 46), and trap handlers have been added to both test scripts to prevent stale fixtures on interruption. The duplicate integration tests (Tests 3-4 from Rev 1) have been replaced with genuinely different smoke tests. No Critical or Major issues remain. Three Minor concerns are noted below, none of which block implementation.

---

## Round 1 Major Concerns Resolution

### 1. Test Count Discrepancy -- RESOLVED

**Round 1 concern:** Plan stated "46 existing tests" but runtime count was 44 due to skipped test numbers (26, 33, 35) and a string label (27b).

**Resolution in Rev 2:** The plan now correctly states "44 runtime tests" throughout (lines 24, 51, 130). The header comment says "46 test cases" is acknowledged as inaccurate and flagged for update (line 24). The numbering origin note (line 21) explains why improvement numbers are #4/#5/#7/#8 instead of sequential. The plan commits to updating the header comment to document the actual test inventory including numbering gaps (Acceptance Criteria WG-1, line 406).

**Verified:** Ran `bash generators/test_skill_generator.sh` -- confirmed `Total: 44` with 44 passes, 0 failures. The discrepancy between the header comment ("46 test cases") and runtime count (44) is a documentation issue, not a logic error, and the plan addresses it.

### 2. Source Tree Modification Without Trap Handlers -- RESOLVED

**Round 1 concern:** Tests creating temporary directories in `skills/` had no cleanup mechanism for interrupted execution, risking stale directories that break `deploy_all_core()` and `validate-all.sh`.

**Resolution in Rev 2:**

- **WG-1 (`test_skill_generator.sh`):** Trap handler added at lines 132-139 of the plan. The handler removes `skills/test-validate-invalid/` on EXIT, INT, and TERM signals. Belt-and-suspenders: explicit `rm -rf` after Test 48 (line 113), plus the final cleanup test (Test 50) as a third layer.

- **WG-3 (`test-integration.sh`):** Trap handler at lines 619-625 of the plan removes all smoke artifacts (`$TEST_DIR`, `$DEPLOY_DIR/smoke-coord`, `$DEPLOY_DIR/smoke-pipe`) on EXIT, INT, and TERM. Rev 2 also removed the `skills/smoke-invalid/` test that modified the source tree -- the integration tests now do NOT touch `skills/` at all (line 429, Acceptance Criteria WG-3: "No tests modify the source tree").

- **Rev 2 duplicate removal:** The original Tests 3-4 in the integration test (which duplicated WG-1's `--validate` tests AND created `skills/smoke-invalid/` in the source tree) have been replaced with a full lifecycle test (generate-validate-deploy-undeploy) and a meta-test (run the unit suite). This eliminates the second source-tree modification point entirely.

**Verified:** The trap handler pattern (`trap cleanup EXIT INT TERM` with `rm -rf ... 2>/dev/null || true`) is correct. EXIT fires on both normal and abnormal termination, so cleanup runs in all cases. The `2>/dev/null || true` suffix ensures the handler is idempotent (no failure if the directory doesn't exist).

---

## New Concerns

### Minor: Trap Handler Interaction with Existing Script Cleanup (Minor)

**Category:** Implementation detail

The plan adds a `cleanup_on_exit` trap handler to `test_skill_generator.sh` that fires on EXIT. The existing Test 46 (to be renumbered 50) also performs cleanup by removing `$TEST_DIR`. These are complementary and non-conflicting -- the trap handler cleans `skills/test-validate-invalid/` while Test 50 cleans `$TEST_DIR`. However, if a future contributor adds a trap handler that also handles `$TEST_DIR`, the two could interfere. Bash only supports one handler per signal; `trap cleanup EXIT` replaces any previous EXIT handler rather than chaining.

**Impact:** None today. The plan's two cleanup mechanisms (trap for `skills/test-validate-invalid/`, Test 50 for `$TEST_DIR`) target different directories and do not conflict. The concern is purely forward-looking.

**Recommended adjustment:** A comment near the trap handler noting that only `skills/test-validate-invalid/` is its responsibility, and that `$TEST_DIR` cleanup is handled by the final test, would prevent future confusion.

### Minor: Integration Test Test 4 (Meta-Test) Doubles Execution Time (Minor)

**Category:** Test design

Integration Test 4 runs the full unit test suite (`test_skill_generator.sh`) from within the integration test. This means the unit suite runs twice when both test scripts are run sequentially (e.g., in a CI pipeline or a manual "run all tests" workflow). With the unit suite at ~44 tests, this is not a significant time cost today, but it compounds as the test suite grows.

Additionally, Test 4 (meta-test) temporarily creates `skills/test-validate-invalid/` via the unit suite's Test 48. The unit suite's trap handler will clean this up, but the integration test should document that Test 4 has this side effect on the source tree (it is transient and cleaned up, but an operator observing the test mid-run might see the stale directory).

**Impact:** Low. Execution time is the main cost, and it is currently small.

**Recommended adjustment:** Consider making Test 4 conditional or gated behind a `--full` flag in a future iteration. For now, accept the duplication as a useful meta-validation.

### Minor: Integration Test Deploys to Real `~/.claude/skills/` (Minor)

**Category:** Side effects

Integration Tests 1 and 3 deploy smoke skills to `~/.claude/skills/smoke-coord` and `~/.claude/skills/smoke-pipe`. While these are cleaned up by both explicit `rm -rf` within the test command and the trap handler, there is a brief window during execution where these smoke skills are deployed to the user's real skill directory. If a Claude Code session is running concurrently, it could potentially discover and index these skills.

**Impact:** Negligible. The skills exist for milliseconds, have "smoke" in the name, and are structurally valid (they were generated by `generate_skill.py`). No realistic user impact.

**Recommended adjustment:** None required. The plan's approach of using `~/.claude/skills/` directly is the only way to verify the deployment path works, since `deploy.sh` hardcodes that target directory.

---

## Verified Claims

The following plan claims were verified against the actual codebase and live test runs:

| Claim | Status | Evidence |
|-------|--------|----------|
| Test suite produces 44 runtime tests (not 46) | Verified | Live run: `Total: 44`, `Pass: 44`, `Fail: 0` |
| Test numbers 26, 33, 35 are skipped; 27b is a string label | Verified | Read `test_skill_generator.sh` -- no Test 26, 33, or 35 definitions; line 342 uses `run_test "27b"` |
| Header comment says "46 test cases" | Verified | Line 4: `# Runs all 46 test cases from the plan` |
| `$SKILLS_DIR` resolves to repo root (parent of `generators/`) | Verified | Line 29: `SKILLS_DIR="$(dirname "$SCRIPT_DIR")"` |
| `DEPLOY_SCRIPT` variable already exists | Verified | Line 408: `DEPLOY_SCRIPT="$(dirname "$SCRIPT_DIR")/scripts/deploy.sh"` |
| `deploy.sh --validate architect` succeeds (exit 0) | Verified | Live run: validates with warnings, deploys, exit 0 |
| `deploy.sh --validate test-validate-invalid` fails (exit 1) | Verified | Live run: 5 validation errors, "Skipping deployment", exit 1 |
| `deploy.sh --validate --contrib journal` succeeds (exit 0) | Verified | Live run: validates with warnings, deploys, exit 0 |
| Bug at line 103 of `ship/SKILL.md` uses value-based check | Verified | Line 103: `if [ "$SECURITY_MATURITY" = "advisory" ]` |
| `validate-all.sh` iterates `skills/*/SKILL.md` (stale dirs would be picked up) | Verified | Line 49: `for skill in "$REPO_DIR"/skills/*/SKILL.md` |
| `deploy_all_core()` iterates `skills/*/` (stale dirs would be deployed) | Verified | Line 101: `for skill_dir in "$SKILLS_DIR"/*/` |
| `generate_skill.py` accepts `-t` (target-dir) and `--force` flags | Verified | `--help` output confirms `--target-dir` and `--force` |
| `$BOLD` is undefined in test script | Verified | Line 505 uses `${BOLD}` but it is never defined (pre-existing, not introduced by this plan) |
| `set -euo pipefail` in `deploy.sh` with empty ARGS array | Verified | Bash 5.3 handles empty array expansion correctly under `set -u` |
| Rev 2 removed duplicate integration tests 3-4 | Verified | Rev 2 Tests 3-4 are lifecycle and meta-test (lines 223-244), not `--validate` duplicates |

---

## Implementation Complexity Assessment

| Improvement | Plan's Estimate | Actual Complexity | Notes |
|-------------|----------------|-------------------|-------|
| WG-1: --validate tests | Low | Low | All three test commands (`--validate`, `--validate` with invalid, `--validate --contrib`) verified live. `DEPLOY_SCRIPT` variable already exists. Trap handler is 4 lines. Only complexity is maintaining correct line insertion point relative to Test 45 and cleanup test. |
| WG-2: Settings precedence fix | Low | Low | 3-line logic change. The fix is correct: `LOCAL_SET=0` tracks source rather than checking resolved value. No interaction with the `case` validation block on lines 109-113. Pseudocode in a skill definition -- not directly executed, interpreted by Claude. |
| WG-3: Integration test framework | Low | Low | Standalone script, no source-tree modifications (Rev 2 removed the problematic `skills/smoke-invalid/` test). The `run_test` pattern is copied from the unit suite. `set -e` at the top could cause premature exit if a non-`run_test` command fails, but the only such commands are `rm -rf` (returns 0 on non-existent paths) and `mkdir -p` (idempotent). |
| WG-4: Archetype decision guide | None (docs only) | None | Pure documentation. Content outline in the plan is comprehensive. Cross-references to templates and CLAUDE.md are accurate. |

---

## Breaking Changes / Backward Compatibility

None identified. Unchanged from Round 1 assessment:
- New tests append to existing suite (no renumbering of tests 1-45).
- Cleanup test renumber (46 to 50) is the only existing-test change, and it is the last test.
- Ship SKILL.md fix corrects behavior to match documented precedence semantics.
- New files (`test-integration.sh`, `ARCHETYPE_GUIDE.md`) do not affect existing functionality.

---

## Trap Handler Soundness

The plan's trap handler implementations were reviewed for correctness:

**`test_skill_generator.sh` handler (WG-1):**
```bash
cleanup_on_exit() {
    rm -rf "$SKILLS_DIR/skills/test-validate-invalid" 2>/dev/null || true
}
trap cleanup_on_exit EXIT INT TERM
```
- Correct: fires on EXIT (normal + error exits), INT (Ctrl+C), TERM (kill).
- Idempotent: `rm -rf` on non-existent path returns 0; `2>/dev/null || true` suppresses edge cases.
- Scoped: only cleans `skills/test-validate-invalid/`, does not interfere with `$TEST_DIR` cleanup in Test 50.
- Placement: "near the top of the script, after variable definitions" -- correct, since `$SKILLS_DIR` must be defined first (line 29).

**`test-integration.sh` handler (WG-3):**
```bash
cleanup() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
    rm -rf "$DEPLOY_DIR/smoke-coord" 2>/dev/null || true
    rm -rf "$DEPLOY_DIR/smoke-pipe" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
```
- Correct: same signal set, same idempotent pattern.
- Complete: covers all three artifact directories the script creates.
- No source-tree modifications: the integration test never writes to `skills/` (Rev 2 fix).

**Edge case -- nested trap handlers:** Integration Test 4 runs `test_skill_generator.sh` as a subprocess. The subprocess has its own trap handler. Trap handlers are per-process, so the parent integration test's handler and the child unit test's handler operate independently. No conflict.

---

## Integration Test Feasibility (Rev 2 Replacements)

**Test 3 (Full lifecycle):** Generate-validate-deploy-undeploy cycle. Verified that all individual commands work:
- `generate_skill.py` with `-t $TEST_DIR --force` writes to `/tmp`, not `skills/`.
- `validate_skill.py` accepts arbitrary paths.
- Manual `mkdir -p` + `cp` to `~/.claude/skills/` works for deployment.
- `rm -rf` + `[ ! -d ]` verifies undeployment.

**Test 4 (Meta-test):** Runs `test_skill_generator.sh` as a subprocess. This is straightforward -- the script exits 0 on success, 1 on failure. The `run_test` harness captures the exit code correctly. The only consideration is that Test 4 will take ~10-15 seconds (the full unit suite), making it the slowest integration test.

Both replacement tests are feasible and provide genuinely different coverage from WG-1's `--validate` tests.

---

## Verdict: PASS

The revised plan resolves both Round 1 Major concerns completely:
1. Test count is now accurately documented as 44 runtime tests.
2. Trap handlers are added to both test scripts with correct signal handling and idempotent cleanup.

The three new Minor concerns do not block implementation. The plan's four improvements are independent, low-risk, and well-specified. All proposed test commands have been verified against the live codebase.
