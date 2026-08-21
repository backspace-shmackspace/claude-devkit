# Claude Devkit

**Version:** 1.0.0
**Last Updated:** 2026-08-21
**Purpose:** Unified development toolkit for Claude Code - skills, agents, generators, and templates

For full architecture, skill registry, workflows, and troubleshooting, see [REFERENCE.md](REFERENCE.md).
For a getting-started tutorial, see [GETTING_STARTED.md](GETTING_STARTED.md).

## Coding Guidelines

These apply to all work in this project — interactive, headless, ad hoc, or skill-driven.

### 1. Think Before Coding

- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

### 3. Surgical Changes

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

Every changed line should trace directly to the request.

### 4. Goal-Driven Execution

Transform tasks into verifiable goals:
- "Add validation" -> "Write tests for invalid inputs, then make them pass"
- "Fix the bug" -> "Write a test that reproduces it, then make it pass"
- "Refactor X" -> "Ensure tests pass before and after"

### 5. Output Rules

- Always print full absolute paths for artifact references (plan files, review files, audit logs). Makes paths clickable in Warp terminal.

## Project Rules

### Python
- **stdlib only** for all scripts in `scripts/`. No external dependencies.
- **Atomic writes** via `_atomic_write_json()` or temp-file-then-rename.
- **Validation tuples** `(bool, error_msg)` for validation functions.

### Skills
- Edit source (`skills/*/SKILL.md`), not deployment (`~/.claude/skills/`)
- Validate before committing: `validate-skill skills/<name>/SKILL.md`
- Follow v2.0.0 architectural patterns (11 patterns, see REFERENCE.md)
- One skill per directory

### Tests
- Run `bash scripts/test-integration.sh` before considering changes complete
- Run `bash scripts/validate-all.sh` to verify all skills validate
- New features require integration tests in `test-integration.sh`

### Git
- Follow conventional commits: `feat(scope):`, `fix(scope):`, `chore(scope):`
- Don't commit secrets, `.env` files, or credentials

## Quick Reference

```bash
# Deploy skills
./scripts/deploy.sh

# Run tests (165 integration tests)
bash scripts/test-integration.sh

# Validate all skills (23 skills)
bash scripts/validate-all.sh

# Generate agents for a project
gen-agent ~/projects/my-app --type all

# Core workflow
/architect add feature        # Plan
/ship <plan-path>             # Implement
/audit                        # Scan
/sync                         # Update docs

# Devkit CLI (cross-project)
devkit init ~/projects/my-app
devkit shell ~/projects/my-app
devkit status
devkit learnings              # Cross-project pattern detection
```

## Key Architecture

- **Skills** live in `skills/*/SKILL.md` (source) and deploy to `~/.claude/skills/`
- **Artifacts** are centralized at `~/.claude-devkit/projects/<project-id>/plans/`
- **Learnings** aggregate cross-project at `~/.claude-devkit/learnings/`
- **Agents** are project-local at `<project>/.claude/agents/`
- **Helper scripts** deploy to `~/.claude-devkit/scripts/`

---

**Full documentation:** [REFERENCE.md](REFERENCE.md) (architecture, skill registry, security maturity, audit logging, scoring, workflows, patterns, troubleshooting)
**Maintained by:** @backspace-shmackspace
