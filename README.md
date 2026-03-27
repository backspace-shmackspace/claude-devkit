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
/ship plans/add-user-authentication.md
/audit
/sync
```

## What's Included

### Skills (13)

Pre-built workflows for common development tasks:

| Skill | Purpose | Usage |
|-------|---------|-------|
| `/architect` | Create implementation plans with context alignment and approval gates. Detects security-sensitive features and requires threat modeling when threat-model-gate is deployed. | `/architect add shopping cart` |
| `/ship` | Execute plans with pattern validation, security gates (secrets/code/deps), testing, QA, and retro capture. Supports security maturity levels (L1/L2/L3) and `--security-override`. | `/ship plans/feature.md` |
| `/retro` | Mine review artifacts for recurring patterns and capture learnings | `/retro` or `/retro feature-name` |
| `/audit` | Security and performance scanning. Composable: invokes /secure-review when deployed. | `/audit` or `/audit code` |
| `/sync` | Update documentation and CLAUDE.md | `/sync` or `/sync full` |
| `/test-idempotent` | Test skill idempotency and determinism | `/test-idempotent my-skill` |
| `/receiving-code-review` | Code review reception discipline | `/receiving-code-review` |
| `/verification-before-completion` | Evidence-before-claims gate — requires fresh test/build output before completion claims | `/verification-before-completion` |
| `/compliance-check` | Validate against regulatory frameworks (FedRAMP, FIPS, OWASP, SOC 2) | `/compliance-check fedramp fips` |
| `/dependency-audit` | Supply chain security with vulnerability scanning and license compliance | `/dependency-audit` |
| `/secrets-scan` | Pre-commit secrets detection for API keys, tokens, credentials | `/secrets-scan staged` |
| `/secure-review` | Deep semantic security review with data flow tracing | `/secure-review changes` |
| `/threat-model-gate` | Security planning reference for authentication, authorization, data handling | `/threat-model-gate` |

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
- **senior-architect.md.template** — Local architect agent (legacy)

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
/ship plans/add-shopping-cart.md

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
/ship plans/add-user-authentication.md

# Security gates run automatically:
# - Step 0: Secrets scan (blocks if secrets found)
# - Step 4d: Secure code review (blocks at L2/L3 if vulnerabilities found)
# - Step 6: Dependency audit (blocks at L2/L3 if vulnerable deps found)

# 3. Override security gate if needed (false positive or time-sensitive)
/ship plans/add-user-authentication.md --security-override "False positive: test fixture data"

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
/ship plans/add-checkout-flow.md
```

## Available Skills

### `/architect` - Implementation Planning

Creates detailed implementation plans with red team review and approval gates.

**Usage:**
```bash
/architect add user authentication
/architect --fast create API endpoints  # Skip red team review
```

**Output:**
- `plans/[feature].md` — Approved implementation plan
- `plans/[feature].redteam.md` — Red team critique
- `plans/[feature].feasibility.md` — Feasibility review
- `plans/[feature].review.md` — Librarian review

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
/ship plans/add-user-authentication.md
/ship plans/feature.md --security-override "reason"
```

**Options:**
- `--security-override "reason"` — Override security BLOCKED verdicts with logged reason

**Output:**
- Implemented code changes
- `plans/archive/[feature]/[feature].code-review.md` — Code review
- `plans/archive/[feature]/[feature].qa-report.md` — QA report
- Git commit (on approval)

**Workflow:**
1. Pre-flight checks (plan exists, tests pass, security skills deployed at L2/L3)
2. Secrets scan (if /secrets-scan deployed)
3. Read and validate plan
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
- `plans/audit-[timestamp].summary.md` — Audit summary
- `plans/audit-[timestamp].security.md` — Security findings
- `plans/audit-[timestamp].performance.md` — Performance findings
- `plans/audit-[timestamp].qa.md` — QA regression results

**Workflow:**
1. Detect scope (plan/code/full)
2. Parallel scans (security + performance)
3. QA regression testing
4. Synthesis with severity ratings
5. Verdict (PASS/PASS_WITH_NOTES/BLOCKED)
6. Archive reports

### `/sync` - Documentation Sync

Updates CLAUDE.md and documentation with current patterns.

**Usage:**
```bash
/sync           # Sync recent changes (last 7 days)
/sync full      # Sync all files
```

**Output:**
- `plans/sync-[timestamp].review.md` — Librarian review
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
alias gen-architect='python $CLAUDE_DEVKIT/generators/generate_senior_architect.py'
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
ln -s ~/projects/claude-devkit/generators/generate_senior_architect.py scripts/

# Copy templates
cp ~/projects/claude-devkit/templates/senior-architect.md.template .claude/templates/

# Use locally
python scripts/generate_senior_architect.py .
```

## Testing

Run the comprehensive test suite:

```bash
cd ~/projects/claude-devkit
bash generators/test_skill_generator.sh
```

**Test Coverage (46 tests):**
- Generator and validator help text (2 tests)
- All 13 core skills validation (architect, ship, retro, audit, sync,
  test-idempotent, receiving-code-review, verification-before-completion,
  compliance-check, dependency-audit, secrets-scan, secure-review,
  threat-model-gate)
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
Total:  46
Pass:   46
Fail:   0

✅ All tests passed!
```

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
│   ├── generate_senior_architect.py   # Create architects
│   ├── validate_skill.py              # Validate skills
│   ├── test_skill_generator.sh        # Test suite
│   └── README.md
│
├── templates/                 # Reusable templates
│   ├── senior-architect.md.template
│   ├── skill-coordinator.md.template
│   ├── skill-pipeline.md.template
│   └── skill-scan.md.template
│
├── configs/                   # Shared configurations
│   ├── skill-patterns.json
│   ├── agent-patterns.json
│   ├── tech-stack-definitions/    # Tech stack configs (7 stacks)
│   └── base-definitions/          # (empty - reserved for future)
│
├── scripts/                   # Deployment and utilities
│   ├── deploy.sh              # Deploy skills to ~/.claude/skills/
│   ├── install.sh             # Automated installation
│   ├── uninstall.sh           # Clean uninstallation
│   └── validate-all.sh        # Health check - validate all skills
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
**Last Updated:** 2026-03-27
**Maintained by:** @backspace-shmackspace
