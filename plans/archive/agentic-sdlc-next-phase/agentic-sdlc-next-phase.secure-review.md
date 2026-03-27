# Secure Review Summary -- changes -- 2026-03-27T16-05-00

## Verdict
**PASS**

## Scope
- Mode: `changes` (uncommitted modifications in working directory)
- Security-analyst agent: not found (generic scan)
- Files reviewed (8):
  1. `templates/agents/coder-specialist.md.template`
  2. `templates/agents/qa-engineer-specialist.md.template`
  3. `templates/claude-md-security-section.md.template` (new file)
  4. `CLAUDE.md`
  5. `generators/test_skill_generator.sh`
  6. `scripts/validate-all.sh` (new file)
  7. `scripts/deploy.sh`
  8. `generators/generate_agents.py`

---

## Critical Findings
Count: 0

No critical findings.

## High Findings
Count: 0

No high findings.

## Medium Findings
Count: 2

### M-1: Unquoted variable expansion in validate-all.sh (CWE-78: OS Command Injection)
- **File:** `scripts/validate-all.sh`, lines 33 and 39
- **Severity:** Medium
- **Description:** `$STRICT_FLAG` is used unquoted in command invocations:
  ```
  python3 "$VALIDATE_PY" "$skill_path" $STRICT_FLAG > /dev/null 2>&1
  python3 "$VALIDATE_PY" "$skill_path" $STRICT_FLAG 2>&1 | sed 's/^/    /' || true
  ```
  When `$STRICT_FLAG` is empty (no argument passed), the unquoted expansion correctly disappears (which is the intended behavior -- passing no extra argument). However, if a user passes a value containing spaces or shell metacharacters as `$1`, word splitting could produce unexpected arguments to `python3`. The variable is sourced from `${1:-}` (the first positional parameter to the script), which limits the attack surface to direct CLI invocation by the same user. The `set -euo pipefail` and `set -u` mitigate some risks.
- **Impact:** Low practical risk. The script runs locally by the developer who invokes it. An attacker would need local shell access, at which point they already have arbitrary execution. This is a defensive-coding best practice issue rather than an exploitable vulnerability.
- **Recommendation:** Use an array pattern instead:
  ```bash
  STRICT_ARGS=()
  if [[ -n "${1:-}" ]]; then STRICT_ARGS+=("$1"); fi
  # then: python3 "$VALIDATE_PY" "$skill_path" "${STRICT_ARGS[@]}"
  ```

### M-2: deploy.sh --validate flag passes unquoted path in error message (CWE-116: Improper Output Encoding)
- **File:** `scripts/deploy.sh`, lines 42 and 66
- **Severity:** Medium
- **Description:** The error message includes `$src/SKILL.md` without quoting in the `echo` hint:
  ```
  echo "  Run: python3 generators/validate_skill.py $src/SKILL.md" >&2
  ```
  While `$src` is derived from controlled path variables (`$SKILLS_DIR/$skill` or `$CONTRIB_DIR/$skill`) and the skill name is already validated by `validate_skill_name()` to reject `/`, `..`, and leading `-`, the variable is expanded unquoted inside a double-quoted string. In this specific context (inside double quotes in an echo), the expansion is actually safe -- bash will expand `$src` inside the double-quoted string without word splitting. This is informational only.
- **Impact:** None in practice. The variable is inside double quotes within the `echo` statement, and the skill name is pre-validated.
- **Recommendation:** No action required. The current code is correct.

## Low Findings
Count: 3

### L-1: Test script uses rm -rf on user-controlled test directory (CWE-73: External Control of File Name)
- **File:** `generators/test_skill_generator.sh`, line 497
- **Severity:** Low
- **Description:** `rm -rf "$TEST_DIR"` is used for cleanup. `$TEST_DIR` is derived from `mktemp -d` earlier in the script (not shown in diff but present in original), which produces a safe random temporary directory path. The variable is properly quoted.
- **Impact:** No risk. The path comes from `mktemp -d`, not user input.
- **Recommendation:** No action required. Current pattern is safe.

### L-2: Test 31 writes to user home directory path (CWE-377: Insecure Temporary File)
- **File:** `generators/test_skill_generator.sh`, lines 405-407
- **Severity:** Low
- **Description:** The test creates a directory at `$HOME/.claude/skills/test-undeploy-skill` and writes a test file there. This is the actual deployment target directory, not a temporary directory. The test then undeploys it.
- **Impact:** Minimal. This is intentional test behavior testing the real undeploy path. The test skill name (`test-undeploy-skill`) is unlikely to collide with a real skill. If the test fails mid-execution, a stale directory is left but is harmless.
- **Recommendation:** Consider using a unique name with timestamp or random suffix to avoid any theoretical collision.

### L-3: generate_agents.py error output change may affect downstream consumers (CWE-209: Information Exposure Through Error Messages)
- **File:** `generators/generate_agents.py`, line 436
- **Severity:** Low
- **Description:** Error message for unknown agent types changed from stdout (`print(f"...")`) to stderr (`print(f"...", file=sys.stderr)`). The function now returns exit code 1 on failures. This is actually an improvement -- errors should go to stderr and exit codes should reflect failure. No security concern.
- **Impact:** None. This is a positive change for correctness.
- **Recommendation:** No action required.

