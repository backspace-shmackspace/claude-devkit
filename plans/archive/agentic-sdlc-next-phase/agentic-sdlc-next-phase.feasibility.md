# Feasibility Review: Agentic SDLC Next Phase (Rev 2)

**Plan:** `./plans/agentic-sdlc-next-phase.md` (Rev 2)
**Reviewer:** Feasibility Analyst
**Date:** 2026-03-27
**Previous review:** Rev 1 feasibility (PASS with 3M/7m)
**Verdict:** PASS

---

## Summary

Rev 2 adequately addresses all three Major concerns (M1, M2, M3) from the Rev 1 review and resolves most Minor concerns. The revisions are precise and well-targeted. Two new minor concerns are introduced by the revisions, neither of which changes the verdict. The plan remains technically sound, additive, and backward-compatible.

---

## Rev 1 Major Concerns: Resolution Status

### M1. `validate-all.sh` glob with empty directory (RESOLVED)

**Rev 1 concern:** The glob `"$REPO_DIR"/skills/*/SKILL.md` could match zero files, causing the `for` loop to iterate over a literal glob string.

**Rev 2 resolution:** The plan now explicitly includes `shopt -s nullglob` in the script (line 758) and documents the rationale (line 827: "prevents glob from expanding to literal string when no matches"). The `[ -f "$skill" ]` guard inside loops was removed since `nullglob` makes it redundant (line 827).

**Verification:** Tested `shopt -s nullglob` on the target system (bash 5.3.9). A glob against a nonexistent path produces zero iterations, which is the correct behavior. Resolved.

### M2. `deploy.sh --validate` argument parsing complexity (RESOLVED)

**Rev 1 concern:** The `case` statement structure makes `--validate` flag combinations non-trivial. The Rev 1 plan did not specify how `--validate` interacts with `--contrib`, `--all`, or single-skill arguments.

**Rev 2 resolution:** The plan now provides a complete pre-processing loop (lines 262-276) that extracts `--validate` from `$@` before the `case` statement runs, and includes a full interaction matrix (lines 280-292) covering all 9 flag combinations.

**Verification:** Reviewed the pre-processing approach against the actual `deploy.sh` structure (lines 148-198). The approach is correct -- `set -- "${ARGS[@]}"` replaces the original `$@` with the filtered argument list, and the existing `case "${1:-}"` dispatch proceeds unchanged. Tested `set -- "${ARGS[@]}"` with an empty array under `set -euo pipefail` on bash 5.3.9: it correctly sets `$#` to 0 and `${1:-}` to empty, which maps to the `""` branch (deploy all core). Resolved.

### M3. Test cleanup renumbering not specified (RESOLVED)

**Rev 1 concern:** The plan said "renumber the cleanup test" but did not specify the target number.

**Rev 2 resolution:** The plan now explicitly specifies "Test 46" as the cleanup target in multiple locations (lines 216, 217, 218, 234, 735). The total test count is clearly stated as 46 throughout. Resolved.

---

## Rev 1 Minor Concerns: Resolution Status

| # | Concern | Status | Notes |
|---|---------|--------|-------|
| m1 | Ambiguous test count "45+" | **Resolved** | Rev 2 uses "46" consistently throughout (lines 218, 329, 359, 468, 527, 734). |
| m2 | `validate-all.sh` claims to validate agents but does not | **Resolved** | Rev 2 scopes script to skills only (line 224: "Agent templates are not validated here") with documented rationale about placeholder variables. |
| m3 | `generate_agents.py` exit code fix incomplete for unknown types | **Resolved** | Rev 2 adds an `unknown_types` counter (lines 300-305, 876-878) alongside `write_failures`, and the return condition checks both (line 897). |
| m4 | `validate-all.sh` suppresses all output on failure | **Resolved** | Rev 2 shows full validation output on failure by re-running the validator with output visible (lines 779-780: `python3 ... \| sed 's/^/    /'`). |
| m5 | Undefined `BOLD` variable in test script | **Not addressed** | Pre-existing bug. Not in scope for this plan. Acceptable. |
| m6 | Section 3a header remains despite being deferred | **Resolved** | Rev 2 marks 3a with "DEFERRED" heading (line 311) and explains rationale inline. |
| m7 | Stale `/dream` reference in parent plan | **Not addressed** | Correctly identified as out-of-scope (parent plan, not this plan). Acceptable. |

