---
name: dependency-audit
description: Supply chain security audit — coordinates real CLI vulnerability scanners (npm audit, pip-audit, govulncheck, cargo audit, etc.) and synthesizes findings with license compliance and risk assessment.
model: claude-sonnet-4-5
version: 1.0.0
---
# /dependency-audit Workflow

## Role

This skill is a **pipeline coordinator**. It orchestrates a sequential supply chain security workflow by delegating scanner invocation and synthesis to appropriate tools. It does NOT perform LLM-based CVE lookup — it coordinates real CLI scanners that use live vulnerability databases, then synthesizes their output. The LLM's training data has a knowledge cutoff and cannot reliably detect post-cutoff CVEs.

## Inputs

- Package manifest path or scope: $ARGUMENTS (optional — auto-detected if omitted)
- Supported: `package.json`, `requirements.txt`, `pyproject.toml`, `Pipfile`, `go.mod`, `Cargo.toml`, `pom.xml`, `Gemfile`

## Step 0 — Pre-flight: detect manifest and scanner availability

Tool: `Bash` (direct — coordinator does this), `Glob`

**Detect manifest type** by searching for known manifest files:

Tool: `Glob`

Search patterns (in order):
- `**/package.json` → ecosystem: Node.js, scanner: `npm audit`
- `**/requirements.txt` or `**/pyproject.toml` or `**/Pipfile` → ecosystem: Python, scanners: `pip-audit` or `safety`
- `**/go.mod` → ecosystem: Go, scanner: `govulncheck`
- `**/Cargo.toml` → ecosystem: Rust, scanner: `cargo audit`
- `**/pom.xml` → ecosystem: Java, scanner: `mvn dependency:analyze`
- `**/Gemfile` → ecosystem: Ruby, scanner: `bundle audit`

If $ARGUMENTS specifies a manifest path, use that directly. Otherwise, use the first manifest found.

**Check scanner availability** via `which`:

Tool: `Bash`

```bash
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
echo "Run timestamp: $TIMESTAMP"

# Detect ecosystem and check scanners
ECOSYSTEM=""
MANIFEST=""
SCANNER=""
SCANNER_CMD=""

# Check for manifests and their scanners
if [ -f "package.json" ] || [ -f "$(find . -name 'package.json' -not -path '*/node_modules/*' -maxdepth 3 | head -1)" ]; then
  MANIFEST=$(find . -name 'package.json' -not -path '*/node_modules/*' -maxdepth 3 | head -1)
  ECOSYSTEM="Node.js"
  if which npm >/dev/null 2>&1; then SCANNER="npm"; SCANNER_CMD="npm audit --json"; fi
fi

if [ -z "$ECOSYSTEM" ] && ([ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "Pipfile" ]); then
  MANIFEST=$(ls requirements.txt pyproject.toml Pipfile 2>/dev/null | head -1)
  ECOSYSTEM="Python"
  if which pip-audit >/dev/null 2>&1; then SCANNER="pip-audit"; SCANNER_CMD="pip-audit --format json";
  elif which safety >/dev/null 2>&1; then SCANNER="safety"; SCANNER_CMD="safety check --json"; fi
fi

if [ -z "$ECOSYSTEM" ] && [ -f "go.mod" ]; then
  MANIFEST="go.mod"
  ECOSYSTEM="Go"
  if which govulncheck >/dev/null 2>&1; then SCANNER="govulncheck"; SCANNER_CMD="govulncheck ./..."; fi
fi

if [ -z "$ECOSYSTEM" ] && [ -f "Cargo.toml" ]; then
  MANIFEST="Cargo.toml"
  ECOSYSTEM="Rust"
  if which cargo >/dev/null 2>&1; then SCANNER="cargo audit"; SCANNER_CMD="cargo audit --json"; fi
fi

if [ -z "$ECOSYSTEM" ] && [ -f "pom.xml" ]; then
  MANIFEST="pom.xml"
  ECOSYSTEM="Java"
  if which mvn >/dev/null 2>&1; then SCANNER="mvn"; SCANNER_CMD="mvn dependency:analyze -q"; fi
fi

if [ -z "$ECOSYSTEM" ] && [ -f "Gemfile" ]; then
  MANIFEST="Gemfile"
  ECOSYSTEM="Ruby"
  if which bundle >/dev/null 2>&1 && bundle exec gem list 2>/dev/null | grep -q bundler-audit; then
    SCANNER="bundle-audit"; SCANNER_CMD="bundle audit check --update";
  fi
fi

echo "ECOSYSTEM=$ECOSYSTEM"
echo "MANIFEST=$MANIFEST"
echo "SCANNER=$SCANNER"
echo "SCANNER_CMD=$SCANNER_CMD"
echo "TIMESTAMP=$TIMESTAMP"
```

