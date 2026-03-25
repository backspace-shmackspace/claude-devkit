# Feasibility Review: Superpowers Adoption Roadmap (Rev 2)

**Reviewer:** code-reviewer agent
**Date:** 2026-03-05
**Plan:** `./plans/superpowers-adoption-roadmap.md` (Revision 2)
**Review Round:** 2 (re-review after Round 1 revisions)

---

## Code Review Summary

Revision 2 addresses all three Round 1 concerns substantively. The validator
hard-error problem is solved by the `type: reference` frontmatter dispatch
and a dedicated Phase 0. The systematic-debugging size estimate is now realistic
(~20KB with explicit comparison to ship's 21KB). The `skill-patterns.json`
config is no longer dead -- the plan explicitly ties it to the Phase 0 validator
implementation. No critical or blocking issues remain. The plan is ready for
implementation.

---

## Round 1 Concern Resolution Assessment

### 1. validate_skill.py hard errors for Reference archetype -- RESOLVED

The plan now specifies a `type: reference` field in frontmatter (lines 120-122)
and details which checks to skip: Pattern 2 (Numbered Steps), Pattern 4
(Verdict Gates), Pattern 9 (Scope Parameters), Structural Minimum Steps,
Structural Workflow Header. Phase 0 is explicitly gated as a prerequisite for
all other phases.

The approach is correct given the validator's architecture. The current
`main()` function unconditionally calls all five validation functions
(`validate_frontmatter`, `validate_workflow_header`, `validate_inputs_section`,
`validate_steps`, `validate_patterns`). Phase 0 needs to add a conditional
branch on `frontmatter.get("type") == "reference"` to skip the workflow-oriented
functions and call Reference-specific validation instead. This is straightforward
(~30-50 lines of Python) and well within the plan's scope.

The `|| echo "Expected"` suppression pattern is eliminated. Good.

**Status:** Resolved. One implementation detail noted (see Major M1).

### 2. Size estimate for systematic-debugging -- RESOLVED

Revised to ~20KB with rationale: "raw superpowers source is ~22KB across 4
files; adaptation restructures and trims cross-references." The /ship skill
is confirmed at 21,386 bytes (`wc -c`), making the ~20KB estimate credible.
The context window analysis (worst-case ~30-40KB for 2 co-activated skills)
is reasonable and grounded in measured data.

**Status:** Resolved. No further concerns.

### 3. skill-patterns.json dead config -- RESOLVED

Line 840 explicitly states: "This schema is consumed by `validate_skill.py`
(Phase 0 implementation). It is not dead configuration." The plan specifies
adding a `reference` key with `required_frontmatter`, `requires_numbered_steps:
false`, etc. Phase 0 acceptance criteria (line 257) require the validator to
consume this config.

**Status:** Resolved. Minor structural suggestion (see Minor m2).

---

## Critical Issues (Must Fix)

None.

---

## Major Improvements (Should Fix)

### M1: Phase 0 should specify the validator skip mechanism

The plan correctly identifies which checks to skip for Reference skills but
does not specify the code-level mechanism. The current `validate_patterns()`
function (lines 200-243 of `validate_skill.py`) iterates all patterns from
the JSON config including Pattern 4 (Verdict Gates, severity: error). There
are three possible approaches:

- (a) Add per-pattern `if` checks inside `validate_patterns()` to skip by ID
  when the skill type is `reference`
- (b) Skip `validate_patterns()`, `validate_steps()`,
  `validate_workflow_header()`, and `validate_inputs_section()` entirely for
  Reference skills and call a dedicated `validate_reference_skill()` instead
- (c) Add `"excluded_archetypes": ["reference"]` to each pattern definition in
  the JSON config

**Recommendation:** Use approach (b). It is the cleanest separation and matches
the plan's implied design (lines 196-200 describe Reference-specific checks as
a distinct set). The Phase 0 task breakdown should explicitly name the new
function and show the `main()` conditional branching. This is not a plan defect
-- it is an implementation detail -- but specifying the mechanism prevents the
implementer from choosing a fragile approach (e.g., approach (a) with
hard-coded pattern IDs).

### M2: deploy.sh `--undeploy` needs nested argument parsing

The current `deploy.sh` uses a flat `case` statement on `$1` (lines 118-150).
The plan proposes `--undeploy <name>` and `--undeploy --contrib <name>`. The
second variant requires three positional arguments (`$1=--undeploy`,
`$2=--contrib`, `$3=<name>`), which the current single-level `case` does not
handle.

This is ~20 lines of bash and not a blocker, but the plan implies it is a
simple flag addition. The implementer should expect to add a nested `case`
or `if` block within the `--undeploy` branch.

### M3: Phase 0 test plan should include negative test cases

The Phase 0 test plan (lines 209-249) validates that a correct Reference skill
passes. It does not include negative test cases:

