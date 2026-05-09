# Feasibility Review: Quantitative Eval/Scoring System (Round 2)

**Reviewer:** code-reviewer agent
**Date:** 2026-05-09
**Plan:** `./plans/quantitative-eval-scoring.md` (Rev 2)
**Previous Review:** Round 1 verdict was REVISE (C1: revision_rounds data dependency)
**Verdict:** REVISE

---

## Code Review Summary

Rev 2 resolves most Round 1 findings well. The jq removal (F1), sample size tiering (F2), L1 documentation (F3), and negative test cases (F4) are all properly addressed. However, the C1 resolution -- deriving efficiency from `step_5_revision_loop` step_start event counting -- contains a structural error that produces a coarser signal than the plan claims and makes the `revision_count == 2` score (0.2) unreachable.

---

## Round 1 Resolution Status

| ID | Round 1 Finding | Status | Notes |
|----|----------------|--------|-------|
| **C1** | `revision_rounds` not emitted in `run_end` | **Partially Resolved** | Redesigned to use step event counting. Avoids the coordinator-prose change. But the counting logic has a structural problem -- see New C1 below. |
| **M1/F1** | jq vs python3 boundary | **Resolved** | `compute-run-score.sh` is now python3-only. jq explicitly documented as NOT a dependency. Clear throughout plan. |
| **M2/F2** | Trend detection sample size too low | **Resolved** | Tiered analysis: 5-9 runs get summary stats only (no trend claims), 10+ runs get linear regression. `--min-runs` default raised to 5 (minimum for any output). Slope threshold requires 10+ data points. Well-documented rationale. |
| **M3/F3** | L1 ephemeral log limitation | **Resolved** | Explicitly documented in the trending section (line 147), the reflector interface (line 523), and the risk assessment table. Commands display an L1 notice. |
| **M4** | Schema `oneOf` addition unclear | **Resolved** | Lines 123-124 now explicitly state both changes: (1) add to enum, (2) add to `oneOf` array. Implementation task at line 642-644 mirrors this. |
| **M5** | Score emission placement imprecise | **Resolved** | Rev 2 moves `run_score` emission to BEFORE `run_end` (not after). Lines 265, 600-628 are precise: after `step_end` for Step 6, before `run_end` emission. This is cleaner than Round 1's "after run_end" placement and avoids HMAC chain ordering ambiguity. |
| **S1** | Velocity timestamp parsing | **Resolved** | Full python3 datetime parsing logic in pseudocode (lines 451-468). Handles missing run_end by using current time. |
| **S2** | score-dimensions.json consumption | **Resolved** | Line 274 and line 556 explicitly state: "v1 dimensions are hardcoded in compute-run-score.sh for simplicity." The JSON file is documentation-first, machine-readable in v2. |
| **S3/F4** | Negative test cases | **Resolved** | 4 explicit negative tests added (lines 729-733): nonexistent file, incomplete log, malformed JSONL, 0 scored runs for trend command. Test count expanded from 8 to 12. |
| **S4** | Weight normalization | **Resolved** | Composite computation (line 471-476) filters to scored dimensions and normalizes: `d['score'] * d['weight'] / total_weight`. Zero-weight velocity is excluded. |
| **S5** | `trend` run_id discovery | **Resolved** | Line 678 specifies filtering to target skill prefix (e.g., only `ship-*.jsonl`). |
| **S6** | Task breakdown count | **Resolved** | Header now says "Files to Create (3)" matching the 3-row table. |

---

## New Critical Issue

### C1 (New). step_5_revision_loop step_start event counting cannot distinguish 1 vs 2 revision rounds

The plan states (line 65): "Count the number of step_start events with step == step_5_revision_loop. 0 occurrences = 1.0. 1 occurrence = 0.6. 2 occurrences = 0.2."

I verified the actual `/ship` SKILL.md structure at lines 1035-1112. Step 5 emits exactly **one** `step_start` for `step_5_revision_loop` at entry (line 1048-1049) and exactly **one** `step_end` at exit (line 1110-1111). The entire revision loop -- which can iterate up to 2 rounds internally via "Re-run Step 4" (line 1098) and the "Max 2 revision rounds total" loop-back (line 1102) -- is bracketed by this single step_start/step_end pair.

This means:
- **0 step_start events** = Step 5 never executed (code review passed first time). This case works correctly.
- **1 step_start event** = Step 5 executed (1 OR 2 rounds). Cannot distinguish.
- **2 step_start events** = **Impossible** with the current SKILL.md structure. This score is unreachable.

The plan's scoring table claims three distinct scores (1.0, 0.6, 0.2) but only two are reachable (1.0 and 0.6). The efficiency dimension becomes binary rather than the intended gradient.

**Why this matters:** The efficiency dimension is designed to measure "how clean the implementation was" with a gradient. Collapsing 1-round and 2-round revisions into the same 0.6 score loses the signal that a 2-round revision is materially worse than a 1-round revision. The trend analysis and reflector will not be able to detect a pattern shift from "occasional 1-round revisions" to "always hitting the 2-round cap."

**Available alternatives:**

