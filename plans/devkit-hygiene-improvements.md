# Plan: Devkit Hygiene Improvements -- Test Coverage, Bug Fix, Smoke Tests, and Documentation

## Revision Log

| Rev | Date | Trigger | Summary |
|-----|------|---------|---------|
| 1 | 2026-03-27 | Initial draft | Four improvements from portfolio review: deploy.sh --validate tests, settings precedence fix, integration test framework, archetype decision guide |
| 2 | 2026-03-27 | Red team, librarian, feasibility reviews | Fixed test count (44 actual, not 46). Added trap handlers for source-tree cleanup. Replaced duplicate integration tests 3-4 with unique smoke tests. Added numbering origin note. Added CLAUDE.md normalization note. Added variable name clarifying comments. |

## Context

The agentic-sdlc-next-phase plan shipped quality infrastructure (expanded test suite, validate-all.sh, deploy.sh --validate flag, generate_agents.py exit code fix). A portfolio review identified four remaining hygiene improvements:

1. The `--validate` flag in `deploy.sh` has zero automated test coverage, despite a project learning (#2026-03-27) explicitly calling out this gap.
2. The settings precedence logic in `skills/ship/SKILL.md` has a known bug where explicitly setting `"advisory"` in local settings gets overridden by project settings.
3. No test verifies that a skill actually runs end-to-end -- only structural validation exists.
4. The three skill archetypes (coordinator, pipeline, scan) lack a standalone decision guide for new skill authors.

These are independent, low-risk improvements that close specific gaps identified in `.claude/learnings.md` and the portfolio review.

**Numbering note:** The improvement numbers (#4, #5, #7, #8) in the Proposed Design section are inherited from the portfolio review where items #1-#3 and #6 were addressed in the agentic-sdlc-next-phase plan. The Goals section uses 1-4 for readability within this plan.

**Current state (confirmed):**
- Test suite: 44 tests at runtime in `generators/test_skill_generator.sh`. The header comment says "46 test cases" but test numbers 26, 33, and 35 are skipped (never created or since removed), and Test 27b uses a string label. The `TOTAL_COUNT` at runtime is 44. Conditional contrib tests (43-45) may further reduce the count on machines without contrib skills.
- `deploy.sh`: Has `--validate` flag with pre-processing loop, applies to both `deploy_skill()` and `deploy_contrib_skill()`
- `skills/ship/SKILL.md`: v3.5.0, bug at lines 93-106
- `scripts/validate-all.sh`: Exists and functional
- No integration/smoke test script exists

## Goals

1. **Close the `--validate` test gap** -- Add automated tests proving the `--validate` flag works (positive path), blocks invalid skills (negative path), and works with `--contrib` (combination path). Addresses the learning at `.claude/learnings.md` line 42.

2. **Fix the settings precedence bug** -- Ensure that when `.claude/settings.local.json` explicitly sets `security_maturity` to `"advisory"`, the project-level setting in `.claude/settings.json` does not override it. The fix: track whether the local source provided a value with a `LOCAL_SET` boolean flag, independent of what that value is.

3. **Create a smoke-test framework** -- Provide a lightweight `scripts/test-integration.sh` script that exercises live end-to-end paths (generate skill, deploy it, validate-all, full lifecycle). These are smoke tests, not behavioral LLM tests.

4. **Create an archetype decision guide** -- Provide a standalone `generators/ARCHETYPE_GUIDE.md` document with a decision tree, comparison table, and examples to help authors choose between coordinator, pipeline, and scan archetypes.

## Non-Goals

- Behavioral testing of LLM skill execution (cannot test Claude's response to a skill prompt in CI)
- Modifying any skill other than `skills/ship/SKILL.md` (the bug fix)
- CI/CD pipeline integration (deferred to v1.2 per CLAUDE.md roadmap)
- Changes to the skill generator, validator, or agent generator
- Renumbering existing tests (only appending new ones)
- Adding smoke tests for every skill (start with infrastructure paths)

## Assumptions

1. The test suite currently passes at 44 runtime tests (confirmed; header says 46 but numbers 26, 33, 35 are skipped and 27b is a string label)
2. `deploy.sh --validate` flag is functional but untested (confirmed from file read -- the `VALIDATE` pre-processing loop and both `deploy_skill()`/`deploy_contrib_skill()` guards exist)
3. At least one contrib skill exists at `contrib/journal/SKILL.md` (used in combination test)
4. Python 3 and `validate_skill.py` are available on the test machine
5. The cleanup test is currently Test 46 (the last test) and will need to be renumbered when new tests are inserted before it

## Proposed Design

### Improvement #4: deploy.sh --validate Flag Tests

**What:** Add 3 new test cases to `generators/test_skill_generator.sh` that exercise the `--validate` flag.

**Where:** Insert after Test 42 (validate compliance-check skill) and before the contrib skill tests (Test 43). This groups the deploy validation tests near the existing deploy tests (31-32) logically, but places them after all core skill validation tests since they depend on those skills being structurally valid.

Actually, a better placement: insert after the contrib skill tests (Test 43-45) and before the cleanup test (Test 46). This avoids disrupting the existing test numbering and places new tests at the natural extension point. The new tests will be numbered 47, 48, 49, and cleanup moves to Test 50.

**Tests:**

**Test 47 (Positive):** Deploy a valid core skill with `--validate` and verify it succeeds.
```bash
# Deploy architect skill with validation -- should succeed
run_test 47 "Deploy with --validate (valid skill)" \
    "bash '$DEPLOY_SCRIPT' --validate architect" \
    0
```

**Test 48 (Negative):** Create an intentionally invalid skill in the test directory, attempt `deploy.sh --validate` on it, and verify deployment is blocked.
```bash
# Create an invalid skill (missing required frontmatter fields)
mkdir -p "$TEST_DIR/skills/test-invalid-deploy"
echo "# No frontmatter, no steps" > "$TEST_DIR/skills/test-invalid-deploy/SKILL.md"

# Point deploy.sh at the test directory's skills -- but deploy.sh uses REPO_DIR/skills,
# so we need a different approach: use a modified SKILLS_DIR or test in-place.
#
# Approach: temporarily create an invalid skill in the real skills/ directory,
# test that --validate blocks it, then clean up. This is risky because it
# modifies the source tree during tests.
#
# Safer approach: create a standalone test that directly invokes the validation
# logic. Since deploy_skill() calls validate_skill.py on the SKILL.md and
# returns 1 on failure, we can test the deploy script by passing a skill name
# that points to an invalid file.
#
# Safest approach: create a temporary skill directory in the real skills/ dir,
# verify --validate blocks it, then remove it. The test harness already creates
# test fixtures in /tmp and cleans up.
```

After analysis, the safest approach for the negative test: create a temporary invalid skill directory inside the real `skills/` directory (e.g., `skills/test-validate-invalid/`), run `deploy.sh --validate test-validate-invalid`, verify it returns non-zero, then remove the temporary directory. A `trap` handler at the script level ensures cleanup even on interruption.

```bash
# Create invalid skill in real skills/ directory for testing
# Note: $SKILLS_DIR resolves to the repo root (parent of generators/)
mkdir -p "$SKILLS_DIR/skills/test-validate-invalid"
echo "# No frontmatter" > "$SKILLS_DIR/skills/test-validate-invalid/SKILL.md"

run_test 48 "Deploy with --validate blocks invalid skill" \
    "bash '$DEPLOY_SCRIPT' --validate test-validate-invalid" \
    non-zero

# Clean up the temporary skill directory
rm -rf "$SKILLS_DIR/skills/test-validate-invalid"
```

**Test 49 (Combination):** Deploy a valid contrib skill with `--validate --contrib` and verify it succeeds.
```bash
# Test --validate with --contrib (if journal contrib exists)
if [[ -f "$SKILLS_DIR/contrib/journal/SKILL.md" ]]; then
    run_test 49 "Deploy with --validate --contrib (valid skill)" \
        "bash '$DEPLOY_SCRIPT' --validate --contrib journal" \
        0
else
    echo -e "${YELLOW}  Test 49: SKIP (journal contrib skill not found)${RESET}"
fi
```

**Cleanup renumber:** Test 46 (currently cleanup) renumbered to Test 50.

**Total test count after expansion:** Up to 47 runtime tests (44 existing + 3 new deploy-validate tests; Test 49 is conditional). The header comment will be updated to document the actual test inventory including numbering gaps. Cleanup test renumbered to 50.

**Trap handler addition:** A `trap` handler will be added near the top of `test_skill_generator.sh` to clean up known temporary directories (`skills/test-validate-invalid/`) on EXIT, INT, and TERM signals. This ensures interrupted tests do not leave stale directories that would break `deploy_all_core()` or `validate-all.sh`.

```bash
# Trap handler for cleanup on interruption (prevents stale test fixtures in skills/)
cleanup_on_exit() {
    rm -rf "$SKILLS_DIR/skills/test-validate-invalid" 2>/dev/null || true
}
trap cleanup_on_exit EXIT INT TERM
```

### Improvement #5: Settings Precedence Fix

**What:** Replace the value-based fallback check on line 103 of `skills/ship/SKILL.md` with a source-tracking boolean.

**Current code (lines 93-106):**
```bash
SECURITY_MATURITY="advisory"  # Default: L1

# Read local settings first (takes precedence)
if [ -f ".claude/settings.local.json" ]; then
  LOCAL_MATURITY=$(python3 -c "import json; d=json.load(open('.claude/settings.local.json')); print(d.get('security_maturity',''))" 2>/dev/null || echo "")
  [ -n "$LOCAL_MATURITY" ] && SECURITY_MATURITY="$LOCAL_MATURITY"
fi

# Fall back to project settings
if [ "$SECURITY_MATURITY" = "advisory" ] && [ -f ".claude/settings.json" ]; then
  PROJECT_MATURITY=$(python3 -c "import json; d=json.load(open('.claude/settings.json')); print(d.get('security_maturity',''))" 2>/dev/null || echo "")
  [ -n "$PROJECT_MATURITY" ] && SECURITY_MATURITY="$PROJECT_MATURITY"
fi
```

**Bug:** Line 103 checks `if [ "$SECURITY_MATURITY" = "advisory" ]`. If the user explicitly sets `security_maturity: "advisory"` in `.claude/settings.local.json`, the condition is true and the code falls through to read project settings. If the project sets `"enforced"`, the project setting wins -- violating the documented "local overrides project" precedence.

**Fixed code:**
```bash
SECURITY_MATURITY="advisory"  # Default: L1
LOCAL_SET=0  # Track source, not value, to preserve precedence when local sets "advisory"

# Read local settings first (takes precedence)
if [ -f ".claude/settings.local.json" ]; then
  LOCAL_MATURITY=$(python3 -c "import json; d=json.load(open('.claude/settings.local.json')); print(d.get('security_maturity',''))" 2>/dev/null || echo "")
  if [ -n "$LOCAL_MATURITY" ]; then
    SECURITY_MATURITY="$LOCAL_MATURITY"
    LOCAL_SET=1
  fi
fi

# Only fall back to project settings if local did NOT provide a value
if [ "$LOCAL_SET" -eq 0 ] && [ -f ".claude/settings.json" ]; then
  PROJECT_MATURITY=$(python3 -c "import json; d=json.load(open('.claude/settings.json')); print(d.get('security_maturity',''))" 2>/dev/null || echo "")
  [ -n "$PROJECT_MATURITY" ] && SECURITY_MATURITY="$PROJECT_MATURITY"
fi
```

**Also update the prose** above the code block (line 89) to make the precedence model explicit:

Current: "Read `.claude/settings.local.json` (if exists), then `.claude/settings.json` (if exists). Extract the `security_maturity` field. Local settings override project settings."

Updated: "Read `.claude/settings.local.json` (if exists), then `.claude/settings.json` (if exists). Extract the `security_maturity` field. Precedence: if `.claude/settings.local.json` provides a `security_maturity` value (even if that value is `"advisory"`), the project-level setting is not consulted. The fallback to `.claude/settings.json` only occurs when the local file is absent or does not contain the `security_maturity` key."

### Improvement #7: Integration Test Framework

**What:** Create `scripts/test-integration.sh` -- a lightweight smoke-test script that exercises live end-to-end paths.

**Design principles:**
- Reuse the same `run_test()` harness pattern from `test_skill_generator.sh`
- Test infrastructure paths (generate, validate, deploy), not LLM execution
- Clean up all artifacts after tests, with a `trap` handler as a safety net
- Exit 0 on all pass, 1 on any failure
- Self-contained -- does not depend on `test_skill_generator.sh`

**Tests:**

**Test 1: Generate and deploy a coordinator skill, verify deployment.**
```bash
# Generate a coordinator skill into /tmp
python3 "$GENERATE_PY" smoke-coord -d "Smoke test." -a coordinator -t "$TEST_DIR" --force
# Deploy it (temporarily copy to ~/.claude/skills/)
mkdir -p "$DEPLOY_DIR/smoke-coord"
cp "$TEST_DIR/skills/smoke-coord/SKILL.md" "$DEPLOY_DIR/smoke-coord/SKILL.md"
# Verify it exists
[ -f "$DEPLOY_DIR/smoke-coord/SKILL.md" ]
# Clean up
rm -rf "$DEPLOY_DIR/smoke-coord"
```

**Test 2: Run validate-all.sh and verify exit code 0.**
```bash
bash "$REPO_DIR/scripts/validate-all.sh"
```

**Test 3: Generate a pipeline skill, validate it, deploy it, undeploy it (full lifecycle).**
```bash
# Generate a pipeline skill
python3 "$GENERATE_PY" smoke-pipe -d "Smoke test pipeline." -a pipeline -t "$TEST_DIR" --force
# Validate it
python3 "$REPO_DIR/generators/validate_skill.py" "$TEST_DIR/skills/smoke-pipe/SKILL.md"
# Deploy it
mkdir -p "$DEPLOY_DIR/smoke-pipe"
cp "$TEST_DIR/skills/smoke-pipe/SKILL.md" "$DEPLOY_DIR/smoke-pipe/SKILL.md"
# Verify deployment
[ -f "$DEPLOY_DIR/smoke-pipe/SKILL.md" ]
# Undeploy
rm -rf "$DEPLOY_DIR/smoke-pipe"
# Verify removal
[ ! -d "$DEPLOY_DIR/smoke-pipe" ]
```

**Test 4: Run the unit test suite and verify it passes (meta-test).**
```bash
bash "$REPO_DIR/generators/test_skill_generator.sh"
```

**Test 5: Cleanup all smoke test artifacts.**
```bash
rm -rf "$TEST_DIR"
rm -rf "$DEPLOY_DIR/smoke-coord"
rm -rf "$DEPLOY_DIR/smoke-pipe"
```

**Note on Tests 3-4:** Rev 1 had Tests 3-4 as `deploy.sh --validate` positive and negative tests, which duplicated WG-1 Tests 47-48 exactly. Rev 2 replaces them with genuinely different smoke tests: a full generate-validate-deploy-undeploy lifecycle (Test 3) and a meta-test that runs the unit suite from within the integration test (Test 4). The `deploy.sh --validate` coverage is handled solely by WG-1.

### Improvement #8: Archetype Decision Guide

**What:** Create `generators/ARCHETYPE_GUIDE.md` with a decision tree, comparison table, and examples.

**Structure:**
1. **Introduction** -- What archetypes are and why they matter
2. **Decision Tree** -- Text-based flowchart: "Does your workflow delegate to multiple agents?" -> Yes -> Coordinator; "Does your workflow run sequential stages with gates?" -> Yes -> Pipeline; "Does your workflow analyze something and produce a severity-rated report?" -> Yes -> Scan
3. **Comparison Table** -- Side-by-side of all three archetypes across dimensions: control flow, parallelism, verdict gates, revision loops, artifact pattern, typical step count
4. **Archetype Details** -- For each archetype:
   - When to use (and when NOT to use)
   - Structural requirements
   - Example skills that use it
   - Template reference
5. **Reference Archetype** -- Brief note on the reference archetype (non-executable skills like `receiving-code-review` and `verification-before-completion`)
6. **Cross-references** -- Links to templates, CLAUDE.md patterns, and the skill generator

**Content sources:**
- CLAUDE.md "Archetype Patterns" section (coordinator, pipeline, scan examples)
- `templates/skill-coordinator.md.template`, `templates/skill-pipeline.md.template`, `templates/skill-scan.md.template`
- Existing skills as examples: `/architect` (coordinator), `/ship` (pipeline), `/audit` (scan)

## Interfaces / Schema Changes

### Script Interface Changes

| Script | Change | Type |
|--------|--------|------|
| `generators/test_skill_generator.sh` | Add tests 47-49 for `--validate` flag, add trap handler, renumber cleanup to Test 50 | Additive (existing tests unchanged except cleanup renumber) |
| `scripts/test-integration.sh` | New script | New file |

### Skill Changes

| Skill | Change | Type |
|-------|--------|------|
| `skills/ship/SKILL.md` | Fix settings precedence logic at lines 93-106 | Bug fix (behavioral correction) |

### Documentation Changes

| File | Change | Type |
|------|--------|------|
| `generators/ARCHETYPE_GUIDE.md` | New file | New documentation |

### No Changes To

- `scripts/deploy.sh` (already has `--validate` flag implemented)
- `scripts/validate-all.sh` (no changes needed)
- `generators/validate_skill.py` (no changes needed)
- `generators/generate_skill.py` (no changes needed)
- `CLAUDE.md` (registry updates deferred until all 4 improvements ship; the three test count references -- currently showing 46 and 45 inconsistently -- must be normalized to the correct post-expansion count in a follow-up `/sync` pass)

## Data Migration

No data migration required. All changes are additive or in-place fixes.

## Rollout Plan

The four improvements are independent and can be implemented in any order. The recommended sequence minimizes risk by doing the bug fix first (smallest blast radius), then test additions (which validate existing infrastructure), then new files:

### Step 1: Settings Precedence Fix (WG-2)

**Scope:** 1 modified file (`skills/ship/SKILL.md`)
**Risk:** Low (changes 8 lines in an embedded code block; behavior correction, not feature change)
**Rollback:** `git checkout HEAD~1 -- skills/ship/SKILL.md`
**Verify:** Read the fixed code block and confirm `LOCAL_SET` boolean gates the fallback

### Step 2: deploy.sh --validate Tests (WG-1)

**Scope:** 1 modified file (`generators/test_skill_generator.sh`)
**Risk:** Low (additive tests only; existing tests unchanged except cleanup renumber; trap handler ensures cleanup on interruption)
**Rollback:** `git checkout HEAD~1 -- generators/test_skill_generator.sh`
**Verify:** `bash generators/test_skill_generator.sh` -- all tests pass, no stale directories remain

### Step 3: Integration Test Framework (WG-3)

**Scope:** 1 new file (`scripts/test-integration.sh`)
**Risk:** Low (new script; creates/cleans up temp artifacts; trap handler ensures cleanup; does not modify source tree)
**Rollback:** `rm scripts/test-integration.sh`
**Verify:** `bash scripts/test-integration.sh` -- all 5 tests pass

### Step 4: Archetype Decision Guide (WG-4)

**Scope:** 1 new file (`generators/ARCHETYPE_GUIDE.md`)
**Risk:** None (documentation only)
**Rollback:** `rm generators/ARCHETYPE_GUIDE.md`
**Verify:** File exists and contains decision tree, comparison table, and examples

All four steps can be committed together or individually.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Test 48 (negative --validate test) leaves stale `skills/test-validate-invalid/` directory on test failure or interruption | Low | Medium | Add `trap cleanup_on_exit EXIT INT TERM` handler at script top that removes `skills/test-validate-invalid/`. Also add explicit `rm -rf` after the test (belt-and-suspenders). The cleanup test (Test 50) provides a third layer. |
| Integration test creates temporary skill artifacts during execution | Low | Low | Trap handler at script top removes all smoke artifacts on EXIT/INT/TERM. No source-tree modifications in integration tests (Rev 2 removed the `skills/smoke-invalid/` test). |
| ship SKILL.md fix has no automated test | Low | Medium | The fix is a 3-line logic change in an embedded code block. It is verified by code review. A behavioral test would require mocking `.claude/settings.local.json` and running the /ship skill, which is out of scope (see Non-Goals). The fix addresses a documented learning entry, so the next /retro run can verify it is addressed. |
| Archetype guide becomes stale when new archetypes are added | Low | Low | Cross-reference CLAUDE.md as the authoritative source. The guide is a decision aid, not a specification. |
| Test 49 (--validate --contrib) skips on machines without contrib skills | Medium | Low | The test uses conditional skip (consistent with existing Tests 43-45). The positive and negative tests (47, 48) are unconditional and provide primary coverage. |

## Test Plan

### Exact Test Commands

```bash
# Run expanded unit test suite (WG-1 verification)
cd /Users/imurphy/projects/claude-devkit && bash generators/test_skill_generator.sh

# Run integration smoke tests (WG-3 verification)
cd /Users/imurphy/projects/claude-devkit && bash scripts/test-integration.sh

# Verify ship SKILL.md validates after fix (WG-2 verification)
cd /Users/imurphy/projects/claude-devkit && python3 generators/validate_skill.py skills/ship/SKILL.md

# Verify all skills still validate (regression check)
cd /Users/imurphy/projects/claude-devkit && bash scripts/validate-all.sh
```

### Manual Verification

1. **Settings precedence fix:** Read `skills/ship/SKILL.md` lines 93-116 and confirm:
   - `LOCAL_SET=0` is initialized before the local settings block
   - `LOCAL_SET=1` is set inside the `if [ -n "$LOCAL_MATURITY" ]` block
   - The fallback condition uses `[ "$LOCAL_SET" -eq 0 ]` instead of `[ "$SECURITY_MATURITY" = "advisory" ]`
   - The prose above the code block documents the precedence model explicitly

2. **deploy.sh --validate tests:** Run test suite. Verify:
   - Test 47 passes (valid skill with --validate)
   - Test 48 passes (invalid skill blocked by --validate)
   - Test 49 passes or skips (--validate --contrib)
   - Test 50 passes (cleanup)
   - No stale `skills/test-validate-invalid/` directory remains after test completion or interruption

3. **Integration smoke tests:** Run `bash scripts/test-integration.sh`. Verify:
   - All 5 tests pass
   - No artifacts remain in `~/.claude/skills/smoke-*`
   - Script exits 0

4. **Archetype guide:** Verify `generators/ARCHETYPE_GUIDE.md` contains:
   - Decision tree with at least 3 decision points
   - Comparison table with coordinator, pipeline, scan columns
   - At least one example skill per archetype
   - Cross-references to templates

## Acceptance Criteria

### WG-1: deploy.sh --validate Tests

- [ ] Trap handler added near script top: `trap cleanup_on_exit EXIT INT TERM` with function that removes `skills/test-validate-invalid/`
- [ ] Test 47 exists: deploys a valid core skill with `--validate` and expects exit 0
- [ ] Test 48 exists: creates an intentionally invalid skill, runs `deploy.sh --validate`, and expects non-zero exit
- [ ] Test 48 cleans up the temporary invalid skill directory after the test (plus trap handler as backup)
- [ ] Test 49 exists: deploys a valid contrib skill with `--validate --contrib` (conditional on contrib existence)
- [ ] Cleanup test renumbered from 46 to 50
- [ ] Test suite header comment updated to reflect accurate test inventory (documenting numbering gaps at 26, 33, 35 and string label 27b)
- [ ] `bash generators/test_skill_generator.sh` passes with 0 failures

### WG-2: Settings Precedence Fix

- [ ] `LOCAL_SET=0` initialized at line 95 (after `SECURITY_MATURITY="advisory"`)
- [ ] Inline comment on `LOCAL_SET=0` explaining the purpose: `# Track source, not value, to preserve precedence when local sets "advisory"`
- [ ] `LOCAL_SET=1` set inside the local settings block when a value is found
- [ ] Fallback condition on the project settings block uses `[ "$LOCAL_SET" -eq 0 ]` instead of `[ "$SECURITY_MATURITY" = "advisory" ]`
- [ ] Prose explanation above the code block explicitly documents the precedence: "if local provides a value (even advisory), project is not consulted"
- [ ] `python3 generators/validate_skill.py skills/ship/SKILL.md` exits 0 (ship skill still validates)
- [ ] No other lines in `skills/ship/SKILL.md` are modified

### WG-3: Integration Test Framework

- [ ] `scripts/test-integration.sh` exists and is executable
- [ ] Trap handler added at script top: `trap cleanup EXIT INT TERM` with function that removes all smoke artifacts
- [ ] Uses the same `run_test()` harness pattern as `test_skill_generator.sh`
- [ ] Test 1: generates a coordinator skill, deploys it to `~/.claude/skills/`, verifies the file exists, cleans up
- [ ] Test 2: runs `validate-all.sh` and expects exit 0
- [ ] Test 3: generates a pipeline skill, validates it, deploys it, verifies deployment, undeploys it, verifies removal (full lifecycle)
- [ ] Test 4: runs the unit test suite (`test_skill_generator.sh`) and expects exit 0 (meta-test)
- [ ] Test 5: cleanup removes all smoke test artifacts
- [ ] No tests modify the source tree (no temporary skills created in `skills/`)
- [ ] `bash scripts/test-integration.sh` passes with 0 failures
- [ ] No artifacts remain after the script completes

### WG-4: Archetype Decision Guide

- [ ] `generators/ARCHETYPE_GUIDE.md` exists
- [ ] Contains a decision tree (text-based flowchart or structured questions) with at least 3 decision points
- [ ] Contains a comparison table with columns for coordinator, pipeline, and scan
- [ ] Contains at least one example skill per archetype (architect for coordinator, ship for pipeline, audit for scan)
- [ ] Cross-references `templates/skill-coordinator.md.template`, `templates/skill-pipeline.md.template`, `templates/skill-scan.md.template`
- [ ] Mentions the reference archetype briefly
- [ ] Cross-references `CLAUDE.md` as the authoritative source for pattern specifications

## Task Breakdown

### Files to Create

| # | File | Purpose | Work Group |
|---|------|---------|------------|
| 1 | `scripts/test-integration.sh` | Smoke-test framework for live skill execution paths | WG-3 |
| 2 | `generators/ARCHETYPE_GUIDE.md` | Decision guide for choosing between coordinator, pipeline, and scan archetypes | WG-4 |

### Files to Modify

| # | File | Change | Work Group |
|---|------|--------|------------|
| 3 | `generators/test_skill_generator.sh` | Add trap handler, add tests 47-49 for `--validate` flag, renumber cleanup to Test 50 | WG-1 |
| 4 | `skills/ship/SKILL.md` | Fix settings precedence logic (lines 93-106): replace value-based check with `LOCAL_SET` boolean | WG-2 |

## Work Groups

### Work Group 1: deploy.sh --validate Tests

**Files:** `generators/test_skill_generator.sh`

**Tasks:**
1. [ ] Read `generators/test_skill_generator.sh`
2. [ ] Add a trap handler near the top of the script (after variable definitions, before first test):
   ```bash
   # Trap handler: clean up temporary test fixtures on interruption
   # Prevents stale directories in skills/ that would break deploy_all_core() and validate-all.sh
   cleanup_on_exit() {
       rm -rf "$SKILLS_DIR/skills/test-validate-invalid" 2>/dev/null || true
   }
   trap cleanup_on_exit EXIT INT TERM
   ```
3. [ ] After Test 45 (validate journal-review contrib skill) and before the current Test 46 (cleanup), insert:
   - **Test 47:** Positive test -- `bash '$DEPLOY_SCRIPT' --validate architect` expects exit 0
   - **Test 48:** Negative test -- create `$SKILLS_DIR/skills/test-validate-invalid/SKILL.md` with `# No frontmatter`, run `bash '$DEPLOY_SCRIPT' --validate test-validate-invalid` expecting non-zero, then `rm -rf "$SKILLS_DIR/skills/test-validate-invalid"` (note: `$SKILLS_DIR` resolves to the repo root, which is the parent of `generators/`)
   - **Test 49:** Combination test -- if `$SKILLS_DIR/contrib/journal/SKILL.md` exists, run `bash '$DEPLOY_SCRIPT' --validate --contrib journal` expecting exit 0; else skip
4. [ ] Renumber Test 46 (cleanup) to **Test 50**
5. [ ] Update the header comment to accurately document the test inventory, noting the numbering gaps (26, 33, 35 skipped; 27b is a string label) and the actual runtime count
6. [ ] Run: `bash generators/test_skill_generator.sh` -- verify all tests pass

**Exact code to insert** (before the current "Test 46: Cleanup" block):

```bash
# --- Deploy validation tests ---

# Test 47: Deploy with --validate (valid skill)
run_test 47 "Deploy with --validate (valid skill)" \
    "bash '$DEPLOY_SCRIPT' --validate architect" \
    0

# Test 48: Deploy with --validate blocks invalid skill
# Note: $SKILLS_DIR resolves to the repo root (parent of generators/)
mkdir -p "$SKILLS_DIR/skills/test-validate-invalid"
echo "# No frontmatter" > "$SKILLS_DIR/skills/test-validate-invalid/SKILL.md"
run_test 48 "Deploy with --validate blocks invalid skill" \
    "bash '$DEPLOY_SCRIPT' --validate test-validate-invalid" \
    non-zero
rm -rf "$SKILLS_DIR/skills/test-validate-invalid"

# Test 49: Deploy with --validate --contrib (valid contrib skill)
if [[ -f "$SKILLS_DIR/contrib/journal/SKILL.md" ]]; then
    run_test 49 "Deploy with --validate --contrib (valid skill)" \
        "bash '$DEPLOY_SCRIPT' --validate --contrib journal" \
        0
else
    echo -e "${YELLOW}  Test 49: SKIP (journal contrib skill not found)${RESET}"
fi
```

### Work Group 2: Settings Precedence Fix

**Files:** `skills/ship/SKILL.md`

**Tasks:**
1. [ ] Read `skills/ship/SKILL.md` lines 85-116
2. [ ] Replace lines 89-106 with the fixed version:

**Prose replacement (line 89):**

Old:
```
Read `.claude/settings.local.json` (if exists), then `.claude/settings.json` (if exists). Extract the `security_maturity` field. Local settings override project settings.
```

New:
```
Read `.claude/settings.local.json` (if exists), then `.claude/settings.json` (if exists). Extract the `security_maturity` field. Precedence: if `.claude/settings.local.json` provides a `security_maturity` value (even if that value is `"advisory"`), the project-level setting is not consulted. The fallback to `.claude/settings.json` only occurs when the local file is absent or does not contain the `security_maturity` key.
```

**Code block replacement (lines 93-106):**

Old:
```bash
SECURITY_MATURITY="advisory"  # Default: L1

# Read local settings first (takes precedence)
if [ -f ".claude/settings.local.json" ]; then
  LOCAL_MATURITY=$(python3 -c "import json; d=json.load(open('.claude/settings.local.json')); print(d.get('security_maturity',''))" 2>/dev/null || echo "")
  [ -n "$LOCAL_MATURITY" ] && SECURITY_MATURITY="$LOCAL_MATURITY"
fi

# Fall back to project settings
if [ "$SECURITY_MATURITY" = "advisory" ] && [ -f ".claude/settings.json" ]; then
  PROJECT_MATURITY=$(python3 -c "import json; d=json.load(open('.claude/settings.json')); print(d.get('security_maturity',''))" 2>/dev/null || echo "")
  [ -n "$PROJECT_MATURITY" ] && SECURITY_MATURITY="$PROJECT_MATURITY"
fi
```

New:
```bash
SECURITY_MATURITY="advisory"  # Default: L1
LOCAL_SET=0  # Track source, not value, to preserve precedence when local sets "advisory"

# Read local settings first (takes precedence)
if [ -f ".claude/settings.local.json" ]; then
  LOCAL_MATURITY=$(python3 -c "import json; d=json.load(open('.claude/settings.local.json')); print(d.get('security_maturity',''))" 2>/dev/null || echo "")
  if [ -n "$LOCAL_MATURITY" ]; then
    SECURITY_MATURITY="$LOCAL_MATURITY"
    LOCAL_SET=1
  fi
fi

# Only fall back to project settings if local did NOT provide a value
if [ "$LOCAL_SET" -eq 0 ] && [ -f ".claude/settings.json" ]; then
  PROJECT_MATURITY=$(python3 -c "import json; d=json.load(open('.claude/settings.json')); print(d.get('security_maturity',''))" 2>/dev/null || echo "")
  [ -n "$PROJECT_MATURITY" ] && SECURITY_MATURITY="$PROJECT_MATURITY"
fi
```

3. [ ] Verify no other lines in `skills/ship/SKILL.md` are modified
4. [ ] Run: `python3 generators/validate_skill.py skills/ship/SKILL.md` -- verify exit 0

### Work Group 3: Integration Test Framework

**Files:** `scripts/test-integration.sh` (new)

**Tasks:**
1. [ ] Create `scripts/test-integration.sh` with the following content:

```bash
#!/usr/bin/env bash
#
# Integration smoke tests for claude-devkit
# Tests live end-to-end paths: generate -> validate -> deploy -> undeploy
#
# Usage:
#   bash scripts/test-integration.sh
#
# These are smoke tests that verify infrastructure paths work.
# They do NOT test LLM skill execution (which requires an active Claude session).
#
# 5 tests: coordinator lifecycle, validate-all, pipeline lifecycle, unit meta-test, cleanup

set -e

# Colors
RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
BLUE='\033[94m'
RESET='\033[0m'

# Counters
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"  # Repo root (parent of scripts/)
GENERATE_PY="$REPO_DIR/generators/generate_skill.py"
VALIDATE_PY="$REPO_DIR/generators/validate_skill.py"
DEPLOY_DIR="$HOME/.claude/skills"
TEST_DIR="/tmp/integration-smoke-test"

# Trap handler: clean up all smoke artifacts on exit/interruption
cleanup() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
    rm -rf "$DEPLOY_DIR/smoke-coord" 2>/dev/null || true
    rm -rf "$DEPLOY_DIR/smoke-pipe" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Clean up test directory at start
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Test runner function (same pattern as test_skill_generator.sh)
run_test() {
    local test_num="$1"
    local test_name="$2"
    local test_command="$3"
    local expected_exit="$4"

    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    echo ""
    echo -e "${BLUE}Test $test_num: $test_name${RESET}"

    set +e
    eval "$test_command" > /dev/null 2>&1
    actual_exit=$?
    set -e

    if [[ "$expected_exit" == "0" && $actual_exit -eq 0 ]]; then
        echo -e "${GREEN}  PASS${RESET}"
        PASS_COUNT=$((PASS_COUNT + 1))
    elif [[ "$expected_exit" != "0" && $actual_exit -ne 0 ]]; then
        echo -e "${GREEN}  PASS${RESET}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}  FAIL (expected exit $expected_exit, got $actual_exit)${RESET}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo "========================================"
echo "Claude Devkit Integration Smoke Tests"
echo "========================================"

# Test 1: Generate a coordinator skill, deploy it, verify deployment
run_test 1 "Generate, deploy, and verify a coordinator skill" \
    "python3 '$GENERATE_PY' smoke-coord -d 'Smoke test coordinator.' -a coordinator -t '$TEST_DIR' --force && \
     mkdir -p '$DEPLOY_DIR/smoke-coord' && \
     cp '$TEST_DIR/skills/smoke-coord/SKILL.md' '$DEPLOY_DIR/smoke-coord/SKILL.md' && \
     [ -f '$DEPLOY_DIR/smoke-coord/SKILL.md' ] && \
     rm -rf '$DEPLOY_DIR/smoke-coord'" \
    0

# Test 2: Run validate-all.sh and verify exit code 0
run_test 2 "validate-all.sh passes for all skills" \
    "bash '$REPO_DIR/scripts/validate-all.sh'" \
    0

# Test 3: Full lifecycle -- generate pipeline skill, validate, deploy, undeploy
run_test 3 "Full lifecycle: generate, validate, deploy, undeploy a pipeline skill" \
    "python3 '$GENERATE_PY' smoke-pipe -d 'Smoke test pipeline.' -a pipeline -t '$TEST_DIR' --force && \
     python3 '$VALIDATE_PY' '$TEST_DIR/skills/smoke-pipe/SKILL.md' && \
     mkdir -p '$DEPLOY_DIR/smoke-pipe' && \
     cp '$TEST_DIR/skills/smoke-pipe/SKILL.md' '$DEPLOY_DIR/smoke-pipe/SKILL.md' && \
     [ -f '$DEPLOY_DIR/smoke-pipe/SKILL.md' ] && \
     rm -rf '$DEPLOY_DIR/smoke-pipe' && \
     [ ! -d '$DEPLOY_DIR/smoke-pipe' ]" \
    0

# Test 4: Meta-test -- run the unit test suite from within the integration test
run_test 4 "Unit test suite passes (meta-test)" \
    "bash '$REPO_DIR/generators/test_skill_generator.sh'" \
    0

# Test 5: Cleanup
echo ""
echo -e "${BLUE}Test 5: Cleanup${RESET}"
rm -rf "$TEST_DIR"
rm -rf "$DEPLOY_DIR/smoke-coord"
rm -rf "$DEPLOY_DIR/smoke-pipe"
if [[ ! -d "$TEST_DIR" ]]; then
    echo -e "${GREEN}  PASS${RESET}"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}  FAIL${RESET}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
TOTAL_COUNT=$((TOTAL_COUNT + 1))

# Summary
echo ""
echo "========================================"
echo "Integration Test Summary"
echo "========================================"
echo "Total:  $TOTAL_COUNT"
echo -e "${GREEN}Pass:   $PASS_COUNT${RESET}"
echo -e "${RED}Fail:   $FAIL_COUNT${RESET}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}All integration tests passed!${RESET}"
    exit 0
else
    echo -e "${RED}Some integration tests failed${RESET}"
    exit 1
fi
```

2. [ ] Make executable: `chmod +x scripts/test-integration.sh`
3. [ ] Run: `bash scripts/test-integration.sh` -- verify all 5 tests pass
4. [ ] Verify no artifacts remain after execution

### Work Group 4: Archetype Decision Guide

**Files:** `generators/ARCHETYPE_GUIDE.md` (new)

**Tasks:**
1. [ ] Create `generators/ARCHETYPE_GUIDE.md` with the following sections:

**Content outline:**

```markdown
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
```

2. [ ] Verify the file references existing skills and templates correctly
3. [ ] Verify cross-references to CLAUDE.md are accurate

## Context Alignment

### CLAUDE.md Patterns Followed

- **Three-tier structure:** Test changes in `generators/` (Tier 2), integration test in `scripts/`, skill fix in `skills/` (Tier 1), documentation in `generators/`. All changes are in the correct tier.
- **Test suite pattern:** New tests in `test_skill_generator.sh` follow the existing `run_test()` harness pattern with numbered tests.
- **Conventional commits:** Proposed commit messages follow `fix(scope):` and `feat(scope):` patterns.
- **Core vs Contrib:** The `--validate --contrib` test (Test 49) uses conditional skip, consistent with existing contrib tests (43-45).
- **Edit source, not deployment:** The ship SKILL.md fix edits the source file, not the deployed copy.
- **v2.0.0 patterns:** The settings precedence fix maintains the skill's compliance with all 11 architectural patterns.

### Prior Plans Referenced

- **agentic-sdlc-next-phase.md** -- The parent plan that shipped the `--validate` flag, `validate-all.sh`, and expanded test suite. This plan adds test coverage and an integration test framework that the parent plan identified as needed but scoped out.
- **security-guardrails-phase-b.md** -- Introduced the security maturity level logic that contains the precedence bug. The bug was identified during the /retro review and documented in `.claude/learnings.md`.
- **secure-review-remediation.md** -- Identified related coder patterns (settings precedence check tests outcome rather than source).

### Deviations from Established Patterns

1. **Integration test is a separate file from the unit test suite:** The existing test pattern uses a single `test_skill_generator.sh` file. The integration test is in a separate `scripts/test-integration.sh` because it tests different things (end-to-end paths vs structural validation) and has different runtime characteristics (creates/deploys real skills vs validating existing files). Keeping them separate allows running unit tests without side effects.

2. **ARCHETYPE_GUIDE.md in generators/ instead of docs/:** The guide is placed in `generators/` because it is a companion to `generate_skill.py` and the skill templates. A `docs/` directory does not currently exist in the repository, and creating one for a single file would be premature.

3. **Test numbers 47-50 instead of 47-49:** The cleanup test is always the last test. Renumbering it from 46 to 50 (instead of leaving it at 46 and inserting before it) maintains the invariant that the cleanup test number equals the total test count, which makes the test summary easier to verify at a glance.

<!-- Context Metadata
discovered_at: 2026-03-27T21:00:00Z
claude_md_exists: true
recent_plans_consulted: agentic-sdlc-next-phase.md, security-guardrails-phase-b.md, secure-review-remediation.md
archived_plans_consulted: none
-->

## Status: APPROVED
