# Plan: Agentic SDLC Next Phase -- Quality Infrastructure, Phase C Completion, and Devkit Maturity

## Revision Log

| Rev | Date | Trigger | Summary |
|-----|------|---------|---------|
| 1 | 2026-03-27 | Initial draft | Strategic plan covering Phase C completion, quality infrastructure, and devkit maturity improvements |
| 2 | 2026-03-27 | Review findings (RT PASS 4M/6m, LIB PASS_WITH_NOTES 4R, FEAS PASS 3M/7m) | Address all Major and Required findings: RT-M1 expand exit code fix to unknown types; RT-M2 show stderr on validation failures; RT-M3 specify deploy.sh --validate pre-processing loop with interaction matrix; RT-M4 core skill tests FAIL if missing (not skip); F-M1 add nullglob guard; F-M3 specify cleanup renumber to Test 46; L-R1 fix stale "26 tests" in CLAUDE.md; L-R2 note registry already current; L-R3 mark 3a DEFERRED; L-R4 roadmap update includes test count fix. Also: RT-m1 add plan filename deviation; RT-m6/F-m2 scope validate-all.sh to skills only. |
| 2.1 | 2026-03-27 | Round 2 review findings (RT PASS 1M/5m, LIB PASS 1R, FEAS PASS 2m) | RT2-M1/L2-R1: Append `\|\| true` to validate-all.sh diagnostic re-run pipe to prevent `set -euo pipefail` abort on validation failure. F2-m9: Apply --validate flag to both `deploy_skill()` and `deploy_contrib_skill()` so `--validate --contrib` works. |

## Context

The agentic SDLC security initiative is functionally complete:

- **Phase A** (5 standalone security skills): SHIPPED (commit history)
- **Phase B** (embedding security in /ship, /architect, /audit): SHIPPED (commit 0eb9e0a)
- **Phase C** (documentation and templates): DEFINED but not yet planned as a standalone blueprint

The security mesh is built. The question is: what does the devkit need next?

Analysis of the learnings file (`.claude/learnings.md`) and archived artifacts reveals a consistent pattern of infrastructure gaps that compound over time:

1. **QA coverage gaps are the #1 recurring finding.** Across 6+ features, the QA agent skips the full test suite, does not run integration tests, and does not add new skills to the test suite. The learnings file has 5 separate entries flagging this.
2. **No CI/CD automation.** No automated gate exists between QA and merge. The test suite must be run manually. Developer discipline is the only enforcement mechanism.
3. **New skills are invisible to the test suite.** The 5 security skills added in Phase A were never added to `test_skill_generator.sh`. If a future change breaks their structure, the test suite will not catch it.
4. **Coder patterns degrade over time without automated checks.** Stale cross-references, settings precedence bugs, revision loop prose omissions, and implicit else guards are all patterns that automated linting could catch.

This plan addresses these gaps in a sequenced approach that maximizes impact: first, close the Phase C documentation debt (low risk, high value); second, build quality infrastructure that prevents the recurring gaps; third, advance devkit maturity with the highest-impact roadmap items.

**Current skill versions (confirmed):**
- `skills/ship/SKILL.md` -- v3.5.0
- `skills/architect/SKILL.md` -- v3.1.0
- `skills/audit/SKILL.md` -- v3.1.0
- 13 core skills + 3 contrib skills deployed

## Architectural Analysis

### Key Drivers

1. **Close the QA gap** -- The learnings file identifies QA coverage as the top systemic risk. Every shipped feature since the initial release has skipped at least one QA validation step. This is a tooling problem, not a discipline problem -- the test suite does not cover what it should.
2. **Complete the security initiative** -- Phase C is the final cleanup step. It is low-risk and should be done before starting new work to avoid documentation drift.
3. **Invest in infrastructure** -- The roadmap lists several v1.1 items (project initializer, CLAUDE.md template generator, skill version upgrade tool). The highest-impact item is the one that reduces ongoing maintenance burden: automated validation of all skills in the test suite.
4. **Observability** -- The /retro skill mines artifacts for patterns, but there is no way to track devkit health over time. A validation summary that runs across all skills provides a health snapshot.

### Trade-offs

| Decision | Option A | Option B | Choice | Rationale |
|----------|----------|----------|--------|-----------|
| Scope of quality infrastructure | Full CI/CD pipeline (GitHub Actions, pre-commit hooks) | Expand test suite + add validation commands | **Option B** | The devkit is a personal/small-team toolkit. A full CI/CD pipeline adds maintenance burden disproportionate to team size. Expanding the existing test suite and adding a `validate-all` command provides 80% of the value at 20% of the cost. CI/CD can be layered on later. |
| Phase C vs quality infra ordering | Phase C first, then quality | Quality first, then Phase C | **Option A** | Phase C is smaller scope (1 session), lower risk, and closes an open initiative. Completing it first provides clean closure before starting new infrastructure work. Quality infra benefits from Phase C being complete (CLAUDE.md is current). |
| Test suite expansion strategy | Add new test files per skill | Extend existing `test_skill_generator.sh` | **Option B** | The existing test suite is well-structured with a run_test() harness. Adding tests for new skills follows the same pattern. One test file is easier to maintain than many. |
| Skill version upgrade tool | Build now (v1.1 roadmap) | Defer to v1.2 | **Defer** | Version upgrades are infrequent (skills change ~monthly). The manual process (edit frontmatter, validate, deploy) is adequate. The version upgrade tool adds polish but not critical value. Deferred to keep this plan focused. |
| Project initializer | Build now (v1.1 roadmap) | Defer to v1.2 | **Defer** | The project initializer creates new project scaffolds. While useful, it is a convenience tool, not an infrastructure gap. Deferred to keep scope manageable. |
| CLAUDE.md template generator | Build now (v1.1 roadmap) | Build as part of Phase C | **Phase C** | The security section template (`templates/claude-md-security-section.md.template`) is Phase C scope from the parent plan. Creating a broader CLAUDE.md template generator is deferred, but the security section template is in scope. |

### Requirements

