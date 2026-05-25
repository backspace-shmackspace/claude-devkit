# Plan: Scanner Value Instrumentation

**Status:** DRAFT
**Author:** Senior Architect Agent
**Date:** 2026-05-25
**Version:** 1.1

---

## Revision Log

| Finding ID | Source | Severity | Resolution |
|------------|--------|----------|------------|
| F-01 | Red Team | Critical | Scoped correlation analysis to `/ship` runs only. `/architect` scanner_invocation events are enriched but not correlated (no run_score). Timeline estimates revised to count only `/ship` runs. Added known limitation to Risks table. |
| F-02 | Red Team, Feasibility M1 | Major | Added Change 0 (prerequisite): fix grep patterns from `Files scanned:` to `Files:` and `Total symbols:` to `Symbols:` in both skills. |
| F-03 | Red Team | Major | Removed `"tree-sitter"` from `parser_mode` and `scanner_mode` enums. Only `"tree-sitter-partial"` and `"regex-fallback"` are valid until the scanner code path exists. |
| F-04 | Red Team | Major | Replaced causal framing in example output and score-reflector candidate learning with purely correlational language. Changed `[Finding]` prefix to `[Correlation]`. |
| L-01 | Librarian | Required | Removed `jq` from Assumptions point 5. |
| L-02 | Librarian | Required | Added explicit "update test count from 37 to 42" to Work Group 3 CLAUDE.md scope. |
| Feas-M2 | Feasibility | Major | Changed `file_count` and `symbol_count` schema types from "string or integer" to integer. |
| Feas-M3 | Feasibility | Major | Eliminated `"unknown"` sentinel. Use `"absent"` consistently for both missing scanner_invocation events and pre-instrumentation run_score events. |
| Feas-M4 | Feasibility | Major | Revised `scanner-value-report.sh` line estimate from ~350 to ~550. Phase 2 effort revised from 1.5 days to 2 days. Total effort revised from 4 days to 4.5 days. |

---

## Context

### Problem Statement

The codebase scanner (`scripts/codebase-scanner.py`) was deployed in v1.1 and integrated into `/architect` Step 1 and `/ship` Step 1. It currently emits a `scanner_invocation` audit event with basic metadata (version, parser_mode, file_count, symbol_count, output_sha256). However, there is no mechanism to measure whether the scanner actually improves outcomes: plan quality, code quality, token cost, or delivery speed.

The original plan (`plans/codebase-symbol-index.md`) included a Phase 6 measurement gate (Days 10-14) with manual baseline/treatment comparison. That approach requires deliberate A/B testing and does not produce ongoing, automated measurement. This plan builds production instrumentation that answers the question continuously: **"Is the scanner making runs better?"**

### What Exists Today

1. **Scanner invocation event** (`scanner_invocation`) -- emitted by `/architect` and `/ship` with fields: `scanner_version`, `parser_mode`, `file_count`, `symbol_count`, `output_sha256`. Missing: `output_token_count`. **Known bug:** `file_count` and `symbol_count` are always `"unknown"` because grep patterns use `Files scanned:` and `Total symbols:` but the scanner outputs `Files:` and `Symbols:`.

2. **Run scoring** (`run_score` event) -- emitted by `compute-run-score.sh` at the end of each `/ship` run with dimensions: efficiency (revision rounds), security (gate outcomes), quality (CR + QA verdicts). No correlation with scanner data. **Note:** Only `/ship` emits `run_score`. `/architect` does not call `compute-run-score.sh` and has no scoring.

3. **Score reflector** (`score-reflector.sh`) -- reads all `run_score` events, computes stats and trends (5 runs = summary, 10+ = regression). Outputs candidate learnings. Has no scanner awareness.

4. **Schema gap** -- `scanner_invocation` is emitted by skills but is NOT listed in the `event_type` enum in `configs/audit-event-schema.json`.

### What's Missing

1. **Token cost measurement** -- No `output_token_count` field on `scanner_invocation`. Cannot quantify how much context budget the scanner consumes.

2. **Scanner-score correlation** -- No way to slice `/ship` `run_score` data by scanner attributes (parser_mode, presence/absence, output size). Cannot answer "do tree-sitter runs score better than regex runs?" (`/architect` emits `scanner_invocation` but has no scoring, so correlation is only possible for `/ship` runs.)

3. **Cross-run comparison** -- No dedicated analysis tool that correlates scanner metadata with downstream outcomes across `/ship` runs.

4. **Broken field extraction** -- Existing `scanner_invocation` events emit `file_count: "unknown"` and `symbol_count: "unknown"` due to grep pattern mismatch (grep looks for `Files scanned:` but scanner outputs `Files:`).

5. **Statistical guidance** -- No documented thresholds for how many runs are needed before scanner value claims are trustworthy.

---

## Goals

