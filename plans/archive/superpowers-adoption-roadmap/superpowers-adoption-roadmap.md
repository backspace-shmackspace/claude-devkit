# Plan: Superpowers Adoption Roadmap for Claude-Devkit

**Date:** 2026-03-05
**Author:** Senior Architect
**Target Repo:** `~/projects/claude-devkit`
**Affects:** `skills/`, `contrib/`, `scripts/deploy.sh`, `generators/validate_skill.py`, CLAUDE.md

---

## Revision Log

| Rev | Date | Trigger | Summary |
|-----|------|---------|---------|
| 1 | 2026-03-05 | Initial draft | 6-phase adoption roadmap with independent /dream + /ship cycles |
| 2 | 2026-03-05 | Red team, review, feasibility findings | Added Phase 0 (validator), behavioral tests, conflict resolution, rollback, licensing, corrected size estimates |

---

## Context

The [superpowers plugin](https://github.com/obra/superpowers) (v4.3.1, by Jesse Vincent) provides workflow discipline skills for Claude Code. After thorough analysis, six superpowers features have been identified as providing genuine value that claude-devkit lacks:

1. **systematic-debugging** -- Structured 4-phase root cause debugging methodology
2. **verification-before-completion** -- Evidence-before-claims gate preventing false completion claims
3. **test-driven-development** -- Strict red-green-refactor enforcement with anti-pattern reference
4. **receiving-code-review** -- Technical rigor for handling external review feedback
5. **dispatching-parallel-agents** -- Pattern for spinning up one agent per independent failure domain
6. **finishing-a-development-branch** -- Structured 4-option branch completion workflow

**What NOT to port** (devkit already has superior versions):
- brainstorming --> /dream is better (adversarial review, context discovery)
- writing-plans --> /dream produces detailed plans
- executing-plans --> /ship is better (worktree isolation, file boundary validation)
- subagent-driven-development --> /ship already does this with more safety rails
- using-git-worktrees --> worktree-manager-skill already exists in prodsecrm
- writing-skills --> meta-skill already exists in prodsecrm
- using-superpowers --> meta-skill that auto-triggers; devkit uses explicit invocation by design

### Licensing and Attribution

The superpowers plugin is published under the **MIT License** (see `LICENSE` in the plugin repository). MIT permits derivative works with attribution. All adapted skills must include an attribution comment in their SKILL.md frontmatter:

```yaml
attribution: "Adapted from superpowers plugin (v4.3.1) by Jesse Vincent, MIT License"
```

This satisfies the MIT license requirement to include the copyright notice in derivative works. The adapted skills are restructured for devkit conventions (not direct copies), but the structural concepts (Iron Laws, gate functions, red flag tables, rationalization tables) originate from superpowers and warrant attribution.

### Deployment Architecture Constraint

**Critical finding:** `deploy.sh` only copies `SKILL.md` from each skill directory. Supporting technique files (e.g., `root-cause-tracing.md`, `defense-in-depth.md`, `condition-based-waiting.md`, `testing-anti-patterns.md`) are NOT deployed to `~/.claude/skills/`.

**Design decision:** All supporting content must be embedded inline within `SKILL.md` as collapsed sections or appendices. This is architecturally sound because Claude Code reads the entire SKILL.md on invocation, and keeping everything in one file simplifies deployment, versioning, and validation. The alternative (modifying deploy.sh to recursively copy all files) would require changes across the tool chain and is deferred.

### Adaptation Philosophy

These are not direct ports. Each skill will be adapted to follow claude-devkit's v2.0.0 patterns:
- YAML frontmatter with `name`, `description`, `model`, `version`
- Numbered `## Step N -- [Action]` headers where applicable
- Tool declarations per step
- Verdict gates where applicable
- Timestamped artifacts where applicable

However, several of these skills are **behavioral disciplines** (not multi-step workflows). They do not naturally fit the Coordinator/Pipeline/Scan archetypes. The superpowers approach -- a single SKILL.md that acts as a **behavioral constraint document** -- is actually the correct pattern for these. Skills like `verification-before-completion` and `systematic-debugging` are invoked by Claude Code's skill matching, not by explicit `/command` invocation. They shape behavior rather than orchestrating a workflow.

**Design decision:** Behavioral discipline skills will use a **Reference** archetype -- a single SKILL.md with structured rules, gate functions, red flags, and anti-pattern tables. No numbered steps, no Tool declarations, no verdict gates. This is a new archetype for claude-devkit, distinct from Coordinator/Pipeline/Scan. Phase 0 adds validator support for this archetype before any Reference skills are created.

---

## Goals

1. **Adopt 6 workflow discipline features** from superpowers as new claude-devkit skills
2. **Maintain claude-devkit patterns** -- all skills pass `validate_skill.py` (Reference archetype validated via Phase 0 additions)
3. **Independent phases** -- each phase (1-6) is a standalone /dream + /ship cycle
4. **Core vs Contrib placement** -- behavioral disciplines go in `skills/` (universal), workflow-specific skills go in `contrib/` (opt-in)
5. **Deploy.sh compatibility** -- all content in SKILL.md, no supporting files required
6. **Clean validation** -- no `|| echo "Expected"` suppressions; all skills must pass their archetype's validation rules

## Non-Goals

1. **Direct porting** -- we adapt, not copy. Superpowers' content is restructured for devkit conventions.
2. **Modifying deploy.sh** -- supporting files will be embedded, not added as separate files.
3. **Modifying existing skills** -- /ship, /dream, /audit, /sync are not changed by this roadmap.
4. **Adding superpowers as a dependency** -- devkit skills are standalone.
5. **Implementing all superpowers skills** -- only the 6 identified in the gap analysis.

## Assumptions

1. claude-devkit's `validate_skill.py` can be extended to support a Reference archetype (Phase 0 confirms this).
2. Skills deployed to `~/.claude/skills/` are automatically available in Claude Code sessions.
3. Each phase (1-6) can be implemented independently without blocking other phases. Phase 0 must complete first.
4. The superpowers plugin content is available at `~/.claude/plugins/cache/claude-plugins-official/superpowers/4.3.1/`.
5. The superpowers plugin is MIT-licensed, permitting derivative works with attribution.

---

## Architectural Analysis

### Skill Classification

| Skill | Archetype | Tier | Rationale |
|-------|-----------|------|-----------|
| systematic-debugging | Reference | Core (`skills/`) | Universal debugging discipline, benefits all projects |
| verification-before-completion | Reference | Core (`skills/`) | Universal verification gate, prevents false claims |
| test-driven-development | Reference | Core (`skills/`) | Universal TDD enforcement, benefits all projects |
| receiving-code-review | Reference | Core (`skills/`) | Universal review reception discipline |
| dispatching-parallel-agents | Reference | Core (`skills/`) | Universal parallel debugging pattern |
| finishing-a-development-branch | Pipeline | Contrib (`contrib/`) | Workflow-specific, partially overlaps with /ship commit gate |

### Reference Archetype Definition

A new archetype for behavioral constraint skills:

**Characteristics:**
- Single SKILL.md with no numbered steps
- Activated by Claude Code's skill matching (description-triggered, not command-triggered)
- Contains: Iron Law / Core Principle, When to Use, Gate Functions, Red Flags, Anti-Pattern Tables, Rationalizations
- No Tool declarations, no verdict gates, no timestamped artifacts
- No archive references (no artifacts produced)
- Frontmatter includes `type: reference` to signal the archetype to the validator

**Validation (Phase 0):** `validate_skill.py` will be updated to detect `type: reference` in frontmatter and skip checks for numbered steps, tool declarations, verdict gates, inputs section, and minimum step count. Reference-specific checks will validate: valid frontmatter, presence of a core principle section, no empty body. This prevents masking real errors behind `|| echo "Expected"` suppressions.

### Activation Scoping and Conflict Resolution

Five Reference skills will be description-triggered (implicit activation). The following analysis addresses what happens when multiple skills could activate on the same prompt.

**Activation Domains:**

| Skill | Activates On | Does NOT Activate On |
|-------|-------------|---------------------|
| systematic-debugging | Debugging existing failures: test failures, runtime errors, unexpected behavior, build failures | New feature implementation, code review, task planning |
| test-driven-development | Implementing new features or bug fixes where code must be written | Pure debugging (no code changes yet), code review reception, task planning |
| verification-before-completion | About to claim work is complete, before committing or creating PRs | Mid-implementation work, initial investigation, planning |
| receiving-code-review | Receiving and responding to code review feedback | Writing code, debugging, self-review |
| dispatching-parallel-agents | 2+ independent tasks with no shared state that can run concurrently | Single failures, related failures, exploratory work |

**Expected Multi-Activation Scenarios:**

| Scenario | Skills Activated | Resolution |
|----------|-----------------|------------|
| Bug report arrives | systematic-debugging | Single activation -- investigate first, do not write code yet |
| Root cause found, fix needed | test-driven-development | Single activation -- write failing test, then fix |
| Fix implemented, about to commit | verification-before-completion | Single activation -- verify before claiming done |
| Bug report with 3 independent test failures | systematic-debugging + dispatching-parallel-agents | Compatible -- dispatch parallel agents, each follows debugging discipline |
| Code review feedback received on a fix | receiving-code-review | Single activation -- handle review feedback |

**Iron Law Priority (when skills appear to conflict):**
1. systematic-debugging's "investigate before fixing" takes precedence over TDD's "write test first" -- you cannot write a meaningful test until you understand the root cause. TDD activates after investigation identifies what to fix.
2. verification-before-completion activates last in any workflow -- it gates the completion claim, not the implementation approach.
3. receiving-code-review is scoped exclusively to external feedback contexts and does not overlap with the other four.

**Context Window Cost Analysis:**
- Each Reference skill will be ~8-22KB (see size estimates per phase)
- Claude Code's skill matching loads only skills whose descriptions match the current context -- it does not load all deployed skills simultaneously
- Worst-case simultaneous load: 2 skills (~30-40KB) in the bug-with-parallel-failures scenario
- For comparison, the existing /ship skill is 21KB alone; the context window accommodates this comfortably
- If empirical testing reveals context pressure, skill descriptions will be narrowed to reduce co-activation

### Phase Independence Analysis

| Phase | Depends On | Can Parallel With |
|-------|-----------|-------------------|
| Phase 0: Validator + Rollback | None | None (must complete first) |
| Phase 1: systematic-debugging | Phase 0 | Phases 2-6 |
| Phase 2: verification-before-completion | Phase 0 | Phases 1, 3-6 |
| Phase 3: test-driven-development | Phase 0 | Phases 1-2, 4-6 |
| Phase 4: receiving-code-review | Phase 0 | Phases 1-3, 5-6 |
| Phase 5: dispatching-parallel-agents | Phase 0 | Phases 1-4, 6 |
| Phase 6: finishing-a-development-branch | Phase 0 | Phases 1-5 |

Phase 0 is a prerequisite for all other phases. Phases 1-6 remain fully independent of each other.

---

## Implementation Plan

### Phase 0: Reference Archetype Validator Support + Rollback Mechanism

**Scope:** Update `validate_skill.py` to recognize the Reference archetype. Add a rollback procedure. This must complete before any Reference skill is created.

**Placement:** `~/projects/claude-devkit/generators/validate_skill.py`, `~/projects/claude-devkit/scripts/deploy.sh`

#### Task Breakdown

##### Files to Modify

| File | Change |
|------|--------|
| `generators/validate_skill.py` | Add Reference archetype detection via `type: reference` frontmatter field; skip numbered-step, verdict-gate, inputs, and minimum-step checks for Reference skills; add Reference-specific checks (valid frontmatter, non-empty body, presence of core principle heading) |
| `configs/skill-patterns.json` | Add `reference` archetype definition (consumed by the updated validator) |
| `scripts/deploy.sh` | Add `--undeploy <skill-name>` flag that removes `~/.claude/skills/<skill-name>/` directory |

#### Proposed Design

**Validator changes:**
1. Parse `type` field from YAML frontmatter (values: `pipeline`, `coordinator`, `scan`, `reference`; default: infer from structure as today)
2. When `type: reference` is detected, skip: Pattern 2 (Numbered Steps), Pattern 4 (Verdict Gates), Pattern 9 (Scope Parameters), Structural: Minimum Steps, Structural: Workflow Header
3. Apply Reference-specific checks: frontmatter fields (`name`, `description`, `version`, `type`, `attribution`), body is non-empty, at least one heading that contains "Law", "Principle", "Rule", or "Gate" (confirming core behavioral constraint is documented)
4. Exit code 0 for passing Reference skills (no `|| echo` suppression needed)

**Rollback mechanism:**
- `deploy.sh --undeploy <skill-name>`: removes `~/.claude/skills/<skill-name>/` and prints confirmation
- `deploy.sh --undeploy --contrib <skill-name>`: same for contrib skills
- Manual rollback documented in Risk Assessment section for cases where deploy.sh is unavailable

#### Test Plan

```bash
cd ~/projects/claude-devkit

# Create a minimal Reference skill fixture for testing
mkdir -p /tmp/test-reference-skill
cat > /tmp/test-reference-skill/SKILL.md << 'EOF'
---
name: test-reference
description: Test fixture for Reference archetype validation
model: claude-sonnet-4-5
version: 1.0.0
type: reference
attribution: "Test fixture"
---

# Test Reference Skill

## The Iron Law

Test principle.

## When to Use

Test trigger conditions.
EOF

# Validate -- must exit 0 (no suppression)
python generators/validate_skill.py /tmp/test-reference-skill/SKILL.md

# Validate a Pipeline skill still works
python generators/validate_skill.py skills/ship/SKILL.md

# Test undeploy
./scripts/deploy.sh test-reference
test -d ~/.claude/skills/test-reference && echo "DEPLOYED"
./scripts/deploy.sh --undeploy test-reference
test ! -d ~/.claude/skills/test-reference && echo "UNDEPLOYED"

# Cleanup
rm -rf /tmp/test-reference-skill
```

#### Acceptance Criteria

- [ ] `validate_skill.py` accepts `type: reference` in frontmatter and skips inapplicable checks
- [ ] `validate_skill.py` exits 0 for a valid Reference skill (no error suppression needed)
- [ ] `validate_skill.py` still exits non-zero for Reference skills with missing frontmatter or empty body
- [ ] Existing Pipeline/Coordinator/Scan skills continue to validate without changes
- [ ] `configs/skill-patterns.json` contains `reference` archetype definition consumed by the validator
- [ ] `deploy.sh --undeploy <name>` removes the skill directory from `~/.claude/skills/`
- [ ] `deploy.sh --undeploy --contrib <name>` removes contrib skill directory

---

### Phase 1: systematic-debugging Skill

**Scope:** Create a structured debugging discipline skill with embedded supporting techniques.

**Placement:** `~/projects/claude-devkit/skills/systematic-debugging/SKILL.md`

#### Task Breakdown

##### Files to Create

| File | Purpose |
|------|---------|
| `skills/systematic-debugging/SKILL.md` | Main skill definition with 4-phase debugging methodology and embedded supporting techniques |

##### Files to Modify

| File | Change |
|------|--------|
| `CLAUDE.md` | Add systematic-debugging to Skill Registry table |

#### Proposed Design

The SKILL.md will contain:

1. **Frontmatter:** name, description (triggers on bugs/failures/unexpected behavior -- NOT on new feature implementation), model: claude-sonnet-4-5, version: 1.0.0, type: reference, attribution
2. **The Iron Law:** "NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST"
3. **When to Use:** Trigger conditions (test failures, bugs, build failures, integration issues)
4. **When NOT to Use:** New feature implementation (use TDD instead), code review reception, task planning
5. **The Four Phases:**
   - Phase 1: Root Cause Investigation (read errors, reproduce, check changes, gather evidence, trace data flow)
   - Phase 2: Pattern Analysis (find working examples, compare against references, identify differences)
   - Phase 3: Hypothesis and Testing (form hypothesis, test minimally, verify)
   - Phase 4: Implementation (create failing test, single fix, verify, "3 failed fixes = question architecture" rule)
6. **Red Flags** -- thought patterns that mean "STOP, return to Phase 1"
7. **Common Rationalizations** table
8. **Embedded Supporting Techniques** (appendices):
   - Appendix A: Root Cause Tracing (backward tracing through call stack)
   - Appendix B: Defense-in-Depth Validation (4-layer validation pattern)
   - Appendix C: Condition-Based Waiting (replace arbitrary timeouts with condition polling)

**Estimated size:** ~20KB after adaptation (raw superpowers source is ~22KB across 4 files; adaptation restructures and trims cross-references).

**Key adaptations from superpowers:**
- Removed superpowers cross-references (`superpowers:test-driven-development` becomes a general reference to the TDD discipline)
- Removed "your human partner" framing (devkit skills address Claude Code directly)
- Embedded all three supporting technique files inline as appendices
- Added devkit frontmatter with `type: reference` and `attribution`
- Added explicit "When NOT to Use" section to narrow activation scope

#### Test Plan

```bash
cd ~/projects/claude-devkit

# 1. Validate skill (must exit 0 -- no suppression)
python generators/validate_skill.py skills/systematic-debugging/SKILL.md

# 2. Verify no superpowers cross-references
grep -c "superpowers:" skills/systematic-debugging/SKILL.md && echo "FAIL: superpowers refs found" || echo "PASS: no superpowers refs"

# 3. Verify no old framing
grep -ci "your human partner" skills/systematic-debugging/SKILL.md && echo "FAIL: old framing found" || echo "PASS: no old framing"

# 4. Verify attribution present
grep -q "attribution:" skills/systematic-debugging/SKILL.md && echo "PASS: attribution present" || echo "FAIL: no attribution"

# 5. Deploy and verify
./scripts/deploy.sh systematic-debugging
test -f ~/.claude/skills/systematic-debugging/SKILL.md && echo "PASS: deployed" || echo "FAIL: not deployed"

# 6. Behavioral smoke test: verify skill description triggers on debugging contexts
# Extract description from frontmatter and confirm it contains debugging trigger words
grep -i "description:" skills/systematic-debugging/SKILL.md | grep -qi "bug\|failure\|unexpected\|error" && echo "PASS: description targets debugging" || echo "FAIL: description too broad"

# 7. Full test suite
bash generators/test_skill_generator.sh
```

**Behavioral Acceptance Test (manual, documented):**

After deployment, run this prompt in a Claude Code session with the skill active:

> Prompt: "The tests in `tests/test_parser.py` are failing with `KeyError: 'status'`. Fix it."

Expected behavioral markers in response:
- [ ] Agent investigates the error before proposing a fix (reads the test, reads the parser, checks recent changes)
- [ ] Agent does NOT immediately write code or propose a patch
- [ ] Agent forms an explicit hypothesis before attempting a fix
- [ ] If first fix fails, agent returns to investigation rather than trying another guess

This test is manual because behavioral verification requires a live Claude Code session. Document results in the skill's PR description.

#### Acceptance Criteria

- [ ] `skills/systematic-debugging/SKILL.md` exists with valid YAML frontmatter including `type: reference` and `attribution`
- [ ] `validate_skill.py` exits 0 (no error suppression)
- [ ] Contains all 4 debugging phases with clear progression requirements
- [ ] Contains the "3 failed fixes = question architecture" escalation rule
- [ ] Contains embedded Root Cause Tracing, Defense-in-Depth, and Condition-Based Waiting appendices
- [ ] Contains "When NOT to Use" section scoping activation to debugging contexts only
- [ ] Deploys successfully via `deploy.sh systematic-debugging`
- [ ] CLAUDE.md Skill Registry updated with new entry
- [ ] No superpowers-specific cross-references remain
- [ ] No "your human partner" framing remains
- [ ] Behavioral smoke test completed and results documented in PR

---

### Phase 2: verification-before-completion Skill

**Scope:** Create an evidence-before-claims verification gate skill.

**Placement:** `~/projects/claude-devkit/skills/verification-before-completion/SKILL.md`

#### Task Breakdown

##### Files to Create

| File | Purpose |
|------|---------|
| `skills/verification-before-completion/SKILL.md` | Verification gate requiring evidence before completion claims |

##### Files to Modify

| File | Change |
|------|--------|
| `CLAUDE.md` | Add verification-before-completion to Skill Registry table |

#### Proposed Design

The SKILL.md will contain:

1. **Frontmatter:** name, description (triggers when about to claim work is complete, before committing/PRs), model: claude-sonnet-4-5, version: 1.0.0, type: reference, attribution
2. **The Iron Law:** "NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE"
3. **The Gate Function:** 5-step verification process (IDENTIFY, RUN, READ, VERIFY, CLAIM)
4. **Common Failures Table:** What each claim requires (tests pass, build succeeds, bug fixed, etc.)
5. **Red Flags:** Using "should", "probably", expressing satisfaction before verification
6. **Rationalization Prevention Table**
7. **Key Patterns:** Tests, regression tests (TDD red-green), build, requirements, agent delegation
8. **When to Apply:** Before ANY variation of success/completion claims
9. **Relationship to Other Skills:** This skill activates at the end of a workflow, after debugging (systematic-debugging) or implementation (TDD) is complete. It does not conflict with those skills -- it gates the final claim.

**Estimated size:** ~8KB after adaptation.

**Key adaptations from superpowers:**
- Removed "your human partner" framing and personal failure memories
- Removed "24 failure memories" anecdote (replaced with generic principle statement)
- Streamlined for devkit conventions
- Added `type: reference` and `attribution` to frontmatter

#### Test Plan

```bash
cd ~/projects/claude-devkit

# 1. Validate (must exit 0)
python generators/validate_skill.py skills/verification-before-completion/SKILL.md

# 2. Content checks
grep -c "superpowers:" skills/verification-before-completion/SKILL.md && echo "FAIL" || echo "PASS: no superpowers refs"
grep -ci "your human partner" skills/verification-before-completion/SKILL.md && echo "FAIL" || echo "PASS: no old framing"
grep -q "attribution:" skills/verification-before-completion/SKILL.md && echo "PASS" || echo "FAIL: no attribution"

# 3. Deploy and verify
./scripts/deploy.sh verification-before-completion
test -f ~/.claude/skills/verification-before-completion/SKILL.md && echo "PASS" || echo "FAIL"

# 4. Full test suite
bash generators/test_skill_generator.sh
```

**Behavioral Acceptance Test (manual, documented):**

> Prompt: "I implemented the feature. The code looks correct. Let's commit."

Expected behavioral markers:
- [ ] Agent does NOT immediately commit
- [ ] Agent identifies what verification evidence is needed (tests, build, lint)
- [ ] Agent runs verification commands and shows output
- [ ] Agent only claims completion after showing passing evidence

#### Acceptance Criteria

- [ ] `skills/verification-before-completion/SKILL.md` exists with valid YAML frontmatter including `type: reference` and `attribution`
- [ ] `validate_skill.py` exits 0 (no error suppression)
- [ ] Contains the 5-step gate function (IDENTIFY, RUN, READ, VERIFY, CLAIM)
- [ ] Contains the common failures table mapping claims to required evidence
- [ ] Contains red flags and rationalization prevention
- [ ] Deploys successfully via `deploy.sh verification-before-completion`
- [ ] CLAUDE.md Skill Registry updated with new entry
- [ ] Behavioral smoke test completed and results documented in PR

---

### Phase 3: test-driven-development Skill

**Scope:** Create a strict TDD enforcement skill with embedded anti-patterns reference.

**Placement:** `~/projects/claude-devkit/skills/test-driven-development/SKILL.md`

#### Task Breakdown

##### Files to Create

| File | Purpose |
|------|---------|
| `skills/test-driven-development/SKILL.md` | TDD enforcement with red-green-refactor cycle and anti-patterns reference |

##### Files to Modify

| File | Change |
|------|--------|
| `CLAUDE.md` | Add test-driven-development to Skill Registry table |

#### Proposed Design

The SKILL.md will contain:

1. **Frontmatter:** name, description (triggers when implementing features or bugfixes, before writing implementation code -- NOT when debugging existing failures), model: claude-sonnet-4-5, version: 1.0.0, type: reference, attribution
2. **The Iron Law:** "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST" -- write code before test? Delete it.
3. **Red-Green-Refactor Cycle:**
   - RED: Write failing test (requirements, good/bad examples)
   - Verify RED: Watch it fail (MANDATORY, never skip)
   - GREEN: Minimal code to pass
   - Verify GREEN: Watch it pass (MANDATORY)
   - REFACTOR: Clean up while keeping tests green
4. **Good Tests:** Quality criteria table (Minimal, Clear, Shows intent)
5. **Why Order Matters:** Detailed rebuttals for common objections
6. **Common Rationalizations Table**
7. **Red Flags -- STOP and Start Over**
8. **Bug Fix Integration:** Bug found --> investigate root cause first (defer to systematic-debugging) --> once cause is understood, write failing test --> TDD cycle
9. **Verification Checklist:** Before marking work complete (defer to verification-before-completion)
10. **Embedded Appendix: Testing Anti-Patterns**
    - Anti-Pattern 1: Testing Mock Behavior
    - Anti-Pattern 2: Test-Only Methods in Production
    - Anti-Pattern 3: Mocking Without Understanding
    - Anti-Pattern 4: Incomplete Mocks
    - Anti-Pattern 5: Integration Tests as Afterthought

**Estimated size:** ~15KB after adaptation.

**Key adaptations from superpowers:**
- Removed superpowers cross-references
- Removed "your human partner" framing
- Embedded testing-anti-patterns.md inline as appendix
- Examples kept language-agnostic (TypeScript examples retained as illustration but principle is universal)
- Added explicit scoping: activates on implementation, not debugging
- Added cross-references to systematic-debugging (for bug investigation) and verification-before-completion (for completion gate)

#### Test Plan

```bash
cd ~/projects/claude-devkit

# 1. Validate (must exit 0)
python generators/validate_skill.py skills/test-driven-development/SKILL.md

# 2. Content checks
grep -c "superpowers:" skills/test-driven-development/SKILL.md && echo "FAIL" || echo "PASS"
grep -ci "your human partner" skills/test-driven-development/SKILL.md && echo "FAIL" || echo "PASS"
grep -q "attribution:" skills/test-driven-development/SKILL.md && echo "PASS" || echo "FAIL"

# 3. Deploy and verify
./scripts/deploy.sh test-driven-development
test -f ~/.claude/skills/test-driven-development/SKILL.md && echo "PASS" || echo "FAIL"

# 4. Full test suite
bash generators/test_skill_generator.sh
```

**Behavioral Acceptance Test (manual, documented):**

> Prompt: "Add a `parse_config()` function that reads YAML config files and returns a dict."

Expected behavioral markers:
- [ ] Agent writes a test for `parse_config()` BEFORE writing the implementation
- [ ] Agent runs the test and shows it failing (RED phase)
- [ ] Agent then writes minimal implementation
- [ ] Agent runs the test again and shows it passing (GREEN phase)

#### Acceptance Criteria

- [ ] `skills/test-driven-development/SKILL.md` exists with valid YAML frontmatter including `type: reference` and `attribution`
- [ ] `validate_skill.py` exits 0 (no error suppression)
- [ ] Contains the Iron Law ("delete code written before tests")
- [ ] Contains complete Red-Green-Refactor cycle with verification steps
- [ ] Contains embedded Testing Anti-Patterns appendix (5 anti-patterns)
- [ ] Contains bug fix integration guidance referencing systematic-debugging for investigation
- [ ] Deploys successfully via `deploy.sh test-driven-development`
- [ ] CLAUDE.md Skill Registry updated with new entry
- [ ] Behavioral smoke test completed and results documented in PR

---

### Phase 4: receiving-code-review Skill

**Scope:** Create a code review reception discipline skill.

**Placement:** `~/projects/claude-devkit/skills/receiving-code-review/SKILL.md`

#### Task Breakdown

##### Files to Create

| File | Purpose |
|------|---------|
| `skills/receiving-code-review/SKILL.md` | Code review reception discipline with YAGNI checks and pushback guidelines |

##### Files to Modify

| File | Change |
|------|--------|
| `CLAUDE.md` | Add receiving-code-review to Skill Registry table |

#### Proposed Design

The SKILL.md will contain:

1. **Frontmatter:** name, description (triggers when receiving code review feedback, before implementing suggestions), model: claude-sonnet-4-5, version: 1.0.0, type: reference, attribution
2. **The Response Pattern:** 6-step process (READ, UNDERSTAND, VERIFY, EVALUATE, RESPOND, IMPLEMENT)
3. **Forbidden Responses:** No performative agreement ("You're absolutely right!", "Great point!")
4. **Handling Unclear Feedback:** Stop, do not implement anything, ask for clarification
5. **Source-Specific Handling:** From user vs. from external reviewers
6. **YAGNI Check:** grep codebase for actual usage before implementing "properly"
7. **Implementation Order:** Clarify first, then blocking --> simple --> complex, test each
8. **When to Push Back:** Technical reasoning, not defensiveness
9. **Acknowledging Correct Feedback:** "Fixed. [description]" -- no gratitude expressions
10. **Common Mistakes Table**
11. **GitHub Thread Replies:** Reply in comment thread, not top-level

**Estimated size:** ~8KB after adaptation.

**Key adaptations from superpowers:**
- Generalized "your human partner" to "the user" or "the project owner"
- Removed personal code phrase ("Strange things are afoot at the Circle K")
- Retained the core YAGNI and anti-performative-agreement principles
- Streamlined for devkit conventions

#### Test Plan

```bash
cd ~/projects/claude-devkit

# 1. Validate (must exit 0)
python generators/validate_skill.py skills/receiving-code-review/SKILL.md

# 2. Content checks
grep -c "superpowers:" skills/receiving-code-review/SKILL.md && echo "FAIL" || echo "PASS"
grep -ci "your human partner" skills/receiving-code-review/SKILL.md && echo "FAIL" || echo "PASS"
grep -q "attribution:" skills/receiving-code-review/SKILL.md && echo "PASS" || echo "FAIL"

# 3. Deploy and verify
./scripts/deploy.sh receiving-code-review
test -f ~/.claude/skills/receiving-code-review/SKILL.md && echo "PASS" || echo "FAIL"

# 4. Full test suite
bash generators/test_skill_generator.sh
```

**Behavioral Acceptance Test (manual, documented):**

> Prompt: "Review feedback: 'This function should use a class instead of a dict for type safety.' Please implement."

Expected behavioral markers:
- [ ] Agent does NOT immediately refactor to a class
- [ ] Agent evaluates whether the suggestion is warranted (YAGNI check -- is the dict actually causing problems?)
- [ ] Agent does NOT use performative agreement ("Great point!", "You're absolutely right!")
- [ ] If implementing, agent provides technical reasoning; if pushing back, agent provides technical reasoning

#### Acceptance Criteria

- [ ] `skills/receiving-code-review/SKILL.md` exists with valid YAML frontmatter including `type: reference` and `attribution`
- [ ] `validate_skill.py` exits 0 (no error suppression)
- [ ] Contains the 6-step response pattern (READ through IMPLEMENT)
- [ ] Contains forbidden responses section (no performative agreement)
- [ ] Contains YAGNI check pattern (grep before implementing "properly")
- [ ] Contains pushback guidelines with technical reasoning approach
- [ ] Contains source-specific handling (user vs. external reviewer)
- [ ] Deploys successfully via `deploy.sh receiving-code-review`
- [ ] CLAUDE.md Skill Registry updated with new entry
- [ ] Behavioral smoke test completed and results documented in PR

---

### Phase 5: dispatching-parallel-agents Skill

**Scope:** Create a parallel agent dispatch pattern skill for independent debugging tasks.

**Placement:** `~/projects/claude-devkit/skills/dispatching-parallel-agents/SKILL.md`

#### Task Breakdown

##### Files to Create

| File | Purpose |
|------|---------|
| `skills/dispatching-parallel-agents/SKILL.md` | Pattern for dispatching one agent per independent failure domain |

##### Files to Modify

| File | Change |
|------|--------|
| `CLAUDE.md` | Add dispatching-parallel-agents to Skill Registry table |

#### Proposed Design

The SKILL.md will contain:

1. **Frontmatter:** name, description (triggers when facing 2+ independent tasks without shared state), model: claude-sonnet-4-5, version: 1.0.0, type: reference, attribution
2. **When to Use:** Decision tree (multiple failures? -> independent? -> parallel dispatch vs. sequential vs. single agent)
3. **The Pattern:**
   - Step 1: Identify Independent Domains (group failures by subsystem)
   - Step 2: Create Focused Agent Tasks (scope, goal, constraints, expected output)
   - Step 3: Dispatch in Parallel (via Task tool)
   - Step 4: Review and Integrate (read summaries, verify no conflicts, run full suite)
4. **Agent Prompt Structure:** Good prompts are focused, self-contained, specific about output
5. **Common Mistakes:** Too broad, no context, no constraints, vague output expectations
6. **When NOT to Use:** Related failures, need full context, exploratory debugging, shared state
7. **Verification:** Review summaries, check for conflicts, run full suite, spot check

**Estimated size:** ~10KB after adaptation.

**Key adaptations from superpowers:**
- Retained the core parallel dispatch pattern essentially as-is (it is well-designed)
- Adjusted code examples to be tool-agnostic (Task tool reference instead of specific framework)
- Added integration with devkit's existing /ship worktree pattern (reference, not dependency)

#### Test Plan

```bash
cd ~/projects/claude-devkit

# 1. Validate (must exit 0)
python generators/validate_skill.py skills/dispatching-parallel-agents/SKILL.md

# 2. Content checks
grep -c "superpowers:" skills/dispatching-parallel-agents/SKILL.md && echo "FAIL" || echo "PASS"
grep -ci "your human partner" skills/dispatching-parallel-agents/SKILL.md && echo "FAIL" || echo "PASS"
grep -q "attribution:" skills/dispatching-parallel-agents/SKILL.md && echo "PASS" || echo "FAIL"

# 3. Deploy and verify
./scripts/deploy.sh dispatching-parallel-agents
test -f ~/.claude/skills/dispatching-parallel-agents/SKILL.md && echo "PASS" || echo "FAIL"

# 4. Full test suite
bash generators/test_skill_generator.sh
```

**Behavioral Acceptance Test (manual, documented):**

> Prompt: "Three test files are failing: test_parser.py, test_renderer.py, and test_exporter.py. They test independent modules. Fix all of them."

Expected behavioral markers:
- [ ] Agent recognizes the independence of the three failures
- [ ] Agent dispatches parallel tasks (one per module) rather than fixing sequentially
- [ ] Each dispatched task has a scoped prompt with constraints
- [ ] Agent reviews and integrates results after parallel tasks complete

#### Acceptance Criteria

- [ ] `skills/dispatching-parallel-agents/SKILL.md` exists with valid YAML frontmatter including `type: reference` and `attribution`
- [ ] `validate_skill.py` exits 0 (no error suppression)
- [ ] Contains the 4-step pattern (Identify, Create, Dispatch, Review)
- [ ] Contains agent prompt structure guidelines (focused, self-contained, specific)
- [ ] Contains common mistakes section with good/bad examples
- [ ] Contains "When NOT to Use" decision criteria
- [ ] Deploys successfully via `deploy.sh dispatching-parallel-agents`
- [ ] CLAUDE.md Skill Registry updated with new entry
- [ ] Behavioral smoke test completed and results documented in PR

---

### Phase 6: finishing-a-development-branch Skill

**Scope:** Create a structured branch completion workflow skill.

**Placement:** `~/projects/claude-devkit/contrib/finishing-branch/SKILL.md`

**Rationale for contrib (not core):** This skill partially overlaps with /ship's commit gate (Step 6) and the worktree-manager-skill in prodsecrm. It is most useful in projects that use feature branches without /ship, making it a workflow preference rather than a universal discipline.

#### Task Breakdown

##### Files to Create

| File | Purpose |
|------|---------|
| `contrib/finishing-branch/SKILL.md` | Structured 4-option branch completion workflow |

##### Files to Modify

| File | Change |
|------|--------|
| `CLAUDE.md` | Add finishing-branch to Contrib Skills table |
| `contrib/README.md` | Add finishing-branch entry with prerequisites |

#### Proposed Design

The SKILL.md will follow the **Pipeline archetype** (sequential steps with gates):

1. **Frontmatter:** name: finishing-branch, description (triggers when implementation is complete, all tests pass, and branch needs integration), model: claude-sonnet-4-5, version: 1.0.0, attribution
2. **Step 0 -- Verify Tests:** Run project test suite. If tests fail, stop. Cannot proceed until green.
3. **Step 1 -- Determine Base Branch:** Detect base branch (main/master) via merge-base.
4. **Step 2 -- Present Options:** Exactly 4 options:
   1. Merge locally
   2. Push and create PR
   3. Keep branch as-is
   4. Discard (with typed confirmation)
5. **Step 3 -- Execute Choice:** Branch-specific logic for each option.
6. **Step 4 -- Cleanup Worktree:** Remove worktree for options 1, 2, 4. Keep for option 3.

**Estimated size:** ~8KB after adaptation.

**Key adaptations from superpowers:**
- Restructured as numbered steps following devkit Pipeline archetype
- Added Tool declarations per step (Bash for git operations)
- Added verdict gate at Step 0 (test verification)
- Retained the 4-option structure exactly (well-designed)
- Added discard confirmation gate

#### Test Plan

```bash
cd ~/projects/claude-devkit

# 1. Validate (must exit 0 -- Pipeline archetype, standard validation)
python generators/validate_skill.py contrib/finishing-branch/SKILL.md

# 2. Content checks
grep -c "superpowers:" contrib/finishing-branch/SKILL.md && echo "FAIL" || echo "PASS"
grep -ci "your human partner" contrib/finishing-branch/SKILL.md && echo "FAIL" || echo "PASS"
grep -q "attribution:" contrib/finishing-branch/SKILL.md && echo "PASS" || echo "FAIL"

# 3. Deploy and verify
./scripts/deploy.sh --contrib finishing-branch
test -f ~/.claude/skills/finishing-branch/SKILL.md && echo "PASS" || echo "FAIL"

# 4. Full test suite
bash generators/test_skill_generator.sh
```

#### Acceptance Criteria

- [ ] `contrib/finishing-branch/SKILL.md` exists with valid YAML frontmatter including `attribution`
- [ ] `validate_skill.py` exits 0 (Pipeline archetype, standard validation)
- [ ] Contains numbered steps following Pipeline archetype
- [ ] Contains test verification gate at Step 0
- [ ] Presents exactly 4 options (merge, PR, keep, discard)
- [ ] Contains typed confirmation for discard option
- [ ] Contains worktree cleanup logic
- [ ] Deploys successfully via `./scripts/deploy.sh --contrib finishing-branch`
- [ ] CLAUDE.md Contrib Skills table updated with new entry
- [ ] `contrib/README.md` updated with finishing-branch entry

---

## Interfaces / Schema Changes

### Reference Archetype in skill-patterns.json

Add to `configs/skill-patterns.json` (consumed by the updated `validate_skill.py` -- see Phase 0):

```json
{
  "reference": {
    "required_frontmatter": ["name", "description", "version", "type", "attribution"],
    "required_sections": ["core_principle"],
    "core_principle_patterns": ["Iron Law", "Core Principle", "Fundamental Rule", "The Gate"],
    "requires_numbered_steps": false,
    "requires_tool_declarations": false,
    "requires_verdict_gates": false,
    "requires_artifacts": false,
    "requires_inputs_section": false,
    "requires_workflow_header": false
  }
}
```

This schema is consumed by `validate_skill.py` (Phase 0 implementation). It is not dead configuration.

### deploy.sh Changes

Add `--undeploy` flag (Phase 0). No other changes required -- all content is embedded in SKILL.md.

### CLAUDE.md Registry Changes

Add to the Core Skills table (after test-idempotent):

| Skill | Version | Purpose | Model | Archetype |
|-------|---------|---------|-------|-----------|
| **systematic-debugging** | 1.0.0 | 4-phase root cause debugging with embedded techniques (tracing, defense-in-depth, condition-based waiting). Triggers on bugs, test failures, unexpected behavior. | claude-sonnet-4-5 | Reference |
| **verification-before-completion** | 1.0.0 | Evidence-before-claims gate. Requires running verification commands and showing output before claiming work is done. | claude-sonnet-4-5 | Reference |
| **test-driven-development** | 1.0.0 | Strict red-green-refactor enforcement with embedded testing anti-patterns reference. | claude-sonnet-4-5 | Reference |
| **receiving-code-review** | 1.0.0 | Technical rigor for code review reception. No performative agreement. YAGNI checks. Push back with reasoning. | claude-sonnet-4-5 | Reference |
| **dispatching-parallel-agents** | 1.0.0 | Pattern for dispatching one agent per independent failure domain. Scoped prompts, constraints, integration verification. | claude-sonnet-4-5 | Reference |

Add to the Contrib Skills table:

| Skill | Version | Purpose | Prerequisites | Archetype |
|-------|---------|---------|--------------|-----------|
| **finishing-branch** | 1.0.0 | Structured 4-option branch completion (merge/PR/keep/discard) with test verification gate and worktree cleanup. | git, gh CLI (for PR creation) | Pipeline |

---

## Data Migration

None. This is purely additive (new skill files, registry entries, and validator enhancement).

---

## Rollout Plan

Each phase is independently deployable (after Phase 0). Recommended order (by value density and risk):

1. **Phase 0: Validator + Rollback** -- Must be first. Unblocks clean validation for all Reference skills and provides rollback capability.
2. **Phase 4: receiving-code-review** -- Narrowest activation scope; lowest risk of over-triggering. Serves as canary deployment for the Reference archetype.
3. **Phase 2: verification-before-completion** -- Highest impact. Deployed after canary validates the Reference approach.
4. **Phase 1: systematic-debugging** -- Second highest impact. Largest skill file (~20KB).
5. **Phase 3: test-driven-development** -- Enforces testing discipline.
6. **Phase 5: dispatching-parallel-agents** -- Useful for complex debugging sessions.
7. **Phase 6: finishing-a-development-branch** -- Contrib, lowest priority.

**Canary strategy:** Phase 4 (receiving-code-review) is deployed first among Reference skills because it has the narrowest trigger scope (only activates on code review feedback) and the lowest risk of interfering with normal workflows. If the Reference archetype causes problems in practice (unexpected triggering, context issues), the issue will surface in a low-impact context before the more aggressively-triggering skills (verification-before-completion, systematic-debugging) are deployed.

**Rollback procedure:** If any deployed skill degrades output quality:
1. `./scripts/deploy.sh --undeploy <skill-name>` removes it from `~/.claude/skills/`
2. Remove the CLAUDE.md registry entry
3. The skill source remains in the repo for iteration but is no longer active

Each phase follows this cycle:

```
/dream [phase description] --> /ship plans/[phase-plan].md --> deploy.sh [skill-name] --> behavioral smoke test
```

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Skill description too broad, triggers on unrelated contexts | Medium | Medium | Each skill has explicit "When to Use" AND "When NOT to Use" sections. Descriptions are scoped to specific trigger conditions. Canary deployment (Phase 4 first) validates the approach. Iterate on description wording based on behavioral tests. |
| Multiple skills activate simultaneously, causing contradictory instructions | Medium | Medium | Activation domains are explicitly non-overlapping (see Conflict Resolution section). Iron Law priority documented. Context window cost analyzed (~30-40KB worst case, within normal range). Description scoping prevents most co-activation. |
| Embedded appendices make SKILL.md too large for effective context | Low | Medium | Largest skill is systematic-debugging at ~20KB (comparable to existing /ship at 21KB). Worst-case simultaneous load is ~30-40KB (2 skills). If empirical testing shows context pressure, narrow descriptions to reduce co-activation or extract appendices to "see also" references. |
| Deployed skill degrades output quality (over-literal Iron Law interpretation) | Medium | High | Rollback via `deploy.sh --undeploy <name>`. Canary deployment catches issues before high-impact skills are deployed. Behavioral smoke tests documented per phase. |
| deploy.sh single-file limitation creates maintenance burden | Low | Low | Accepted tradeoff. Embedding is simpler than modifying the deploy chain. If many skills need supporting files, revisit deploy.sh. |
| Superpowers plugin updates diverge from devkit adaptations | Low | Low | These are independent adaptations, not mirrors. Devkit skills evolve independently based on user needs. Attribution maintained per MIT license. |
| deploy.sh does not support `--contrib` flag | Low | High | Verify before Phase 6 implementation. If unsupported, add the flag or document manual deployment steps. |

**Rollback procedure (manual fallback):** If `deploy.sh --undeploy` is unavailable:
```bash
rm -rf ~/.claude/skills/<skill-name>
# Then remove the entry from CLAUDE.md Skill Registry
```

---

## Test Plan

For each phase, after implementation:

```bash
# 1. Validate skill structure (must exit 0 -- no suppression)
cd ~/projects/claude-devkit
python generators/validate_skill.py skills/<skill-name>/SKILL.md

# 2. Content checks (automated)
grep -c "superpowers:" skills/<skill-name>/SKILL.md && echo "FAIL" || echo "PASS"
grep -ci "your human partner" skills/<skill-name>/SKILL.md && echo "FAIL" || echo "PASS"
grep -q "attribution:" skills/<skill-name>/SKILL.md && echo "PASS" || echo "FAIL"

# 3. Deploy skill
./scripts/deploy.sh <skill-name>

# 4. Verify deployment
test -f ~/.claude/skills/<skill-name>/SKILL.md && echo "PASS" || echo "FAIL"

# 5. Run full test suite (ensures no regressions)
bash generators/test_skill_generator.sh

# 6. Behavioral smoke test (manual -- see per-phase section)
# Run the documented prompt in a Claude Code session
# Verify behavioral markers are present in response
# Document results in PR description
```

**Test command for CI:**

```bash
cd ~/projects/claude-devkit && bash generators/test_skill_generator.sh
```

---

## Context Alignment

### CLAUDE.md Patterns Followed
- **Skill location:** `skills/<skill-name>/SKILL.md` for core, `contrib/<skill-name>/SKILL.md` for optional
- **YAML frontmatter:** name, description, model, version fields
- **Core vs Contrib:** Universal disciplines in `skills/`, workflow preferences in `contrib/`
- **deploy.sh compatibility:** Single SKILL.md per skill directory
- **Plans location:** This roadmap saved to `./plans/` per convention
- **Conventional commits:** Implementation commits will follow `feat(skills):` pattern

### Prior Plans Related
- **zerg-adoption-priorities.md** (claude-devkit plans/) -- Established the pattern for multi-phase adoption roadmaps with independent /ship cycles
- **ship-always-worktree.md** (claude-devkit plans/) -- Established worktree isolation as a core pattern (Phase 6 references worktree cleanup)
- **journal-skill-blueprint.md** (claude-devkit plans/) -- Established the contrib/ tier for optional/personal skills

### Deviations from Established Patterns
- **New Reference archetype:** Behavioral discipline skills do not follow Coordinator/Pipeline/Scan patterns. This is a justified deviation because these skills shape behavior rather than orchestrate workflows. The archetype is supported by Phase 0 validator changes and documented in CLAUDE.md.
- **Model selection (claude-sonnet-4-5):** Reference skills use Sonnet, not Opus, because they are behavioral constraints read at context-load time, not expensive multi-agent orchestrations. This follows the existing pattern where /sync uses Sonnet.

---

## Verification

After all phases (0-6) are complete:

- [ ] `validate_skill.py` supports Reference archetype via `type: reference` frontmatter (Phase 0)
- [ ] `deploy.sh --undeploy` removes skills cleanly (Phase 0)
- [ ] 5 new skills in `skills/` directory (systematic-debugging, verification-before-completion, test-driven-development, receiving-code-review, dispatching-parallel-agents)
- [ ] 1 new skill in `contrib/` directory (finishing-branch)
- [ ] All 6 skills pass `validate_skill.py` with exit code 0 (no error suppression)
- [ ] All 6 skills deploy successfully via deploy.sh
- [ ] CLAUDE.md Skill Registry updated with all 6 entries
- [ ] contrib/README.md updated with finishing-branch entry
- [ ] Full test suite passes: `bash generators/test_skill_generator.sh`
- [ ] No superpowers-specific cross-references in any skill file
- [ ] No "your human partner" framing in any skill file
- [ ] All skills include `attribution` in frontmatter (MIT license compliance)
- [ ] Behavioral smoke tests completed for all 5 Reference skills (results documented in PRs)

---

## Next Steps

1. **Immediate:** Implement Phase 0 (validator Reference archetype support + rollback mechanism)
2. **Then:** Run `/dream` for Phase 4 (receiving-code-review) as canary deployment
3. **Then:** Run `/ship` on the approved Phase 4 plan, deploy, run behavioral smoke test
4. **Then:** Proceed with remaining phases in rollout order (2, 1, 3, 5, 6)
5. **After all phases:** Run `/sync` to update CLAUDE.md comprehensively

Each phase generates its own plan file at `~/projects/claude-devkit/plans/<phase-name>.md` via /dream, which then gets implemented via /ship.

---

## Plan Metadata

- **Plan File:** `./plans/superpowers-adoption-roadmap.md`
- **Affected Components:** `~/projects/claude-devkit/skills/`, `~/projects/claude-devkit/contrib/`, `~/projects/claude-devkit/generators/validate_skill.py`, `~/projects/claude-devkit/configs/skill-patterns.json`, `~/projects/claude-devkit/scripts/deploy.sh`, `~/projects/claude-devkit/CLAUDE.md`, `~/projects/claude-devkit/contrib/README.md`
- **Validation:** `cd ~/projects/claude-devkit && bash generators/test_skill_generator.sh`

## Status: APPROVED

<!-- Context Metadata
discovered_at: 2026-03-05T10:00:00Z
claude_md_exists: true
recent_plans_consulted: zerg-adoption-priorities.md, ship-always-worktree.md, journal-skill-blueprint.md
archived_plans_consulted: dream-remove-mcp-deps, audit-remove-mcp-deps
superpowers_version: 4.3.1
superpowers_path: ~/.claude/plugins/cache/claude-plugins-official/superpowers/4.3.1/
superpowers_license: MIT
revision: 2
revision_trigger: redteam-review-feasibility
-->
