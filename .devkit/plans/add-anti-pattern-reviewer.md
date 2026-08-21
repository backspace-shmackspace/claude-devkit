# Plan: Add Code Anti-Pattern Reviewer to /audit Skill

**Status:** APPROVED
**Created:** 2026-08-20
**Revised:** 2026-08-21
**Skill:** /audit v3.2.0 -> v3.3.0
**Scope:** New scan dimension, synthesis update, documentation, tests

---

## Goals

1. Add a new "anti-pattern scan" step to the `/audit` skill that detects code quality anti-patterns across seven categories: code smells, dead code, duplicated logic, naming convention violations, architectural anti-patterns, error handling anti-patterns, and testing anti-patterns. The scan runs for `code` and `full` scopes only (skipped for `plan` scope).
2. Produce a `.devkit/plans/audit-[timestamp].antipatterns.md` artifact using the same severity rating format (Critical/High/Medium/Low) as existing scan dimensions.
3. Update the synthesis step to consume anti-pattern findings alongside security, performance, and QA results when computing the overall audit verdict.
4. Update CLAUDE.md skill registry, artifact locations, directory tree description, and integration tests to reflect the new scan dimension.

## Non-Goals

- **Not building an external static analysis tool.** The anti-pattern scan is LLM-driven code analysis dispatched to a subagent, consistent with existing performance and QA scans.
- **Not adding a standalone `/antipattern` skill.** This is a scan dimension within `/audit`, not a new top-level skill.
- **Not modifying the audit-event-schema.json.** Step identifiers are free-form strings; no schema changes needed for the new step names.
- **Not modifying the scoring system.** `/audit` does not emit `run_score` events (only `/ship` does), so `compute-run-score.sh` and `score-reflector.sh` are untouched.
- **Not adding per-language anti-pattern rulesets.** The initial version uses the subagent's built-in knowledge. Language-specific rulesets can be added as a future enhancement.
- **Not parallelizing scan steps.** Steps 2-5 remain sequential (each dispatches an independent subagent, but the coordinator waits for each before proceeding). Steps 2-4 are designed to be independent (no cross-step data dependencies), enabling future parallelization without structural changes. Parallelization is a separate optimization.
- **Not duplicating complexity analysis.** The existing performance scan already covers algorithm complexity (O(n^2) analysis, cyclomatic complexity). The anti-pattern scan excludes complexity violations to avoid double-counting findings in the synthesis step.

## Assumptions

1. The existing `/audit` skill structure (Scan archetype, 6 steps) is well-established and the new step should follow identical patterns (audit event emission, subagent dispatch, scope-aware prompts).
2. `claude-sonnet-4-6` is the appropriate model for anti-pattern detection (pattern-matching task, consistent with the performance scan model choice).
3. Anti-pattern findings use the same severity scale as other scan dimensions and contribute to the existing verdict rules (BLOCKED/PASS_WITH_NOTES/PASS) without changing the rules themselves.
4. The step renumbering (inserting Step 4, shifting QA to Step 5, Synthesis to Step 6, Gate to Step 7) is acceptable since audit event step names are per-run identifiers, not cross-run API contracts.
5. The anti-pattern scan is skipped for `plan` scope because six of seven categories are code-level concerns that cannot be meaningfully detected in a plan document. This matches the QA regression pattern (also skipped for plan scope).

## Proposed Design

### Step Renumbering

The current `/audit` skill has 6 steps. Inserting the anti-pattern scan as Step 4 shifts subsequent steps:

| Current | New | Name |
|---------|-----|------|
| Step 1 | Step 1 | Determine scope (unchanged) |
| Step 2 | Step 2 | Security scan (unchanged) |
| Step 3 | Step 3 | Performance scan (unchanged) |
| -- | **Step 4** | **Anti-pattern scan (NEW)** |
| Step 4 | Step 5 | QA regression (renumbered) |
| Step 5 | Step 6 | Synthesis (renumbered, updated) |
| Step 6 | Step 7 | Gate (renumbered) |

**Prose cross-reference update:** The QA regression step's "no QA agent found" branch currently says "Continue to Step 5 (do not block workflow)." After renumbering, this must become "Continue to Step 6 (do not block workflow)."

### New Step 4 -- Anti-pattern scan

**Trigger:** Only run if scope is `code` or `full` (skip for `plan`). Plan scope is skipped because six of seven anti-pattern categories (code smells, dead code, duplicated logic, naming violations, error handling, testing) are code-level concerns that cannot be detected in a plan document. This matches the QA regression step, which also skips plan scope.

