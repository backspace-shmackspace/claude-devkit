# Red Team Review (Round 2): Quantitative Eval/Scoring System

**Plan:** `./plans/quantitative-eval-scoring.md` (Rev 2)
**Reviewed:** 2026-05-09
**Reviewer:** security-analyst (red team role)
**Round:** 2 (re-review after revisions addressing Round 1 Critical + Major findings)

## Verdict: PASS

No Critical findings. One Major finding identified (new, introduced by the revision). All Round 1 Critical and Major findings are Resolved.

---

## Round 1 Resolution Status

### C1: `revision_rounds` not emitted in `/ship` `run_end` events -- RESOLVED

**Round 1 finding:** The plan's efficiency dimension read `run_end.revision_rounds`, which is defined in the schema but never emitted by `/ship`. This would produce a constant 1.0 efficiency score for every run.

**Resolution in Rev 2:** The plan was redesigned to derive revision count from `step_start` events for `step_5_revision_loop` (plan lines 65-66, 76-77, 266, 347-379). The `run_end.revision_rounds` field is no longer referenced by the scoring logic. The pseudocode (lines 347-379) counts `step_start` events with `step == 'step_5_revision_loop'` and scores accordingly. The design note at line 76 explicitly documents why this approach was chosen over modifying coordinator prose.

**Assessment:** This is a sound fix. The structural evidence approach is more robust than a field that depends on coordinator variable tracking. Verified that `/ship` SKILL.md (lines 1047-1049) does emit `step_start` with `step: "step_5_revision_loop"` conditionally when Step 5 executes. The fallback to 0.5 (neutral) when no code review events exist (lines 358-366) handles edge cases correctly.

**However:** See new finding F-01 below regarding the event count assumption.

---

### M1: `run_score` emitted after L2/L3 audit log staging -- RESOLVED

**Round 1 finding:** The plan placed score computation after `run_end`, which occurs after `git add --force` stages the audit log. The committed log at L2/L3 would be missing the `run_score` event.

**Resolution in Rev 2:** The plan now explicitly places `run_score` emission BEFORE `run_end` (plan lines 265, 600-628). The integration section (lines 209-258) shows the correct ordering: Step 6 step_end -> compute-run-score.sh -> emit run_score -> emit run_end -> git add --force. The key design decisions table (line 265) documents: "run_score emitted immediately BEFORE run_end." The Ship integration section (lines 600-628) specifies the exact insertion point: "after the step_end for Step 6 and before the run_end emission."

**Assessment:** Fully resolved. The placement ensures `run_score` is in the JSONL file before `git add --force` stages it. The velocity computation (lines 460-462) correctly uses `datetime.utcnow()` since `run_end` has not been emitted yet. Line 628 acknowledges the delta is negligible.

---

### M2: `steps_completed` field also not emitted -- RESOLVED

**Round 1 finding:** The plan treated schema-defined fields as if they were populated, creating false confidence about available data.

**Resolution in Rev 2:** The "Current state" section (line 23) now explicitly states: "The schema also defines `revision_rounds` and `steps_completed` fields on `run_end`, but **neither field is currently emitted** by `/ship`, `/architect`, or `/audit`. These are schema placeholders that were never wired into the coordinator prose." The design note (line 76) and `score-dimensions.json` notes (line 559) both document the gap.

**Assessment:** Fully resolved. The plan now accurately represents the current system state and does not depend on either field.

---

### M3: `run_end` convention break and HMAC chain complications -- RESOLVED

**Round 1 finding:** Emitting `run_score` after `run_end` broke the convention that `run_end` is the final run-lifecycle event and created HMAC chain ambiguity at L3.

**Resolution in Rev 2:** By moving `run_score` to BEFORE `run_end` (line 265), `run_end` remains the final run-lifecycle event. The key decisions table (line 265) states: "Maintains a clean event ordering where run_end remains the final event in the run." Line 625 notes: "At L3, the HMAC chain naturally includes run_score before run_end -- no chain shape ambiguity."

**Assessment:** Fully resolved. The event ordering is now: step_end(Step 6) -> run_score -> run_end -> git add --force. This is clean and does not create variable chain shapes. The HMAC chain at L3 always has the same structure (with or without run_score producing the only variance, which is acceptable since score computation failure is non-blocking and documented).

---

## Round 1 Minor/Info Status (Verification Only)