**Pre-flight outcomes:**

- If no manifest found: Stop workflow. Output: "No supported package manifest found. Supported: package.json, requirements.txt, pyproject.toml, Pipfile, go.mod, Cargo.toml, pom.xml, Gemfile"
- If manifest found but no scanner available: Log `SCANNER=""` — workflow continues. Steps 1–3 will be skipped for CVE scanning; Steps 4–5 (license + supply chain) still run. Verdict will be `INCOMPLETE`.
- If manifest and scanner found: Full workflow runs.

## Step 1 — Read and parse manifest

Tool: `Read` (direct — coordinator does this)

Read the manifest file identified in Step 0. Extract:
- All direct dependencies (name + version or version constraint)
- All dev/test dependencies (if present and relevant)
- Lock file location (e.g., `package-lock.json`, `Pipfile.lock`, `go.sum`, `Cargo.lock`, `Gemfile.lock`) for precise version data

If a lock file exists alongside the manifest, note it — the scanner will use it for exact vulnerability matching.

Output summary of dependency count to stdout (e.g., "Found 42 direct dependencies, 87 total including transitive").

## Step 2 — Invoke scanner

Tool: `Bash` (direct — coordinator does this)

**If no scanner is available (SCANNER="" from Step 0):**

Output:
```
SCANNER STATUS: INCOMPLETE — no vulnerability scanner available for [ecosystem]

To enable full vulnerability scanning, install the appropriate scanner:
  Node.js:  npm (included with Node.js)
  Python:   pip install pip-audit   (or: pip install safety)
  Go:       go install golang.org/x/vuln/cmd/govulncheck@latest
  Rust:     cargo install cargo-audit
  Java:     Apache Maven required (https://maven.apache.org)
  Ruby:     gem install bundler-audit

Continuing with license compliance and supply chain risk assessment only.
Steps 4–5 will still run. CVE vulnerability data will NOT be reported.
```

Set SCANNER_OUTPUT="(no scanner available)" and skip to Step 3 synthesis with empty CVE data.

**If scanner is available:**

Run the scanner. Note: non-zero exit codes from vulnerability scanners indicate findings, not errors.

```bash
# Run scanner — non-zero exit = findings found, not a command error
SCANNER_OUTPUT_FILE="./plans/dependency-audit-${TIMESTAMP}.scanner-raw.json"

case "$SCANNER" in
  npm)
    npm audit --json 2>/dev/null > "$SCANNER_OUTPUT_FILE" || true
    ;;
  pip-audit)
    pip-audit --format json 2>/dev/null > "$SCANNER_OUTPUT_FILE" || true
    ;;
  safety)
    safety check --json 2>/dev/null > "$SCANNER_OUTPUT_FILE" || true
    ;;
  govulncheck)
    govulncheck -json ./... 2>/dev/null > "$SCANNER_OUTPUT_FILE" || true
    ;;
  "cargo audit")
    cargo audit --json 2>/dev/null > "$SCANNER_OUTPUT_FILE" || true
    ;;
  mvn)
    mvn dependency:analyze -q 2>&1 > "$SCANNER_OUTPUT_FILE" || true
    ;;
  bundle-audit)
    bundle audit check --update 2>&1 > "$SCANNER_OUTPUT_FILE" || true
    ;;
esac

echo "Scanner output saved to: $SCANNER_OUTPUT_FILE"
cat "$SCANNER_OUTPUT_FILE"
```

## Step 3 — LLM synthesis of scanner output

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

Prompt:
"You are a security analyst synthesizing vulnerability scanner output for a dependency audit report.

Read the scanner output file at `./plans/dependency-audit-[TIMESTAMP].scanner-raw.json`.
Also read the manifest file at `[MANIFEST]`.

**Your task:**

1. Parse the scanner output and extract all vulnerability findings.
2. For each finding, identify:
   - Package name and affected version
   - CVE/vulnerability ID (e.g., CVE-2024-XXXXX, GHSA-XXXXX)
   - Severity (Critical / High / Medium / Low — use scanner-reported severity)
   - Description (one sentence)
   - Whether a fixed version is available
   - Whether the vulnerable package is a direct dependency or transitive