**Model:** `claude-sonnet-4-6` (pattern-matching task, same as performance scan).

**Audit events:** Emits `step_start` / `step_end` with step identifier `step_4_antipattern_scan`.

**Anti-pattern categories (seven):**

| Category | Description | Example Findings |
|----------|-------------|-----------------|
| Code smells | Structural indicators of deeper problems | Methods > 50 lines, functions with > 5 parameters, deeply nested conditionals (> 4 levels) |
| Dead code | Unreachable or unused code | Unreachable branches, unused imports/variables/functions, commented-out code blocks |
| Duplicated logic | Copy-paste patterns | Near-identical code blocks, repeated conditional chains, duplicated utility functions |
| Naming convention violations | Inconsistent or misleading names | Mixed naming styles, single-letter variables outside loops, misleading boolean names |
| Architectural anti-patterns | Structural design problems | God classes (> 500 lines or > 20 methods), circular dependencies, layer violations |
| Error handling anti-patterns | Inadequate error management | Empty catch/except blocks, catching generic `Exception`, swallowed errors, missing error propagation |
| Testing anti-patterns | Test quality issues | Test code in production paths, commented-out test assertions, tests without assertions, hardcoded test data shared across tests |

**Severity mapping:**
- **Critical:** Dead code that masks security vulnerabilities (high bar: the finding must identify both the dead code and the specific vulnerability it masks)
- **High:** God classes (> 500 lines or > 20 methods) or circular dependencies in core modules; empty catch blocks in error-sensitive paths; high duplication (> 3 identical blocks); deeply nested conditionals in business logic
- **Medium:** Naming violations; unused imports; test code quality issues
- **Low:** Minor code smells; style inconsistencies; single instances of duplicated logic

**Artifact:** `.devkit/plans/audit-[timestamp].antipatterns.md`

**Artifact structure:**
```markdown
# Anti-Pattern Scan -- [scope] -- [timestamp]

## Verdict
[PASS / PASS_WITH_NOTES / BLOCKED]

## Summary
[Brief overview of anti-pattern landscape]

## Findings

### Critical
- [Finding with file path, line reference, category, and remediation guidance]

### High
- [Finding with file path, line reference, category, and remediation guidance]

### Medium
- [Finding with file path, line reference, category, and remediation guidance]

### Low
- [Finding with file path, line reference, category, and remediation guidance]

## Statistics
- Total findings: N
- Categories represented: [list]
- Files affected: N
```

#### Implementation Detail: Subagent Prompts

The SKILL.md is the prompt. The following specifies the exact prompt text for each scope variant, following the pattern established by Steps 2 and 3 in the current SKILL.md.

**Step 4 audit event emission (before subagent dispatch):**

Tool: `Bash`

```bash
bash scripts/emit-audit-event.sh ".audit-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_start","step":"step_4_antipattern_scan","step_name":"Anti-pattern scan","agent_type":"coordinator"}'
```

**If scope is "plan":**
- Output: "Scope is 'plan' -- skipping anti-pattern scan (code-level analysis not applicable to plan documents)."
- Continue to Step 5 (QA regression).

**If scope is "code":**

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-6`

Prompt: "Analyze uncommitted changes for code anti-patterns across these categories:
- Code smells: methods > 50 lines, functions with > 5 parameters, deeply nested conditionals (> 4 levels)
- Dead code: unreachable branches, unused imports/variables/functions, commented-out code blocks
- Duplicated logic: near-identical code blocks, repeated conditional chains, duplicated utility functions
- Naming convention violations: mixed naming styles, single-letter variables outside loops, misleading boolean names. For naming analysis, first check for project-specific style configuration (e.g., .eslintrc, pyproject.toml [tool.ruff], .editorconfig) and align findings to the project's declared conventions. If no style configuration exists, report only clearly misleading names, not style preference differences.
- Architectural anti-patterns: god classes (> 500 lines or > 20 methods), circular dependencies, layer violations
- Error handling anti-patterns: empty catch/except blocks, catching generic Exception, swallowed errors, missing error propagation
- Testing anti-patterns: test code in production paths, commented-out test assertions, tests without assertions, hardcoded test data shared across tests

Do not flag error handling or architectural issues that are primarily security vulnerabilities (those belong in the security scan).

Rate findings: Critical / High / Medium / Low.
- Critical: Dead code masking security vulnerabilities only (must identify both the dead code and the specific vulnerability it masks)
- High: God classes, circular dependencies, empty catch blocks in error-sensitive paths, high duplication (> 3 identical blocks), deeply nested conditionals in business logic
- Medium: Naming violations, unused imports, test code quality issues
- Low: Minor code smells, style inconsistencies, single instances of duplicated logic

Write to `.devkit/plans/audit-[timestamp].antipatterns.md`"

**If scope is "full":**

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-6`

