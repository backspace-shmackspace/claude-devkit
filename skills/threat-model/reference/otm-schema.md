---
name: otm-schema
description: >
  OTM v0.2.0 JSON schema reference with element type documentation,
  field constraints, example fragments, and DREAD-to-OTM risk rating
  mapping. Loaded on demand during Phase 3 synthesis.
---

# Open Threat Model (OTM) v0.2.0 Schema Reference

## Overview

The Open Threat Model (OTM) is a machine-readable JSON format for
representing threat models. It provides a standardized structure for
describing system components, trust zones, data flows, threats, and
mitigations in a way that is interoperable across threat modeling tools.

- **Specification repository:**
  <https://github.com/iriusrisk/OpenThreatModel>
- **Version:** 0.2.0

### License and Attribution

The OTM specification is created and maintained by
[IriusRisk](https://www.iriusrisk.com/) and is licensed under the
**Creative Commons Attribution-ShareAlike 4.0 International License
(CC-BY-SA-4.0)**.

This reference file describes the OTM structure using original example
fragments and independent descriptions rather than reproducing verbatim
specification text. Attribution to IriusRisk as the creator of OTM is
required under the CC-BY-SA-4.0 license terms.

Full license text: <https://creativecommons.org/licenses/by-sa/4.0/>

### Schema Provenance

The following provenance data records the source material used to create
this reference. Use it to detect drift if the upstream specification is
updated.

| Property | Value |
|----------|-------|
| Schema version | `0.2.0` |
| Source repository | `https://github.com/iriusrisk/OpenThreatModel` |
| Source tag | `0.2.0` (commit `6bcb2abe0ef8f992c1fbb18843bb66f659959e4b`) |
| Retrieval date | 2026-06-20 |
| SHA256 of `otm_schema.json` at tag | `bf3a9703787b942ca81d08dd7e4288c4b6396258e8e117b181009c4e0c25b18a` |

**Maintenance note:** To check for updates, compare the SHA256 above
against the current `otm_schema.json` in the source repository. If the
hash differs, review the changes and update this reference file
accordingly.

**Maintenance status:** OTM v0.2.0 was released August 2023 with no
subsequent releases as of this writing. The spec should be treated as a
structural convention given the maintainer community's low activity
level.

---

## Top-Level Structure

An OTM document is a JSON object with 9 top-level properties: 2
required and 7 optional domain element arrays.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `otmVersion` | string | Yes | Schema version identifier. Must be `"0.2.0"`. |
| `project` | object | Yes | Metadata about the project being modeled. |
| `representations` | array or null | No | Diagrams, architectural views, or other visual representations. |
| `assets` | array or null | No | Valuable data and resources that require protection. |
| `trustZones` | array | No | Security boundary definitions (trust levels). |
| `components` | array or null | No | System building blocks (services, databases, clients). |
| `dataflows` | array | No | Data movement between components. |
| `threats` | array or null | No | Identified threats with risk ratings. |
| `mitigations` | array or null | No | Proposed or existing security controls. |

Every OTM JSON document produced by this skill must include at minimum:

```json
{
  "otmVersion": "0.2.0",
  "project": {
    "name": "...",
    "id": "..."
  }
}
```

---

## Element Type Reference

### project (required)

Contains metadata identifying the system under analysis.

**Required fields:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Human-readable project name. |
| `id` | string | Unique identifier for this threat model instance. |

**Optional fields:**

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Summary of the system being modeled. |
| `owner` | string | Person or team responsible for the project. |
| `ownerContact` | string | Contact information for the owner. |
| `tags` | array of strings | Classification labels. |
| `attributes` | object | Arbitrary key-value metadata. |

**Example:**

```json
{
  "otmVersion": "0.2.0",
  "project": {
    "name": "Order Processing API",
    "id": "order-api-tm-2026",
    "description": "REST API for processing customer orders with payment integration",
    "owner": "Platform Engineering",
    "ownerContact": "platform-eng@example.com",
    "tags": ["api", "payments", "pii"],
    "attributes": {
      "methodology": "STRIDE+DREAD",
      "modelVersion": "1.0"
    }
  }
}
```

### representations

Diagrams or architectural views that support the threat model.

**Required fields:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Descriptive name for this representation. |
| `id` | string | Unique identifier. |
| `type` | string | Kind of representation (e.g., `"diagram"`, `"code"`, `"threat-model"`). |

**Optional fields:**

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | What this representation shows. |
| `size` | object | Dimensions (contains `width` and `height` numbers). |
| `repository` | object | Source location (contains `url` string). |
| `attributes` | object | Arbitrary key-value metadata. |

**Example:**

```json
{
  "id": "rep-arch-overview",
  "name": "System Architecture Diagram",
  "type": "diagram",
  "description": "High-level component layout showing trust boundaries",
  "repository": {
    "url": "https://wiki.example.com/arch/order-api-diagram.png"
  }
}
```

### assets

Valuable data and resources that the system must protect.

**Required fields:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Name of the asset. |
| `id` | string | Unique identifier. |
| `risk` | object | CIA risk assessment (see below). |

**Asset risk object:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `confidentiality` | number (0-100) | Yes | Confidentiality requirement rating. |
| `integrity` | number (0-100) | Yes | Integrity requirement rating. |
| `availability` | number (0-100) | Yes | Availability requirement rating. |
| `comment` | string | No | Narrative explaining the ratings. |

**Optional fields:**

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | What this asset is and why it matters. |
| `attributes` | object | Arbitrary key-value metadata. |

**Example:**

```json
{
  "id": "asset-customer-pii",
  "name": "Customer PII",
  "description": "Names, email addresses, and shipping addresses",
  "risk": {
    "confidentiality": 90,
    "integrity": 80,
    "availability": 50,
    "comment": "PII breach triggers regulatory notification requirements"
  },
  "attributes": {
    "classification": "confidential",
    "regulations": "GDPR, CCPA"
  }
}
```

### trustZones

Security boundary definitions that partition the system into areas of
different trust levels.

**Required fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier. |
| `name` | string | Name of the trust zone. |
| `risk` | object | Trust rating (see below). |

**Trust zone risk object:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `trustRating` | number (0-100) | Yes | How trusted this zone is (0 = untrusted, 100 = fully trusted). |

**Optional fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Zone classification. |
| `description` | string | What this zone encompasses. |
| `parent` | object | Reference to a parent zone (contains `trustZone` string). |
| `representations` | array | Visual representation references. |
| `attributes` | object | Arbitrary key-value metadata. |

**Example:**

```json
{
  "id": "tz-public",
  "name": "Public Internet",
  "description": "Untrusted external network including end-user browsers and third-party clients",
  "risk": {
    "trustRating": 10
  },
  "type": "internet",
  "attributes": {
    "zoneId": "TZ-001"
  }
}
```

### components

System building blocks: services, databases, queues, external APIs, and
other architectural elements.

**Required fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier. |
| `name` | string | Component name. |
| `type` | string | Component category (e.g., `"web-service"`, `"database"`, `"queue"`, `"external-service"`). |
| `parent` | object | Trust zone or parent component (contains `trustZone` string). |

**Optional fields:**

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | What this component does. |
| `representations` | array | Visual representation references. |
| `assets` | array | References to assets processed by this component. |
| `threats` | array | Inline threat references (see Threats section). |
| `tags` | array of strings | Classification labels. |
| `attributes` | object | Arbitrary key-value metadata. |

**Example:**

```json
{
  "id": "comp-api-gateway",
  "name": "API Gateway",
  "type": "web-service",
  "description": "NGINX-based reverse proxy handling TLS termination and rate limiting",
  "parent": {
    "trustZone": "tz-dmz"
  },
  "tags": ["entrypoint", "tls-termination"],
  "attributes": {
    "technology": "NGINX",
    "componentId": "C-001"
  }
}
```

### dataflows

Data movement between components, representing communication channels
and data exchange.

**Required fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier. |
| `name` | string | Description of what flows. |
| `source` | string | ID of the source component. |
| `destination` | string | ID of the destination component. |

**Optional fields:**

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Details about the data flow. |
| `bidirectional` | boolean | Whether data flows in both directions. |
| `assets` | array | References to assets carried by this flow. |
| `threats` | array | Inline threat references. |
| `tags` | array of strings | Classification labels. |
| `attributes` | object | Arbitrary key-value metadata. |

**Example:**

```json
{
  "id": "df-client-to-gateway",
  "name": "Client API Requests",
  "source": "comp-browser",
  "destination": "comp-api-gateway",
  "description": "HTTPS requests containing authentication tokens and order data",
  "bidirectional": true,
  "tags": ["crosses-trust-boundary"],
  "attributes": {
    "protocol": "HTTPS/TLS 1.3",
    "sensitivity": "confidential",
    "flowId": "DF-001"
  }
}
```

### threats

Identified threats with risk ratings. Threats can be defined at the
top level (global) or inline within components and dataflows.

**Required fields (top-level threats):**

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier. |
| `name` | string | Concise threat title. |
| `risk` | object | Risk assessment (see below). |

**Threat risk object:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `likelihood` | number (0-100) or null | Yes | How likely the threat is to be realized. |
| `likelihoodComment` | string or null | No | Narrative explaining the likelihood rating. |
| `impact` | number (0-100) | Yes | Severity of consequences if the threat is realized. |
| `impactComment` | string | No | Narrative explaining the impact rating. |

OTM does not compute a combined risk score from likelihood and impact.
It provides both axes to downstream tools or risk calculation engines
for further processing.

**Optional fields:**

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Detailed threat scenario. |
| `categories` | array of strings | Threat classification labels (e.g., STRIDE category). |
| `cwes` | array of strings | CWE identifiers if applicable. |
| `tags` | array of strings | Additional classification labels. |
| `attributes` | object | Arbitrary key-value metadata (used for raw DREAD scores). |

**Example (with DREAD-to-OTM mapping applied):**

```json
{
  "id": "threat-sql-injection",
  "name": "SQL Injection via Order Search",
  "description": "Attacker crafts malicious search parameters to extract or modify order records through unsanitized input to the search endpoint",
  "categories": ["Tampering", "Information Disclosure"],
  "risk": {
    "likelihood": 70,
    "likelihoodComment": "DREAD Reproducibility: 8/10, Exploitability: 7/10, Discoverability: 6/10.",
    "impact": 80,
    "impactComment": "DREAD Damage Potential: 8/10. Affected Users: 7/10 (all users with order history)."
  },
  "tags": ["STRIDE-T", "STRIDE-I", "boundary-crossing"],
  "attributes": {
    "threatId": "TM-001",
    "dpiScore": "8",
    "rScore": "8",
    "eScore": "7",
    "auScore": "7",
    "discScore": "6",
    "dreadAverage": "7.2",
    "dreadFormula": "(DamagePotential + Reproducibility + Exploitability + AffectedUsers + Discoverability) / 5",
    "attackTechnique": "ATT&CK: T1190 (Exploit Public-Facing Application)"
  }
}
```

**Inline threat references** (within components or dataflows) use a
simplified structure referencing a top-level threat by ID with a state
value and optional mitigation references:

```json
{
  "threat": "threat-sql-injection",
  "state": "exposed",
  "mitigations": [
    {
      "mitigation": "mit-parameterized-queries",
      "state": "required"
    }
  ]
}
```

### mitigations

Proposed or existing security controls that reduce threat risk.

**Required fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier. |
| `name` | string | Concise mitigation title. |
| `riskReduction` | number (0-100) | Estimated risk reduction percentage. |

**Optional fields:**

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Implementation details for this control. |
| `attributes` | object | Arbitrary key-value metadata. |

**Example:**

```json
{
  "id": "mit-parameterized-queries",
  "name": "Parameterized Database Queries",
  "description": "Replace string concatenation in SQL query construction with parameterized queries using the ORM query builder",
  "riskReduction": 90,
  "attributes": {
    "effort": "low",
    "effectiveness": "full",
    "timeline": "immediate"
  }
}
```

---

## DREAD-to-OTM Risk Rating Mapping

DREAD uses a five-axis model (each scored 0-10). OTM uses a two-axis
model (`likelihood` 0-100 and `impact` 0-100). Mapping five axes to
two axes is inherently lossy. This section defines the mapping strategy
that preserves maximum fidelity.

### Layer 1: OTM `risk` Fields

Map DREAD dimensions to OTM axes using these formulas:

```
OTM impact     = DamagePotential * 10
                 (scale 0-10 -> 0-100)

OTM likelihood = ((Reproducibility + Exploitability + Discoverability) / 3) * 10
                 (average of three axes, scale 0-10 -> 0-100)
```

**Rationale:**

- **Damage Potential** measures impact severity directly -- it maps
  cleanly to OTM `impact`.
- **Reproducibility**, **Exploitability**, and **Discoverability** are
  all facets of how likely a threat is to be realized -- their average
  maps to OTM `likelihood`.
- **Affected Users** is a scope modifier that does not map cleanly to
  either axis. It is preserved in the `attributes` layer and in the
  `impactComment` narrative only.

**Narrative fields:**

- `impactComment`: `"DREAD Damage Potential: {D}/10. Affected Users:
  {A}/10 ({scope description})."`
- `likelihoodComment`: `"DREAD Reproducibility: {R}/10,
  Exploitability: {E}/10, Discoverability: {Disc}/10."`

### Layer 2: OTM `attributes` Object

Store all five raw DREAD scores in the threat's `attributes` field
for lossless round-tripping:

```json
{
  "attributes": {
    "dpiScore": "7",
    "rScore": "8",
    "eScore": "6",
    "auScore": "9",
    "discScore": "5",
    "dreadAverage": "7.0",
    "dreadFormula": "(DamagePotential + Reproducibility + Exploitability + AffectedUsers + Discoverability) / 5"
  }
}
```

**Attribute key reference:**

| Key | DREAD Dimension | Used In |
|-----|-----------------|---------|
| `dpiScore` | Damage Potential | `risk.impact` mapping |
| `rScore` | Reproducibility | `risk.likelihood` mapping |
| `eScore` | Exploitability | `risk.likelihood` mapping |
| `auScore` | Affected Users | `risk.impactComment` only |
| `discScore` | Discoverability | `risk.likelihood` mapping |
| `dreadAverage` | Overall DREAD average | Severity classification |
| `dreadFormula` | Computation formula | Documentation / auditability |

### Information Loss Acknowledgment

Mapping five axes to two axes is inherently lossy. The Affected Users
dimension influences both likelihood and impact but does not map cleanly
to either. By preserving raw scores in `attributes`, any downstream
tool can reconstruct the full DREAD profile. The OTM `risk` fields
provide interoperability with tools that understand OTM's two-axis
model, while `attributes` provides full fidelity for tools that
understand DREAD.

### Worked Example

Given a threat with these DREAD scores:

| Dimension | Score |
|-----------|-------|
| Damage Potential | 8 |
| Reproducibility | 6 |
| Exploitability | 7 |
| Affected Users | 9 |
| Discoverability | 5 |

**Step 1 -- Compute OTM impact:**

```
impact = DamagePotential * 10 = 8 * 10 = 80
```

**Step 2 -- Compute OTM likelihood:**

```
likelihood = ((Reproducibility + Exploitability + Discoverability) / 3) * 10
           = ((6 + 7 + 5) / 3) * 10
           = (18 / 3) * 10
           = 6.0 * 10
           = 60
```

**Step 3 -- Compose narrative fields:**

```
impactComment:     "DREAD Damage Potential: 8/10. Affected Users: 9/10 (75-100% of users; all tenants)."
likelihoodComment: "DREAD Reproducibility: 6/10, Exploitability: 7/10, Discoverability: 5/10."
```

**Step 4 -- Compute DREAD average (for severity classification):**

```
dreadAverage = (8 + 6 + 7 + 9 + 5) / 5 = 35 / 5 = 7.0
```

**Step 5 -- Store in OTM threat object:**

```json
{
  "id": "threat-example",
  "name": "Example Threat",
  "risk": {
    "likelihood": 60,
    "likelihoodComment": "DREAD Reproducibility: 6/10, Exploitability: 7/10, Discoverability: 5/10.",
    "impact": 80,
    "impactComment": "DREAD Damage Potential: 8/10. Affected Users: 9/10 (75-100% of users; all tenants)."
  },
  "attributes": {
    "dpiScore": "8",
    "rScore": "6",
    "eScore": "7",
    "auScore": "9",
    "discScore": "5",
    "dreadAverage": "7.0",
    "dreadFormula": "(DamagePotential + Reproducibility + Exploitability + AffectedUsers + Discoverability) / 5"
  }
}
```

---

## Complete OTM JSON Example

The following is a complete, structurally valid OTM document for a
reference web application. It demonstrates all element types with
DREAD-to-OTM risk rating mapping applied.

```json
{
  "otmVersion": "0.2.0",
  "project": {
    "name": "Bookstore API",
    "id": "bookstore-api-tm-001",
    "description": "REST API for an online bookstore with user accounts and payment processing",
    "owner": "Engineering Team",
    "attributes": {
      "methodology": "STRIDE+DREAD",
      "modelVersion": "1.0",
      "createdDate": "2026-06-20"
    }
  },
  "representations": [
    {
      "id": "rep-system-context",
      "name": "System Context Diagram",
      "type": "diagram",
      "description": "High-level architecture showing trust zones and component placement"
    }
  ],
  "trustZones": [
    {
      "id": "tz-external",
      "name": "External Network",
      "description": "Untrusted public internet including browsers and third-party API clients",
      "risk": {
        "trustRating": 10
      },
      "attributes": {
        "zoneId": "TZ-001"
      }
    },
    {
      "id": "tz-internal",
      "name": "Internal Application Network",
      "description": "Private network segment hosting application services and data stores",
      "risk": {
        "trustRating": 70
      },
      "attributes": {
        "zoneId": "TZ-002"
      }
    }
  ],
  "components": [
    {
      "id": "comp-browser",
      "name": "Web Browser",
      "type": "external-client",
      "description": "End-user browser running the bookstore frontend",
      "parent": {
        "trustZone": "tz-external"
      },
      "tags": ["user-facing"],
      "attributes": {
        "componentId": "C-001"
      }
    },
    {
      "id": "comp-api-server",
      "name": "Bookstore API Server",
      "type": "web-service",
      "description": "Django REST framework application handling book catalog, user accounts, and order processing",
      "parent": {
        "trustZone": "tz-internal"
      },
      "tags": ["entrypoint", "authentication"],
      "attributes": {
        "technology": "Django 5.x / Python",
        "componentId": "C-002"
      }
    },
    {
      "id": "comp-database",
      "name": "PostgreSQL Database",
      "type": "database",
      "description": "Primary data store for user accounts, book catalog, and order records",
      "parent": {
        "trustZone": "tz-internal"
      },
      "tags": ["data-store", "pii"],
      "attributes": {
        "technology": "PostgreSQL 16",
        "componentId": "C-003"
      }
    }
  ],
  "dataflows": [
    {
      "id": "df-browser-to-api",
      "name": "Browser to API Requests",
      "source": "comp-browser",
      "destination": "comp-api-server",
      "description": "HTTPS requests carrying authentication tokens, search queries, and order submissions",
      "bidirectional": true,
      "tags": ["crosses-trust-boundary"],
      "attributes": {
        "protocol": "HTTPS/TLS 1.3",
        "sensitivity": "confidential",
        "flowId": "DF-001"
      }
    },
    {
      "id": "df-api-to-db",
      "name": "API to Database Queries",
      "source": "comp-api-server",
      "destination": "comp-database",
      "description": "SQL queries for user authentication, catalog retrieval, and order persistence",
      "bidirectional": true,
      "attributes": {
        "protocol": "PostgreSQL wire protocol (TLS)",
        "sensitivity": "restricted",
        "flowId": "DF-002"
      }
    }
  ],
  "assets": [
    {
      "id": "asset-user-credentials",
      "name": "User Credentials",
      "description": "Usernames, hashed passwords, and session tokens",
      "risk": {
        "confidentiality": 95,
        "integrity": 90,
        "availability": 60,
        "comment": "Credential compromise enables account takeover across all user accounts"
      }
    },
    {
      "id": "asset-order-records",
      "name": "Order Records",
      "description": "Purchase history including payment references and shipping addresses",
      "risk": {
        "confidentiality": 80,
        "integrity": 85,
        "availability": 70,
        "comment": "Contains PII and partial payment data subject to PCI DSS scope"
      }
    }
  ],
  "threats": [
    {
      "id": "threat-credential-brute-force",
      "name": "Credential Brute Force at Login Endpoint",
      "description": "Attacker performs automated credential stuffing or brute-force attacks against the authentication endpoint to gain access to user accounts",
      "categories": ["Spoofing"],
      "risk": {
        "likelihood": 77,
        "likelihoodComment": "DREAD Reproducibility: 9/10, Exploitability: 7/10, Discoverability: 7/10.",
        "impact": 70,
        "impactComment": "DREAD Damage Potential: 7/10. Affected Users: 8/10 (25-75% of users; credential reuse amplifies scope)."
      },
      "tags": ["STRIDE-S", "boundary-crossing"],
      "attributes": {
        "threatId": "TM-001",
        "dpiScore": "7",
        "rScore": "9",
        "eScore": "7",
        "auScore": "8",
        "discScore": "7",
        "dreadAverage": "7.6",
        "dreadFormula": "(DamagePotential + Reproducibility + Exploitability + AffectedUsers + Discoverability) / 5",
        "attackTechnique": "ATT&CK: T1110 (Brute Force)"
      }
    },
    {
      "id": "threat-idor-order-access",
      "name": "Insecure Direct Object Reference on Order Records",
      "description": "Authenticated user manipulates order ID parameters to access or modify another user's order records, bypassing authorization checks",
      "categories": ["Elevation of Privilege", "Information Disclosure"],
      "risk": {
        "likelihood": 63,
        "likelihoodComment": "DREAD Reproducibility: 8/10, Exploitability: 6/10, Discoverability: 5/10.",
        "impact": 60,
        "impactComment": "DREAD Damage Potential: 6/10. Affected Users: 5/10 (5-25% of users; requires authenticated attacker targeting specific orders)."
      },
      "tags": ["STRIDE-E", "STRIDE-I"],
      "attributes": {
        "threatId": "TM-002",
        "dpiScore": "6",
        "rScore": "8",
        "eScore": "6",
        "auScore": "5",
        "discScore": "5",
        "dreadAverage": "6.0",
        "dreadFormula": "(DamagePotential + Reproducibility + Exploitability + AffectedUsers + Discoverability) / 5",
        "attackTechnique": "ATT&CK: T1078 (Valid Accounts)"
      }
    },
    {
      "id": "threat-missing-audit-log",
      "name": "Missing Audit Trail for Administrative Actions",
      "description": "Administrative operations (user deletion, role changes, bulk exports) are not logged, preventing detection of insider threats and making forensic investigation impossible after a breach",
      "categories": ["Repudiation"],
      "risk": {
        "likelihood": 50,
        "likelihoodComment": "DREAD Reproducibility: 7/10, Exploitability: 4/10, Discoverability: 4/10.",
        "impact": 50,
        "impactComment": "DREAD Damage Potential: 5/10. Affected Users: 6/10 (all users affected if insider threat goes undetected, but direct damage is limited to loss of accountability)."
      },
      "tags": ["STRIDE-R", "cross-cutting"],
      "attributes": {
        "threatId": "TM-003",
        "dpiScore": "5",
        "rScore": "7",
        "eScore": "4",
        "auScore": "6",
        "discScore": "4",
        "dreadAverage": "5.2",
        "dreadFormula": "(DamagePotential + Reproducibility + Exploitability + AffectedUsers + Discoverability) / 5"
      }
    }
  ],
  "mitigations": [
    {
      "id": "mit-rate-limiting",
      "name": "Rate Limiting on Authentication Endpoint",
      "description": "Implement progressive rate limiting (exponential backoff after 5 failed attempts per IP, account lockout after 10 failed attempts per account) on the login endpoint",
      "riskReduction": 75,
      "attributes": {
        "effort": "low",
        "effectiveness": "partial",
        "timeline": "immediate",
        "mitigates": "TM-001"
      }
    },
    {
      "id": "mit-object-level-authz",
      "name": "Object-Level Authorization Checks",
      "description": "Enforce ownership verification on all order record endpoints by checking that the authenticated user's ID matches the order's owner_id before returning or modifying data",
      "riskReduction": 95,
      "attributes": {
        "effort": "medium",
        "effectiveness": "full",
        "timeline": "immediate",
        "mitigates": "TM-002"
      }
    }
  ]
}
```

---

## Mapping from Skill Workflow to OTM Elements

The three-phase workflow in the parent SKILL.md maps to OTM elements
as follows:

| Workflow Phase | Workflow Output | OTM Element |
|----------------|-----------------|-------------|
| Phase 1 -- System Decomposition | Components | `components` |
| Phase 1 -- System Decomposition | Trust zones | `trustZones` |
| Phase 1 -- System Decomposition | Assets | `assets` |
| Phase 1 -- System Decomposition | Data flows | `dataflows` |
| Phase 1 -- System Decomposition | Architecture diagrams | `representations` |
| Phase 2 -- Threat Analysis | Identified threats | `threats` (with `risk` using DREAD mapping) |
| Phase 2 -- Threat Analysis | DREAD scores | `threats[].risk` + `threats[].attributes` |
| Phase 3 -- Synthesis | Proposed mitigations | `mitigations` |
| Phase 3 -- Synthesis | Project metadata | `project` |

---

## CycloneDX Threat Modeling BOM (TM-BOM)

*Reserved for future content.*

CycloneDX specification v2.0 is expected to introduce a Threat Modeling
Bill of Materials (TM-BOM) format. When the specification is finalized
(expected August 2026), this section will document:

- Mapping between OTM elements and CycloneDX TM-BOM components
- Conversion strategy for dual-format output (OTM + CycloneDX)
- Any structural changes required to the skill workflow

Monitor the CycloneDX specification at
<https://cyclonedx.org/capabilities/tm/> for updates.

Structural changes to this reference file and the parent SKILL.md may
be required once the TM-BOM specification is finalized.