- All changes pass existing test suite (`bash generators/test_skill_generator.sh`)
- No breaking changes to existing skill interfaces, generator interfaces, or deployment patterns
- All new test cases follow the existing `run_test()` pattern in `test_skill_generator.sh`
- Phase C changes match the specification in the parent plan (`plans/agentic-sdlc-security-skills.md`, Phase C section)
- Quality infrastructure changes are additive and do not modify existing passing tests

## Goals

1. **Complete Phase C** -- Update agent templates with security awareness, create CLAUDE.md security section template, update CLAUDE.md registry and documentation, update agent-patterns.json
2. **Expand test suite** -- Add validation tests for all 13 core skills (currently only 4 are tested: architect, ship, audit, sync). Add validation tests for contrib skills. Add new security skills to the test suite.
3. **Add validate-all command** -- Create a `validate-all.sh` script that validates every skill in the repository (core and contrib), providing a single-command health check
4. **Fix generator exit code bug** -- `generate_agents.py` returns exit 0 even when agent writes fail or unknown agent types are requested (identified in learnings file)
5. **Add deploy verification** -- Extend `deploy.sh` to optionally validate skills before deploying (`--validate` flag)
6. **Update CLAUDE.md roadmap** -- Mark completed items, add new items reflecting devkit maturity

## Non-Goals

- Full CI/CD pipeline (GitHub Actions, pre-commit hooks) -- too much infrastructure for current team size
- Skill version upgrade tool -- low-impact, deferred to v1.2
- Project initializer -- convenience tool, deferred to v1.2
- Interactive TUI for skill generation -- v1.2 scope
- Agent testing framework -- v1.2 scope (the expanded test suite provides structural validation; behavioral testing is a larger effort)
- Modifying any Phase A or Phase B security skills
- Entropy-based scanning for /secrets-scan (v1.1.0 of that specific skill)

## Assumptions

1. Phase A and Phase B are stable and deployed (confirmed from git history and CLAUDE.md)
2. The parent plan (`plans/agentic-sdlc-security-skills.md`) Phase C specification is the authoritative source for documentation and template changes
3. All 13 core skills exist in `skills/` directory and pass `validate-skill` individually
4. The existing test suite (`generators/test_skill_generator.sh`) passes at 33 tests
5. Python 3 is available on all target platforms
6. The `validate_agent.py` script exists and is functional

## Proposed Design

### Stream 1: Phase C Completion (Documentation and Templates)

Complete the remaining work from the parent security plan. This is a cleanup task with a defined specification.

#### 1a. Agent Template Security Sections

Add security awareness to the coder and QA agent templates. The parent plan specifies exact content:

**`templates/agents/coder-specialist.md.template`** -- Insert after `# Specialist Context Injection` and before `# Conflict Resolution`:

```markdown
# Security Awareness

## Secure Coding Standards
- Input validation for all external data
- Parameterized queries (no string concatenation for SQL/NoSQL)
- Output encoding by context (HTML, URL, JavaScript, CSS)
- Use framework-provided CSRF protections
- Never log sensitive data (passwords, tokens, PII)
- Use constant-time comparison for secrets
```

**`templates/agents/qa-engineer-specialist.md.template`** -- Insert after `# Specialist Context Injection` and before `# Conflict Resolution`:

```markdown
# Security Testing

## Required Security Tests
- Input validation boundary tests
- Authentication bypass attempts
- Authorization boundary tests (horizontal + vertical privilege escalation)
- SQL/NoSQL injection test cases
- XSS payload test cases
- CSRF token validation tests

## Test Data Security
- Never use production data in tests
- Use realistic but synthetic PII
- Rotate test credentials
- Clean up test secrets from fixtures
```

#### 1b. CLAUDE.md Security Section Template

Create `templates/claude-md-security-section.md.template` per the parent plan specification:

```markdown
## Security

### Threat Model
[Link to threat model document or describe key assets and trust boundaries]

### Security Requirements
- Authentication: [method -- e.g., OAuth 2.0, SAML, mTLS]
- Authorization: [model -- e.g., RBAC, ABAC, policy-based]
- Encryption: [at-rest and in-transit requirements]
- Compliance: [frameworks -- e.g., FedRAMP, SOC 2, HIPAA]

### Secure Development
- All PRs require `/secure-review` pass (or manual security review)
- Secrets scanning enabled in CI (`/secrets-scan` or equivalent)
- Dependencies audited weekly (`/dependency-audit`)
- Threat model updated with each major feature (`threat-model-gate`)

### Platform Specific
[Add platform-specific security requirements here if applicable,
e.g., FIPS crypto, container base images, security context constraints]
```

#### 1c. CLAUDE.md Registry and Documentation Updates

Update the CLAUDE.md documentation to reflect current state:

- Verify skill registry is current -- the CLAUDE.md skill registry already lists all 13 core skills with correct versions (`/ship` v3.5.0 with security gates, `/architect` v3.1.0 with threat-model-gate, `/audit` v3.1.0 with composability). **No changes expected** to skill registry content.
- Add `claude-md-security-section.md.template` to the Template Registry table
- Verify Security Maturity Levels section is accurate and complete (expected: no changes needed)
- Fix stale test count: CLAUDE.md currently says "26 tests" in three locations (generators section line 727, coverage section line 913, roadmap v1.0 line 1058). Update all three to "33 tests" to match the actual `test_skill_generator.sh` count. This count will be further updated in Stream 2 when tests are added.
- Mark Roadmap items: Phase A DONE, Phase B DONE, Phase C DONE (after this plan)

#### 1d. agent-patterns.json Update

The `security` variant for `coder` and `qa-engineer` already exists in `configs/agent-patterns.json` (confirmed: coder has `["security", "frontend", "python", "typescript"]`, qa-engineer has `["security", "frontend", "python"]`). No change needed -- the parent plan's specification matches the current state.

### Stream 2: Quality Infrastructure

Address the systemic QA gaps identified in the learnings file.

#### 2a. Expand Test Suite to Cover All Skills

The current test suite (`generators/test_skill_generator.sh`) validates only 4 production skills: architect, ship, audit, sync. The 9 remaining core skills and 3 contrib skills are not tested.

Add validation tests for every core skill. Core skill tests must **FAIL** (not skip) if the skill file is missing -- a deleted core skill is a test failure, not a condition to skip. The conditional skip pattern is reserved for contrib skills, where the directory genuinely may not exist on all machines.