### F-05 (Round 1, Minor): Security gates treated equally -- ACKNOWLEDGED

The plan lists gate-specific penalties under "Phase 5: Advanced Analytics" in the Future Work section (line 894): "Gate-specific security penalties (secrets_scan BLOCKED = -0.5, secure_review BLOCKED = -0.3, dependency_audit BLOCKED = -0.2)." This acknowledges the issue and defers it, which is an acceptable v1 scoping decision.

### F-06 (Round 1, Minor): Quality dimension inconsistent verdict selection -- ADDRESSED

The pseudocode now has inline comments explaining the selection logic. Line 415: "Use the first code review verdict (pre-revision quality signal)." Lines 416-417: "Rationale: the first verdict reflects the coder's unrevised output. Post-revision verdicts are captured by the efficiency dimension." The double-penalty concern remains but is documented.

### F-07 (Round 1, Minor): Reflector trend detection threshold arbitrary -- ADDRESSED

The plan now uses a tiered analysis model (lines 160-168): 5-9 runs get summary statistics only (no trend claims), 10+ runs get trend analysis with the slope threshold. The slope requirement is "magnitude > 0.05 per run AND at least 10 data points" (line 166). This is a significant improvement -- the 5-run regression concern is eliminated.

### F-08 (Round 1, Minor): No scoring on failed/blocked runs -- ACKNOWLEDGED

Listed under Future Work (line 893): "Scoring failed/blocked runs (v1 only scores successful runs on the PASS path)." Acceptable v1 scope.

### F-09 (Round 1, Minor): `score-dimensions.json` not validated at runtime -- ADDRESSED

The plan now normalizes weights dynamically (lines 471-476, 653). The composite calculation uses `effective_weight = weight / sum_of_weights`, so non-unit weight sums produce correct composites. The `score-dimensions.json` is documented as a "plain data file" (lines 274, 556) consumed as documentation in v1 with hardcoded dimensions in the script.

### F-10 (Round 1, Info): `outcome` field format inconsistency -- ADDRESSED

The Future Work section (line 876) now notes: "/architect emits `\"outcome\":\"PASS\"` (uppercase, verdict terminology) vs `/ship`'s `\"outcome\":\"success\"` (lowercase). Score computation for `/architect` must normalize outcome values."

### F-11 (Round 1, Info): Composite score not meaningful as absolute number -- ADDRESSED

The plan adds contextual guidance (line 669): "Include contextual note in output: 'Composite scores are most useful for trend analysis across runs.'"

### F-12 (Round 1, Info): Phases 2 and 3 parallel claim misleading -- ADDRESSED

The Phase Dependencies section (line 763) now acknowledges: "Phase 2 query commands can be written and unit-tested with synthetic data before Phase 3 provides real data. However, they will display 'No score data' in production until Phase 3 lands."

---

## New Findings (Round 2)

### F-01: Efficiency dimension step_start count does not distinguish 1 vs 2 revision rounds [Major]

The revised efficiency dimension counts `step_start` events with `step == "step_5_revision_loop"` (plan line 65, pseudocode lines 347-354). The formula maps: 0 occurrences = 1.0, 1 occurrence = 0.6, 2 occurrences = 0.2.

However, examining `/ship` SKILL.md, Step 5 emits exactly ONE `step_start` at entry (line 1049) and ONE `step_end` at exit (line 1111). The "Max 2 revision rounds total" (line 1102) is an INTERNAL loop within Step 5: after 5b re-verifies and gets REVISION_NEEDED again, the coordinator loops back to 5a within the same Step 5 scope. It does NOT exit Step 5, emit `step_end`, and re-enter with a new `step_start`.

Evidence: there are exactly 2 references to `step_5_revision_loop` in the entire ship SKILL.md -- one `step_start` (line 1049) and one `step_end` (line 1111). There is no second `step_start` emission within the revision loop iteration.

This means:
- 0 revision rounds: 0 `step_start` events for step_5 -> efficiency = 1.0 (correct)
- 1 revision round: 1 `step_start` event -> efficiency = 0.6 (correct)
- 2 revision rounds: still 1 `step_start` event -> efficiency = 0.6 (INCORRECT, should be 0.2)

The formula can never produce 0.2. The efficiency dimension has only two possible scored outcomes (1.0 or 0.6), not three. The "2 occurrences = 0.2" case documented in the table (line 65) is structurally impossible given the current `/ship` event emission pattern.

