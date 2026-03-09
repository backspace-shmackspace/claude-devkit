# Generators

Tools for generating Claude Code resources: local agents and skill definitions.

## Overview

These scripts create local agents that:
- Use Claude Opus 4.6 model for high-capability tasks
- Provide high-level design and implementation planning
- Generate detailed blueprints saved to `./plans/`
- Can be customized per-project for domain-specific expertise

## Scripts

### generate_senior_architect.sh (Bash)

Simple bash script for quick generation.

**Usage:**
```bash
./scripts/generate_senior_architect.sh [target-directory] [project-type]
```

**Examples:**
```bash
# Generate in current directory
./scripts/generate_senior_architect.sh . "Next.js TypeScript React"

# Generate in another project
./scripts/generate_senior_architect.sh ~/projects/my-app "Python FastAPI"

# Generate in parent directory
./scripts/generate_senior_architect.sh .. "Rust CLI"
```

### generate_senior_architect.py (Python)

More feature-rich Python version with auto-detection.

**Usage:**
```bash
python scripts/generate_senior_architect.py [target-directory] --project-type TYPE
```

**Examples:**
```bash
# Auto-detect project type from package.json, requirements.txt, etc.
python scripts/generate_senior_architect.py ~/projects/my-app

# Specify project type explicitly
python scripts/generate_senior_architect.py . --project-type "Next.js 14 TypeScript 5.3"

# Overwrite existing agent
python scripts/generate_senior_architect.py . --force
```

**Auto-Detection:**
The Python script detects project type from:
- `package.json` → Next.js, React, Vue, Express, etc.
- `requirements.txt` → Python
- `Cargo.toml` → Rust
- `go.mod` → Go
- `pom.xml` / `build.gradle` → Java
- And more...

## What Gets Created

**File:** `.claude/agents/senior-architect.md`

**Structure:**
```markdown
---
name: senior-architect
description: "High-level design and implementation planning..."
model: claude-opus-4-6
color: purple
---

# Identity
...

# Mission
...

# Project Context
**Project:** my-app
**Stack:** Next.js TypeScript React
**Patterns:** (Discovered from CLAUDE.md)

# Operating Rules
...

# Output Contract
...
```

## Post-Generation Steps

1. **Review and customize** the generated agent:
   ```bash
   code .claude/agents/senior-architect.md
   ```

2. **Update Project Context section:**
   - Add specific stack versions (e.g., "Next.js 14.1, TypeScript 5.3")
   - Add project-specific patterns from CLAUDE.md
   - Include common file paths and directory conventions
   - Add refusal conditions for project constraints

3. **Restart Claude Code session** to register the agent:
   ```bash
   # Exit and restart claude-code CLI
   /exit
   claude-code
   ```

4. **Test the agent:**
   ```
   Use the senior-architect agent to create a plan for adding user authentication
   ```

## Using with /dream Skill

The updated `/dream` skill automatically discovers senior-architect agents:

1. Checks local `.claude/agents/senior-architect.md`
2. If not found, recurses up directory tree
3. If not found anywhere, prompts to create one

**Workflow:**
```bash
# In a new project without an architect
/dream add OAuth authentication

# Claude prompts:
"No senior-architect agent found. Create one? (y/N)"

# If yes, generates agent and continues with planning
```

## Distribution

### Copy to Other Projects Manually

```bash
# Copy to another project
cp scripts/generate_senior_architect.py ~/projects/other-project/

# Or make it globally available
cp scripts/generate_senior_architect.py ~/bin/
chmod +x ~/bin/generate_senior_architect.py
```

### Install as Global Tool

Add to your `~/.bashrc` or `~/.zshrc`:
```bash
alias gen-agent='python ~/projects/claude-devkit/generators/generate_agents.py'
alias gen-architect='python ~/projects/claude-devkit/generators/generate_senior_architect.py'
```

Or use the automated installer:
```bash
cd ~/projects/claude-devkit
./scripts/install.sh
```

Then use from anywhere:
```bash
cd ~/projects/my-app
gen-agent . --type all
```

## Integration with Workspaces

These scripts can be added to the `workspaces` project for centralized project tooling.