1. Fix broken `file_count` and `symbol_count` extraction patterns in `/architect` and `/ship` scanner_invocation emission blocks (prerequisite -- already touching these lines).
2. Add `output_token_count` to the `scanner_invocation` event so token cost is captured automatically.
3. Embed scanner metadata (parser_mode, output_token_count) into the `/ship` `run_score` event so downstream analysis can correlate scanner characteristics with run outcomes.
4. Build a dedicated `scanner-value-report.sh` analysis script that slices `/ship` score history by scanner cohort (tree-sitter-partial vs regex-fallback vs absent) and reports whether the scanner correlates with better outcomes.
5. Document the statistical sample sizes needed and the tiered confidence levels for trusting scanner value claims.
6. Register `scanner_invocation` in the audit event schema (closing the existing gap).

## Non-Goals

1. Modify the scanner itself (no changes to `codebase-scanner.py` extraction logic, output format, or caching behavior).
2. Build a real-time dashboard or UI -- analysis is CLI-based, consistent with existing tooling.
3. Implement automated A/B testing (manually disabling the scanner to create a control group). The instrumentation supports natural variation (regex fallback when tree-sitter is unavailable, runs where scanner output is empty).
4. Add a new scoring dimension for the scanner. The scanner's value is measured through its impact on existing dimensions (efficiency, quality, velocity), not as its own score.
5. Modify the composite score formula. Scanner correlation is an analysis overlay, not a scoring change.
6. Add scoring to `/architect`. The scanner is invoked in `/architect` Step 1, but `/architect` does not emit `run_score` events (it has verdicts, not scores). Correlating scanner mode with `/architect` plan quality is a future enhancement, not part of this instrumentation.

## Assumptions

1. Sufficient natural variation in scanner modes exists across runs. Some runs use tree-sitter-partial, some use regex-fallback (on machines without the scanner venv), and some have empty scanner output (scanner script not found). If all runs have identical scanner mode, the cohort comparison will report "insufficient variance" rather than produce misleading results.
2. The existing `run_score` event provides a reliable outcome signal. Efficiency, security, and quality dimensions are valid proxies for "run quality."
3. Token count approximation (1 token ~= 4 characters) is sufficient for instrumentation purposes. Exact tokenizer-level counting is not needed for comparative analysis.
4. L2 or L3 maturity is needed for meaningful cross-session analysis (L1 logs are ephemeral). The tooling will work at L1 but warn about limited data.
5. Python 3.10+ is available (consistent with `compute-run-score.sh` and `score-reflector.sh` dependencies). No `jq` dependency -- new scripts use embedded Python only.

---

## Proposed Design

### Architecture Overview

```
                   Existing                              New / Modified
              +------------------+                  +--------------------+
              | /architect       |                  | scanner_invocation |
              | Step 1           |--- emits ------->| event (+ new fields:|
              | (scanner invoke) |                  |   output_token_count,|
              +------------------+                  |   fixed file_count, |
                                                    |   fixed symbol_count)|
              +------------------+                  +--------------------+
              | /ship Step 1     |--- emits ------->|        (same)       |
              | (scanner invoke) |                  +--------------------+
              +------------------+                           |
                                                   (/ship only -- /architect
                                                    has no scoring)
                                                             v
              +------------------+                  +--------------------+
              | compute-run-     |--- emits ------->| run_score event    |
              | score.sh         |                  | (+ new fields:     |
              | (/ship end only) |                  |   scanner_mode,    |
              +------------------+                  |   scanner_tokens)  |
                                                    +--------------------+
                                                           |
                                                           v
                                                    +--------------------+
                                                    | scanner-value-     |
                                                    | report.sh          |
                                                    | (new script)       |
                                                    +--------------------+
                                                           |
                                                           v
                                                    [Cohort comparison,
                                                     correlation report,
                                                     confidence levels]
```

**Note:** `/architect` emits enriched `scanner_invocation` events (with fixed field extraction and `output_token_count`) for completeness and future use, but these events are not correlated with outcomes because `/architect` does not produce `run_score` events. All correlation analysis in this plan operates on `/ship` runs exclusively.

### Change 0: Fix broken field extraction in scanner_invocation (prerequisite)

Both `/architect` and `/ship` currently extract `file_count` and `symbol_count` from the scanner summary header using grep patterns that do not match the actual output format. The skills grep for `Files scanned:` and `Total symbols:`, but the scanner outputs `Files:` and `Symbols:`.

**Current (broken):**
```bash
FILE_COUNT=$(echo "$SCANNER_SUMMARY" | grep -oP 'Files scanned:\s*\K[0-9]+' || echo "unknown")
SYMBOL_COUNT=$(echo "$SCANNER_SUMMARY" | grep -oP 'Total symbols:\s*\K[0-9]+' || echo "unknown")
```

**Fixed:**
```bash
FILE_COUNT=$(echo "$SCANNER_SUMMARY" | grep -oP 'Files:\s*\K[0-9]+' || echo "0")
SYMBOL_COUNT=$(echo "$SCANNER_SUMMARY" | grep -oP 'Symbols:\s*\K[0-9]+' || echo "0")
```