```bash
# Core skills -- unconditional (FAIL if missing):
# Test 34: Validate retro skill
# Test 35: Validate test-idempotent skill
# Test 36: Validate receiving-code-review skill
# Test 37: Validate verification-before-completion skill
# Test 38: Validate secure-review skill
# Test 39: Validate dependency-audit skill
# Test 40: Validate secrets-scan skill
# Test 41: Validate threat-model-gate skill
# Test 42: Validate compliance-check skill
```

Core skill test pattern (no conditional guard):

```bash
# Test 34: Validate retro skill
run_test 34 "Validate retro skill" \
    "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/retro/SKILL.md'" \
    0
```

Also add contrib skill validation (conditional on directory existence -- skip is acceptable for contrib):

```bash
# Test 43: Validate journal skill (if exists)
# Test 44: Validate journal-recall skill (if exists)
# Test 45: Validate journal-review skill (if exists)
```

Cleanup test renumbered from Test 33 to **Test 46** (the last test).

Total test count after expansion: **46** (33 existing tests with cleanup renumbered + 9 new core skill tests + 3 new contrib skill tests + 1 renumbered cleanup).

This ensures that any future modification to or accidental deletion of these skills is caught by the test suite.

#### 2b. Add validate-all.sh Script

Create `scripts/validate-all.sh` -- a single-command health check that validates every skill in the repository. (Agent templates contain placeholder variables and cannot be validated without first generating a concrete agent; agent validation is out of scope for this script.)

```bash
#!/usr/bin/env bash
# Validate all skills in claude-devkit
# Usage: ./scripts/validate-all.sh [--strict]
#
# Validates:
#   - All core skills in skills/*/SKILL.md
#   - All contrib skills in contrib/*/SKILL.md (if directory exists)
#
# Note: Agent templates are not validated here because they contain
# placeholder variables ({project_name}, etc.) that require generation
# before validation. Use validate_agent.py on generated agents instead.
#
# Exits 0 if all pass, 1 if any fail

# For each skill in skills/*/SKILL.md: run validate_skill.py
# For each skill in contrib/*/SKILL.md: run validate_skill.py
# Report summary: N skills validated, M passed, K failed
```

This provides the "devkit health snapshot" that is currently missing.

#### 2c. Deploy Validation Flag

Extend `scripts/deploy.sh` to support `--validate` flag:

```bash
./scripts/deploy.sh --validate                    # Validate + deploy all core skills
./scripts/deploy.sh --validate architect           # Validate + deploy one core skill
./scripts/deploy.sh --validate --all               # Validate + deploy core + contrib
./scripts/deploy.sh --validate --contrib           # Validate + deploy all contrib
./scripts/deploy.sh --validate --contrib journal   # Validate + deploy one contrib skill
```

When `--validate` is passed, run `validate_skill.py` on each skill before copying it to `~/.claude/skills/`. If validation fails, abort deployment for that skill and report the error.

**Argument parsing approach:** The current `deploy.sh` uses a `case` statement on `$1` for dispatching. Since `--validate` is a modifier flag (not a dispatch target), it must be extracted in a pre-processing loop **before** the existing `case` statement. This avoids restructuring the entire argument parser:

```bash
# Pre-processing loop: extract --validate before the case statement
VALIDATE=0
ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--validate" ]; then
        VALIDATE=1
    else
        ARGS+=("$arg")
    fi
done
set -- "${ARGS[@]}"

# Existing case statement on $1 proceeds unchanged
```

**Full interaction matrix:**

| Command | VALIDATE | $1 after shift | Behavior |
|---------|----------|----------------|----------|
| `deploy.sh` | 0 | `""` | Deploy all core (unchanged) |
| `deploy.sh architect` | 0 | `architect` | Deploy one core (unchanged) |
| `deploy.sh --validate` | 1 | `""` | Validate + deploy all core |
| `deploy.sh --validate architect` | 1 | `architect` | Validate + deploy one core |
| `deploy.sh --validate --all` | 1 | `--all` | Validate + deploy core + contrib |
| `deploy.sh --validate --contrib` | 1 | `--contrib` | Validate + deploy all contrib |
| `deploy.sh --validate --contrib journal` | 1 | `--contrib` | Validate + deploy one contrib |
| `deploy.sh --all` | 0 | `--all` | Deploy core + contrib (unchanged) |
| `deploy.sh --contrib journal` | 0 | `--contrib` | Deploy one contrib (unchanged) |

This prevents deploying broken skills -- addressing the gap where a manual edit to `skills/*/SKILL.md` might break validation but still get deployed.

#### 2d. Fix generate_agents.py Exit Code Bug

The learnings file identifies: "Generator continues-on-write-error but exits 0." The fix is to track write failures and unknown type requests, and return exit code 1 if any agent failed to write or if unknown types were requested.

In `generate_agents()`:
- Add a `write_failures` counter (increment on each failed `atomic_write()`)
- Add an `unknown_types` counter (increment when `agent_type not in AGENT_TYPES`, near line 433-435 where the code currently prints a warning and continues)
- Return 1 if `write_failures > 0 or unknown_types > 0`

This ensures that `--type typo-name` returns non-zero instead of silently succeeding with zero agents generated.

### Stream 3: Devkit Maturity

Improvements that advance the devkit toward v1.1 readiness.

#### 3a. Learnings Consumption Feedback Loop -- DEFERRED

> **DEFERRED:** This item is out of scope for this plan. It is documented here for context only. See Deviation 4 in Context Alignment for rationale.

The `/retro` skill writes to `.claude/learnings.md` and `/ship` Step 2 reads it for pattern validation. But there is no mechanism to track whether learnings are being addressed. A future micro-plan should add a `## Status` column to each learning entry format recommendation in the `/retro` skill, with values: `open`, `addressed`, `wont-fix`. This would change the `/retro` skill's output contract and requires its own validation cycle.

#### 3b. CLAUDE.md Roadmap Update

Update the roadmap section to reflect current state:

