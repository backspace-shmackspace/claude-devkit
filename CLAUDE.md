# Claude Devkit

**Version:** 1.0.0
**Last Updated:** 2026-03-31
**Purpose:** Unified development toolkit for Claude Code - skills, agents, generators, and templates

**New to Claude Devkit?** Start with [GETTING_STARTED.md](GETTING_STARTED.md) for a 15-minute tutorial.

## Overview

Claude Devkit is the complete toolkit for building with Claude Code. It combines skill definitions, agent generators, templates, and reusable configurations into a single, version-controlled repository.

**What's Inside:**
- **Skills** — 12 core reusable Claude Code workflows including `/architect`, `/ship`, `/retro`, `/audit`, `/sync`, and security skills
- **Generators** — Scripts to create agents, skills, and project structures
- **Templates** — Reusable templates for agents and skills
- **Configs** — Shared configurations and patterns
- **Scripts** — Deployment and validation utilities

## Architecture

### Three-Tier Structure

```
claude-devkit/
├── skills/              # Tier 1: Core skill definitions (source of truth)
│   ├── architect/           # Planning with approval gates
│   ├── ship/            # Implementation pipeline
│   ├── retro/           # Retrospective and learnings capture
│   ├── audit/           # Security and performance scanning
│   ├── sync/            # Documentation synchronization
│   ├── compliance-check/      # Regulatory framework validation
│   ├── dependency-audit/      # Supply chain security
│   ├── secrets-scan/          # Pre-commit secrets detection
│   ├── secure-review/         # Deep semantic security review
│   └── threat-model-gate/     # Security planning reference
│
├── contrib/             # Tier 1b: Optional/personal skills (opt-in)
│   ├── journal/         # Obsidian journal writing
│   ├── journal-recall/  # Journal search and retrieval
│   └── README.md        # Available contrib skills documentation
│
├── generators/          # Tier 2: Code generation
│   ├── generate_skill.py              # Create new skills
│   ├── generate_senior_architect.py   # Create architect agents
│   ├── validate_skill.py              # Validate skill definitions
│   └── README.md
│
├── templates/           # Tier 3: Reusable templates
│   ├── senior-architect.md.template   # Local architect agent
│   ├── skill-coordinator.md.template  # Coordinator pattern
│   ├── skill-pipeline.md.template     # Pipeline pattern
│   └── skill-scan.md.template         # Scan pattern
│
├── configs/             # Shared configurations
│   ├── skill-patterns.json
│   ├── audit-event-schema.json
│   └── base-definitions/
│
├── plans/audit-logs/    # JSONL audit event logs (L1: gitignored, L2/L3: committed)
│
└── scripts/             # Deployment and utilities
    ├── deploy.sh        # Deploy skills to ~/.claude/skills/
    ├── install.sh       # Automated installation
    ├── uninstall.sh     # Clean uninstallation
    ├── validate-all.sh  # Health check - validate all skills
    ├── emit-audit-event.sh    # Audit event emission helper (invoked by skills)
    ├── audit-log-query.sh     # Query utility for JSONL audit logs
    └── test-integration.sh    # Integration smoke tests (8 tests)
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
| **architect** | 3.3.0 | Context discovery → Architect (with project context) → Red Team + Librarian + Feasibility (parallel) → Revision loop → Approval gate. Supports `--fast`. Stage 2 plan content scan detects security-sensitive features; invokes security-analyst (Required, not Recommended) when deployed and injects threat-model-gate requirements. Context alignment and metadata in output. Auto-commits artifacts on verdict. JSONL audit logging to `plans/audit-logs/architect-<run_id>.jsonl`. | opus-4-6 | 6 |
| **ship** | 3.7.0 | Pre-flight check → Read plan + security requirements validation (Step 1 checks for threat model output and blocks if required gates are unmet) → Pattern validation (warnings) → Security gates (secrets-scan, secure-review with threat model context passing in Step 4d, dependency-audit) with maturity levels (L1/L2/L3) → Worktree isolation → Parallel coders → File boundary validation → Merge → Code review + tests + QA (parallel) → Revision loop → Commit gate → Retro capture. Supports `--security-override`. Structural conflict prevention. Learnings consumption. JSONL audit logging to `plans/audit-logs/ship-<run_id>.jsonl` with maturity-aware retention. | opus-4-6 | 8 |
| **retro** | 1.0.0 | Mine review artifacts for recurring patterns and write project learnings. Scope modes: recent/full/feature-name. Glob-based discovery, format-resilient prompts, severity-rated findings, semantic deduplication. | opus-4-6 | 6 |
| **audit** | 3.2.0 | Scope detection (plan/code/full) → Security scan (composable: invokes /secure-review when deployed, otherwise built-in scan) + Performance scan → QA regression → Synthesis with PASS/PASS_WITH_NOTES/BLOCKED verdict → Structured reporting with timestamped artifacts. JSONL audit logging to `plans/audit-logs/audit-<run_id>.jsonl`. | opus-4-6 | 6 |
| **sync** | 3.0.0 | Detect changes (recent/full) → Detect undocumented env vars → Librarian review with CURRENT/UPDATES_NEEDED verdict → Apply updates → User verification with git diff → Archive review. | claude-sonnet-4-6 | 6 |
| **receiving-code-review** | 1.0.0 | Code review reception discipline: 6-step response pattern (READ through IMPLEMENT), anti-performative-agreement, YAGNI enforcement, source-specific handling, pushback guidelines. Reference archetype. | claude-sonnet-4-6 | Reference |
| **verification-before-completion** | 1.0.0 | Evidence-before-claims gate: 5-step verification (IDENTIFY, RUN, READ, VERIFY, CLAIM). Requires fresh test/build output before any completion claim. Red flags, rationalization table, key patterns for TDD and bug fixes. Reference archetype. | claude-sonnet-4-6 | Reference |
| **compliance-check** | 1.0.0 | Validate codebase against code-level compliance signals for regulatory frameworks (FedRAMP, FIPS, OWASP, SOC 2). Scoped to source code analysis only — not a compliance certification. | opus-4-6 | 5 |
| **dependency-audit** | 1.0.0 | Supply chain security audit — coordinates real CLI vulnerability scanners (npm audit, pip-audit, govulncheck, cargo audit, etc.) and synthesizes findings with license compliance and risk assessment. | claude-sonnet-4-6 | 8 |
| **secrets-scan** | 1.0.0 | Pre-commit secrets detection with pattern-based scanning for API keys, tokens, passwords, private keys, and connection strings. Self-contained — no external tools required. | claude-sonnet-4-6 | 6 |
| **secure-review** | 1.1.0 | Deep semantic security review of code changes with data flow tracing, taint analysis, and trust boundary validation. When invoked with plan context (e.g., by /ship Step 4d), includes a `## Threat Model Coverage` section mapping findings against threat model requirements. Composable building block invoked by /audit when deployed. | opus-4-6 | 5 |
| **threat-model-gate** | 1.0.0 | Use when planning security-sensitive features — authentication, authorization, data handling, API design, cryptography, or network configuration — requires explicit threat modeling before implementation decisions are made. Reference archetype. | claude-sonnet-4-6 | Reference |

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

