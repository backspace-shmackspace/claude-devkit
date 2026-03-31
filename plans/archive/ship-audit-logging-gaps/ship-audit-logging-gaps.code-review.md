# Code Review: ship-audit-logging-gaps (Revision 2)

**Plan:** `plans/ship-audit-logging-gaps.md`
**Files reviewed:**
- `scripts/emit-audit-event.sh`
- `skills/ship/SKILL.md`
- `scripts/test-integration.sh`

**Verdict: PASS**

---

## Critical Findings (Must Fix)

None.

---

## Major Findings (Should Fix)

None.

---

## Minor Findings (Consider)

None.

---

## Positives

**PREV_HMAC "genesisgenesis" bug is fixed correctly.** The previous review's C1 finding identified that `tail -1 "$AUDIT_LOG" 2>/dev/null | python3 -c ...` produced `PREV_HMAC="genesisgenesis"` on first invocation under `set -o pipefail`, because `tail` exits non-zero on a missing file and the `|| echo "genesis"` fallback appended a second `"genesis"`. The fix (lines 194–210 of `emit-audit-event.sh`) wraps the entire `tail` pipeline in `if [[ -f "$AUDIT_LOG" ]]; then ... else PREV_HMAC="genesis"; fi`. This eliminates the `|| echo "genesis"` fallback entirely on the success path. The additional `[[ -z "$PREV_HMAC" ]] && PREV_HMAC="genesis"` guard (line 207) handles the edge case where `python3` produces empty output (e.g., log file exists but contains only whitespace). The fix exactly matches the specification in C1 and makes L3 chains verifiable by external tools using `"genesis"` as the sentinel.

**SEQUENCE wc -l first-invocation fix remains correct.** The conditional (lines 124–128) — `if [ -f "$AUDIT_LOG" ]; then SEQUENCE=...; else SEQUENCE=1; fi` — is unchanged and correct. The `2>/dev/null` was correctly absent from the success path (added only for error suppression when it was needed).

**Header comment fix is correct.** Line 12 of `test-integration.sh` now reads `# 8 tests:`, matching the actual TOTAL_COUNT of 8 increments (run_test calls 1, 2, 3, 4, 6, 7, 8 plus the inline Test 9 block). This resolves the minor m1 finding.

**Step 6 FAIL path is correctly structured.** The finalization block is guarded with "Execute the following finalization block ONLY if the commit gate verdict is PASS or PASS_WITH_NOTES" (line 1129 of SKILL.md). The FAIL path (lines 1263–1280) has its own dedicated bash block that emits `step_end`, then `run_end`, then `rm -f` — in the correct order. The state file exists at this point because the finalization block was skipped.

**Step 7 state file lifecycle is correct.** The `rm -f ".ship-audit-state-${RUN_ID}.json"` appears at line 1380 (after the `step_end` emission at line 1376), making it the final action of the PASS path. Step 7 emit calls will succeed because the state file is alive throughout Step 7. The FAIL path (Step 6) still performs cleanup at Step 6 since Step 7 is skipped.

**Step 4 retrospective marker structure is correct.** All four substeps (4a, 4b, 4c, 4d) emit `step_start` / verdict-or-security_decision / `step_end` triples during the coordinator's sequential result evaluation phase. The comment block explaining the retrospective nature and timing caveat is present and accurate. Identifiers match the parent plan's schema (`step_4a_code_review`, `step_4b_tests`, `step_4c_qa`, `step_4d_secure_review`).

**Step 5 conditional language is clear.** The emit calls include explicit prose: "These emit calls are conditional on Step 5 actually executing. If Step 4 code review returned PASS, skip this entire Step 5 section including these emit calls." The step_end appears after the "Max 2 revision rounds" paragraph and before Step 6 — correct placement.

**Test output capture and temp-file python3 patterns are correct.** The `run_test` function captures stdout/stderr to a temp file and displays the first 20 lines on failure. Tests G, H, and J all use heredoc-written temp python3 scripts with unquoted delimiters for shell variable expansion. No triple-level escaping is present in any test.

**Known coder pattern verification:** Checked all entries in `## Coder Patterns > ### Missed by coders, caught by reviewers`:
- "Event emitted after the resource it depends on has been deleted" — FIXED. `step_end` now precedes `rm -f` on both PASS and FAIL paths.
- "Plan-specified instrumentation points partially skipped" — FIXED. Steps 4a–4d, Step 5, Step 6 FAIL path are all instrumented.
- "rm -rf in cleanup blocks under set -e without || true guard" — Not applicable to the changes in this plan.
- All other known patterns — not present in the changed files.

**Checked against `## Reviewer Patterns > ### Overcorrected`:** No self-refuted cosmetic observations in this review. All findings in the previous round were real and have been addressed.

---

## Required Actions

None. Both findings from the previous review (C1 PREV_HMAC bug, m1 header comment) are fixed correctly. All acceptance criteria from the plan are met.