```markdown
### v1.0 (Current)
- [x] Core skills (architect, ship, audit, sync, retro)
- [x] Security skills (5 standalone + 3 workflow integrations)
- [x] Skill generator with 3 archetypes
- [x] Agent generator (unified)
- [x] Skill validator + agent validator
- [x] Deployment scripts (core + contrib)
- [x] Test suite (46 tests)
- [x] Security maturity levels (L1/L2/L3)

### v1.1 (Next)
- [ ] Expanded test suite (all 13 core skills + contrib)
- [ ] validate-all health check command
- [ ] Deploy-time validation (--validate flag)
- [ ] CLAUDE.md template generator (broader than security section)
- [ ] Project initializer (full project setup)
- [ ] Skill version upgrade tool

### v1.2 (Planned)
- [ ] Interactive TUI for skill generation
- [ ] Agent testing framework (behavioral, not just structural)
- [ ] Skill dependency management
- [ ] CI/CD pipeline templates
```

## Interfaces / Schema Changes

### Skill Frontmatter Changes

No skill frontmatter changes. (The `/retro` skill output format change described in section 3a is DEFERRED and not part of this plan.)

### Script Interface Changes

| Script | Change | Type |
|--------|--------|------|
| `scripts/deploy.sh` | Add `--validate` flag | New optional flag (backward-compatible) |
| `scripts/validate-all.sh` | New script | New file |
| `generators/test_skill_generator.sh` | Add tests 34-45, renumber cleanup to Test 46 (total: 46 tests) | Additive (existing tests unchanged except cleanup renumber) |

### Generator Interface Changes

| Generator | Change | Type |
|-----------|--------|------|
| `generators/generate_agents.py` | Fix exit code on write failure and unknown agent types | Bug fix (behavioral correction) |

### Template Changes

| Template | Change | Type |
|----------|--------|------|
| `templates/agents/coder-specialist.md.template` | Add Security Awareness section | Additive |
| `templates/agents/qa-engineer-specialist.md.template` | Add Security Testing section | Additive |
| `templates/claude-md-security-section.md.template` | New file | New template |

### Config Changes

No config changes. `configs/agent-patterns.json` already has the `security` variant for `coder` and `qa-engineer`.

## Data Migration

No data migration required. All changes are additive.

## Rollout Plan

This plan is organized into **3 streams** that can be executed in sequence within 2-3 sessions. The streams are ordered by dependency and risk:

### Stream 1: Phase C Completion (Session 1)

**Scope:** 3 modified files + 1 new file + CLAUDE.md update
**Risk:** Low (additive content only, no behavioral changes)
**Rollback:** `git checkout HEAD~1 -- templates/ CLAUDE.md`

1. Modify `templates/agents/coder-specialist.md.template`
2. Modify `templates/agents/qa-engineer-specialist.md.template`
3. Create `templates/claude-md-security-section.md.template`
4. Update `CLAUDE.md` (registry, roadmap, template table)
5. Validate, test, commit

### Stream 2: Quality Infrastructure (Session 2)

**Scope:** 3 modified files + 1 new file
**Risk:** Low-Medium (test suite expansion could surface pre-existing validation issues in untested skills)
**Rollback:** `git checkout HEAD~1 -- generators/test_skill_generator.sh scripts/ generators/generate_agents.py`

1. Expand `generators/test_skill_generator.sh` with tests for all skills
2. Create `scripts/validate-all.sh`
3. Add `--validate` flag to `scripts/deploy.sh`
4. Fix `generators/generate_agents.py` exit code bug
5. Run expanded test suite, fix any pre-existing validation issues found
6. Commit

### Stream 3: Devkit Maturity (Session 2 or 3)

**Scope:** 1 modified file (CLAUDE.md roadmap update, can combine with Stream 2 commit)
**Risk:** Low (documentation only)
**Rollback:** `git checkout HEAD~1 -- CLAUDE.md`

1. Update CLAUDE.md roadmap section
2. Commit (may combine with Stream 2)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Untested skills fail validation when added to test suite | Medium | Medium | This is actually a success -- finding pre-existing validation issues is the purpose of expanding the test suite. Fix any issues found as part of Stream 2. If a skill has structural issues, fix the skill before adding the test (test should pass, not be skipped). |
| CLAUDE.md update conflicts with concurrent changes | Medium | Low | CLAUDE.md is frequently modified. Run `git diff HEAD CLAUDE.md` before starting Stream 1 to verify baseline. Resolve conflicts if any. |
| Agent template changes break existing generated agents | Low | Low | Template changes are additive (new sections). Existing generated agents are not re-generated automatically. Only new agents created after the template update will include security sections. |
| validate-all.sh takes too long to run | Low | Low | Current skill count is 13 core + 3 contrib. Each validation takes <1 second. Total runtime will be under 30 seconds. |
| deploy.sh --validate breaks existing deployment workflows | Low | Medium | The --validate flag is opt-in. Default behavior (no flag) is unchanged. |
| generate_agents.py exit code fix breaks existing scripts | Low | Low | The fix changes behavior only when a write error occurs. Normal operation (successful writes) is unchanged. Scripts that check `$?` will now correctly detect partial failures. |

## Test Plan

### Validation Commands

```bash
# Stream 1: Validate templates (visual inspection -- templates don't have validators)
cat /Users/imurphy/projects/claude-devkit/templates/agents/coder-specialist.md.template
cat /Users/imurphy/projects/claude-devkit/templates/agents/qa-engineer-specialist.md.template
cat /Users/imurphy/projects/claude-devkit/templates/claude-md-security-section.md.template

# Stream 2: Run expanded test suite
cd /Users/imurphy/projects/claude-devkit && bash generators/test_skill_generator.sh

# Stream 2: Run validate-all
cd /Users/imurphy/projects/claude-devkit && bash scripts/validate-all.sh

# Stream 2: Test deploy with validation
cd /Users/imurphy/projects/claude-devkit && bash scripts/deploy.sh --validate

# Stream 2: Test generate_agents exit code on write failure
cd /tmp && mkdir -p sg-test-exit && python3 /Users/imurphy/projects/claude-devkit/generators/generate_agents.py /tmp/sg-test-exit --type coder --force; echo "Exit code: $?"

# Verify all skills validate
for skill in /Users/imurphy/projects/claude-devkit/skills/*/SKILL.md; do
  python3 /Users/imurphy/projects/claude-devkit/generators/validate_skill.py "$skill"
done
```

