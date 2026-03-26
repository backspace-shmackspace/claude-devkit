---
name: compliance-check
description: Validate codebase against code-level compliance signals for regulatory frameworks (FedRAMP, FIPS, OWASP, SOC 2). Scoped to source code analysis only — not a compliance certification.
model: claude-opus-4-6
version: 1.0.0
---
# /compliance-check Workflow

## Role

This skill is a **scan coordinator**. It orchestrates parallel compliance signal scans per requested framework, synthesizes findings, and produces a structured report with a PASS / PASS_WITH_NOTES / BLOCKED verdict. It checks **code-level signals only** — it does not verify organizational, infrastructure, or procedural controls.

This report is a development aid, not a compliance certification.

## Inputs

- Framework(s): $ARGUMENTS (required)
  - `fedramp` — Federal Risk and Authorization Management Program code-level controls
  - `fips` — FIPS 140-3 approved cryptography and key management patterns
  - `owasp` — OWASP Top 10 compliance with evidence
  - `soc2` — SOC 2 Type II code-level security controls

Multiple frameworks can be specified: `/compliance-check fips owasp`

## Step 0 — Parse and validate framework arguments

Tool: `Read`

Parse `$ARGUMENTS` as a space-separated list of framework names.

Normalize each to lowercase for matching.

**Validation:** For each argument, check against the supported list: `fedramp`, `fips`, `owasp`, `soc2`.

If any unknown framework name is found, stop immediately with:
"Unknown framework: [name]. Supported: fedramp, fips, owasp, soc2.

Usage: /compliance-check [fedramp|fips|owasp|soc2] [...]
Multiple frameworks may be specified: /compliance-check fips owasp"

If `$ARGUMENTS` is empty, stop with:
"Framework argument required. Supported: fedramp, fips, owasp, soc2.

Usage: /compliance-check [fedramp|fips|owasp|soc2] [...]"

Derive timestamp: `[timestamp]` = current ISO datetime (e.g., `2026-03-25T14-30-00`)

Store the validated list of frameworks for Step 1.

## Step 1 — Parallel compliance scans (one per framework)

Dispatch one Task subagent per validated framework, all in parallel.

Tool: `Task` (one subagent per framework, dispatched in parallel)

**Scope constraint (apply to all scan prompts):** Limit analysis to code-level signals only: source code files, configuration files (Dockerfiles, docker-compose, Kubernetes manifests, terraform, CI configs), dependency manifests (package.json, requirements.txt, go.mod, Cargo.toml), and hardcoded values. Do NOT attempt to verify organizational policies, infrastructure controls, personnel procedures, or runtime behavior.

---

**If `fedramp` is in the validated framework list:**

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`

Prompt: "Perform a FedRAMP code-level compliance signal scan. Scope: source code, configuration files, deployment manifests only.

Do NOT attempt to verify organizational policies, infrastructure controls outside the codebase, or personnel procedures.

Check for these FedRAMP code-level signals:

Access Control (AC):
- Role-based access control (RBAC) implementation patterns in code
- Least privilege enforcement (no overly broad permission grants in code)
- Session timeout configuration in application code
- Multi-factor authentication enforcement in authentication flows

Audit and Accountability (AU):
- Audit logging calls present for security-relevant events (login, logout, privilege changes, data access)
- Log entries include who, what, when, where (user ID, action, timestamp, source IP)
- Sensitive data excluded from log statements (no passwords, tokens, PII in log calls)

Configuration Management (CM):
- No hardcoded environment-specific values (IPs, hostnames) in source code
- Configuration loaded from environment variables or secret managers (not hardcoded)
- Dependency pinning (exact versions in manifests, not ranges for production deps)

Identification and Authentication (IA):
- Password complexity enforcement (min length, complexity rules in validation code)
- Account lockout after failed attempts (present in authentication logic)
- Secure credential storage patterns (hashing libraries used, not plaintext storage)

System and Communications Protection (SC):
- TLS/HTTPS enforcement in HTTP client configuration
- No HTTP (non-TLS) connections to external services in code
- Encryption at rest patterns (use of encryption libraries for stored sensitive data)

Rate each finding: Critical / High / Medium / Low.
Write to `./plans/compliance-check-[timestamp].fedramp.md`"

---

**If `fips` is in the validated framework list:**

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`

Prompt: "Perform a FIPS 140-3 code-level compliance signal scan. Scope: source code, configuration files, dependency manifests only.

Do NOT attempt to verify CMVP certification status of runtime cryptographic modules. Check only what is visible in source code.

Check for these FIPS code-level signals:

