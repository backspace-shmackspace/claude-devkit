---
name: report-template
description: >
  Complete markdown report template for threat model output. Defines
  all sections, table structures, and placeholder fields. Loaded on
  demand during Phase 3 synthesis.
---

# Threat Model: {PROJECT_NAME}

> CONFIDENTIAL -- This document contains security-sensitive information
> about system vulnerabilities. Handle according to your organization's
> data classification policy.

## Metadata

- **Date:** {DATE}
- **Version:** {VERSION}
- **Author:** {AUTHOR}
- **Scope:** {SCOPE_DESCRIPTION}
- **Methodology:** STRIDE + DREAD
- **Skill Version:** threat-model v1.0.0

## Executive Summary

{EXECUTIVE_SUMMARY: 1-3 sentences describing overall risk posture, highest-severity threats, and key recommendations.}

| Severity | Count |
|----------|-------|
| CRITICAL | {CRITICAL_COUNT} |
| HIGH     | {HIGH_COUNT} |
| MEDIUM   | {MEDIUM_COUNT} |
| LOW      | {LOW_COUNT} |

## System Description

{SYSTEM_DESCRIPTION: Brief architectural overview of the system being modeled. Include deployment model, primary technology stack, and user-facing surface area.}

## Trust Zones

| Zone ID | Name | Trust Level | Description |
|---------|------|-------------|-------------|
| TZ-001 | {ZONE_NAME} | {TRUST_LEVEL} | {ZONE_DESCRIPTION} |

Trust levels: Public (untrusted), DMZ (partially trusted), Internal
(trusted), Administrative (highly trusted), Data Storage (restricted).

Add or remove rows as needed. Every component must belong to exactly one
trust zone.

## Components

| Component ID | Name | Type | Trust Zone | Technology |
|--------------|------|------|------------|------------|
| C-001 | {COMPONENT_NAME} | {COMPONENT_TYPE} | TZ-{N} | {TECHNOLOGY} |

Component types: Web Application, API Service, Database, Cache, Message
Queue, Background Worker, External API, Load Balancer, Identity Provider,
File Storage, CDN, Client Application.

Add or remove rows as needed. Every component referenced in Data Flows or
Threat Register must appear in this table.

## Data Flows

| Flow ID | Source | Destination | Data | Protocol | Sensitivity |
|---------|--------|-------------|------|----------|-------------|
| DF-001 | C-{N} | C-{N} | {DATA_DESCRIPTION} | {PROTOCOL} | {CLASSIFICATION} |

Sensitivity classifications: Public, Internal, Confidential, Restricted.

Protocols: HTTPS, gRPC, TCP, TLS, AMQP, JDBC, WebSocket, SSH, SMTP, or
as appropriate.

Add or remove rows as needed. Every data flow referenced in the Threat
Register must appear in this table.

## Assets

| Asset ID | Name | Classification | CIA Requirements |
|----------|------|----------------|------------------|
| A-001 | {ASSET_NAME} | {CLASSIFICATION} | C:{H/M/L} I:{H/M/L} A:{H/M/L} |

Classifications: Public, Internal, Confidential, Restricted.

CIA ratings: H (High), M (Medium), L (Low). Rate each of Confidentiality,
Integrity, and Availability independently based on the asset's value and
the impact of compromise.

Add or remove rows as needed.

## Trust Boundaries

| Boundary ID | From Zone | To Zone | Crossing Components | Data Flows |
|-------------|-----------|---------|---------------------|------------|
| TB-001 | TZ-{N} | TZ-{N} | C-{N}, C-{N} | DF-{N} |

Every trust boundary is a crossing between two trust zones. List the
components on each side and the data flows that cross the boundary.
STRIDE analysis in the Threat Register is organized around these
boundaries.

Add or remove rows as needed. Every boundary referenced in the Threat
Register must appear in this table.

## Threat Register

Threats are grouped by severity (CRITICAL, HIGH, MEDIUM, LOW) and listed
in descending order of DREAD average score within each group.

Severity bands:
- **CRITICAL:** DREAD average >= 8.0
- **HIGH:** DREAD average >= 6.0 and < 8.0
- **MEDIUM:** DREAD average >= 4.0 and < 6.0
- **LOW:** DREAD average < 4.0

When a DREAD average falls within 0.5 of a severity boundary (e.g.,
5.5-6.4 near the HIGH/MEDIUM boundary), apply calibration: if Damage
Potential >= 7, round UP; if Damage Potential <= 3, round DOWN; otherwise
retain the computed band.

### CRITICAL Threats

#### TM-{NNN}: {THREAT_TITLE}

