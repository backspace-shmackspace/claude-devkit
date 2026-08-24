# Claude Devkit

**Version:** 1.0.0
**Last Updated:** 2026-08-21
**Purpose:** Unified development toolkit for Claude Code - skills, agents, generators, and templates

**New to Claude Devkit?** Start with [GETTING_STARTED.md](GETTING_STARTED.md) for a 15-minute tutorial.

## Overview

Claude Devkit is the complete toolkit for building with Claude Code. It combines skill definitions, agent generators, templates, and reusable configurations into a single, version-controlled repository.

**What's Inside:**
- **Skills** — 20 core skills (13 workflows + 7 knowledge bases) including `/architect`, `/ship`, `/retro`, `/audit`, `/sync`, `/fix`, security skills, and prodsec knowledge-base references
- **Generators** — Scripts to create agents, skills, and project structures
- **Templates** — Reusable templates for agents and skills
- **Configs** — Shared configurations and patterns
- **Scripts** — Deployment and validation utilities
- **Meta-Harness** — `devkit` CLI for targeting and managing skill execution across multiple repositories from outside the target project (see Quick Start step 5 and Integration Patterns)

## Architecture

### Three-Tier Structure

```
claude-devkit/
├── skills/              # Tier 1: Core skill definitions (source of truth)
│   ├── architect/           # Planning with approval gates
│   ├── ship/            # Implementation pipeline
│   ├── retro/           # Retrospective and learnings capture
│   ├── audit/           # Security, performance, and anti-pattern scanning
│   ├── sync/            # Documentation synchronization
│   ├── compliance-check/      # Regulatory framework validation
│   ├── dependency-audit/      # Supply chain security
│   ├── secrets-scan/          # Pre-commit secrets detection
│   ├── secure-review/         # Deep semantic security review
│   ├── threat-model-gate/     # Security planning reference
│   ├── fix/                   # Targeted finding remediation
│   ├── input-validation-injection/  # Injection prevention reference (knowledge-base)
│   ├── client-side-security/        # Browser security reference (knowledge-base)
│   ├── ai-code-review/              # AI-generated code review (knowledge-base)
│   ├── semgrep/                     # Semgrep static analysis (knowledge-base)
│   ├── build-yaml-misconfiguration/ # CI/CD pipeline security (knowledge-base)
│   ├── container-hardening/         # Container security (knowledge-base)
│   └── threat-model/                # Full STRIDE+DREAD threat modeling (knowledge-base)
│
├── contrib/             # Tier 1b: Optional/personal skills (opt-in)
│   ├── journal/         # Obsidian journal writing
│   ├── journal-recall/  # Journal search and retrieval
│   └── README.md        # Available contrib skills documentation
│
├── generators/          # Tier 2: Code generation
│   ├── generate_skill.py              # Create new skills
│   ├── generate_agents.py             # Create project agents (unified)
│   ├── generate_senior_architect.py   # Deprecated wrapper → generate_agents.py
│   ├── validate_skill.py              # Validate skill definitions
│   └── README.md
│
├── templates/           # Tier 3: Reusable templates
│   ├── skill-coordinator.md.template  # Coordinator pattern
│   ├── skill-pipeline.md.template     # Pipeline pattern
│   └── skill-scan.md.template         # Scan pattern
│
├── configs/             # Shared configurations
│   ├── skill-patterns.json
│   ├── audit-event-schema.json
│   ├── scanner-languages.json  # Language grammar config for codebase scanner
│   ├── scanner-value-thresholds.json  # Confidence tiers for scanner value analysis
│   └── base-definitions/
│
└── scripts/             # Deployment and utilities
    ├── deploy.sh        # Deploy skills to ~/.claude/skills/
    ├── install.sh       # Automated installation
    ├── uninstall.sh     # Clean uninstallation
    ├── validate-all.sh  # Health check - validate all skills
    ├── codebase-scanner.py    # Deterministic codebase symbol index (tree-sitter + regex fallback)
    ├── devkit_cli.py           # Meta-harness CLI implementation (stdlib only)
    ├── devkit                  # Meta-harness entry point (thin bash wrapper)
    ├── emit-audit-event.sh    # Audit event emission helper (invoked by skills)
    ├── audit-log-query.sh     # Query utility for JSONL audit logs
    ├── compute-run-score.sh   # Compute per-dimension scores from a JSONL audit log
    ├── score-reflector.sh     # Deterministic score reflector (candidate learnings)
    ├── scanner-value-report.sh # Scanner value analysis: cohort comparison by scanner mode
    ├── ship-queue.sh          # Sequential /ship runner for unattended batch execution
    ├── resolve-project-dir.sh # Reusable shell function for project artifact directory resolution
    ├── learnings_parser.py    # Deterministic learnings file parser (stdlib only)
    ├── learnings_aggregator.py # Cross-project learnings aggregator (stdlib only)
    ├── learnings_promotions.py # Promotion lifecycle manager (stdlib only)
    └── test-integration.sh    # Integration smoke tests (165 tests)
```

**Centralized Artifact Storage (per-project, outside target repos):**

```
~/.claude-devkit/
├── registry.json                    # Cross-project registry
├── scanner-venv/                    # Tree-sitter scanner venv
├── cache/                           # Scanner cache
├── scripts/                         # Deployed helper scripts
│   ├── emit-audit-event.sh
│   ├── compute-run-score.sh
│   ├── codebase-scanner.py
│   ├── score-reflector.sh
│   ├── scanner-value-report.sh
│   ├── audit-log-query.sh
│   └── resolve-project-dir.sh
├── learnings/                       # Shared cross-project learnings store
│   ├── index.json                   # Aggregated cross-project index
│   ├── promotions.json              # Promotion lifecycle tracking
│   └── reports/                     # /retro mine output reports
│       └── mine-<timestamp>.md
├── runs/                            # Detached execution output
└── projects/
    └── <project-id>/                # Per-project artifacts ($DEVKIT_PROJECT_DIR)
        ├── state.json
        ├── plan-refs/               # Cross-repo plan references (JSON)
        │   └── <plan-name>.ref.json
        └── plans/
            ├── [feature].md                     # Plans from /architect
            ├── [feature].redteam.md
            ├── audit-[timestamp].summary.md
            ├── audit-logs/                      # JSONL audit logs
            │   ├── ship-[run_id].jsonl
            │   ├── architect-[run_id].jsonl
            │   └── audit-[run_id].jsonl
            └── archive/                         # Archived artifacts
```

### Data Flow

```
Edit skills/*/SKILL.md or contrib/*/SKILL.md → git commit → ./scripts/deploy.sh [--contrib] → ~/.claude/skills/
       ↓
Use generators/ to create new skills and agents
       ↓
Customize from templates/
       ↓
Validate with validate_skill.py
       ↓
Deploy and use in Claude Code
       ↓
Skill invocation → codebase-scanner.py (pre-scan) → structured symbol index → agent context
```

**Core vs Contrib:**
- `skills/`: Universal skills deployed by default to all users
- `contrib/`: Optional/personal skills requiring user-specific setup (e.g., `~/journal/` vault)
- Deploy core only: `./scripts/deploy.sh` (default)
- Deploy contrib only: `./scripts/deploy.sh --contrib [name]`
- Deploy all: `./scripts/deploy.sh --all`

## Skill Registry

### Core Skills (skills/)

