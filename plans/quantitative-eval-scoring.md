# Plan: Quantitative Eval/Scoring System for Claude Devkit

## Revision Log

| Rev | Date | Trigger | Summary |
|-----|------|---------|---------|
| 1 | 2026-05-09 | Initial draft | Original plan submitted for review |
| 2 | 2026-05-09 | Red team FAIL + Feasibility REVISE + Librarian PASS | **C1:** Redesigned efficiency dimension to derive revision round count from `step_start`/`step_end` events (step_5_revision_loop) instead of nonexistent `run_end.revision_rounds` field. **M1:** Moved `run_score` emission before `run_end` to ensure inclusion in L2/L3 committed logs and HMAC chain. **M2:** Documented `steps_completed` as schema-defined-but-not-emitted; quality dimension already uses verdict events (not `steps_completed`). **M3:** `run_score` now precedes `run_end`, eliminating the "after run_end" convention break. **F1:** Dropped jq from `compute-run-score.sh` deps; python3 only. **F2:** Raised reflector `--min-runs` to 10 for trend claims; 5-9 runs get summary stats only. **F3:** Documented L1 ephemeral log limitation for reflector. **F4:** Added 4 negative test cases. **Librarian:** Fixed "Files to Create" count (3 not 4), added test-integration.sh test 16 version update and CLAUDE.md test count update to scope, made `score-dimensions.json` a plain data file (no `$schema`). |
| 3 | 2026-05-09 | Red team PASS (new Major) + Feasibility REVISE (new Critical) | **R2-F01/R2-C1:** Step 5 emits exactly one `step_start`/`step_end` pair wrapping the entire revision loop — individual rounds do not get their own step events. Changed efficiency dimension to count `verdict` events with `verdict_source == "code_review"` instead: 1 verdict = 0 revision rounds, 2 = 1 round, 3 = 2 rounds. Updated pseudocode, dimension table, design note, score-dimensions.json, tests, and acceptance criteria. |

## Context

Claude devkit skills are stateless. Each `/ship`, `/architect`, or `/audit` run executes identically regardless of whether the last 10 runs all hit the same revision loop failure, or whether security findings have been trending upward for a month. The existing verdict gate system (PASS/FAIL/BLOCKED) provides a binary quality signal but no gradient -- there is no difference between a PASS that required zero revisions and a PASS that barely scraped through after two revision rounds with five security findings downgraded at L1.

The JSONL audit log infrastructure (`plans/audit-logs/`, `scripts/emit-audit-event.sh`, `scripts/audit-log-query.sh`) already records rich structured data per run (step timing, verdicts, security decisions, file modifications). But no mechanism aggregates this data across runs, computes quantitative metrics, or feeds outcomes back into subsequent skill invocations.

**Problem statement:** Skills cannot learn from prior runs. A coder agent that consistently produces code requiring revision loops receives no signal to change its approach. A project whose security posture is degrading run-over-run has no dashboard showing the trend.

**Reference system:** remote-factory (at `~/projects/remote-factory`) solves analogous problems with a three-tier composite scoring system (hygiene + growth + project dimensions, each returning EvalResult with 0-1 score and weight), an append-only experiment store (TSV + per-experiment artifacts), and ACE self-improvement (deterministic reflector extracts statistics from outcomes, generates candidate playbook bullets with helpful/harmful counters, curator prunes net-negative items). The key architectural insight from remote-factory is that reflection is purely statistical -- no LLM needed for the feedback loop. Devkit's adaptation must respect the markdown-skill constraint (skills cannot import Python libraries; scoring logic lives in standalone scripts).

**Current state:**
- Binary verdict gates: PASS / FAIL / BLOCKED / PASS_WITH_NOTES / REVISION_NEEDED
- JSONL audit logs with event types: run_start, run_end, step_start, step_end, verdict, security_decision, file_modification, error
- `run_end` events currently emit `outcome`, `commit_sha` (success path), and `plan_file`. The schema also defines `revision_rounds` and `steps_completed` fields on `run_end`, but **neither field is currently emitted** by `/ship`, `/architect`, or `/audit`. These are schema placeholders that were never wired into the coordinator prose.
- `.claude/learnings.md` captures qualitative learnings from `/retro` and `/ship` Step 7
- `scripts/audit-log-query.sh` provides summary, timeline, security, verdicts, files, overrides, recent commands

**Target state:** After implementation, each skill run that opts in will emit a `run_score` event near the end of its run (before `run_end`), containing per-dimension 0-1 scores. A query command will show score trends across runs. The existing `.claude/learnings.md` mechanism will be enhanced with statistically-derived entries from score patterns.

## Goals

1. Define scoring dimensions relevant to devkit skill runs (not remote-factory dimensions)
2. Add `run_score` event type to the audit event schema and emit-audit-event.sh infrastructure
3. Instrument `/ship` to emit per-run scores based on data already available in its audit log
4. Add score query/trending commands to `audit-log-query.sh`
5. Add a deterministic score-reflector script that analyzes score history and proposes learnings

## Non-Goals

