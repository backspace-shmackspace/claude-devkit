# QA Report: Devkit Hygiene Improvements (Re-validation after Code Review Fix)

**Plan:** `plans/devkit-hygiene-improvements.md`
**Date:** 2026-03-27
**Re-validation trigger:** Code review found and fixed one Major issue — `set -e` + `rm -rf` without `|| true` in Test 5 of `scripts/test-integration.sh`
**Verdict:** PASS_WITH_NOTES

---

## Code Review Fix Verification

**Issue:** Test 5 in `scripts/test-integration.sh` used bare `rm -rf "$TEST_DIR"` (and two similar calls) under `set -e`. If any path did not exist at cleanup time, the script would exit non-zero before recording the PASS, causing a spurious FAIL on clean-state runs.

**Fix applied:** Lines 114-116 now use `|| true` on all three `rm -rf` calls:
```bash
rm -rf "$TEST_DIR" || true
rm -rf "$DEPLOY_DIR/smoke-coord" || true
rm -rf "$DEPLOY_DIR/smoke-pipe" || true
```

**Verification:** Confirmed present in the file at lines 114-116. Fix is correct and complete.

---

## Acceptance Criteria Coverage

### WG-1: deploy.sh --validate Tests (`generators/test_skill_generator.sh`)

| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | Trap handler added near script top with `cleanup_on_exit` removing `skills/test-validate-invalid/` | MET | Lines 50-55. Function and `trap cleanup_on_exit EXIT INT TERM` both present. |
| 2 | Test 47 exists: deploys valid core skill with `--validate`, expects exit 0 | MET | Lines 512-515. Deploys `architect` skill. |
| 3 | Test 48 exists: creates invalid skill, runs `deploy.sh --validate`, expects non-zero exit | MET | Lines 517-524. Creates `$SKILLS_DIR/skills/test-validate-invalid/SKILL.md` with `# No frontmatter`. |
| 4 | Test 48 cleans up temporary invalid skill directory after the test | MET | Line 524: `rm -rf "$SKILLS_DIR/skills/test-validate-invalid"` immediately after `run_test 48`. Trap handler provides second layer. |
| 5 | Test 49 exists: deploys valid contrib skill with `--validate --contrib` (conditional) | MET | Lines 526-533. Guards on `$SKILLS_DIR/contrib/journal/SKILL.md`. |
| 6 | Cleanup test renumbered from 46 to 50 | MET | Lines 535-546. `echo -e "${BLUE}Test 50: Cleanup${RESET}"` confirmed. |
| 7 | Header comment updated to reflect accurate test inventory (numbering gaps documented) | MET | Lines 9-22. Documents gaps at 26, 33, 35; string label 27b; deploy-validate tests 47-49; cleanup at 50. |
| 8 | `bash generators/test_skill_generator.sh` passes with 0 failures | NOT VERIFIED | Script was not executed during this QA review (no live shell execution). Structural review is complete; runtime pass is unverified. See notes. |

**WG-1 Finding (minor, pre-existing):** `BOLD` is referenced at line 551 (`${BOLD}Test Summary${RESET}`) but is never defined in the color variables block (lines 27-31). This predates this plan — the new tests do not introduce it — but means the summary header will render without bold formatting. Cosmetic only; does not affect test pass/fail logic.

---

### WG-2: Settings Precedence Fix (`skills/ship/SKILL.md`)

| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | `LOCAL_SET=0` initialized after `SECURITY_MATURITY="advisory"` | MET | Line 95. `SECURITY_MATURITY` is line 94; `LOCAL_SET=0` is line 95. |
| 2 | Inline comment on `LOCAL_SET=0` explaining purpose | MET | Line 95: `# Track source, not value, to preserve precedence when local sets "advisory"` — matches plan spec verbatim. |
| 3 | `LOCAL_SET=1` set inside the local settings block when value is found | MET | Line 102. Inside `if [ -n "$LOCAL_MATURITY" ]` block. |
| 4 | Fallback condition uses `[ "$LOCAL_SET" -eq 0 ]` instead of `[ "$SECURITY_MATURITY" = "advisory" ]` | MET | Line 107: `if [ "$LOCAL_SET" -eq 0 ] && [ -f ".claude/settings.json" ]`. Old value-based check is gone. |
| 5 | Prose above code block explicitly documents precedence ("even if that value is advisory") | MET | Line 89. Full prose present; matches plan specification. |
| 6 | `python3 generators/validate_skill.py skills/ship/SKILL.md` exits 0 | NOT VERIFIED | Not executed during this review. Frontmatter, step format, and all required patterns are structurally intact; high confidence in pass. |
| 7 | No other lines in `skills/ship/SKILL.md` are modified | MET | Only lines 89 (prose) and 93-110 (code block) changed. All other steps, tool declarations, verdict gates, and archiving logic are intact. |

---

### WG-3: Integration Test Framework (`scripts/test-integration.sh`)

| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | `scripts/test-integration.sh` exists and is executable | MET | `-rwxr-xr-x` confirmed. |
| 2 | Trap handler at script top: `trap cleanup EXIT INT TERM` removing all smoke artifacts | MET | Lines 37-42. Removes `$TEST_DIR`, `$DEPLOY_DIR/smoke-coord`, `$DEPLOY_DIR/smoke-pipe` with `|| true`. |
| 3 | Uses same `run_test()` harness pattern as `test_skill_generator.sh` | MET | Lines 49-75. Same four-argument signature, `eval`, `set +e`/`set -e`, PASS/FAIL counting. |
| 4 | Test 1: generates coordinator skill, deploys, verifies file, cleans up | MET | Lines 82-88. Generates `smoke-coord`, copies to `$DEPLOY_DIR`, verifies with `[ -f ... ]`, removes. |
| 5 | Test 2: runs `validate-all.sh`, expects exit 0 | MET | Lines 91-93. |
| 6 | Test 3: full lifecycle — generate pipeline, validate, deploy, verify, undeploy, verify removal | MET | Lines 96-104. All six lifecycle steps present in one compound command. |
| 7 | Test 4: runs `test_skill_generator.sh`, expects exit 0 (meta-test) | MET | Lines 107-109. |
| 8 | Test 5: cleanup removes all smoke test artifacts | MET | Lines 111-124. `|| true` applied to all three `rm -rf` calls (code review fix). |
| 9 | No tests modify the source tree (no temporary skills created in `skills/`) | MET | All generated skills go to `/tmp/integration-smoke-test`. No writes to `$REPO_DIR/skills/`. |
| 10 | `bash scripts/test-integration.sh` passes with 0 failures | NOT VERIFIED | Not executed during this review. |
| 11 | No artifacts remain after the script completes | NOT VERIFIED | Trap handler (EXIT) and explicit `|| true` cleanup in Test 5 cover this structurally. |

**WG-3 Finding (minor, cosmetic):** `test-integration.sh` emits plain `PASS` / `FAIL` in `run_test()` output (lines 66, 72) while `test_skill_generator.sh` uses `✅ PASS` / `❌ FAIL`. Logic is identical; output style differs. Not a behavioral defect.

---

### WG-4: Archetype Decision Guide (`generators/ARCHETYPE_GUIDE.md`)

| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | `generators/ARCHETYPE_GUIDE.md` exists | MET | File present and readable. |
| 2 | Contains a decision tree with at least 3 decision points | MET | Lines 13-24. Three ordered questions covering coordinator, pipeline, scan, and reference paths. |
| 3 | Contains a comparison table with columns for coordinator, pipeline, and scan | MET | Lines 28-36. Seven dimensions compared. |
| 4 | Contains at least one example skill per archetype | MET | `/architect` (line 60), `/ship` and `/sync` (lines 86-87), `/audit` and `/secrets-scan` (lines 111-112). |
| 5 | Cross-references all three templates | MET | `templates/skill-coordinator.md.template` (line 61), `templates/skill-pipeline.md.template` (line 88), `templates/skill-scan.md.template` (line 113). |
| 6 | Mentions the reference archetype briefly | MET | Lines 115-135. Full section with When to Use, Examples, and Key Differences from workflow archetypes. |
| 7 | Cross-references `CLAUDE.md` as authoritative source | MET | Lines 149-151: "See the CLAUDE.md 'Skill Architectural Patterns (v2.0.0)' section for the complete pattern specification." |

---

## Missing Tests or Edge Cases

1. **No automated behavioral test for WG-2 fix.** The settings precedence fix is correct by inspection — `LOCAL_SET` guards the fallback unconditionally regardless of what value was stored. The exact bug scenario (`advisory` in local, `enforced` in project) cannot be tested without mocking `.claude/settings.local.json` and executing the /ship skill. Out of scope per plan Non-Goals.

2. **Test 47 verifies exit code only, not artifact presence.** A deploy script returning 0 without writing files would pass Test 47. Exit-code-only is the plan's stated scope for this test; acceptable known limitation.

3. **Integration Test 4 nests the full unit suite (~44 tests).** The integration suite runtime is dominated by Test 4. Not a defect, but relevant for future CI budget planning.

4. **`BOLD` variable undefined in `test_skill_generator.sh`.** Pre-existing defect, not introduced by this plan. Recommend fixing in a follow-up commit alongside any other cosmetic cleanup.

---

## Notes (PASS_WITH_NOTES rationale)

All four work groups meet their acceptance criteria structurally. The code review Major fix (`|| true` in Test 5) is correctly applied and verified. PASS_WITH_NOTES rather than PASS because:

1. **Three criteria require live execution to confirm.** `bash generators/test_skill_generator.sh`, `python3 generators/validate_skill.py skills/ship/SKILL.md`, and `bash scripts/test-integration.sh` were not run during this review. Logic and structure are correct; runtime confirmation is the remaining gap.

2. **Pre-existing `BOLD` variable defect** is cosmetic but visible on every test suite run.

**To upgrade to PASS:** Run the three commands from the plan's Test Plan section and confirm all exit 0:

```bash
cd /Users/imurphy/projects/claude-devkit && bash generators/test_skill_generator.sh
cd /Users/imurphy/projects/claude-devkit && bash scripts/test-integration.sh
cd /Users/imurphy/projects/claude-devkit && python3 generators/validate_skill.py skills/ship/SKILL.md
```
