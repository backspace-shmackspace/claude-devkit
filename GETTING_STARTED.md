# Getting Started with Claude Devkit

**Time to First Skill:** ~15 minutes
**Prerequisites:** Python 3.8+, Claude Code CLI, git

## What is Claude Devkit?

Claude Devkit is the complete toolkit for building with Claude Code. It provides reusable skills (workflows), agent generators, templates, and validation tools to accelerate development with Claude Code.

**What you'll learn:**
- How to install and verify claude-devkit
- How to deploy and use built-in skills (/dream, /ship, /audit, /sync)
- How to generate project agents
- How to create your first custom skill

## Prerequisites

### Required

- **Python 3.8 or higher**
- **Claude Code CLI** installed and configured
- **git**

### Recommended

- zsh or bash shell
- Basic familiarity with Claude Code

### Verify Prerequisites

```bash
python3 --version  # Should be 3.8+
claude-code --version
git --version
```

## Installation (5 minutes)

### Step 1: Clone the Repository

```bash
cd ~/workspaces
git clone <your-repo-url> claude-devkit
cd claude-devkit
```

### Step 2: Run Installation Script

```bash
./scripts/install.sh
```

**What it does:**
- Detects your shell (zsh or bash)
- Adds `CLAUDE_DEVKIT` environment variable
- Adds generators to your PATH
- Creates convenient aliases (gen-skill, gen-agent, validate-skill, etc.)
- Backs up your shell config before making changes

### Step 3: Reload Your Shell

```bash
source ~/.zshrc  # or source ~/.bashrc
```

### Step 3.5: Configure Model Aliases (Optional, Recommended for Vertex AI)

Claude Code's Task tool uses short aliases (`opus`, `sonnet`, `haiku`) when spawning subagents. You can control which model IDs these aliases resolve to via environment variables:

```bash
# Add to ~/.zshrc or ~/.bashrc
export ANTHROPIC_DEFAULT_OPUS_MODEL='claude-opus-4-6[1m]'
export ANTHROPIC_DEFAULT_SONNET_MODEL='claude-sonnet-4-6'
export ANTHROPIC_DEFAULT_HAIKU_MODEL='claude-haiku-4-5@20251001'
```

| Variable | Alias | Description |
|----------|-------|-------------|
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `opus` | Model ID for Opus subagents |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `sonnet` | Model ID for Sonnet subagents |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `haiku` | Model ID for Haiku subagents |

**Why this matters:**
- Without these, aliases resolve to defaults that may not match your deployment
- The `[1m]` suffix on Opus selects the 1M context window variant
- On Vertex AI, date suffixes (e.g., `@20250514`) may not be available for all models — test each alias after setting
- `CLAUDE_CODE_SUBAGENT_MODEL` sets a default model when no explicit `model` is specified in the Task call

**Verify aliases work** by spawning a subagent and asking it to self-report its model ID.

### Step 4: Verify Installation

```bash
# Check commands are available
which gen-skill
which gen-agent
which validate-skill

# Should all return paths like:
# /Users/yourname/workspaces/claude-devkit/generators/generate_skill.py
```

## Quick Start: Your First Skill (10 minutes)

### Step 1: Deploy Built-in Skills

```bash
cd ~/workspaces/claude-devkit
./scripts/deploy.sh
```

**What it does:**
- Copies all skills from `skills/` to `~/.claude/skills/`
- Makes them available in Claude Code

**Verify deployment:**
```bash
ls ~/.claude/skills/
# Should show: audit  dream  ship  sync  test-idempotent
```

### Step 2: Test a Built-in Skill

```bash
# Navigate to any project (or create a test project)
cd ~/projects/my-app

# Start Claude Code
claude-code

# Use /dream skill
/dream add user authentication
```

**What you should see:**
- Architect creates implementation plan
- Red team + Librarian review in parallel
- Revision loop (up to 2 iterations)
- Approval gate with APPROVED/NEEDS_WORK verdict
- Plan saved to `plans/add-user-authentication.md`

### Step 3: Create Your First Custom Skill

```bash
# Generate a new skill (interactive mode)
gen-skill hello-world

# Or with flags (non-interactive)
gen-skill hello-world \
  --description "Say hello with style" \
  --archetype coordinator
```

**What it creates:**
- `~/workspaces/claude-devkit/skills/hello-world/SKILL.md`
- Validated against v2.0.0 patterns
- Ready for customization

### Step 4: Customize Your Skill

```bash
# Open in your editor
code ~/workspaces/claude-devkit/skills/hello-world/SKILL.md
```

**What to customize:**
Replace `[TODO: ...]` placeholders with actual logic:
- Input validation
- Main actions
- Success criteria
- Output formats
- Archive strategy

**Example:**
```markdown
## Step 0 — Greet user

Tool: `Bash`

**Action:**
- [TODO: Define greeting format]
- [TODO: Specify output location]
```

Becomes:
```markdown
## Step 0 — Greet user

Tool: `Bash`

**Action:**
- Echo personalized greeting: "Hello, {user}! Welcome to Claude Code."
- Save greeting to `./greetings/{user}-{timestamp}.txt`
```

### Step 5: Deploy and Test

```bash
# Deploy your skill
cd ~/workspaces/claude-devkit
./scripts/deploy.sh hello-world

# Test it
claude-code
/hello-world Claude
```

## Quick Start: Your First Agent (10 minutes)

### Step 1: Generate Agents for Your Project

```bash
cd ~/projects/my-app

# Auto-detect tech stack and generate all agents
gen-agent . --type all
```

**What it detects:**
- `pyproject.toml` with fastapi → Python FastAPI
- `package.json` with next → Next.js TypeScript
- `package.json` with react → React TypeScript
- Security tools (bandit, safety) → Security-focused Python