Approved Cryptographic Algorithms — flag any use of non-FIPS-approved algorithms:
- Hash functions: MD5, SHA-1 are NOT approved. SHA-2 (SHA-256, SHA-384, SHA-512) and SHA-3 are approved.
- Symmetric encryption: DES, 3DES, RC4, RC2, Blowfish are NOT approved. AES (128, 192, 256-bit) is approved.
- Asymmetric encryption: RSA < 2048 bits is NOT approved. RSA >= 2048, ECDSA with NIST curves (P-256, P-384, P-521) are approved.
- Key agreement: DH < 2048 bits is NOT approved. DH >= 2048, ECDH with NIST curves are approved.
- MAC: HMAC-SHA1 is borderline — flag for review. HMAC-SHA-256 and above are approved.

Key Management Patterns:
- Key derivation using PBKDF2, HKDF, or NIST-approved KDFs (flag use of custom KDFs)
- Key lengths meeting FIPS minimums (flag short keys)
- Secure key storage patterns (keys not hardcoded in source)

Random Number Generation:
- Use of cryptographically secure RNG (flag use of Math.random(), random.random(), or non-CSPRNG for security purposes)
- Flag use of predictable seeds for security-sensitive randomness

Cipher Mode of Operation:
- Flag ECB mode usage (not approved for most uses)
- Flag unauthenticated CBC for encryption-then-MAC concerns (prefer GCM or CCM)

Rate each finding: Critical / High / Medium / Low.
Critical: Non-FIPS algorithm actively used in security-sensitive path.
High: Non-FIPS algorithm used but context unclear, or key length below minimum.
Medium: Potentially non-FIPS pattern requiring manual review.
Low: Informational — approved algorithm but suboptimal configuration.

Write to `./plans/compliance-check-[timestamp].fips.md`"

---

**If `owasp` is in the validated framework list:**

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`

Prompt: "Perform an OWASP Top 10 (2021) code-level compliance signal scan. Scope: source code and configuration files only.

Check each OWASP Top 10 category for code-level evidence of compliance or violation:

A01 - Broken Access Control:
- Missing authorization checks on sensitive endpoints
- Insecure direct object references (user-controlled IDs without ownership check)
- CORS misconfiguration (wildcard origins in code)

A02 - Cryptographic Failures:
- Sensitive data transmitted in HTTP (non-TLS)
- Weak or deprecated cryptographic algorithms (see FIPS scan for specifics)
- Secrets hardcoded in source

A03 - Injection:
- SQL queries built by string concatenation (not parameterized)
- Command injection (os.system, exec with user input)
- LDAP, XPath, SSTI injection patterns
- NoSQL injection (unvalidated object queries)

A04 - Insecure Design:
- Missing input validation on public API endpoints
- Business logic that can be bypassed by parameter manipulation
- Rate limiting absent on authentication/sensitive endpoints

A05 - Security Misconfiguration:
- Debug endpoints or stack traces exposed in production configuration
- Default credentials in config files
- Unnecessary features or services enabled in deployment manifests

A06 - Vulnerable and Outdated Components:
- Dependency manifests present for review (flag if lock files are absent)
- Known vulnerable version ranges (flag if visible from manifest context)

A07 - Identification and Authentication Failures:
- Weak session management (short session IDs, missing expiry)
- Brute force protection absent on login endpoints
- Insecure password reset flows

A08 - Software and Data Integrity Failures:
- Deserialization of untrusted data without validation
- Dependency integrity checks absent (no subresource integrity, no lock files)
- CI/CD pipeline accepting unverified artifacts

A09 - Security Logging and Monitoring Failures:
- Absence of logging for authentication events, access control failures
- Sensitive data included in log statements

A10 - Server-Side Request Forgery (SSRF):
- User-controlled URLs passed to HTTP client libraries without allowlist validation
- DNS rebinding exposure patterns

Rate each finding: Critical / High / Medium / Low.
Write to `./plans/compliance-check-[timestamp].owasp.md`"

---

**If `soc2` is in the validated framework list:**

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`

Prompt: "Perform a SOC 2 Type II code-level compliance signal scan. Focus on the Security trust service criteria (CC). Scope: source code, configuration files, and deployment manifests only.

Do NOT attempt to verify organizational policies, vendor management, HR procedures, or physical security. Check only what is visible in source code and configuration.

Check for these SOC 2 code-level signals:

CC6 - Logical and Physical Access Controls:
- Authentication required for all non-public endpoints (flag missing auth middleware)
- Role-based access control implementation (RBAC patterns present)
- Privileged access controls (admin functions gated by elevated role checks)
- Session management (timeouts, invalidation on logout)

CC7 - System Operations:
- Error handling that does not expose stack traces or internal details to users
- Logging of security-relevant events (authentication, authorization failures, data access)
- Sensitive data excluded from logs (no passwords, tokens, or PII in log calls)

CC8 - Change Management:
- No commented-out code containing credentials or sensitive logic
- Environment-specific configuration externalized (not hardcoded for prod/staging)
- Feature flags or configuration toggles present for controlled rollout