Prompt: "Full codebase anti-pattern audit across these categories:
- Code smells: methods > 50 lines, functions with > 5 parameters, deeply nested conditionals (> 4 levels)
- Dead code: unreachable branches, unused imports/variables/functions, commented-out code blocks
- Duplicated logic: near-identical code blocks, repeated conditional chains, duplicated utility functions
- Naming convention violations: mixed naming styles, single-letter variables outside loops, misleading boolean names. For naming analysis, first check for project-specific style configuration (e.g., .eslintrc, pyproject.toml [tool.ruff], .editorconfig) and align findings to the project's declared conventions. If no style configuration exists, report only clearly misleading names, not style preference differences.
- Architectural anti-patterns: god classes (> 500 lines or > 20 methods), circular dependencies, layer violations
- Error handling anti-patterns: empty catch/except blocks, catching generic Exception, swallowed errors, missing error propagation
- Testing anti-patterns: test code in production paths, commented-out test assertions, tests without assertions, hardcoded test data shared across tests

Do not flag error handling or architectural issues that are primarily security vulnerabilities (those belong in the security scan).

Rate findings: Critical / High / Medium / Low.
- Critical: Dead code masking security vulnerabilities only (must identify both the dead code and the specific vulnerability it masks)
- High: God classes, circular dependencies, empty catch blocks in error-sensitive paths, high duplication (> 3 identical blocks), deeply nested conditionals in business logic
- Medium: Naming violations, unused imports, test code quality issues
- Low: Minor code smells, style inconsistencies, single instances of duplicated logic

Write to `.devkit/plans/audit-[timestamp].antipatterns.md`"

**Step 4 audit event emission (after subagent completes):**

Tool: `Bash`

```bash
bash scripts/emit-audit-event.sh ".audit-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_end","step":"step_4_antipattern_scan","step_name":"Anti-pattern scan","agent_type":"coordinator"}'
```

### Synthesis Step Updates (new Step 6)

The synthesis step (renumbered from Step 5 to Step 6) is updated to:

1. Read the additional `.devkit/plans/audit-[timestamp].antipatterns.md` artifact (if it exists -- it will not exist for plan scope).
2. Include anti-pattern findings in the overall finding counts (Critical/High/Medium/Low).
3. Add an `Anti-patterns` entry to the `## Reports` section of the summary.
4. Anti-pattern findings contribute to the same verdict rules -- no rule changes needed:
   - BLOCKED: Any Critical findings OR 3+ High findings (across all dimensions including anti-patterns)
   - PASS_WITH_NOTES: 1-2 High findings OR 3+ Medium findings
   - PASS: Only Medium/Low findings

### Gate Step Updates (new Step 7)

The gate step (renumbered from Step 6 to Step 7) audit event identifiers update from `step_6_gate` to `step_7_gate`. No logic changes.

### Version Bump

`/audit` version: `3.2.0` -> `3.3.0` (minor version: new non-breaking feature).

### State File Update

The state file initialization in Step 1 updates `skill_version` from `3.2.0` to `3.3.0`.

## Interfaces/Schema Changes

**No schema changes required.**

- `configs/audit-event-schema.json`: The `step` field is a free-form string (`"type": "string"`), so new step identifiers like `step_4_antipattern_scan` are valid without schema modification.
- `configs/skill-patterns.json`: No changes needed. The validator checks structural patterns (frontmatter, steps, tools, verdicts) which are unchanged.
- No new CLI arguments, environment variables, or configuration keys.

## Data Migration

None. This is additive only. Existing audit logs are unaffected -- they will simply lack `step_4_antipattern_scan` events, which is expected (the step did not exist when they were created).

## Rollout Plan

1. **Modify** `skills/audit/SKILL.md` with the new Step 4 and renumbered Steps 5-7.
2. **Update** `CLAUDE.md` skill registry entry for `/audit` to reflect v3.3.0, the new step count (7), and the updated description.
3. **Update** `CLAUDE.md` artifact locations tree, directory tree comment, and test count references.
4. **Add** integration test assertions to `scripts/test-integration.sh` for the new step and renumbered steps.
5. **Validate** with `python3 generators/validate_skill.py skills/audit/SKILL.md`.
6. **Run** `bash scripts/validate-all.sh` to confirm no regressions.
7. **Run** `bash scripts/test-integration.sh` to confirm integration tests pass.
8. **Deploy** with `./scripts/deploy.sh audit`.

## Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Anti-pattern scan adds latency to /audit runs | Medium | High | Sonnet model (faster than Opus) mitigates; scan runs sequentially so adds ~30-60s |
| False positives in anti-pattern detection | Medium | Medium | LLM-driven analysis has inherent false positive risk; severity ratings help triage; findings are advisory |
| Step renumbering breaks existing audit log analysis scripts | Low | Low | Audit event step names are per-run identifiers; `audit-log-query.sh` uses event_type not step names for aggregation; no cross-run step name contracts exist |
| Large codebases may produce excessive findings | Low | Medium | Subagent prompt instructs to focus on highest-severity findings first and cap output |

## Test Plan

### Automated Tests

**Command to run all tests:**
```bash
bash scripts/test-integration.sh && bash scripts/validate-all.sh
```

**New integration tests added to `scripts/test-integration.sh`:**

1. **Structural test: audit SKILL.md version is 3.3.0**
   - `grep -q 'version: 3.3.0' skills/audit/SKILL.md`

2. **Structural test: audit SKILL.md contains anti-pattern scan step**
   - `grep -q 'step_4_antipattern_scan' skills/audit/SKILL.md`

3. **Structural test: audit SKILL.md contains antipatterns artifact reference**
   - `grep -q 'antipatterns.md' skills/audit/SKILL.md`

4. **Structural test: audit SKILL.md contains renumbered QA regression step**
   - `grep -q 'step_5_qa_regression' skills/audit/SKILL.md`

5. **Structural test: audit SKILL.md contains renumbered synthesis step**
   - `grep -q 'step_6_synthesis' skills/audit/SKILL.md`

6. **Structural test: audit SKILL.md contains renumbered gate step**
   - `grep -q 'step_7_gate' skills/audit/SKILL.md`

**Test count update:** The current `test-integration.sh` has 54 actual `run_test` invocations (the header comment says 55 -- a pre-existing discrepancy). Adding 6 new tests brings the total to 60. Update the header comment to 60 (fixing the pre-existing discrepancy at the same time).

### Manual Validation

After deployment (`./scripts/deploy.sh audit`), run in a Claude Code session:
```
/audit full
```
Verify:
- Anti-pattern scan step executes and produces `.devkit/plans/audit-[timestamp].antipatterns.md`
- Summary artifact includes anti-pattern findings in the overall verdict
- JSONL audit log contains `step_4_antipattern_scan` step events

## Acceptance Criteria

1. `/audit` skill version is `3.3.0` in frontmatter.
2. Step 4 (Anti-pattern scan) exists with audit event emission (`step_4_antipattern_scan`), conditional trigger (skip for `plan` scope), model `claude-sonnet-4-6`, exact subagent prompt text for `code` and `full` scopes with Tool declarations, and artifact output to `.devkit/plans/audit-[timestamp].antipatterns.md`.
3. Steps 5-7 are correctly renumbered with updated audit event identifiers (`step_5_qa_regression`, `step_6_synthesis`, `step_7_gate`), including the prose cross-reference update ("Continue to Step 6").
4. Synthesis step (Step 6) reads the anti-pattern artifact (when present) and includes findings in the overall verdict calculation.
5. Gate step (Step 7) summary output includes anti-pattern finding counts.
6. Summary artifact template includes `Anti-patterns` in the `## Reports` section.
7. `CLAUDE.md` skill registry entry for `/audit` reflects v3.3.0, 7 steps, and updated description: "Scope detection (plan/code/full) -> Security scan (composable: invokes /secure-review when deployed, otherwise built-in scan) + Performance scan + Anti-pattern scan -> QA regression -> Synthesis with PASS/PASS_WITH_NOTES/BLOCKED verdict -> Structured reporting with timestamped artifacts."
8. `CLAUDE.md` artifact locations tree includes `audit-[timestamp].antipatterns.md`.
9. `CLAUDE.md` test count references (lines 86 and 1043) updated to 60.
10. `CLAUDE.md` directory tree comment for `audit/` updated to include anti-pattern scanning.
11. `bash scripts/validate-all.sh` exits 0 (all skills validate).
12. `bash scripts/test-integration.sh` exits 0 (all integration tests pass, including 6 new anti-pattern structural tests and the corrected header count of 60).