---

## Vulnerability Scan

### OWASP Top 10 / CWE Top 25
- **Injection (CWE-78, CWE-89):** No SQL, NoSQL, or command injection vectors found. Shell scripts use quoted variable expansions correctly in all security-critical paths. The `validate_skill_name()` function in `deploy.sh` properly rejects path traversal attempts (`/`, `..`) and flag injection (`-`).
- **Broken Authentication:** N/A -- no authentication mechanisms in scope.
- **XSS / CSRF:** N/A -- no web application code in scope.
- **Insecure Deserialization:** N/A -- no deserialization in scope.
- **Path Traversal (CWE-22):** `validate_skill_name()` prevents traversal via `/` and `..` checks. Paths are constructed from controlled base directories.
- **Hardcoded Credentials:** None found. No API keys, tokens, passwords, or private keys in any modified file.
- **Dangerous Functions:** No use of `eval`, `exec`, `os.system`, `subprocess.call(shell=True)`, or raw SQL in modified files.
- **Cryptographic Issues:** N/A -- no cryptographic operations in scope.
- **TOCTOU / Race Conditions:** `atomic_write()` in `generate_agents.py` uses `tempfile.mkstemp()` + `os.replace()`, which is the correct atomic write pattern. No TOCTOU issues.

## Data Flow Scan

### Sensitive Data Paths
- No PII handling in any modified file.
- No secrets, tokens, or credentials in any modified file.
- No logging of sensitive data.
- Template files (`coder-specialist.md.template`, `qa-engineer-specialist.md.template`) contain security guidance that explicitly prohibits logging sensitive data -- this is a positive security control being added.

### Data Leakage
- Error messages in `deploy.sh` and `generate_agents.py` expose file paths (e.g., `$src/SKILL.md`). These are local filesystem paths visible only to the developer running the tool. No external exposure vector.
- No debug endpoints, stack traces, or verbose error responses that could leak information.

## Auth/Authz Scan

### Authentication / Authorization
- N/A -- all modified files are local CLI tools and templates. No network-facing authentication or authorization logic is introduced.
- No session management, JWT handling, OAuth flows, or RBAC enforcement in scope.
- No API endpoints introduced or modified.

---

## Security Posture Assessment

### Positive Security Controls Added
1. **Secure coding standards in coder template** (`coder-specialist.md.template`): Adds input validation, parameterized queries, output encoding, CSRF protection, no-sensitive-logging, and constant-time comparison requirements. This is a meaningful security improvement for generated agents.
2. **Security testing requirements in QA template** (`qa-engineer-specialist.md.template`): Adds input validation boundary tests, auth bypass tests, authorization boundary tests, injection tests, XSS tests, and CSRF tests. Also adds test data security guidelines (no production data, synthetic PII, credential rotation).
3. **CLAUDE.md security section template** (`claude-md-security-section.md.template`): Provides a structured template for projects to document threat models, security requirements, and secure development practices.
4. **Deploy-time validation** (`deploy.sh --validate`): Adds optional validation gate before deployment, preventing invalid skills from being deployed.
5. **Expanded test coverage** (`test_skill_generator.sh`): Adds validation tests for 9 additional core skills and 3 conditional contrib skills, increasing coverage from 33 to 46 tests.
6. **validate-all.sh health check**: New script for comprehensive validation of all skills in one command.
7. **Improved error handling** (`generate_agents.py`): Errors now go to stderr with proper exit codes, improving failure visibility.

### Risk Assessment
The changes are entirely in the development tooling layer (generators, templates, deployment scripts, tests). No production application code, no network-facing services, and no data handling logic is modified. The changes consistently improve security posture by embedding security guidance into agent templates and adding validation gates.

---

## Risk Score
**2 / 10** (Low risk -- PASS)

- Scale: 1-3 Low risk (PASS), 4-6 Medium risk (PASS_WITH_NOTES), 7-10 High risk (BLOCKED)
- Rationale: Only medium/low informational findings. No exploitable vulnerabilities. Changes improve security posture. All files are local development tools with no external attack surface.

## Action Items

1. **(Optional, M-1)** Consider quoting `$STRICT_FLAG` using an array pattern in `validate-all.sh` for defensive coding best practices. Not blocking.

## Scan Coverage
- Scope: changes (uncommitted modifications)
- Vulnerability scan: Inline (OWASP Top 10, CWE Top 25, dangerous functions, hardcoded credentials, crypto, injection, path traversal, TOCTOU)
- Data flow scan: Inline (PII, secrets, logging, error exposure, data leakage)
- Auth/authz scan: Inline (N/A -- no auth/authz code in scope)
- Security-analyst agent: not found

## Redaction Notice
All secret values in findings have been redacted (first 4 / last 4 characters shown).
Actual values are never included in security reports.
No secrets were found in this review -- no redaction was necessary.