The `/ship` skill runs three security gates when the corresponding skills are deployed:

1. **Secrets scan** (Step 0 pre-flight): Runs `/secrets-scan` on working directory. BLOCKS at all maturity levels (committed secrets cannot be un-committed). Override available with `--security-override`.

2. **Secure review** (Step 4d verification): Runs `/secure-review` on uncommitted changes. At L1: BLOCKED auto-downgrades to PASS_WITH_NOTES. At L2/L3: BLOCKED stops workflow unless overridden.

3. **Dependency audit** (Step 6 commit gate): Runs `/dependency-audit` on manifest files. At L1: BLOCKED auto-downgrades to PASS_WITH_NOTES. At L2/L3: BLOCKED stops workflow unless overridden.

**Override Syntax:**

```bash
/ship plans/feature.md --security-override "False positive: hardcoded test API key in fixture file"
```

**Notes:**
- Security gates are conditional — only run if the corresponding skill is deployed
- At L2/L3, `/ship` pre-flight checks that all three security skills are deployed
- Missing skills at L1 log warnings; at L2/L3, missing skills block pre-flight
- Override reasons are logged for audit trails (especially important at L3)

## Audit Logging

`/ship`, `/architect`, and `/audit` emit structured JSONL audit events to `plans/audit-logs/` on every run, providing a machine-parseable record of what agents did and when.

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

**Log File Locations:**

- `/ship` logs: `plans/audit-logs/ship-<run_id>.jsonl`
- `/architect` logs: `plans/audit-logs/architect-<run_id>.jsonl`
- `/audit` logs: `plans/audit-logs/audit-<run_id>.jsonl`

