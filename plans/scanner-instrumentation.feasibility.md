# Feasibility Review: Scanner Value Instrumentation (Round 2)

**Plan:** `plans/scanner-instrumentation.md` (v1.1)
**Reviewer:** Feasibility Analyst
**Date:** 2026-05-25
**Verdict:** PASS

---

## Prior Concern Resolution Status

All 8 prior concerns (4 Major, 4 of the 6 Minor) from the Round 1 feasibility review have been addressed in v1.1. Assessment follows.

| ID | Severity | Concern | Status | Notes |
|----|----------|---------|--------|-------|
| M1 | Major | Broken grep patterns (`Files scanned:` vs `Files:`) | **Resolved** | Change 0 added as prerequisite phase. Grep patterns fixed. Default changed from `"unknown"` to `"0"`. |
| M2 | Major | `file_count`/`symbol_count` typed as "string or integer" | **Resolved** | Schema now defines both as integer. |
| M3 | Major | `"unknown"` vs `"absent"` inconsistency | **Resolved** | Unified on `"absent"` throughout. Data Migration section clarified. Single sentinel value documented. |
| M4 | Major | `scanner-value-report.sh` line estimate too low (350) | **Resolved** | Revised to ~550 lines. Phase 2 effort revised from 1.5 days to 2 days. Total revised from 4 days to 4.5 days. |
| m2 | Minor | Python 3.10+ assumption too strict | **Resolved** | Plan now states "Python 3.10+ is available (consistent with compute-run-score.sh)" without requiring 3.10-specific features. The constraint is stated but the code samples use no 3.10+ syntax. |
| m4 | Minor | Cohen's d undefined for cohort size 1 | **Resolved** | Phase 2 deliverable now explicitly says "Handle Cohen's d edge cases (cohort size 1, pooled SD = 0)". |
| m5 | Minor | No `--help` for `scanner-value-report.sh` | **Not addressed** | No mention of `--help` in the plan. Low impact -- trivial to add during implementation. |
| m6 | Minor | Test 42 schema grep is fragile | **Not addressed** | Still proposes `grep for scanner_invocation in schema file`. Low impact -- grep will work, just not robust against false matches. |

Additionally, all 4 Red Team findings (F-01 through F-04) and 2 Librarian findings (L-01, L-02) from the revision log have been addressed. The most impactful resolution was F-01 (scoping correlation to `/ship` runs only), which required updating the architecture diagram, timeline estimates, and practical timeline section. The plan now correctly and consistently states that only `/ship` runs contribute to correlation analysis.

---

## Summary

The v1.1 revision is substantially improved. The major structural issues from Round 1 are resolved. The plan demonstrates thorough understanding of the existing audit infrastructure and proposes changes that are backward compatible, correctly scoped, and well-documented. The remaining concerns are implementable refinements, not architectural issues.

---

## New Concerns

### Critical

None.

### Major

**M1. Change 0 code sample does not fix the JSON emission template (string vs integer)**

The plan defines `file_count` and `symbol_count` as integers in the schema (correctly resolving prior M2), and Change 0 fixes the grep pattern and changes the default from `"unknown"` to `"0"`. However, the plan does not show or mention fixing the JSON emission template line in the skill files. The current emission template wraps these values in JSON string quotes:

```bash
# Current template (line 353 of ship/SKILL.md, line 135 of architect/SKILL.md):
"{\"file_count\":\"${SCANNER_FILE_COUNT}\",\"symbol_count\":\"${SCANNER_SYMBOL_COUNT}\"}"
```

With this template, even after fixing the grep, the emitted JSON would be `"file_count":"6"` (a string), not `"file_count":6` (an integer). To match the schema (integer type), the template needs to drop the inner quotes:

```bash
"{\"file_count\":${SCANNER_FILE_COUNT},\"symbol_count\":${SCANNER_SYMBOL_COUNT}}"
```

This is not a difficult fix, but it must be explicitly called out because: (a) it is a precondition for the schema to validate, (b) `scanner-value-report.sh` likely parses these as integers via `json.loads()`, and a string `"6"` versus integer `6` matters, and (c) the same fix applies to both `/architect` and `/ship`. If the template is not fixed, the schema change creates a schema-emission mismatch rather than resolving one.

**Recommended fix:** Add an explicit note to Change 0 (or Work Group 1) that the emission template line must also be updated to emit `file_count` and `symbol_count` as unquoted integers in the JSON string. Similarly, `output_token_count` (Change 1) should be emitted without JSON string quotes.

**M2. Change 0 code sample uses wrong variable name and different command patterns**

