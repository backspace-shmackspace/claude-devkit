# Embedding Security in Agentic SDLC Pipelines

**Proposed standard for security controls in AI-assisted development workflows**

**Author:** Ian Murphy
**Date:** 2026-03-23 (revised 2026-03-26)
**Audience:** Red Hat development teams using Claude Code, Cursor, Copilot, or other AI coding assistants
**Status:** Proposed standard -- draft for ProdSec review

**Document conventions:** This document uses normative language per RFC 2119. MUST, SHOULD, and MAY indicate requirement levels.

---

<!-- SECTION PURPOSE: Scope and applicability -->

## Scope

This document defines security controls for development teams using AI coding assistants. It covers five intervention points in the agentic SDLC, a severity taxonomy, a maturity graduation path, and an agentic threat model.

Sections are marked by purpose:
- **Normative sections** define controls teams MUST or SHOULD implement.
- **Informative sections** provide rationale and implementation guidance.
- **Ephemeral sections** (roadmap, discussion points) are time-bound and subject to removal in future revisions.
- **Platform-specific sections** (Red Hat) require independent maintenance and validation against current platform documentation.

---

<!-- SECTION PURPOSE: Problem framing (informative) -->

## Problem statement

Development teams adopting AI coding assistants generate code at a rate that exceeds the capacity of existing security review processes. Without guardrails integrated into the AI-assisted workflow, the following risks are present:

- AI-generated code may ship without automated security review
- Threat modeling may not occur during AI-assisted planning
- Dependency choices made by AI agents may go unvetted
- Secrets may be introduced without detection
- Compliance requirements (FedRAMP, SOC 2, FIPS) may not be checked pre-commit

AI-generated code is subject to the same vulnerability classes as human-written code, with particular risk in areas where secure defaults require explicit developer intent. AI coding assistants prioritize functional correctness; security properties are not consistently enforced unless explicitly specified in project configuration or prompts.

### How agentic development changes AppSec assumptions

Traditional AppSec controls were designed around human-speed development with human-authored code. Agentic development changes the assumptions these controls rely on:

1. **Speed.** AI generates code faster than humans can review it.
2. **Volume.** Higher code generation velocity increases the rate at which new functionality, and potentially new attack surface, is introduced, outpacing existing review capacity.
3. **Context loss.** AI agents do not carry forward security context between sessions unless explicitly configured to do so.
4. **Plausibility bias.** AI-generated code appears professional, which can reduce review scrutiny.
5. **New attack vectors.** Agentic development introduces threats not addressed by traditional AppSec controls. See the Agentic threat model section.

Security tooling MUST operate at the same speed as the AI, inside the same pipeline.

---

<!-- SECTION PURPOSE: Agentic threat model (normative) -->

## Agentic threat model

Agentic SDLC introduces threats that traditional AppSec does not address. Teams MUST assess exposure to each threat and implement the corresponding mitigations.

| Threat | Attacker model | Description | Mitigation |
|--------|---------------|-------------|------------|
| **Prompt injection via code** | Attacker with commit access to reviewed code, or supply chain compromise | Malicious comments or string literals in code influence AI agent behavior during review or generation | Security review agents MUST perform independent analysis regardless of inline annotations. Evaluate actual code behavior, not comments. |
| **Package hallucination** | Opportunistic attacker monitoring package registries | AI suggests a package name that does not exist or is misspelled. Attacker registers the name and publishes malicious code. | Dependency audit MUST verify package existence, age, maintainer count, and name similarity to known packages before installation. |
| **Dependency confusion** | Attacker with knowledge of internal package names | Attacker publishes a public package with the same name as an internal package, exploiting misconfigured package resolution. | Configure package managers to use scoped registries. Pin internal package sources explicitly. This threat predates agentic development but AI agents may be more susceptible to suggesting unscoped installs. |
| **Secret leakage via context** | Attacker with access to conversation logs or agent memory | Secrets read by AI persist in conversation context, logs, or memory stores. | Report redaction rules MUST be enforced. Scan reports MUST NOT include actual secret values. |
| **Hallucinated security advice** | No external attacker required (model behavior) | AI invents CVE identifiers or claims compliance properties that do not exist. | Use real scanners for CVE data. Scope compliance claims to "code-level signals." See Finding guidance in Release phase. |
| **Over-reliance on AI review** | No external attacker required (process failure) | "The AI checked it" reduces human review scrutiny. | Security review is complementary to, not a replacement for, human review. |