The default is changed from `"unknown"` to `"0"` (integer) so these fields always emit numeric values, consistent with the schema definition (integer type).

### Change 1: Add `output_token_count` to scanner_invocation

Both `/architect` and `/ship` already compute `SCANNER_HASH` from the scanner output. After that computation, add a token count estimate:

```bash
SCANNER_TOKEN_COUNT=$(printf '%s' "$SCANNER_OUTPUT" | wc -c | awk '{printf "%.0f", $1 / 4}')
```

The `output_token_count` field is appended to the existing `scanner_invocation` event JSON.

### Change 2: Propagate scanner metadata into run_score (/ship only)

`compute-run-score.sh` already reads the entire JSONL audit log to extract verdict and security_decision events. It will additionally extract the `scanner_invocation` event (if present in the same log) and embed two new fields in the `run_score` output:

- `scanner_mode`: value of `parser_mode` from the `scanner_invocation` event, or `"absent"` if no scanner_invocation event exists in the log.
- `scanner_tokens`: value of `output_token_count` from the `scanner_invocation` event, or `0` if absent.

These fields are informational (not dimensions, not in the composite score). They travel with the `run_score` event so downstream analysis tools can correlate without re-reading the full JSONL log.

**Scope note:** Only `/ship` calls `compute-run-score.sh`, so only `/ship` `run_score` events carry scanner metadata. `/architect` logs contain `scanner_invocation` events but no `run_score` events. This is intentional -- adding scoring to `/architect` would be scope expansion.

### Change 3: New analysis script -- `scripts/scanner-value-report.sh`

A new shell script wrapping embedded Python (following the `score-reflector.sh` pattern). It reads all `run_score` events from `plans/audit-logs/ship-*.jsonl` (scoped to `/ship` logs only -- `/architect` logs do not contain `run_score` events), groups them by `scanner_mode`, and produces a comparative report.

**Output format (markdown):**

```
## Scanner Value Report (N /ship runs analyzed)

### Caveat
This is observational data, not a randomized experiment. Correlations below
do NOT imply causation. Confounders (developer skill, project type, plan
complexity) may explain observed differences. See Statistical Assessment.

### Cohort Summary
| Cohort              | Runs | Efficiency | Security | Quality | Composite | Velocity (min) |
|---------------------|------|------------|----------|---------|-----------|----------------|
| tree-sitter-partial |   12 | 0.87       | 0.95     | 0.82    | 0.88      | 14.2           |
| regex-fallback      |    5 | 0.72       | 0.90     | 0.68    | 0.77      | 18.7           |
| absent              |    3 | 0.60       | 0.85     | 0.55    | 0.67      | 22.1           |

### Token Cost
| Cohort              | Mean Tokens | Median Tokens |
|---------------------|-------------|---------------|
| tree-sitter-partial |        1850 |          1720 |
| regex-fallback      |        1200 |          1150 |

### Statistical Assessment
- Sample sizes: tree-sitter-partial=12, regex-fallback=5, absent=3
- Confidence level: PRELIMINARY (need 15+ per cohort for RELIABLE)
- Effect size (composite, tree-sitter-partial vs absent): +0.21 (LARGE, d=1.3)
- Recommendation: Continue collecting data. 8 more regex-fallback runs needed for RELIABLE threshold.

### Correlations
- [Correlation] tree-sitter-partial runs have higher mean efficiency (0.87 vs 0.72) than regex-fallback runs.
- [Correlation] tree-sitter-partial runs have lower mean velocity (14.2 min vs 18.7 min) than regex-fallback runs.
- [Caution] Small sample sizes -- correlations are directional, not conclusive. Multiple confounders (developer skill, codebase type) are not controlled for.
```

### Change 4: Register scanner_invocation in audit event schema

Add `"scanner_invocation"` to the `event_type` enum in `configs/audit-event-schema.json` and add a `scanner_invocation` oneOf entry defining its fields.

### Change 5: Update score-reflector.sh

Add scanner-aware analysis to the reflector. When 10+ `/ship` runs are available, the reflector checks whether scanner mode correlates with score outcomes and can generate a candidate learning like:

```
- **[2026-05-25] Scanner mode correlates with efficiency** [Medium] -- tree-sitter-partial /ship runs have 0.15 higher mean efficiency than regex-fallback runs (0.87 vs 0.72 across 17 runs). Correlation only -- confounders not controlled. Investigate whether tree-sitter venv presence is a factor.
  #scanner #efficiency (2026-05-25)
```

---

## Statistical Sample Size Analysis

### The Core Question

"How long should I run it before I start to trust the data?"

This depends on three factors: (1) the effect size you're trying to detect, (2) the variance in your measurements, and (3) the confidence level you need.

### Effect Size Assumptions

What magnitude of difference would be meaningful?

