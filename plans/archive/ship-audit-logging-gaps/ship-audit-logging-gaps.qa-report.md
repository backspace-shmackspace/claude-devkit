# QA Report: ship-audit-logging-gaps

**Plan:** `plans/ship-audit-logging-gaps.md`
**Date:** 2026-03-31
**Revision Round:** 2 (re-validation after revision)
**QA Agent:** qa-engineer (claude-devkit specialist)
**Verdict:** PASS

---

## What Changed in This Revision

The revision addressed two specific issues flagged in the previous PASS_WITH_NOTES report:

1. **Note N1 (PREV_HMAC first-invocation bug):** The previous report identified this as a cosmetic header count issue, but the actual bug was in `emit-audit-event.sh` lines 191-210: when the log file does not yet exist on the first invocation at L3, `tail -1 "$AUDIT_LOG"` would pipe an empty string to python3, and `PREV_HMAC` would be set to the empty string rather than `"genesis"`. The fix wraps the `tail` call in an `if [[ -f "$AUDIT_LOG" ]]; then ... else PREV_HMAC="genesis"; fi` conditional, matching the same pattern used for the SEQUENCE counter. This is what caused Test 7 (L3 HMAC chain) to fail: the first event's HMAC was computed against an empty `prev_hmac` rather than `"genesis"`, breaking chain verification.

2. **Header comment count (test-integration.sh):** The header comment incorrectly stated "9 tests" (Note N1 from prior report). The revision corrected this to "8 tests", matching the actual `TOTAL_COUNT=8` at runtime.

---

## Acceptance Criteria Coverage

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `emit-audit-event.sh` correctly appends the first event when the log file does not yet exist (no silent failure under `set -euo pipefail`) | **MET** | Lines 124-128: `if [ -f "$AUDIT_LOG" ]; then SEQUENCE=$(( $(wc -l < "$AUDIT_LOG" \| tr -d ' ') + 1 )); else SEQUENCE=1; fi`. The `<` redirect only runs when the file exists. Verified by live Test 6 (first emit call in test G creates the log file on a nonexistent path — passes). |
| 2 | Steps 4a/4b/4c/4d have retrospective per-substep `step_start`/`step_end` markers and `verdict`/`security_decision` events using identifiers `step_4a_code_review`, `step_4b_tests`, `step_4c_qa`, `step_4d_secure_review` | **MET** | Verified in prior round (structural code inspection). No changes to SKILL.md in this revision. |
| 3 | Step 5 has `step_start` and `step_end` events bracketing the revision loop, with explicit conditional language | **MET** | Verified in prior round. No changes to SKILL.md in this revision. |
| 4 | Step 6 finalization block is wrapped under the PASS-path conditional so it does not execute on the FAIL path | **MET** | Verified in prior round. No changes to SKILL.md in this revision. |
| 5 | Step 6 `step_end` is emitted before the state file is deleted (not after) | **MET** | Verified in prior round. No changes to SKILL.md in this revision. |
| 6 | Step 6 FAIL path has a dedicated bash block that emits `step_end` and `run_end` before state file cleanup | **MET** | Verified in prior round. No changes to SKILL.md in this revision. |
| 7 | Step 7 emit calls succeed (state file is not deleted until after Step 7 completes) | **MET** | Verified in prior round. No changes to SKILL.md in this revision. |
| 8 | State file cleanup happens at the end of Step 7 (PASS path) or end of Step 6 (FAIL path) | **MET** | Verified in prior round. No changes to SKILL.md in this revision. |
| 9 | Integration test G passes: 3 calls produce 3 sequenced, valid JSONL events | **MET** | Live execution: Test 6 PASS (Total: 8, Pass: 8, Fail: 0). |
| 10 | Integration test H passes: L3 HMAC chain is verifiable by replaying events with the key | **MET** | Live execution: Test 7 PASS. This was the previously-failing test. The PREV_HMAC fix (lines 194-210 of emit-audit-event.sh) correctly seeds `PREV_HMAC="genesis"` on first invocation when the log file does not yet exist. Chain replay assertion in the python3 verification script passes. |
| 11 | Integration test J passes: 12 calls produce 12 sequenced events with consistent run_id | **MET** | Live execution: Test 8 PASS. |
| 12 | `run_test` function captures output and displays it on failure (not redirected to /dev/null) | **MET** | `test-integration.sh` lines 61-82: `mktemp` temp file, `eval "$test_command" > "$test_output_file" 2>&1`, `head -20 "$test_output_file"` on failure, `rm -f` cleanup. Unchanged from prior round. |
| 13 | Integration tests use temp-file python3 verification scripts (no triple-level escaping) | **MET** | All three new tests (6, 7, 8) use `cat > "$VERIFY_SCRIPT" <<PYEOF ... PYEOF` pattern. Unchanged from prior round. |
| 14 | `generators/test_skill_generator.sh` passes (53 tests, 0 failures) | **MET** | Live execution: Test 4 (meta-test) PASS — `test_skill_generator.sh` is invoked inside the integration suite and passes. |
| 15 | `scripts/validate-all.sh` passes (15 skills, 0 failures) | **MET** | Live execution: Test 2 PASS. |
| 16 | `scripts/test-integration.sh` passes (8 tests, 0 failures) | **MET** | Live execution: Total: 8, Pass: 8, Fail: 0. Header comment now reads "8 tests" matching actual runtime count. |