| Skill | Version | Purpose | Model | Steps |
|-------|---------|---------|-------|-------|
| **architect** | 3.5.0 | Context discovery → Architect (with project context) → Red Team + Librarian + Feasibility (parallel) → Revision loop → Approval gate. Supports `--fast`. Stage 2 plan content scan detects security-sensitive features; invokes security-analyst (Required, not Recommended) when deployed and injects threat-model-gate requirements. Plans include `## Work Groups` in Task Breakdown for /ship parallel execution. Context alignment and metadata in output. Auto-commits artifacts on verdict. JSONL audit logging to `$DEVKIT_PROJECT_DIR/plans/audit-logs/architect-<run_id>.jsonl`. Cross-repo context discovery when `DEVKIT_TARGET_COUNT > 1` (reads CLAUDE.md and runs scanner on all targets). Plan-ref creation via `devkit plan sync` on approval. | opus-4-6 | 6 |
| **ship** | 3.9.0 | Pre-flight check → Read plan + security requirements validation (Step 1 checks for threat model output and blocks if required gates are unmet; validates CWD against cross-repo plan targets) → Pattern validation (warnings) → Security gates (secrets-scan, secure-review with threat model context passing in Step 4d, dependency-audit) with maturity levels (L1/L2/L3) → Worktree isolation → Parallel coders (filtered by `target:` annotation for cross-repo plans) → File boundary validation → Merge → Code review + tests + QA (parallel) → Revision loop → Commit gate (emits `run_score` before `run_end`) → Retro capture. Supports `--security-override`. Structural conflict prevention. Learnings consumption. JSONL audit logging to `$DEVKIT_PROJECT_DIR/plans/audit-logs/ship-<run_id>.jsonl` with maturity-aware retention. Quantitative scoring (efficiency, security, quality, velocity) emitted as `run_score` event. Cross-repo plan ref cleanup via `devkit plan archive` on archive step. | opus-4-6 | 8 |
| **retro** | 1.1.0 | Mine review artifacts for recurring patterns and write project learnings. Scope modes: recent/full/feature-name/mine. `mine` scope performs cross-project learnings analysis: aggregates all project learnings, detects tag-based patterns across 3+ projects, proposes promotions (LLM-assisted), and records proposals for human review. Glob-based discovery, format-resilient prompts, severity-rated findings, semantic deduplication. | opus-4-6 | 7 |
| **audit** | 3.3.0 | Scope detection (plan/code/full) → Security scan (composable: invokes /secure-review when deployed, otherwise built-in scan) + Performance scan + Anti-pattern scan → QA regression → Synthesis with PASS/PASS_WITH_NOTES/BLOCKED verdict → Structured reporting with timestamped artifacts. JSONL audit logging to `$DEVKIT_PROJECT_DIR/plans/audit-logs/audit-<run_id>.jsonl`. | opus-4-6 | 7 |
| **sync** | 3.0.0 | Detect changes (recent/full) → Detect undocumented env vars → Librarian review with CURRENT/UPDATES_NEEDED verdict → Apply updates → User verification with git diff → Archive review. | claude-sonnet-4-6 | 6 |
| **receiving-code-review** | 1.0.0 | Code review reception discipline: 6-step response pattern (READ through IMPLEMENT), anti-performative-agreement, YAGNI enforcement, source-specific handling, pushback guidelines. Reference archetype. | claude-sonnet-4-6 | Reference |
| **verification-before-completion** | 1.0.0 | Evidence-before-claims gate: 5-step verification (IDENTIFY, RUN, READ, VERIFY, CLAIM). Requires fresh test/build output before any completion claim. Red flags, rationalization table, key patterns for TDD and bug fixes. Reference archetype. | claude-sonnet-4-6 | Reference |
| **compliance-check** | 1.0.0 | Validate codebase against code-level compliance signals for regulatory frameworks (FedRAMP, FIPS, OWASP, SOC 2). Scoped to source code analysis only — not a compliance certification. | opus-4-6 | 5 |
| **dependency-audit** | 1.1.0 | Supply chain security audit — coordinates real CLI vulnerability scanners (npm audit, pip-audit, govulncheck, cargo audit, etc.) and synthesizes findings with license compliance, structured supply chain risk criteria with GitHub metadata, and risk assessment. | claude-sonnet-4-6 | 8 |
| **secrets-scan** | 1.1.0 | Pre-commit secrets detection with pattern-based scanning for API keys, tokens, passwords, private keys, connection strings, and insecure defaults detection. Self-contained — no external tools required. | claude-sonnet-4-6 | 6 |
| **secure-review** | 1.2.0 | Deep semantic security review of code changes with data flow tracing, taint analysis, trust boundary validation, blast radius assessment, codebase sizing, and regression detection. When invoked with plan context (e.g., by /ship Step 4d), includes a `## Threat Model Coverage` section mapping findings against threat model requirements. Composable building block invoked by /audit when deployed. | opus-4-6 | 5 |
| **threat-model-gate** | 1.1.0 | Use when planning security-sensitive features — authentication, authorization, data handling, API design, cryptography, or network configuration — requires explicit threat modeling before implementation decisions are made. Includes DREAD reference and cross-reference to threat-model skill. Reference archetype. | claude-sonnet-4-6 | Reference |
| **fix** | 1.0.0 | Targeted finding remediation — parse a specific finding from a review artifact (/ship or /audit), dispatch a scoped coder, run focused verification (security re-scan, code review, or tests), and commit with traceability back to the source finding. Supports `--dry-run`. Lightweight alternative to full /architect → /ship for single-finding fixes. | opus-4-6 | 5 |
| **input-validation-injection** | 1.0.0 | Injection prevention reference: SQL, LDAP, OS command, prototype pollution, ReDoS. Knowledge-base from prodsec-skills. | N/A | Knowledge-base |
| **client-side-security** | 1.0.0 | Browser security reference: XSS (5 contexts), CSP, CSRF, XS-Leaks, Trusted Types, security headers. Knowledge-base from prodsec-skills. | N/A | Knowledge-base |
| **ai-code-review** | 1.0.0 | AI-generated code review: hallucinated APIs, plausible-but-wrong logic, pattern drift, stale dependencies. Knowledge-base from prodsec-skills. | N/A | Knowledge-base |
| **semgrep** | 1.0.0 | Semgrep static analysis orchestration: auto-language detection, 30+ rulesets, SARIF output, Semgrep Pro support. Knowledge-base from prodsec-skills. | N/A | Knowledge-base |
| **build-yaml-misconfiguration** | 1.0.0 | CI/CD pipeline security: GitLab CI, Tekton, Containerfile hardening across 18+ misconfiguration categories. Knowledge-base from prodsec-skills. | N/A | Knowledge-base |
| **container-hardening** | 1.0.0 | Container image and runtime security: non-root, read-only filesystem, capability restrictions, UBI base images. Knowledge-base from prodsec-skills. | N/A | Knowledge-base |
| **threat-model** | 1.0.0 | Full STRIDE+DREAD threat modeling with OTM v0.2.0 JSON output, MITRE ATT&CK mapping, three-phase methodology. Knowledge-base from prodsec-skills. Includes reference/ subdirectory. | N/A | Knowledge-base |

### Contrib Skills (contrib/)

| Skill | Version | Purpose | Prerequisites | Steps |
|-------|---------|---------|--------------|-------|
| **journal** | 1.0.0 | Write entries to Obsidian work journal (daily logs, meetings, projects, learnings, decisions, biweekly leadership updates). Pipeline archetype with embedded templates, on-disk override, path sanitization, append semantics. | `~/journal/` vault with Obsidian structure | 6 |
| **journal-recall** | 1.0.0 | Search and retrieve past journal entries (date lookup, keyword search, weekly review, project status). Pipeline archetype with multi-mode retrieval. | Same `~/journal/` vault as journal skill | 4 |
| **journal-review** | 1.0.0 | Periodic review of daily entries — surfaces unlogged decisions, learnings, untracked action items, and recurring themes for promotion to formal entries. Pipeline archetype with interactive approval. | Same `~/journal/` vault as journal skill | 6 |

**Deployment:**
- Core skills: `./scripts/deploy.sh` (default)
- Contrib skills: `./scripts/deploy.sh --contrib [name]`
- See `contrib/README.md` for prerequisites and usage

## Security Maturity Levels

The `/ship` skill implements a three-level security model for progressive enforcement:

| Level | Name | Behavior | Use Case |
|-------|------|----------|----------|
| **L1** | Advisory | Security scans run and report findings. BLOCKED verdicts auto-downgrade to PASS_WITH_NOTES with prominent warnings. Workflow continues. | Default for all projects. Early-stage development, prototypes, teams ramping up security practices. |
| **L2** | Enforced | Security BLOCKED verdicts stop the workflow. Override available via `--security-override "reason"`. Override reason is logged. | Production codebases with security requirements. Teams enforcing security standards. |
| **L3** | Audited | Same as L2, but all overrides are logged to audit trails for compliance review. | Regulated environments (FedRAMP, HIPAA, SOC 2, PCI-DSS). Compliance-driven teams. |

**Configuration:**

Set the security maturity level in `.claude/settings.json` or `.claude/settings.local.json`:

```json
{
  "security_maturity": "L1"
}
```

**Security Gates:**

The `/ship` skill runs four security gates when the corresponding skills are deployed:

0. **Plan security requirements check** (Step 1): Validates that security-sensitive plans include a
   `## Security Requirements` section (derived from threat-model-gate output). At L1: warns if
   missing. At L2/L3: blocks if missing.

1. **Secrets scan** (Step 0 pre-flight): Runs `/secrets-scan` on working directory. BLOCKS at all
   maturity levels (committed secrets cannot be un-committed). Override available with
   `--security-override`.

2. **Secure review** (Step 4d verification): Runs `/secure-review` on uncommitted changes. At L1:
   BLOCKED auto-downgrades to PASS_WITH_NOTES. At L2/L3: BLOCKED stops workflow unless overridden.

3. **Dependency audit** (Step 6 commit gate): Runs `/dependency-audit` on manifest files. At L1:
   BLOCKED auto-downgrades to PASS_WITH_NOTES. At L2/L3: BLOCKED stops workflow unless overridden.

**Override Syntax:**

```bash
/ship $DEVKIT_PROJECT_DIR/plans/feature.md --security-override "False positive: hardcoded test API key in fixture file"
```

**Notes:**
- Security gates are conditional — only run if the corresponding skill is deployed
- At L2/L3, `/ship` pre-flight checks that all three security skills are deployed
- Missing skills at L1 log warnings; at L2/L3, missing skills block pre-flight
- Override reasons are logged for audit trails (especially important at L3)

## Audit Logging

`/ship`, `/architect`, and `/audit` emit structured JSONL audit events to `$DEVKIT_PROJECT_DIR/plans/audit-logs/` on every run, providing a machine-parseable record of what agents did and when.

**Event Types:**

| Event | When Emitted |
|-------|-------------|
| `run_start` | Beginning of every run |
| `run_end` | End of every run (success, failure, or blocked) |
| `step_start` / `step_end` | Beginning and end of each step |
| `verdict` | When a verdict gate is evaluated (PASS/FAIL/BLOCKED) |
| `security_decision` | When a security gate runs (secrets-scan, secure-review, dependency-audit) |
| `file_modification` | When files are merged from worktrees (per work group) |
| `error` | When a step fails unexpectedly |
| `run_score` | When a skill run completes and scores are computed (emitted immediately before `run_end`, on PASS path only) |
| `scanner_invocation` | When codebase-scanner.py runs during Step 1 context discovery; includes `output_token_count` field |

**Log File Locations:**

- `/ship` logs: `$DEVKIT_PROJECT_DIR/plans/audit-logs/ship-<run_id>.jsonl`
- `/architect` logs: `$DEVKIT_PROJECT_DIR/plans/audit-logs/architect-<run_id>.jsonl`
- `/audit` logs: `$DEVKIT_PROJECT_DIR/plans/audit-logs/audit-<run_id>.jsonl`

**Maturity-Aware Retention:**

| Level | Log Retention | HMAC Integrity |
|-------|--------------|----------------|
| **L1** (advisory) | Centralized only (`~/.claude-devkit/projects/<id>/`) — ephemeral, not in project | None |
| **L2** (enforced) | Centralized + copied to project `.devkit-audit-logs/` and committed via `git add --force` | None |
| **L3** (audited) | Centralized + copied to project + committed; HMAC chain with key persisted to `.ship-audit-key-<run_id>` | HMAC-SHA256 chain (post-run verifiable) |

**Query Utility:**

Requirements: `jq` (required for all commands), `openssl` (required for `verify-chain` HMAC verification).

```bash
# Show summary for a specific run
./scripts/audit-log-query.sh summary 20260327-143052-a1b2c3

# Show step timeline with computed durations
./scripts/audit-log-query.sh timeline 20260327-143052-a1b2c3

# Show security decisions
./scripts/audit-log-query.sh security 20260327-143052-a1b2c3

# Show all security overrides across all runs
./scripts/audit-log-query.sh overrides --all

# Show 5 most recent runs
./scripts/audit-log-query.sh recent 5

# Verify L3 HMAC chain integrity
./scripts/audit-log-query.sh verify-chain 20260327-143052-a1b2c3
```

**Implementation:**