| Metric | Meaningful Difference | Rationale |
|--------|----------------------|-----------|
| Efficiency (revision rounds) | 0.15 points (~1 fewer revision in 3 runs) | Revision rounds are the primary coder quality signal. A 0.15 difference means tree-sitter runs need ~37% fewer revision rounds. |
| Quality (CR + QA) | 0.15 points | Similar reasoning to efficiency. |
| Velocity (wall-clock minutes) | 3-5 minutes per run | If runs average 15-20 minutes, a 3-5 minute reduction (~20%) is operationally meaningful. |
| Composite | 0.10 points | Composite aggregates efficiency, security, quality. A 0.10 difference is noticeable. |
| Token cost (output_token_count) | Descriptive only | Token cost is a cost metric, not an outcome metric. No effect size threshold needed -- just report the number. |

### Variance Estimates

Score dimensions range 0.0-1.0. Based on the existing scoring formulas:

- **Efficiency** has discrete steps: 1.0 (0 revisions), 0.6 (1 revision), 0.2 (2 revisions), 0.5 (neutral). Expected standard deviation: ~0.25.
- **Quality** is similarly discrete: steps of 0.3 and 0.5 from a base of 1.0. Expected standard deviation: ~0.20.
- **Security** tends to cluster at 1.0 (PASS) or 0.7 (BLOCKED). Expected standard deviation: ~0.15.
- **Composite** averages these, reducing variance. Expected standard deviation: ~0.15.

### Sample Size Calculations

Using a simplified power analysis framework (two-sample t-test, alpha=0.05 two-tailed, power=0.80):

**Formula:** n per group = 2 * ((z_alpha/2 + z_beta) * sigma / delta)^2

Where sigma is pooled standard deviation and delta is the minimum detectable effect.

| Effect Size (delta) | Assumed SD (sigma) | n per cohort (power=0.80) | n per cohort (power=0.90) |
|--------------------|--------------------|--------------------------|--------------------------|
| 0.10 (composite) | 0.15 | 36 | 48 |
| 0.15 (efficiency/quality) | 0.25 | 44 | 59 |
| 0.15 (efficiency/quality) | 0.20 | 28 | 38 |
| 0.20 (large effect) | 0.25 | 25 | 34 |
| 0.20 (large effect) | 0.20 | 16 | 22 |

### Confounders

Scanner mode is NOT randomly assigned. Confounders affect both the scanner mode and the run outcome:

| Confounder | Effect | Mitigation |
|-----------|--------|------------|
| **Plan complexity** | Complex plans have more revision rounds regardless of scanner. Tree-sitter might be available on the same machine that handles complex plans. | Report effect sizes alongside raw means. Look for within-machine variation when the same developer runs both modes. |
| **Codebase size** | Large codebases produce larger scanner output AND may have more revision rounds. | Include file_count and symbol_count in the report. Bucket analysis by codebase size if data permits. |
| **Developer skill** | More experienced developers may have tree-sitter installed AND write better code. | This is a real confounder in observational data. Acknowledge it in the report. Controlled experiments (deliberately disabling tree-sitter for some runs) would address this but are out of scope. |
| **Project type** | Python-heavy projects get tree-sitter parsing; TypeScript projects get regex. Language may correlate with run quality. | Report per-language parser_mode distribution. |
| **Time/learning effects** | Later runs may score better simply because the developer is learning. Scanner mode may shift over time too. | Plot scores chronologically with scanner mode annotations. |

**Key insight:** This is observational data, not a randomized experiment. The analysis can detect correlation but cannot prove causation. The report will explicitly state this.

### Tiered Confidence Levels

The `scanner-value-report.sh` script will report one of four confidence tiers:

| Tier | Total Runs | Per-Cohort Minimum | What You Can Claim | Label |
|------|-----------|--------------------|--------------------|-------|
| **INSUFFICIENT** | < 5 total | N/A | Nothing -- not enough data to analyze | "Insufficient data" |
| **PRELIMINARY** | 5-14 total, or < 5 in any non-empty cohort | >= 3 in at least 2 cohorts | Directional signals only. "tree-sitter runs tend to score higher, but sample size is too small to be confident." | "Preliminary signal" |
| **RELIABLE** | 15-29 total, >= 8 per non-empty cohort | >= 8 per cohort | Meaningful comparison. Effect sizes are reportable. "tree-sitter runs score 0.15 higher on efficiency (n=12 vs n=8, d=0.8)." Confounders acknowledged. | "Reliable comparison" |
| **HIGH_CONFIDENCE** | 30+ total, >= 15 per non-empty cohort | >= 15 per cohort | Strong evidence. Effect sizes with confidence intervals. Trend analysis within cohorts. "tree-sitter runs consistently score higher across 3+ weeks of data." | "High confidence" |

### Relationship to Existing Thresholds

The `score-reflector.sh` uses:
- < 5 runs = "Insufficient data"
- 5-9 runs = Summary statistics only
- 10+ runs = Trends with linear regression

These thresholds are appropriate for **overall score trends** (single population). Scanner value assessment requires **cohort comparison** (two or more populations), which needs larger samples because you're splitting the data. The scanner-value-report thresholds are intentionally higher:

- score-reflector needs 10 runs total for trends
- scanner-value-report needs 15+ total AND 8+ per cohort for reliable comparison

This is the correct relationship: comparing groups requires more data than analyzing a single group.

### Practical Timeline Estimates

Assuming a development cadence of:
- 2-4 `/ship` runs per week (the only scored skill -- all timeline estimates count `/ship` runs exclusively)
- 1-2 `/architect` runs per week (emits `scanner_invocation` but NOT `run_score`; these runs do NOT contribute to correlation analysis)

| Milestone | `/ship` Runs Needed | Calendar Time | What You Learn |
|-----------|---------------------|---------------|----------------|
| First signal | 5 total | ~2 weeks | "Scanner is present and logging data. No comparisons possible yet." |
| Preliminary comparison | 10 total, 3+ per cohort | ~4 weeks | "Directional signal: tree-sitter-partial runs tend to score higher/lower/same." |
| Reliable comparison | 20 total, 8+ per cohort | ~6-10 weeks | "Effect sizes are meaningful. Tree-sitter-partial correlates with +0.15 on efficiency (or not)." |
| High confidence | 30+ total, 15+ per cohort | ~12-16 weeks | "Confident correlation report: scanner mode is/is not associated with measurable outcome differences." |

**Why only /ship runs count:** `/architect` emits `scanner_invocation` events but does not call `compute-run-score.sh` and does not emit `run_score` events. Correlation analysis requires both scanner metadata and outcome scores in the same run. Adding scoring to `/architect` is out of scope (see Non-Goals).

**Accelerating the timeline:** If you need faster results, you can:
1. Run `/ship` on smaller plans to increase run frequency.
2. Deliberately disable the scanner venv on some runs (`rm ~/.claude-devkit/scanner-venv/bin/python3` temporarily) to create a regex-fallback cohort.
3. Use L2 maturity to ensure all logs persist across sessions.

---

## Interfaces / Schema Changes

### Modified: `scanner_invocation` event (in skills)

New field:

```json
{
  "output_token_count": 1850
}
```

Type: integer. Approximate token count of the scanner's summary output (character count / 4, rounded).

### Modified: `run_score` event (in compute-run-score.sh output)

New fields:

```json
{
  "scanner_mode": "tree-sitter-partial",
  "scanner_tokens": 1850
}
```

- `scanner_mode`: string, one of `"tree-sitter-partial"`, `"regex-fallback"`, `"absent"`. Extracted from `scanner_invocation.parser_mode` in the same run's log. Default `"absent"` if no `scanner_invocation` event found. (The value `"tree-sitter"` is reserved for future use when the scanner supports full tree-sitter extraction for all languages; it is not included in the enum until that code path exists.)
- `scanner_tokens`: integer, extracted from `scanner_invocation.output_token_count`. Default `0` if absent.

These fields are NOT dimensions -- they have no weight and do not affect the composite score.

### Modified: `configs/audit-event-schema.json`

1. Add `"scanner_invocation"` to the `event_type` enum.
2. Add a `scanner_invocation` entry to the `oneOf` array defining its fields:
   - `scanner_version` (string, required)
   - `parser_mode` (string, enum: `["tree-sitter-partial", "regex-fallback"]`, required)
   - `file_count` (integer, required)
   - `symbol_count` (integer, required)
   - `output_sha256` (string, required)
   - `output_token_count` (integer, required)

3. Add `scanner_mode` and `scanner_tokens` as optional fields to the `run_score` definition.

### New: `configs/scanner-value-thresholds.json`

```json
{
  "title": "Scanner Value Analysis Thresholds",
  "version": "1.0.0",
  "description": "Configuration for scanner-value-report.sh confidence tiers and effect size thresholds.",
  "confidence_tiers": {
    "INSUFFICIENT": {
      "min_total_runs": 0,
      "max_total_runs": 4,
      "min_per_cohort": 0,
      "label": "Insufficient data"
    },
    "PRELIMINARY": {
      "min_total_runs": 5,
      "max_total_runs": 14,
      "min_per_cohort": 3,
      "label": "Preliminary signal"
    },
    "RELIABLE": {
      "min_total_runs": 15,
      "max_total_runs": 29,
      "min_per_cohort": 8,
      "label": "Reliable comparison"
    },
    "HIGH_CONFIDENCE": {
      "min_total_runs": 30,
      "min_per_cohort": 15,
      "label": "High confidence"
    }
  },
  "effect_size_thresholds": {
    "small": 0.10,
    "medium": 0.15,
    "large": 0.20
  },
  "notes": {
    "token_approximation": "1 token ~= 4 characters. This is a rough estimate for comparative purposes, not an exact tokenizer count.",
    "confounders": "Scanner mode is not randomly assigned. Cohort comparisons are observational, not experimental. Correlations do not imply causation. Confounders include developer skill, project type, plan complexity, and time/learning effects.",
    "scope": "Analysis covers /ship runs only. /architect emits scanner_invocation but has no scoring, so architect runs are excluded from correlation analysis.",
    "existing_reflector_thresholds": "score-reflector.sh uses 5/10 thresholds for single-population trend analysis. Scanner value assessment uses higher thresholds (15/30) because cohort comparison requires more data than single-group analysis."
  }
}
```