**Impact:** The efficiency dimension loses granularity. A run requiring 2 revision rounds (the maximum, indicating significant coder-reviewer misalignment) receives the same score as a run requiring 1 round. The distinction between "minor revision" and "major revision" is lost.

**Remediation options:**

(a) Count `verdict` events with `verdict_source == "code_review"` instead. Step 4 emits these as retrospective markers (line 989), and Step 5b re-runs Step 4 "in its entirety." If 2 rounds occur, there would be 3 code_review verdict events (initial + round 1 re-verify + round 2 re-verify). Formula: `revision_count = max(0, code_review_verdict_count - 1)`. This accurately counts actual revision rounds from structural evidence.

(b) Accept the limitation and update the documentation: efficiency has two levels (0 revisions = 1.0, 1+ revisions = 0.6). Update the table, the formula, the `score-dimensions.json`, and the coupling note.

(c) Modify `/ship` SKILL.md to emit per-round step events (e.g., `step_5a_round_1`, `step_5a_round_2`). This expands scope to coordinator prose changes.

Option (a) is recommended because it uses data that already exists in the log (code_review verdict events are re-emitted during Step 5b's re-run of Step 4), requires no changes to `/ship` SKILL.md, and provides accurate three-level granularity.

---

### F-02: Velocity timestamp parsing uses naive UTC assumption [Minor]

The velocity computation (lines 460-462) uses `datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.000Z')` when `run_end` has not been emitted. It then parses timestamps with `datetime.fromisoformat(ts.replace('Z', '+00:00'))`.

The `replace('Z', '+00:00')` approach works for the specific format emitted by `emit-audit-event.sh` (which uses macOS `date -u +%Y-%m-%dT%H:%M:%S.000Z`). However, `datetime.fromisoformat` in Python 3.10 and earlier does not support the `Z` suffix at all -- the `replace` call is necessary. In Python 3.11+, `fromisoformat` accepts `Z` natively. The code is correct for both versions due to the `replace`, but the `+00:00` replacement changes the timezone representation.

The deeper issue: `datetime.utcnow()` is deprecated since Python 3.12 (it returns a naive datetime without timezone info). The recommended replacement is `datetime.now(timezone.utc)`. While this does not cause incorrect results (the naive datetime is compared against another effectively-naive datetime from the same source), it will produce deprecation warnings on Python 3.12+.

**Impact:** Deprecation warning on Python 3.12+ stderr output. No incorrect results.

**Remediation:** Use `datetime.now(timezone.utc)` instead of `datetime.utcnow()`. Add `from datetime import datetime, timezone` to the imports.

---

### F-03: Composite score uses hardcoded 0.3333 weights that do not sum to 1.0 [Minor]

The pseudocode (lines 374, 397, 448) uses `"weight": 0.3333` for each active dimension. The composite calculation (lines 471-477) normalizes by `total_weight = sum(d['weight'] for d in scored)`, which produces `total_weight = 0.9999`. The normalization then computes `score * weight / total_weight`, which is `score * 0.3333 / 0.9999 = score * 0.33333...`. This is mathematically correct (the normalization handles the rounding), but the intermediate representation is misleading: the `weight` field in the emitted `run_score` event will show `0.3333` rather than the effective `0.3333...` (1/3).

The plan addresses this from the feasibility review (S4), and the normalization in line 474 handles it. This is a cosmetic issue.

**Impact:** None. The normalization produces correct results.

**Remediation:** No action required. Could use `round(1/3, 4)` = 0.3333 which is already what the plan uses.

---

### F-04: `compute-run-score.sh` error path emits neutral scores without indicating error [Minor]

The script interface (lines 317-319) says: "0 = any error (writes warning to stderr, outputs neutral-score JSON to stdout). Never exits non-zero."

If the script encounters an error (e.g., invalid file path, python3 crash), it outputs all-neutral scores (0.5 per dimension, 0.5 composite). This neutral output is then emitted as a `run_score` event via `emit-audit-event.sh`. There is no field in the emitted event that distinguishes "all dimensions are genuinely neutral because no gates ran" from "scoring failed and we fell back to neutral."

For a single run, this is harmless. For trend analysis, error-induced neutral scores pollute the dataset. If `compute-run-score.sh` consistently fails (e.g., due to a python3 version issue), all runs would show 0.5 composite, creating a flat line that masks real trends.

**Impact:** Low. Error-induced neutral scores are indistinguishable from genuine neutral scores in trend data.

**Remediation:** Add an optional `"error": true` field to the neutral fallback output so the `run_score` event can be tagged. The reflector and trend commands can then exclude error-flagged scores. Alternatively, do not emit `run_score` at all on error (the ship integration already handles empty output on line 616: "Warning: Score computation returned empty output. Continuing without score.").

---

### F-05: Plan references line numbers in ship SKILL.md that may drift [Minor]

The plan (lines 600, 687-688) references specific line numbers in `/ship` SKILL.md: "the current line that emits step_end for step_6_commit_gate (line 1237-1238) and the line that emits run_end (line 1240-1243)." These line numbers are accurate at time of plan writing but will drift if any prior content in the SKILL.md is modified before this plan is implemented.

**Impact:** Low. An implementer following these line numbers on a modified SKILL.md would insert the score computation in the wrong location.

**Remediation:** The plan already provides sufficient structural description ("after step_end for Step 6 is emitted and before run_end") that line numbers are supplementary, not primary. No action needed, but the implementer should locate the insertion point structurally rather than by line number.

---

### F-06: Reflector linear regression on scores bounded [0, 1] may produce misleading slope magnitudes [Minor]

The reflector uses a slope magnitude threshold of 0.05 per run (line 166) to detect degrading trends. With scores bounded between 0 and 1, the maximum possible slope magnitude is 1.0 / (N-1) for N runs. For 10 runs (the minimum for trend analysis), the maximum slope is ~0.111. The threshold of 0.05 means any consistent degradation of more than 0.5 points over 10 runs triggers an alert.

This is reasonable for most cases, but the threshold has an interaction with the neutral score (0.5). A project that transitions from "no security gates deployed" (neutral 0.5) to "security gates deployed and passing" (1.0) would show a strong positive slope, generating a "security improving" signal. In reality, the project simply started measuring. The neutral-to-measured transition creates false trend signals.

**Impact:** Low. The reflector output is human-curated, so a human would recognize this pattern. But the generated candidate learnings text would be misleading.

**Remediation:** The reflector could detect dimension transitions (a run of 0.5 neutral scores followed by non-0.5 scores) and exclude the neutral prefix from trend computation. This is a v2 refinement.

---

## Summary

| Severity | Count | Finding IDs |
|----------|-------|-------------|
| Critical | 0 | -- |
| Major | 1 | F-01 |
| Minor | 5 | F-02, F-03, F-04, F-05, F-06 |

### Round 1 Resolution Status

| Finding | Severity | Status |
|---------|----------|--------|
| C1: revision_rounds not emitted | Critical | Resolved (redesigned to use step events) |
| M1: run_score ordering / L2/L3 staging | Major | Resolved (moved before run_end) |
| M2: steps_completed not emitted | Major | Resolved (documented as schema gap) |
| M3: run_end convention / HMAC chain | Major | Resolved (run_end remains final event) |
| F-05 to F-12 (Minor/Info) | Minor/Info | All addressed or acknowledged in Future Work |

### Assessment

The revisions are thorough and well-executed. The C1 redesign (deriving efficiency from step events instead of a non-emitted run_end field) is architecturally cleaner than the original approach. The M1 fix (moving run_score before run_end) elegantly resolves both the L2/L3 staging issue and the HMAC chain concern simultaneously. The documentation additions (schema gap acknowledgment, L1 ephemeral limitation, tiered analysis thresholds) substantially improve the plan's accuracy about the current system state.

The new Major finding (F-01: step_start count cannot distinguish 1 vs 2 revision rounds) is a data fidelity issue within the redesigned efficiency dimension. It does not invalidate the scoring system -- efficiency still captures the binary signal of "revision occurred vs. did not occur" -- but it loses the intended three-level granularity. The recommended fix (counting code_review verdict events instead of step_start events) is a contained change to the pseudocode and dimension documentation that does not affect any other part of the plan.

Verdict is PASS because F-01 is Major (not Critical) -- the scoring system is functional with the binary efficiency signal, and the fix is straightforward. If the author prefers three-level granularity, the remediation in F-01 provides a clean path without expanding scope.
