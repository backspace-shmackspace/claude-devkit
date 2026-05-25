# Red Team Review: Scanner Value Instrumentation (Round 2)

**Plan reviewed:** `plans/scanner-instrumentation.md` v1.1
**Reviewer:** Red Team Agent
**Date:** 2026-05-25

---

## Verdict: PASS

All prior Critical and Major findings have been addressed. Four new Minor findings and one Info finding identified. None are blocking.

---

## Prior Findings Resolution

### F-01 [Critical]: /architect emits scanner_invocation but never emits run_score -- correlation is impossible for architect runs

**Status: Resolved.**

The revised plan chose option (c) from the original recommendation: scope correlation to `/ship` only. This is thoroughly addressed:

- Architecture diagram (line 102-103) explicitly notes "/architect has no scoring."
- Context section (line 38) states "Only `/ship` emits `run_score`."
- Non-Goals (line 74) explicitly states "Add scoring to `/architect`" is out of scope.
- Timeline estimates (line 308-309) count only `/ship` runs (2-4/week) and note `/architect` runs do not contribute.
- Risks table (line 511) acknowledges this halves effective data collection rate.
- `scanner-value-report.sh` (line 168) reads `ship-*.jsonl` only.
- The word "only" or "exclusively" appears in nearly every section referencing correlation scope.

No ambiguity remains.

### F-02 [Major]: Existing scanner_invocation events emit broken metadata

**Status: Resolved.**

Change 0 (line 127-143) is added as a prerequisite phase, fixing grep patterns from `Files scanned:` to `Files:` and `Total symbols:` to `Symbols:`. The default is changed from `"unknown"` to `"0"`. Phase 0 is listed as a separate implementation phase with 0.5 days effort. The revision log confirms this was addressed per both Red Team and Feasibility feedback.

### F-03 [Major]: parser_mode enum includes "tree-sitter" which the scanner cannot currently produce

**Status: Resolved.**

The schema definition (line 362) now uses `["tree-sitter-partial", "regex-fallback"]` only. Line 351 explicitly states `"tree-sitter"` is reserved for future use and excluded from the enum. The `scanner_mode` field on `run_score` (line 349) also lists only `"tree-sitter-partial"`, `"regex-fallback"`, and `"absent"`.

### F-04 [Major]: Confounders section acknowledges causal inference is impossible but tooling output implies causation

**Status: Resolved.**

The example output (lines 199-203) now uses purely correlational language:
- `[Correlation]` prefix replaces `[Finding]`
- Language like "have higher mean efficiency" replaces "suggesting fewer revision rounds when agents have structured context"
- `[Caution]` block with confounder acknowledgment appears directly after correlations
- The caveat section (lines 177-179) appears before the cohort table

The score-reflector candidate learning (line 213-215) also uses correlational framing: "correlates with" instead of causal recommendations.

---

## New Findings

### F-11: Change 0 fix emits file_count and symbol_count as JSON strings, not integers [Minor]

The plan's Change 0 (line 139-140) changes the default from `"unknown"` to `"0"`:

```bash
FILE_COUNT=$(echo "$SCANNER_SUMMARY" | grep -oP 'Files:\s*\K[0-9]+' || echo "0")
```

The schema (line 364) defines `file_count` as `integer, required`. However, the existing JSON template in both skills (confirmed at ship/SKILL.md line 353) uses string interpolation:

```bash
"{\"file_count\":\"${SCANNER_FILE_COUNT}\",...}"
```

The `\"` quoting around `${SCANNER_FILE_COUNT}` means the value is always emitted as a JSON string, regardless of whether the bash variable contains `"0"`, `"6"`, or `"unknown"`. The grep fix alone does not produce schema-compliant integer values. The JSON template must also be changed to emit unquoted values:

```bash
"{\"file_count\":${SCANNER_FILE_COUNT},...}"
```

**Impact:** Without fixing the JSON template, the schema declares integer type but the events emit string type. Validation tools or downstream parsers expecting integers will see type mismatches. The analysis scripts will likely handle this via Python's int() coercion, but it is still a schema violation.

**Recommendation:** Add to Change 0 scope: update the JSON template strings in both skills to emit `file_count` and `symbol_count` as unquoted integers. The plan already modifies these lines, so this is a zero-cost addition.

---

### F-12: No ship logs contain scanner_invocation events -- the plan's data pipeline is untested in production [Minor]

The plan's core data flow is: `scanner_invocation` event in ship log -> `compute-run-score.sh` reads it -> embeds `scanner_mode` in `run_score`.

However, examining all three existing ship JSONL logs:

```
ship-20260509-085018-ii5d8f.jsonl: 0 scanner_invocation events
ship-20260523-175341-xywlcy.jsonl: 0 scanner_invocation events  
ship-20260525-115424-ud937f.jsonl: 0 scanner_invocation events
```