---

## Data Migration

None. New fields are added to existing events with backward-compatible defaults. Analysis scripts handle missing fields gracefully (default `scanner_mode` to `"absent"`, `scanner_tokens` to `0`).

Old `run_score` events (without `scanner_mode`/`scanner_tokens`) will be treated as `scanner_mode: "absent"` by `scanner-value-report.sh` and excluded from cohort comparisons. They will still appear in overall trend analysis. There is a single sentinel value: `"absent"` means "no scanner data available for this run" regardless of whether the field is missing (pre-instrumentation) or present with value `"absent"` (post-instrumentation, scanner not invoked).

---

## Implementation Plan

### Phase 0: Fix Broken Field Extraction (prerequisite)

**Estimated effort:** 0.5 days
**Dependencies:** None
**Deliverable:** Fixed `file_count` and `symbol_count` extraction in both skills

1. Fix grep patterns in `/architect` SKILL.md: `Files scanned:` to `Files:`, `Total symbols:` to `Symbols:`. Change default from `"unknown"` to `"0"`.
2. Fix grep patterns in `/ship` SKILL.md: same changes.

### Phase 1: Schema and Event Enrichment

**Estimated effort:** 1 day
**Dependencies:** Phase 0
**Deliverable:** Updated schema, enriched events in both skills and compute-run-score.sh

1. Add `scanner_invocation` to `configs/audit-event-schema.json` enum and oneOf array (with `file_count` and `symbol_count` as integer type, `parser_mode` enum as `["tree-sitter-partial", "regex-fallback"]`).
2. Add `output_token_count` field to the scanner invocation blocks in `/architect` SKILL.md and `/ship` SKILL.md.
3. Add `scanner_mode` and `scanner_tokens` optional fields to the `run_score` definition in the schema.
4. Modify `scripts/compute-run-score.sh` to extract `scanner_invocation` data from the JSONL log and embed `scanner_mode` and `scanner_tokens` in the output JSON.

### Phase 2: Analysis Script

**Estimated effort:** 2 days
**Dependencies:** Phase 1
**Deliverable:** Working `scanner-value-report.sh` with cohort comparison (~550 lines)

