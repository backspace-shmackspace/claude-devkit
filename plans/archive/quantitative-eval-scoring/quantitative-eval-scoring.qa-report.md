# QA Report: Quantitative Eval/Scoring System

**Plan:** `plans/quantitative-eval-scoring.md`
**QA Date:** 2026-05-09
**QA Agent:** qa-engineer
**Verdict:** PASS

---

## Acceptance Criteria Coverage

### AC1 — `scripts/compute-run-score.sh` exists, is executable, produces valid JSON for any JSONL input

**Status: PASS**

File exists at `/Users/imurphy/projects/claude-devkit/scripts/compute-run-score.sh`.
Executable bits confirmed: `-rwxr-xr-x` (verified via `ls -la`).
`bash scripts/compute-run-score.sh --help` exits 0 with correct usage output.

Tested against:
- Complete synthetic log (Test 20): all three dimensions scored correctly, valid JSON produced
- Empty log (Test 21): all dimensions return 0.5 neutral, composite 0.5
- Nonexistent file path (Test 24): exits 0, returns neutral JSON, warning to stderr
- Incomplete log with no `run_end` (Test 25): scores computed from available events
- Malformed JSONL lines (Test 26): bad lines skipped, valid events scored correctly


### AC2 — Efficiency derived from `verdict` events with `verdict_source == "code_review"` (NOT from `run_end.revision_rounds` or `step_start` events)

**Status: PASS**

Code at lines 150-158 of `scripts/compute-run-score.sh`:
```python
code_review_verdicts = [
    e for e in events
    if e.get('event_type') == 'verdict'
    and e.get('verdict_source') == 'code_review'
]
```

No references to `run_end.revision_rounds` or step_start-based counting anywhere in the efficiency computation block. The `--help` text explicitly states "Derived from count of code_review verdict events." `configs/score-dimensions.json` efficiency `source` field correctly reads: "verdict events where verdict_source == 'code_review' (count - 1 = revision rounds)".

Test 25 specifically validates the formula: 2 code_review verdicts produce efficiency 0.6 (1 revision round), and Test 20 validates 1 code_review verdict produces efficiency 1.0 (0 revision rounds).


### AC3 — `configs/audit-event-schema.json` includes `run_score` in both the `event_type` enum and the `oneOf` array

**Status: PASS**

Confirmed via `python3` verification:
- `event_type` enum: `['run_start', 'run_end', 'step_start', 'step_end', 'verdict', 'security_decision', 'file_modification', 'error', 'run_score']` — `run_score` is present.
- `oneOf` titles: `['run_start', 'run_end', 'step_start', 'step_end', 'verdict', 'security_decision', 'file_modification', 'error', 'run_score']` — `run_score` is present.
- The `run_score` oneOf entry includes `dimensions` array (items with `name`, `score`, `weight`, `details`), `composite` number, and `velocity_minutes` number — matching the plan specification exactly.
- `notes.run_score_ordering` key added documenting ordering semantics.
- File parses as valid JSON.


### AC4 — `configs/score-dimensions.json` exists as plain JSON data file (no `$schema`) defining four dimensions

**Status: PASS**

File exists at `configs/score-dimensions.json`. Parses as valid JSON. No `$schema` key present (confirmed). Keys: `['title', 'version', 'description', 'notes', 'dimensions']`. Four dimensions defined: `efficiency`, `security`, `quality`, `velocity`. The `notes` object includes `weight_convention`, `efficiency_coupling`, and `schema_gap` entries as specified in the plan. Efficiency `scoring` field documents the correct formula: `max(0.0, 1.0 - (count - 1) * 0.4)`, referencing code_review verdict count (not step_start events).


### AC5 — `/ship` SKILL.md emits `run_score` event before `run_end` (version bumped to 3.8.0)

**Status: PASS**

Version confirmed: `version: 3.8.0` in frontmatter (line 4).

Score computation block at lines 1240-1249 of `skills/ship/SKILL.md`:
```bash
# Score computation (pre-run_end, non-blocking)
# All verdict, security_decision, and step events are already in the log at this point.
# run_score is emitted before run_end so it is included in L2/L3 committed logs.
SCORE_JSON=$(bash scripts/compute-run-score.sh "$AUDIT_LOG" 2>/dev/null)
if [ -n "$SCORE_JSON" ]; then
  bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" "$SCORE_JSON"
  echo "Run score computed and logged."
else
  echo "Warning: Score computation returned empty output. Continuing without score."
fi
```

Confirmed ordering: `step_end` for step_6 (line 1238) → `run_score` computation (lines 1240-1249) → `run_end` emission (lines 1251-1254). This matches the plan's required insertion point exactly.

Integration test 16 confirms version 3.8.0 assertion passes.


### AC6 — `audit-log-query.sh scores <run_id>` shows per-dimension scores