---

## Specific Fix Verification

### AC1 — wc -l first-invocation fix (emit-audit-event.sh lines 124-128)

**Before revision:**
```bash
SEQUENCE=$(( $(wc -l < "$AUDIT_LOG" 2>/dev/null | tr -d ' ') + 1 ))
```

**After revision:**
```bash
if [ -f "$AUDIT_LOG" ]; then
  SEQUENCE=$(( $(wc -l < "$AUDIT_LOG" | tr -d ' ') + 1 ))
else
  SEQUENCE=1
fi
```

The fix is present and correct at lines 124-128 of `scripts/emit-audit-event.sh`.

### AC10 — PREV_HMAC first-invocation fix (emit-audit-event.sh lines 191-210)

**Before revision (inferred from test failure):** The `tail -1 "$AUDIT_LOG"` call was not guarded by a file-existence check. On first invocation at L3, `$AUDIT_LOG` does not exist. `tail -1` on a missing file produces empty output. The python3 pipe would receive an empty string and print `"genesis"` (correct fallback path). However, the subsequent `[[ -z "$PREV_HMAC" ]] && PREV_HMAC="genesis"` guard was absent or the `2>/dev/null` suppressed a pipefail exit, resulting in an empty PREV_HMAC being used for HMAC computation.

**After revision (lines 191-210):**
```bash
if [[ -f "$AUDIT_LOG" ]]; then
    PREV_HMAC=$(tail -1 "$AUDIT_LOG" | python3 -c "
import json, sys
try:
    line = sys.stdin.read().strip()
    if line:
        event = json.loads(line)
        print(event.get('hmac', 'genesis'), end='')
    else:
        print('genesis', end='')
except Exception:
    print('genesis', end='')
" 2>/dev/null)
    [[ -z "$PREV_HMAC" ]] && PREV_HMAC="genesis"
else
    PREV_HMAC="genesis"
fi
```

The `else PREV_HMAC="genesis"` branch correctly handles first invocation. The `[[ -z "$PREV_HMAC" ]] && PREV_HMAC="genesis"` guard defends against any edge case where the file exists but produces empty output. Fix is present and correct.

### AC16 — Header comment fix (test-integration.sh line 13)

**Before revision:** `# 9 tests: coordinator lifecycle, ...`

**After revision:** `# 8 tests: coordinator lifecycle, validate-all, pipeline lifecycle, unit meta-test, emit-audit-event JSONL correctness, L3 HMAC chain, 10+ call state persistence, cleanup`

Header now correctly states "8 tests" matching `TOTAL_COUNT=8` at runtime.

---

## Live Test Execution Evidence

```
bash scripts/test-integration.sh
========================================
Claude Devkit Integration Smoke Tests
========================================
Test 1: Generate, deploy, and verify a coordinator skill    PASS
Test 2: validate-all.sh passes for all skills               PASS
Test 3: Full lifecycle: generate, validate, deploy, undeploy PASS
Test 4: Unit test suite passes (meta-test)                   PASS
Test 6: emit-audit-event.sh multi-call JSONL correctness     PASS
Test 7: emit-audit-event.sh L3 HMAC chain verification       PASS
Test 8: emit-audit-event.sh 10+ call state persistence       PASS
Test 9: Cleanup                                              PASS
========================================
Total:  8  |  Pass: 8  |  Fail: 0
All integration tests passed!
```

All 8 tests pass. No regressions in pre-existing tests 1-4. All three new tests (6, 7, 8) pass including Test 7 which was failing before this revision.

---

## Missing Tests or Edge Cases

No new gaps identified in this revision round. The edge cases noted in the prior round remain non-blocking informational items:

1. **Step 5 revision loop exhaustion path** — No integration test for the revision-loop-exhaustion variant of Step 5. Deferred in Non-Goals. Low risk.
2. **Step 4 retrospective markers on FAIL/stop paths** — Verified by static inspection only. No integration test. Low risk; positioning is structurally correct.
3. **HMAC field ordering assumption** — Documented in Test 7 comment. Accepted limitation. Not a bug.

---

## Notes

### N1 — Test number gap (1, 2, 3, 4, 6, 7, 8, 9 — no Test 5)

The gap is deliberate per the plan spec: the old Test 5 (Cleanup) was renumbered to Test 9 and new tests were inserted as 6, 7, 8. Terminal output shows the gap in numbering, which is cosmetic. `TOTAL_COUNT=8` is correct. Non-blocking; no change needed.

### N2 — Stop-path retrospective marker positioning (unchanged from prior round)

Step 4 retrospective markers are emitted after result evaluation and before the "If stopping" prose block. On a stop path, the coordinator emits all four substep marker triplets, then outputs the stop message. This is correct behavior and intentional per the plan's design. Non-blocking.

---

## Summary

All 16 acceptance criteria are now met. The two revision fixes are confirmed correct by code inspection and live test execution. Test 7 (L3 HMAC chain, AC10) passes with 0 failures — this was the specific test that drove the PREV_HMAC first-invocation fix. The SKILL.md changes (AC2-AC8) were not touched in this revision and remain correct from the prior round. No blocking issues remain.