**Maturity-Aware Retention:**

| Level | Log Retention | HMAC Integrity |
|-------|--------------|----------------|
| **L1** (advisory) | Gitignored — ephemeral, available during run for debugging | None |
| **L2** (enforced) | Committed to git via `git add --force` in Step 6 | None |
| **L3** (audited) | Committed to git; HMAC chain with key persisted to `.ship-audit-key-<run_id>` | HMAC-SHA256 chain (post-run verifiable) |

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
- `configs/audit-event-schema.json` — JSON Schema defining all event types with OTel field mapping documentation.
- `plans/audit-logs/` — Dedicated directory for audit logs (separate lifecycle from `plans/archive/`).

**OTel Migration:** The JSONL format is designed for future migration to OpenTelemetry spans via a format adapter. The adapter requires span hierarchy reconstruction (not a trivial field rename) and will be built when Kagenti provides an OTel collector endpoint.

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
| **generate_senior_architect.py** | Create single architect agent (legacy - use generate_agents.py instead) | `.claude/agents/senior-architect.md` |
| **validate_skill.py** | Validate skills against v2.0.0 patterns | Exit code 0/1/2 + validation report |
| **validate_agent.py** | Validate agents for inheritance patterns | Exit code 0/1/2 + validation report |

## Template Registry

| Template | Purpose | Archetype | Use Case |
|----------|---------|-----------|----------|
| **skill.md.template** | Base skill template | N/A | Starting point for custom skills |
| **skill-coordinator.md.template** | Coordinator workflow | Coordinator | Multi-agent delegation, revision loops |
| **skill-pipeline.md.template** | Pipeline workflow | Pipeline | Sequential validation checkpoints |
| **skill-scan.md.template** | Scan workflow | Scan | Parallel analysis, severity ratings |
| **senior-architect.md.template** | Local architect agent (legacy) | N/A | High-level design and planning |
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
- Adds `CLAUDE_DEVKIT` environment variable
- Adds generators to your PATH
- Creates convenient aliases (gen-skill, gen-agent, validate-skill, etc.)
- Backs up your shell config before making changes

**Manual Installation (Alternative):**
```bash
# Add to ~/.zshrc or ~/.bashrc
export CLAUDE_DEVKIT="$HOME/projects/claude-devkit"
export PATH="$PATH:$CLAUDE_DEVKIT/generators"

# Aliases
alias gen-skill='python $CLAUDE_DEVKIT/generators/generate_skill.py'
alias gen-agent='python $CLAUDE_DEVKIT/generators/generate_agents.py'
alias gen-architect='python $CLAUDE_DEVKIT/generators/generate_senior_architect.py'
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
/ship plans/add-user-authentication.md
/audit
/sync
```

## Complete Workflows

### Workflow 1: Feature Development (Full Lifecycle)

```bash
# 1. Plan the feature
/architect add shopping cart functionality

# 2. Optional: Audit the plan before implementation
/audit plan plans/add-shopping-cart.md

# 3. Implement the plan
/ship plans/add-shopping-cart.md

# 4. Update documentation
/sync

# 5. Final security and performance audit
/audit
```

**Artifacts Created:**
- `plans/add-shopping-cart.md` — Approved implementation plan
- `plans/add-shopping-cart.redteam.md` — Red team review
- `plans/add-shopping-cart.feasibility.md` — Feasibility review
- `plans/add-shopping-cart.review.md` — Librarian review
- `plans/archive/add-shopping-cart/` — Code review and QA reports
- `plans/audit-[timestamp].summary.md` — Final audit results
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
cat plans/audit-[timestamp].summary.md

# 3. Address critical issues
# ... make fixes ...

# 4. Re-audit
/audit code

# 5. Update docs with security patterns
/sync
```

**Artifacts Created:**
- `plans/audit-[timestamp].summary.md` — Audit summary with verdict
- `plans/audit-[timestamp].security.md` — Security findings
- `plans/audit-[timestamp].performance.md` — Performance findings
- `plans/audit-[timestamp].qa.md` — QA regression results
- `plans/archive/audit/audit-[timestamp]/` — Archived reports

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
- `plans/sync-[timestamp].review.md` — Librarian review
- `CLAUDE.md` — Updated with current patterns
- `README.md` — Updated usage docs (if needed)
- `plans/archive/sync/sync-[timestamp].review.md` — Archived review

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
| **6. Structured reporting** | Consistent markdown format | Outputs to `./plans/` |
| **7. Bounded iterations** | Max revision loops prevent cycles | `Max N revision` language |
| **8. Model selection** | Right model for each task | Valid `model:` in frontmatter |
| **9. Scope parameters** | Flexible invocation | `## Inputs` with `$ARGUMENTS` |
| **10. Archive on success** | Move artifacts after completion | References `./plans/archive/` |
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