3. Categorize findings by severity:
   - Critical: RCE, authentication bypass, data exfiltration — must fix before shipping
   - High: Significant security impact — should fix soon
   - Medium: Limited impact or requires unusual conditions — review and plan fix
   - Low: Minimal impact — track but lower priority

4. Note any findings where the scanner could not complete (e.g., network errors, auth required).

**Output:** Write your synthesis to `./plans/dependency-audit-[TIMESTAMP].cve-synthesis.md` with:
```
## CVE Findings

**Scanner:** [scanner name and version if available]
**Ecosystem:** [ecosystem]
**Scan date:** [timestamp]
**Total vulnerabilities:** [count by severity: X Critical, X High, X Medium, X Low]

### Critical Findings
[table: Package | CVE ID | Description | Fixed Version | Direct/Transitive]

### High Findings
[table]

### Medium Findings
[table]

### Low Findings
[table]

### Scanner Notes
[any warnings, incomplete scans, or limitations from the scanner output]
```

If scanner output was empty or indicated no findings, write: 'No vulnerabilities found by scanner.'
If no scanner was available (SCANNER_STATUS=INCOMPLETE), write: 'CVE scan skipped — no scanner available.'"

## Step 4 — License compliance check

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

Prompt:
"You are reviewing a software project's dependency manifest for license compliance issues.

Read the manifest at `[MANIFEST]`. If a lock file exists (package-lock.json, Pipfile.lock, go.sum, Cargo.lock, Gemfile.lock), also read it for exact package versions.

**Your task:**

