# QA Report: Portfolio Hygiene -- Generator Defaults Update (Task 9, AC #4)

**Date:** 2026-02-24
**Scope:** claude-devkit generator defaults updated from `claude-skills` to `claude-devkit`
**Plan Reference:** `~/plans/portfolio-hygiene.md`, Task 9, Acceptance Criterion #4
**Validator:** qa-engineer agent (claude-devkit)

---

## Verdict: PASS

All 8 acceptance criteria verified. No defects found.

---

## Acceptance Criteria Coverage

- [x] **AC1: `generate_skill.sh` default points to `~/workspaces/claude-devkit`**
  - File: `/Users/imurphy/projects/claude-devkit/generators/generate_skill.sh`, line 35
  - Actual: `TARGET_DIR="${3:-$HOME/workspaces/claude-devkit}"`
  - Status: PASS

- [x] **AC2: `generate_skill.py` default points to `~/workspaces/claude-devkit`**
  - File: `/Users/imurphy/projects/claude-devkit/generators/generate_skill.py`, lines 533-534
  - Actual default: `default=str(Path.home() / 'workspaces' / 'claude-devkit')`
  - Actual help text: `help='Target directory containing skills/ (default: ~/workspaces/claude-devkit)'`
  - Status: PASS

- [x] **AC3: `test_skill_generator.sh` SKILLS_DIR points to `~/workspaces/claude-devkit`**
  - File: `/Users/imurphy/projects/claude-devkit/generators/test_skill_generator.sh`, line 28
  - Actual: `SKILLS_DIR="$HOME/workspaces/claude-devkit"`
  - Status: PASS

- [x] **AC4: `validate_skill.py` usage example references `~/workspaces/claude-devkit`**
  - File: `/Users/imurphy/projects/claude-devkit/generators/validate_skill.py`, line 9
  - Actual: `python validate_skill.py ~/workspaces/claude-devkit/skills/dream/SKILL.md`
  - Status: PASS

- [x] **AC5: `README.md` references updated from `claude-skills` to `claude-devkit`**
  - File: `/Users/imurphy/projects/claude-devkit/generators/README.md`
  - Line 379: `--target-dir, -t    Target directory containing skills/ (default: ~/workspaces/claude-devkit)` -- PASS
  - Line 461: `python validate_skill.py ~/workspaces/claude-devkit/skills/dream/SKILL.md` -- PASS
  - Lines 556-562: Section title is "Integration with claude-devkit", content references `~/workspaces/claude-devkit/skills/<name>/SKILL.md` and `cd ~/workspaces/claude-devkit && ./deploy.sh <name>` -- PASS
  - Status: PASS

- [x] **AC6: `install.sh` example path references `claude-devkit`**
  - File: `/Users/imurphy/projects/claude-devkit/scripts/install.sh`, line 172
  - Actual: `validate-skill ../claude-devkit/skills/my-skill/SKILL.md`
  - Status: PASS

- [x] **AC7: No remaining `claude-skills` references in any of the 6 files**
  - Ran `grep claude-skills` against all 6 files; zero matches across all files.
  - Status: PASS

- [x] **AC8: Generator functional test passes**
  - Command: `python3 generate_skill.py test-qa-validation -d "QA validation test." -t /tmp/sg-qa-validation --force`
  - Result: Skill generated at `/tmp/sg-qa-validation/skills/test-qa-validation/SKILL.md`, validation returned "PASS -- All v2.0.0 patterns validated successfully."
  - Cleanup: `/tmp/sg-qa-validation` removed after test.
  - Status: PASS

---

## Missing Tests or Edge Cases

None identified. The implementation covers all 6 files specified in the plan, all functional defaults and documentation references have been updated, and the generator produces valid output after the change.

One minor observation (non-blocking): The `install.sh` line 172 uses a relative path (`../claude-devkit/skills/...`) rather than the tilde-prefixed absolute path (`~/workspaces/claude-devkit/skills/...`) used elsewhere. This is consistent with the plan's specification for `install.sh` (which shows the example as a usage hint where relative paths are appropriate for demonstrating the `validate-skill` alias from a sibling directory). No action required.

---

## Notes

- The path choice of `~/workspaces/claude-devkit` (rather than `~/projects/claude-devkit`) is correct and intentional. The `generate_skill.py` `validate_target_dir()` function (lines 113-132) restricts target directories to `~/workspaces/` or `/tmp/`. Using `~/projects/` would cause the generator to reject its own default with exit code 2.
- The functional test required pre-creating the target directory (`mkdir -p /tmp/sg-qa-validation`) before running the generator, as `validate_target_dir()` checks for directory existence. This is expected behavior -- the generator validates that the target exists before writing.
- All changes are consistent with the plan's Task 9 specification. Line numbers match the plan's references.