1. Create `scripts/scanner-value-report.sh` following the `score-reflector.sh` pattern (bash wrapper, embedded Python). Reads `plans/audit-logs/ship-*.jsonl` only (not architect logs).
2. Create `configs/scanner-value-thresholds.json` with confidence tier configuration.
3. Implement cohort grouping, per-dimension mean comparison, effect size calculation (Cohen's d), confidence tier assignment, markdown and JSON output. Handle Cohen's d edge cases (cohort size 1, pooled SD = 0).

### Phase 3: Score Reflector Enhancement

**Estimated effort:** 0.5 days
**Dependencies:** Phase 1
**Deliverable:** Scanner-aware candidate learnings in score-reflector.sh

1. Add scanner mode correlation check to `scripts/score-reflector.sh` (10+ `/ship` runs path).
2. Generate candidate learning (using correlational language, not causal) when scanner mode shows statistically notable correlation with a dimension.

### Phase 4: Testing and Documentation

**Estimated effort:** 1 day
**Dependencies:** Phases 1-3
**Deliverable:** Integration tests, updated CLAUDE.md

1. Add integration tests to `scripts/test-integration.sh` for new fields and analysis script.
2. Update `CLAUDE.md` with scanner-value-report.sh documentation.
3. Run full validation suite.

---

## Rollout Plan

### Days 1-2: Implementation (Phases 0-1)
Fix broken field extraction. Deploy enriched events and schema updates. From this point forward, all `/ship` and `/architect` runs emit corrected scanner metadata with `output_token_count`.

### Days 3-4: Analysis Script (Phase 2)
Build `scanner-value-report.sh` with cohort comparison.

### Day 5: Testing and Polish (Phases 3-4)
Score reflector enhancement. Integration tests. Documentation. Deploy skills.

### Week 2-4: Data Collection
Run `/ship` normally. Scanner-value-report.sh shows "Insufficient data" or "Preliminary signal." No action needed. (`/architect` runs emit scanner data but are not counted toward correlation analysis.)

### Week 6-10: First Reliable Comparison
With ~20 `/ship` scored runs and 8+ per cohort, run `scanner-value-report.sh` for the first reliable comparison. Review correlations. Consider deliberate A/B testing if cohort sizes are imbalanced. (Timeline is longer than if `/architect` runs counted -- only 2-4 `/ship` runs per week contribute to scoring.)

### Week 12-16: High Confidence Decision
With ~30 `/ship` scored runs and 15+ per cohort, the report provides high-confidence correlations. Make a go/no-go decision on scanner investment (e.g., expanding tree-sitter coverage to TypeScript/Java/Go).

### Rollback Plan

1. **Enriched events cause issues:** Revert the skill SKILL.md changes (remove `output_token_count` from scanner_invocation blocks). `compute-run-score.sh` handles missing scanner data gracefully (defaults to `"absent"` / `0`).
2. **Analysis script errors:** `scanner-value-report.sh` is standalone and never blocks any skill. Delete it.
3. **Schema changes break validation:** The schema change only adds to enums and oneOf -- it is backward compatible. No existing validation should break.

---

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| `/architect` scanner data is not correlated with outcomes | Certain | Medium | `/architect` does not emit `run_score`. Scanner value is measured through `/ship` runs only. `/architect` `scanner_invocation` events are emitted for completeness but not analyzed. This halves the effective data collection rate. Timeline estimates adjusted accordingly. |
| Insufficient cohort variance (all runs use same scanner mode) | Medium | Medium | Report warns "insufficient variance." User can create variance by temporarily removing scanner venv. |
| Confounders mask or exaggerate scanner effect | High | Medium | Report explicitly states "observational, not experimental." Correlational language only. Effect sizes reported alongside raw means. Confounders listed before findings. |
| Token count approximation (chars/4) is inaccurate | Low | Low | Used for comparative analysis only. Consistent approximation is sufficient for cohort comparison. |
| Old run_score events (pre-instrumentation) pollute analysis | Low | Low | Treated as `scanner_mode: "absent"` and excluded from cohort comparisons. |
| L1 log ephemerality limits cross-session analysis | Medium | Medium | Warning displayed by scanner-value-report.sh. Recommendation to use L2/L3 for meaningful analysis. |
| Analysis script produces misleading conclusions from small samples | Medium | High | Tiered confidence levels with conservative thresholds. PRELIMINARY tier explicitly says "directional only, not conclusive." Correlational framing throughout. |

---

## Test Plan

### Integration Tests (added to test-integration.sh)

```bash
# Test 38: compute-run-score.sh extracts scanner_mode from scanner_invocation event
# Synthetic log with scanner_invocation + verdict events -> run_score includes scanner_mode

# Test 39: compute-run-score.sh defaults scanner_mode to "absent" when no scanner_invocation
# Synthetic log without scanner_invocation -> run_score.scanner_mode == "absent"

# Test 40: scanner-value-report.sh runs without errors on empty audit-logs directory
# Empty dir -> exits 0, prints "insufficient data" message

# Test 41: scanner-value-report.sh produces markdown output for synthetic scored runs
# 6 synthetic run_score events (3 tree-sitter, 3 regex) -> markdown output with cohort table

# Test 42: scanner_invocation in audit-event-schema.json enum
# grep for scanner_invocation in schema file -> found
```

### Exact Test Command

```bash
bash generators/test_skill_generator.sh && bash scripts/test-integration.sh && python3 scripts/codebase-scanner.py --self-test
```

### Manual Validation

```bash
# Run scanner-value-report.sh against existing audit logs
bash scripts/scanner-value-report.sh

# Run with JSON output
bash scripts/scanner-value-report.sh --format json

# Verify compute-run-score.sh new fields
echo '{"event_type":"scanner_invocation","parser_mode":"tree-sitter-partial","output_token_count":1500}' > /tmp/test-scanner-score.jsonl
echo '{"event_type":"run_start","timestamp":"2026-05-25T10:00:00Z"}' >> /tmp/test-scanner-score.jsonl
echo '{"event_type":"verdict","verdict":"PASS","verdict_source":"code_review"}' >> /tmp/test-scanner-score.jsonl
bash scripts/compute-run-score.sh /tmp/test-scanner-score.jsonl | python3 -m json.tool
# Verify output contains scanner_mode and scanner_tokens fields
```

---

## Acceptance Criteria

1. `scanner_invocation` events in both `/architect` and `/ship` include `output_token_count` field.
2. `scanner_invocation` is registered in `configs/audit-event-schema.json` with all fields defined.
3. `compute-run-score.sh` output includes `scanner_mode` and `scanner_tokens` fields, correctly extracted from `scanner_invocation` event in the same log.
4. `compute-run-score.sh` defaults `scanner_mode` to `"absent"` and `scanner_tokens` to `0` when no `scanner_invocation` event exists.
5. `scanner-value-report.sh` reads `run_score` events from `plans/audit-logs/ship-*.jsonl`, groups by `scanner_mode`, and produces a markdown comparison report.
6. `scanner-value-report.sh` assigns correct confidence tier based on sample sizes.
7. `scanner-value-report.sh` computes and reports Cohen's d effect size for composite score between cohorts.
8. `scanner-value-report.sh --format json` produces valid JSON output.
9. `score-reflector.sh` generates a scanner-correlation candidate learning when 10+ runs show scanner mode correlating with a dimension.
10. `configs/scanner-value-thresholds.json` defines all four confidence tiers with correct thresholds.
11. All existing tests pass (`bash generators/test_skill_generator.sh` and `bash scripts/test-integration.sh`).
12. 5 new integration tests pass in `test-integration.sh`.

---

## Task Breakdown

## Work Groups

### Shared Dependencies

- `configs/audit-event-schema.json` (modify -- add scanner_invocation to enum and oneOf with `parser_mode` enum `["tree-sitter-partial", "regex-fallback"]`, `file_count`/`symbol_count` as integer; add scanner_mode/scanner_tokens to run_score)
- `configs/scanner-value-thresholds.json` (create -- confidence tier configuration)

### Work Group 1: Event Enrichment

- `skills/architect/SKILL.md` (modify -- fix grep patterns `Files scanned:` to `Files:` and `Total symbols:` to `Symbols:`, change default from `"unknown"` to `"0"`, add output_token_count to scanner_invocation emission block, ~8 lines)
- `skills/ship/SKILL.md` (modify -- same grep pattern fixes, add output_token_count to scanner_invocation emission block, ~8 lines)
- `scripts/compute-run-score.sh` (modify -- extract scanner_invocation from JSONL, add scanner_mode and scanner_tokens to output JSON, ~30 lines)

### Work Group 2: Analysis Tooling

- `scripts/scanner-value-report.sh` (create -- cohort comparison analysis script, ~550 lines, bash wrapper + embedded Python following score-reflector.sh pattern. Reads `ship-*.jsonl` only. Correlational language throughout.)
- `scripts/score-reflector.sh` (modify -- add scanner mode correlation check in 10+ `/ship` runs path, correlational language, ~40 lines)

### Work Group 3: Testing and Documentation

- `scripts/test-integration.sh` (modify -- add 5 new integration tests for scanner value instrumentation, ~80 lines)
- `CLAUDE.md` (modify -- add scanner-value-report.sh to Scripts section, update test count from 37 to 42, add scanner-value-thresholds.json to configs section, ~15 lines)

---

## Context Alignment

### CLAUDE.md Patterns Followed

1. **Scripts in `scripts/` directory** -- `scanner-value-report.sh` follows the established pattern of standalone analysis scripts (`score-reflector.sh`, `compute-run-score.sh`).
2. **Bash wrapper with embedded Python** -- `scanner-value-report.sh` uses the same architecture as `score-reflector.sh` (bash argument parsing, embedded `python3 -` heredoc for computation).
3. **Configs in `configs/` directory** -- `scanner-value-thresholds.json` follows the pattern of `score-dimensions.json` and `audit-event-schema.json`.
4. **Integration testing in `test-integration.sh`** -- New tests follow the existing `run_test()` pattern.
5. **Exit code conventions** -- Always exits 0 for analysis scripts (same as `score-reflector.sh` and `compute-run-score.sh`).
6. **JSONL audit logging** -- Enriched events follow the established JSONL format with the same escaping and emission patterns.
7. **Tiered analysis levels** -- Confidence tiers (INSUFFICIENT/PRELIMINARY/RELIABLE/HIGH_CONFIDENCE) follow the precedent of score-reflector.sh's tiered analysis (insufficient/<5, summary/5-9, trends/10+).
8. **No jq dependency for new scripts** -- `scanner-value-report.sh` uses `python3` only, consistent with `compute-run-score.sh` and `score-reflector.sh`. (Note: `audit-log-query.sh` uses jq, but the newer scripts avoid it.)

### Prior Plans This Builds Upon

1. **codebase-symbol-index.md** (APPROVED, implemented) -- This plan directly extends Phase 6 (Measurement and Evaluation) from the original scanner plan. Phase 6 proposed manual baseline/treatment measurement; this plan replaces it with automated, ongoing instrumentation.
2. **devkit-hygiene-improvements.md** (APPROVED) -- Established the integration test infrastructure extended here.

### Deviations from Established Patterns

1. **scanner_invocation schema gap** -- The `scanner_invocation` event type is currently emitted by skills but NOT listed in `configs/audit-event-schema.json`. This plan closes that gap. This is a correction, not a deviation.
2. **Cross-event field propagation in compute-run-score.sh** -- Today, `compute-run-score.sh` reads only `verdict` and `security_decision` events. This plan adds reading `scanner_invocation` events and propagating their fields into the `run_score` output. This is a new pattern (reading one event type to enrich another), but it follows the same "read JSONL, extract, compute, output JSON" architecture.
3. **Broken grep pattern fix (Change 0)** -- Existing `scanner_invocation` field extraction is broken (grep patterns do not match scanner output format). This plan fixes it as a prerequisite since the same lines are being modified. This is a bug fix, not a deviation.

---

<!-- Context Metadata
discovered_at: 2026-05-25T17:19:43Z
claude_md_exists: true
recent_plans_consulted: codebase-symbol-index.md, agentic-sdlc-security-skills.md, audit-remove-mcp-deps.md
archived_plans_consulted: agentic-sdlc-next-phase.feasibility.md
-->

## Status: APPROVED