Analyze the dependencies for license compliance concerns. LLM analysis is appropriate for license review since license data is stable (licenses don't change after release) and license terms are documented.

1. **Identify licenses** for each dependency (use your knowledge of well-known packages' licenses).
   Note: You may not know every package's license. For packages you are uncertain about, flag them as 'license unknown — verify manually'.

2. **Flag compliance concerns:**
   - **Copyleft (strong):** GPL-2.0, GPL-3.0, AGPL-3.0 — may require source disclosure
   - **Copyleft (weak):** LGPL, MPL — generally OK for linking but review usage
   - **Restricted:** Commercial licenses, proprietary, no-license (all-rights-reserved)
   - **Patent risk:** Check for packages with known patent encumbrances
   - **License conflicts:** GPL-incompatible combinations

3. **Approve without concern:**
   - MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, Unlicense, CC0

**Output:** Write to `./plans/dependency-audit-[TIMESTAMP].license-check.md` with:
```
## License Compliance

### Summary
[X packages reviewed, Y flagged for review, Z unknown]

### Flagged Dependencies
| Package | License | Concern | Recommendation |
|---------|---------|---------|----------------|

### Unknown Licenses (verify manually)
| Package | Notes |

### Approved Licenses
[Count of packages with permissive licenses — no individual listing needed]

### Notes
[Any license conflict combinations, usage-specific caveats]
```"

## Step 5 — Supply chain risk assessment

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

Prompt:
"You are performing a supply chain risk assessment of a software project's dependencies.

Read the manifest at `[MANIFEST]`.

**Your task:**

Assess supply chain health indicators using your knowledge of packages and general patterns. This is LLM heuristic analysis — flag concerns for human verification, not definitive findings.

1. **Typosquatting indicators** — Check for package names that are:
   - Very similar to popular packages (e.g., 'lodash' vs 'l0dash', 'react' vs 'reeact')
   - Unusual character substitutions
   - Suspicious name patterns for the ecosystem

2. **Maintenance health indicators** — For packages you know about:
   - Packages known to be unmaintained or deprecated
   - Packages that had ownership transfers recently
   - Packages with known malicious versions in their history

3. **Dependency sprawl** — Flag:
   - Unusually large number of dependencies for the project type
   - Dependencies that duplicate functionality of other dependencies
   - Dependencies for trivial functionality (e.g., single-function packages)

4. **Version pinning** — Check if:
   - Dependencies use exact versions (good) vs. wide ranges (risk)
   - Lock file is present (good) vs. absent (risk)
   - Any dependency uses `*` or `latest` as version (high risk)

**Output:** Write to `./plans/dependency-audit-[TIMESTAMP].supply-chain.md` with:
```
## Supply Chain Risk Assessment

### Typosquatting Suspects
[Table: Package | Similar To | Risk Level | Recommendation]
[Or: 'No typosquatting suspects identified.']

### Maintenance Concerns
[Table: Package | Concern | Risk Level]
[Or: 'No known maintenance concerns.']

### Version Pinning
[Summary: Lock file present? Loose version ranges? Specific risky patterns found?]

### Dependency Health Summary
[Overall assessment: HEALTHY / REVIEW_NEEDED / CONCERNING]

### Disclaimer
This is LLM heuristic analysis. Findings require human verification. Check package registries (npmjs.com, PyPI, crates.io, etc.) for current status.
```"

## Step 6 — Generate consolidated report

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

Prompt:
"You are generating a consolidated dependency audit report from three analysis documents.

Read all three analysis files:
- `./plans/dependency-audit-[TIMESTAMP].cve-synthesis.md`
- `./plans/dependency-audit-[TIMESTAMP].license-check.md`
- `./plans/dependency-audit-[TIMESTAMP].supply-chain.md`

Also read the manifest at `[MANIFEST]`.

**Your task:**

Write a consolidated report to `./plans/dependency-audit-[TIMESTAMP].report.md` with:

```
# Dependency Audit Report

**Date:** [TIMESTAMP]
**Ecosystem:** [ecosystem]
**Manifest:** [manifest path]
**Scanner used:** [scanner name or 'none — INCOMPLETE']

## Executive Summary

[2-3 sentences summarizing the overall security posture of the dependencies]

**Verdict:** [PASS / PASS_WITH_NOTES / BLOCKED / INCOMPLETE — see Step 7 criteria]

## Vulnerability Findings
[Paste CVE synthesis content]

## License Compliance
[Paste license check content]

## Supply Chain Risk
[Paste supply chain content]

## Remediation Priorities

### Immediate (Critical/High vulnerabilities)
[Numbered list with: package, CVE, fix command (e.g., npm update package@version)]

### Short-term (Medium vulnerabilities, license concerns)
[Numbered list]

### Monitor (Low vulnerabilities, supply chain flags)
[Numbered list]

## Scanner Installation (if INCOMPLETE)
[Only if no scanner was available — installation instructions for this ecosystem]
```

Preliminary verdict guidance for your report (final verdict set in Step 7):
- BLOCKED: Any Critical CVE present
- PASS_WITH_NOTES: High CVEs, license flags, or supply chain concerns — no Critical CVEs
- INCOMPLETE: No scanner available — CVE data missing
- PASS: No findings across all three analyses"

## Step 7 — Verdict gate

Tool: `Read` (direct — coordinator does this)

Read `./plans/dependency-audit-[TIMESTAMP].report.md` and determine final verdict.

**Verdict rules (in priority order):**

1. **BLOCKED** — Any Critical severity CVE found. Mandatory remediation before shipping.
2. **INCOMPLETE** — No scanner was available. CVE vulnerability data is missing. Cannot report PASS. License and supply chain data may be present.
3. **PASS_WITH_NOTES** — No Critical CVEs, but any of: High severity CVEs, license compliance flags, supply chain concerns.
4. **PASS** — Scanner ran successfully, no CVEs found, no license flags, no supply chain concerns.

**IMPORTANT:** The skill MUST NOT report PASS when SCANNER was unavailable. INCOMPLETE is the correct verdict — it honestly represents that the vulnerability check could not be performed.

**Output verdict and archive:**

Tool: `Bash`

```bash
mkdir -p ./plans/archive/dependency-audit/${TIMESTAMP}
mv ./plans/dependency-audit-${TIMESTAMP}.scanner-raw.json \
   ./plans/dependency-audit-${TIMESTAMP}.cve-synthesis.md \
   ./plans/dependency-audit-${TIMESTAMP}.license-check.md \
   ./plans/dependency-audit-${TIMESTAMP}.supply-chain.md \
   ./plans/archive/dependency-audit/${TIMESTAMP}/ 2>/dev/null || true
echo "Archived analysis files to ./plans/archive/dependency-audit/${TIMESTAMP}/"
```

**Final output by verdict:**

- **PASS:** "Dependency audit PASS. No vulnerabilities, license issues, or supply chain concerns found. Report: `./plans/dependency-audit-[TIMESTAMP].report.md`"
- **PASS_WITH_NOTES:** "Dependency audit PASS_WITH_NOTES. Review findings in report: `./plans/dependency-audit-[TIMESTAMP].report.md`. Address High severity items before next release."
- **INCOMPLETE:** "Dependency audit INCOMPLETE. No vulnerability scanner available for [ecosystem]. Install [scanner] to enable CVE scanning. License and supply chain analysis: `./plans/dependency-audit-[TIMESTAMP].report.md`"
- **BLOCKED:** "Dependency audit BLOCKED. Critical vulnerabilities found — do not ship until resolved. Report: `./plans/dependency-audit-[TIMESTAMP].report.md`"
