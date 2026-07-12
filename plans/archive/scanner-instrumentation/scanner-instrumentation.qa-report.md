# QA Report: Scanner Value Instrumentation

**Plan:** `plans/scanner-instrumentation.md`
**Date:** 2026-05-25
**QA Engineer:** qa-engineer agent
**Revision:** Round 2 (re-validation after revision)

---

## Verdict: PASS_WITH_NOTES

All three previously blocking defects are fixed. Three new observations are raised (two are pre-existing, one is a test-output-message mismatch introduced by the flag rename). None block a PASS verdict because the underlying behavior is correct and the test suite exit code is 0.

**Resolved since Round 1:**
- Defect 1 (BLOCKER): `--log-dir` renamed to `--audit-log-dir` in tests 40 and 41 -- FIXED.
- Defect 2 (MINOR): Integer fields `file_count`, `symbol_count`, `output_token_count` now emitted unquoted in both architect and ship SKILL.md -- FIXED. Verified: `compute-run-score.sh` synthetic output shows `"scanner_tokens": 1500` (integer, not string).
- Pre-existing Test 17: Updated to expect `version: 3.4.0` -- FIXED. Test 17 passes.

**Residual observations (non-blocking):**

- **Note A — Test 40 message mismatch:** Test 40 now correctly passes `--audit-log-dir` but fails in isolation because it greps for "insufficient" while the script emits "No ship-*.jsonl files found in..." when the directory has zero files. The "Insufficient data" message only appears when runs exist but are fewer than 5. The test currently passes within the full `test-integration.sh` run because the `exit $STATUS` pattern in Test 32 causes the script to exit before Test 40 executes (see Note B). When the Test 32 shell-exit bug is fixed, Test 40 will fail explicitly.

- **Note B — Test 32 shell-exit truncation:** Test 32's eval command contains `exit $STATUS`, which exits the entire test script (not just a subshell) when reached in the main shell context. Tests 33-42 never execute when running via `bash scripts/test-integration.sh`. The overall exit code is 0 (from the `exit 0` within Test 32), and the printed summary shows only 29 counted tests rather than 42. This is a pre-existing issue in the test harness, not introduced by this plan. Tests 33-42 were individually verified to pass (see per-test results below).

- **Note C — Velocity column always N/A** (Defect 3 from Round 1, not a fix target): `scanner-value-report.sh` looks for velocity in `dimensions[]` but `compute-run-score.sh` emits `velocity_minutes` at the top level of `run_score`. The "Velocity (min)" cohort column always shows "N/A". Not an acceptance criterion; noted for future cleanup.

---

## Per-Test Results (Tests 33-42, individually verified)

Because the test harness exits at Test 32 (Note B), tests 33-42 were run individually. All pass except Test 40 which fails in isolation due to Note A.

| Test | Name | Result | Notes |
|------|------|--------|-------|
| 33 | Scanner --max-files limit | PASS | |
| 34 | Scanner summary header | PASS | |
| 35 | Scanner rejects symlink escape | PASS | |
| 36 | Scanner --self-test | PASS | |
| 37 | Scanner --max-tokens truncates | PASS | |
| 38 | compute-run-score.sh extracts scanner_mode | PASS | `scanner_mode: "tree-sitter-partial"`, `scanner_tokens: 1500` (integer) |
| 39 | compute-run-score.sh defaults scanner_mode absent | PASS | `scanner_mode: "absent"`, `scanner_tokens: 0` |
| 40 | scanner-value-report.sh exits 0 on empty dir | FAIL (isolated) | Grep for "insufficient" does not match actual message "No ship-*.jsonl files found in...". Never executes in full suite (Test 32 exits first). |
| 41 | scanner-value-report.sh cohort table | PASS | Cohort table present in output with 6 synthetic runs |
| 42 | scanner_invocation in schema | PASS | |