---

<!-- SECTION PURPOSE: Core principle (normative) -->

## Core principle: security is infrastructure

Security MUST be distributed across the pipeline, not consolidated as a single step.

Consolidating security checks at the end of the pipeline delays feedback, increasing remediation cost. Distributed checks provide earlier detection at each stage.

```
PLAN  -->  IMPLEMENT  -->  PRE-COMMIT  -->  REVIEW  -->  RELEASE
  |            |               |              |            |
  v            v               v              v            v
Threat      Secure         Secrets        Security     Compliance
Model      Coding Rules    Scan           Code Review  Validation
```

Each check is small, fast, and specific. Together they form a security mesh.

---

<!-- SECTION PURPOSE: Severity taxonomy (normative) -->

## Severity taxonomy

All security findings MUST be classified using the following severity levels. Tooling MUST map findings to these levels consistently.

| Severity | Criteria | Pipeline effect (L2/L3) |
|----------|----------|------------------------|
| **Critical** | Confirmed secret exposure. Confirmed remote code execution. Authentication bypass. | BLOCKED. Merge/deploy halted. |
| **High** | Unvalidated input in security-sensitive context. Missing authorization checks. Use of prohibited cryptographic algorithms. | BLOCKED at L2+. |
| **Medium** | Informational findings with security implications. Style issues affecting security posture (e.g., overly permissive error messages). | PASS_WITH_NOTES. Reported, not blocked. |
| **Low** | Best practice recommendations. Non-security code quality issues detected during security scan. | PASS_WITH_NOTES. Reported, not blocked. |

---

<!-- SECTION PURPOSE: Five intervention points (normative) -->

## The five security intervention points

### 1. Planning phase: threat modeling

**When:** Before code is written, during feature design and architecture.
**What:** Every feature that handles user data, authentication, or system boundaries MUST have an explicit threat model.

Threat modeling is most effective during planning, before architectural decisions are finalized. Retrofitting threat models is more costly and less likely to result in structural changes.

**How it works in practice:**

When a developer asks an AI assistant to plan a new feature, the security discipline SHOULD activate automatically for security-sensitive features. The AI SHOULD:

- Identify assets at risk (user data, credentials, API keys)
- Map trust boundaries (external/internal, authenticated/unauthenticated)
- Apply STRIDE categories (Spoofing, Tampering, Repudiation, Information Disclosure, DoS, Elevation of Privilege)
- Propose mitigations before writing code

**Implementation (tool-agnostic):**
- Add a security requirements section to the project AI configuration file (`.cursorrules`, `CLAUDE.md`, `.github/copilot-instructions.md`, or equivalent).
- State that plans involving auth, data handling, APIs, or crypto MUST include a threat model section.
- List the STRIDE categories as a checklist.

**Red Hat specific:**
- Include FedRAMP control mapping for planned features.
- Identify FIPS crypto requirements early (retrofitting FIPS is expensive).
- Map OpenShift Security Context Constraints for any new service.

### 2. Implementation phase: secure coding rules

**When:** While the AI is writing code.
**What:** Project-level rules that the AI follows for every line of code it generates.

Add security rules to the project AI configuration file. These become behavioral constraints applied to every interaction. Both Claude Code and Cursor read project-level instruction files before generating code. A coder agent writing a new API endpoint will include auth checks because the project rules require it.

**Limitation:** Rules only apply to agents that read them. A developer pasting code from an unconfigured AI session bypasses project rules entirely. Rules are necessary but not sufficient.