### Manual Testing

1. **Template verification** -- Generate a new coder agent with `gen-agents /tmp/test-project --type coder --force`. Verify the generated agent includes the "Security Awareness" section between "Specialist Context Injection" and "Conflict Resolution".

2. **Template verification (QA)** -- Generate a new QA agent with `gen-agents /tmp/test-project --type qa-engineer --force`. Verify the generated agent includes the "Security Testing" section.

3. **CLAUDE.md verification** -- Verify all 13 core skills are listed in the skill registry with correct versions. Verify the security maturity levels section is present. Verify the template registry includes the new security section template.

4. **Test suite expansion** -- Run the expanded test suite. All tests should pass. The test count should be 46 (33 existing with cleanup renumbered to 46, plus 12 new skill validation tests 34-45).

5. **validate-all verification** -- Run `scripts/validate-all.sh`. Verify it validates all core skills and reports a summary.

6. **deploy --validate verification** -- Run `scripts/deploy.sh --validate`. Verify it validates skills before deploying. Test with a deliberately broken skill (temporarily add invalid frontmatter) to verify deployment is blocked.

7. **generate_agents exit code** -- Create a read-only directory and attempt to generate an agent into it. Verify the generator returns exit code 1.

### Exact Test Command

```bash
cd /Users/imurphy/projects/claude-devkit && bash generators/test_skill_generator.sh
```

## Acceptance Criteria

### Stream 1: Phase C Completion

- [ ] `templates/agents/coder-specialist.md.template` includes "Security Awareness" section with secure coding standards
- [ ] `templates/agents/qa-engineer-specialist.md.template` includes "Security Testing" section with security test requirements and test data security guidelines
- [ ] `templates/claude-md-security-section.md.template` exists with threat model, security requirements, secure development, and platform-specific sections
- [ ] CLAUDE.md skill registry verified current (all 13 core skills with correct versions -- no changes expected)
- [ ] CLAUDE.md stale "26 tests" count updated to "33 tests" in all three locations (lines 727, 913, 1058)
- [ ] CLAUDE.md template registry includes `claude-md-security-section.md.template`
- [ ] Security Maturity Levels documentation is present and accurate

### Stream 2: Quality Infrastructure

- [ ] Test suite validates all 13 core skills (architect, ship, audit, sync, retro, test-idempotent, receiving-code-review, verification-before-completion, secure-review, dependency-audit, secrets-scan, threat-model-gate, compliance-check)
- [ ] Test suite validates contrib skills when they exist (journal, journal-recall, journal-review)
- [ ] All expanded test suite tests pass
- [ ] `scripts/validate-all.sh` exists and validates all skills (core + contrib) with pass/fail summary and diagnostic output for failures
- [ ] `scripts/validate-all.sh` exits 0 when all skills pass, 1 when any fail
- [ ] `scripts/deploy.sh --validate` validates skills before deploying
- [ ] `scripts/deploy.sh --validate` blocks deployment of invalid skills
- [ ] `scripts/deploy.sh` without `--validate` works exactly as before (backward compatible)
- [ ] `generators/generate_agents.py` returns exit code 1 when any agent write fails or unknown agent types are requested
- [ ] `generators/generate_agents.py` returns exit code 0 when all agent writes succeed and all types are valid (unchanged behavior)

### Stream 3: Devkit Maturity

- [ ] CLAUDE.md roadmap updated with v1.0 completed items, v1.1 planned items, v1.2 planned items

## Task Breakdown

### Files to Create

| # | File | Purpose |
|---|------|---------|
| 1 | `templates/claude-md-security-section.md.template` | CLAUDE.md security section template for project bootstrapping |
| 2 | `scripts/validate-all.sh` | Single-command health check for all skills (core and contrib) |

### Files to Modify

| # | File | Change |
|---|------|--------|
| 3 | `templates/agents/coder-specialist.md.template` | Add "Security Awareness" section (insert after Specialist Context Injection, before Conflict Resolution) |
| 4 | `templates/agents/qa-engineer-specialist.md.template` | Add "Security Testing" section (insert after Specialist Context Injection, before Conflict Resolution) |
| 5 | `CLAUDE.md` | Verify skill registry (no changes expected), fix stale "26 tests" to "33 tests" in 3 locations, add security template to template registry, update roadmap, verify security maturity levels documentation |
| 6 | `generators/test_skill_generator.sh` | Add validation tests for 9 untested core skills + 3 contrib skills (tests 34-45), renumber cleanup to Test 46. Total: 46 tests. |
| 7 | `scripts/deploy.sh` | Add `--validate` flag that runs validate_skill.py before deploying |
| 8 | `generators/generate_agents.py` | Fix exit code bug: track write failures and unknown types, return 1 if any fail |

## Work Groups

### Work Group 1: Agent Template Updates (Stream 1)

- `templates/agents/coder-specialist.md.template`
- `templates/agents/qa-engineer-specialist.md.template`
- `templates/claude-md-security-section.md.template`

These are template files with no runtime dependencies. They can be modified and created independently.

### Work Group 2: Documentation (Stream 1)

- `CLAUDE.md`

Registry and roadmap updates. Depends on Work Group 1 being finalized (template registry references the new template file).

### Work Group 3: Test Suite Expansion (Stream 2)

- `generators/test_skill_generator.sh`

Additive tests only. No modifications to existing tests.

### Work Group 4: Validation and Deploy Infrastructure (Stream 2)

- `scripts/validate-all.sh`
- `scripts/deploy.sh`

New script and deploy enhancement. No dependencies between them.

### Work Group 5: Generator Bug Fix (Stream 2)

- `generators/generate_agents.py`

Isolated bug fix. No dependencies on other work groups.

## Implementation Plan

### Stream 1: Phase C Completion

#### Step 1.1: Agent Template Updates (Work Group 1)