The scanner integration was deployed to `/ship` Step 1 (the code is at ship/SKILL.md lines 334-353), but none of the existing ship runs actually emitted a `scanner_invocation` event. Only `/architect` logs contain `scanner_invocation` events. This means the entire Change 2 pipeline (compute-run-score.sh reading scanner_invocation from the same ship log) has never been exercised in production -- the scanner_invocation emission code in `/ship` may have a conditional path that prevents it from firing.

**Impact:** The plan assumes the ship scanner_invocation emission is working and just needs field fixes. If the emission itself is not triggering (perhaps the scanner is not found in the `/ship` execution environment), then Changes 0-1 for `/ship` are modifications to dead code, and the correlation pipeline will receive no data.

**Recommendation:** Investigate why `/ship` runs do not emit `scanner_invocation` events despite having the emission code. If the scanner script is not found during `/ship` execution (e.g., `$SCANNER_SCRIPT` resolves to a nonexistent path in the worktree context), that is a separate bug to fix first. Add a smoke test that verifies `/ship` actually emits `scanner_invocation` in the test plan.

---

### F-13: Cohen's d edge cases are acknowledged but not fully specified [Minor]

The plan (line 455) mentions "Handle Cohen's d edge cases (cohort size 1, pooled SD = 0)." This is the right instinct but the handling is not specified:

- **Cohort size 1:** Variance is undefined for a single observation. The pooled SD formula divides by `n1 + n2 - 2`, which is 0 when both cohorts have size 1.
- **Pooled SD = 0:** All observations in both cohorts are identical (e.g., every run scored exactly 1.0). Cohen's d would be division by zero.
- **All observations identical within one cohort:** The within-group variance is zero for that cohort, pulling pooled SD toward zero and inflating d.

The PRELIMINARY tier allows cohorts as small as 3, and the plan reports effect sizes at PRELIMINARY tier (line 287: "Effect sizes are reportable" appears under RELIABLE, but the example output on line 197 shows effect size at PRELIMINARY). This means Cohen's d will be computed with very small samples where these edge cases are real.

**Impact:** Without explicit handling (e.g., returning "N/A" when either cohort has fewer than 2 observations, or capping d at a maximum), the script could produce NaN, Infinity, or misleadingly large effect sizes.

**Recommendation:** Specify the edge case behavior: (a) Cohen's d is only computed when both cohorts have n >= 2; (b) if pooled SD is 0 and means differ, report "Infinite" or "N/A"; (c) if pooled SD is 0 and means are equal, d = 0. Add these to the acceptance criteria or the analysis script specification.

---

### F-14: Plan does not account for the latest ship run missing run_score despite outcome=success [Minor]

The latest ship run (`ship-20260525-115424-ud937f.jsonl`) completed with `outcome: "success"` but emitted zero `run_score` events. Additionally, it emitted events after `run_end` (a `step_start`/`step_end` pair at sequence 48-49 after `run_end` at sequence 47), suggesting the run lifecycle event ordering described in the schema is not consistently followed.

The plan's analysis script reads `run_score` events and counts them as "/ship runs." A ship run that succeeds but emits no `run_score` is invisible to the analysis. If this is a common occurrence (e.g., `compute-run-score.sh` is not called on certain code paths), the effective data collection rate is even lower than the plan estimates.

**Impact:** If some fraction of ship runs silently fail to emit `run_score`, the timeline estimates (6-10 weeks for RELIABLE) are optimistic. This also means the "absent" cohort (no scanner data) may be conflated with "run_score not emitted" runs, since both result in no data.

**Recommendation:** This is likely a separate bug in `/ship`, not in scope for this plan. However, the plan should acknowledge that `run_score` emission is not guaranteed even for successful runs, and `scanner-value-report.sh` should report total ship log files found vs. ship logs containing `run_score` events, so the user can detect this gap.

---

### F-15: Score-reflector scanner correlation at "10+ runs" threshold may not have enough per-cohort data [Info]

Change 5 (line 209-215) adds scanner-mode correlation to `score-reflector.sh` when "10+ `/ship` runs are available." But 10 total runs split across three cohorts (tree-sitter-partial, regex-fallback, absent) could mean 8-1-1 or 7-2-1 distributions. Computing a correlation with 1-2 observations in the minority cohort is statistically meaningless.

The dedicated `scanner-value-report.sh` has proper per-cohort minimums (PRELIMINARY requires 3 per cohort, RELIABLE requires 8). But `score-reflector.sh` does not gate on per-cohort size -- it just checks "10+ runs total."

**Recommendation:** Add a per-cohort minimum (e.g., 3) to the score-reflector scanner correlation check, consistent with the PRELIMINARY tier in `scanner-value-report.sh`.

---

## Summary

The v1.1 revision is substantially improved. All four blocking findings from Round 1 have been addressed with appropriate scope, language, and schema changes. The plan's scope is now cleanly defined around `/ship` runs only, the confounders are presented with correlational framing, and the schema reflects reality.

The four Minor findings (F-11 through F-14) are implementation details that can be caught during code review. F-12 (no ship scanner_invocation events in production) is the most operationally significant -- it suggests the plan's core data pipeline has not been exercised yet and may require a prerequisite investigation.

No further revision rounds are needed before approval.