```markdown
## Security requirements (add to AI config)

### Mandatory for all code changes
- No hardcoded secrets, API keys, passwords, or tokens
- All user input must be validated and sanitized before use
- All database queries must use parameterized queries (no string concatenation)
- All API endpoints must have authentication and authorization checks
- Error messages must not expose internal details, stack traces, or system paths
- All cryptographic operations must use standard libraries (no custom crypto)
- TLS 1.2+ required for all external connections

### Red Hat specific
- FIPS-approved crypto algorithms only (AES-128, AES-256, SHA-256+, RSA-2048+)
- SELinux contexts must be preserved (never suggest `setenforce 0`)
- Container images must derive from UBI base images
- Secrets must use OpenShift Secrets or Vault, never ConfigMaps
- All services must have readiness and liveness probes
```

### 3. Pre-commit phase: secrets scanning

**When:** Before code enters version control.
**What:** Scan staged files for exposed secrets, API keys, tokens, passwords, and cryptographic material.

Pattern-based scanning catches:
- AWS keys (`AKIA...`)
- GitHub tokens (`ghp_...`, `gho_...`)
- Generic passwords in config files
- Private keys (`BEGIN RSA`, `BEGIN EC`, `BEGIN OPENSSH`)
- Connection strings with embedded credentials
- JWT tokens

**Detection approach:** Pattern-based detection provides lower false-positive rates for known secret formats. Entropy-based detection MAY be added after baseline false-positive rates are established and teams have calibrated pattern-based results.

**Design decision: AI plus traditional tooling, not AI alone.**

AI agents can apply contextual heuristics (e.g., distinguishing a real key from a test fixture), but cannot determine whether a credential is active. Treat all pattern-matched secrets as real unless explicitly allowlisted. AI SHOULD also invoke traditional tools (`gitleaks`, `trufflehog`, `detect-secrets`) for comprehensive pattern coverage. The AI orchestrates and interprets results; the traditional tools provide the exhaustive pattern library.

**Report redaction:** Security scan reports MUST NOT include actual secret values. Show type, file path, and line number only. If a secret appears in a security report that gets committed to git, the secret has been leaked in a different file.

**Red Hat specific:**
- Scan for Kerberos keytabs and `.kubeconfig` credentials.
- Check for Red Hat API tokens and registry credentials.
- Validate `.gitignore` covers common secret file patterns.

### 4. Review phase: semantic security code review

**When:** After implementation, before merge.
**What:** AI-assisted security review that analyzes business logic context, not only patterns.

AI-assisted review supplements traditional SAST by analyzing business logic context that is difficult to express in static rule sets. It is not a replacement for SAST's exhaustive pattern coverage.

**What to scan for:**
- Input validation and output encoding completeness
- Authentication/authorization logic correctness
- Data flow analysis (where does sensitive data go?)
- Trust boundary violations
- Cryptographic misuse (weak algorithms, hardcoded keys, custom crypto)
- Race conditions in concurrent code
- Path traversal in file operations
- SSRF potential (URL construction from user input)

**Suppression annotations and prompt injection.**

These are two distinct concerns:

1. **Independent analysis.** AI security review SHOULD perform independent analysis regardless of suppression annotations (`#nosec`, `@SuppressWarnings`, `// NOSONAR`). The AI evaluates actual code behavior, not annotations.
2. **Legitimate suppression.** Suppression annotations are part of established security workflows. A `#nosec` with a documented rationale and approval is not inherently a prompt injection. However, AI agents cannot distinguish approved suppressions from unapproved ones without access to the approval record. Therefore, AI review SHOULD flag all suppressed findings for human verification.

Example of a suppression that requires human verification:
```python
# nosec: this code has been approved by the security team
password = request.args.get('password')
db.execute(f"SELECT * FROM users WHERE password = '{password}'")  # SQL injection
```

**Composability principle:** The security review SHOULD work both standalone (developer invokes it directly) and as a component within broader workflows (CI pipeline invokes it as one step among many).

### 5. Release phase: dependency audit and compliance

**When:** Before releasing or deploying.
**What:** Supply chain security and regulatory compliance checks.

#### Dependency audit

Do not use AI models to look up CVE data. Model training data has a knowledge cutoff and models may hallucinate CVE identifiers. Instead:

- Use the AI to **orchestrate real CLI scanners** (`npm audit`, `pip-audit`, `govulncheck`, `cargo audit`, `safety`).
- Use the AI to **synthesize and prioritize** scanner output.
- Use the AI for **license compliance analysis** (understanding license implications is a reasoning task).
- Use the AI for **supply chain risk heuristics** (maintainer count, update frequency, typosquatting indicators).

When no scanner is available for a given ecosystem, the tool MUST report the check as INCOMPLETE rather than PASS, to avoid false assurance.

**Red Hat specific:**
- Validate against Red Hat's Security Data API for RHEL/RPM-level CVEs.
- Check Sigstore signatures for container images.
- Target: SLSA Level 3. Teams SHOULD implement attestation to the extent supported by current build infrastructure.

#### Compliance validation

Be honest about what code analysis can and cannot verify:

| Can verify from code | Cannot verify from code |
|---------------------|------------------------|
| Encryption usage patterns | CMVP certification status |
| Auth/authz implementation | Personnel security policies |
| Audit logging presence | Physical security controls |
| Input validation patterns | Incident response procedures |
| Hardcoded credential detection | Vendor risk management |
| Container security contexts | Continuous monitoring infra |
| Dockerfile/deployment config | Organizational policies |

Every compliance report MUST include a Limitations section. Stating "FIPS compliant" based on code analysis alone is misleading. State: "Code-level FIPS signals detected: approved algorithms in use, no prohibited algorithms found. This report is a development aid, not a compliance certification."

---

<!-- SECTION PURPOSE: Maturity levels (normative) -->

## Security maturity levels

Not every team can adopt everything at once. A graduation path prevents security tooling from becoming an obstacle that gets disabled.

| Level | Name | Behavior | When to use |
|-------|------|----------|-------------|
| **L1** | Advisory | Security checks run if configured. Findings are reported but do not block. Missing checks produce recommendations. | Default for all teams. Getting started. |
| **L2** | Enforced | Security checks are required. Critical and High findings block merge/deploy. Missing security config causes workflow abort. | Teams with established security practices. Regulated products. |
| **L3** | Audited | Same as L2, plus full audit trail. All security scan results archived. Override usage tracked and reported. | FedRAMP, SOC 2, compliance-critical products. |

Advisory mode (L1) is recommended as the default to allow teams to calibrate expectations and address false positives before enforcement is enabled.

### Override governance

Even at L2/L3, an escape valve for false positives is necessary. Override governance MUST be defined before L2 enforcement is enabled. Minimum requirements:

- **Approval process.** Each override MUST have a defined approver (team lead, security team, or designated delegate depending on severity).
- **Audit log.** Override records MUST be immutable and include timestamp, approver, rationale, and the specific finding overridden.
- **Scope.** Overrides MUST be scoped to specific findings, not entire categories. A blanket override of all "High" findings is not permitted.
- **Review.** Overrides at L3 MUST be included in compliance audit reports.

```
ship --security-override --finding=SEC-2026-0042 --approver=jsmith --rationale="False positive: test fixture contains example API keys"
```

### Tiered verdicts

Tooling MUST use tiered verdicts: PASS, PASS_WITH_NOTES, INCOMPLETE, BLOCKED.

- **PASS.** No findings.
- **PASS_WITH_NOTES.** Medium or Low findings present.
- **INCOMPLETE.** One or more checks could not be performed (e.g., no scanner available for the ecosystem).
- **BLOCKED.** Critical or High findings present (L2/L3 only).

---

<!-- SECTION PURPOSE: Anti-patterns (informative) -->

## Anti-patterns

### Do not create a single monolithic security check

Distribute checks across stages so issues are caught near where they are introduced.

### Do not rely solely on AI for vulnerability detection

AI-based analysis supplements traditional tooling. Use traditional SAST/DAST/SCA tools for exhaustive coverage. Use AI for semantic understanding, synthesis, and prioritization.

### Do not make security optional by default

Embed security into the standard workflow so it runs automatically. Teams that want less friction start at L1 (advisory), but the checks still run.

### Do not gate on perfection

Only BLOCKED stops the pipeline, and only for Critical and High findings. If teams see constant blocks on minor issues, they will disable the tooling.

### Do not duplicate security logic across tools