1. [ ] Read `templates/agents/coder-specialist.md.template`
2. [ ] Insert "Security Awareness" section after `# Specialist Context Injection` and before `# Conflict Resolution`:

    ```markdown
    # Security Awareness

    ## Secure Coding Standards
    - Input validation for all external data
    - Parameterized queries (no string concatenation for SQL/NoSQL)
    - Output encoding by context (HTML, URL, JavaScript, CSS)
    - Use framework-provided CSRF protections
    - Never log sensitive data (passwords, tokens, PII)
    - Use constant-time comparison for secrets
    ```

3. [ ] Read `templates/agents/qa-engineer-specialist.md.template`
4. [ ] Insert "Security Testing" section after `# Specialist Context Injection` and before `# Conflict Resolution`:

    ```markdown
    # Security Testing

    ## Required Security Tests
    - Input validation boundary tests
    - Authentication bypass attempts
    - Authorization boundary tests (horizontal + vertical privilege escalation)
    - SQL/NoSQL injection test cases
    - XSS payload test cases
    - CSRF token validation tests

    ## Test Data Security
    - Never use production data in tests
    - Use realistic but synthetic PII
    - Rotate test credentials
    - Clean up test secrets from fixtures
    ```

5. [ ] Create `templates/claude-md-security-section.md.template` with threat model, security requirements, secure development, and platform-specific sections (content per Proposed Design section 1b)

#### Step 1.2: CLAUDE.md Updates (Work Group 2)

6. [ ] Read `CLAUDE.md`
7. [ ] Verify skill registry table has all 13 core skills with current versions. The CLAUDE.md skill registry already lists `/ship` v3.5.0 with security gates, `/architect` v3.1.0 with threat-model-gate awareness, `/audit` v3.1.0 with composability, and all 5 security skills. **No changes expected** to the skill registry table itself.
7b. [ ] Fix stale test count: Update "26 tests" to "33 tests" in three CLAUDE.md locations:
    - Generators section (line 727): `test_skill_generator.sh -- Test suite (26 tests)` -> `(33 tests)`
    - Coverage section (line 913): `**Coverage (26 tests):**` -> `**(33 tests):**`
    - Roadmap v1.0 section (line 1058): `Test suite (26 tests)` -> `(33 tests)`
8. [ ] Add `claude-md-security-section.md.template` to Template Registry table:

    | Template | Purpose | Archetype | Use Case |
    |----------|---------|-----------|----------|
    | **claude-md-security-section.md.template** | Security section for project CLAUDE.md | N/A | Project bootstrapping |

9. [ ] Verify Security Maturity Levels section exists and is accurate (L1/L2/L3 definitions, configuration example, security gates description)
10. [ ] Update roadmap section (mark completed items, add new items per Proposed Design section 3b)

#### Step 1.3: Stream 1 Verification

11. [ ] Visually verify template changes are correctly placed (after Specialist Context Injection, before Conflict Resolution)
12. [ ] Verify new template file exists at `templates/claude-md-security-section.md.template`
13. [ ] Run existing test suite to verify no regressions:
    ```bash
    cd /Users/imurphy/projects/claude-devkit && bash generators/test_skill_generator.sh
    ```
14. [ ] Commit Stream 1:
    ```bash
    git add templates/agents/coder-specialist.md.template templates/agents/qa-engineer-specialist.md.template templates/claude-md-security-section.md.template CLAUDE.md
    git commit -m "feat(phase-c): complete security documentation and templates

    Add security awareness sections to coder and QA agent templates.
    Create CLAUDE.md security section template for project bootstrapping.
    Update CLAUDE.md skill registry with current versions and security context.
    Update roadmap to reflect completed security initiative.

    Phase C of agentic-sdlc-security-skills plan.
    Implements: ./plans/agentic-sdlc-security-skills.md (Phase C)"
    ```

### Stream 2: Quality Infrastructure

#### Step 2.1: Expand Test Suite (Work Group 3)

15. [ ] Read `generators/test_skill_generator.sh`
16. [ ] After the existing Test 32 (undeploy nonexistent skill) and before Test 33 (cleanup), insert new validation tests. Core skill tests are **unconditional** (FAIL if missing). Contrib skill tests use conditional skip:

    ```bash
    # --- Core skill validation (unconditional -- FAIL if missing) ---

    # Test 34: Validate retro skill
    run_test 34 "Validate retro skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/retro/SKILL.md'" \
        0

    # Test 35: Validate test-idempotent skill
    run_test 35 "Validate test-idempotent skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/test-idempotent/SKILL.md'" \
        0

    # Test 36: Validate receiving-code-review skill
    run_test 36 "Validate receiving-code-review skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/receiving-code-review/SKILL.md'" \
        0

    # Test 37: Validate verification-before-completion skill
    run_test 37 "Validate verification-before-completion skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/verification-before-completion/SKILL.md'" \
        0

    # Test 38: Validate secure-review skill
    run_test 38 "Validate secure-review skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/secure-review/SKILL.md'" \
        0

    # Test 39: Validate dependency-audit skill
    run_test 39 "Validate dependency-audit skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/dependency-audit/SKILL.md'" \
        0

    # Test 40: Validate secrets-scan skill
    run_test 40 "Validate secrets-scan skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/secrets-scan/SKILL.md'" \
        0

    # Test 41: Validate threat-model-gate skill
    run_test 41 "Validate threat-model-gate skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/threat-model-gate/SKILL.md'" \
        0

    # Test 42: Validate compliance-check skill
    run_test 42 "Validate compliance-check skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/compliance-check/SKILL.md'" \
        0

    # --- Contrib skill validation (conditional -- skip if not present) ---

    # Test 43: Validate journal contrib skill (if exists)
    if [[ -f "$SKILLS_DIR/contrib/journal/SKILL.md" ]]; then
        run_test 43 "Validate journal contrib skill" \
            "python3 '$VALIDATE_PY' '$SKILLS_DIR/contrib/journal/SKILL.md'" \
            0
    else
        echo -e "${YELLOW}  Test 43: SKIP (journal contrib skill not found)${RESET}"
    fi

    # Test 44: Validate journal-recall contrib skill (if exists)
    if [[ -f "$SKILLS_DIR/contrib/journal-recall/SKILL.md" ]]; then
        run_test 44 "Validate journal-recall contrib skill" \
            "python3 '$VALIDATE_PY' '$SKILLS_DIR/contrib/journal-recall/SKILL.md'" \
            0
    else
        echo -e "${YELLOW}  Test 44: SKIP (journal-recall contrib skill not found)${RESET}"
    fi

    # Test 45: Validate journal-review contrib skill (if exists)
    if [[ -f "$SKILLS_DIR/contrib/journal-review/SKILL.md" ]]; then
        run_test 45 "Validate journal-review contrib skill" \
            "python3 '$VALIDATE_PY' '$SKILLS_DIR/contrib/journal-review/SKILL.md'" \
            0
    else
        echo -e "${YELLOW}  Test 45: SKIP (journal-review contrib skill not found)${RESET}"
    fi
    ```