1. **Count code_review verdict events instead.** Step 5b says "Re-run Step 4 in its entirety" which re-emits Step 4 substep events, including code_review verdict events. The count of `verdict` events where `verdict_source == "code_review"` directly maps to revision rounds: 1 verdict = 0 rounds, 2 verdicts = 1 round, 3 verdicts = 2 rounds. Formula: `revision_rounds = code_review_verdict_count - 1`. This uses data already in the log and provides the full 3-value gradient.

2. **Add per-round step_start emissions inside Step 5.** Modify SKILL.md to emit `step_start`/`step_end` for each round (e.g., `step_5a_round_1`, `step_5a_round_2`). This expands scope to coordinator prose changes, which Rev 2 explicitly wanted to avoid.

3. **Accept the binary signal.** Acknowledge that efficiency is 1.0 (no revisions) or 0.6 (revisions occurred) in v1. Upgrade to the code_review verdict counting approach or add `revision_rounds` to `run_end` in v2.

**Recommendation:** Option 1 (count code_review verdict events) is the strongest choice. It requires no SKILL.md changes, uses data already in the log, and provides the intended 3-value gradient. The plan's pseudocode already filters for `verdict_source == 'code_review'` in the quality dimension (line 405), so the pattern is established. The efficiency derivation should be:

```python
code_review_verdicts = [
    e for e in events
    if e.get('event_type') == 'verdict'
    and e.get('verdict_source') == 'code_review'
]
revision_count = max(0, len(code_review_verdicts) - 1)
```

This also has better semantics: the first code_review verdict is the initial assessment (not a revision), and each subsequent verdict represents a revision round. The `step_5_revision_loop` presence/absence can remain as a cross-check but should not be the primary signal.

**Impact if unaddressed:** The efficiency dimension produces only 2 distinct scores instead of 3. Trend analysis cannot distinguish "getting worse within the revision loop" from "entered the revision loop." The `score-dimensions.json` documentation would be inaccurate (claiming a score of 0.2 that can never occur).

---

## Minor Observations (No Action Required)

### O1. Velocity uses current time, which is correct but could be clearer

The plan correctly notes (line 628) that velocity is computed using current time since `run_end` has not been emitted yet, and that the delta is "negligible." This is fine. The pseudocode at line 460 handles this explicitly.

### O2. The security dimension penalty for multiple BLOCKED gates may produce negative pre-floor scores

With 4 BLOCKED security gates (secrets_scan + secure_review + dependency_audit + plan_security_check), the raw score would be `1.0 - (4 * 0.3) = -0.2`, floored to 0.0. This is handled correctly by the `max(0.0, ...)` at line 392. No issue.

### O3. Run ordering in reflector relies on timestamp sorting

The reflector sorts run_score events by timestamp (line 529). Since timestamps are second-precision (macOS limitation noted in the schema), two runs starting within the same second could be misordered. This is extremely unlikely in practice (consecutive /ship runs are minutes apart at minimum) and is not worth adding complexity to address.

---

## What Went Well in Rev 2

1. **Thorough revision log.** The Rev 2 summary (lines 6-8) documents exactly which Round 1 finding triggered each change. This makes the review delta clear and auditable.

2. **Pre-run_end emission placement.** Moving `run_score` before `run_end` (instead of after) is cleaner than Round 1's proposal. It maintains `run_end` as the final run-lifecycle event, avoids HMAC chain edge cases, and ensures L2/L3 `git add --force` captures both events.

3. **Tiered analysis levels.** The 5-9 runs vs 10+ runs split for the reflector is well-calibrated. The example outputs (lines 170-205) demonstrate both modes clearly.

4. **Coupling documentation.** The `score-dimensions.json` notes object (line 557-560) documents the efficiency formula coupling to /ship's max revision count and the schema gap. This was a Round 1 suggestion and is implemented well.

5. **Comprehensive negative test cases.** The 4 negative tests (nonexistent file, incomplete log, malformed JSONL, 0 scored runs) cover the most likely production failure modes.

---

## Recommendations

Prioritized:

1. **[MUST] Fix New C1:** Replace the efficiency dimension's primary data source from `step_5_revision_loop` step_start counting to code_review verdict counting. `revision_count = len(code_review_verdicts) - 1`. This preserves the 3-value gradient (0, 1, 2 rounds) using data already in the log, requires no SKILL.md changes, and matches the plan's stated intent. Update: the dimension table (line 65), the pseudocode (lines 348-379), the design rationale (lines 76-78), the `score-dimensions.json` source field (line 567), the efficiency coupling note (line 558), and the acceptance criteria mentioning `step_5_revision_loop` (line 836, 944).

2. **[CONSIDER] Keep step_5_revision_loop as a secondary signal.** The presence of a `step_5_revision_loop` step_start event is still useful as a binary "did revisions happen?" check. It can serve as a cross-validation for the code_review verdict count (if `revision_count > 0` but no `step_5` step_start exists, something is wrong). But it should not be the primary efficiency data source.

---

## Verdict

**REVISE** -- New C1 (step_5_revision_loop step_start counting cannot distinguish 1 vs 2 revision rounds) makes the efficiency dimension coarser than intended. The fix is straightforward (count code_review verdict events instead) and requires no changes outside the plan itself. All Round 1 findings are properly resolved. Once C1 is fixed, the plan is ready to implement.
