# Secure Review Summary -- changes -- 2026-05-25T22:50:00

## Verdict
PASS_WITH_NOTES

## Critical Findings
Count: 0

(None)

## High Findings
Count: 0

(None)

## Medium Findings
Count: 2

### M-1: Unguarded `int()` conversion can crash scoring pipeline (CWE-20: Improper Input Validation)

**Source:** Vulnerability scan
**File:** `scripts/compute-run-score.sh`, embedded Python line 291
**Severity:** Medium

The new code at line 291 performs `int(scanner_evt.get('output_token_count', 0))` without a try/except guard. If a malformed or tampered JSONL audit log contains a non-numeric `output_token_count` value (e.g., `"output_token_count": "NaN"` or `"output_token_count": "1500 tokens"`), this will raise an unhandled `ValueError` and crash the entire `compute-run-score.sh` script.

This is inconsistent with the sibling code in `scanner-value-report.sh` (lines 242-245), which correctly wraps the same conversion in a `try/except` block via `get_scanner_tokens()`.

**Impact:** A crashed scoring script means no `run_score` event is emitted, which silently breaks the quantitative scoring pipeline. At L2/L3 maturity this could result in incomplete audit logs being committed. The crash is triggered by malformed data, not by attacker-controlled input in normal operation, but audit logs at L3 are committed to git and could be edited by any contributor.

**Recommendation:** Wrap in try/except consistent with the pattern used in `scanner-value-report.sh`:
```python
try:
    scanner_tokens = int(scanner_evt.get('output_token_count', 0))
except (TypeError, ValueError):
    scanner_tokens = 0
```

---

### M-2: Test flag mismatch -- Tests 40 and 41 use `--log-dir` but script accepts `--audit-log-dir` (CWE-670: Always-Incorrect Control Flow Implementation)

**Source:** Vulnerability scan / auth-authz scan
**File:** `scripts/test-integration.sh`, lines 510 and 529
**Severity:** Medium

Tests 40 and 41 invoke `scanner-value-report.sh` with `--log-dir` but the script only recognizes `--audit-log-dir`. The unknown flag is silently discarded (the `*) shift ;;` catch-all emits a warning to stderr, which the test suppresses with `2>/dev/null`). The path argument following `--log-dir` is also discarded as a second unknown arg.

As a result, both tests use the default `./plans/audit-logs/` directory instead of the intended temp directory. The tests may pass or fail depending on ambient audit log state, not the synthetic test data. This means the scanner-value-report.sh script has no effective integration test coverage for its core path (reading from a specified directory).

**Impact:** Reduced test coverage means regressions in the reporting script could go undetected. No direct security impact, but the tests create false confidence in code correctness.

**Recommendation:** Change `--log-dir` to `--audit-log-dir` in both tests:
- Line 510: `--log-dir` -> `--audit-log-dir`
- Line 529: `--log-dir` -> `--audit-log-dir`

## Low Findings
Count: 3

### L-1: JSON string interpolation of shell variables without sanitization (pre-existing, scope-adjacent)

**Source:** Vulnerability scan
**Files:** `skills/architect/SKILL.md` line 136, `skills/ship/SKILL.md` line 354
**Severity:** Low

Shell variables `SCANNER_VERSION`, `SCANNER_PARSER_MODE`, `SCANNER_HASH`, and the new `SCANNER_TOKEN_COUNT` are interpolated directly into a JSON string passed to `emit-audit-event.sh`. The `SCANNER_PARSER_MODE` is extracted via `grep -oP 'Parser:\s*\K\S+'` which matches any non-whitespace, potentially including JSON-special characters like `"`, `\`, or `}`.

This is a **pre-existing** pattern not introduced by this diff. The new `SCANNER_TOKEN_COUNT` variable is safe because it is computed via `wc -c | awk '{printf "%.0f", $1 / 4}'` which only outputs numeric values.

**Impact:** If the codebase-scanner.py output were to contain a `Parser: ` line with JSON-special characters, the audit event JSON could become malformed. Exploitation requires control over scanner output, which is not externally reachable. Risk is negligible in practice.

**Recommendation:** No action needed for this diff. Consider using `python3 json.dumps()` for JSON construction in a future cleanup pass (consistent with `emit-audit-event.sh` which already uses it).

---

### L-2: `subprocess.run` invocation in scanner-value-report.sh with log file paths

**Source:** Data flow scan
**File:** `scripts/scanner-value-report.sh`, lines 171-176
**Severity:** Low

The script passes `log_files[:1]` (a file path from `glob.glob()`) to `subprocess.run(['git', 'check-ignore', '--quiet'] + log_files[:1])`. The paths come from a glob pattern against a known directory, not from user input. The `subprocess.run` uses a list (not `shell=True`), which prevents shell injection. The call is wrapped in a try/except that catches all exceptions.

**Impact:** Negligible. The subprocess call is safe by construction (list-based invocation, no shell expansion, exception-guarded). Noted for completeness.

---

### L-3: Silent fallback on unknown CLI arguments

**Source:** Auth/authz scan
**File:** `scripts/scanner-value-report.sh`, lines 104-107
**Severity:** Low

Unknown arguments are silently discarded with only a warning to stderr. This is the root cause of M-2 above. While this is a reasonable UX choice for a reporting tool (fail-open, never block), it makes debugging harder and enables the test mismatch to go unnoticed.

**Impact:** No security impact. Ergonomic concern only.

**Recommendation:** Consider adding a `--strict` mode that exits non-zero on unknown arguments, or at minimum log unknown args at a higher visibility level.

## Risk Score
3 / 10

Low risk. All changes are to local-only analysis scripts and skill definitions (markdown). No network-facing code, no authentication logic, no credential handling, no data persistence to external systems. The two medium findings are robustness and test correctness issues, not exploitable vulnerabilities.

## Action Items

1. **[M-1]** Add try/except guard around `int()` conversion in `compute-run-score.sh` line 291
2. **[M-2]** Fix test flag mismatch: change `--log-dir` to `--audit-log-dir` in `test-integration.sh` lines 510 and 529

## Scan Coverage
- Scope: changes (uncommitted modifications in working directory)
- Files reviewed: 9 (CLAUDE.md, scripts/compute-run-score.sh, scripts/score-reflector.sh, scripts/test-integration.sh, skills/architect/SKILL.md, skills/ship/SKILL.md, scripts/scanner-value-report.sh, configs/audit-event-schema.json, configs/scanner-value-thresholds.json)
- Vulnerability scan: inline (no separate artifact -- single-agent execution)
- Data flow scan: inline
- Auth/authz scan: inline
- Security-analyst agent: not found (generic scan)

## Redaction Notice
All secret values in findings have been redacted (first 4 / last 4 characters shown).
Actual values are never included in security reports. No secrets were detected in the scanned changes.