---

## New Concerns Introduced by Rev 2

### Critical

None.

### Major

None.

### Minor

**m8. `validate-all.sh` re-runs validator on failure, which may produce different output if the validator has non-deterministic behavior.**

The proposed failure handling (lines 774-780) runs `python3 "$VALIDATE_PY" "$skill_path" $STRICT_FLAG > /dev/null` in the `if` conditional, and if it fails, re-runs the same command with output visible (`python3 "$VALIDATE_PY" "$skill_path" $STRICT_FLAG 2>&1 | sed 's/^/    /'`). The validator is deterministic (it parses YAML and checks patterns), so this is safe in practice. However, the double-execution adds ~1 second per failure. With 16 skills total, worst case is 16 additional seconds -- negligible.

No adjustment needed. Noting for completeness.

**m9. The `deploy.sh` validation integration inserts into `deploy_skill()` but not `deploy_contrib_skill()`.**

The plan (lines 856-863) specifies adding the validation check to `deploy_skill()` before the `cp` command. However, `deploy.sh` has a separate `deploy_contrib_skill()` function (lines 44-58) that is structurally identical but operates on `$CONTRIB_DIR`. When `--validate --contrib journal` is invoked, `deploy_contrib_skill()` is called, not `deploy_skill()`. The validation check must also be added to `deploy_contrib_skill()` for `--validate` to work with contrib skills.

The interaction matrix (lines 288-292) includes `--validate --contrib` as a valid combination, but the implementation instructions only modify `deploy_skill()`. An implementer will likely notice this during testing (the `--validate --contrib` test would fail), but the plan should specify both insertion points.

**Recommended adjustment:** Add the same validation block to `deploy_contrib_skill()` before its `cp` command. Alternatively, extract a shared `maybe_validate()` helper called by both functions. This is a 5-line addition.

---

## Assumptions Re-verified

All 6 assumptions from Rev 1 remain valid. No new assumptions were introduced in Rev 2.

| # | Assumption | Status |
|---|-----------|--------|
| 1 | Phase A and Phase B are stable and deployed | Still confirmed |
| 2 | Parent plan Phase C spec is authoritative source | Still confirmed |
| 3 | All 13 core skills pass `validate-skill` individually | Still confirmed |
| 4 | Existing test suite passes at 33 tests | Still confirmed |
| 5 | Python 3 is available | Still confirmed |
| 6 | `validate_agent.py` exists and is functional | Still confirmed |

---

## Complexity Assessment (Unchanged from Rev 1)

| Stream | Estimated Effort | Risk | Notes |
|--------|-----------------|------|-------|
| Stream 1: Phase C | 1 session | Low | Template insertions at well-defined anchor points. CLAUDE.md edits are routine. |
| Stream 2: Quality Infra | 1-2 sessions | Low-Medium | Test expansion is mechanical. `validate-all.sh` is straightforward. `deploy.sh --validate` flag is now well-specified (M2 resolved). Generator fix is a 5-line change. |
| Stream 3: Maturity | 0.5 sessions (can combine with Stream 2) | Low | Documentation-only. |

**Overall estimate of 2-3 sessions remains realistic.** The M2 resolution (pre-processing loop with interaction matrix) reduces implementation risk for the deploy.sh change compared to Rev 1.

---

## Breaking Changes

None. Assessment unchanged from Rev 1. All changes remain additive or bug fixes.

---

## Test Coverage Assessment

The test strategy is adequate. The Rev 1 recommendation to add a "Test 47: validate-all returns exit 0" was not incorporated into Rev 2. This remains a nice-to-have but is not blocking -- `validate-all.sh` is tested manually in the verification steps (lines 908-909).

---

## Verdict: PASS

All three Rev 1 Major concerns (M1, M2, M3) are resolved. Five of seven Rev 1 Minor concerns are resolved; the remaining two (m5, m7) are correctly out of scope. Two new Minor concerns are introduced (m8, m9), of which m9 (missing validation in `deploy_contrib_skill()`) should be addressed during implementation but does not change the overall assessment. No Critical or Major issues remain. The plan is ready for implementation.