**Status: PASS**

`cmd_scores()` function exists at line 578 of `scripts/audit-log-query.sh`. Dispatch case at line 809 routes `scores` to `cmd_scores`. Help text documents the command with example usage.

Test 22 confirms the command parses `run_score` events and outputs both `efficiency` and `Composite score`. Output format includes dimension name, score, weight, and details columns.


### AC7 — `audit-log-query.sh trend [N]` shows composite score trend across recent runs

**Status: PASS**

`cmd_trend()` function exists at line 647 of `scripts/audit-log-query.sh`. Supports `[N]` positional argument and `--dimension <name>` flag. Dispatch case at line 811 routes `trend` to `cmd_trend`. Help text documents both forms with examples.

Test 23 confirms aggregation across multiple log files (3 synthetic logs). Test 27 confirms graceful handling of zero scored runs with "No score data found." message.

The composite trend table shows per-run columns for efficiency, security, quality, composite, plus a summary row with mean, first, last, and delta values.


### AC8 — `scripts/score-reflector.sh` exists, is executable, uses tiered analysis (5-9 runs summary, 10+ trends)

**Status: PASS**

File exists at `scripts/score-reflector.sh`. Executable bits confirmed: `-rwxr-xr-x`.
`bash scripts/score-reflector.sh --help` exits 0 with correct usage output.

Tiered analysis verified with live execution against synthetic data:
- 7 runs: output shows `## Score Summary (7 runs analyzed)` with mean/min/max table and "Trend analysis requires 10+ runs." notice. No slope values in output. No trend claims.
- 12 runs with degrading efficiency (slope -0.065/run): output shows `## Candidate Learnings from Score Analysis (12 runs analyzed)` with full summary + trend table including slope column. Trend finding correctly triggered for efficiency and composite decline.

Both `--min-runs N` and `--format md|json` flags are implemented.


### AC9 — All existing integration tests continue to pass

**Status: PASS**

`bash scripts/test-integration.sh` output: **26/26 tests passed, 0 failed.**

All pre-existing tests (1-4, 6-8, 10-19) continue to pass unchanged. Test 16 correctly asserts `version: 3.8.0`. `bash scripts/validate-all.sh` passes: **15/15 skills validated.**


### AC10 — At least 8 new integration tests (4 positive + 4 negative/edge cases)

**Status: PASS**

Tests 20-27 are new scoring tests (8 total):

| Test | Type | Scenario |
|------|------|----------|
| 20 | Positive | Complete log with all event types → correct scores |
| 21 | Positive | Empty log → all neutral 0.5 scores |
| 22 | Positive | `audit-log-query.sh scores` parses run_score events |
| 23 | Positive | `audit-log-query.sh trend` aggregates across multiple logs |
| 24 | Negative | Nonexistent file → exits 0, neutral scores, warning to stderr |
| 25 | Negative | Incomplete log (no run_end) → scores from available events |
| 26 | Negative | Malformed JSONL lines → skipped, valid events scored |
| 27 | Negative | trend with 0 scored runs → "No score data found" message |


### AC11 — CLAUDE.md updated with scoring system documentation and updated test count

**Status: PASS**

Confirmed via grep:
- `## Quantitative Scoring` section present at line 242.
- `run_score` added to the Event Types table (line 192) with description: "When a skill run completes and scores are computed (emitted immediately before `run_end`, on PASS path only)".
- `/ship` registry description updated to mention scoring (line 102).
- `compute-run-score.sh` and `score-reflector.sh` added to Scripts section (lines 235-236).
- Directory structure updated: `compute-run-score.sh` and `score-reflector.sh` listed under `scripts/` (lines 69-71).
- Test count updated from 18 to 26 in both the directory structure comment and the Scripts section description (line 71, 914).
- L1 ephemeral log limitation documented (line 290).
- `score-dimensions.json` documented as plain data file (line 292).

---

## Missing Tests or Edge Cases

The following cases are not covered by the current integration tests. These are not blocking — the plan's required test count (8) is met and all 8 pass — but they are worth noting for future test expansion:

**Moderate priority:**

1. **Efficiency formula boundary at 3 verdicts (score = 0.2):** Test 25 covers 2 verdicts → 0.6. Three verdicts (2 revision rounds → 0.2) is the floor of the non-zero scoring range and is not directly tested. The formula is simple, but an explicit test would lock in the boundary.

2. **BLOCKED security gate scoring (-0.3 penalty):** Test 26 tests a BLOCKED security_decision but only verifies security = 0.7 within a malformed-JSONL scenario. A clean isolated test for the -0.3 penalty with a single BLOCKED gate (producing exactly 0.7) and a double BLOCKED gate (producing 0.4) would be tighter coverage.