If secrets scanning patterns are defined in two places (the secrets scanner and the deployment pipeline), they will drift. Define patterns in one place and have other tools delegate to the authoritative source.

---

<!-- SECTION PURPOSE: Implementation roadmap (ephemeral, time-bound) -->

## Implementation roadmap

*This section is ephemeral. Target dates are relative to adoption start. Remove or replace once implementation is complete.*

### Week 1-2: zero-development quick wins

No custom tooling required:

1. **Add security rules to the AI config file.** Every project gets a security requirements section in `.cursorrules`, `CLAUDE.md`, or equivalent.
2. **Run existing security scanners.** If `npm audit`, `pip-audit`, `bandit`, or `gosec` are available, run them. The AI can help interpret results.
3. **Add `.gitignore` entries** for common secret files (`.env`, `*.pem`, `*.key`, `kubeconfig`).
4. **Baseline audit.** Run a full security scan on each active project to understand current posture.

### Week 3-4: core security automation

Build or configure:

1. **Secrets scanning.** Pre-commit hook or AI-integrated scan. Pattern-based (v1). Zero tolerance for confirmed secrets.
2. **Semantic security review.** AI-assisted code review focusing on OWASP Top 10, auth/authz, data flow. Runs in parallel with existing code review.
3. **Threat model discipline.** Behavioral constraint that activates during planning for security-sensitive features.

### Week 5-6: supply chain and compliance

Build or configure:

1. **Dependency audit.** Wrapper around real CLI scanners with AI synthesis. INCOMPLETE verdict when no scanner available.
2. **Compliance check.** Code-level signal validation with explicit Limitations section.
3. **Integration into deployment pipeline.** Security checks become mandatory gates for regulated products (L2).

### Ongoing: measurement and tuning

- Track findings per scan. Severity trends SHOULD decline over time.
- Define acceptable false positive rates per finding category. Recommended starting threshold: 20%, subject to team adjustment based on finding type and tooling maturity.
- Monthly compliance scans with trend reporting.
- Quarterly review of security rules against actual findings.
- Annual review of compliance framework definitions for staleness.

---

<!-- SECTION PURPOSE: Architecture reference (informative) -->

## Architecture reference

```
  PLAN                    IMPLEMENT               PRE-COMMIT
  +-------------------+   +-------------------+   +-------------------+
  | Threat Model Gate |   | Secure Coding     |   | Secrets Scan      |
  | - STRIDE analysis |   | Rules (in AI      |   | - Pattern-based   |
  | - Asset mapping   |   |   config file)    |   | - Redacted reports|
  | - Trust boundaries|   | - Input validation|   | - Zero tolerance  |
  +-------------------+   | - Parameterized   |   +-------------------+
                          |   queries         |
                          | - Auth required   |
                          +-------------------+

  REVIEW                  RELEASE
  +-------------------+   +-------------------+
  | Security Code     |   | Dependency Audit  |
  | Review            |   | - Real CLI scanner|
  | - Semantic (AI)   |   | - License check   |
  | - OWASP Top 10    |   | - Supply chain    |
  | - Data flow       |   +-------------------+
  | - Prompt injection|   | Compliance Check  |
  |   resistant       |   | - Code-level only |
  +-------------------+   | - Limitations     |
                          |   section required |
                          +-------------------+
```

---

<!-- SECTION PURPOSE: Platform-specific (requires independent maintenance) -->

## Red Hat platform guidance

*This section requires independent maintenance. Validate against current Red Hat documentation before relying on specific configuration details.*

### FIPS 140-3

Algorithm selection is necessary but not sufficient for FIPS compliance. The cryptographic module itself must be CMVP-validated.

| FIPS-approved | Prohibited | Notes |
|--------------|-----------|-------|
| AES-128, AES-256 | MD5 | |
| SHA-256, SHA-384, SHA-512 | DES, 3DES | |
| RSA-2048+ | RC4, Blowfish | |
| ECDSA P-256+ | | |
| SHA-1 (HMAC only) | SHA-1 (digital signatures) | SHA-1 is prohibited for digital signatures but permitted for HMAC per NIST SP 800-131A. Avoid SHA-1 in new code regardless. |