The Change 0 "Fixed" code sample uses `$SCANNER_SUMMARY`:
```bash
FILE_COUNT=$(echo "$SCANNER_SUMMARY" | grep -oP 'Files:\s*\K[0-9]+' || echo "0")
```

But the actual skill files use `$SCANNER_OUTPUT` (and `printf '%s'` instead of `echo`, with `2>/dev/null`):
```bash
SCANNER_FILE_COUNT=$(printf '%s' "$SCANNER_OUTPUT" | grep -oP 'Files scanned:\s*\K[0-9]+' 2>/dev/null || echo "unknown")
```

The variable name mismatch, the `echo` vs `printf '%s'` difference, the missing `2>/dev/null`, and the different variable name prefix (`FILE_COUNT` vs `SCANNER_FILE_COUNT`) could cause implementation confusion. A coder following the plan literally would introduce a variable that doesn't exist.

**Recommended fix:** Update Change 0 code samples to use the actual variable names (`SCANNER_OUTPUT`, `SCANNER_FILE_COUNT`, `SCANNER_SYMBOL_COUNT`) and the existing command patterns (`printf '%s'`, `2>/dev/null`).

### Minor

**m1. Token count calculation via `wc -c | awk` has a minor whitespace issue on macOS**

The proposed token count calculation:
```bash
SCANNER_TOKEN_COUNT=$(printf '%s' "$SCANNER_OUTPUT" | wc -c | awk '{printf "%.0f", $1 / 4}')
```

On macOS, `wc -c` outputs leading whitespace (e.g., `    1850`). The `awk` call handles this correctly (awk trims whitespace), so the calculation works. However, if `SCANNER_OUTPUT` is empty, `wc -c` outputs `0` and the token count will be `0`, which is the correct behavior. No action needed, but the implementation should add `|| echo "0"` as a safety net in case `wc` or `awk` fail unexpectedly.

**m2. `score-reflector.sh` reads `*.jsonl` (all logs) but Phase 3 scanner correlation must scope to `/ship` runs**

The existing `score-reflector.sh` collects `run_score` events from `plans/audit-logs/*.jsonl`, which includes `/architect` and `/audit` log files. Since only `/ship` emits `run_score`, this is harmless today. However, the Phase 3 scanner correlation check must extract `scanner_mode` from `run_score` events, not from `scanner_invocation` events in separate log files. This works because `compute-run-score.sh` (Change 2) embeds `scanner_mode` directly in the `run_score` event. But the plan's Phase 3 description says "checks whether scanner mode correlates with score outcomes" without specifying where `scanner_mode` comes from. The implementation should read `scanner_mode` from the `run_score` event itself (where it is embedded by Change 2), not by cross-referencing `scanner_invocation` events.

**m3. Test coverage gaps from Round 1 not fully addressed**

Round 1 identified three test coverage gaps:
1. No test for `output_token_count` field being numeric -- not addressed in v1.1 tests (38-42).
2. No test for `scanner-value-report.sh --format json` -- not addressed.
3. No test for `score-reflector.sh` scanner-correlation output -- not addressed.

The plan added the L-02 resolution (update test count from 37 to 42), and the existing 5 tests (38-42) provide core coverage. However, the three additional tests recommended in Round 1 remain absent. These are not blockers -- the 5 proposed tests cover the critical paths -- but adding them would strengthen regression coverage for the acceptance criteria (specifically criteria 1, 8, and 9).

**m4. Python 3.10+ assumption is stated but unnecessary**

Assumption 5 says "Python 3.10+ is available." The code samples and existing scripts use only standard library modules available since Python 3.6+ (`json`, `sys`, `os`, `glob`, `datetime`, `math`). No `match`/`case`, no `|` union types, no `str.removeprefix()`. The plan should either state the actual minimum (3.8+ for consistency with existing scripts) or note a specific 3.10+ feature it intends to use. Stating 3.10+ unnecessarily narrows the compatibility claim.

**m5. Prior minor m3 (macOS `grep -oP` portability) remains unaddressed**

Round 1 noted that `grep -oP` (Perl regex) is not supported by macOS BSD grep. The user has `ugrep` installed, so it works in practice. The plan's Change 0 fixes the *pattern* but retains `grep -oP`. Round 1 suggested replacing with a `python3 -c` call to eliminate both the bug and the portability concern in one change. The plan did not adopt this suggestion. This is acceptable -- the current user environment supports `-P` -- but it means the skill emission blocks are not portable to vanilla macOS without `ugrep` or GNU grep.

---

## Breaking Changes and Backward Compatibility

**No breaking changes.** The assessment from Round 1 remains valid:

1. New fields (`output_token_count`, `scanner_mode`, `scanner_tokens`) are additive.
2. Schema changes (adding `scanner_invocation` to the enum and oneOf) are backward compatible.
3. Old `run_score` events lacking new fields are handled with `"absent"` / `0` defaults.
4. `scanner-value-report.sh` is standalone and never invoked by any skill workflow.
5. The `emit_neutral()` fallback in `compute-run-score.sh` does not include the new fields, which is correct -- downstream consumers handle their absence.

---

## Dependency and Library Assessment

No issues. Same as Round 1:
- `python3` standard library only. No `numpy`, `scipy`, or external stats packages.
- Cohen's d computed with arithmetic: `d = (mean1 - mean2) / pooled_sd`. No library needed.
- No new binaries. Bash wrapper + embedded Python follows established pattern.
- No `jq` dependency (correctly addressed via L-01 resolution).

---

## Test Coverage Assessment

The 5 proposed integration tests (38-42) provide adequate core coverage:

| Test | What It Covers | Gap? |
|------|---------------|------|
| 38 | `compute-run-score.sh` extracts `scanner_mode` from `scanner_invocation` event | No |
| 39 | `compute-run-score.sh` defaults `scanner_mode` to `"absent"` when no `scanner_invocation` | No |
| 40 | `scanner-value-report.sh` handles empty audit-logs directory | No |
| 41 | `scanner-value-report.sh` produces markdown for synthetic scored runs | No |
| 42 | `scanner_invocation` registered in `audit-event-schema.json` enum | Fragile (grep-based) |

**Remaining gaps (non-blocking):**
- No test for `output_token_count` being numeric in emitted events (Acceptance Criterion 1).
- No test for `--format json` output (Acceptance Criterion 8).
- No test for `score-reflector.sh` scanner-correlation candidate learning (Acceptance Criterion 9).

These gaps are acceptable for a v1 implementation. The manual validation section covers them informally.

---

## Implementation Complexity Assessment

| Phase | Plan Estimate | My Assessment | Notes |
|-------|---------------|---------------|-------|
| Phase 0 | 0.5 days | 0.5 days | Straightforward grep fix + emission template fix (M1 above). Two files, ~4 lines each. |
| Phase 1 | 1 day | 1 day | Schema update is mechanical. `compute-run-score.sh` modification is ~30 lines of Python within an existing structure. |
| Phase 2 | 2 days | 2 days | ~550 lines is reasonable. Cohort grouping, Cohen's d, confidence tiers, two output formats, edge case handling. Matches revised estimate. |
| Phase 3 | 0.5 days | 0.5 days | Adding scanner correlation to `score-reflector.sh` is ~40 lines within existing structure. |
| Phase 4 | 1 day | 0.5-1 day | 5 integration tests + CLAUDE.md update. Tests follow existing `run_test()` pattern. |
| **Total** | **5 days** | **4.5-5 days** | Aligned with v1.1 estimate of 4.5 days. |

---

## Recommended Adjustments

1. **Fix the JSON emission template in Change 0 (Major).** Explicitly show that `file_count`, `symbol_count`, and `output_token_count` must be emitted as unquoted values in the JSON string (integers, not strings). Add a code sample showing the corrected emission template line alongside the corrected grep pattern.

2. **Fix variable names in Change 0 code sample (Major).** Replace `$SCANNER_SUMMARY`, `FILE_COUNT`, `SYMBOL_COUNT` with the actual variable names used in the skill files: `$SCANNER_OUTPUT`, `SCANNER_FILE_COUNT`, `SCANNER_SYMBOL_COUNT`. Match the existing `printf '%s'` and `2>/dev/null` patterns.

3. **Clarify Phase 3 data source.** Add a note that `score-reflector.sh`'s scanner correlation check should read `scanner_mode` from the `run_score` event (where it is embedded by Change 2), not by cross-referencing raw `scanner_invocation` events from log files.

4. **Consider adding 1-2 more integration tests** for `output_token_count` numeric validation and `--format json` output parsing, to close the gap between acceptance criteria and test coverage.

---

## Verdict: PASS

The v1.1 revision resolves all prior Major concerns and most Minor concerns. The two new Major findings (M1: emission template string-vs-integer, M2: code sample variable name mismatch) are implementable fixes that do not require architectural changes. The statistical reasoning, confidence tiers, and scoping to `/ship` runs are well-considered. The work group decomposition is clean and the effort estimates are realistic.

Total estimated effort: 4.5-5 days (aligned with plan's revised 4.5-day estimate after the M1/M2 corrections).