- `scripts/emit-audit-event.sh` — Standalone helper script invoked by each skill step. Reads state from a per-run state file (shell variables don't persist across Bash tool calls). Uses `python3 json.dumps()` for RFC 8259 compliant escaping. Exits 0 on all error paths (never blocks `/ship`).
- `scripts/compute-run-score.sh` — Reads a run's JSONL audit log, computes per-dimension scores (efficiency, security, quality, velocity), outputs partial event JSON for `emit-audit-event.sh`. Now includes `scanner_mode` and `scanner_tokens` fields in the output JSON (consumed by `scanner-value-report.sh`). Exits 0 on all paths; handles empty, incomplete, and malformed logs gracefully (neutral 0.5 scores). No jq dependency.
- `scripts/score-reflector.sh` — Deterministic score reflector. Reads all `run_score` events from `$DEVKIT_PROJECT_DIR/plans/audit-logs/`, computes statistics and trends, correlates run scores with scanner mode cohorts, outputs candidate learnings entries to stdout for human review. Tiered analysis: 5-9 runs = summary stats, 10+ runs = trends. No jq dependency.
- `configs/audit-event-schema.json` — JSON Schema defining all event types with OTel field mapping documentation.
- `$DEVKIT_PROJECT_DIR/plans/audit-logs/` — Dedicated directory for audit logs (separate lifecycle from `$DEVKIT_PROJECT_DIR/plans/archive/`).

**OTel Migration:** The JSONL format is designed for future migration to OpenTelemetry spans via a format adapter. The adapter requires span hierarchy reconstruction (not a trivial field rename) and will be built when Kagenti provides an OTel collector endpoint.

## Quantitative Scoring

`/ship` v3.8.0+ emits a `run_score` event at the end of each successful run (immediately before `run_end`). Scores are computed from data already available in the JSONL audit log -- no LLM required.

**Scoring Dimensions:**

| Dimension | Weight | Source | Scoring Logic |
|-----------|--------|--------|---------------|
| **efficiency** | 0.3333 | `verdict` events with `verdict_source == "code_review"` | Count code_review verdicts. 1 verdict = 0 revision rounds = 1.0. 2 verdicts = 1 round = 0.6. 3 verdicts = 2 rounds = 0.2. Formula: `max(0.0, 1.0 - (count - 1) * 0.4)`. No events: 0.5 (neutral). |
| **security** | 0.3333 | `security_decision` events | Start 1.0. BLOCKED: -0.3, PASS_WITH_NOTES: -0.1, floor 0.0. No events: 0.5 (neutral). |
| **quality** | 0.3333 | `verdict` events (code_review + qa) | Start 1.0. First CR REVISION_NEEDED: -0.3, CR FAIL: -0.5. Last QA PASS_WITH_NOTES: -0.1, QA FAIL: -0.5, floor 0.0. No events: 0.5 (neutral). |
| **velocity** | 0.0 | `run_start.timestamp` to time of `run_score` emission | Duration in minutes. Informational only (not in composite). |

**Composite score** = normalized weighted sum of efficiency, security, quality (each effective weight 1/3). Velocity is excluded.

**Neutral score (0.5):** Used when a dimension has no data (e.g., no security skills deployed). Avoids artificially inflating or penalizing scores for missing data.

**Query commands:**

```bash
# Show per-dimension scores for a specific run
./scripts/audit-log-query.sh scores 20260327-143052-a1b2c3

# Show composite score trend for last 10 runs
./scripts/audit-log-query.sh trend

# Show efficiency trend for last 5 runs
./scripts/audit-log-query.sh trend 5 --dimension efficiency
```

**Score reflector (manual invocation):**

```bash
# Analyze score history and generate candidate learnings entries
bash scripts/score-reflector.sh

# With options
bash scripts/score-reflector.sh --min-runs 10 --format json
```

**Scanner value analysis (manual invocation):**

```bash
# Compare /ship run scores by scanner mode cohort (tree-sitter-partial vs regex-fallback vs absent)
bash scripts/scanner-value-report.sh

# JSON output
bash scripts/scanner-value-report.sh --format json
```

Thresholds and confidence tiers are configured in `configs/scanner-value-thresholds.json`. Analysis covers `/ship` runs only (the only skill that emits `run_score`). Reports require L2 or L3 maturity for meaningful cross-session data (L1 logs are ephemeral).

**Sample size thresholds for reflector analysis:**

| Runs Available | Analysis Level |
|----------------|---------------|
| < 5 | "Insufficient data" message (exit 0, no output) |
| 5-9 | Summary statistics only: per-dimension mean, min, max. No trend claims. |
| 10+ | Full analysis: summary statistics + linear regression trends (slope > 0.05/run threshold). |

**L1 ephemeral log limitation:** At L1 (advisory), JSONL audit logs exist only in the centralized directory (`~/.claude-devkit/projects/<id>/plans/audit-logs/`) and are not copied to the project. The `trend` command and `score-reflector.sh` can only analyze runs that still have log files on disk. For meaningful cross-session trend analysis, use L2 or L3 maturity (logs are copied to the project's `.devkit-audit-logs/` and committed to git). The tools display a notice when operating against ephemeral logs.

**Dimension definitions:** `configs/score-dimensions.json` — plain JSON data file documenting dimension weights, scoring logic, and design notes. Consumed by humans and future tooling (v1 dimensions are hardcoded in `compute-run-score.sh`).

## Shared Learnings Layer

Cross-project learnings aggregation, pattern detection, and promotion pipeline. Aggregates per-project `.claude/learnings.md` files into a central index, identifies recurring patterns across 3+ projects via tag-based correlation, and provides a promotion workflow for escalating patterns into concrete code changes.

**Architecture:**

```
~/.claude-devkit/learnings/
├── index.json           # Aggregated cross-project index (deterministic, rebuilt each run)
├── promotions.json      # Promotion lifecycle state (CANDIDATE -> PROPOSED -> APPROVED -> PROMOTED)
└── reports/
    └── mine-<timestamp>.md   # /retro mine output reports
```

**Components:**

| Component | Script | Purpose |
|-----------|--------|---------|
| Parser | `scripts/learnings_parser.py` | Parse `.claude/learnings.md` into structured entries |
| Aggregator | `scripts/learnings_aggregator.py` | Cross-project discovery, tag correlation, candidate detection |
| Promotions | `scripts/learnings_promotions.py` | Promotion lifecycle management (propose/approve/promote/reject) |
| CLI | `devkit learnings` | CLI access to aggregation and promotion pipeline |
| Skill | `/retro mine` | LLM-assisted proposal generation from candidates |

**Cross-project pattern detection (tag-based correlation):**

The aggregator counts distinct projects per tag. Tags appearing in 3+ projects become promotion candidates. This is the primary detection mechanism -- more reliable than title matching because independent projects use the same tags (`#qa`, `#security`, `#injection`) even when describing root causes with different titles. Secondary: exact title matches across projects (same normalized title in 3+ projects).

**Promotion types:**

| Type | Target | Description |
|------|--------|-------------|
| `skill_rule` | `skills/*/SKILL.md` | New validation rule, gate condition, or checklist item |
| `coder_prompt` | Agent templates or base definitions | Amendment to coder agent prompt |
| `reviewer_prompt` | Agent templates or base definitions | Amendment to reviewer agent prompt |
| `hook_config` | `.claude/settings.json` template | New hook or permission pattern |
| `validation_pattern` | `generators/validate_*.py` | New validation check |
| `learnings_template` | `templates/*.template` | New template content |

**Usage:**

```bash
# Run cross-project aggregation (deterministic, no LLM)
devkit learnings                          # Show summary
devkit learnings --format json            # Write index.json + print path

# Manage promotions
devkit learnings promotions               # List all promotions
devkit learnings promotions approve <promo-id>
devkit learnings promotions promote <promo-id> --commit <sha>
devkit learnings promotions reject <promo-id> --reason "..."

# LLM-assisted proposal generation (in Claude Code session)
/retro mine
```

**Security:**
- Learnings files are read-only to the aggregator (never writes into project repos)
- All writes confined to `~/.claude-devkit/learnings/` (directory 0o700, files 0o600)
- Symlinked discovery paths rejected (same check as `validate_target()`)
- Promo-IDs validated against `^promo-[0-9]{8}-[a-f0-9]{6}$`
- Commit SHAs validated against `^[a-f0-9]{7,40}$`
- Per-file read capped at 1MB
- Prompt injection countermeasure block in `/retro mine` LLM prompt
- Security-sensitive promotions flagged when targeting security-related files
- Actor identity recorded at each state transition (`proposed_by`, `approved_by`, `promoted_by`)
- `index.json` stores home-relative paths (not absolute)

## MCP Servers (Migrated)

**MIGRATION NOTICE:** As of 2026-02-24, all MCP servers have been migrated to the `helper-mcps` monorepo at `~/projects/workspaces/helper-mcps/`. The `mcp-servers/` directory in `claude-devkit` has been removed.

**Reason for migration:** MCP servers are containerized services with different deployment, testing, and lifecycle patterns than Claude Code skills. The `helper-mcps` monorepo provides:
- Shared library patterns (`BaseMCPServer`, `CredentialProvider`, lifecycle state machines)
- Consistent Docker multi-stage builds
- Unified testing infrastructure with 90% coverage enforcement
- Structured logging to stderr (avoiding stdio pollution)

**Migrated servers:**
- `redhat-browser-mcp` — Authenticated access to Red Hat internal documentation via Playwright browser automation with SSO. Includes URL validation with SSRF protection, content extraction pipeline, audit logging, and rate limiting.

**New location:**
```bash
cd ~/projects/workspaces/helper-mcps/redhat-browser-mcp/
```

**See:** `~/projects/workspaces/helper-mcps/CLAUDE.md` for complete MCP server documentation.

## Generator Registry

| Generator | Purpose | Output |
|-----------|---------|--------|
| **generate_skill.py** | Create new skill definitions from archetypes | `skills/<name>/SKILL.md` |
| **generate_agents.py** | Create all project agents (unified generator) | `.claude/agents/*` |
| **generate_senior_architect.py** | Deprecated wrapper for `generate_agents.py --type senior-architect` | `.claude/agents/senior-architect.md` |
| **validate_skill.py** | Validate skills against v2.0.0 patterns | Exit code 0/1/2 + validation report |
| **validate_agent.py** | Validate agents for inheritance patterns | Exit code 0/1/2 + validation report |

## Template Registry

| Template | Purpose | Archetype | Use Case |
|----------|---------|-----------|----------|
| **skill.md.template** | Base skill template | N/A | Starting point for custom skills |
| **skill-coordinator.md.template** | Coordinator workflow | Coordinator | Multi-agent delegation, revision loops |
| **skill-pipeline.md.template** | Pipeline workflow | Pipeline | Sequential validation checkpoints |
| **skill-scan.md.template** | Scan workflow | Scan | Parallel analysis, severity ratings |
| **claude-md-security-section.md.template** | Security section for project CLAUDE.md | N/A | Project bootstrapping |

### Agent Templates (templates/agents/)

| Template | Purpose | Inherits From |
|----------|---------|---------------|
| **coder-specialist.md.template** | Code implementation specialist | coder-base.md v2.1.0 |
| **qa-engineer-specialist.md.template** | Testing and validation specialist | qa-engineer-base.md v1.8.0 |
| **code-reviewer-standalone.md.template** | Standalone code reviewer | N/A (standalone) |
| **code-reviewer-specialist.md.template** | Specialist code reviewer | code-reviewer-base.md v1.0.0 |
| **security-analyst.md.template** | Threat modeling and security | architect-base.md v1.5.0 |
| **senior-architect.md.template** | High-level design and planning | architect-base.md v1.5.0 |

## Quick Start

### 1. Install

```bash
# Automated installation (recommended)
cd ~/projects/claude-devkit
./scripts/install.sh

# Reload shell
source ~/.zshrc  # or source ~/.bashrc

# Verify installation
which gen-skill gen-agent validate-skill
```

**What install.sh Does:**
- Auto-detects shell (zsh or bash)
- Exports `CLAUDE_DEVKIT` environment variable (also used by skills to locate `codebase-scanner.py`)
- Adds generators to your PATH
- Creates convenient aliases (gen-skill, gen-agent, validate-skill, etc.)
- Backs up your shell config before making changes
- Creates optional tree-sitter venv at `~/.claude-devkit/scanner-venv/` for high-fidelity symbol
  extraction (falls back to regex if unavailable)

**Manual Installation (Alternative):**
```bash
# Add to ~/.zshrc or ~/.bashrc
export CLAUDE_DEVKIT="$HOME/projects/claude-devkit"
export PATH="$PATH:$CLAUDE_DEVKIT/generators"

# Aliases
alias gen-skill='python $CLAUDE_DEVKIT/generators/generate_skill.py'
alias gen-agent='python $CLAUDE_DEVKIT/generators/generate_agents.py'
alias gen-architect='python $CLAUDE_DEVKIT/generators/generate_agents.py --type senior-architect'
alias validate-skill='python $CLAUDE_DEVKIT/generators/validate_skill.py'
alias validate-agent='python $CLAUDE_DEVKIT/generators/validate_agent.py'
alias deploy-skills='cd $CLAUDE_DEVKIT && ./scripts/deploy.sh'

# Reload
source ~/.zshrc
```

### 2. Deploy Skills

```bash
cd ~/projects/claude-devkit
./scripts/deploy.sh           # Deploy all skills
./scripts/deploy.sh architect     # Deploy one skill
```

### 3. Generate Your First Agent

```bash
cd ~/projects/my-app
gen-agent . --type all  # Generate all agents (auto-detects stack)
# Or: gen-agent . --type coder --tech-stack "Next.js TypeScript"
```

### 4. Use Skills

```bash
# In any Claude Code session
/architect add user authentication
/ship $DEVKIT_PROJECT_DIR/plans/add-user-authentication.md
/audit
/sync
```

### 5. Use the Meta-Harness (Optional)

The `devkit` CLI lets you target and run skills against any registered git repository
from outside that project -- no `cd` required. See Integration Patterns > With
Meta-Harness for the full model.

```bash
# Initialize a project for devkit management
devkit init ~/projects/my-app

# Run skills from anywhere
devkit audit ~/projects/my-app
devkit architect ~/projects/my-app "add feature"

# Run a skill in the background (detached execution)
devkit architect ~/projects/my-app "add feature" --detach
# Returns a run ID immediately, e.g.: 20260821-143052-a1b2c3

# Check background run status
devkit jobs                         # List all runs
devkit result 20260821-143052-a1b2c3  # Print result
devkit logs 20260821-143052-a1b2c3    # Print stderr logs
devkit clean --days 14              # Remove old completed runs

# Open interactive session
devkit shell ~/projects/my-app

# Open multi-target interactive session (cross-repo planning)
devkit shell ~/projects/my-app --with ~/projects/cve-api

# Check status of all managed projects
devkit status

# Pass skill flags through with the `--` separator (everything after `--` is
# forwarded verbatim, bypassing the flag-injection guard on skill args)
devkit architect ~/projects/my-app "add feature" -- --fast
devkit architect ~/projects/my-app "add feature" --detach -- --fast
devkit ship ~/projects/my-app $DEVKIT_PROJECT_DIR/plans/feature.md -- --security-override "reason"

# Cross-repo planning (multi-target architect)
devkit architect ~/projects/my-app "integrate with cve-api" --with ~/projects/cve-api

# Plan lifecycle management
devkit plan list ~/projects/my-app
devkit plan show ~/projects/my-app integrate-cve-api
devkit plan resolve devkit://cve-api-f25db5e61a87/plans/add-v2-endpoint.md
```

## Complete Workflows

### Workflow 1: Feature Development (Full Lifecycle)

```bash
# 1. Plan the feature
/architect add shopping cart functionality

# 2. Optional: Audit the plan before implementation
/audit plan $DEVKIT_PROJECT_DIR/plans/add-shopping-cart.md

# 3. Implement the plan
/ship $DEVKIT_PROJECT_DIR/plans/add-shopping-cart.md

# 4. Update documentation
/sync

# 5. Final security and performance audit
/audit
```

**Artifacts Created:**
- `$DEVKIT_PROJECT_DIR/plans/add-shopping-cart.md` — Approved implementation plan
- `$DEVKIT_PROJECT_DIR/plans/add-shopping-cart.redteam.md` — Red team review
- `$DEVKIT_PROJECT_DIR/plans/add-shopping-cart.feasibility.md` — Feasibility review
- `$DEVKIT_PROJECT_DIR/plans/add-shopping-cart.review.md` — Librarian review
- `$DEVKIT_PROJECT_DIR/plans/archive/add-shopping-cart/` — Code review and QA reports
- `$DEVKIT_PROJECT_DIR/plans/audit-[timestamp].summary.md` — Final audit results
- `CLAUDE.md` — Updated with new patterns

**Security Gates:**

If security skills are deployed, `/ship` runs three security gates:
- **Step 0 (pre-flight):** `/secrets-scan` checks for committed secrets
- **Step 4d (verification):** `/secure-review` analyzes code changes for vulnerabilities
- **Step 6 (commit gate):** `/dependency-audit` scans for vulnerable dependencies

At L1 (advisory), BLOCKED verdicts show warnings but don't stop the workflow. At L2/L3 (enforced/audited), BLOCKED verdicts stop the workflow unless overridden with `--security-override "reason"`.

### Workflow 2: Security Audit (Existing Codebase)

```bash
# 1. Run comprehensive audit
/audit full

# 2. Review findings
cat $DEVKIT_PROJECT_DIR/plans/audit-[timestamp].summary.md

# 3. Address critical issues
# ... make fixes ...

# 4. Re-audit
/audit code

# 5. Update docs with security patterns
/sync
```

**Artifacts Created:**
- `$DEVKIT_PROJECT_DIR/plans/audit-[timestamp].summary.md` — Audit summary with verdict
- `$DEVKIT_PROJECT_DIR/plans/audit-[timestamp].security.md` — Security findings
- `$DEVKIT_PROJECT_DIR/plans/audit-[timestamp].performance.md` — Performance findings
- `$DEVKIT_PROJECT_DIR/plans/audit-[timestamp].qa.md` — QA regression results
- `$DEVKIT_PROJECT_DIR/plans/archive/audit/audit-[timestamp]/` — Archived reports

### Workflow 3: Documentation Sync (Weekly Maintenance)

```bash
# 1. Sync with recent changes
/sync

# 2. Review proposed updates
git diff CLAUDE.md

# 3. Commit if approved
git add CLAUDE.md
git commit -m "Update CLAUDE.md with recent patterns"

# 4. Or sync all files (full mode)
/sync full
```

**Artifacts Created:**
- `$DEVKIT_PROJECT_DIR/plans/sync-[timestamp].review.md` — Librarian review
- `CLAUDE.md` — Updated with current patterns
- `README.md` — Updated usage docs (if needed)
- `$DEVKIT_PROJECT_DIR/plans/archive/sync/sync-[timestamp].review.md` — Archived review

### Workflow 4: Creating New Skills

```bash
# 1. Generate skill scaffold
gen-skill deploy-check \
  --description "Verify deployment health" \
  --archetype pipeline \
  --deploy

# 2. Customize the skill
code ~/projects/claude-devkit/skills/deploy-check/SKILL.md
# Replace [TODO: ...] placeholders with actual logic

# 3. Validate
validate-skill ~/projects/claude-devkit/skills/deploy-check/SKILL.md

# 4. Redeploy
cd ~/projects/claude-devkit
./scripts/deploy.sh deploy-check

# 5. Test
/deploy-check production
```

**Generated:**
- `skills/deploy-check/SKILL.md` — Validated skill definition
- `~/.claude/skills/deploy-check/SKILL.md` — Deployed skill

### Workflow 5: Creating Project Architects

```bash
# 1. Auto-detect project type
cd ~/projects/shop-frontend
gen-architect .

# 2. Or specify type explicitly
gen-architect . --project-type "Next.js 14 TypeScript Tailwind Stripe"

# 3. Customize for domain
code .claude/agents/senior-architect.md
# Add e-commerce patterns, Stripe integration, etc.

# 4. Test
/exit
claude-code
> Use senior-architect to plan a checkout flow
```

**Generated:**
- `.claude/agents/senior-architect.md` — Local architect agent

## Skill Architectural Patterns (v2.0.0)

All skills follow these 10 patterns:

| Pattern | Description | Enforcement |
|---------|-------------|-------------|
| **1. Coordinator** | Skills coordinate work, don't execute directly | Role section with delegation language |
| **2. Numbered steps** | Explicit workflow progression | `## Step N -- [Action]` headers |
| **3. Tool declarations** | Each step specifies tools | `Tool:` line in every step |
| **4. Verdict gates** | Control flow with PASS/FAIL/BLOCKED | Verdict logic in steps |
| **5. Timestamped artifacts** | All outputs include ISO timestamps | `[timestamp]` references |
| **6. Structured reporting** | Consistent markdown format | Outputs to `$DEVKIT_PROJECT_DIR/plans/` |
| **7. Bounded iterations** | Max revision loops prevent cycles | `Max N revision` language |
| **8. Model selection** | Right model for each task | Valid `model:` in frontmatter |
| **9. Scope parameters** | Flexible invocation | `## Inputs` with `$ARGUMENTS` |
| **10. Archive on success** | Move artifacts after completion | References `$DEVKIT_PROJECT_DIR/plans/archive/` |
| **11. Worktree isolation** | Structural conflict prevention for parallel work | Git worktrees per work unit with validation |

### Archetype Patterns

#### Coordinator Pattern (like `/architect`)

**Characteristics:**
- Delegates core work to specialist agents
- Runs parallel quality reviews
- Bounded revision loops (max 2 rounds)
- Verdict gates block progression on failures
- Archives approved artifacts

**Use Cases:**
- Planning and design
- Research and analysis
- Multi-agent workflows
- Document review and approval

**Note:** Coordinators may perform non-blocking git commits for artifact durability (e.g., /architect auto-commits plan artifacts after verdict). Commit failures must never alter the verdict outcome.

**Example Structure:**
```markdown
## Step 0 — Context discovery (read project context)
Tool: Read

## Step 1 — Main work (delegate to agent)
Tool: Task (via .claude/agents/ if found, otherwise subagent_type=general-purpose)

## Step 2 — Parallel quality reviews (3 agents)
Tool: Task (multiple subagents in parallel: red team + librarian + feasibility)

## Step 3 — Revision loop (max 2 iterations)
Tool: Same agent from Step 1

## Step 4 — Approval gate
**If PASS:** Archive artifacts, report success
**If FAIL:** Report blocking issues
```

#### Pipeline Pattern (like `/ship`)

**Characteristics:**
- Sequential execution with checkpoints
- Pre-flight environment checks
- Implementation → Review → Test → Deploy
- Bounded revision loops between stages
- Commit gate at the end

**Use Cases:**
- Code implementation
- Testing and validation
- Deployment pipelines
- Sequential workflows with gates

**Example Structure:**
```markdown
## Step 0 — Pre-flight checks
Tool: Bash

## Step 1 — Read and validate input
Tool: Read

## Step 2 — Pattern validation (warnings only)
Tool: Grep, Read

## Step 3 — Main implementation
Tool: Task (via .claude/agents/ if found, otherwise subagent_type=general-purpose)

## Step 4 — Code review
Tool: Sonnet model

## Step 5 — Revision loop (max 2 iterations)
Tool: Same agent from Step 3

## Step 6 — Run tests
Tool: Bash

## Step 7 — Commit gate
**If PASS:** Commit with proper format
**If FAIL:** Report what blocked commit
```

#### Scan Pattern (like `/audit`)

**Characteristics:**
- Determines scan scope (plan, code, full)
- Runs parallel analysis tasks
- Synthesizes results with severity ratings
- Verdict based on risk score
- Archives all reports

**Use Cases:**
- Security audits
- Code quality scans
- Dependency analysis
- Risk assessments

**Example Structure:**
```markdown
## Step 0 — Detect scope
Tool: Glob, Read

## Step 1 — Parallel scans
Tool: Task (multiple subagents in parallel)

## Step 2 — Synthesis
Tool: Orchestrator (current agent)

## Step 3 — Verdict gate
**If Critical issues:** BLOCKED
**If High issues:** PASS_WITH_NOTES
**If Low/None:** PASS

## Step 4 — Archive
Tool: Bash (move to archive/)
```

#### Worktree Isolation Pattern (like `/ship` v3.1.0+)

**Characteristics:**
- Creates isolated git worktrees per parallel work unit
- Agents work in separate filesystems (structural conflict prevention)
- Validates file boundaries post-execution
- Merges only scoped files to main tree
- Cleans up worktrees after completion

**Use Cases:**
- Parallel implementation work groups
- Preventing file conflicts in multi-agent workflows
- Isolated testing environments
- Revision loops with guaranteed file scope

**Example Structure:**
```markdown
## Step 2a — Shared Dependencies
Tool: Task (single coder), then Bash (commit to HEAD)

## Step 2b — Create Worktrees
Tool: Bash (git worktree add per work group)

## Step 2c — Dispatch Coders
Tool: Task (multiple coders in parallel, each in own worktree)

## Step 2d — File Boundary Validation
Tool: Bash (git diff per worktree, verify modified ⊆ scoped)
**If violations:** BLOCK workflow

## Step 2e — Merge Worktrees
Tool: Bash (copy scoped files to main tree)

## Step 2f — Cleanup
Tool: Bash (git worktree remove, delete temp files)
```

**Benefits:**
- **Structural guarantees** — Agents physically cannot modify files outside their worktree
- **Validation safety net** — Detects violations even if worktree boundaries are bypassed
- **Universal isolation** — Every `/ship` run uses worktree isolation, regardless of work group count
- **Resilient** — Failed cleanup doesn't block workflow (`git worktree prune` recovers)

**When to use:**
- All `/ship` implementations use worktree isolation by default (v3.3.0+)
- Plans with multiple work groups that modify different file sets benefit from parallel worktrees
- Teams requiring audit trails of which agent modified which files

**When NOT to use:**
- Read-only operations (no conflict risk)
- Tightly coupled files that must be modified together (use single work group instead)

#### Knowledge-Base Pattern (prodsec-skills integration)

**Characteristics:**
- Tool-agnostic reference materials (not executable workflows)
- Domain-specific security knowledge, checklists, and methodologies
- Imported from Red Hat Product Security's prodsec-skills repository
- Loaded as context by other skills or directly by users
- No model, steps, tools, or verdict gates

**Use Cases:**
- Security review context (load alongside /secure-review or /audit)
- Developer reference during implementation
- Code review checklists
- Standalone security analysis methodology

**Frontmatter:**
```yaml
---
name: skill-name
description: Invocation condition description.
type: knowledge-base
version: 1.0.0
attribution: "Red Hat Product Security, prodsec-skills repository"
---
```

**Example usage:**
```
Using skills/input-validation-injection/SKILL.md: review this endpoint for injection risks.
Using skills/threat-model/SKILL.md: perform a threat model for the authentication subsystem.
```

**`threat-model-gate` vs `threat-model`:** These serve different purposes and have different invocation patterns.
`threat-model-gate` is a **planning gate** (behavioral discipline, `type: reference`) -- it is invoked automatically by `/architect` Stage 2 and checked by `/ship` Step 1 to ensure threat modeling happens before implementation. Users do not invoke it directly.
`threat-model` is a **standalone methodology** (domain knowledge, `type: knowledge-base`) -- it provides full STRIDE+DREAD+OTM threat modeling methodology for hands-on threat modeling sessions.

Knowledge-base skills are loaded as context, not invoked as slash commands. Use:
```
Using skills/threat-model/SKILL.md: perform a threat model for this system.
```
Do not attempt `/threat-model` -- knowledge-base skills have no workflow steps to execute.

## Artifact Locations

```
$DEVKIT_PROJECT_DIR/plans/              # ~/.claude-devkit/projects/<project-id>/plans/
├── [feature].md                           # Plans from /architect
├── [feature].redteam.md                   # Red team reviews
├── [feature].feasibility.md               # Feasibility reviews
├── [feature].review.md                    # Librarian reviews
├── audit-[timestamp].summary.md           # Audit summaries
├── audit-[timestamp].security.md          # Security scan results
├── audit-[timestamp].performance.md       # Performance scan results
├── audit-[timestamp].qa.md                # QA regression results
├── audit-[timestamp].antipatterns.md      # Anti-pattern scan results
├── sync-[timestamp].review.md             # Documentation reviews
├── retro-[timestamp].coder-scan.md        # Coder calibration scan (from /retro)
├── retro-[timestamp].reviewer-scan.md     # Reviewer calibration scan (from /retro)
├── retro-[timestamp].test-scan.md         # Test pattern scan (from /retro)
├── retro-[timestamp].summary.md           # Retro summary with verdict
├── audit-logs/                            # JSONL audit event logs (queryable across runs)
│   ├── ship-[run_id].jsonl                # /ship run audit log (L2/L3: copied to project for git)
│   ├── architect-[run_id].jsonl           # /architect run audit log
│   └── audit-[run_id].jsonl              # /audit run audit log
└── archive/
    ├── [feature]/
    │   ├── [feature].code-review.md       # Code review (from /ship)
    │   ├── [feature].secure-review.md     # Secure review (from /ship Step 4d; may include ## Threat Model Coverage section when invoked with plan context)
    │   └── [feature].qa-report.md         # QA report (from /ship)
    ├── sync/
    │   └── sync-[timestamp].review.md     # Archived sync reviews
    ├── audit/
    │   └── audit-[timestamp]/             # Archived audit reports
    ├── retro/
    │   └── retro-[timestamp]/             # Archived retro reports
    └── fix/
        ├── fix-[finding-id]-[timestamp].code-review.md           # Code review (from /fix)
        ├── fix-[finding-id]-[timestamp]-reverify.secure-review.md  # Security re-scan (from /fix, security findings)
        └── fix-[finding-id]-[timestamp]-reverify.security-review.md # Fallback security review (from /fix, no /secure-review deployed)
```

`.claude/learnings.md` — Project-level learnings (lives in the project directory, created by `/retro` and `/ship` Step 7)

## Development Rules

### For Skills

1. **Edit source, not deployment** — Edit `skills/*/SKILL.md` or `contrib/*/SKILL.md`, not `~/.claude/skills/*/SKILL.md`
2. **Validate before committing** — Run `validate-skill skills/<name>/SKILL.md` or `validate-skill contrib/<name>/SKILL.md`
3. **Test before committing** — Use the skill in Claude Code to verify behavior
4. **Update registry** — When adding/changing skills, update CLAUDE.md registry
5. **Follow v2.0.0 patterns** — Use all 10 architectural patterns
6. **One skill per directory** — Each skill is `skills/<name>/SKILL.md` or `contrib/<name>/SKILL.md`
7. **Core vs Contrib** — Core skills (`skills/`) are universal and deploy to all users. Contrib skills (`contrib/`) require user-specific setup and are opt-in. Use `contrib/` for personal/opinionated workflows (e.g., journal system with hardcoded paths).

### For Generators

1. **Use atomic writes** — Write to temp file, rename on success
2. **Validate all inputs** — Sanitize and validate before file operations
3. **Rollback on failure** — Clean up partial artifacts
4. **Document templates** — Add comments explaining placeholders
5. **Test thoroughly** — Run test suite before committing

### For Templates

1. **Use descriptive placeholders** — `{project_name}`, `{stack_type}`, not `{X}`, `{Y}`
2. **Document placeholders** — Include comment block listing all placeholders
3. **Validate generated output** — Ensure generator + template passes validation
4. **Include metadata** — Add generation timestamp and version

## Directory Reference

### /skills

Source of truth for **core skill definitions** (deployed to all users). Each skill is a directory with `SKILL.md`.

**Structure:**
```
skills/
├── architect/SKILL.md
├── ship/SKILL.md
├── retro/SKILL.md
├── audit/SKILL.md
├── sync/SKILL.md
├── receiving-code-review/SKILL.md
├── verification-before-completion/SKILL.md
├── compliance-check/SKILL.md
├── dependency-audit/SKILL.md
├── secrets-scan/SKILL.md
├── secure-review/SKILL.md
├── threat-model-gate/SKILL.md
├── fix/SKILL.md
├── input-validation-injection/SKILL.md
├── client-side-security/SKILL.md
├── ai-code-review/SKILL.md
├── semgrep/SKILL.md
├── build-yaml-misconfiguration/SKILL.md
├── container-hardening/SKILL.md
└── threat-model/SKILL.md          # Also includes reference/ subdirectory
```

**Frontmatter Format:**
```yaml
---
name: skill-name
description: One-line description.
model: claude-opus-4-6
version: 2.0.0
---
```

### /contrib

**Optional/personal skills** requiring user-specific setup (opt-in deployment). Same structure as `/skills`, but not deployed by default.

**Structure:**
```
contrib/
├── journal/SKILL.md           # Obsidian journal writing
├── journal-recall/SKILL.md    # Journal search/retrieval
└── README.md                  # Prerequisites and usage
```

**When to use contrib:**
- Skills requiring user-specific paths (e.g., `~/journal/`)
- Opinionated workflows not suitable for all developers
- Personal productivity tools
- Skills that need local configuration

**Deployment:**
```bash
./scripts/deploy.sh --contrib journal    # Deploy one contrib skill
./scripts/deploy.sh --contrib            # Deploy all contrib skills
./scripts/deploy.sh --all                # Deploy core + contrib
```

### /generators

Python scripts for code generation with validation and atomic writes.

**Scripts:**
- `generate_skill.py` — Create skills from archetypes
- `generate_agents.py` — Create all project agents (unified generator)
- `generate_senior_architect.py` — Deprecated wrapper around `generate_agents.py --type senior-architect`
- `validate_skill.py` — Validate skill definitions
- `validate_agent.py` — Validate agents for inheritance patterns
- `test_skill_generator.sh` — Test suite (66 tests)

**Capabilities:**
- Auto-detection (project type, stack)
- Interactive prompts or CLI flags
- Atomic file operations
- Automatic validation
- Optional deployment

### /templates

Reusable templates with placeholder substitution.

**Templates:**
- `skill-coordinator.md.template` — Coordinator archetype
- `skill-pipeline.md.template` — Pipeline archetype
- `skill-scan.md.template` — Scan archetype

**Placeholder Format:**
- `{project_name}` — Project name
- `{stack_type}` — Technology stack
- `{description}` — Skill description
- `{timestamp}` — ISO timestamp

### /configs

Shared configurations and pattern definitions.

**Contents:**
- `skill-patterns.json` — Validation patterns
- `scanner-languages.json` — Language grammar configuration for codebase scanner (extensions, tree-sitter queries, package versions for Python, TypeScript, Java, Go)
- `scanner-value-thresholds.json` — Confidence tier configuration for scanner value analysis (INSUFFICIENT/PRELIMINARY/RELIABLE/HIGH_CONFIDENCE thresholds)
- `devkit-defaults.json` — Default configuration for the meta-harness CLI (registry path, `allowed_roots`, `claude` command/flag, size limits, `clean_retention_days` for detached run cleanup, `scripts_dir_name`, `max_cross_repo_targets` for cross-repo plan limits). Loaded by `scripts/devkit_cli.py` at startup; hardcoded fallback defaults are used if missing or corrupt.
- `tech-stack-definitions/` — Stack-specific configs (7 stacks: python, fastapi, typescript, react, nextjs, astro, security)
- `base-definitions/` — Reserved for future use (currently empty)

### /scripts

Deployment and utility scripts.

**Scripts:**
- `deploy.sh` — Deploy skills to `~/.claude/skills/` (core and/or contrib)
- `install.sh` — Automated installation (PATH, aliases, shell config)
- `uninstall.sh` — Clean uninstallation with backup restoration
- `validate-all.sh` — Health check - validate all skills in one pass
- `codebase-scanner.py` — Deterministic codebase symbol index for agent context. Extracts functions, classes, methods, and import graph. Uses tree-sitter (>=0.25.0) when available in `~/.claude-devkit/scanner-venv/`, falls back to regex. Invoked by `/architect` Step 1 and `/ship` Step 1. Tree-sitter venv created by `install.sh`.
- `devkit_cli.py` — Meta-harness CLI implementation (Python 3.8+, stdlib only). Validates target repositories and skill names, manages per-project state (`~/.claude-devkit/projects/<project-id>/state.json`) and the global registry (`~/.claude-devkit/registry.json`), and delegates skill execution to Claude Code via `subprocess.run(["claude", "--print", ...])` (or `os.execvp` for `devkit shell`). Sets `DEVKIT_PROJECT_DIR`, `DEVKIT_SCRIPTS`, and `DEVKIT_TARGET_*` env vars before invocation. Supports detached/background execution (`--detach`) with run output capture to `~/.claude-devkit/runs/`. Multi-target support via `--with` flag for cross-repo planning. `devkit plan` subcommand for plan lifecycle management (list, show, validate, sync, resolve, archive). Reads defaults from `configs/devkit-defaults.json` with hardcoded fallback.
- `devkit` — Thin bash entry point wrapper that execs `devkit_cli.py` with `python3`. Installed as a shell alias and added to PATH by `install.sh`.
- `emit-audit-event.sh` — Standalone helper script for skill audit event emission (invoked by `/ship`, `/architect`, `/audit`)
- `audit-log-query.sh` — Query utility for JSONL audit logs (summary, timeline, security, verdicts, files, overrides, verify-chain, recent, scores, trend)
- `compute-run-score.sh` — Compute per-dimension quantitative scores from a JSONL audit log (python3, no jq)
- `score-reflector.sh` — Deterministic score reflector for candidate learnings generation (python3, no jq)
- `scanner-value-report.sh` — Scanner value analysis: cohort comparison of /ship run scores by scanner mode (tree-sitter-partial vs regex-fallback vs absent). No jq dependency.
- `ship-queue.sh` — Sequential `/ship` runner for unattended batch execution via `devkit ship`. Clean-tree gates between runs prevent cascading failures.
- `resolve-project-dir.sh` — Reusable shell function for three-tier project artifact directory resolution (`DEVKIT_PROJECT_DIR` env var > computed from CWD > deprecated `.devkit/` fallback)
- `learnings_parser.py` — Deterministic learnings parser (Python 3.8+, stdlib only). Parses `.claude/learnings.md` files into structured entries with date, severity (case-insensitive, two positional variants), tags, seen-in, section hierarchy, and stable SHA-256 IDs. Size limit guard (1MB). Returns `(entries, warnings)` -- never raises on parse errors.
- `learnings_aggregator.py` — Cross-project learnings aggregator (Python 3.8+, stdlib only). Discovers learnings files via registry + allowed_roots scan (maxdepth=4), parses with `learnings_parser.py`, builds tag-based cross-project correlation, identifies promotion candidates (tags in 3+ projects). Writes `~/.claude-devkit/learnings/index.json` atomically. Skips symlinks, backup dirs, non-git dirs.
- `learnings_promotions.py` — Promotion lifecycle manager (Python 3.8+, stdlib only). Manages `~/.claude-devkit/learnings/promotions.json` state. Subcommands: propose, approve, promote, reject, list. Records actor identity at each transition. Validates promo-IDs (`^promo-[0-9]{8}-[a-f0-9]{6}$`) and commit SHAs (`^[a-f0-9]{7,40}$`). Flags security-sensitive promotions.
- `test-integration.sh` — Integration smoke tests (165 tests): emit-audit-event.sh JSONL correctness,
  L3 HMAC chain verification, 10+ call state persistence, end-to-end generate/validate/deploy
  lifecycle, threat model consumption structural tests across /ship, /architect, /secure-review,
  quantitative scoring tests (8 tests: 4 positive, 4 negative/edge cases),
  codebase-scanner integration tests (8 tests),
  scanner value instrumentation tests (5 tests),
  anti-pattern scan structural tests (6 tests),
  meta-harness tests (13 tests: 8 functional, 5 security -- symlink rejection, allowed_roots
  enforcement, oversized state file, invalid skill name, `--`-prefixed argument injection),
  detached execution tests (20 tests: run ID generation/validation, `--detach` flag
  extraction, watcher lifecycle with mock processes, jobs/result/logs commands, cleanup
  with stale PID detection, directory permissions, path traversal rejection, no shell=True),
  zero-project-footprint tests (38 tests: project ID determinism/uniqueness/case-normalization/
  sanitization, central storage, env var propagation, migration with rollback, helper script
  deployment with checksums, security permissions, relink/path commands, backward compatibility),
  cross-repo plan tests (29 tests: frontmatter parser, devkit:// URI resolution, plan refs,
  multi-target shell/dispatch, devkit plan subcommand, read_plan_refs, validate_plan_targets,
  cmd_path traversal protection, plan archive),
  and shared learnings layer tests (18 tests: parser 5, aggregator 4, promotions 4, CLI 3,
  security 2)

**Usage:**
```bash
# Deploy skills
./scripts/deploy.sh                    # Deploy all core skills (default)
./scripts/deploy.sh architect              # Deploy one core skill
./scripts/deploy.sh --contrib journal  # Deploy one contrib skill
./scripts/deploy.sh --contrib          # Deploy all contrib skills
./scripts/deploy.sh --all              # Deploy core + contrib
./scripts/deploy.sh --validate         # Validate before deploying (blocks on errors)
./scripts/deploy.sh --help             # Show usage

# Validate all skills
./scripts/validate-all.sh              # Health check - validate all skills

# Install/uninstall devkit
./scripts/install.sh          # Install claude-devkit
./scripts/uninstall.sh        # Uninstall claude-devkit
```

## Integration Patterns

### With Workspaces Architecture

Claude Devkit is a standalone tools repository within the workspaces ecosystem:

```
~/workspaces/
├── .config/agents/base/        # Base agents (universal)
├── claude-devkit/              # This repo (tools)
├── my-project/                 # Project (specialist agents)
└── CLAUDE.md                   # Workspaces docs
```

**Integration Points:**
- Skills invoke local `.claude/agents/` project agents via Glob, with Task subagent fallback
- Generators create specialist agents that inherit from base
- Projects reference skill patterns in their CLAUDE.md

### With Claude Code

Claude Devkit deploys skills to Claude Code's skill directory:

```
~/.claude/
└── skills/
    ├── architect/SKILL.md
    ├── ship/SKILL.md
    ├── audit/SKILL.md
    └── sync/SKILL.md
```

**Workflow:**
1. Edit `~/projects/claude-devkit/skills/*/SKILL.md`
2. Commit to git
3. Run `./scripts/deploy.sh`
4. Restart Claude Code (or continue session)
5. Use skills with `/<skill-name> [args]`

### Tool Permissions (Reducing Prompts)

Skills invoke many tools during execution (Read, Glob, Bash, Task, etc.), which can generate frequent permission prompts. A global allowlist in `~/.claude/settings.json` pre-authorizes trusted tool patterns so skills run with minimal interruption.

**Current allowlist** (in `~/.claude/settings.json`):

| Category | Patterns | Risk |
|----------|----------|------|
| **Read-only tools** | `Read`, `Glob`, `Grep`, `WebSearch`, `WebFetch` | None — cannot modify files |
| **Agent delegation** | `Task` | Low — spawns sub-agents |
| **File mutation** | `Edit`, `Write` | Medium — needed for agents writing plans, reviews, and code |
| **Git read** | `git status*`, `git log*`, `git diff*`, `git rev-parse*` | None |
| **Git write** | `git add*`, `git commit*`, `git push*`, `git reset --soft*` | Medium — /ship commit gate and squash |
| **Git worktree** | `git worktree*` | Low — /ship isolation |
| **Git general** | `git branch*`, `git checkout*`, `git stash*`, `git config*` | Low |
| **File management** | `mkdir*`, `mv *`, `cp *`, `rm -f *` | Low — artifact archival, worktree merges |
| **Test runners** | `npm test*`, `npm run*`, `npx*`, `pytest*`, `python3*` | Low — project test execution |
| **Utilities** | `ls*`, `which*`, `cat*`, `head*`, `tail*`, `sort*`, `grep*`, `chmod*`, `bash*` | Low |

**Still requires prompting** (not in allowlist):
- `rm -rf` (recursive delete)
- `curl`, `wget` (network calls from bash)
- `sudo` (privilege escalation)
- `docker` (container operations)
- Any unmatched bash command

**Maintaining the allowlist:**
- Edit `~/.claude/settings.json` directly
- Project-level overrides go in `.claude/settings.json` or `.claude/settings.local.json`
- Lists merge — project settings layer on top of global settings

### With Meta-Harness

The `devkit` CLI (`scripts/devkit_cli.py`) is an external orchestrator layer that lets
you target and run skills against any registered repository without first `cd`-ing
into it. It does not replace or reimplement skills -- it is a front door that sets
CWD correctly and delegates to Claude Code for actual execution.

```
devkit CLI  (scripts/devkit_cli.py)
  |
  +-- validate target path (git repo? no symlinks? under allowed_roots?)
  +-- validate skill name and args (reject flag-injection-shaped input)
  +-- compute project ID from resolved path (SHA-256 based)
  +-- read/create ~/.claude-devkit/projects/<project-id>/state.json
  +-- update ~/.claude-devkit/registry.json
  +-- check skill deployment (~/.claude/skills/<skill>/SKILL.md exists?)
  +-- set DEVKIT_PROJECT_DIR and DEVKIT_SCRIPTS env vars
  +-- set CLAUDE_DEVKIT env var
  |
  v
subprocess.run(["claude", "--print", "/<skill> <args>"], cwd=<resolved target>)
```

**Key model:**
- Skills remain plain `SKILL.md` files executed by Claude Code -- the harness never
  duplicates skill logic.
- Per-project state (`~/.claude-devkit/projects/<project-id>/state.json`) tracks the last
  invocation. It is informational only; no skill reads it.
- The global registry (`~/.claude-devkit/registry.json`) provides cross-project
  visibility (`devkit status`) but is never authoritative -- every access
  re-validates against the filesystem, and stale (deleted) paths are marked
  `[STALE]` rather than silently pruned.
- Existing security maturity levels (L1/L2/L3), security gates, and JSONL audit
  logging are unchanged -- they are implemented inside skills, not the harness.
- Target paths default to `~/projects/` and `~/workspaces/` (`allowed_roots` in
  `configs/devkit-defaults.json`), plus the devkit root and `/tmp/`. Symlinked
  targets and non-git directories are rejected.

**Commands:** `devkit init <target>`, `devkit <skill> <target> [args]`,
`devkit shell <target> [--with <target2> ...]`, `devkit status [<target>]`,
`devkit deploy [--validate]`, `devkit jobs [<target>]`, `devkit result <run-id>`,
`devkit logs <run-id>`, `devkit clean [--days N]`, `devkit migrate <target>`,
`devkit relink <old> <new>`, `devkit path <target> [subpath]`,
`devkit plan list|show|validate|sync|resolve|archive <target> [args]`,
`devkit learnings [--format json|md] [promotions [approve|promote|reject <id>]]`.

**Detached execution (`--detach`):** Adding `--detach` to any skill invocation
spawns Claude Code in the background and returns a run ID immediately. A watcher
process captures stdout/stderr to `~/.claude-devkit/runs/<run-id>/` and finalizes
metadata on completion. The `--detach` flag is extracted before `validate_args()`
runs, so it does not conflict with the `--`-prefix rejection guard.

```bash
# Run a skill in the background
devkit architect ~/projects/my-app "add feature" --detach
# Returns: 20260821-143052-a1b2c3

# Check status, retrieve results
devkit jobs                              # List all runs
devkit jobs ~/projects/my-app            # Filter by project
devkit result 20260821-143052-a1b2c3     # Print captured result
devkit logs 20260821-143052-a1b2c3       # Print stderr logs
devkit clean --days 14                   # Remove old runs (default: 7 days)

# Combine with skill flags
devkit architect ~/projects/my-app "add feature" --detach -- --fast
```

Run directories are stored at `~/.claude-devkit/runs/<run-id>/` with `meta.json`
(run metadata), `stdout.log`, `stderr.log`, and `result.json` (parsed from stdout).
Directory permissions are 0o700; files are 0o600. Stale runs (watcher died before
finalizing) are detected via PID liveness checks.

**Environment variables set by the CLI:**

| Variable | Set By | Used By | Value |
|----------|--------|---------|-------|
| `DEVKIT_PROJECT_DIR` | `devkit_cli.py` (cmd_run_skill, cmd_shell, _spawn_detached) | All skills | `~/.claude-devkit/projects/<project-id>` |
| `DEVKIT_SCRIPTS` | `devkit_cli.py` (cmd_run_skill, cmd_shell, _spawn_detached) | All skills | `~/.claude-devkit/scripts` |
| `CLAUDE_DEVKIT` | `install.sh` (shell config) | Generators, development fallback | Path to devkit source repo |
| `DEVKIT_TARGET_COUNT` | `devkit_cli.py` (cmd_run_skill, cmd_shell, _spawn_detached) | `/architect` Step 0, multi-target skills | Number of targets (always set, even for single-target: `1`) |
| `DEVKIT_TARGET_N_DIR` | `devkit_cli.py` | Skills needing cross-repo artifact access | `~/.claude-devkit/projects/<project-id>` for target N |
| `DEVKIT_TARGET_N_PATH` | `devkit_cli.py` | Skills needing cross-repo source access | Resolved repo path for target N |
| `DEVKIT_TARGET_N_ID` | `devkit_cli.py` | Skills referencing project IDs | Project ID for target N |
| `DEVKIT_TARGET_N_NAME` | `devkit_cli.py` | Skills displaying project names | Basename of target N's repo path |

**Single-target consistency:** `DEVKIT_TARGET_COUNT=1` and `DEVKIT_TARGET_0_*` vars are
always set, even for single-target invocations (both `devkit shell` and `devkit <skill>`).
This provides a consistent interface for skills: they can always read `DEVKIT_TARGET_0_PATH`
instead of conditionally checking whether indexed vars exist. `DEVKIT_TARGET_COUNT > 1`
indicates a multi-target session.

Skills use `$DEVKIT_PROJECT_DIR/plans/` for artifact storage. When invoked without the CLI
(directly in Claude Code), skills compute the project directory from CWD using a three-tier
resolution: (1) `$DEVKIT_PROJECT_DIR` env var, (2) computed from CWD when `$CLAUDE_DEVKIT` or
`~/.claude-devkit/` exists, (3) deprecated legacy `.devkit/plans/` fallback with warning.

**New commands for centralized artifact management:**

```bash
# Migrate existing .devkit/ artifacts to centralized location
devkit migrate ~/projects/my-app

# Recover artifacts after project directory rename/move
devkit relink ~/old/path/my-app ~/new/path/my-app

# Print the centralized artifact directory path for a project
devkit path ~/projects/my-app
devkit path ~/projects/my-app plans/feature.md
```

`devkit path` validates subpath arguments against path traversal: `..` segments are
rejected and the resolved path is verified to be under the project's central directory.

`devkit init` creates the project directory at `~/.claude-devkit/projects/<project-id>/` and does
NOT create any `.devkit/` directory in the target project. Zero runtime footprint in target projects.

**Passing flags through (`--` separator):** `validate_args()` rejects any skill
argument starting with `--` as a flag-injection guard, so skill flags like `--fast`
or `--security-override "reason"` cannot be passed directly. Use `--` to mark the
end of harness-parsed arguments -- everything after it is forwarded verbatim to the
skill (see `split_skill_args()` in `devkit_cli.py`):

```bash
devkit architect ~/projects/my-app "add feature" -- --fast
devkit ship ~/projects/my-app $DEVKIT_PROJECT_DIR/plans/feature.md -- --security-override "reason"
```

**Cross-repo plan support (`--with` flag and `devkit plan` subcommand):**

Plans that span multiple repositories use a `targets:` field in YAML frontmatter
to declare all involved projects. Each target has a `role` (`primary` or `secondary`).
The primary project stores the plan file; secondary projects get lightweight JSON
reference files (`plan-refs/*.ref.json`) so `devkit status` and `devkit plan list`
can show cross-repo relationships from any involved project.

```bash
# Multi-target architect (creates cross-repo plan with targets: frontmatter)
devkit architect ~/projects/my-app "integrate with cve-api" --with ~/projects/cve-api

# Multi-target shell (sets DEVKIT_TARGET_COUNT and indexed env vars)
devkit shell ~/projects/my-app --with ~/projects/cve-api

# Plan lifecycle management
devkit plan list <target>               # List plans + cross-repo refs
devkit plan show <target> <plan-name>   # Show plan details with target info
devkit plan validate <target> <file>    # Validate plan frontmatter (targets exist)
devkit plan sync <target>               # Rebuild plan-refs from frontmatter
devkit plan resolve <devkit-uri>        # Resolve devkit:// URI to absolute path
devkit plan archive <target> <plan>     # Archive plan + remove refs from all projects
```

The `--with` flag is extracted before `validate_args()` runs (same as `--detach`),
so it does not conflict with the `--`-prefix rejection guard. Each `--with` target
passes the same validation as primary targets (non-symlink, real git repo, under
`allowed_roots`, devkit-initialized). Max 10 targets per cross-repo plan (configured
via `max_cross_repo_targets` in `configs/devkit-defaults.json`).

`devkit://` URIs resolve project-id references to absolute paths:
```
devkit://cve-api-f25db5e61a87/plans/add-v2-endpoint.md
  -> ~/.claude-devkit/projects/cve-api-f25db5e61a87/plans/add-v2-endpoint.md
```
Path traversal via `..` segments is rejected. URI path must start with `plans/`.

**Known limitation:** `devkit shell` replaces the harness process via `os.execvp()`,
so `last_invocation` is written before the interactive session starts and is never
updated with an exit code afterward (the harness never regains control). `devkit
status` will show a stale timestamp with `exit_code: null` for projects primarily
accessed via `shell`.

### With Project Agents

Generated senior-architect agents live in project directories:

```
~/projects/my-app/
└── .claude/
    └── agents/
        └── senior-architect.md
```

**Integration:**
- `/architect` skill checks for `.claude/agents/senior-architect.md`
- If not found, prompts to generate using `gen-architect`
- Agent reads project `CLAUDE.md` for context

## Validation

### Skill Validation

Run validation before committing:

```bash
validate-skill skills/architect/SKILL.md
```

**Checks:**
- ✅ Valid YAML frontmatter
- ✅ Required fields (name, description, model)
- ✅ Workflow header format
- ✅ Numbered steps (`## Step N -- [Action]`)
- ✅ Tool declarations
- ✅ Verdict gates (PASS/FAIL/BLOCKED)
- ✅ Timestamped artifacts
- ✅ Bounded iterations (max N revisions)
- ✅ Archive references
- ✅ Scope parameters

**Output Formats:**
- Human-readable (default)
- JSON (`--json` flag)
- Strict mode (`--strict` flag)

**Exit Codes:**
- `0` = Pass
- `1` = Fail (errors found)
- `2` = Invalid args

### Test Suite

Run comprehensive test suite:

```bash
cd ~/projects/claude-devkit
bash generators/test_skill_generator.sh
```

**Coverage (66 tests):**
- Generator and validator help text
- All 20 core skills (architect, ship, retro, audit, sync,
  receiving-code-review, verification-before-completion, compliance-check,
  dependency-audit, secrets-scan, secure-review, threat-model-gate, fix,
  input-validation-injection, client-side-security, ai-code-review,
  semgrep, build-yaml-misconfiguration, container-hardening, threat-model)
- All 3 contrib skills (journal, journal-recall, journal-review)
- All archetypes (coordinator, pipeline, scan, knowledge-base)
- Knowledge-base archetype positive/negative tests (valid, empty body, missing attribution)
- deploy.sh reference/ directory copy test
- secrets-scan grep pattern syntax validation
- Input validation (names, descriptions, paths)
- JSON output
- Negative tests (missing frontmatter, empty steps)
- Metadata comments
- Cleanup

## Troubleshooting

### Skills not found after deployment

**Issue:** `/<skill-name>` not recognized

**Solution:**
1. Verify deployment: `ls ~/.claude/skills/<skill-name>/SKILL.md`
2. Restart Claude Code session: `/exit` then `claude-code`
3. Check frontmatter has correct `name:` field

### Generator command not found

**Issue:** `command not found: gen-skill`

**Solution:**
```bash
# Add to shell config
echo 'export PATH="$PATH:$HOME/projects/claude-devkit/generators"' >> ~/.zshrc
source ~/.zshrc
```

### Validation fails on generated skill

**Issue:** Newly generated skill fails validation

**Solution:** This indicates a template bug. Check template file and ensure all patterns are present.

### Permission denied on scripts

**Issue:** `Permission denied` when running generators

**Solution:**
```bash
chmod +x ~/projects/claude-devkit/generators/*.py
chmod +x ~/projects/claude-devkit/scripts/*.sh
```

### Agent not using correct model

**Issue:** Agent uses wrong model (e.g., sonnet instead of opus)

**Solution:** Check frontmatter in agent file:
```yaml
---
model: claude-opus-4-6  # Must be exactly this
---
```

### Deployment overwrites customizations

**Issue:** Running deploy.sh overwrites skill changes

**Solution:** Never edit skills in `~/.claude/skills/`. Always edit in `~/projects/claude-devkit/skills/` and redeploy.

### Scanner venv or cache issues

**Issue:** Scanner fails to use tree-sitter, or cache appears stale/corrupted

**Solution:**
```bash
# Remove scanner venv and cache (will be recreated on next install)
rm -rf ~/.claude-devkit/scanner-venv
rm -rf ~/.claude-devkit/cache

# Or use uninstall.sh which handles cleanup automatically
./scripts/uninstall.sh

# Re-run install to recreate scanner venv
./scripts/install.sh
```

The scanner falls back to regex-based extraction when tree-sitter is unavailable — skill execution is never blocked.

**Scanner venv location:** `~/.claude-devkit/scanner-venv/`
**Cache location:** `~/.claude-devkit/cache/<project-hash>/index.json`

### devkit CLI: permission prompts block non-interactive execution

**Issue:** `devkit <skill> <target>` appears to hang indefinitely during `--print`
mode.

**Solution:** Non-interactive skill execution requires tool permission allowlists
in `~/.claude/settings.json` (or project `.claude/settings.json`); otherwise Claude
Code stops to prompt for permission and the non-interactive session stalls waiting
for input that never comes. See the Tool Permissions section above. `devkit` prints
a pre-flight warning when no allowlists are detected, but does not block the run.

### devkit init rejects a valid project path

**Issue:** `devkit init ~/some/path` exits 1 with a validation error even though
the path is a real git repository.

**Solution:** Check `configs/devkit-defaults.json`'s `allowed_roots` list (default:
`~/projects/`, `~/workspaces/`, plus the devkit root and `/tmp/` which are always
allowed). Add the parent directory to `allowed_roots`, or move the project under an
already-allowed root. Also confirm the target is not a symlink -- symlinked targets
are rejected regardless of `allowed_roots`.

### devkit shell shows stale status afterward

**Issue:** After running `devkit shell <target>` and exiting the interactive
session, `devkit status <target>` still shows the pre-session timestamp with
`exit_code: null`.

**Solution:** This is a known limitation, not a bug. `devkit shell` uses
`os.execvp()` to replace the harness process with `claude`, so the harness never
regains control after the interactive session starts and cannot record an exit
code. State is written immediately before `execvp` with `exit_code: null` to
indicate an interactive session occurred. Use `devkit <skill> <target>` (
non-interactive mode) if you need accurate post-run status tracking.

### devkit learnings shows no entries

**Issue:** `devkit learnings` reports 0 entries parsed even though projects have learnings files.

**Solution:** The aggregator discovers learnings files via two paths: (1) projects registered in
`~/.claude-devkit/registry.json`, and (2) filesystem scan under `allowed_roots` from
`configs/devkit-defaults.json`. Ensure your projects are either registered (`devkit init <target>`)
or located under an allowed root. Also verify learnings files are at the expected path:
`<project>/.claude/learnings.md`. The aggregator skips symlinked paths and backup directories
(containing `_backup_`).

### /retro mine proposes already-tracked promotions

**Issue:** `/retro mine` keeps proposing the same patterns.

**Solution:** The skill filters candidates against `~/.claude-devkit/learnings/promotions.json`.
If this file is missing or corrupt, all candidates appear as new. Verify the file exists and is
valid JSON: `python3 -m json.tool ~/.claude-devkit/learnings/promotions.json`. If corrupt, delete
it and re-run -- previously proposed entries will be re-proposed but can be rejected.

## Syncing Across Machines

If you work on multiple machines:

### Machine 1 (Initial Setup)

```bash
cd ~/projects/claude-devkit
git init
git add .
git commit -m "Initial commit: Claude Devkit"
git remote add origin <your-repo-url>
git push -u origin main
```

### Machine 2+ (Clone)

```bash
cd ~/projects
git clone <your-repo-url> claude-devkit

# Add to shell config (same as installation)
echo 'export PATH="$PATH:$HOME/projects/claude-devkit/generators"' >> ~/.zshrc
source ~/.zshrc

# Deploy skills
cd claude-devkit
./scripts/deploy.sh
```

## Version Control

### Recommended .gitignore

```gitignore
# Test outputs
test-output/
*.test.md
.test/

# Python
__pycache__/
*.py[cod]
venv/

# OS files
.DS_Store

# Editor files
.vscode/
.idea/

# Logs
*.log

# Temporary files
tmp/
temp/

# L2/L3 compliance artifacts (staged into project for git tracking at L1: gitignore)
.devkit-audit-logs/
.devkit-plans/

# Audit run state files (ephemeral — deleted at run end)
.ship-audit-state-*
.architect-audit-state-*
.audit-audit-state-*

# Audit HMAC key files (L3 only — never commit to shared repos)
.ship-audit-key-*

# Scanner cache (outside repo, at ~/.claude-devkit/cache/) — no repo entry needed
```

### Commit Messages

Follow conventional commits:

```
feat(skills): add deploy-check skill for production validation
fix(generators): handle spaces in project names
docs(README): update installation instructions
test(generators): add validation tests for scan archetype
```

## Roadmap

### v1.0 (Current)

- [x] Core skills (architect, ship, audit, sync, retro)
- [x] Security skills (5 standalone + 3 workflow integrations)
- [x] Skill generator with 3 archetypes
- [x] Agent generator (unified)
- [x] Skill validator + agent validator
- [x] Deployment scripts (core + contrib)
- [x] Test suite (66 tests, all 20 core + 3 contrib skills validated)
- [x] Security maturity levels (L1/L2/L3)
- [x] validate-all health check command
- [x] Deploy-time validation (--validate flag)
- [x] Structured JSONL audit logging (ship, architect, audit) with maturity-aware retention and query utility

### v1.1 (Next)

- [x] Codebase symbol index (deterministic scanner for agent context — tree-sitter + regex fallback)
- [ ] CLAUDE.md template generator (broader than security section)
- [ ] Project initializer (full project setup)
- [ ] Skill version upgrade tool

### v1.2 (Planned)

- [ ] Interactive TUI for skill generation
- [ ] Agent testing framework (behavioral, not just structural)
- [ ] Skill dependency management
- [ ] CI/CD pipeline templates

## Contributing

This is a personal toolkit, but contributions welcome:

1. **Add new skills** — Generate scaffold, customize, validate
2. **Create generators** — Add to `generators/` with docs
3. **Improve templates** — Enhance archetypes
4. **Write tests** — Extend test suite
5. **Submit PR** — Share improvements

## License

MIT - Use freely in your projects

## Related Resources

- **Claude Code Documentation:** https://claude.ai/code
- **Workspaces Architecture:** `~/workspaces/CLAUDE.md`
- **Base Agents:** `~/workspaces/.config/agents/base/README.md`
- **Multi-LLM Support:** [GEMINI.md](GEMINI.md) - Framework overview for Gemini users

---

**Maintained by:** @backspace-shmackspace
**Repository:** `~/projects/claude-devkit`
**Deployment:** `~/.claude/skills/`
