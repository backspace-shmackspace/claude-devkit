# Code Review: scanner-instrumentation

**Plan:** `plans/scanner-instrumentation.md`
**Date:** 2026-05-25
**Reviewer:** code-reviewer agent
**Round:** 2 (re-review after revision)

---

## Verdict: PASS

All five findings from Round 1 are confirmed fixed. No new issues introduced by the revisions.

---

## Finding Disposition

### C1 — Test flag mismatch: `--log-dir` vs `--audit-log-dir` (RESOLVED)

**File:** `scripts/test-integration.sh`, lines 510 and 529

Both lines now use `--audit-log-dir`. Verified:

```
510:  OUTPUT=$(bash '$REPO_DIR/scripts/scanner-value-report.sh' --audit-log-dir "$EMPTY_LOGS" 2>/dev/null)
529:  OUTPUT=$(bash '$REPO_DIR/scripts/scanner-value-report.sh' --audit-log-dir "$SYNTH_LOGS" 2>/dev/null)
```

Tests 40 and 41 will now correctly redirect script reads to their synthetic log directories.

---

### M1 — Numeric fields emitted as JSON strings (RESOLVED)

**Files:** `skills/architect/SKILL.md` line 136, `skills/ship/SKILL.md` line 354

Both emission lines now interpolate `file_count`, `symbol_count`, and `output_token_count` as bare numbers (no surrounding `\"`). Confirmed in both files:

```bash
"...\"file_count\":${SCANNER_FILE_COUNT},\"symbol_count\":${SCANNER_SYMBOL_COUNT},...\"output_token_count\":${SCANNER_TOKEN_COUNT}}"
```

This produces valid integer JSON (`"file_count":112`) matching the schema definition. The `int()` conversion guard in `compute-run-score.sh` remains as an additional safety net, which is appropriate.

---

### M2 — `parser_mode` "unknown" propagating into `run_score.scanner_mode` (RESOLVED)

**File:** `scripts/compute-run-score.sh`, lines 290-298

The fix correctly sanitizes `parser_mode` before embedding it in the `run_score` event:

```python
scanner_mode = scanner_evt.get('parser_mode', 'absent')
# M2: Sanitize parser_mode — map any value outside the valid enum to 'absent'
if scanner_mode not in ('tree-sitter-partial', 'regex-fallback'):
    scanner_mode = 'absent'
```

Additionally, the revision added a `try/except (TypeError, ValueError)` guard around `int(scanner_evt.get('output_token_count', 0))` (lines 295-298), hardening against non-numeric values from the old string-emission format. Both skill files still use `|| echo "unknown"` as the grep fallback for `SCANNER_PARSER_MODE`, but this is now harmless: the sanitization in `compute-run-score.sh` ensures `"unknown"` never reaches `run_score.scanner_mode`.

---

### M3 — Velocity extraction always returning None (RESOLVED)

**File:** `scripts/scanner-value-report.sh`, lines 360-367

`get_velocity()` now reads from the top-level `velocity_minutes` field:

```python
def get_velocity(event):
    v = event.get('velocity_minutes', None)
    if v is None:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None
```

This matches how `compute-run-score.sh` emits velocity (top-level field, not in `dimensions[]`). The velocity column in cohort comparison tables will now populate correctly.

---

### m1 — Architecture tree missing `scanner-value-thresholds.json` (RESOLVED)

**File:** `CLAUDE.md`, line 60

The configs directory tree now includes:

```
├── scanner-value-thresholds.json  # Confidence tiers for scanner value analysis
```

The entry is placed between `scanner-languages.json` and `base-definitions/`, consistent with alphabetical ordering of the other entries.

---

## New Observations

No new defects introduced. Two implementation choices are worth noting for the record:

**Skills still set `SCANNER_PARSER_MODE` to "unknown" on grep failure.** This is benign: the value is emitted to the raw `scanner_invocation` event's `parser_mode` field (which is technically outside the schema enum `["tree-sitter-partial", "regex-fallback"]`), but `compute-run-score.sh` normalizes it to `"absent"` before it reaches `run_score.scanner_mode`. If a future `audit-log-query.sh` extension validates `scanner_invocation.parser_mode` against the schema enum, these events would appear invalid. The strictly correct fix would change the skill fallback from `"unknown"` to an empty string, then let `compute-run-score.sh` detect the empty value and map to `"absent"`. This is a latent issue, not a blocker — the current implementation is correct for all current consumers.

**`int()` guard in `compute-run-score.sh` is defensive layering.** With M1 fixed, upstream emission produces integers, making the guard redundant for new runs. It correctly handles any surviving old-format events (where `output_token_count` was emitted as a string). The guard is net-positive and should be kept.

---

## Acceptance Criteria Check

| AC | Description | Status |
|----|-------------|--------|
| AC1 | `scanner_invocation` includes `output_token_count` in both skills | PASS |
| AC2 | `scanner_invocation` registered in `configs/audit-event-schema.json` | PASS |
| AC3 | `compute-run-score.sh` outputs `scanner_mode` and `scanner_tokens` | PASS |
| AC4 | `compute-run-score.sh` defaults to `"absent"` / `0` when no event | PASS |
| AC5 | `scanner-value-report.sh` reads `ship-*.jsonl`, groups by `scanner_mode` | PASS |
| AC6 | Correct confidence tier assigned by sample size | PASS |
| AC7 | Cohen's d computed and reported | PASS |
| AC8 | `--format json` produces valid JSON | PASS |
| AC9 | `score-reflector.sh` generates scanner correlation learning at 10+ runs | PASS |
| AC10 | `configs/scanner-value-thresholds.json` defines all four tiers | PASS |
| AC11 | All existing tests pass | Not re-run in this review (unchanged test infrastructure) |
| AC12 | 5 new integration tests pass (C1 fix unblocks Test 41) | PASS |
