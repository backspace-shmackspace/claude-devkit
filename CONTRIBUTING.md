# Contributing to Claude Devkit

Thanks for your interest in contributing! This project provides reusable skills, generators, and templates for Claude Code.

## How to Contribute

### Adding a New Skill

1. Generate a scaffold: `gen-skill my-skill --description "..." --archetype pipeline`
2. Customize `skills/my-skill/SKILL.md` — replace `[TODO: ...]` placeholders
3. Validate: `validate-skill skills/my-skill/SKILL.md`
4. Test in Claude Code: deploy and run the skill
5. Submit a PR

### Improving Generators or Templates

1. Make your changes in `generators/` or `templates/`
2. Run the test suite: `bash generators/test_skill_generator.sh`
3. Ensure all 26 tests pass
4. Submit a PR

### Reporting Issues

- Open an issue with a clear description of the problem
- Include steps to reproduce if applicable
- Note your OS, Python version, and Claude Code version

## Guidelines

- **Follow v2.0.0 skill patterns** — all skills must pass `validate-skill`
- **Test before submitting** — run validation and use the skill in Claude Code
- **Keep PRs focused** — one feature or fix per PR
- **Use conventional commits** — `feat(skills):`, `fix(generators):`, `docs:`, etc.

## Skill Patterns

All skills must follow the [architectural patterns](CLAUDE.md#skill-architectural-patterns-v200):

1. Coordinator role with delegation
2. Numbered steps (`## Step N -- [Action]`)
3. Tool declarations per step
4. Verdict gates (PASS/FAIL/BLOCKED)
5. Timestamped artifacts
6. Structured reporting to `./plans/`
7. Bounded iterations (max N revisions)
8. Model selection in frontmatter
9. Scope parameters with `$ARGUMENTS`
10. Archive on success

## Core vs Contrib

- `skills/` — Universal skills suitable for all users
- `contrib/` — Optional skills requiring user-specific setup (e.g., Obsidian vault paths)

If your skill requires user-specific paths or opinionated workflows, put it in `contrib/`.

## Code of Conduct

Be respectful and constructive. We're all here to build useful tools.