- A Reference skill with missing `attribution` field (should fail)
- A Reference skill with empty body (should fail)
- A Reference skill with no core principle heading (should fail)
- A Pipeline skill with `type: reference` smuggled in (should this be rejected?)

The acceptance criteria mention some of these (line 255: "exits non-zero for
Reference skills with missing frontmatter or empty body") but the test plan
does not include the corresponding test commands. Adding 3-4 negative fixture
tests to the Phase 0 test plan would increase confidence.

---

## Minor Suggestions (Consider)

### m1: `validate_patterns()` Tool declaration check is harmless for Reference skills

The function checks whether steps have `Tool:` declarations (lines 230-241).
For Reference skills with zero steps, `find_steps()` returns an empty list, so
the loop body never executes and no spurious warning is produced. This is safe
but worth noting for the implementer: if approach (b) from M1 is used, this
is moot since `validate_patterns()` is skipped entirely.

### m2: Consider an `"archetypes"` namespace in skill-patterns.json

The plan shows the `reference` key as a standalone object in the JSON. The
existing file has two top-level keys: `"patterns"` and
`"structural_requirements"`. Adding `"reference"` as a third top-level key
works but does not scale if future archetypes (pipeline, coordinator, scan)
need their own config. Consider:

```json
{
  "patterns": [...],
  "structural_requirements": [...],
  "archetypes": {
    "reference": { ... }
  }
}
```

### m3: `--contrib` flag risk entry is overly cautious

The risk table (line 909) lists "deploy.sh does not support `--contrib` flag"
as Low/High. Examining the actual `deploy.sh`, the `--contrib` flag is already
fully implemented (lines 119-129) with both single-skill and all-contrib modes.
This risk entry can be removed or downgraded to "verified: no risk."

### m4: Behavioral smoke tests should capture evidence

All behavioral tests are manual ("run this prompt in a Claude Code session").
This is acceptable for v1.0.0 but the tests are not reproducible -- Claude
Code's skill matching behavior may vary between sessions. The plan should note
that behavioral test results should be captured as transcript excerpts or
screenshots in the PR description, not just checkbox assertions.

### m5: Content grep test for `superpowers:` is correct but worth documenting why

The test `grep -c "superpowers:" ...` targets the cross-reference syntax
`superpowers:skill-name`, not general mentions of "superpowers." The
`attribution` field contains "superpowers plugin" (no colon after
"superpowers"), so it will not false-positive. This is correct but non-obvious;
a comment in the test plan explaining the pattern target would help future
maintainers.

---

## What Went Well

1. **Round 1 concerns addressed directly.** The revision log explicitly
   references the feasibility findings and each concern has a clear resolution
   with specific design decisions documented.

2. **Conflict resolution analysis is thorough.** The activation domain table,
   multi-activation scenarios, and Iron Law priority ordering (lines 126-156)
   are well-reasoned. The analysis that systematic-debugging precedes TDD
   (investigate before testing) and verification-before-completion activates
   last is correct.

3. **Canary deployment strategy is smart.** Starting with receiving-code-review
   (narrowest trigger scope) before deploying aggressively-triggering skills
   reduces risk. The rationale is explicitly documented (lines 884).

4. **Phase 0 as a hard prerequisite is the right structure.** This prevents
   the Round 1 problem of skills being created before the validator can handle
   them.

5. **Licensing handled correctly.** MIT attribution via frontmatter field
   satisfies the license requirement cleanly.

6. **Size estimates are now grounded in measured data.** The ~20KB estimate
   with explicit comparison to ship's 21KB gives confidence in the context
   window analysis and eliminates the Round 1 guesswork.

7. **Phase independence is genuine.** Confirmed by examining file-level scope:
   each phase creates one SKILL.md and makes additive CLAUDE.md changes.
   No hidden inter-phase dependencies.

---

## Recommendations

1. **(Phase 0)** Specify the validator skip mechanism explicitly -- recommend
   approach (b): conditional branch in `main()` that calls
   `validate_reference_skill()` instead of the workflow-oriented functions.

2. **(Phase 0)** Add 3-4 negative test cases to the test plan (missing
   attribution, empty body, no core principle heading).

3. **(Phase 0)** Structure the `skill-patterns.json` addition under an
   `"archetypes"` key for future extensibility.

4. **(Phase 6)** Remove or downgrade the `--contrib` flag risk entry -- it is
   already implemented and working.

5. **(All phases)** Capture behavioral smoke test results as transcript excerpts
   in PR descriptions.

---

## Verdict

**PASS**

The plan is technically feasible. All three Round 1 concerns are resolved.
The remaining Major items (M1-M3) are implementation-detail refinements that
can be addressed during Phase 0 coding without requiring plan revisions. The
plan provides sufficient guidance for an implementer to proceed with confidence,
starting with Phase 0 as the gating prerequisite.

No blocking issues. Recommend proceeding with Phase 0 implementation.