## Artifact Locations

```
./plans/
├── [feature].md                           # Plans from /architect
├── [feature].redteam.md                   # Red team reviews
├── [feature].feasibility.md               # Feasibility reviews
├── [feature].review.md                    # Librarian reviews
├── audit-[timestamp].summary.md           # Audit summaries
├── audit-[timestamp].security.md          # Security scan results
├── audit-[timestamp].performance.md       # Performance scan results
├── audit-[timestamp].qa.md                # QA regression results
├── sync-[timestamp].review.md             # Documentation reviews
├── retro-[timestamp].coder-scan.md        # Coder calibration scan (from /retro)
├── retro-[timestamp].reviewer-scan.md     # Reviewer calibration scan (from /retro)
├── retro-[timestamp].test-scan.md         # Test pattern scan (from /retro)
├── retro-[timestamp].summary.md           # Retro summary with verdict
├── audit-logs/                            # JSONL audit event logs (queryable across runs)
│   ├── ship-[run_id].jsonl                # /ship run audit log (L1: gitignored, L2/L3: committed)
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
    └── retro/
        └── retro-[timestamp]/             # Archived retro reports
```

`.claude/learnings.md` — Project-level learnings (lives outside `./plans/`, created by `/retro` and `/ship` Step 7)

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
└── threat-model-gate/SKILL.md
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
- `generate_senior_architect.py` — Create architect agents
- `validate_skill.py` — Validate skill definitions
- `test_skill_generator.sh` — Test suite (46 tests)

**Capabilities:**
- Auto-detection (project type, stack)
- Interactive prompts or CLI flags
- Atomic file operations
- Automatic validation
- Optional deployment

### /templates

Reusable templates with placeholder substitution.

**Templates:**
- `senior-architect.md.template` — Local architect agent
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
- `tech-stack-definitions/` — Stack-specific configs (7 stacks: python, fastapi, typescript, react, nextjs, astro, security)
- `base-definitions/` — Reserved for future use (currently empty)

### /scripts

Deployment and utility scripts.

**Scripts:**
- `deploy.sh` — Deploy skills to `~/.claude/skills/` (core and/or contrib)
- `install.sh` — Automated installation (PATH, aliases, shell config)
- `uninstall.sh` — Clean uninstallation with backup restoration
- `validate-all.sh` — Health check - validate all skills in one pass
- `emit-audit-event.sh` — Standalone helper script for skill audit event emission (invoked by `/ship`, `/architect`, `/audit`)
- `audit-log-query.sh` — Query utility for JSONL audit logs (summary, timeline, security, verdicts, files, verify-chain, recent)
- `test-integration.sh` — Integration smoke tests (8 tests): emit-audit-event.sh JSONL correctness, L3 HMAC chain
  verification, 10+ call state persistence, and end-to-end generate/validate/deploy lifecycle

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

**Coverage (46 tests):**
- Generator and validator help text
- All 12 core skills (architect, ship, retro, audit, sync,
  receiving-code-review, verification-before-completion, compliance-check,
  dependency-audit, secrets-scan, secure-review, threat-model-gate)
- All 3 contrib skills (journal, journal-recall, journal-review)
- All archetypes (coordinator, pipeline, scan)
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

# Audit logs (L1 ephemeral — gitignored at advisory maturity)
plans/audit-logs/*.jsonl

# Audit run state files (ephemeral — deleted at run end)
.ship-audit-state-*
.architect-audit-state-*
.audit-audit-state-*

# Audit HMAC key files (L3 only — never commit to shared repos)
.ship-audit-key-*
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
- [x] Test suite (46 tests, all 12 core + 3 contrib skills validated)
- [x] Security maturity levels (L1/L2/L3)
- [x] validate-all health check command
- [x] Deploy-time validation (--validate flag)
- [x] Structured JSONL audit logging (ship, architect, audit) with maturity-aware retention and query utility

### v1.1 (Next)

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