**Recommended structure:**
```
workspaces/
├── tools/
│   ├── generate-senior-architect.py
│   ├── generate-senior-architect.sh
│   └── README.md
└── templates/
    └── senior-architect.md.template
```

## Customization Examples

### Example 1: Next.js E-commerce

```markdown
# Project Context

**Project:** shop-frontend
**Stack:** Next.js 14, TypeScript 5.3, Tailwind CSS, Stripe, PostgreSQL
**Patterns:**
- App Router (not Pages Router)
- Server Components by default
- Client Components only when needed (use 'use client')
- API routes in app/api/
- Stripe webhooks in app/api/webhooks/stripe/
- Database queries via Drizzle ORM
```

### Example 2: Python Microservice

```markdown
# Project Context

**Project:** payment-service
**Stack:** Python 3.12, FastAPI, PostgreSQL, Redis, Docker
**Patterns:**
- Async handlers for all routes
- Database migrations via Alembic
- Redis for caching and rate limiting
- Structured logging with structlog
- OpenAPI schema auto-generated
- Health checks at /health and /health/ready
```

### Example 3: Rust CLI Tool

```markdown
# Project Context

**Project:** deploy-cli
**Stack:** Rust 1.75, Clap 4.x, Tokio async runtime
**Patterns:**
- Subcommands for operations (deploy, rollback, status)
- Config file in ~/.deploy/config.toml
- Error handling via anyhow
- Progress bars via indicatif
- Cross-platform builds (Linux, macOS, Windows)
```

## Troubleshooting

### Agent Not Found After Generation

**Issue:** "Agent type 'senior-architect' not found"

**Solution:** Restart Claude Code session to register new agent files.

### Agent Uses Wrong Model

**Issue:** Agent not using claude-opus-4-6

**Solution:** Check frontmatter in `.claude/agents/senior-architect.md`:
```yaml
---
model: claude-opus-4-6  # Must be exactly this
---
```

### Agent Has No Domain Knowledge

**Issue:** Generic responses, not project-specific

**Solution:** Customize the "Project Context" section with:
- Specific stack versions
- Project patterns from CLAUDE.md
- Common file paths
- Domain-specific terminology

### Permission Denied

**Issue:** `Permission denied` when running scripts

**Solution:** Make scripts executable:
```bash
chmod +x scripts/generate_senior_architect.sh
chmod +x scripts/generate_senior_architect.py
```

## Related Documentation

