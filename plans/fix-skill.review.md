# Librarian Review: `/fix` Skill Plan (Round 2)

**Reviewed:** `plans/fix-skill.md` (Rev 2, 2026-05-23)
**Against:** `CLAUDE.md` (last updated 2026-05-09)
**Reviewer:** Librarian
**Round:** 2 (re-review after revision)
**Date:** 2026-05-23

## Verdict: PASS

All required edits from round 1 are resolved. One minor gap in the task breakdown (CLAUDE.md test count references) is flagged as an optional suggestion -- it does not block because the plan already covers the test file updates and the CLAUDE.md counts are a downstream consequence that `/sync` would catch.

## Round 1 Resolution Status

### Required Edit 1: Move Pattern 5 to deviations table

**Status: RESOLVED**

Pattern 5 ("Timestamped artifacts") has been removed from the "Patterns Followed" table (lines 848-858) and added to the "Deviations with Justification" table (line 877) with justification: "Uses `fix-[finding-id]-[timestamp]` naming instead of pure ISO timestamp naming. Finding-ID provides semantic traceability to the source finding. Timestamp suffix prevents naming collisions across multiple invocations for the same finding. Artifacts are short-lived (archived in Step 4b)."

The deviation entry is honest and well-justified. The hybrid naming (`fix-[finding-id]-[timestamp]`) is a reasonable compromise that provides both semantic traceability (finding-ID) and temporal uniqueness (timestamp).

### Required Edit 2: Address artifact naming collision risk

**Status: RESOLVED**

The plan chose option (a) -- adding a timestamp suffix to artifact names. This is reflected in:

- **Revision log** (line 9): "(5) Add timestamp suffix to artifact names to prevent collision (librarian req 2)."
- **Artifact Naming Convention section** (lines 599-607): Explicit statement that artifacts include a `[timestamp]` suffix (ISO 8601 compact). The table shows names like `fix-[finding-id]-[timestamp]-reverify.secure-review.md` and `fix-[finding-id]-[timestamp].code-review.md`.
- **Workflow steps 3a and 3b** (lines 370, 382, 421): Consistently use the timestamped naming convention throughout the workflow.

The naming collision risk is fully resolved. Multiple invocations for the same finding will produce distinct artifact names.

## New Conflicts

None found. The revised plan is consistent with CLAUDE.md.

Specific checks performed:
- **Skill Registry table format** matches the existing table structure (Skill, Version, Purpose, Model, Steps columns).
- **Pipeline archetype** classification is consistent with CLAUDE.md's archetype documentation (sequential execution, checkpoints, commit gate).
- **Frontmatter format** (`name`, `description`, `model`, `version`) matches the documented format at CLAUDE.md line 824-831. Single-line description is correct per feasibility M-01.
- **Em-dash step headers** (`## Step N -- [Action]`) are consistent with the CLAUDE.md pattern spec (which uses double hyphens, not em-dashes -- but the plan's revision log says "Change all step headers to em-dashes" per feasibility M-02, matching deployed skill convention). No conflict.
- **`plans/archive/fix/`** archive path follows the existing pattern (`plans/archive/<skill>/`).
- **Rollback section** references `rm -rf ~/.claude/skills/fix/`. Note: `deploy.sh` does support `--undeploy fix` (lines 151, 200 of deploy.sh), which is the preferred method. Not a conflict -- either approach works.

## Required Edits

None.

## Optional Suggestions

1. **CLAUDE.md test count references are incomplete in the task breakdown.** The plan correctly identifies updating test counts in the test files themselves (`generators/test_skill_generator.sh` header from "up to 56" to "up to 57"; `scripts/test-integration.sh` header from "26 tests" to "28 tests"). However, CLAUDE.md also references these counts in three additional locations that should be updated during implementation:
   - Line 867: `test_skill_generator.sh -- Test suite (46 tests)` -- should become "47 tests"
   - Line 1065: `Coverage (46 tests):` -- should become "47 tests"
   - Line 914 and 71: `test-integration.sh -- Integration smoke tests (26 tests)` -- should become "28 tests"
   - Line 1225: `Test suite (46 tests, all 12 core` -- should become "47 tests, all 13 core"

   These are covered implicitly by the plan's CLAUDE.md update task ("Update skill count references") but are not enumerated in the task breakdown. The implementer should catch these, and `/sync` would flag them afterward if missed. Not blocking.

2. **Rollback could use `--undeploy`.** The rollback section says `rm -rf ~/.claude/skills/fix/`. Since `deploy.sh` supports `--undeploy fix` (confirmed in deploy.sh lines 151-204), the rollback instructions could use the canonical command instead. Not blocking -- either works.