17. [ ] Update the test script header comment from "33 test cases" to "46 test cases"
18. [ ] Renumber the cleanup test from Test 33 to **Test 46** (the final test)

#### Step 2.2: Create validate-all.sh (Work Group 4)

19. [ ] Create `scripts/validate-all.sh`:

    ```bash
    #!/usr/bin/env bash
    # Validate all skills in claude-devkit
    # Usage: ./scripts/validate-all.sh [--strict]
    #
    # Validates:
    #   - All core skills in skills/*/SKILL.md
    #   - All contrib skills in contrib/*/SKILL.md (if directory exists)
    #
    # Note: Agent templates are not validated here. They contain placeholder
    # variables that require generation before validation.
    #
    # Exit codes:
    #   0 = All validations passed
    #   1 = One or more validations failed

    set -euo pipefail
    shopt -s nullglob  # Prevent glob from expanding to literal string when no matches

    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    VALIDATE_PY="$REPO_DIR/generators/validate_skill.py"
    STRICT_FLAG="${1:-}"

    PASS_COUNT=0
    FAIL_COUNT=0
    TOTAL_COUNT=0

    validate_skill() {
        local skill_path="$1"
        local skill_name="$(basename "$(dirname "$skill_path")")"
        TOTAL_COUNT=$((TOTAL_COUNT + 1))

        if python3 "$VALIDATE_PY" "$skill_path" $STRICT_FLAG > /dev/null; then
            echo "  PASS: $skill_name"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            echo "  FAIL: $skill_name"
            # Re-run with stderr visible so the user can see why it failed
            python3 "$VALIDATE_PY" "$skill_path" $STRICT_FLAG 2>&1 | sed 's/^/    /' || true
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    }

    echo "Validating all claude-devkit skills..."
    echo ""

    # Core skills
    echo "Core skills (skills/):"
    for skill in "$REPO_DIR"/skills/*/SKILL.md; do
        validate_skill "$skill"
    done

    # Contrib skills
    if [ -d "$REPO_DIR/contrib" ]; then
        echo ""
        echo "Contrib skills (contrib/):"
        for skill in "$REPO_DIR"/contrib/*/SKILL.md; do
            validate_skill "$skill"
        done
    fi

    # Summary
    echo ""
    echo "========================================"
    echo "Validation Summary"
    echo "========================================"
    echo "Total:  $TOTAL_COUNT"
    echo "Pass:   $PASS_COUNT"
    echo "Fail:   $FAIL_COUNT"

    if [ $FAIL_COUNT -eq 0 ]; then
        echo ""
        echo "All skills validated successfully."
        exit 0
    else
        echo ""
        echo "Some skills failed validation."
        exit 1
    fi
    ```

    Key differences from Rev 1:
    - `shopt -s nullglob` prevents glob loops from iterating on literal strings when no files match (F-M1)
    - Failures show full validation output (re-runs validator with output visible) instead of suppressing all output (RT-M2)
    - Scoped to skills only; agent templates excluded with documented rationale (RT-m6/F-m2)
    - Removed `[ -f "$skill" ]` guard inside loops since `nullglob` ensures only real matches iterate

20. [ ] Make executable: `chmod +x scripts/validate-all.sh`

#### Step 2.3: Deploy Validation Flag (Work Group 4)

21. [ ] Read `scripts/deploy.sh`
22. [ ] Add `--validate` flag handling using a pre-processing loop **before** the existing `case` statement (do not add `--validate` as a case branch -- it is a modifier, not a dispatch target):

    ```bash
    # Add at top of script, before the case statement:
    VALIDATE=0
    ARGS=()
    for arg in "$@"; do
        if [ "$arg" = "--validate" ]; then
            VALIDATE=1
        else
            ARGS+=("$arg")
        fi
    done
    set -- "${ARGS[@]}"

    # Existing case statement on $1 proceeds unchanged.
    # The --validate flag is already extracted and $@ no longer contains it.
    ```

    In **both** `deploy_skill()` and `deploy_contrib_skill()`, before the `cp` command:

    ```bash
    if [ "$VALIDATE" -eq 1 ]; then
        if ! python3 "$REPO_DIR/generators/validate_skill.py" "$src/SKILL.md"; then
            echo "ERROR: Validation failed for '$skill'. Skipping deployment." >&2
            echo "  Run: python3 generators/validate_skill.py $src/SKILL.md" >&2
            return 1
        fi
    fi
    ```

    This ensures `--validate --contrib` and `--validate --all` also validate before deploying.

23. [ ] Update `show_help()` to document the `--validate` flag and its combinations (see interaction matrix in Proposed Design section 2c)

#### Step 2.4: Fix generate_agents.py Exit Code (Work Group 5)

24. [ ] Read `generators/generate_agents.py`
25. [ ] In the `generate_agents()` function, add write failure and unknown type tracking:

    ```python
    # After: generated = [], skipped = []
    write_failures = 0
    unknown_types = 0

    # At the unknown agent type branch (near line 433-435):
    # FROM:
    #     print(f"Unknown agent type: {agent_type}")
    #     continue
    # TO:
    #     print(f"Unknown agent type: {agent_type}", file=sys.stderr)
    #     unknown_types += 1
    #     continue

    # Change the existing continue after atomic_write failure:
    # FROM:
    #     print(f"Error: {error}", file=sys.stderr)
    #     continue
    # TO:
    #     print(f"Error: {error}", file=sys.stderr)
    #     write_failures += 1
    #     continue

    # Before the return statement, change:
    # FROM: return 0
    # TO: return 1 if (write_failures > 0 or unknown_types > 0) else 0
    ```