CC9 - Risk Mitigation:
- Input validation on all external data sources (HTTP params, file uploads, webhooks)
- Output encoding to prevent injection in rendered content
- Dependency versions pinned (supply chain risk reduction)

Data Protection Patterns:
- Encryption used for sensitive data fields at rest (ORM-level or application-level)
- Secure transmission enforced (TLS configuration, HSTS headers in web config)
- PII minimization (collect only what is needed)

Rate each finding: Critical / High / Medium / Low.
Write to `./plans/compliance-check-[timestamp].soc2.md`"

## Step 2 — Synthesis

Read all completed scan reports and synthesize into a unified compliance summary.

Tool: `Read` (direct — coordinator does this)

Read all reports that were generated (only the frameworks that were requested):
- `./plans/compliance-check-[timestamp].fedramp.md` (if fedramp was scanned)
- `./plans/compliance-check-[timestamp].fips.md` (if fips was scanned)
- `./plans/compliance-check-[timestamp].owasp.md` (if owasp was scanned)
- `./plans/compliance-check-[timestamp].soc2.md` (if soc2 was scanned)

Generate `./plans/compliance-check-[timestamp].summary.md` with this structure:

```markdown
# Compliance Check Summary — [frameworks] — [timestamp]

## Verdict
[PASS / PASS_WITH_NOTES / BLOCKED]

## Frameworks Checked
[List of frameworks scanned]

## Critical Findings
[Count: N]
- [Finding — framework, control reference, file:line if applicable]

## High Findings
[Count: N]
- [Finding — framework, control reference, file:line if applicable]

## Medium Findings
[Count: N]
(Summarize or list with framework attribution)

## Low Findings
[Count: N]
(Summarize or list)

## Risk Score
[1-10 scale]
- 1-3: Low risk (PASS)
- 4-6: Medium risk (PASS_WITH_NOTES)
- 7-10: High risk (BLOCKED)

## Action Items
(Prioritized by severity — address Critical before any compliance claim)

1. [Critical item 1 — framework + control]
2. [Critical item 2 — framework + control]
3. [High item 1 — framework + control]
...

## Framework Reports
[List each scanned framework with its report path]

## Limitations

This report covers **code-level compliance signals only**. The following controls
are NOT verifiable from source code analysis and require separate verification:

### Not Checked
- [ ] Organizational policies and procedures
- [ ] Infrastructure and network controls
- [ ] Personnel security (background checks, training)
- [ ] Physical security controls
- [ ] Vendor and third-party risk management
- [ ] Incident response procedures and testing
- [ ] Continuous monitoring infrastructure
- [ ] CMVP certification status of cryptographic modules (FIPS)
- [ ] Audit log forwarding and SIEM integration

### What This Report DOES Cover
- Code-level security patterns (encryption, auth, input validation)
- Configuration file analysis (Dockerfiles, deployment manifests)
- Dependency and library usage patterns
- Hardcoded credentials and secret management patterns

**This report is a development aid, not a compliance certification.**
```

**Verdict rules:**
- **BLOCKED**: Any Critical findings OR 3+ High findings
- **PASS_WITH_NOTES**: 1-2 High findings OR 3+ Medium findings
- **PASS**: Only Medium/Low findings

## Step 3 — Verdict gate

Read `./plans/compliance-check-[timestamp].summary.md` and report verdict.

Tool: `Read`

**If BLOCKED:**
Report:
"compliance-check BLOCKED — Critical compliance gaps require remediation.

Summary: ./plans/compliance-check-[timestamp].summary.md
All Critical findings must be resolved before making any compliance claims.

Frameworks checked: [list]
Critical findings: [count]
High findings: [count]

This report is a development aid, not a compliance certification."

**If PASS_WITH_NOTES:**
Report:
"compliance-check PASS WITH NOTES — Compliance gaps found but not blocking.

Summary: ./plans/compliance-check-[timestamp].summary.md
Review High findings before making compliance claims. Merging is not blocked.

Frameworks checked: [list]
High findings: [count]
Medium findings: [count]

This report is a development aid, not a compliance certification."

**If PASS:**
Report:
"compliance-check PASS — No blocking compliance gaps found.

Summary: ./plans/compliance-check-[timestamp].summary.md

Frameworks checked: [list]
Medium findings: [count]
Low findings: [count]

This report is a development aid, not a compliance certification."

## Step 4 — Archive on completion

Move scan artifacts to archive.

Tool: `Bash`

Archive path: `./plans/archive/compliance-check/[timestamp]/`

```bash
mkdir -p "./plans/archive/compliance-check/[timestamp]"
mv ./plans/compliance-check-[timestamp].* "./plans/archive/compliance-check/[timestamp]/"
```

Report: "Scan complete. Results archived to ./plans/archive/compliance-check/[timestamp]/"
