# Secure Review Summary -- changes -- 2026-03-27T15-30-00

## Verdict
**PASS**

## Critical Findings
Count: 0

_(None)_

## High Findings
Count: 0

_(None)_

## Medium Findings
Count: 0

_(None)_

## Low Findings
Count: 2

### L-1: `eval` usage in test runner functions

- **Severity:** Low
- **Scan:** Vulnerability
- **Files:**
  - `generators/test_skill_generator.sh:71`
  - `scripts/test-integration.sh:61`
- **Description:** Both scripts use `eval "$test_command"` in their `run_test()` function to execute test commands. `eval` interprets shell metacharacters and can lead to command injection if the input is attacker-controlled.
- **Mitigating factors:** All test commands are hardcoded string literals defined within the scripts themselves. There is no external input path -- `$test_command` is never sourced from user input, environment variables, or file contents. These are developer-only test scripts, not production runtime code.
- **Recommendation:** No action required. The `eval` pattern is standard for shell test harnesses with internally-defined command strings. If the test runner is ever refactored to accept external test definitions, this should be revisited.

### L-2: `rm -rf` on variable-constructed paths

- **Severity:** Low
- **Scan:** Vulnerability
- **Files:**
  - `generators/test_skill_generator.sh:47,53,524,538`
  - `scripts/test-integration.sh:38-40,87,102,114-116`
- **Description:** Both scripts use `rm -rf` with paths constructed from shell variables (`$TEST_DIR`, `$SKILLS_DIR`, `$DEPLOY_DIR`). If a variable were empty or incorrectly set, `rm -rf` could delete unintended directories.
- **Mitigating factors:** All path variables are derived from `BASH_SOURCE` (the script's own location) or hardcoded `/tmp/` prefixes. The new trap handler in `test_skill_generator.sh` (lines 50-55) properly scopes cleanup to a single known directory (`$SKILLS_DIR/skills/test-validate-invalid`). The integration test trap handler (lines 37-41) is similarly well-scoped. No unbounded recursive deletes exist.
- **Recommendation:** No action required. The current scoping is adequate. For additional defense-in-depth, scripts could validate that `$TEST_DIR` starts with `/tmp/` before executing `rm -rf`, but this is not blocking.

## Informational Notes

### Settings precedence fix (ship/SKILL.md)

The settings precedence change correctly introduces a `LOCAL_SET` flag to track whether `.claude/settings.local.json` provided a `security_maturity` value. This prevents a subtle bug where `settings.local.json` setting `"advisory"` (the default) would be overridden by a different value in `settings.json`.

**Security assessment:** The fix is sound. The `case` validation at line 113-117 correctly rejects unknown maturity values and defaults to `"advisory"` (L1, the most permissive but safe default). No new attack surface is introduced.

### Trap handler addition (test_skill_generator.sh)

The new `cleanup_on_exit` trap handler (lines 50-55) addresses a race condition where Test 48 creates a temporary invalid skill directory (`skills/test-validate-invalid/`) inside the repo tree. If the script was interrupted between creation and deletion, this stale directory would persist and break `deploy_all_core()` and `validate-all.sh`. The trap catches `EXIT`, `INT`, and `TERM` signals.

**Security assessment:** This is a correctness improvement that also prevents a denial-of-service condition (broken deploy/validate workflows from stale test fixtures). No security concerns.

### New integration test script (scripts/test-integration.sh)

The integration test script follows the same patterns as the existing unit test script. It generates temporary skills in `/tmp/`, deploys them to `~/.claude/skills/`, validates them, and cleans up. The trap handler ensures cleanup on abnormal exit.

**Security assessment:** No concerns. The script operates on its own test fixtures and does not interact with production data or credentials.

### New archetype guide (generators/ARCHETYPE_GUIDE.md)

Pure documentation file. Contains no executable code, no secrets, no configuration, and no security-relevant content.

**Security assessment:** No concerns.

## Risk Score
**2 / 10** -- Low risk (PASS)

The changes are developer tooling (test scripts, documentation, configuration logic). No production code, no network-facing code, no credential handling, no authentication logic. The two Low findings are standard shell patterns with adequate mitigations already in place.

## Action Items

_(No Critical or High findings. No action required before merging.)_

Optional improvements (not blocking):
1. Consider adding a `[[ "$TEST_DIR" == /tmp/* ]]` guard before `rm -rf "$TEST_DIR"` in both test scripts for defense-in-depth.

## Scan Coverage
- **Scope:** changes (uncommitted modifications)
- **Files reviewed:**
  - `generators/test_skill_generator.sh` -- trap handlers, deploy validation tests (Tests 47-50)
  - `skills/ship/SKILL.md` -- settings precedence fix (LOCAL_SET flag)
  - `scripts/test-integration.sh` -- new integration smoke test script (5 tests)
  - `generators/ARCHETYPE_GUIDE.md` -- new documentation file
- **Vulnerability scan:** Completed -- checked OWASP Top 10, CWE Top 25, injection vectors, hardcoded secrets, dangerous functions, TOCTOU
- **Data flow scan:** Completed -- checked PII exposure, encryption gaps, data leakage, logging of sensitive values
- **Auth/authz scan:** Completed -- checked auth bypasses, RBAC, session management, JWT, OAuth (none present in scope)
- **Security-analyst agent:** not found

## Redaction Notice
All secret values in findings have been redacted (first 4 / last 4 characters shown).
Actual values are never included in security reports.

No secrets were found in this review.