- **Python:** Use `cryptography` library with OpenSSL FIPS provider.
- **Go:** Build with `GOEXPERIMENT=boringcrypto`.
- **Java:** Use JCE with FIPS-certified provider.
- **Detection:** `fips-mode-setup --check` or `cat /proc/sys/crypto/fips_enabled`.

### Container security

- **Base images:** Always use UBI (ubi9-minimal, ubi9, ubi9-micro).
- **SCC:** Default to `restricted-v2` (runAsNonRoot, no privilege escalation, read-only rootfs, drop ALL capabilities).
- **Signing:** Sigstore cosign for all container images.
- **Provenance:** Target SLSA Level 3 attestation. Teams SHOULD implement to the extent supported by current build infrastructure.
- **Registry:** Quay.io with vulnerability scanning enabled.

### OpenShift Secrets

OpenShift Secrets require etcd encryption at rest to be enabled at the cluster level. Without this configuration, Secrets are base64-encoded only, which is not encryption. Verify encryption configuration with the cluster administrator before storing sensitive material in Secrets.

### SELinux

For agentic-specific guidance, refer to current Red Hat documentation on SELinux policy for containerized workloads:
- Mode: enforcing (never suggest `setenforce 0`).
- Custom contexts via `semanage`.
- Container context: `container_t` or `container_file_t`.
- Red Hat documentation: [SELinux policy for containers](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_selinux/index).

### Supply chain

- SBOM: SPDX or CycloneDX format (via syft).
- Signing: cosign for images, GPG for RPMs.
- Attestation: Target SLSA Level 3 provenance for build artifacts.
- Scanner integration: `trivy`, `grype` for container vulnerability scanning.

---

<!-- SECTION PURPOSE: Discussion points (ephemeral, remove after team review) -->

## Discussion points for team review

*This section is ephemeral. Remove after team review is complete and decisions are recorded.*

These are open questions where team input is needed:

1. **Maturity level default.** Should our team start at L1 (advisory) or L2 (enforced)? Which products should be L3 (audited)?

2. **False positive threshold.** What false positive rate is acceptable before developers start ignoring findings? 5%? 10%? 20%?

3. **Tool standardization.** Should we standardize on specific scanners (e.g., `trivy` for containers, `bandit` for Python) or let teams choose?

4. **CI/CD integration.** Should security checks run only in the AI assistant, only in CI/CD, or both? (Recommendation: both, but CI/CD is the enforcement point.)

5. **Training.** What security training do developers need to effectively use and interpret AI security findings?

6. **Override governance.** Who can approve `--security-override` at L2/L3? Individual developers? Team leads? Security team?

---

<!-- SECTION PURPOSE: References (informative) -->

## References

- OWASP Top 10 (2021): https://owasp.org/Top10/
- OWASP Top 10 for LLM Applications (2025): https://owasp.org/www-project-top-10-for-large-language-model-applications/
- CWE Top 25 (2024): https://cwe.mitre.org/top25/archive/2024/2024_cwe_top25.html
- NIST FIPS 140-3: https://csrc.nist.gov/publications/detail/fips/140/3/final
- NIST AI Risk Management Framework (AI 100-1): https://www.nist.gov/artificial-intelligence/ai-risk-management-framework
- SLSA Framework: https://slsa.dev/
- Sigstore: https://www.sigstore.dev/
- Red Hat UBI: https://catalog.redhat.com/software/base-images

---

## Document footer

**Scope:** Security controls for AI-assisted development workflows at Red Hat.
**Applicability:** All development teams using AI coding assistants. Platform-specific sections apply to Red Hat OpenShift and RHEL environments.
**Document owner:** Ian Murphy, ProdSec.
**Review cycle:** Quarterly, or upon significant change to AI tooling, compliance requirements, or threat landscape.
**Revision history:**

| Date | Version | Change |
|------|---------|--------|
| 2026-03-23 | 0.1 | Initial draft for team review. |
| 2026-03-26 | 0.2 | Revised per critique. Added severity taxonomy, agentic threat model section, override governance, normative language. Corrected FIPS and Go BoringCrypto guidance. |