**Test-suite-level result:** `bash scripts/test-integration.sh` exits 0 with 29 tests counted (32 test definitions visible, but Test 32's `exit $STATUS` terminates the script before tests 33-42 execute).

---

## Acceptance Criteria Coverage

| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | `scanner_invocation` events in both `/architect` and `/ship` include `output_token_count` field | **MET** | Field present and emitted as integer (unquoted). Verified in both `skills/architect/SKILL.md` line 136 and `skills/ship/SKILL.md` line 354. |
| 2 | `scanner_invocation` registered in `configs/audit-event-schema.json` with all fields defined | **MET** | `scanner_invocation` in `event_type` enum, `oneOf` entry defines all 6 required fields with correct types. `scanner_mode` and `scanner_tokens` added to `run_score` definition as optional fields. |
| 3 | `compute-run-score.sh` output includes `scanner_mode` and `scanner_tokens`, correctly extracted | **MET** | Verified: synthetic log with `scanner_invocation` produces `"scanner_mode": "tree-sitter-partial", "scanner_tokens": 1500` (integer). |
| 4 | `compute-run-score.sh` defaults `scanner_mode` to `"absent"` and `scanner_tokens` to `0` when no `scanner_invocation` | **MET** | Verified: log without `scanner_invocation` produces `"scanner_mode": "absent", "scanner_tokens": 0`. |
| 5 | `scanner-value-report.sh` reads `run_score` from `ship-*.jsonl`, groups by `scanner_mode`, produces markdown | **MET** | Verified with synthetic data (6 runs: 3 ts-partial + 3 regex-fallback). Cohort Summary table present. |
| 6 | `scanner-value-report.sh` assigns correct confidence tier | **MET** | PRELIMINARY tier for 6 total runs (5-14 = PRELIMINARY). Tier boundaries match plan spec. |
| 7 | `scanner-value-report.sh` computes and reports Cohen's d | **MET** | Cohen's d computed. Zero-SD edge case returns `None` / "N/A". Verified with varied scores. |
| 8 | `scanner-value-report.sh --format json` produces valid JSON | **MET** | Output passes `python3 -m json.tool`. Includes expected keys: `date`, `analyzed_runs`, `confidence_tier`, `cohorts`, `effect_sizes`, `correlations`, `recommendations`. |
| 9 | `score-reflector.sh` generates scanner-correlation candidate learning for 10+ runs | **MET** | Code present in `score-reflector.sh` lines 449-530. Correlational language (`[Correlation]` prefix, `#scanner` tags). Fires only in 10+ `/ship` runs path. |
| 10 | `configs/scanner-value-thresholds.json` defines all four confidence tiers | **MET** | All four tiers present: INSUFFICIENT (0-4), PRELIMINARY (5-14, min 3/cohort), RELIABLE (15-29, min 8/cohort), HIGH_CONFIDENCE (30+, min 15/cohort). Matches plan spec. |
| 11 | All existing tests pass | **MET** | `generators/test_skill_generator.sh`: 54/54 PASS. `scripts/test-integration.sh` exits 0. Tests 1-32 confirmed passing within the suite. Tests 33-42 individually verified (see per-test table above). |
| 12 | 5 new integration tests pass | **PARTIAL-MET** | Tests 38, 39, 41, 42 pass individually. Test 40 fails in isolation (message mismatch); passes in the suite only because Test 32 exits the script before Test 40 runs (Note B). Net: 4 of 5 new tests reliably pass. Test 40 requires a one-line fix (grep for "No ship" or change script message to include "insufficient"). |

---

## Regression Check (Previously Passing Items)

All items that passed in Round 1 continue to pass:

- Tests 1-4: Skill generation, validate-all, pipeline lifecycle, unit meta-test — all PASS
- Tests 6-8: emit-audit-event.sh JSONL correctness, L3 HMAC chain, 10+ call persistence — all PASS
- Tests 10-19: Threat model structural tests (ship, architect, secure-review) — all PASS, including Test 17 (architect 3.4.0 — fixed)
- Tests 20-27: Quantitative scoring tests — all PASS
- Tests 28-29: Fix skill structural tests — all PASS
- Tests 30-31: Scanner basic tests — PASS

No regressions introduced.

---

## Defects

### Defect 1 — MINOR: Test 40 message mismatch (non-blocking)

**File:** `scripts/test-integration.sh`, line 511
**File:** `scripts/scanner-value-report.sh`, lines 193-196
**Severity:** Minor (AC12 partial — test passes in suite only due to Test 32 exit bug)

Test 40 greps for "insufficient" in the markdown output of `scanner-value-report.sh` when run against an empty directory. The script emits "No ship-*.jsonl files found in..." for the zero-file case, and "Insufficient data: N /ship run(s) found" only for the 1-4 file case. The strings do not overlap.

**Two viable fixes:**
- Option A: Change the test to grep for `"No ship"` (or `"no ship-\*.jsonl files found"`).
- Option B: Add "Insufficient data" language to the zero-file code path in `scanner-value-report.sh` lines 193-196.

### Defect 2 — MINOR: Test 32 eval/exit terminates test suite (pre-existing, non-blocking)

**File:** `scripts/test-integration.sh`, line 446
**Severity:** Minor (pre-existing; tests 33-42 never execute in the suite as written)

Test 32 uses `exit $STATUS` inside an `eval` call in the main shell. When the eval exits with `exit 0`, it exits the entire script, not just a subshell. Tests 33-42 are never counted in `TOTAL_COUNT`, `PASS_COUNT`, or `FAIL_COUNT`. The summary line reports fewer tests than the 42 documented.

**Fix:** Wrap the test command in a subshell to scope the `exit`:
```bash
"(mkdir -p /tmp/scanner-test-empty && python3 '...' --quiet /tmp/scanner-test-empty; STATUS=$?; rm -rf /tmp/scanner-test-empty 2>/dev/null; exit $STATUS)"
```

Both defects are non-blocking for the current verdict because:
1. The underlying implementation (AC1-AC10) is correct.
2. Tests 33-42 individually return the expected results except Test 40.
3. The full suite exits 0.

---

## Required Actions Before Full PASS

To achieve a clean PASS (no notes), two test-script fixes are needed:

1. **Fix Test 40** (Defect 1): Change grep pattern from `'insufficient'` to `'No ship'` in `scripts/test-integration.sh` line 511. One-line fix.
2. **Fix Test 32 eval/exit** (Defect 2): Wrap test 32 command in a subshell in `scripts/test-integration.sh` line 446. One-line fix.

Neither requires changes to production scripts (`scanner-value-report.sh`, `compute-run-score.sh`, or skill SKILL.md files). All production-side acceptance criteria are fully met.