1. **Automated playbook evolution** -- Not injecting generated guidance into skill SKILL.md files automatically. v1 generates candidate learnings for human review.
2. **LLM-based reflection** -- v1 reflector is purely statistical (following remote-factory's design). No LLM calls in the scoring or reflection pipeline.
3. **Cross-project scoring** -- v1 scores are per-project (scoped to `./plans/audit-logs/`). Cross-project aggregation is future work.
4. **Real-time dashboards** -- v1 is CLI query tools. TUI/web dashboards are future work.
5. **Scoring for /architect and /audit** -- v1 instruments `/ship` only. `/architect` and `/audit` scoring is Phase 2.
6. **Modifying verdict gates based on scores** -- Verdicts remain binary. Scores augment verdicts; they do not replace them.
7. **Test coverage measurement** -- Parsing test coverage from arbitrary test runners is fragile. v1 scores what the audit log already captures.
8. **Backfill scoring for historical runs** -- `compute-run-score.sh` could retroactively score old logs, but this is not v1 scope.

## Assumptions

1. `python3` is available (same dependency as existing audit infrastructure via `emit-audit-event.sh`)
2. Existing JSONL audit logs are the canonical persistence layer -- no new storage backends
3. Skills will emit `run_score` events via `emit-audit-event.sh` (same mechanism as all other events)
4. The scoring system is opt-in per skill -- skills that do not emit `run_score` simply have no scores
5. Score dimensions and weights may evolve; the schema should accommodate this without breaking old data
6. `.claude/learnings.md` remains the canonical feedback mechanism for skill agents

## Architectural Analysis

### Scoring Dimensions for Devkit Skills

Remote-factory's dimensions (project growth, experiment diversity, hygiene) do not apply to devkit skills. Devkit skills coordinate code implementation, review, and security scanning. The relevant dimensions are:

| Dimension | Weight | Source | Scoring Logic | Rationale |
|-----------|--------|--------|---------------|-----------|
| **efficiency** | 0.25 | `verdict` events with `verdict_source == "code_review"` | Count `verdict` events where `verdict_source == "code_review"`. 1 verdict = 0 revision rounds (Step 4 ran once) = 1.0. 2 verdicts = 1 revision round (Step 5 re-ran Step 4) = 0.6. 3 verdicts = 2 revision rounds = 0.2. Formula: `1.0 - (max(0, verdict_count - 1) * 0.4)`, floor 0.0. 0 verdicts (no code review ran) = 0.5 (neutral). | Measures how clean the implementation was. Fewer revision rounds = better coder-reviewer alignment. Derived from code_review verdict count: Step 4 emits one verdict per pass, and Step 5 re-runs Step 4 per revision round, so verdict count directly maps to revision rounds + 1. |
| **security** | 0.25 | `security_decision` events | Start at 1.0. Each BLOCKED gate: -0.3 (even if downgraded/overridden). Each PASS_WITH_NOTES gate: -0.1. All PASS or not-run: 1.0. Floor at 0.0. | Measures security posture. Overrides are still penalized (they indicate real findings). |
| **quality** | 0.25 | `verdict` events (code_review, qa sources) | Start at 1.0. Code review REVISION_NEEDED on first pass: -0.3. Code review FAIL: -0.5. QA PASS_WITH_NOTES: -0.1. QA FAIL: -0.5. Floor at 0.0. | Measures implementation quality from reviewer/QA perspective. |
| **velocity** | 0.25 | `run_start.timestamp`, `run_end.timestamp` | Computed but NOT included in composite score for v1. Reported as informational. Duration in minutes, no normalization. | Wall-clock time varies too much (model latency, human interruption, machine load). Informational only in v1. |

**Composite score** = weighted sum of efficiency, security, quality. Velocity is reported but excluded from composite. Effective weight normalization: efficiency 1/3, security 1/3, quality 1/3.

**Design rationale for equal weights:** In v1, all three active dimensions are equally important. A project that ships fast but insecurely, or securely but requiring constant revisions, is not healthy. Weights are configurable for future tuning.

**Neutral score behavior:** If a dimension cannot be computed (e.g., no security gates ran because no security skills are deployed), the dimension scores 0.5 (neutral) rather than 1.0 or 0.0. This follows remote-factory's principle: missing data should not artificially inflate or penalize scores.

**Efficiency dimension design note:** The `run_end` event schema defines `revision_rounds` and `steps_completed` fields, but neither field is currently emitted by any skill coordinator. Additionally, `/ship` Step 5 emits exactly one `step_start`/`step_end` pair wrapping the entire revision loop — individual rounds within the loop do not get their own step events. The efficiency dimension therefore counts `verdict` events with `verdict_source == "code_review"`: Step 4 emits one code_review verdict per pass, and Step 5 re-runs Step 4 on each revision round. This gives verdict_count = revision_rounds + 1, which reliably distinguishes 0, 1, and 2 revision rounds. If `/ship` later populates `revision_rounds` in `run_end`, the scoring script can be updated to prefer that field, but v1 does not depend on it.

**Coupling note:** The efficiency formula assumes `/ship`'s max revision count is 2 (producing scores of 1.0, 0.6, 0.2 for 0, 1, 2 rounds respectively). If the max ever increases, the formula should be reviewed. This coupling is documented in `score-dimensions.json`.

### Event Schema Extension

New event type `run_score` added to `configs/audit-event-schema.json`:

```json
{
  "title": "run_score",
  "description": "Emitted once near the end of a run, immediately before run_end. Contains per-dimension quantitative scores computed from the run's audit log.",
  "allOf": [
    { "$ref": "#/definitions/common_fields" },
    {
      "type": "object",
      "properties": {
        "event_type": { "const": "run_score" },
        "dimensions": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": { "type": "string" },
              "score": { "type": "number", "minimum": 0, "maximum": 1 },
              "weight": { "type": "number", "minimum": 0, "maximum": 1 },
              "details": { "type": "string" }
            },
            "required": ["name", "score", "weight", "details"]
          }
        },
        "composite": {
          "type": "number",
          "minimum": 0,
          "maximum": 1,
          "description": "Weighted composite score across all scored dimensions."
        },
        "velocity_minutes": {
          "type": "number",
          "description": "Wall-clock run duration in minutes (informational, not scored)."
        }
      },
      "required": ["event_type", "dimensions", "composite"]
    }
  ]
}
```

**Schema implementation note:** The `run_score` type must be added in two places within `configs/audit-event-schema.json`: (1) add `"run_score"` to the `event_type` enum in `definitions.common_fields.properties.event_type.enum`, and (2) add the full `run_score` definition as a new element in the top-level `oneOf` array.

### Score Computation Architecture

Score computation must happen outside skill markdown (skills cannot import Python). Two options:

| Option | Mechanism | Pros | Cons |
|--------|-----------|------|------|
| A. Standalone script | `scripts/compute-run-score.sh` reads the JSONL log for the current run, computes scores, outputs JSON | Reusable across skills. Testable. Follows emit-audit-event.sh pattern. | Extra script invocation. |
| B. Inline in coordinator | Coordinator reads audit log with Bash/jq and computes scores inline | No new script. | Logic duplicated per skill. Not testable in isolation. |

**Choice: Option A.** A standalone `scripts/compute-run-score.sh` script reads the JSONL log for a completed run, extracts the data needed for each dimension, computes scores, and outputs a partial event JSON suitable for passing to `emit-audit-event.sh`. This follows the established pattern where scoring logic lives in scripts, not in skill prose.

**Language choice:** `compute-run-score.sh` is a bash wrapper around a `python3` heredoc block. The scoring logic involves conditional branching, floating-point arithmetic, JSON parsing, and array iteration -- all of which are natural in python3 and would be unmaintainably complex in jq. `jq` is NOT a dependency for this script (though it remains a dependency of `audit-log-query.sh`). This follows the pattern established by `audit-log-query.sh`'s `cmd_timeline()` function, which uses a python3 heredoc for structured computation.

### History and Trending

No new storage mechanism is needed. Score events are JSONL lines in existing audit logs. The query script (`audit-log-query.sh`) gains new commands:

- `scores <run_id>` -- Show per-dimension scores for a single run
- `trend [N]` -- Show composite score trend for the last N runs (default 10)
- `trend --dimension <name> [N]` -- Show trend for a single dimension

**L1 ephemeral log limitation:** At L1 (advisory), JSONL audit logs are gitignored and ephemeral. They persist on disk across sessions but are not committed and may be cleaned up by the user or OS. This means the `trend` command and `score-reflector.sh` at L1 maturity can only analyze runs that still have log files on disk. For meaningful cross-session trend analysis, L2 or L3 maturity is required (logs are committed to git and persist permanently). The `trend` command and `score-reflector.sh` will display a notice when operating against gitignored logs: "Note: L1 (advisory) logs are not committed to git. Trend data is limited to logs still on disk."

### Feedback Loop: Score Reflector

A new `scripts/score-reflector.sh` script implements deterministic reflection (no LLM):

1. Reads score events from all audit logs in `plans/audit-logs/`
2. Computes per-dimension statistics: mean, min, max, and (with sufficient data) trend
3. Generates candidate learnings entries in `.claude/learnings.md` format
4. Outputs candidates to stdout for human review (does not write to learnings.md directly in v1)

The reflector follows the same pattern as remote-factory's reflector: purely statistical, counter-based evidence tracking. But instead of generating playbook bullets for agent roles, it generates learnings entries for devkit's `.claude/learnings.md` sections.

**Sample size thresholds for analysis:**

| Runs Available | Analysis Level |
|----------------|---------------|
| < 5 | "Insufficient data. Need at least 5 scored runs." (exit 0, no output) |
| 5-9 | Summary statistics only: per-dimension mean, min, max, and overall composite mean. No trend claims. |
| 10+ | Full analysis: summary statistics plus linear regression trend detection per dimension. Trend claims require slope magnitude > 0.05 per run AND at least 10 data points. |

This tiered approach prevents statistically dubious trend claims from small samples. At 5-9 runs, even simple summary statistics ("your average security score is 0.4 across 7 runs") are actionable without claiming a trend direction.

**Example reflector output (10+ runs):**
```
## Candidate Learnings from Score Analysis (12 runs analyzed)

### Coder Patterns > Missed by coders, caught by reviewers
- **[2026-05-09] Revision loop rate is high (58%)** [Medium] -- 7/12 runs required
  at least one revision round. Efficiency score trending downward (0.73 -> 0.53
  over 12 runs, slope -0.017/run). Common: code review REVISION_NEEDED on first
  pass. Consider: are plan acceptance criteria clear enough for coders to
  self-verify before review?
  #coder #efficiency #revision-loop (2026-05-09)

### Security Patterns
- **[2026-05-09] Security override usage increasing** [High] -- 4/12 runs used
  --security-override. Security dimension score declining (0.90 -> 0.67,
  slope -0.019/run). Most common override gate: secure_review. Review whether
  secure-review findings are actionable or represent false positives that should
  be tuned.
  #security #override #trend (2026-05-09)
```

**Example reflector output (5-9 runs):**
```
## Score Summary (7 runs analyzed)

Note: Trend analysis requires 10+ runs. Showing summary statistics only.

| Dimension  | Mean  | Min   | Max   |
|------------|-------|-------|-------|
| efficiency | 0.600 | 0.200 | 1.000 |
| security   | 0.857 | 0.400 | 1.000 |
| quality    | 0.743 | 0.500 | 1.000 |
| composite  | 0.733 | 0.367 | 1.000 |

Lowest dimension: efficiency (mean 0.600). 5/7 runs entered the revision loop.
```

### Integration with Existing Systems

```
+-----------------------------------------------------------------+
| /ship run                                                        |
|                                                                  |
|  Step 0-6: Normal execution, emitting audit events               |
|       |                                                          |
|       v                                                          |
|  Step 6 (PASS path finalization, before run_end):                |
|       |  Run compute-run-score.sh                                |
|       |    Reads: plans/audit-logs/ship-<run_id>.jsonl            |
|       |    Outputs: partial event JSON                            |
|       |  emit-audit-event.sh -> appends run_score event           |
|       |                                                          |
|       v                                                          |
|  emit-audit-event.sh -> appends run_end event                    |
|       |                                                          |
|       v                                                          |
|  git add --force (L2/L3 -- run_score is in the staged log)       |
|       |                                                          |
|       v                                                          |
|  Squash, commit, archive                                         |
|       |                                                          |
|       v                                                          |
|  Step 7: Retro capture (unchanged)                               |
|       |    Reads: archived review artifacts                       |
|       v                                                          |
|  .claude/learnings.md (qualitative, from artifacts)              |
+-----------------------------------------------------------------+

+-----------------------------------------------------------------+
| Periodic: score-reflector.sh (manual invocation)                 |
|                                                                  |
|  Reads: ALL plans/audit-logs/*.jsonl run_score events            |
|       |                                                          |
|       v                                                          |
|  Computes: per-dimension statistics, trends (10+ runs)           |
|       |                                                          |
|       v                                                          |
|  Outputs: candidate learnings to stdout                          |
|           (human copies relevant ones to .claude/learnings.md)   |
+-----------------------------------------------------------------+

+-----------------------------------------------------------------+
| audit-log-query.sh scores <run_id>                               |
| audit-log-query.sh trend [N]                                     |
|                                                                  |
|  Reads: plans/audit-logs/*.jsonl run_score events                |
|  Outputs: formatted score tables / trend visualization           |
+-----------------------------------------------------------------+
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Scores augment, not replace, verdicts | Verdict gates are control-flow (PASS = proceed, BLOCKED = stop). Scores are analytics (how well did we do?). Mixing them creates ambiguous semantics. |
| run_score emitted immediately BEFORE run_end | Ensures run_score is included in L2/L3 committed logs (git add --force happens after run_end). Maintains a clean event ordering where run_end remains the final event in the run. Avoids HMAC chain complications at L3. |
| Efficiency derived from code_review verdict count, not run_end field | The `run_end.revision_rounds` field is defined in the schema but not emitted by `/ship`. Step 5 wraps the entire revision loop in a single `step_start`/`step_end` pair (individual rounds don't get separate step events). The scoring script counts `verdict` events with `verdict_source == "code_review"` instead — Step 4 emits one per pass, and Step 5 re-runs Step 4 per revision round, giving verdict_count = revision_rounds + 1. |
| Velocity excluded from composite | Wall-clock time is too noisy (model latency, human pauses, CI vs local). Including it would make composite scores incomparable across environments. |
| 0.5 for missing dimensions | Follows remote-factory's neutral-score principle. A project without security skills deployed should not get a perfect 1.0 security score (misleading) or 0.0 (punitive). 0.5 = "we do not know." |
| Script-based, not inline | Skills are markdown. Scoring logic in bash/python scripts is testable, reusable, and does not bloat skill prose. |
| python3 only for compute-run-score.sh | The scoring logic requires conditional branching, float arithmetic, JSON parsing, and array iteration. jq would produce write-only code. python3 is already a dependency of emit-audit-event.sh. |
| Reflector outputs to stdout, not learnings.md | v1 is human-in-the-loop. Automated learnings injection risks low-quality entries polluting the file. Human curation matches devkit's existing `/retro` pattern. |
| JSONL, not TSV | Remote-factory uses TSV for its experiment store. Devkit already has JSONL infrastructure. Adding TSV would create a parallel persistence mechanism. JSONL run_score events in existing audit logs is the natural fit. |
| Trend analysis requires 10+ runs | Linear regression on 5-9 data points is statistically dubious -- a single outlier dominates the slope. Below 10 runs, the reflector reports summary statistics (mean, min, max) without trend claims. |
| score-dimensions.json is a plain data file | Follows `configs/skill-patterns.json` convention (plain JSON data, no `$schema`). Not a JSON Schema -- it is consumed by `compute-run-score.sh` as configuration, not used to validate other files. |

## Proposed Design

### New Files

| File | Purpose |
|------|---------|
| `scripts/compute-run-score.sh` | Reads a run's JSONL audit log, computes per-dimension scores, outputs partial event JSON |
| `scripts/score-reflector.sh` | Reads all run_score events across audit logs, computes statistics and trends, outputs candidate learnings |
| `configs/score-dimensions.json` | Dimension definitions with weights (documentation and future machine-readable config; v1 dimensions are hardcoded in compute-run-score.sh for simplicity) |

### Modified Files

| File | Changes |
|------|---------|
| `configs/audit-event-schema.json` | Add `run_score` to `event_type` enum + new `oneOf` entry. Add `run_score_ordering` note. |
| `scripts/audit-log-query.sh` | Add `scores` and `trend` commands |
| `scripts/test-integration.sh` | Add tests for compute-run-score.sh, score query commands, and negative/edge cases. Update test 16 version assertion (3.7.0 -> 3.8.0). |
| `skills/ship/SKILL.md` | Add score computation + emission in Step 6 PASS-path finalization (before `run_end` emission). Version bump 3.7.0 -> 3.8.0. |
| `CLAUDE.md` | Add Scoring System section. Update /ship description. Update Event Types table. Update test-integration.sh test count. |

### Interface: compute-run-score.sh

```bash
#!/usr/bin/env bash
# scripts/compute-run-score.sh
#
# Compute quantitative scores for a completed skill run.
#
# Usage:
#   bash scripts/compute-run-score.sh <audit-log-file>
#   bash scripts/compute-run-score.sh --help
#
# Input:
#   Path to a JSONL audit log file (must contain run_start event;
#   run_end is optional -- scoring works on partial logs)
#
# Output:
#   Partial event JSON suitable for passing to emit-audit-event.sh:
#   {"event_type":"run_score","dimensions":[...],"composite":0.78,"velocity_minutes":12.3}
#
# Exit codes:
#   0 = success (JSON written to stdout)
#   0 = any error (writes warning to stderr, outputs neutral-score JSON to stdout)
#       Never exits non-zero -- follows emit-audit-event.sh convention.
#
# Dependencies: python3
# NOT a dependency: jq (all computation is python3)
```

**Score computation logic (python3 heredoc inside bash wrapper):**

```python
# Pseudocode for the python3 block inside compute-run-score.sh

import json, sys
from datetime import datetime

# 1. Parse all events from the JSONL file
events = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        events.append(json.loads(line))
    except json.JSONDecodeError:
        # Skip malformed lines (partial writes, interrupted runs)
        print(f"Warning: skipping malformed JSONL line", file=sys.stderr)
        continue

dimensions = []

# 2. Efficiency: count code_review verdict events to derive revision rounds
# Step 4 emits one code_review verdict per pass. Step 5 re-runs Step 4 per
# revision round. So: 1 verdict = 0 rounds, 2 = 1 round, 3 = 2 rounds.
code_review_verdicts = [
    e for e in events
    if e.get('event_type') == 'verdict'
    and e.get('verdict_source') == 'code_review'
]
verdict_count = len(code_review_verdicts)

if verdict_count == 0:
    # No code review ran -> no revision data -> neutral
    efficiency_score = 0.5
    efficiency_details = "No code review events found (neutral)"
else:
    revision_count = verdict_count - 1  # first verdict is Step 4, not a revision
    efficiency_score = max(0.0, 1.0 - revision_count * 0.4)
    efficiency_details = f"{revision_count} revision round(s) ({verdict_count} code_review verdict(s))"

dimensions.append({
    "name": "efficiency",
    "score": round(efficiency_score, 4),
    "weight": 0.3333,
    "details": efficiency_details
})

# 3. Security
security_events = [e for e in events if e['event_type'] == 'security_decision']
if not security_events:
    security_score = 0.5  # Neutral: no security gates ran
    security_details = "No security gates ran (neutral)"
else:
    security_score = 1.0
    for se in security_events:
        if se.get('gate_verdict') == 'BLOCKED':
            security_score -= 0.3
        elif se.get('gate_verdict') == 'PASS_WITH_NOTES':
            security_score -= 0.1
    security_score = max(0.0, security_score)
    gate_summary = [f"{se['gate']}:{se['gate_verdict']}" for se in security_events]
    security_details = "; ".join(gate_summary)
dimensions.append({
    "name": "security",
    "score": round(security_score, 4),
    "weight": 0.3333,
    "details": security_details
})

# 4. Quality
verdict_events = [e for e in events if e['event_type'] == 'verdict']
code_review_verdicts = [e for e in verdict_events if e.get('verdict_source') == 'code_review']
qa_verdicts = [e for e in verdict_events if e.get('verdict_source') == 'qa']

quality_score = 1.0
quality_parts = []

if code_review_verdicts:
    # Use the first code review verdict (pre-revision quality signal).
    # Rationale: the first verdict reflects the coder's unrevised output.
    # Post-revision verdicts are captured by the efficiency dimension.
    first_cr = code_review_verdicts[0]
    if first_cr['verdict'] == 'REVISION_NEEDED':
        quality_score -= 0.3
        quality_parts.append("code_review:REVISION_NEEDED")
    elif first_cr['verdict'] == 'FAIL':
        quality_score -= 0.5
        quality_parts.append("code_review:FAIL")
    else:
        quality_parts.append("code_review:PASS")

if qa_verdicts:
    last_qa = qa_verdicts[-1]  # Final QA verdict (post-fix result)
    if last_qa['verdict'] == 'PASS_WITH_NOTES':
        quality_score -= 0.1
        quality_parts.append("qa:PASS_WITH_NOTES")
    elif last_qa['verdict'] == 'FAIL':
        quality_score -= 0.5
        quality_parts.append("qa:FAIL")
    else:
        quality_parts.append("qa:PASS")

if not quality_parts:
    quality_score = 0.5  # Neutral
    quality_details = "No verdict events found (neutral)"
else:
    quality_score = max(0.0, quality_score)
    quality_details = "; ".join(quality_parts)

dimensions.append({
    "name": "quality",
    "score": round(quality_score, 4),
    "weight": 0.3333,
    "details": quality_details
})

# 5. Velocity (informational, not in composite)
run_starts = [e for e in events if e['event_type'] == 'run_start']
run_ends = [e for e in events if e['event_type'] == 'run_end']
velocity_minutes = None
if run_starts:
    start_ts = run_starts[0].get('timestamp')
    # For velocity, use the current time if run_end hasn't been emitted yet
    # (run_score is computed before run_end)
    if run_ends:
        end_ts = run_ends[0].get('timestamp')
    else:
        end_ts = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.000Z')
    if start_ts and end_ts:
        try:
            t0 = datetime.fromisoformat(start_ts.replace('Z', '+00:00'))
            t1 = datetime.fromisoformat(end_ts.replace('Z', '+00:00'))
            velocity_minutes = round((t1 - t0).total_seconds() / 60, 1)
        except Exception:
            pass

# 6. Composite (only scored dimensions with weight > 0)
scored = [d for d in dimensions if d['weight'] > 0]
total_weight = sum(d['weight'] for d in scored)
if total_weight > 0:
    composite = sum(d['score'] * d['weight'] / total_weight for d in scored)
else:
    composite = 0.5
composite = round(composite, 4)

# 7. Output
result = {
    "event_type": "run_score",
    "dimensions": dimensions,
    "composite": composite
}
if velocity_minutes is not None:
    result["velocity_minutes"] = velocity_minutes

print(json.dumps(result))
```

### Interface: score-reflector.sh

```bash
#!/usr/bin/env bash
# scripts/score-reflector.sh
#
# Deterministic score reflector -- analyzes score history and generates
# candidate learnings entries.
#
# Usage:
#   bash scripts/score-reflector.sh [--min-runs N] [--format md|json]
#   bash scripts/score-reflector.sh --help
#
# Reads all run_score events from plans/audit-logs/*.jsonl
# Computes per-dimension statistics and trends
# Outputs candidate learnings entries to stdout
#
# Options:
#   --min-runs N    Minimum runs required for any analysis (default: 5)
#   --format md     Output as markdown learnings entries (default)
#   --format json   Output as structured JSON
#
# Analysis levels:
#   5-9 runs:  Summary statistics only (mean, min, max per dimension)
#   10+ runs:  Summary statistics + trend analysis (linear regression)
#
# Dependencies: python3
# NOT a dependency: jq
#
# Note: At L1 (advisory) maturity, audit logs are gitignored and
# ephemeral. Trend data is limited to logs still on disk. For
# meaningful cross-session analysis, use L2 or L3 maturity.
```

**Reflector logic (deterministic, no LLM):**

1. Collect all `run_score` events across all JSONL files in `plans/audit-logs/`
2. Sort by timestamp
3. For each dimension, compute:
   - Mean score across all runs
   - Min and max score
   - If 10+ runs: linear regression slope over last N runs (positive = improving, negative = degrading)
   - Worst run and best run
4. Generate candidate learnings entries based on analysis level:
   - **5-9 runs (summary only):**
     - Report per-dimension mean, min, max
     - Identify the lowest-mean dimension
     - Report revision loop frequency (from efficiency details)
     - Count security overrides from security_decision events
   - **10+ runs (summary + trends):**
     - All summary statistics from above
     - **Degrading dimensions** (negative slope, magnitude > 0.05 per run): "Dimension X is trending downward"
     - **Consistently low dimensions** (mean < 0.5 over 10+ runs): "Dimension X is chronically low"
     - **High revision rate** (efficiency mean < 0.7): "Revision loops are frequent"
     - **Security override frequency** (count overrides across security_decision events): "Overrides used in N% of runs"
     - **Composite drop** (composite mean of last 5 runs < composite mean of previous 5 runs by > 0.1): "Overall quality declining"
5. Output formatted candidates

### Interface: score-dimensions.json

```json
{
  "title": "Claude Devkit Score Dimensions",
  "version": "1.0.0",
  "description": "Configurable scoring dimensions for skill run evaluation. v1: dimensions are hardcoded in compute-run-score.sh; this file serves as documentation and future machine-readable configuration.",
  "notes": {
    "weight_convention": "Active dimension weights should sum to ~1.0 (excluding velocity which has weight 0.0). compute-run-score.sh normalizes weights at runtime, so non-unit sums produce correct composites but non-standard individual weighted contributions.",
    "efficiency_coupling": "The efficiency formula (1.0 - revision_count * 0.4) assumes /ship max revision count is 2. If /ship increases this limit, review the formula.",
    "schema_gap": "run_end.revision_rounds and run_end.steps_completed are defined in audit-event-schema.json but NOT emitted by any skill coordinator. Efficiency is derived from code_review verdict count instead (verdict_count - 1 = revision rounds)."
  },
  "dimensions": [
    {
      "name": "efficiency",
      "weight": 0.3333,
      "description": "How clean was the implementation? Fewer revision rounds = better.",
      "source": "verdict events where verdict_source == 'code_review' (count - 1 = revision rounds)",
      "scoring": "Count step_start occurrences. 0 = 1.0, 1 = 0.6, 2 = 0.2. Formula: max(0.0, 1.0 - count * 0.4)",
      "neutral": 0.5
    },
    {
      "name": "security",
      "weight": 0.3333,
      "description": "Security gate outcomes. Penalizes BLOCKED and PASS_WITH_NOTES verdicts.",
      "source": "security_decision events",
      "scoring": "Start 1.0. BLOCKED: -0.3, PASS_WITH_NOTES: -0.1, floor 0.0",
      "neutral": 0.5
    },
    {
      "name": "quality",
      "weight": 0.3333,
      "description": "Code review and QA outcomes. Uses first code review verdict (pre-revision) and final QA verdict.",
      "source": "verdict events (code_review first, qa last)",
      "scoring": "Start 1.0. CR REVISION_NEEDED: -0.3, CR FAIL: -0.5, QA PASS_WITH_NOTES: -0.1, QA FAIL: -0.5, floor 0.0",
      "neutral": 0.5
    },
    {
      "name": "velocity",
      "weight": 0.0,
      "description": "Wall-clock run duration in minutes. Informational only (not in composite).",
      "source": "run_start.timestamp to current time (run_score is emitted before run_end)",
      "scoring": "Duration in minutes. Not normalized.",
      "neutral": null
    }
  ]
}
```

### Ship SKILL.md Integration

New score computation block inserted into the Step 6 PASS-path finalization, **after the `step_end` for Step 6 and before the `run_end` emission**. The exact insertion point is between the current line that emits `step_end` for `step_6_commit_gate` (line 1237-1238) and the line that emits `run_end` (line 1240-1243).

```markdown
**Score computation (pre-run_end, non-blocking):**

Tool: `Bash`

After step_end for Step 6 is emitted and before run_end, compute and emit the run score:

\```bash
# Compute run score from audit log (non-blocking)
SCORE_JSON=$(bash scripts/compute-run-score.sh "$AUDIT_LOG" 2>/dev/null)
if [ -n "$SCORE_JSON" ]; then
  bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" "$SCORE_JSON"
  echo "Run score computed and logged."
else
  echo "Warning: Score computation returned empty output. Continuing without score."
fi
\```
```

This placement ensures:
1. All verdict, security_decision, and step events are already in the log (computed from complete data)
2. `run_score` precedes `run_end` in the log, so `run_end` remains the final run-lifecycle event
3. At L2/L3, `git add --force "$AUDIT_LOG"` (which follows `run_end`) stages the log with both `run_score` and `run_end` included
4. At L3, the HMAC chain naturally includes `run_score` before `run_end` -- no chain shape ambiguity
5. The state file still exists (not deleted until end of Step 7)
6. Score computation failure does not block the workflow (non-blocking, follows existing pattern)
7. Velocity is computed using current time (since `run_end` has not been emitted yet), which is close enough -- the delta between score computation and `run_end` emission is negligible

## Implementation Plan

### Phase 1: Schema and Score Computation (core infrastructure)

1. [ ] Create `configs/score-dimensions.json` with the four dimension definitions
   - File: `configs/score-dimensions.json`
   - Content: plain JSON data file (no `$schema` field), following `configs/skill-patterns.json` convention
   - Include `notes` object documenting efficiency coupling and schema gap
   - Validation: valid JSON, active weights sum to ~1.0 (excluding velocity)

2. [ ] Update `configs/audit-event-schema.json` to add `run_score` event type
   - File: `configs/audit-event-schema.json`
   - Change 1: Add `"run_score"` to the `event_type` enum in `definitions.common_fields.properties.event_type.enum`
   - Change 2: Add new `run_score` `oneOf` entry with `dimensions` array, `composite` number, and `velocity_minutes` number
   - Change 3: Add `run_score_ordering` note to the `notes` object: "run_score is emitted immediately before run_end. It is the penultimate run-lifecycle event."
   - Validation: valid JSON Schema (`python3 -c "import json; json.load(open('configs/audit-event-schema.json'))"`)

3. [ ] Create `scripts/compute-run-score.sh`
   - File: `scripts/compute-run-score.sh`
   - Must: be executable (`chmod +x`), have `--help` flag, exit 0 on all paths, use `python3` for all computation (no jq dependency), read from JSONL file, output partial event JSON to stdout
   - Must derive efficiency from `verdict` events with `verdict_source == "code_review"` (count - 1 = revision rounds; NOT from `run_end.revision_rounds` or `step_start` events)
   - Must handle: missing run_start (output neutral scores), missing verdict events (neutral quality), missing security_decision events (neutral security), empty log file (all neutral), nonexistent file path (neutral scores with warning to stderr), malformed JSONL lines (skip with warning to stderr)
   - Must compute velocity using current time (run_score is emitted before run_end)
   - Must normalize weights (effective_weight = weight / sum_of_weights) to handle non-unit weight sums
   - Must follow: emit-audit-event.sh conventions (never exit non-zero, warnings to stderr)
   - Validation: `bash scripts/compute-run-score.sh --help` exits 0

4. [ ] Validate compute-run-score.sh against synthetic test data
   - Create a test JSONL file with known events (step events for revision loop, security_decision events, verdict events)
   - Run compute-run-score.sh against it
   - Verify output JSON matches expected scores
   - Verify efficiency uses step event count, not run_end field
   - Validation: `python3 -c "import json; json.loads(output)"` succeeds, scores match expected values

### Phase 2: Query Infrastructure

5. [ ] Add `scores` command to `scripts/audit-log-query.sh`
   - File: `scripts/audit-log-query.sh`
   - New function `cmd_scores()`: extracts `run_score` event from a run's JSONL, formats as a table showing each dimension name, score, weight, details, and the composite score
   - Include contextual note in output: "Composite scores are most useful for trend analysis across runs."
   - Add to dispatch case statement
   - Update help text
   - Validation: `./scripts/audit-log-query.sh --help` shows `scores` command

6. [ ] Add `trend` command to `scripts/audit-log-query.sh`
   - File: `scripts/audit-log-query.sh`
   - New function `cmd_trend()`: reads all JSONL files in `plans/audit-logs/`, extracts `run_score` events, sorts by timestamp, shows last N runs with composite score and per-dimension scores as a table
   - Support `--dimension <name>` flag to show single-dimension trend
   - Filter to target skill prefix (e.g., only `ship-*.jsonl` files) -- handle gracefully when non-ship logs lack `run_score`
   - Display L1 ephemeral log notice when gitignored logs are detected
   - Uses python3 for computation (same pattern as `cmd_timeline()`)
   - Handle 0 runs with score data gracefully ("No score data found.")
   - Validation: `./scripts/audit-log-query.sh --help` shows `trend` command

### Phase 3: Ship Integration

7. [ ] Instrument `/ship` SKILL.md to emit `run_score` event
   - File: `skills/ship/SKILL.md`
   - Insert score computation block in Step 6 PASS-path finalization, after the `step_end` emission for Step 6 (line 1237-1238) and BEFORE the `run_end` emission (line 1240-1243)
   - The block calls `compute-run-score.sh` with the audit log path, then passes the output to `emit-audit-event.sh`
   - Non-blocking: failure does not stop workflow
   - Bump version from 3.7.0 to 3.8.0
   - Validation: `validate-skill skills/ship/SKILL.md` passes

8. [ ] Update test 16 in `scripts/test-integration.sh` to assert version 3.8.0
   - File: `scripts/test-integration.sh`
   - Change test 16 assertion from `'version: 3.7.0'` to `'version: 3.8.0'`
   - Validation: `grep -q '3.8.0' scripts/test-integration.sh`

### Phase 4: Score Reflector

9. [ ] Create `scripts/score-reflector.sh`
   - File: `scripts/score-reflector.sh`
   - Must: be executable, have `--help` flag, support `--min-runs N` (default 5) and `--format md|json` flags
   - Must: read all `run_score` events from `plans/audit-logs/*.jsonl`
   - Must: use python3 for all computation (no jq dependency)
   - Must: implement tiered analysis: 5-9 runs = summary stats only, 10+ runs = summary + trend
   - Must: output to stdout (never writes to `.claude/learnings.md` directly)
   - Must: exit 0 if insufficient data (fewer than --min-runs runs with scores)
   - Must: display L1 ephemeral log notice
   - Validation: `bash scripts/score-reflector.sh --help` exits 0

10. [ ] Validate score-reflector.sh against synthetic test data
    - Create multiple synthetic JSONL files with run_score events
    - Test with 7 runs (summary stats mode): verify no trend claims, only mean/min/max
    - Test with 12 runs showing a degrading trend: verify trend detection and appropriate candidate learnings
    - Test with runs that have identical scores (zero variance): verify no spurious trend claims
    - Validation: output matches expected analysis level and content

### Phase 5: Tests and Documentation

11. [ ] Add integration tests to `scripts/test-integration.sh`
    - File: `scripts/test-integration.sh`
    - Positive tests (4 minimum):
      - Test: compute-run-score.sh produces valid JSON for a synthetic log with all event types (code_review verdict events, security_decision, qa verdict events)
      - Test: compute-run-score.sh handles empty log gracefully (neutral scores, all 0.5)
      - Test: audit-log-query.sh `scores` command parses run_score events
      - Test: audit-log-query.sh `trend` command aggregates across multiple logs
    - Negative/edge-case tests (4 minimum):
      - Test: compute-run-score.sh with nonexistent file path (exits 0, neutral scores, warning to stderr)
      - Test: compute-run-score.sh with incomplete log (has run_start but no run_end -- should still compute scores from available events)
      - Test: compute-run-score.sh with malformed JSONL lines (skips bad lines, computes from valid ones)
      - Test: audit-log-query.sh `trend` with 0 scored runs (displays "No score data found")
    - Validation: `bash scripts/test-integration.sh` passes with all new tests green

12. [ ] Update CLAUDE.md
    - File: `CLAUDE.md`
    - Add to Event Types table: `run_score` | When a skill run completes and scores are computed (emitted before `run_end`)
    - Add new section: `## Quantitative Scoring` under the Audit Logging section, documenting dimensions, query commands, the reflector, L1 ephemeral limitation, and sample size thresholds
    - Update `/ship` registry description to mention scoring
    - Update Script Registry to include compute-run-score.sh and score-reflector.sh
    - Update `test-integration.sh` test count from "18 tests" to the post-expansion count (26+ tests) in the directory structure comment and the Scripts section
    - Validation: no broken internal references

13. [ ] Run full validation suite
    - Command: `bash scripts/validate-all.sh && bash scripts/test-integration.sh && bash generators/test_skill_generator.sh`
    - All tests must pass
    - Validation: exit code 0 for all three commands

### Phase Dependencies

```
Phase 1 (schema + compute)
    |
    +---> Phase 2 (query commands) -- depends on schema
    |
    +---> Phase 3 (ship integration) -- depends on compute script
              |
              +---> Phase 4 (reflector) -- depends on score events existing
                        |
                        +---> Phase 5 (tests + docs) -- depends on all above
```

Phases 2 and 3 can run in parallel after Phase 1 completes. Note: Phase 2 query commands can be written and unit-tested with synthetic data before Phase 3 provides real data. However, they will display "No score data" in production until Phase 3 lands.

## Data Migration

**None required.** Existing audit logs are unaffected. The `run_score` event type is additive -- old logs simply will not contain run_score events, and all query commands handle this gracefully (showing "No score data" or similar).

## Rollout Plan

1. **Merge Phase 1** -- Schema and compute script. No behavioral changes to any skill.
2. **Merge Phase 2** -- Query commands. No behavioral changes. Users can run `trend` but will see "No score data."
3. **Merge Phase 3** -- Ship integration. `/ship` runs now emit run_score events. Existing behavior unchanged (scoring is non-blocking).
4. **Merge Phase 4** -- Reflector script. Manual invocation only.
5. **Merge Phase 5** -- Tests and docs. Full validation.

Each phase is independently useful and can be shipped as a separate commit. No phase requires rollback of a previous phase.

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| compute-run-score.sh fails on edge cases (empty log, partial log, unexpected event shapes, malformed JSONL) | Medium | Low | Script exits 0 on all paths with neutral-score fallback. 8 integration tests including 4 negative/edge cases. |
| Score computation adds latency to /ship runs | Low | Low | python3 processing a 50-line JSONL file takes <100ms. Non-blocking -- failure skipped. |
| Dimension weights feel wrong after real usage | Medium | Medium | Weights are in `score-dimensions.json` and documented. Can be tuned without changing any script (v2 reads config at runtime). v1 normalizes weights, so non-unit sums still produce correct composites. |
| Score inflation from neutral (0.5) dimensions | Medium | Low | Documented as "we do not know" semantics. Users understand 0.5 = no data. Trend analysis is more valuable than absolute score. |
| Reflector generates noisy/unhelpful learnings candidates | Medium | Medium | v1 is human-curated (stdout only). The reflector does not write to learnings.md. Trend claims require 10+ runs. Summary stats at 5-9 runs avoid false trend signals. |
| JSONL log files grow larger with run_score events | Low | Low | One additional line per run (~500 bytes). Even 1000 runs adds <500KB. |
| Breaking existing audit-log-query.sh commands | Low | High | All changes are additive (new commands). Existing commands untouched. Integration tests verify existing commands still work. |
| L1 users get "insufficient data" from reflector/trend | High | Low | Documented explicitly. L1 scores are on-disk only. Users who want trend analysis can upgrade to L2. |
| Efficiency dimension does not fire for runs that skip Step 5 entirely but have no code review | Low | Low | Handled: if no code review verdict events exist, efficiency returns 0.5 (neutral). Only runs with code review verdicts that did NOT trigger Step 5 get 1.0. |

## Test Plan

### Exact test command

```bash
bash scripts/test-integration.sh
```

This single command runs all integration tests, including the new scoring tests added in Phase 5 Step 11.

### Test matrix

| Test | What it verifies | Phase |
|------|-----------------|-------|
| compute-run-score.sh with complete log (incl. step_5 events) | All three dimensions scored correctly using step events for efficiency, composite computed, velocity reported | Phase 1 |
| compute-run-score.sh with empty log | Returns all-neutral scores (0.5), composite 0.5 | Phase 1 |
| compute-run-score.sh with 2 revision rounds (2 step_5 step_starts) | Efficiency score = 0.2 | Phase 1 |
| compute-run-score.sh with BLOCKED security gate | Security score penalized by 0.3 | Phase 1 |
| compute-run-score.sh with nonexistent file | Exits 0, returns neutral scores, warning to stderr | Phase 1 |
| compute-run-score.sh with incomplete log (no run_end) | Computes scores from available events (efficiency, security, quality from what is present) | Phase 1 |
| compute-run-score.sh with malformed JSONL lines | Skips bad lines, computes from valid ones | Phase 1 |
| audit-log-query.sh scores command | Parses and displays run_score event | Phase 2 |
| audit-log-query.sh trend command | Aggregates run_score events across multiple log files | Phase 2 |
| audit-log-query.sh trend with 0 scored runs | Displays "No score data found" | Phase 2 |
| End-to-end: emit events + compute score + query | Full pipeline from event emission through scoring to query | Phase 3 |
| score-reflector.sh with zero-variance scores | No spurious trend claims | Phase 4 |

### Manual validation (not automated)

- Run `/ship` on a real plan and verify run_score event appears in the JSONL log BEFORE run_end
- Run `./scripts/audit-log-query.sh scores <run_id>` and verify readable output
- Run `./scripts/audit-log-query.sh trend 5` after multiple /ship runs and verify trend display
- Run `./scripts/score-reflector.sh` after 5+ scored runs and verify summary statistics (not trend claims)
- Run `./scripts/score-reflector.sh` after 10+ scored runs and review candidate learnings quality

## Acceptance Criteria

1. `scripts/compute-run-score.sh` exists, is executable, and produces valid JSON for any JSONL input (including empty, incomplete, and malformed files)
2. `scripts/compute-run-score.sh` derives efficiency from `verdict` events with `verdict_source == "code_review"` (NOT from `run_end.revision_rounds` or `step_start` events)
3. `configs/audit-event-schema.json` includes `run_score` in both the `event_type` enum and the `oneOf` array
4. `configs/score-dimensions.json` exists as a plain JSON data file (no `$schema`) defining four dimensions with documented weights
5. `/ship` SKILL.md emits a `run_score` event before `run_end` on successful runs (version bumped to 3.8.0)
6. `audit-log-query.sh scores <run_id>` shows per-dimension scores for a run with score data
7. `audit-log-query.sh trend [N]` shows composite score trend across recent runs
8. `scripts/score-reflector.sh` exists, is executable, and uses tiered analysis (summary at 5-9 runs, trends at 10+)
9. All existing integration tests continue to pass (including test 16 updated to assert 3.8.0)
10. At least 8 new integration tests cover score computation and querying (4 positive + 4 negative/edge cases)
11. CLAUDE.md updated with scoring system documentation and updated test count

## Task Breakdown

### Files to Create (3)

| File | Lines (est.) | Purpose |
|------|-------------|---------|
| `configs/score-dimensions.json` | ~45 | Dimension definitions with weights and documentation notes |
| `scripts/compute-run-score.sh` | ~200 | Score computation from JSONL audit log (python3 heredoc) |
| `scripts/score-reflector.sh` | ~280 | Deterministic reflector with tiered analysis for candidate learnings |

### Files to Modify (5)

| File | Scope of Change |
|------|----------------|
| `configs/audit-event-schema.json` | Add `run_score` to event_type enum + new oneOf entry + ordering note (~50 lines) |
| `scripts/audit-log-query.sh` | Add `cmd_scores()` and `cmd_trend()` functions + dispatch entries (~120 lines) |
| `scripts/test-integration.sh` | Add 8+ new tests (4 positive, 4 negative). Update test 16 version assertion (3.7.0 -> 3.8.0) (~120 lines) |
| `skills/ship/SKILL.md` | Add score computation block in Step 6 PASS-path (before run_end), version bump 3.7.0 -> 3.8.0 (~15 lines) |
| `CLAUDE.md` | Add Scoring System section, update tables, update test count (~50 lines) |

### Files NOT Modified

| File | Reason |
|------|--------|
| `scripts/emit-audit-event.sh` | No changes needed. `run_score` is just another event type passed as partial JSON. |
| `.claude/learnings.md` | Not modified by any automation. Score reflector outputs to stdout. Human copies relevant entries. |
| Other skills (architect, audit, retro, etc.) | v1 only instruments `/ship`. Other skills are Phase 2. |

## Future Work (Deferred)

### Phase 2: Broader Skill Coverage
- Instrument `/architect` with scoring dimensions: plan quality (red team verdict), revision rounds, context alignment
- Instrument `/audit` with scoring dimensions: finding severity distribution, coverage completeness
- Add `/retro` scoring: learning quality, deduplication effectiveness
- Note: `/architect` emits `"outcome":"PASS"` (uppercase, verdict terminology) vs `/ship`'s `"outcome":"success"` (lowercase). Score computation for `/architect` must normalize outcome values.

### Phase 3: Automated Feedback Loop
- Score reflector writes directly to `.claude/learnings.md` (with deduplication against existing entries)
- `/ship` Step 2 (pattern validation) reads score trends and adjusts coder prompts
- Configurable thresholds in `.claude/settings.json` for automated learnings injection

### Phase 4: Cross-Project Aggregation
- Aggregate scores across multiple projects using a shared store
- Identify patterns that are project-specific vs universal
- Generate global learnings applicable across all codebases

### Phase 5: Advanced Analytics
- Statistical significance testing for trend detection
- Anomaly detection (sudden score drops)
- Correlation analysis (which dimension changes predict composite changes)
- Integration with OTel collector for dashboarding (when Kagenti provides endpoint)
- Scoring failed/blocked runs (v1 only scores successful runs on the PASS path)
- Gate-specific security penalties (secrets_scan BLOCKED = -0.5, secure_review BLOCKED = -0.3, dependency_audit BLOCKED = -0.2)

## Context Alignment

### CLAUDE.md Patterns Followed

| Pattern | How This Plan Follows It |
|---------|--------------------------|
| **JSONL audit logging** | Extends existing event schema with `run_score` type. Same emission mechanism (emit-audit-event.sh). Same retention rules (L1 gitignored, L2/L3 committed). |
| **Scripts for infrastructure** | New logic in standalone scripts (`compute-run-score.sh`, `score-reflector.sh`), not in skill markdown. Follows emit-audit-event.sh and audit-log-query.sh patterns. |
| **Non-blocking post-commit steps** | Score computation is non-blocking (matches Step 7 retro capture pattern). Failure does not affect the committed code. |
| **Existing query infrastructure** | New commands added to `audit-log-query.sh` (not a new query tool). Same python3 dependency. |
| **Learnings as feedback mechanism** | Score reflector outputs candidate entries for `.claude/learnings.md` (not a new feedback mechanism). Consumed by existing coder/reviewer/QA prompts. |
| **Configurable via JSON** | Score dimensions and weights in `configs/score-dimensions.json`. Follows `configs/skill-patterns.json` pattern (plain data file, no `$schema`). |
| **v2.0.0 skill patterns** | Ship SKILL.md changes maintain all 11 architectural patterns. Version bump follows semver. |
| **Exit 0 convention** | compute-run-score.sh exits 0 on all paths (same as emit-audit-event.sh). Never blocks /ship. |

### Prior Plans This Builds Upon

| Plan | Relationship |
|------|-------------|
| `ship-run-audit-logging` (archived) | Established the JSONL audit infrastructure this plan extends. `run_score` is a new event type in the same log files. |
| `agentic-sdlc-security-skills` | Established security maturity levels and security gates. Security dimension scoring reads `security_decision` events that these gates emit. |
| `devkit-hygiene-improvements` | Established integration test infrastructure (`test-integration.sh`). New scoring tests follow the same test runner pattern. |
| `threat-model-consumption` | Established threat model context passing in `/ship`. Score reflector can detect trends in threat model coverage via secure-review artifacts. |

### Deviations from Established Patterns

| Deviation | Justification |
|-----------|---------------|
| Score computation in external script, not coordinator | Coordinators manage control flow. Score computation is analytics -- a different concern. External script is testable and reusable. This deviates from the pattern where coordinators orchestrate all work, but follows the pattern where infrastructure logic lives in scripts. |
| Version jump 3.7.0 -> 3.8.0 for a non-breaking addition | Minor version bump for a feature addition (new event emission). Follows semver. Some prior changes used larger bumps, but a non-breaking additive change warrants minor. |
| score-dimensions.json as documentation-first, code-second | v1 hardcodes dimensions in compute-run-score.sh for simplicity. The JSON file documents the intended configuration format for v2 runtime consumption. This is pragmatic: config-file discovery and parsing adds complexity without v1 benefit. |

## Verification

After all phases complete:

- `bash scripts/compute-run-score.sh --help` exits 0
- `bash scripts/score-reflector.sh --help` exits 0
- `./scripts/audit-log-query.sh --help` shows `scores` and `trend` commands
- `python3 -c "import json; json.load(open('configs/score-dimensions.json'))"` succeeds
- `python3 -c "import json; json.load(open('configs/audit-event-schema.json'))"` succeeds
- `bash scripts/validate-all.sh` passes
- `bash scripts/test-integration.sh` passes (including 8+ new scoring tests and updated test 16)
- `bash generators/test_skill_generator.sh` passes
- `grep -q 'run_score' configs/audit-event-schema.json` succeeds
- `grep -q 'version: 3.8.0' skills/ship/SKILL.md` succeeds
- `grep -q 'compute-run-score' skills/ship/SKILL.md` succeeds
- `grep -q 'Quantitative Scoring' CLAUDE.md` succeeds
- `grep -q 'code_review' scripts/compute-run-score.sh` succeeds

## Next Steps

1. Review this plan. Request clarification on any dimension definitions, weights, or architectural decisions.
2. Execute Phase 1 (schema + compute script) -- foundational infrastructure with no skill changes.
3. Execute Phases 2-3 in parallel (query commands + ship integration). Phase 2 is testable with synthetic data; real scores arrive when Phase 3 lands.
4. Execute Phase 4 (reflector) after at least one real /ship run has emitted score data.
5. Execute Phase 5 (tests + docs) after all scripts are written.
6. After 10+ scored /ship runs, manually invoke `score-reflector.sh` and evaluate candidate learnings quality (including trend analysis). This informs whether Phase 3 (automated feedback loop) from Future Work is worth pursuing.

## Status: APPROVED

## Plan Metadata

- **Plan File:** `./plans/quantitative-eval-scoring.md`
- **Affected Components:** configs/audit-event-schema.json, scripts/compute-run-score.sh (new), scripts/score-reflector.sh (new), scripts/audit-log-query.sh, scripts/test-integration.sh, skills/ship/SKILL.md, configs/score-dimensions.json (new), CLAUDE.md
- **Validation:** `bash scripts/validate-all.sh && bash scripts/test-integration.sh && bash generators/test_skill_generator.sh`

<!-- Context Metadata
discovered_at: 2026-05-09T07:54:00Z
claude_md_exists: true
recent_plans_consulted: agentic-sdlc-security-skills.md, audit-remove-mcp-deps.md, devkit-hygiene-improvements.md
archived_plans_consulted: embedding-security-in-agentic-sdlc.md, ship-run-audit-logging, threat-model-consumption
-->
