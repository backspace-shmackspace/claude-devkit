# Claude Devkit

Complete development toolkit for Claude Code - skills, agents, generators, and templates.

**New to Claude Devkit?** Start with [GETTING_STARTED.md](GETTING_STARTED.md) for a 15-minute tutorial.

## Quick Start

### 1. Install

```bash
# Clone the repository
cd ~/projects
git clone <your-repo-url> claude-devkit

# Run installation script
cd claude-devkit
./scripts/install.sh

# Reload shell
source ~/.zshrc  # or source ~/.bashrc

# Verify installation
which gen-skill gen-agent validate-skill
```

### 2. Deploy Skills

```bash
cd ~/projects/claude-devkit
./scripts/deploy.sh           # Deploy all skills
```

### 3. Start Using

```bash
# In any Claude Code session
/architect add user authentication
/ship $DEVKIT_PROJECT_DIR/plans/add-user-authentication.md
/audit
/sync
```

### 4. Use the Meta-Harness (Optional)

The `devkit` CLI (`devkit --version` → `0.4.0`) lets you target and run skills
against any registered git repository from outside that project — no `cd`
required.

```bash
# Register a project for devkit management
devkit init ~/projects/my-app

# Run skills from anywhere
devkit audit ~/projects/my-app
devkit architect ~/projects/my-app "add feature"

# Pass skill flags through with `--` (bypasses the flag-injection guard)
devkit architect ~/projects/my-app "add feature" -- --fast

# Cross-repo planning: add secondary targets with --with
devkit architect ~/projects/my-app "integrate with cve-api" --with ~/projects/cve-api
devkit shell ~/projects/my-app --with ~/projects/cve-api

# Manage cross-repo plans (list/show/validate/sync/resolve/archive)
devkit plan list ~/projects/my-app
devkit plan show ~/projects/my-app integrate-cve-api

# Shared learnings: aggregate cross-project patterns and manage promotions
devkit learnings aggregate
devkit learnings status
devkit learnings propose <entry-id> --type skill_rule --target skills/ship/SKILL.md --description "..."

# Open an interactive session, or check status of all managed projects
devkit shell ~/projects/my-app
devkit status
```

