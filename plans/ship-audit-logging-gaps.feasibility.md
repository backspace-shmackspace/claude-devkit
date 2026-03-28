# Feasibility Review: Ship Audit Logging Gaps (Rev 2)

**Plan:** `plans/ship-audit-logging-gaps.md` (Rev 2)
**Reviewed:** 2026-03-28
**Reviewer:** Feasibility analysis (source-verified, revision review)
**Verdict:** PASS

---

## Summary

Rev 2 of the plan addresses all three major concerns (M1, M2, M3) from the Rev 1 feasibility review and incorporates red team findings (F1-F5) and librarian edits. All source claims were re-verified against the current files. The revised plan is well-scoped, the proposed changes are technically sound, and the implementation complexity remains low-medium. No new blocking concerns were identified.

---

## Previous Concerns Status

### M1: Test H HMAC chain verification may fail due to JSON key ordering non-determinism

**Status: ADDRESSED.**

Rev 2 (plan lines 305-306) adds an explicit comment in Test H noting the CPython 3.7+ insertion-order assumption: "HMAC key ordering assumption: python3 json.dumps preserves insertion order on CPython 3.7+; test includes a comment noting this." The test code at plan lines 415-416 includes the comment directly in the python3 verification script.

Source verification confirms the approach is sound: `emit-audit-event.sh` line 178 produces `FULL_EVENT` via `json.dumps(merged, separators=(',', ':'))` before HMAC computation at line 203. The test strips `hmac` from the parsed event and re-serializes with the same `json.dumps(..., separators=(',', ':'))`. On CPython 3.7+ (dict preserves insertion order, and the `hmac` key is always last because it is added after initial serialization at line 210), the reconstruction is deterministic. The comment is sufficient mitigation.

### M2: Step 5 emit calls placement is incomplete for the revision loop's internal structure

**Status: ADDRESSED.**

Rev 2 (plan lines 153-185) adds explicit conditional language: "These emit calls are part of Step 5 and MUST NOT execute if Step 5 is skipped" (line 155) and "If Step 4 code review returned PASS, skip this entire Step 5 section including these emit calls" (line 164). The plan also notes (line 155) that the `step_start`/`step_end` pair brackets the entire Step 5 section, and the conditional trigger at the top of Step 5 controls whether the section (including emit calls) executes.

The Rev 1 concern about asymmetric emit on mid-step failure (e.g., commit in 5a fails after step_start) remains a pre-existing pattern consistent with other steps. Rev 2 does not claim to fix this and explicitly notes it is out of scope. This is acceptable.

### M3: Step 6 FAIL path does not emit verdict events for Step 4 sub-results

**Status: ADDRESSED by design change (F1/F2).**

Rev 2 makes two structural changes that resolve this concern:

1. **F1 (plan lines 82-150):** Step 4 now emits retrospective per-substep markers (`step_start`/`step_end` + verdict events for 4a-4d) during the coordinator's sequential result evaluation, after all parallel Tasks complete. These emit calls execute before the stop/continue decision, so they fire on both the PASS and early-stop paths.

2. **F2 (plan lines 187-238):** Step 6 finalization block is wrapped under the PASS-path conditional. The FAIL path gets a dedicated bash block (plan lines 224-234) that emits `step_end` and `run_end` before state file cleanup. Since the finalization block (which contains `rm -f`) is skipped on the FAIL path, the state file is guaranteed to exist for the FAIL-path emit calls.

Source verification confirms this is correct: the current `rm -f` is at SKILL.md line 1110 inside the finalization bash block (lines 1057-1113). Wrapping this block under `**If PASS or PASS_WITH_NOTES:**` and adding a separate FAIL-path block is a clean structural fix.

---

## Rev 1 Minor Concerns Status

### m1: Test output suppression masks debugging information

**Status: FIXED.** Rev 2 (plan lines 274-291) modifies `run_test` to capture output to a temp file and display the first 20 lines on failure instead of redirecting to `/dev/null`. This directly addresses the concern.

### m2: Integration tests use `$REPO_DIR` inside single-quoted strings

**Status: ACCEPTABLE (unchanged).** The `$REPO_DIR` references remain inside the eval context where they expand correctly. The tests are well-specified with exact `run_test` invocations that can be verified by inspection.

### m3: Test cleanup is best-effort

**Status: ACCEPTABLE (unchanged).** The test directory is cleaned at test start (`rm -rf "$TEST_DIR"` at test-integration.sh line 45), and the trap handler cleans up on exit. Mid-test failures leave small temp files that are cleaned on the next run.

### m4: No version bump justification

**Status: ACCEPTABLE (unchanged, documented).** Plan lines 631 explicitly documents the justification in the Deviations table.

### m5: Step 2a vs Step 3a reference

**Status: NOT ADDRESSED but irrelevant.** The plan's Step 5 text (line 921 in SKILL.md) references "Step 2a" but the current SKILL.md uses "Step 3a." This is pre-existing text not modified by this plan, so it remains a cosmetic issue outside scope.

---

## New Concerns

### Major

None.

### Minor

**m1: State file lifetime extension creates a wider cleanup gap on abnormal termination.**

Moving state file cleanup from Step 6 (line 1110) to after Step 7 means that if the /ship coordinator crashes between Steps 6 and 7, the state file persists on disk. This is low impact because: (a) state files are small JSON files, (b) they are per-run (unique RUN_ID), (c) Step 0 pre-flight does not clean them up (it only cleans worktree tracking files), and (d) they do not interfere with subsequent runs. However, over many abnormal terminations, these could accumulate. A future cleanup enhancement could add `rm -f .ship-audit-state-*.json` to the Step 0 stale artifact cleanup block. Not blocking.

**m2: Step 4 retrospective markers have a timing caveat that could mislead audit consumers.**