**What it generates:**
- `.claude/agents/coder-*.md` (implementation specialist)
- `.claude/agents/qa-*.md` (testing specialist)
- `.claude/agents/code-reviewer.md` (code review)
- `.claude/agents/security-analyst.md` (threat modeling)
- `.claude/agents/senior-architect.md` (high-level design)

### Step 2: Verify Agents Created

```bash
ls .claude/agents/

# Should see files like:
# coder-python.md
# qa-python.md
# code-reviewer.md
# security-analyst.md
# senior-architect.md
```

### Step 3: Test Agent Integration with Skills

```bash
# Start Claude Code
claude-code

# Use /ship skill (requires coder, code-reviewer, qa-engineer agents)
/dream add README file
/ship plans/add-readme-file.md
```

**What happens:**
1. `/ship` reads the plan
2. Uses `coder-*.md` to implement the code
3. Uses `code-reviewer.md` to review the code
4. Revision loop (up to 2 iterations)
5. Runs tests
6. Uses `qa-*.md` to validate acceptance criteria
7. Commits if all checks pass

### Step 4: Customize Agents (Optional)

```bash
# Open agent file
code .claude/agents/coder-python.md
```

**What to customize:**
- Tech Stack Override section (add specific libraries, patterns)
- Add project-specific context from CLAUDE.md
- Define coding standards unique to your team

## Next Steps

### Learn More

- **[Full Documentation](CLAUDE.md)** - Comprehensive guide to all features
- **[README](README.md)** - Quick reference and API docs
- **[Generator Documentation](generators/README.md)** - Deep dive on generators

### Common Workflows

Try these complete workflows:

1. **[Feature Development Lifecycle](CLAUDE.md#workflow-1-feature-development-full-lifecycle)**
   - Plan with /dream
   - Implement with /ship
   - Update docs with /sync
   - Audit with /audit

2. **[Creating Custom Skills](CLAUDE.md#workflow-4-creating-new-skills)**
   - Generate scaffold
   - Customize logic
   - Validate
   - Deploy
   - Test

3. **[Security Audits](CLAUDE.md#workflow-2-security-audit-existing-codebase)**
   - Run /audit full
   - Address critical issues
   - Re-audit
   - Update docs

### Explore Built-in Skills

- **`/dream`** - Implementation planning with approval gates
- **`/ship`** - Code implementation with testing pipeline
- **`/audit`** - Security and performance scanning
- **`/sync`** - Documentation synchronization
- **`/test-idempotent`** - Test skill idempotency

### Create More Skills

Generate skills for your specific workflows:

```bash
# Deployment validation
gen-skill deploy-check -d "Verify deployment health" -a pipeline

# Database migration
gen-skill run-migration -d "Execute database migration" -a pipeline

# Dependency scanning
gen-skill scan-deps -d "Analyze dependencies for vulnerabilities" -a scan
```

### Generate Agents for Other Projects

```bash
# Generate for Next.js project
cd ~/projects/shop-frontend
gen-agent . --type all

# Generate for Python API
cd ~/projects/my-api
gen-agent . --type all

# Generate specific agent with tech stack override
gen-agent . --type coder --tech-stack "Python FastAPI"
```

## Troubleshooting

If you encounter issues, check these resources:

- **[README Troubleshooting](README.md#troubleshooting)** - Common installation issues
- **[CLAUDE.md Troubleshooting](CLAUDE.md#troubleshooting)** - Skill and agent issues
- **[Generator Troubleshooting](generators/README.md#troubleshooting)** - Generator-specific issues

### Common Issues

#### Skills not recognized after deployment

**Issue:** `/<skill-name>` not found

**Solution:**
1. Verify deployment: `ls ~/.claude/skills/<skill-name>/SKILL.md`
2. Restart Claude Code: `/exit` then `claude-code`
3. Check frontmatter has correct `name:` field

#### Generator commands not found

**Issue:** `command not found: gen-skill`

**Solution:**
```bash
# Re-run installation
cd ~/workspaces/claude-devkit
./scripts/install.sh

# Reload shell
source ~/.zshrc
```

#### Agents not discovered by skills

**Issue:** `/ship` reports "No coder agent found"

**Solution:**
1. Verify file exists: `ls .claude/agents/`
2. Check filename matches pattern: `coder*.md`, `qa-engineer*.md`, `code-reviewer*.md`
3. Restart Claude Code: `/exit` then `claude-code`

#### Permission denied on scripts

**Issue:** `Permission denied` when running scripts

**Solution:**
```bash
chmod +x ~/workspaces/claude-devkit/scripts/*.sh
chmod +x ~/workspaces/claude-devkit/generators/*.py
```

## Uninstallation

If you need to remove claude-devkit:

```bash
cd ~/workspaces/claude-devkit
./scripts/uninstall.sh
```

**What it does:**
- Removes `CLAUDE_DEVKIT` environment variable
- Removes PATH additions
- Removes aliases
- Restores shell config from backup
- Preserves deployed skills in `~/.claude/skills/` (manual removal if desired)

---

## What's Next?

You now have:
- ✅ Claude Devkit installed and verified
- ✅ Built-in skills deployed and tested
- ✅ Project agents generated
- ✅ Your first custom skill created

**Ready to dive deeper?**

1. Read [CLAUDE.md](CLAUDE.md) for comprehensive documentation
2. Study [Skill Architectural Patterns](CLAUDE.md#skill-architectural-patterns-v200)
3. Explore [Complete Workflows](CLAUDE.md#complete-workflows)
4. Learn about [Agent Validation](generators/README.md#agent-validation)

**Questions?** Check [CLAUDE.md](CLAUDE.md) for detailed documentation.

---

**Version:** 1.0.0
**Last Updated:** 2026-02-18
**Maintained by:** @backspace-shmackspace