- **STRIDE Category:** {Spoofing / Tampering / Repudiation / Information Disclosure / Denial of Service / Elevation of Privilege}
- **Affected Components:** {C-NNN, C-NNN}
- **Affected Data Flows:** {DF-NNN}
- **Trust Boundary:** {TB-NNN}
- **DREAD Score:** DamagePotential:{N} Reproducibility:{N} Exploitability:{N} AffectedUsers:{N} Discoverability:{N} = **{DREAD_AVERAGE}**
- **Severity Calibration:** {Note calibration decision if the score is within 0.5 of a severity boundary; otherwise state "N/A -- not near a boundary"}
- **ATT&CK:** {TNNNN (Technique Name)} *(if applicable; omit line if no ATT&CK mapping)*
- **Scenario:** {Concrete attack scenario describing how the threat could be realized}
- **Existing Mitigations:** {None / description of controls already in place}
- **Proposed Mitigations:** {Specific controls to address this threat}

Repeat the threat entry block above for each CRITICAL threat. If there
are no CRITICAL threats, state: "No CRITICAL threats identified."

### HIGH Threats

#### TM-{NNN}: {THREAT_TITLE}

- **STRIDE Category:** {Spoofing / Tampering / Repudiation / Information Disclosure / Denial of Service / Elevation of Privilege}
- **Affected Components:** {C-NNN, C-NNN}
- **Affected Data Flows:** {DF-NNN}
- **Trust Boundary:** {TB-NNN}
- **DREAD Score:** DamagePotential:{N} Reproducibility:{N} Exploitability:{N} AffectedUsers:{N} Discoverability:{N} = **{DREAD_AVERAGE}**
- **Severity Calibration:** {Note calibration decision if the score is within 0.5 of a severity boundary; otherwise state "N/A -- not near a boundary"}
- **ATT&CK:** {TNNNN (Technique Name)} *(if applicable; omit line if no ATT&CK mapping)*
- **Scenario:** {Concrete attack scenario describing how the threat could be realized}
- **Existing Mitigations:** {None / description of controls already in place}
- **Proposed Mitigations:** {Specific controls to address this threat}

Repeat the threat entry block above for each HIGH threat. If there are
no HIGH threats, state: "No HIGH threats identified."

### MEDIUM Threats

#### TM-{NNN}: {THREAT_TITLE}

- **STRIDE Category:** {Spoofing / Tampering / Repudiation / Information Disclosure / Denial of Service / Elevation of Privilege}
- **Affected Components:** {C-NNN, C-NNN}
- **Affected Data Flows:** {DF-NNN}
- **Trust Boundary:** {TB-NNN}
- **DREAD Score:** DamagePotential:{N} Reproducibility:{N} Exploitability:{N} AffectedUsers:{N} Discoverability:{N} = **{DREAD_AVERAGE}**
- **Severity Calibration:** {Note calibration decision if the score is within 0.5 of a severity boundary; otherwise state "N/A -- not near a boundary"}
- **ATT&CK:** {TNNNN (Technique Name)} *(if applicable; omit line if no ATT&CK mapping)*
- **Scenario:** {Concrete attack scenario describing how the threat could be realized}
- **Existing Mitigations:** {None / description of controls already in place}
- **Proposed Mitigations:** {Specific controls to address this threat}

Repeat the threat entry block above for each MEDIUM threat. If there are
no MEDIUM threats, state: "No MEDIUM threats identified."

### LOW Threats

#### TM-{NNN}: {THREAT_TITLE}

- **STRIDE Category:** {Spoofing / Tampering / Repudiation / Information Disclosure / Denial of Service / Elevation of Privilege}
- **Affected Components:** {C-NNN, C-NNN}
- **Affected Data Flows:** {DF-NNN}
- **Trust Boundary:** {TB-NNN}
- **DREAD Score:** DamagePotential:{N} Reproducibility:{N} Exploitability:{N} AffectedUsers:{N} Discoverability:{N} = **{DREAD_AVERAGE}**
- **Severity Calibration:** {Note calibration decision if the score is within 0.5 of a severity boundary; otherwise state "N/A -- not near a boundary"}
- **ATT&CK:** {TNNNN (Technique Name)} *(if applicable; omit line if no ATT&CK mapping)*
- **Scenario:** {Concrete attack scenario describing how the threat could be realized}
- **Existing Mitigations:** {None / description of controls already in place}
- **Proposed Mitigations:** {Specific controls to address this threat}

Repeat the threat entry block above for each LOW threat. If there are
no LOW threats, state: "No LOW threats identified."

## Cross-Cutting Concerns

{CROSS_CUTTING_CONCERNS: Threats or patterns that span multiple subsystems or trust boundaries. Examples include: shared credential management weaknesses, inconsistent logging across services, missing TLS enforcement on internal links, or common dependency vulnerabilities affecting multiple components.}

List each cross-cutting concern with the affected components, data flows,
and related threat IDs:

- **{CONCERN_TITLE}:** {Description of the cross-cutting pattern.}
  Affected: {C-NNN, C-NNN}. Related threats: {TM-NNN, TM-NNN}.

Repeat for each cross-cutting concern. If none are identified, state:
"No cross-cutting concerns identified."

## Mitigation Roadmap

### Immediate (before release)

- [ ] {MITIGATION_DESCRIPTION} (addresses TM-{NNN})
- [ ] {MITIGATION_DESCRIPTION} (addresses TM-{NNN})

