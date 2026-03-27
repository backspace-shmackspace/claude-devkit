---
name: threat-model-gate
description: Use when planning security-sensitive features — authentication, authorization, data handling, API design, cryptography, or network configuration — requires explicit threat modeling before implementation decisions are made
version: 1.0.0
type: reference
attribution: Original work, claude-devkit project
model: claude-sonnet-4-6
---

# Threat Model Gate

## Overview

Security cannot be added later. Features that touch user data, system boundaries, or trust relationships require threat modeling during planning — not after code is written.

## Core Principle

**Every feature that handles user data, authentication, or system boundaries requires explicit threat modeling before implementation.**

"We'll secure it in the next sprint" is a commitment that never gets honored. The cost of retrofitting security is 10x the cost of designing it in. Threat modeling during planning is the minimum viable security practice.

## When to Activate

Apply this gate when planning involves any of the following:

**Authentication and Identity**
- Login flows, session management, token issuance or validation
- Multi-factor authentication, SSO, OAuth, OIDC, SAML
- Password storage, credential management, account recovery

**Authorization and Access Control**
- Role-based or attribute-based access control (RBAC, ABAC)
- Resource ownership and sharing models
- Admin capabilities, privilege escalation paths
- API key or service account permissions

**Data Handling**
- PII collection, storage, or transmission
- Payment card data, health records, or regulated data categories
- Encryption at rest or in transit
- Data retention, deletion, or export features

**API Design**
- Public-facing endpoints, webhooks, or callbacks
- Inter-service communication with trust implications
- Rate limiting and abuse prevention
- Input validation and output encoding boundaries

**Cryptography**
- Key generation, storage, or rotation
- Algorithm selection (hashing, signing, encryption)
- Certificate management, mTLS
- Secure random number generation

**Network and Infrastructure**
- Firewall rules, network segmentation, VPN configurations
- Load balancer, reverse proxy, or CDN configurations
- Container networking, service mesh, Kubernetes network policies
- DNS, TLS termination, certificate pinning

## The Threat Modeling Checklist

Work through these four areas before committing to an implementation approach:

### 1. Assets

Identify what is worth protecting:

```
ASSETS TO IDENTIFY:
- What data does this feature create, read, update, or delete?
- What is the confidentiality classification? (public / internal / confidential / restricted)
- What is the integrity requirement? (can corruption be tolerated? for how long?)
- What is the availability requirement? (what is the acceptable downtime?)
- What are the downstream systems or users that depend on this data?
```

### 2. Trust Boundaries

Map where trust changes:

```
BOUNDARIES TO IDENTIFY:
- Where does data cross from an untrusted zone to a trusted zone?
- Which actors (users, services, admins) receive which level of trust?
- Where are authentication and authorization enforced?
- What can an unauthenticated caller reach?
- What can an authenticated-but-unauthorized caller reach?
- Where does input become data (the injection boundary)?
```

### 3. Threats (STRIDE Analysis)

Apply STRIDE to each asset and boundary (see STRIDE Quick Reference below):

```
FOR EACH BOUNDARY OR ASSET:
- S: How could an attacker impersonate a legitimate actor?
- T: How could an attacker modify data in transit or at rest?
- R: How could an actor deny having performed an action?
- I: How could an attacker read data they should not see?
- D: How could an attacker make the feature unavailable?
- E: How could an attacker gain more privilege than intended?
```

### 4. Mitigations

For each threat identified, specify the control:

```
MITIGATIONS TO SPECIFY:
- Authentication controls (how is identity verified?)
- Authorization controls (how is permission verified?)
- Input validation (what are the trust boundaries for input?)
- Encryption (what is encrypted, with which algorithm, where?)
- Audit logging (what events are logged, where, for how long?)
- Rate limiting (what abuse scenarios does this prevent?)
- Failure mode (what happens when the control fails?)
```

## STRIDE Quick Reference

| Letter | Threat | What It Targets | Example Mitigation |
|--------|--------|-----------------|-------------------|
| **S** — Spoofing | Impersonating an identity | Authentication | Strong authentication, signed tokens, certificate pinning |
| **T** — Tampering | Modifying data without authorization | Integrity | Digital signatures, HMAC, TLS, input validation |
| **R** — Repudiation | Denying an action was performed | Non-repudiation | Audit logs, signed transactions, tamper-evident logs |
| **I** — Information Disclosure | Exposing data to unauthorized parties | Confidentiality | Encryption at rest/transit, authorization checks, data minimization |
| **D** — Denial of Service | Making a resource unavailable | Availability | Rate limiting, circuit breakers, resource quotas, graceful degradation |
| **E** — Elevation of Privilege | Gaining unauthorized capabilities | Authorization | Least privilege, role enforcement, capability checks, input sanitization |

**STRIDE is a starting point, not a complete threat model.** Use it to ensure you have covered all six threat categories, then go deeper on the categories most relevant to the feature.

## Security Requirements Template for Plans

Every plan for a security-sensitive feature must include a `## Security Requirements` section:

```markdown
## Security Requirements

### Assets
- **[Asset Name]:** [Confidentiality: public/internal/confidential/restricted] | [Integrity: high/medium/low] | [Availability: high/medium/low]

### Trust Boundaries
- **Boundary:** [Description — e.g., "public internet to application server"]
  - **Authentication:** [How identity is established]
  - **Authorization:** [How permission is verified]

### STRIDE Analysis
| Threat | Vector | Mitigation | Residual Risk |
|--------|--------|-----------|---------------|
| Spoofing | [How an attacker could spoof] | [Control] | [low/medium/high] |
| Tampering | [How data could be tampered with] | [Control] | [low/medium/high] |
| Repudiation | [What actions could be denied] | [Control] | [low/medium/high] |
| Information Disclosure | [What data could be exposed] | [Control] | [low/medium/high] |
| Denial of Service | [What could be exhausted or crashed] | [Control] | [low/medium/high] |
| Elevation of Privilege | [How privilege could be escalated] | [Control] | [low/medium/high] |

### Security Controls
- **Input Validation:** [What is validated, where, and how]
- **Encryption:** [At rest: algorithm. In transit: TLS version, cipher suites]
- **Audit Logging:** [What events are logged, retention period, tamper protection]
- **Rate Limiting:** [Limits, scope, response on breach]
- **Secrets Management:** [Where credentials are stored, how rotated]

### Failure Modes
- **If authentication fails:** [Behavior — e.g., "return 401, log attempt, no information leakage"]
- **If authorization fails:** [Behavior — e.g., "return 403, log with user ID and resource"]
- **If encryption fails:** [Behavior — e.g., "abort operation, do not fall back to plaintext"]
```

## Anti-Patterns

When you notice these in a plan, stop and apply threat modeling before proceeding:

**"Security will be added later"**
```
WRONG: "We'll add authentication in v2."
RIGHT: Define the authentication model now. Implementation can be phased; the design cannot.
```

**Implicit trust of internal services**
```
WRONG: "It's only called by our internal API, so we don't need auth."
RIGHT: Internal services are compromised too. Define what trust means and how it is enforced.
```

**Encryption as an afterthought**
```
WRONG: "We'll encrypt the database later when we have time."
RIGHT: Define encryption at rest requirements now. Schema changes after launch are expensive.
```

**Authorization by obscurity**
```
WRONG: "Users won't know the endpoint exists."
RIGHT: Assume all endpoints are discoverable. Enforce authorization explicitly.
```

**Logging as a security control**
```
WRONG: "We'll know if something bad happens because we log everything."
RIGHT: Logging is detection and response, not prevention. Identify the preventive controls.
```

**"We trust our users"**
```
WRONG: "Our users are internal employees, they wouldn't abuse this."
RIGHT: Insider threat is real. Least privilege applies to employees too. Define what each role can do.
```

**Deferring the threat model to the security team**
```
WRONG: "Security will review this before it ships."
RIGHT: The security team reviews your threat model. You write the threat model. Start now.
```

**Sharing secrets in plans or commits**
```
WRONG: Including actual API keys, connection strings, or credentials in plan documents or code.
RIGHT: Reference secrets by name only. Actual values belong in secrets managers, not in plans.
```

## How to Apply During Planning

When drafting or reviewing a plan for a security-sensitive feature:

1. **Identify the security scope.** Does this plan touch any of the activation categories listed above? If yes, the threat model gate is active.

2. **Audit the plan for Security Requirements.** Is there a `## Security Requirements` section with assets, trust boundaries, STRIDE analysis, and security controls documented? If not, the plan is incomplete.

3. **Apply STRIDE.** Walk through each threat category for each identified asset and boundary. If any category has no entry, ask: "Have we genuinely considered this, or have we overlooked it?"

4. **Verify mitigations are specific.** "We'll use standard security practices" is not a mitigation. "Passwords hashed with bcrypt (cost factor 12), stored in the `users` table `password_hash` column, never logged" is a mitigation.

5. **Check failure modes.** What does the feature do when a security control fails? Graceful failure is part of the design.

6. **Flag anti-patterns.** If the plan contains any of the anti-patterns above, surface them explicitly before the plan is approved.

## Relationship to Other Skills

- **Before `/architect` approval:** The threat model gate runs during planning. Plans without a `## Security Requirements` section for security-sensitive features should not receive architect approval.
- **Before `/ship` implementation:** If a plan passed `/architect` but the Security Requirements section is missing or shallow, raise it before implementation begins. It is cheaper to fix the design than the code.
- **After `/secure-review`:** If `/secure-review` finds issues that the threat model should have caught, update the threat model section of the plan and the `.claude/learnings.md` file. Threat model gaps are learning opportunities.
- **In conjunction with `receiving-code-review`:** When reviewing security-related code, apply both skills. `receiving-code-review` governs how you evaluate the reviewer's feedback; `threat-model-gate` governs whether the implementation addresses the correct threats.

## The Bottom Line

**Security is a design constraint, not a feature.** It cannot be sprinted in after the architecture is set.

Threat modeling during planning takes 30 minutes. Retrofitting security after launch takes months and may require breaking API changes, data migrations, or architectural rewrites.

Model the threats. Document the controls. Then build.