## Task Breakdown

### Files to Create or Modify

| File | Action | Description |
|------|--------|-------------|
| `skills/audit/SKILL.md` | modify | Add Step 4 (anti-pattern scan with exact subagent prompts for code/full scopes), renumber Steps 5-7, update synthesis and gate, update prose cross-reference, bump version |
| `CLAUDE.md` | modify | Update /audit skill registry entry (version, step count, description), artifact locations tree, directory tree comment, test count references (2 locations) |
| `scripts/test-integration.sh` | modify | Add 6 structural tests for anti-pattern step and renumbered steps, fix header comment test count to 60 |

## Work Groups

### Work Group 1: Audit skill implementation
- `skills/audit/SKILL.md` (modify -- add Step 4 anti-pattern scan with conditional trigger skipping plan scope, exact subagent prompt text for code and full scopes with Tool/model declarations and audit event emission, anti-pattern/security overlap note in prompts, renumber Steps 5-7 including prose cross-reference "Continue to Step 5" -> "Continue to Step 6", update synthesis to include antipatterns artifact, update gate step identifiers, bump version to 3.3.0, update state file skill_version)

### Work Group 2: Documentation and tests
- `CLAUDE.md` (modify -- update /audit skill registry row: version 3.3.0, step count 7, description "Scope detection (plan/code/full) -> Security scan (composable: invokes /secure-review when deployed, otherwise built-in scan) + Performance scan + Anti-pattern scan -> QA regression -> Synthesis with PASS/PASS_WITH_NOTES/BLOCKED verdict -> Structured reporting with timestamped artifacts. JSONL audit logging to `.devkit/plans/audit-logs/audit-<run_id>.jsonl`."; add `audit-[timestamp].antipatterns.md` to Artifact Locations tree; update directory tree comment for `audit/` to include anti-pattern scanning; update test count from "54 tests" to "60 tests" at both locations)
- `scripts/test-integration.sh` (modify -- add 6 new structural tests: 3 for anti-pattern scan content (version, step identifier, artifact reference) + 3 for renumbered step identifiers (step_5_qa_regression, step_6_synthesis, step_7_gate); fix header comment test count from 55 to 60)

## Context Alignment

### CLAUDE.md Patterns Followed
- **Scan archetype**: The new step follows the existing scan pattern (scope-aware prompt, subagent dispatch, severity-rated findings, artifact output).
- **11 architectural patterns**: Tool declarations, numbered steps, verdict gates, timestamped artifacts, structured reporting all present.
- **Audit event emission**: Step uses `emit-audit-event.sh` with `step_start`/`step_end` events, consistent with existing steps.
- **Model selection**: `claude-sonnet-4-6` for pattern-matching work, matching the performance scan precedent.
- **Version bumping**: Minor version increment (3.2.0 -> 3.3.0) for non-breaking new feature.
- **Subagent prompt completeness**: Step 4 includes exact prompt text for each scope variant with Tool and model declarations, following the pattern of Steps 2 and 3 in the current SKILL.md.

### Prior Plans Consulted
- `audit-2026-08-21T02-42-30.security.md` -- Recent full codebase security audit. Confirmed /audit produces security, performance, and QA artifacts in the expected format. The anti-pattern artifact follows the same structure.

### Deviations from Established Patterns
- **Step renumbering**: Inserting a step mid-sequence requires renumbering. This is the cleanest approach (avoids substep notation like 3b which would be inconsistent with the existing integer-only pattern in /audit). The renumbering only affects internal audit event identifiers, not external APIs.
- **Sequential scan execution**: The CLAUDE.md Scan Pattern archetype describes "Runs parallel analysis tasks" as a core characteristic, but the existing `/audit` skill runs Steps 2-4 (security, performance, QA) sequentially. This plan adds a fourth sequential scan (Step 4, anti-pattern), inheriting the pre-existing deviation. Steps 2-4 have no cross-step data dependencies, so future parallelization requires no structural changes to this implementation.

---

<!-- Context Metadata
discovered_at: 2026-08-20T12:00:00Z
revised_at: 2026-08-21
claude_md_exists: true
recent_plans_consulted: audit-2026-08-21T02-42-30.security.md
archived_plans_consulted: none
revision_notes: Addressed 4 Major + 5 Minor findings from red team, librarian, and feasibility reviews.
-->