Plan lines 85-86 document this: "The retrospective markers reflect the order in which the coordinator evaluates results, not the actual parallel execution timing." This is clearly documented in both the plan and the proposed SKILL.md text (plan lines 98-100). However, the `timestamp` field in each event (generated by `emit-audit-event.sh` at line 127) will contain the evaluation-time timestamp, not the Task execution time. An audit consumer who computes step duration from `step_start.timestamp` to `step_end.timestamp` for Step 4 substeps will get the coordinator's evaluation duration (milliseconds), not the actual review/test/QA duration (seconds to minutes). This is inherent to the retrospective design and well-documented. Not blocking.

**m3: The `run_test` modification (plan lines 274-291) uses `head -20` which may truncate useful python3 traceback output.**

Python tracebacks often appear at the end of output. If a test produces more than 20 lines of output before the traceback, the truncation will hide the actual error. Using `tail -20` instead of (or in addition to) `head -20` would better capture assertion failures. This is a minor usability issue and does not affect correctness.

---

## Source Verification (Rev 2 Claims)

### Claim: Step 4 (lines 772-906) has zero emit-audit-event.sh calls

**Verified: TRUE.** Confirmed by reading SKILL.md lines 772-906. No `emit-audit-event.sh` calls exist in the Step 4 section. The Result evaluation section (lines 863-906) contains only prose and decision matrices.

### Claim: Step 5 (lines 908-969) has zero emit-audit-event.sh calls

**Verified: TRUE.** Confirmed by reading SKILL.md lines 908-969. No `emit-audit-event.sh` calls exist in the Step 5 section.

### Claim: Step 6 step_end at lines 1185-1188, after rm -f at line 1110

**Verified: TRUE.** The `rm -f ".ship-audit-state-${RUN_ID}.json"` is at line 1110. The `step_end` emit call is at lines 1185-1188, which is 75 lines later and outside the finalization bash block (which ends at line 1113). The emit call will always be silently dropped.

### Claim: Step 7 step_start at lines 1204-1206, step_end at lines 1288-1290

**Verified: TRUE.** Both emit calls reference `.ship-audit-state-${RUN_ID}.json` which is deleted at line 1110 (Step 6 finalization). Both will be silently dropped because `emit-audit-event.sh` exits 0 when the state file is missing (line 79-81).

### Claim: emit-audit-event.sh line 124 wc -l bug

**Verified: TRUE.** Line 124 is exactly:
```bash
SEQUENCE=$(( $(wc -l < "$AUDIT_LOG" 2>/dev/null | tr -d ' ') + 1 ))
```
Under `set -euo pipefail` (line 30), the `<` redirect on a nonexistent file causes immediate script exit. The proposed `if [ -f "$AUDIT_LOG" ]` conditional (plan lines 68-72) is the correct fix.

### Claim: test-integration.sh run_test redirects to /dev/null at line 61

**Verified: TRUE.** Line 61 is `eval "$test_command" > /dev/null 2>&1`. The proposed temp-file capture approach is correct.

### Claim: test-integration.sh has 5 tests

**Verified: TRUE.** Tests 1-4 use `run_test`, Test 5 is inline cleanup. Header comment on line 12 says "5 tests."

---

## Implementation Complexity Assessment (Updated)

| Change | Rev 1 Estimate | Rev 2 Estimate | Notes |
|--------|---------------|---------------|-------|
| Fix `wc -l` bug | Trivial | Trivial | Unchanged. |
| Step 4 emit calls | ~30 lines | ~50 lines | Increased due to retrospective per-substep markers (4 substeps x 3 emit calls each = 12 emit calls, plus prose). Well-specified. |
| Step 5 emit calls | ~10 lines | ~15 lines | Slightly increased due to explicit conditional language. |
| Step 6 structural fix | ~15 lines | ~30 lines | Increased due to PASS-path/FAIL-path bifurcation and dedicated FAIL-path bash block. Clear specification. |
| Step 7 state cleanup | ~2 lines | ~2 lines | Unchanged. |
| run_test modification | N/A (new in Rev 2) | ~8 lines | Simple change. |
| Integration tests G/H/J | ~110 lines | ~120 lines | Slightly increased due to temp-file python3 scripts. Eliminates escaping concerns. |

**Overall: Low-Medium complexity.** The increase from Rev 1 is modest and well-justified by the structural improvements. The temp-file python3 approach for tests (F4) eliminates the highest-risk implementation detail (triple-level escaping).

---

## Breaking Changes / Backward Compatibility

**No breaking changes identified.** Same assessment as Rev 1:

- `emit-audit-event.sh` fix is a bug fix (first event was silently dropped; now correctly written)
- State file lifetime extension is invisible to external consumers (per-run filename isolation)
- New emit calls add events to the audit log; no tooling depends on specific event counts
- Integration tests 6/7/8 are additive; Test 5 renumbered to Test 9

---

## Verdict: PASS

All three major concerns from the Rev 1 review have been addressed. The retrospective per-substep markers (F1) are a well-reasoned design that preserves the parent plan's schema contract while respecting the parallel Task dispatch constraint. The Step 6 structural fix (F2) correctly bifurcates the PASS and FAIL paths. The test improvements (F3/F4) reduce debugging friction and eliminate escaping fragility. No new blocking concerns were identified. The plan is ready for implementation.

---

<!-- Context Metadata
reviewed_at: 2026-03-28
plan_file: plans/ship-audit-logging-gaps.md
plan_revision: 2
source_files_verified: scripts/emit-audit-event.sh, skills/ship/SKILL.md, scripts/test-integration.sh
verdict: PASS
previous_concerns_addressed: M1 (comment added), M2 (conditional language), M3 (structural fix)
concerns_critical: 0
concerns_major: 0
concerns_minor: 3
-->