See [CLAUDE.md](CLAUDE.md#with-meta-harness) for the full command reference and
security model.

## What's Included

### Skills (20)

Pre-built workflows for common development tasks:

| Skill | Purpose | Usage |
|-------|---------|-------|
| `/architect` | Create implementation plans with context alignment and approval gates. Detects security-sensitive features via keyword heuristic and Stage 2 plan content scan; requires threat modeling when threat-model-gate is deployed. Does cross-repo context discovery and creates `plan-refs/` via `devkit plan sync` when invoked with multiple targets (`DEVKIT_TARGET_COUNT > 1`, e.g. via `devkit architect ... --with <target2>`). | `/architect add shopping cart` |
| `/ship` | Execute plans with pattern validation, security gates (secrets/code/deps), testing, QA, and retro capture. Supports security maturity levels (L1/L2/L3) and `--security-override`. Validates CWD against cross-repo plan `targets:` and filters work groups by `target:` annotation for multi-repo plans. | `/ship $DEVKIT_PROJECT_DIR/plans/feature.md` |
| `/retro` | Mine review artifacts for recurring patterns and capture learnings. `mine` scope performs cross-project learnings mining via the shared learnings layer. | `/retro`, `/retro feature-name`, or `/retro mine` |
| `/audit` | Security, performance, and anti-pattern scanning. Composable: invokes /secure-review when deployed. | `/audit` or `/audit code` |
| `/sync` | Update documentation and CLAUDE.md | `/sync` or `/sync full` |
| `/receiving-code-review` | Code review reception discipline | `/receiving-code-review` |
| `/verification-before-completion` | Evidence-before-claims gate — requires fresh test/build output before completion claims | `/verification-before-completion` |
| `/compliance-check` | Validate against regulatory frameworks (FedRAMP, FIPS, OWASP, SOC 2) | `/compliance-check fedramp fips` |
| `/dependency-audit` | Supply chain security with vulnerability scanning and license compliance | `/dependency-audit` |
| `/secrets-scan` | Pre-commit secrets detection for API keys, tokens, credentials | `/secrets-scan staged` |
| `/secure-review` | Deep semantic security review with data flow tracing, taint analysis, and trust boundary validation. When invoked with threat model context, produces a `## Threat Model Coverage` section mapping STRIDE threats to implementation status. | `/secure-review changes` |
| `/threat-model-gate` | Security planning reference for authentication, authorization, data handling | `/threat-model-gate` |
| `/fix` | Targeted finding remediation — parse a finding from a review artifact, dispatch a scoped coder, run focused verification, and commit with traceability. Supports `--dry-run`. | `/fix $DEVKIT_PROJECT_DIR/plans/audit-findings.md --finding SEC-01` |

**Knowledge-base skills** (reference guides invoked on demand, no multi-step workflow):

| Skill | Purpose | Usage |
|-------|---------|-------|
| `/input-validation-injection` | Injection prevention: SQL, LDAP, OS command, prototype pollution, ReDoS | `/input-validation-injection` |
| `/client-side-security` | Browser security: XSS (5 contexts), CSP, CSRF, XS-Leaks, Trusted Types | `/client-side-security` |
| `/ai-code-review` | AI-generated code review: hallucinated APIs, plausible-but-wrong logic, pattern drift | `/ai-code-review` |
| `/semgrep` | Semgrep static analysis: auto-language detection, 30+ rulesets, SARIF output | `/semgrep` |
| `/build-yaml-misconfiguration` | CI/CD pipeline security: GitLab CI, Tekton, Containerfile hardening | `/build-yaml-misconfiguration` |
| `/container-hardening` | Container security: non-root, read-only filesystem, capability restrictions | `/container-hardening` |
| `/threat-model` | Full STRIDE+DREAD threat modeling with OTM v0.2.0 JSON output, MITRE ATT&CK mapping | `/threat-model` |

**Audit Logging:** `/ship`, `/architect`, and `/audit` emit structured JSONL events to `$DEVKIT_PROJECT_DIR/plans/audit-logs/`
on every run. At L2/L3, logs are committed to git. Query with `./scripts/audit-log-query.sh`.
See [CLAUDE.md](CLAUDE.md) for full details.

**Cross-repo context:** the `devkit` CLI always sets `DEVKIT_TARGET_COUNT` (and indexed
`DEVKIT_TARGET_N_DIR`/`_PATH`/`_ID`/`_NAME` vars) for every skill invocation, even
single-target ones (`DEVKIT_TARGET_COUNT=1`). `--with` adds secondary targets and
raises the count, letting `/architect` and `/ship` do cross-repo work. See
[CLAUDE.md](CLAUDE.md) for the full env var reference.

### Generators (5)

Create new skills and agents:

```bash
# Generate a new skill
gen-skill deploy-check --description "Verify deployment health"

# Generate project agents (unified generator)
gen-agent ~/projects/my-app --type all

# Generate a single architect (legacy)
gen-architect ~/projects/my-app

# Validate a skill
validate-skill skills/my-skill/SKILL.md

# Validate an agent
validate-agent .claude/agents/coder.md
```

### Templates (12)

Reusable templates for skills and agents:

**Skill Templates:**
- **skill.md.template** — Base skill template
- **skill-coordinator.md.template** — Coordinator workflow pattern
- **skill-pipeline.md.template** — Pipeline workflow pattern
- **skill-scan.md.template** — Scan workflow pattern
- **claude-md-security-section.md.template** — Security section for project CLAUDE.md

**Agent Templates (templates/agents/):**
- **coder-specialist.md.template** — Code implementation specialist
- **qa-engineer-specialist.md.template** — Testing and validation specialist
- **code-reviewer-standalone.md.template** — Standalone code reviewer
- **code-reviewer-specialist.md.template** — Specialist code reviewer
- **security-analyst.md.template** — Threat modeling and security
- **senior-architect.md.template** — High-level design and planning

## Common Workflows

### Feature Development (Full Lifecycle)

```bash
# 1. Plan the feature
/architect add shopping cart functionality

# 2. Implement the plan
/ship $DEVKIT_PROJECT_DIR/plans/add-shopping-cart.md

# 3. Update documentation
/sync

# 4. Final audit
/audit
```

### Security-Sensitive Feature Development

```bash
# 1. Plan with automatic threat modeling (requires threat-model-gate deployed)
/architect add user authentication with JWT tokens

# 2. Implement with security gates (requires security skills deployed)
/ship $DEVKIT_PROJECT_DIR/plans/add-user-authentication.md

# Security gates run automatically:
# - Step 0: Secrets scan (blocks if secrets found)
# - Step 4d: Secure code review (blocks at L2/L3 if vulnerabilities found)
# - Step 6: Dependency audit (blocks at L2/L3 if vulnerable deps found)

# 3. Override security gate if needed (false positive or time-sensitive)
/ship $DEVKIT_PROJECT_DIR/plans/add-user-authentication.md --security-override "False positive: test fixture data"

# 4. Final comprehensive audit
/audit
```

**Security Maturity Levels:**
- **L1 (advisory)**: Security warnings shown, workflow continues (default)
- **L2 (enforced)**: Security BLOCKED verdicts stop workflow (override available)
- **L3 (audited)**: Same as L2 + all overrides logged for compliance

Configure in `.claude/settings.json`:
```json
{
  "security_maturity": "L2"
}
```

### Create New Skill

```bash
# 1. Generate scaffold
gen-skill my-skill \
  --description "One-line description" \
  --archetype pipeline \
  --deploy

# 2. Customize
code ~/projects/claude-devkit/skills/my-skill/SKILL.md

# 3. Validate
validate-skill ~/projects/claude-devkit/skills/my-skill/SKILL.md

# 4. Deploy
cd ~/projects/claude-devkit
./scripts/deploy.sh my-skill

# 5. Use
/my-skill [arguments]
```

### Create Project Agents

```bash
# Navigate to your project
cd ~/projects/my-app

# Generate all agents (auto-detects stack)
gen-agent . --type all

# Or generate specific agent types
gen-agent . --type coder
gen-agent . --type qa-engineer

# Customize for your domain
code .claude/agents/

# Restart Claude Code
/exit
claude-code

# Use with skills
/architect add checkout flow
/ship $DEVKIT_PROJECT_DIR/plans/add-checkout-flow.md
```

## Available Skills

### `/architect` - Implementation Planning

Creates detailed implementation plans with red team review and approval gates.

**Usage:**
```bash
/architect add user authentication
/architect --fast create API endpoints  # Skip red team review
```

**Cross-repo planning:** When invoked via `devkit architect <target> "..." --with <target2>`,
`/architect` runs context discovery against every target (`DEVKIT_TARGET_COUNT > 1`) and,
on approval, writes cross-repo `plan-refs/` via `devkit plan sync` so `devkit status` and
`devkit plan list` show the relationship from any involved project.

**Output:**
- `$DEVKIT_PROJECT_DIR/plans/[feature].md` — Approved implementation plan
- `$DEVKIT_PROJECT_DIR/plans/[feature].redteam.md` — Red team critique
- `$DEVKIT_PROJECT_DIR/plans/[feature].feasibility.md` — Feasibility review
- `$DEVKIT_PROJECT_DIR/plans/[feature].review.md` — Librarian review

**Workflow:**
1. Context discovery (read project CLAUDE.md and docs)
2. Architect creates initial plan
3. Red team + Librarian + Feasibility review in parallel
4. Revision loop (max 2 iterations)
5. Approval gate (APPROVED/NEEDS_WORK/BLOCKED)
6. Archive artifacts on approval

### `/ship` - Implementation Pipeline

Executes implementation plans with code review, testing, and QA validation.

**Usage:**
```bash
/ship $DEVKIT_PROJECT_DIR/plans/add-user-authentication.md
/ship $DEVKIT_PROJECT_DIR/plans/feature.md --security-override "reason"
```

**Options:**
- `--security-override "reason"` — Override security BLOCKED verdicts with logged reason

**Cross-repo plans:** For plans with a `targets:` frontmatter field (created by cross-repo
`/architect`), `/ship` validates the current working directory against the declared targets
and filters parallel work groups by their `target:` annotation, then removes the plan's
`plan-refs/` entries via `devkit plan archive` on archive.

**Output:**
- Implemented code changes
- `$DEVKIT_PROJECT_DIR/plans/archive/[feature]/[feature].code-review.md` — Code review
- `$DEVKIT_PROJECT_DIR/plans/archive/[feature]/[feature].qa-report.md` — QA report
- Git commit (on approval)

**Workflow:**
1. Pre-flight checks (plan exists, tests pass, security skills deployed at L2/L3)
2. Secrets scan (if /secrets-scan deployed)
3. Read and validate plan — checks for `## Security Requirements` section on security-sensitive
   plans (warns at L1, blocks at L2/L3 if missing)
4. Pattern validation (warnings only)
5. Implement code
6. Code review (sonnet model)
7. Secure review (if /secure-review deployed)
8. Revision loop (max 2 iterations)
9. Run tests
10. QA validation
11. Dependency audit (if /dependency-audit deployed)
12. Commit gate with proper format
13. Suggests `/sync` after success

**Security Gates:**
- At **L1 (advisory)**: Security scans run, BLOCKED verdicts show warnings but don't stop workflow
- At **L2 (enforced)**: Security BLOCKED verdicts stop workflow (override available)
- At **L3 (audited)**: Same as L2 + all overrides logged for compliance audit trails

### `/audit` - Security and Performance

Runs comprehensive security, performance, and QA scans.

**Usage:**
```bash
/audit           # Full audit (plan + code)
/audit plan      # Audit plans only
/audit code      # Audit code only
/audit full      # Deep scan (entire codebase)
```

**Output:**
- `$DEVKIT_PROJECT_DIR/plans/audit-[timestamp].summary.md` — Audit summary
- `$DEVKIT_PROJECT_DIR/plans/audit-[timestamp].security.md` — Security findings
- `$DEVKIT_PROJECT_DIR/plans/audit-[timestamp].performance.md` — Performance findings
- `$DEVKIT_PROJECT_DIR/plans/audit-[timestamp].antipatterns.md` — Anti-pattern findings
- `$DEVKIT_PROJECT_DIR/plans/audit-[timestamp].qa.md` — QA regression results

**Workflow:**
1. Detect scope (plan/code/full)
2. Security scan (composable: invokes /secure-review when deployed)
3. Performance scan
4. Anti-pattern scan (code/full scope only; skipped for plan scope)
5. QA regression testing
6. Synthesis with severity ratings
7. Verdict (PASS/PASS_WITH_NOTES/BLOCKED)

### `/sync` - Documentation Sync

Updates CLAUDE.md and documentation with current patterns.

**Usage:**
```bash
/sync           # Sync recent changes (last 7 days)
/sync full      # Sync all files
```

**Output:**
- `$DEVKIT_PROJECT_DIR/plans/sync-[timestamp].review.md` — Librarian review
- Updated `CLAUDE.md`
- Updated `README.md` (if needed)

**Workflow:**
1. Detect changes (recent or full)
2. Detect undocumented environment variables
3. Librarian review (CURRENT/UPDATES_NEEDED)
4. Apply updates
5. User verification with git diff
6. Archive review

## Available Generators

### Skill Generator

Create new Claude Code skills from archetypes.

**Usage:**
```bash
gen-skill <name> [options]
```

**Options:**
```
--description, -d   One-line description (required)
--archetype, -a     Workflow pattern: coordinator, pipeline, scan (default: coordinator)
--model, -m         Model: claude-opus-4-6, sonnet (default: claude-opus-4-6)
--version, -v       Version (default: 1.0.0)
--steps, -s         Number of steps (default: 4)
--deploy            Deploy after generation
--force, -f         Overwrite existing skill
```

**Examples:**
```bash
# Interactive mode
gen-skill check-config

# Generate coordinator skill
gen-skill plan-feature -d "Create feature plan" -a coordinator

# Generate and deploy
gen-skill deploy-check -d "Verify deployment" -a pipeline --deploy
```

**Archetypes:**
- **coordinator** — Multi-agent delegation, parallel reviews, revision loops (like `/architect`)
- **pipeline** — Sequential validation checkpoints (like `/ship`)
- **scan** — Parallel analysis, severity ratings (like `/audit`)

### Unified Agent Generator

Create all project agents (coder, qa-engineer, code-reviewer, security-analyst, senior-architect).

**Usage:**
```bash
gen-agent <directory> [options]
```

**Options:**
```
--type            Agent type: all, coder, qa-engineer, code-reviewer, security-analyst, senior-architect
--tech-stack      Override auto-detected tech stack
--force           Overwrite existing agents
```

**Examples:**
```bash
# Auto-detect from package.json, pyproject.toml, etc.
gen-agent ~/projects/my-app --type all

# Generate specific agent type
gen-agent . --type coder

# Override tech stack
gen-agent . --type qa-engineer --tech-stack "Python FastAPI"

# Force overwrite
gen-agent . --type all --force
```

**Auto-Detection:**
- `pyproject.toml` with fastapi → Python FastAPI
- `pyproject.toml` with bandit/safety → Python Security
- `package.json` with next → Next.js TypeScript
- `package.json` with react → React TypeScript
- `package.json` with astro → Astro
- `tsconfig.json` → TypeScript

### Senior Architect Generator (Legacy)

Simple single-agent generator (now superseded by unified generator).

**Usage:**
```bash
gen-architect <directory> [options]
```

**Note:** Use `gen-agent . --type senior-architect` instead for consistency.

### Skill Validator

Validate skill definitions against v2.0.0 architectural patterns.

**Usage:**
```bash
validate-skill <path-to-SKILL.md> [options]
```

**Options:**
```
--strict    Treat warnings as errors
--json      Output JSON format
```

**Examples:**
```bash
# Human-readable report
validate-skill skills/architect/SKILL.md

# JSON output (for CI)
validate-skill skills/ship/SKILL.md --json

# Strict mode
validate-skill skills/audit/SKILL.md --strict
```

**Exit Codes:**
- `0` = Pass
- `1` = Fail
- `2` = Invalid arguments

### Agent Validator

Validate agent definitions for inheritance patterns and structure.

**Usage:**
```bash
validate-agent <path-to-agent.md> [options]
```

**Options:**
```
--strict    Treat warnings as errors
--json      Output JSON format
```

**Examples:**
```bash
# Validate single agent
validate-agent .claude/agents/coder-security.md

# Validate all agents
validate-agent .claude/agents/*.md

# JSON output (for CI)
validate-agent .claude/agents/*.md --json
```

## Installation

### Prerequisites

- Python 3.8 or higher
- Claude Code CLI installed and configured
- git

### Automated Installation (Recommended)

```bash
cd ~/projects/claude-devkit
./scripts/install.sh
```

**What it does:**
- Auto-detects shell (zsh or bash)
- Adds environment variables and PATH
- Creates aliases (gen-skill, gen-agent, validate-skill, etc.)
- Backs up shell config before changes
- Creates optional tree-sitter venv at `~/.claude-devkit/scanner-venv/` for high-fidelity symbol
  extraction (falls back to regex if unavailable)
- Safe to run multiple times (idempotent)

### Verify Installation

```bash
# Check commands are available
which gen-skill
which gen-agent
which validate-skill

# Deploy skills
deploy-skills

# Verify skills deployed
ls ~/.claude/skills/
```

### Manual Installation (Alternative)

```bash
# Add to ~/.zshrc or ~/.bashrc
cat >> ~/.zshrc << 'EOF'

# Claude Devkit
export CLAUDE_DEVKIT="$HOME/projects/claude-devkit"
export PATH="$PATH:$CLAUDE_DEVKIT/generators"

alias gen-skill='python $CLAUDE_DEVKIT/generators/generate_skill.py'
alias gen-agent='python $CLAUDE_DEVKIT/generators/generate_agents.py'
alias gen-architect='python $CLAUDE_DEVKIT/generators/generate_agents.py --type senior-architect'
alias validate-skill='python $CLAUDE_DEVKIT/generators/validate_skill.py'
alias validate-agent='python $CLAUDE_DEVKIT/generators/validate_agent.py'
alias deploy-skills='cd $CLAUDE_DEVKIT && ./scripts/deploy.sh'
EOF

# Reload
source ~/.zshrc

# Deploy skills
deploy-skills

# Verify
which gen-skill gen-agent
```

### Uninstallation

To remove claude-devkit:

```bash
cd ~/projects/claude-devkit
./scripts/uninstall.sh
```

**What it does:**
- Removes environment variables and PATH additions
- Removes aliases
- Restores shell config from backup
- Preserves deployed skills in ~/.claude/skills/

### Per-Project Installation

```bash
# Symlink generators
ln -s ~/projects/claude-devkit/generators/generate_agents.py scripts/

# Copy templates
cp ~/projects/claude-devkit/templates/agents/senior-architect.md.template .claude/templates/

# Use locally
python scripts/generate_agents.py . --type senior-architect
```

## Testing

Run the comprehensive test suite:

```bash
cd ~/projects/claude-devkit
bash generators/test_skill_generator.sh
```

**Test Coverage (66 tests):**
- Generator and validator help text (2 tests)
- All 20 core skills validation (architect, ship, retro, audit, sync,
  receiving-code-review, verification-before-completion, compliance-check,
  dependency-audit, secrets-scan, secure-review, threat-model-gate, fix,
  input-validation-injection, client-side-security, ai-code-review, semgrep,
  build-yaml-misconfiguration, container-hardening, threat-model)
- Knowledge-base archetype positive/negative tests (valid, empty body, missing attribution)
- All 3 contrib skills validation (journal, journal-recall, journal-review)
- All 3 archetypes (coordinator, pipeline, scan)
- Input validation (names, descriptions, paths)
- JSON output
- Negative tests (missing frontmatter, empty steps)
- Metadata comments
- Cleanup

**Expected Output:**
```
Test Summary
========================================
Total:  66
Pass:   66
Fail:   0

✅ All tests passed!
```

### Integration Tests

Run the integration smoke tests to verify audit logging infrastructure end-to-end:

```bash
cd ~/projects/claude-devkit
bash scripts/test-integration.sh
```

**Integration Test Coverage (165 tests):**
- Coordinator lifecycle (generate → validate → deploy → undeploy)
- `validate-all.sh` health check
- Pipeline lifecycle
- Unit meta-test
- `emit-audit-event.sh` multi-call JSONL correctness
- L3 HMAC chain verification
- 10+ call state persistence
- Cleanup
- Threat model consumption structural tests across /ship, /architect, /secure-review (10 tests)
- Codebase-scanner integration tests (8 tests)
- Fix skill structural tests (2 tests)
- Scanner value instrumentation tests (5 tests)
- Quantitative scoring tests (8 tests: 4 positive, 4 negative/edge cases)
- Anti-pattern scan structural tests (6 tests)
- Meta-harness CLI tests (13 tests: 8 functional, 5 security)
- Detached execution tests (20 tests: run ID, flag extraction, watcher lifecycle, jobs/result/logs, cleanup, permissions, path traversal)
- Zero-project-footprint tests (38 tests: project ID, central storage, env vars, migration, helper scripts, security, relink/path, backward compatibility)
- Cross-repo plan tests (29 tests: frontmatter parser, `devkit://` URI resolution, `plan-refs/` files, multi-target `shell`/skill dispatch, `devkit plan` subcommand, `read_plan_refs`, `validate_plan_targets`, path traversal, plan archive)

## Structure

```
claude-devkit/
├── skills/                    # Skill definitions (source of truth)
│   ├── architect/SKILL.md         # Planning with approval gates
│   ├── ship/SKILL.md          # Implementation pipeline
│   ├── retro/SKILL.md         # Retrospective and learnings capture
│   ├── audit/SKILL.md         # Security and performance
│   └── sync/SKILL.md          # Documentation sync
│
├── generators/                # Code generation scripts
│   ├── generate_skill.py              # Create skills
│   ├── generate_agents.py             # Create all project agents (unified)
│   ├── generate_senior_architect.py   # Deprecated wrapper → generate_agents.py
│   ├── validate_skill.py              # Validate skills
│   ├── validate_agent.py              # Validate agents
│   ├── test_skill_generator.sh        # Test suite
│   └── README.md
│
├── templates/                 # Reusable templates
│   ├── skill-coordinator.md.template
│   ├── skill-pipeline.md.template
│   └── skill-scan.md.template
│
├── configs/                   # Shared configurations
│   ├── skill-patterns.json
│   ├── audit-event-schema.json        # JSON Schema for audit events (OTel-aligned)
│   ├── score-dimensions.json          # Score dimension weights and logic (machine-readable)
│   ├── scanner-languages.json         # Language grammar config for codebase scanner
│   ├── scanner-value-thresholds.json  # Thresholds for scanner value cohort analysis
│   ├── devkit-defaults.json           # Default config for the meta-harness CLI
│   ├── tech-stack-definitions/        # Tech stack configs (7 stacks)
│   └── base-definitions/              # (empty - reserved for future)
│
├── scripts/                   # Deployment and utilities
│   ├── deploy.sh              # Deploy skills to ~/.claude/skills/
│   ├── install.sh             # Automated installation
│   ├── uninstall.sh           # Clean uninstallation
│   ├── validate-all.sh        # Health check - validate all skills
│   ├── codebase-scanner.py    # Deterministic codebase symbol index (tree-sitter + regex fallback)
│   ├── devkit_cli.py          # Meta-harness CLI implementation (stdlib only)
│   ├── devkit                 # Meta-harness entry point (thin bash wrapper)
│   ├── emit-audit-event.sh    # Audit event emission helper (invoked by skills)
│   ├── audit-log-query.sh     # Query utility for JSONL audit logs
│   ├── compute-run-score.sh   # Compute per-dimension scores from a JSONL audit log (includes scanner_mode and scanner_tokens fields)
│   ├── score-reflector.sh     # Deterministic score reflector (candidate learnings, scanner-aware cohort analysis)
│   ├── scanner-value-report.sh  # Scanner value cohort analysis report
│   ├── ship-queue.sh          # Sequential /ship runner for unattended batch execution
│   ├── resolve-project-dir.sh # Project artifact directory resolution helper
│   ├── learnings_parser.py    # Deterministic learnings.md → structured JSON parser
│   ├── learnings_aggregator.py # Cross-project learnings discovery and aggregation
│   ├── learnings_promotions.py # Promotion lifecycle state machine (CANDIDATE→PROMOTED)
│   └── test-integration.sh    # Integration smoke tests (165 tests)
│
├── .claude/                   # Project-specific agents
│   └── agents/
│       ├── coder.md
│       ├── code-reviewer.md
│       ├── code-reviewer-specialist.md
│       ├── devkit-architect.md
│       ├── qa-engineer.md
│       ├── security-analyst.md
│       └── senior-architect.md
│
├── CLAUDE.md                  # Detailed documentation
├── README.md                  # This file
└── .gitignore
```

**Centralized artifact storage** (outside target repos — zero footprint in `claude-devkit/`
or any managed project). See [CLAUDE.md](CLAUDE.md) for the full layout:

```
~/.claude-devkit/
├── registry.json                    # Cross-project registry
├── scripts/                         # Deployed helper scripts
├── runs/                            # Detached execution output
└── projects/
    └── <project-id>/                # Per-project artifacts ($DEVKIT_PROJECT_DIR)
        ├── state.json
        ├── plan-refs/                # Cross-repo plan references (JSON)
        │   └── <plan-name>.ref.json
        └── plans/                    # Plans, reviews, audit-logs/, archive/
```

## Workflow Integration

### With Claude Code

Skills are deployed to Claude Code's skill directory:

```
~/.claude/skills/
├── architect/SKILL.md
├── ship/SKILL.md
├── audit/SKILL.md
└── sync/SKILL.md
```

**Deployment:**
1. Edit `~/projects/claude-devkit/skills/*/SKILL.md`
2. Commit to git
3. Run `./scripts/deploy.sh` (or `./scripts/deploy.sh --validate` to block on errors)
4. Use in Claude Code

### With Projects

Generated architects live in project directories:

```
~/projects/my-app/.claude/agents/senior-architect.md
```

**Integration:**
- `/architect` skill checks for project architect
- If not found, prompts to generate
- Agent reads project CLAUDE.md for context

## Troubleshooting

### Skills not recognized

**Issue:** `/<skill-name>` not found

**Solution:**
1. Verify deployment: `ls ~/.claude/skills/<skill-name>/SKILL.md`
2. Restart Claude Code: `/exit` then `claude-code`

### Generator not found

**Issue:** `command not found: gen-skill`

**Solution:**
```bash
echo 'export PATH="$PATH:$HOME/projects/claude-devkit/generators"' >> ~/.zshrc
source ~/.zshrc
```

### Permission denied

**Issue:** `Permission denied` on scripts

**Solution:**
```bash
chmod +x ~/projects/claude-devkit/generators/*.py
chmod +x ~/projects/claude-devkit/scripts/*.sh
```

### Validation fails

**Issue:** Generated skill fails validation

**Solution:** Check template file for bugs. All generated skills should pass validation automatically.

## Documentation

- **[GETTING_STARTED.md](GETTING_STARTED.md)** — 15-minute tutorial for new users
- **[CLAUDE.md](CLAUDE.md)** — Comprehensive documentation (architectural patterns, workflows, troubleshooting)
- **[README.md](README.md)** — This file (quick start, usage examples)
- **[generators/README.md](generators/README.md)** — Generator documentation
- **skills/*/SKILL.md** — Individual skill documentation

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

# Editor
.vscode/
.idea/

# Logs
*.log

# L2/L3 compliance artifacts (staged into project for git tracking)
.devkit-audit-logs/
.devkit-plans/

# Audit run state files (ephemeral — deleted at run end)
.ship-audit-state-*
.architect-audit-state-*
.audit-audit-state-*

# Audit HMAC key files (L3 only — never commit to shared repos)
.ship-audit-key-*
```

### Syncing Across Machines

**Machine 1:**
```bash
cd ~/projects/claude-devkit
git init
git add .
git commit -m "Initial commit"
git remote add origin <repo-url>
git push -u origin main
```

**Machine 2+:**
```bash
cd ~/projects
git clone <repo-url> claude-devkit
cd claude-devkit
./scripts/deploy.sh
```

## Contributing

Contributions welcome:

1. **Add skills** — Generate scaffold, customize, validate
2. **Create generators** — Add to `generators/`
3. **Improve templates** — Enhance archetypes
4. **Write tests** — Extend test suite
5. **Submit PR** — Share improvements

## License

MIT - Use freely in your projects

## Support

- **Issues:** Report bugs or feature requests
- **Documentation:** See `CLAUDE.md` for detailed docs
- **Examples:** Check `skills/` directory for working examples

## Links

- **Claude Code:** https://claude.ai/code
- **Repository:** `~/projects/claude-devkit`
- **Deployment:** `~/.claude/skills/`

---

**Version:** 1.0.0
**Last Updated:** 2026-08-21
**Maintained by:** @backspace-shmackspace