- [Senior Architect Deactivation Summary](../docs/SENIOR_ARCHITECT_DEACTIVATION.md)
- [Local Agents README](../.claude/agents/README.md)
- [Claude Code Documentation](https://claude.ai/code)

---

# Skill Generator

Tools for generating Claude Code skill definitions (`SKILL.md` files) from templates.

## Overview

The skill generator creates valid `SKILL.md` files following v2.0.0 architectural patterns. It scaffolds skills from three archetypes (coordinator, pipeline, scan) with:
- YAML frontmatter with required fields
- Numbered workflow steps with tool declarations
- Verdict gates (PASS/FAIL/BLOCKED)
- Timestamped artifact outputs
- Archive steps for completed work

Generated skills are validated automatically and can be deployed to `~/.claude/skills/` immediately.

## Quick Start

```bash
# Generate a coordinator skill (delegates to agents, revision loops)
python generate_skill.py deploy-check --description "Verify deployment health"

# Generate a pipeline skill (sequential validation checkpoints)
python generate_skill.py run-tests --archetype pipeline --description "Execute test suite"

# Generate a scan skill (parallel analysis, severity ratings)
python generate_skill.py scan-deps --archetype scan --description "Analyze dependencies"

# Generate and deploy immediately
python generate_skill.py my-skill --description "My new skill" --deploy
```

## Archetypes

| Archetype | Description | Based On | Steps | Use Cases |
|-----------|-------------|----------|-------|-----------|
| **coordinator** | Delegates work to agents, parallel reviews, revision loops | `/dream` | 4-6 | Planning, research, multi-agent workflows |
| **pipeline** | Sequential workflow with validation checkpoints | `/ship` | 6-8 | Implementation, testing, deployment |
| **scan** | Parallel analysis, severity ratings, synthesis | `/audit` | 4-6 | Security scans, code quality, audits |

### Coordinator Pattern

- Delegates core work to specialist agents
- Runs parallel quality reviews
- Bounded revision loops (max 2 rounds)
- Verdict gates block progression on failures
- Archives approved artifacts

**Example:** `/dream` — delegates to architect, runs red team + librarian reviews, revises plan up to 2 times.

### Pipeline Pattern

- Sequential execution with checkpoints
- Pre-flight environment checks
- Implementation → Review → Test → Deploy
- Bounded revision loops between stages
- Commit gate at the end

**Example:** `/ship` — validates plan, implements code, reviews, runs tests, validates acceptance criteria, commits.

### Scan Pattern

- Determines scan scope (plan, code, full)
- Runs parallel analysis tasks
- Synthesizes results with severity ratings (Critical/High/Medium/Low)
- Verdict based on risk score
- Archives all reports

**Example:** `/audit` — runs security, performance, and QA scans in parallel, synthesizes findings, gates on critical issues.

## Scripts

### generate_skill.py (Python)

Main generator script with full validation and atomic writes.

**Usage:**
```bash
python generate_skill.py <skill-name> [options]
```

**Options:**
```
--description, -d   One-line skill description (required for non-interactive)
--archetype, -a     Workflow archetype: coordinator, pipeline, scan (default: coordinator)
--model, -m         Claude model: claude-opus-4-6, claude-sonnet-4-5 (default: claude-opus-4-6)
--version, -v       Skill version (default: 1.0.0)
--steps, -s         Number of workflow steps (default: 4)
--target-dir, -t    Target directory containing skills/ (default: ~/projects/claude-devkit)
--deploy            Run deploy.sh after generation
--force, -f         Overwrite existing skill without prompting
```

**Examples:**
```bash
# Interactive mode (prompts for all inputs)
python generate_skill.py check-config

# Generate coordinator with custom model
python generate_skill.py plan-feature -d "Create feature plan" -a coordinator -m claude-sonnet-4-5

# Generate pipeline and deploy immediately
python generate_skill.py run-migration -d "Run database migration" -a pipeline --deploy

# Generate to custom directory
python generate_skill.py my-skill -d "Custom skill" -t ~/my-project --force
```

**Interactive Mode:**
If `--description` is not provided, the generator prompts for:
- Description
- Archetype (with explanations)
- Model
- Number of steps

### generate_skill.sh (Bash)

Thin bash wrapper for quick generation.

**Usage:**
```bash
./generate_skill.sh <name> [archetype] [target-dir]
```

**Examples:**
```bash
# Generate coordinator (default archetype)
./generate_skill.sh deploy-check

# Generate scan archetype
./generate_skill.sh scan-deps scan

# Generate to custom directory
./generate_skill.sh my-skill coordinator ~/my-project
```

### validate_skill.py (Validator)

Validates skill definitions against all 10 v2.0.0 architectural patterns.

**Usage:**
```bash
python validate_skill.py <path-to-SKILL.md> [--strict] [--json]
```

**What It Checks:**

| Pattern | Check |
|---------|-------|
| 1. Coordinator pattern | Role section contains delegation language |
| 2. Numbered steps | All steps match `## Step N -- [Action]` format |
| 3. Tool declarations | Every step has `Tool:` line |
| 4. Verdict gates | At least one PASS/FAIL/BLOCKED logic |
| 5. Timestamped artifacts | References `[timestamp]` or ISO datetime |
| 6. Structured reporting | Outputs to `./plans/` directory |
| 7. Bounded iterations | Revision loops have `Max N revision` language |
| 8. Model selection | Valid `model:` in YAML frontmatter |
| 9. Scope parameters | `## Inputs` section with `$ARGUMENTS` |
| 10. Archive on success | References `./plans/archive/` |

**Structural Checks:**
- Valid YAML frontmatter with `---` delimiters
- Required fields: `name`, `description`, `model`
- Workflow header: `# /skill-name Workflow`
- Minimum 2 numbered steps
- No empty steps

**Output Formats:**
```bash
# Human-readable report (default)
python validate_skill.py ~/projects/claude-devkit/skills/dream/SKILL.md

# JSON output for CI integration
python validate_skill.py ./skills/ship/SKILL.md --json

# Strict mode (warnings become errors)
python validate_skill.py ./skills/audit/SKILL.md --strict
```

**Exit Codes:**
- `0` = Validation passed
- `1` = Validation failed (errors found)
- `2` = Invalid arguments or file not found

## Generated File Structure

Every generated skill follows this structure:

```markdown
---
name: skill-name
description: One-line description
model: claude-opus-4-6
version: 1.0.0
---
# /skill-name Workflow

## Role
(Coordinator pattern explanation - for coordinator archetype)

## Inputs
- Parameters: $ARGUMENTS

## Step 0 — [First step]
Tool: [Tool name]
[Step logic with TODO placeholders]

## Step 1 — [Second step]
Tool: [Tool name]
[Step logic with TODO placeholders]

...

## Step N — Final verdict gate
**If PASS:** [Success actions]
**If FAIL:** [Failure actions]

<!-- Generated by claude-tools/generators/generate_skill.py v1.0.0 -->
<!-- Archetype: coordinator | Generated: 2026-02-08T14-30-00 -->
```

## Workflow

1. **Generate** — `generate_skill.py` creates `skills/<name>/SKILL.md`
2. **Validate** — Automatically runs `validate_skill.py` on generated file
3. **Deploy** (optional) — If `--deploy` flag set, runs `deploy.sh <name>`
4. **Customize** — Replace `[TODO: ...]` placeholders with actual logic
5. **Test** — Use the skill: `/<skill-name> [arguments]`

## Input Validation

All inputs are validated before any file operations:

### Skill Name Rules
- Lowercase alphanumeric + hyphen only
- 2-30 characters
- No leading/trailing hyphens
- Not a reserved name (dream, ship, audit, sync)

### Description Rules
- Max 200 characters
- Single line (no newlines)
- No YAML-breaking characters (leading `:`, bare `---`)
- No control characters

### Target Directory Rules
- Must exist and be writable
- Must be under `~/projects/` or `/tmp/`
- No path traversal allowed

## Error Handling

The generator uses atomic writes and rollback on failure:

| Failure Point | Rollback Action |
|---------------|----------------|
| Validation fails after generation | Generated file is removed, error details printed |
| Deploy fails after validation passes | Generated file preserved, user can manually deploy |
| Generation fails mid-write | Temp file cleaned up, no partial SKILL.md left |

**Atomic Writes:**
- Write to temp file in same directory
- Atomic rename on success (POSIX `os.replace()`)
- Automatic cleanup on any failure

## Integration with claude-devkit

The generator is designed to work with the `claude-devkit` deployment workflow:

1. Generate into `~/projects/claude-devkit/skills/<name>/SKILL.md`
2. Customize the skill (replace TODO placeholders)
3. Run `cd ~/projects/claude-devkit && ./deploy.sh <name>`
4. Skill is copied to `~/.claude/skills/<name>/SKILL.md`
5. Restart Claude Code to register the skill
6. Use with `/<skill-name> [arguments]`

**With `--deploy` flag:**
Steps 3-4 happen automatically after validation passes.

## Customization

Generated skills contain `[TODO: ...]` placeholders marking areas requiring customization:

- **Validation checks:** Define required parameters and validation rules
- **Main actions:** Replace generic prompts with specific logic
- **Success criteria:** Define what "PASS" means for this workflow
- **Output files:** Specify artifact paths and formats
- **Archive strategy:** Decide what to preserve and where

**Example:**
```markdown
## Step 1 — Validate deployment

Tool: `Bash`

**Checks:**
- [TODO: List required environment variables]
- [TODO: Define health check endpoints]
- [TODO: Specify service dependencies]
```

Becomes:
```markdown
## Step 1 — Validate deployment

Tool: `Bash`

**Checks:**
- Required environment variables: `DATABASE_URL`, `API_KEY`, `STRIPE_SECRET`
- Health check endpoints: `/health`, `/health/ready`, `/health/db`
- Service dependencies: PostgreSQL, Redis, S3
```

## Testing

### Test Suite: Skill Generator

Run the test suite to verify generator functionality:

```bash
cd ~/projects/claude-devkit
bash generators/test_skill_generator.sh
```

**Test Coverage (26 tests):**
- Generator and validator help text
- Validation of all 4 production skills (dream, ship, audit, sync)
- Generation of all 3 archetypes (coordinator, pipeline, scan)
- Validation of generated skills
- Input validation (reject invalid names, descriptions, paths)
- JSON output format
- Negative tests (missing frontmatter, empty steps, etc.)
- Metadata comment presence
- Cleanup

**Expected Output:**
```
Test Summary
========================================
Total:  26
Pass:   26
Fail:   0

✅ All tests passed!
```

### Test Suite: Ship Worktree Isolation

Run the test suite to verify /ship v3.1.0 worktree isolation feature:

```bash
cd ~/projects/claude-devkit
bash generators/test_ship_worktree.sh
```

**Test Coverage (6 scenarios):**
1. **Single Work Group (Backward Compatibility)** - Verify no worktrees created, current behavior preserved
2. **Multiple Work Groups (Happy Path)** - Verify 2 worktrees created, agents work in parallel, validation passes, merge succeeds
3. **Shared Dependencies** - Verify shared deps committed first, work groups use that base
4. **File Boundary Violation (Negative Test)** - Verify validation detects when agent modifies file outside scope
5. **Revision Loop with Worktrees** - Verify worktrees re-created for revisions
6. **Cleanup on Failure** - Verify worktrees cleaned up even if validation fails

**What It Tests:**
- Git worktree creation and cleanup (no orphaned worktrees)
- File boundary validation (detects scope violations)
- Worktree merge logic (copies only scoped files)
- Shared dependencies workflow (committed before work groups)
- Revision loop isolation (worktrees re-created)
- Error handling (cleanup on failure)

**Expected Output:**
```
========================================
Test Summary
========================================
Total:  6
Pass:   6
Fail:   0

✅ All tests passed!

The worktree isolation feature is working correctly:
  ✓ Single work groups maintain backward compatibility
  ✓ Multiple work groups use worktree isolation
  ✓ Shared dependencies are committed first
  ✓ File boundary violations are detected
  ✓ Revision loops recreate worktrees
  ✓ Cleanup happens even on failure
```

**Test Environment:**
- Creates isolated git repository in `/tmp/ship-worktree-test-$$`
- Tests worktree creation, validation, merge, and cleanup
- Verifies no orphaned worktrees using `git worktree list`
- Simulates multi-agent parallel work
- Cleans up completely after all tests

## Troubleshooting

### Validation Fails on Generated Skill

**Issue:** Generated skill fails validation immediately after creation.

**Solution:** This indicates a bug in the template. Check the template file at `templates/skill-<archetype>.md.template` and ensure all required patterns are present.

### Deploy Fails with "deploy.sh not found"

**Issue:** `--deploy` flag requires `deploy.sh` at target directory.

**Solution:** Either:
1. Don't use `--deploy` flag (deploy manually later)
2. Ensure target directory is a valid `claude-devkit` repo with `deploy.sh`

### Generated Skill Has Generic Prompts

**Issue:** Skill works but doesn't do anything useful.

**Solution:** This is expected! Generated skills are scaffolds. Replace all `[TODO: ...]` placeholders with actual logic specific to your use case.

### Skill Not Discovered by Claude Code

**Issue:** `/<skill-name>` not recognized after deployment.

**Solution:**
1. Verify file exists at `~/.claude/skills/<skill-name>/SKILL.md`
2. Restart Claude Code session to re-scan skill directory
3. Check YAML frontmatter has correct `name:` field

### Path Traversal Rejected

**Issue:** `Target directory must be under ~/projects/ or /tmp/`

**Solution:** For security, generator only writes to known safe locations. Use `~/projects/` for real projects or `/tmp/` for testing.

---

# Unified Agent Generator

Comprehensive agent generation system supporting all Claude Code agent types.

## Overview

The unified agent generator creates specialist agents that inherit from base agents (from `~/projects/.config/agents/base/`) and customize them for specific tech stacks.

**Supported Agent Types:**
- `coder` - Code implementation specialist
- `qa-engineer` - Testing and validation specialist
- `code-reviewer` - Code review (standalone or specialist)
- `security-analyst` - Threat modeling and security planning
- `senior-architect` - High-level design and planning

## Quick Start

```bash
# Generate coder agent (auto-detects tech stack)
python3 generate_agents.py . --type coder

# Generate all agents for a project
python3 generate_agents.py . --type all

# Generate with specific tech stack override
python3 generate_agents.py . --type qa-engineer --tech-stack "Python FastAPI"

# Force overwrite existing agents
python3 generate_agents.py . --type all --force
```

## Architecture

### Three-Tier Inheritance

```
Tier 1: Base Agents (~/projects/.config/agents/base/)
  ↓ inherits
Tier 2: Specialist Agents (.claude/agents/)
  ↓ reads at runtime
Tier 3: Runtime Context (CLAUDE.md)
```

**Base Agents (Universal Standards):**
- `coder-base.md` v2.1.0 - Universal coding standards
- `qa-engineer-base.md` v1.8.0 - Universal testing principles
- `code-reviewer-base.md` v1.0.0 - Universal code review standards
- `architect-base.md` v1.5.0 - Universal design patterns

**Specialist Agents (Tech-Specific):**
Generated by this tool, customized per tech stack:
- Replace placeholders like `[TECH_STACK_PLACEHOLDER]`
- Reference CLAUDE.md for project patterns
- Add tech-specific quality standards

## Auto-Detection

The generator auto-detects tech stack from project files:

| Project File | Detected Stack | Agent Variant |
|--------------|---------------|---------------|
| `pyproject.toml` with fastapi | Python FastAPI | coder-python, qa-python |
| `pyproject.toml` with bandit/safety | Python Security | coder-security, qa-security |
| `package.json` with next | Next.js TypeScript | coder-frontend, qa-frontend |
| `package.json` with react | React TypeScript | coder-typescript, qa-frontend |
| `package.json` with astro | Astro | coder-frontend, qa-frontend |
| `tsconfig.json` | TypeScript | coder-typescript |

## Generated Agents

### coder (Code Implementation)

**Variants:**
- `coder-security.md` - Security-focused Python projects
- `coder-frontend.md` - React, Next.js, Astro projects
- `coder-python.md` - General Python projects
- `coder-typescript.md` - TypeScript projects
- `coder.md` - Generic coder (no specific tech stack detected)

**Inherits From:** `coder-base.md` v2.1.0

**Tech Stack Configs:**
- Python: Type hints, pytest, mypy, black
- FastAPI: Async handlers, Pydantic validation, OpenAPI
- TypeScript: Strict mode, ESLint, Prettier
- React: Hooks, React Testing Library, a11y
- Next.js: App Router, Server Components, next/image
- Astro: Static-first, partial hydration, content collections

### qa-engineer (Testing and Validation)

**Variants:**
- `qa-security.md` - Security testing, OWASP Top 10
- `qa-frontend.md` - Component testing, E2E, accessibility
- `qa-python.md` - pytest, coverage, integration tests
- `qa-engineer.md` - Generic QA

**Inherits From:** `qa-engineer-base.md` v1.8.0

**Testing Frameworks:**
- Python: pytest, coverage, bandit
- TypeScript: Vitest, Jest, Playwright
- Frontend: React Testing Library, Playwright, Vitest

### code-reviewer (Code Review)

**Type:** Standalone (no inheritance) or Specialist

**Files:**
- `code-reviewer.md` - Standalone (for /ship skill)
- `code-reviewer-security.md` - Security-focused specialist
- `code-reviewer-performance.md` - Performance-focused specialist

The standalone code-reviewer is fully self-contained and doesn't inherit from a base. It's designed specifically for the /ship skill's code review step.

**Review Dimensions:**
- Code Quality (SOLID, DRY, KISS)
- Security (OWASP Top 10)
- Performance (Algorithm complexity, N+1 queries)
- Maintainability (Readability, comments)
- Error Handling (Edge cases, validation)
- Testability (Unit tests, coverage)

### security-analyst (Threat Modeling)

**Files:**
- `security-analyst.md`

**Inherits From:** `architect-base.md` v1.5.0

**Capabilities:**
- STRIDE threat modeling
- DREAD risk rating
- Attack surface analysis
- Security architecture design
- Compliance planning (OWASP, GDPR, SOC 2)
- Outputs to `./plans/security-*`

### senior-architect (High-Level Design)

**Files:**
- `senior-architect.md`

**Inherits From:** `architect-base.md` v1.5.0 (indirectly - uses custom template)

**Capabilities:**
- Architectural analysis
- Technology recommendations
- Implementation plans with phases
- Risk assessment
- Deployment topology
- Outputs to `./plans/`

## Tech Stack Configurations

Located in `configs/tech-stack-definitions/*.json`:

```
configs/tech-stack-definitions/
├── python.json         # Python 3.11+ standards
├── fastapi.json        # FastAPI framework
├── typescript.json     # TypeScript 5.x
├── react.json          # React 18+
├── nextjs.json         # Next.js 14+ App Router
├── astro.json          # Astro 4.x
└── security.json       # Security-focused Python
```

Each config includes:
- Language and version
- Framework and tools
- Code quality standards
- Testing strategy
- Build configuration
- Security requirements (for security configs)

## Agent Validation

Validate generated agents to ensure they follow inheritance patterns:

```bash
# Validate single agent
python3 validate_agent.py .claude/agents/coder-security.md

# Validate all agents
python3 validate_agent.py .claude/agents/*.md

# Strict mode (warnings become errors)
python3 validate_agent.py .claude/agents/*.md --strict

# JSON output for CI
python3 validate_agent.py .claude/agents/*.md --json
```

**Validation Checks:**
- ✅ Inheritance header present (specialist agents)
- ✅ Base agent and version references valid
- ✅ Tech Stack Override section present
- ✅ CLAUDE.md reference (`**READ FIRST:** ../../../CLAUDE.md`)
- ✅ No base agent content duplication
- ✅ Conflict resolution section present
- ✅ Specialist ID matches filename

## Testing

Run comprehensive test suite:

```bash
bash test_agent_generator.sh
```

**Test Coverage (30 tests):**
- Generator and validator help text
- Generate coder (Python, TypeScript variants)
- Generate QA engineer (Python, frontend variants)
- Generate code-reviewer (standalone)
- Generate security-analyst
- Generate all agents
- Auto-detection (Python, TypeScript, security tools)
- Validation (valid and invalid agents)
- JSON output
- Force overwrite
- Tech stack override

**Expected Output:**
```
═══════════════════════════════════════════
Test Summary
═══════════════════════════════════════════
Tests run: 30
Tests passed: 30
Tests failed: 0

All tests passed!
```

## Integration with Skills

The generated agents are used by skills:

### /ship Skill
**Requires:**
- `.claude/agents/coder*.md` (Step 2: Implementation)
- `.claude/agents/code-reviewer*.md` (Step 3: Code review)
- `.claude/agents/qa-engineer*.md` or `.claude/agents/qa*.md` (Step 6: QA validation)

**Graceful Degradation:**
If agents missing, /ship stops with helpful error messages:
```
❌ No coder agent found. Generate one using:
  python3 ~/projects/claude-devkit/generators/generate_agents.py . --type coder
```

### /audit Skill
**Optionally Uses:**
- `.claude/agents/qa-engineer*.md` or `.claude/agents/qa*.md` (Step 4: QA regression)

**Graceful Degradation:**
If qa-engineer missing, /audit skips regression tests and writes a note to the report (non-blocking).

### /dream Skill
**Optionally Uses:**
- `.claude/agents/senior-architect.md` (Step 1: Plan drafting)

**Graceful Degradation:**
If missing, suggests generating and falls back to MCP architect.

## Usage Examples

### New Python FastAPI Project

```bash
cd ~/projects/my-api

# Project has pyproject.toml with fastapi dependency
cat pyproject.toml
# [project]
# dependencies = ["fastapi", "uvicorn", "pytest"]

# Generate all agents
python3 ~/projects/claude-devkit/generators/generate_agents.py . --type all

# Generated agents:
# .claude/agents/coder-python.md
# .claude/agents/qa-python.md
# .claude/agents/code-reviewer.md
# .claude/agents/security-analyst.md
# .claude/agents/senior-architect.md

# Validate
python3 ~/projects/claude-devkit/generators/validate_agent.py .claude/agents/*.md

# Use with skills
/dream add JWT authentication
/ship plans/add-jwt-authentication.md
/audit
```

### Security-Focused Project

```bash
cd ~/projects/secure-api

# Project has security tools
cat pyproject.toml
# [project.optional-dependencies]
# dev = ["bandit", "safety", "pytest"]

# Generate all agents (auto-detects security focus)
python3 ~/projects/claude-devkit/generators/generate_agents.py . --type all

# Generated agents:
# .claude/agents/coder-security.md    # Security variant
# .claude/agents/qa-security.md       # Security testing variant
# .claude/agents/code-reviewer.md
# .claude/agents/security-analyst.md
# .claude/agents/senior-architect.md
```

### Next.js TypeScript Project

```bash
cd ~/projects/shop-frontend

# Project has package.json with Next.js
cat package.json
# {
#   "dependencies": {
#     "next": "14.1.0",
#     "react": "18.2.0"
#   }
# }

# Generate all agents
python3 ~/projects/claude-devkit/generators/generate_agents.py . --type all

# Generated agents:
# .claude/agents/coder-frontend.md    # Frontend variant
# .claude/agents/qa-frontend.md       # Frontend testing variant
# .claude/agents/code-reviewer.md
# .claude/agents/security-analyst.md
# .claude/agents/senior-architect.md
```

## Troubleshooting

### Agent Not Found After Generation

**Issue:** Skills report "No coder agent found"

**Solution:**
1. Verify file exists: `ls .claude/agents/`
2. Check filename matches expected pattern: `coder*.md`, `qa-engineer*.md`, `code-reviewer*.md`
3. Restart Claude Code session: `/exit` then `claude-code`

### Validation Fails

**Issue:** `validate-agent` reports errors

**Common Issues:**
- Missing CLAUDE.md reference → Add `**READ FIRST:** ../../../CLAUDE.md`
- Missing inheritance header → Ensure `# Inheritance` section present
- Base version mismatch → Update to match current base agent version

### Wrong Tech Stack Detected

**Issue:** Generated `coder-frontend.md` but project is Python

**Solution:** Use `--tech-stack` override:
```bash
python3 generate_agents.py . --type coder --tech-stack "Python FastAPI"
```

### Missing tomli Dependency

**Issue:** Error importing `tomli` when reading `pyproject.toml`

**Solution:** The generator has fallback logic:
- Python 3.11+: Uses built-in `tomllib`
- Python <3.11: Tries `tomli`, falls back to text parsing
- If parsing fails, uses generic Python config

## Version History

### Unified Agent Generator

- **2026-02-08**: Initial release (v1.0.0)
  - All 6 agent types supported
  - Auto-detection for Python, TypeScript, React, Next.js, Astro
  - 7 tech stack configurations
  - Comprehensive validator with strict mode
  - Test suite with 15 tests
  - Integration with /ship, /audit, /dream skills

### Skill Generator

- **2026-02-08**: Initial release (v1.0.0)
  - Three archetypes: coordinator, pipeline, scan
  - Automatic validation against 10 v2.0.0 patterns
  - Input sanitization and atomic writes
  - Optional deployment via `--deploy` flag
  - Interactive and CLI modes

### Senior Architect Generator

- **2026-02-08**: Initial release
  - Bash and Python generator scripts
  - Auto-detection of project type
  - Integration with /dream skill
  - **Note:** Now superseded by unified agent generator (generate_agents.py)
  - **Recommendation:** Use `gen-agent . --type senior-architect` instead