#### Step 2.5: Stream 2 Verification

26. [ ] Run expanded test suite:
    ```bash
    cd /Users/imurphy/projects/claude-devkit && bash generators/test_skill_generator.sh
    ```
27. [ ] If any new skill validation tests fail, fix the skill (not the test) and re-run
28. [ ] Run validate-all:
    ```bash
    cd /Users/imurphy/projects/claude-devkit && bash scripts/validate-all.sh
    ```
29. [ ] Test deploy with validation:
    ```bash
    cd /Users/imurphy/projects/claude-devkit && bash scripts/deploy.sh --validate
    ```
30. [ ] Verify deploy without --validate works as before:
    ```bash
    cd /Users/imurphy/projects/claude-devkit && bash scripts/deploy.sh architect
    ```
31. [ ] Commit Stream 2:
    ```bash
    git add generators/test_skill_generator.sh scripts/validate-all.sh scripts/deploy.sh generators/generate_agents.py
    git commit -m "feat(quality): expand test suite, add validate-all, deploy validation

    Add validation tests for all 13 core skills and 3 contrib skills to the
    test suite (tests 34-46). Core skills FAIL if missing. Previously only
    4 skills were tested.

    Add scripts/validate-all.sh for single-command devkit health check.
    Add --validate flag to deploy.sh to validate skills before deployment.
    Fix generate_agents.py exit code bug (return 1 on write failure or
    unknown agent types).

    Addresses recurring QA coverage gaps identified in .claude/learnings.md."
    ```

### Stream 3: Devkit Maturity (Roadmap Update)

32. [ ] If not already done in Step 1.2, update the CLAUDE.md Roadmap section per Proposed Design section 3b. Ensure the test count in the roadmap reflects the final count (46 tests after Stream 2 expansion). Also verify the three stale "26 tests" references were updated to "33 tests" in Stream 1, and further update them to "46 tests" after Stream 2 completes.
33. [ ] This can be combined with the Stream 2 commit if the roadmap was not updated in Stream 1

## Context Alignment

### CLAUDE.md Patterns Followed

- **Three-tier structure:** Templates in `templates/` (Tier 3). Scripts in `scripts/`. Generators in `generators/`. All changes are in the correct tier.
- **Deploy pattern:** `deploy.sh` enhancement preserves the existing `Edit -> validate -> deploy` workflow. The `--validate` flag makes the validate step automatic rather than manual.
- **Conventional commits:** All proposed commit messages follow `feat(scope): description` pattern.
- **Core vs Contrib:** Test suite expansion covers both `skills/` and `contrib/` directories, respecting the core vs contrib separation.
- **v2.0.0 patterns:** The test suite expansion validates all skills against v2.0.0 patterns, which is the enforcement mechanism for the architectural patterns.
- **Naming conventions:** New scripts follow existing naming patterns (`validate-all.sh` alongside `deploy.sh`, `install.sh`, `uninstall.sh`).

### Prior Plans Referenced

- **agentic-sdlc-security-skills.md (Rev 3)** -- Parent plan. Phase C specification (Section: "Phase C: Documentation and Templates") defines the exact template changes, CLAUDE.md updates, and agent-patterns.json modifications. This plan implements that specification.
- **security-guardrails-phase-b.md** -- Phase B implementation. Successfully shipped. The "Next Steps" section explicitly lists the Phase C items this plan addresses.
- **embedding-security-in-agentic-sdlc.md** -- Proposed standard. The CLAUDE.md security section template draws from this document's security requirements structure.
- **secure-review-remediation.md** -- Identified the `generate_agents.py` exit code bug in its code review findings. This plan fixes it.

### Deviations from Established Patterns

1. **agent-patterns.json not modified:** The parent plan specification says "Add `security` variant to coder and qa-engineer agent types." However, inspection of the current `configs/agent-patterns.json` shows these variants already exist (coder: `["security", "frontend", "python", "typescript"]`, qa-engineer: `["security", "frontend", "python"]`). This was likely done during a prior Phase A or generator update. **No change needed** -- the parent plan's requirement is already satisfied.

2. **Test suite numbering gap:** The existing test suite skips test #26 (there is no Test 26 -- numbering goes from 25 to 27). The new tests continue from 34 to maintain the existing numbering convention rather than renumbering all tests (which would create unnecessary diff noise and risk merge conflicts).

3. **validate-all.sh is a new script type:** The existing scripts directory has `deploy.sh`, `install.sh`, and `uninstall.sh` -- all operational scripts. `validate-all.sh` is a quality assurance script. **Justification:** It belongs in `scripts/` because it is a repository-level utility (not a generator and not a skill). The alternative of placing it in `generators/` was rejected because it validates skills, not generates them. Note: `validate-all.sh` validates skills only (not agent templates). Agent templates contain placeholder variables that require generation before validation, so they are excluded from automated validation.

4. **No /retro skill modification for learnings status tracking:** The proposed design section 3a describes adding a `## Status` column recommendation to `/retro` output format, but after analysis, this is better addressed as a separate micro-plan rather than bundled here. The status tracking would change the `/retro` skill's output contract, which requires its own validation cycle. **DEFERRED** to keep this plan focused on the three streams that have clear acceptance criteria. Section 3a in the Proposed Design is marked as DEFERRED accordingly.

5. **Plan filename differs from parent plan expectation:** The parent plan (`agentic-sdlc-security-skills.md`, line 490) specifies the Phase C plan file should be named `./plans/agentic-sdlc-security-phase-c-docs.md`. This plan uses `./plans/agentic-sdlc-next-phase.md` instead because it broadens scope beyond Phase C alone (adding quality infrastructure and devkit maturity). The parent plan's expected filename is superseded by this broader plan.

## Status: APPROVED

<!-- Context Metadata
discovered_at: 2026-03-27T10:00:00Z
claude_md_exists: true
recent_plans_consulted: security-guardrails-phase-b.md, embedding-security-in-agentic-sdlc.md, secure-review-remediation.md
archived_plans_consulted: agentic-sdlc-security-skills.md, security-guardrails-phase-b/security-guardrails-phase-b.code-review.md
-->