3. **PASS_WITH_NOTES security gate scoring (-0.1 penalty):** Not tested at all by integration tests. The implementation handles it (line 187 of compute-run-score.sh) but no test verifies `gate_verdict == "PASS_WITH_NOTES"` → security score 0.9.

4. **QA FAIL verdict penalty (-0.5 to quality):** No integration test covers a `qa` verdict with `FAIL`. Test 20 covers `qa: PASS`; Test 25 covers only code_review verdicts.

5. **score-reflector.sh --format json output:** The JSON format path exists in the code but is not covered by any integration test. A test asserting valid JSON output from `--format json` would be a quick win.

6. **score-reflector.sh insufficient data (< min-runs) path:** No integration test covers the "Insufficient data" exit path when fewer than min-runs scored runs exist. The reflector outputs a specific message and exits 0; this should be tested.

7. **Composite normalization with all-neutral dimensions:** When all three dimensions return 0.5 (neutral), composite should be exactly 0.5. Test 21 (empty log) covers this, but only implicitly — the test verifies `composite == 0.5`, which is correct.

**Low priority:**

8. **Velocity computation with actual timestamps:** The velocity calculation in compute-run-score.sh is not tested end-to-end (no test checks that `velocity_minutes` appears in the output with a non-None value). This is informational-only and excluded from composite, so the risk is low.

9. **score-reflector.sh with zero-variance scores:** The plan's test matrix mentioned this case ("verify no spurious trend claims"), but it is not in the integration tests. It was listed as a manual validation item in the plan.

---

## Notes

**Test numbering gap:** Tests 5 and 9 appear to be reserved/cleanup positions in the test suite (Test 9 is the cleanup block, executed inline without a `run_test` call; Test 5 is absent). This is a pre-existing pattern from before the scoring work and does not affect correctness. The total count of 26 is accurate.

**score-dimensions.json minor stale field:** The `efficiency` dimension's `scoring` field in `configs/score-dimensions.json` reads "Count code_review verdict events. 1 verdict = 0 rounds = 1.0..." — this is correct per the plan's Rev 3 final design. However, there is a residual artifact in the same file: the `source` field says "verdict events where verdict_source == 'code_review' (count - 1 = revision rounds)" which is correct, but the `scoring` field still says "Count step_start occurrences" in an earlier draft note that was not propagated. **Re-check:** the actual file content (read above) shows the scoring field as "Count code_review verdict events..." — this is correct. No stale text found.

**FAIL path does not emit run_score:** The plan specifies run_score is emitted "before `run_end`" and specifically notes "on the PASS path only" in the CLAUDE.md Event Types table. The implementation confirms this: the score computation block at lines 1240-1249 is inside the `if [ -f "$AUDIT_LOG" ]` success-path block. The FAIL path (lines 1352-1357) emits only `step_end` and `run_end`. This matches the plan's intent — failed runs produce no score — and is consistent with CLAUDE.md's documentation. No defect.

**Integration with L2/L3 logs:** The run_score block runs before `git add --force "$AUDIT_LOG"` (line 1258), ensuring run_score is included in L2/L3 committed logs. This ordering is correct and matches the plan.

**Dependencies correctly declared:** Both `compute-run-score.sh` and `score-reflector.sh` document `python3` as the only dependency and explicitly state "NOT a dependency: jq". This is verified by examining the scripts — no `jq` calls appear anywhere in either file.

---

## Evidence Summary

| Check | Command | Result |
|-------|---------|--------|
| compute-run-score.sh exists + executable | `ls -la scripts/compute-run-score.sh` | -rwxr-xr-x |
| score-reflector.sh exists + executable | `ls -la scripts/score-reflector.sh` | -rwxr-xr-x |
| compute-run-score.sh --help exits 0 | `bash scripts/compute-run-score.sh --help` | exit 0 |
| score-reflector.sh --help exits 0 | `bash scripts/score-reflector.sh --help` | exit 0 |
| run_score in event_type enum | python3 verification | True |
| run_score in oneOf array | python3 verification | True |
| score-dimensions.json valid JSON | python3 json.load | pass |
| score-dimensions.json no $schema | python3 key check | no $schema key |
| score-dimensions.json 4 dimensions | python3 len check | 4 |
| ship version 3.8.0 | grep | version: 3.8.0 |
| run_score before run_end in ship | line inspection (1238-1254) | correct ordering |
| validate-all.sh | bash scripts/validate-all.sh | 15/15 pass |
| test-integration.sh | bash scripts/test-integration.sh | 26/26 pass |
| Tiered analysis 7 runs | live execution | summary only, no trend |
| Tiered analysis 12 runs | live execution | candidates + slope |
| CLAUDE.md Quantitative Scoring | grep | line 242 |
| CLAUDE.md test count updated | grep | 26 tests |
