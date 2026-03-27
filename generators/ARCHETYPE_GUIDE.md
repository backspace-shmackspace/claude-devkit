# Archetype Decision Guide

## When to Use This Guide

Use this guide when creating a new skill with `generate_skill.py` and you need to
choose an archetype (coordinator, pipeline, or scan). Each archetype provides a
structural pattern optimized for a different class of workflow.

## Quick Decision Tree

Answer these questions in order:

1. **Does your workflow delegate work to multiple specialist agents?**
   - Yes -> **Coordinator** (like /architect)
   - No -> Continue

2. **Does your workflow execute sequential stages with pass/fail gates?**
   - Yes -> **Pipeline** (like /ship)
   - No -> Continue

3. **Does your workflow analyze something and produce a severity-rated report?**
   - Yes -> **Scan** (like /audit)
   - No -> Consider whether your workflow is a **Reference** (non-executable
     behavioral guideline, like /receiving-code-review) or needs a custom structure.

## Comparison Table

| Dimension | Coordinator | Pipeline | Scan |
|-----------|------------|----------|------|
| **Control flow** | Delegate -> parallel reviews -> revision loop -> verdict | Sequential stages with checkpoints | Scope detection -> parallel analysis -> synthesis |
| **Parallelism** | Yes (review agents run in parallel) | Limited (stages are sequential; sub-tasks may parallelize) | Yes (analysis agents run in parallel) |
| **Revision loops** | Yes (bounded, max 2 rounds) | Yes (between implementation and review) | No (single-pass analysis) |
| **Verdict gates** | PASS/FAIL at approval gate | PASS/FAIL at commit gate | PASS/PASS_WITH_NOTES/BLOCKED at synthesis |
| **Primary output** | Approved artifact (plan, design) | Committed code | Severity-rated report |
| **Typical steps** | 5-7 | 6-8 | 4-6 |
| **Agent count** | 3+ (main agent + reviewers) | 2-4 (coders + reviewer + QA) | 2-3 (scanners + synthesizer) |

## Coordinator Pattern

### When to Use
- Planning and design workflows that need multi-perspective review
- Research tasks that benefit from parallel analysis by different specialists
- Approval workflows with bounded revision loops
- Any workflow where the skill orchestrates but does not directly execute the core work

### When NOT to Use
- Sequential execution with strict ordering (use Pipeline)
- Analysis/reporting without revision loops (use Scan)
- Simple single-agent tasks (may not need a skill at all)

### Structure
1. Context discovery (read project state)
2. Main work delegation (single specialist agent)
3. Parallel quality reviews (multiple reviewer agents)
4. Revision loop (max 2 iterations, re-delegate to main agent)
5. Approval gate (PASS/FAIL verdict)
6. Archive artifacts

### Example Skills
- `/architect` -- Plans features with red team, librarian, and feasibility reviews
- Template: `templates/skill-coordinator.md.template`

## Pipeline Pattern

### When to Use
- Code implementation workflows with pre-flight checks and commit gates
- Sequential validation chains where each stage depends on the previous
- Deployment pipelines with rollback points
- Any workflow with a clear "input -> transform -> validate -> output" structure

### When NOT to Use
- Multi-agent review workflows (use Coordinator)
- Analysis-only workflows that produce reports (use Scan)
- Workflows where stages can run in parallel (use Coordinator or Scan)

### Structure
1. Pre-flight checks (environment validation)
2. Read and validate input
3. Pattern validation (warnings, not blockers)
4. Main implementation (delegate to coder agents)
5. Review and testing (parallel: code review + tests + QA)
6. Revision loop (max 2 iterations, re-implement)
7. Commit gate (PASS/FAIL verdict)

### Example Skills
- `/ship` -- Implements plans with worktree isolation, security gates, and commit gate (full pipeline)
- `/sync` -- Detects changes and applies documentation updates (simple pipeline -- no worktree isolation or security gates)
- Template: `templates/skill-pipeline.md.template`

## Scan Pattern

### When to Use
- Security audits and vulnerability assessments
- Code quality analysis with severity ratings
- Dependency analysis and risk assessment
- Any workflow that examines a codebase and produces a structured report with findings

### When NOT to Use
- Workflows that need to modify code (use Pipeline)
- Multi-round revision workflows (use Coordinator)
- Workflows that need approval gates rather than severity ratings (use Coordinator)

### Structure
1. Detect scope (what to scan: plan, code, full, specific files)
2. Parallel analysis (multiple scanner agents)
3. Synthesis (combine findings, assign severity ratings)
4. Verdict gate (PASS/PASS_WITH_NOTES/BLOCKED based on severity)
5. Archive reports

### Example Skills
- `/audit` -- Security + performance + QA scans with composable sub-skills
- `/secrets-scan` -- Pattern-based secrets detection
- Template: `templates/skill-scan.md.template`

## Reference Archetype

Not a workflow archetype -- reference skills are non-executable behavioral guidelines
that Claude Code loads as context. They define patterns, anti-patterns, and decision
frameworks rather than step-by-step workflows.

### When to Use
- Behavioral guidelines (code review discipline, verification practices)
- Decision frameworks that should always be in context
- Anti-pattern catalogs

### Examples
- `/receiving-code-review` -- Code review response discipline
- `/verification-before-completion` -- Evidence-before-claims gate

### Key Differences from Workflow Archetypes
- No numbered steps (principles and guidelines instead)
- No Tool declarations
- No verdict gates
- `type: reference` in frontmatter
- Requires `attribution` field in frontmatter

## Generating a Skill

Once you have chosen an archetype:

    gen-skill my-skill-name \
      --description "One-line description." \
      --archetype coordinator|pipeline|scan \
      --deploy

Validate the generated skill:

    validate-skill skills/my-skill-name/SKILL.md

See the CLAUDE.md "Skill Architectural Patterns (v2.0.0)" section for the complete
pattern specification that all skills must follow.