### Short-Term (next sprint/cycle)

- [ ] {MITIGATION_DESCRIPTION} (addresses TM-{NNN})
- [ ] {MITIGATION_DESCRIPTION} (addresses TM-{NNN})

### Long-Term (backlog)

- [ ] {MITIGATION_DESCRIPTION} (addresses TM-{NNN})
- [ ] {MITIGATION_DESCRIPTION} (addresses TM-{NNN})

Add or remove items in each bucket as needed. Every CRITICAL and HIGH
threat must have at least one corresponding mitigation item. MEDIUM and
LOW threats should have mitigation items where practical.

## Assumptions and Limitations

- {ASSUMPTION_OR_LIMITATION}
- {ASSUMPTION_OR_LIMITATION}

Document all assumptions made during the analysis and any known
limitations of this threat model. Examples:

- Assumptions about the deployment environment (e.g., "Assumes
  deployment on a private Kubernetes cluster with network policies
  enforced").
- Scope exclusions (e.g., "Physical security of data centers is out of
  scope").
- Information gaps (e.g., "Third-party API security posture was not
  assessed; threat analysis assumes the API enforces authentication but
  this was not verified").
- Confidence limitations (e.g., "DREAD scores for threats TM-005 through
  TM-008 are estimates based on documentation review; scores may change
  after code-level analysis").

For incremental threat models, also document:
- Which components, boundaries, or data flows were carried forward
  without re-analysis.
- Which threats were added, modified, or retired in this version.

## Regulatory Considerations

Threat models may be subject to organizational data classification,
retention, export control, or legal privilege requirements. Consult
your organization's security and legal teams for handling guidance
specific to your jurisdiction and industry.

{REGULATORY_NOTES: If specific regulatory frameworks apply to this system (e.g., GDPR, HIPAA, PCI DSS, FedRAMP, SOC 2), note them here with any threat model handling requirements they impose. If none are known, state "No specific regulatory frameworks identified. Consult your organization's compliance team."}

## Appendices

### A. DREAD Scoring Reference

DREAD is a risk rating system that scores threats across five dimensions,
each rated 0-10. The DREAD average determines severity classification.

**Formula:**

```
DREAD Average = (DamagePotential + Reproducibility + Exploitability + AffectedUsers + Discoverability) / 5
```

**Dimensions:**

| Dimension | What It Measures |
|-----------|-----------------|
| DamagePotential | How severe is the damage if the threat is realized? |
| Reproducibility | How reliably can the attack be reproduced? |
| Exploitability | How much effort, skill, or access is required to exploit? |
| AffectedUsers | What proportion of users or tenants are impacted? |
| Discoverability | How easy is it for an attacker to find this vulnerability? |

**Severity bands:**

| Severity | DREAD Average |
|----------|---------------|
| CRITICAL | >= 8.0 |
| HIGH     | >= 6.0 and < 8.0 |
| MEDIUM   | >= 4.0 and < 6.0 |
| LOW      | < 4.0 |

**Calibration:** When a score falls within 0.5 of a severity boundary
(e.g., 5.5-6.4 near the HIGH/MEDIUM boundary), re-examine Damage
Potential. If DamagePotential >= 7, round UP to the higher severity.
If DamagePotential <= 3, round DOWN. Otherwise, retain the computed
band.

**Historical note:** DREAD was deprecated by Microsoft in 2008 in favor
of CVSS-based approaches. This skill retains DREAD because it is better
suited to threat modeling (CVSS scores vulnerabilities, not threats) and
because its simplicity is practical for structured analysis. Organizations
using CVSS-based risk frameworks should map DREAD outputs to their
internal scale.

### B. STRIDE Category Reference

STRIDE is a threat categorization framework. Each letter represents a
category of threat.

| Category | Description | Violated Property | Example |
|----------|-------------|-------------------|---------|
| **S**poofing | Impersonating a user, system, or component | Authentication | Forged authentication token accepted by API |
| **T**ampering | Unauthorized modification of data or code | Integrity | SQL injection modifying database records |
| **R**epudiation | Denying having performed an action | Non-repudiation | User action not logged; cannot prove who made a change |
| **I**nformation Disclosure | Exposing data to unauthorized parties | Confidentiality | Error message leaks internal stack trace and database schema |
| **D**enial of Service | Disrupting availability of the system | Availability | Unbounded query causes database timeout for all users |
| **E**levation of Privilege | Gaining unauthorized access or permissions | Authorization | Regular user accesses admin API endpoint due to missing role check |

### C. OTM JSON Output

The companion OTM (Open Threat Model) v0.2.0 JSON document for this
threat model is maintained alongside this report. Refer to the OTM JSON
file for machine-readable representation of the threat model suitable
for toolchain integration.

If the OTM JSON was generated as part of this threat model, reference
its location:

- **OTM JSON file:** {OTM_FILE_PATH_OR_INLINE}

For OTM schema details and the DREAD-to-OTM risk rating mapping, see
`reference/otm-schema.md` in the threat-model skill.
