# Code Review: Task 9 -- Update claude-devkit generator defaults and documentation references

**Reviewer:** Claude Opus 4.6 (code-reviewer agent)
**Date:** 2026-02-24
**Plan:** `~/plans/portfolio-hygiene.md` -- Task 9 (Phase 5)
**Scope:** 6 files in claude-devkit that referenced the deprecated `claude-skills` repo

---

## Verdict: PASS

All 6 files have been updated correctly. Every `claude-skills` reference has been replaced with `claude-devkit`. The new default path is `~/workspaces/claude-devkit` throughout (not `~/projects/claude-devkit`), which is correct given `generate_skill.py`'s `validate_target_dir()` constraint that restricts targets to `~/workspaces/` or `/tmp/`. No extraneous changes were introduced beyond what the plan specifies.

---

## Critical Findings

None.

---

## Major Findings

None.

---

## Minor Findings

1. **`install.sh` line 172 uses relative path:** The example reads `validate-skill ../claude-devkit/skills/my-skill/SKILL.md` (relative path with `../`). The plan specified updating "from `../claude-skills/skills/my-skill/SKILL.md` to reference claude-devkit", which this satisfies. However, the relative `../` form is fragile -- it only works if the user's CWD is a sibling of `claude-devkit`. The other 5 files all use absolute `~/workspaces/claude-devkit/...` paths. This is pre-existing behavior (the old value was `../claude-skills/...`), so it is not a regression, but a future improvement could normalize this to an absolute path for consistency. **Not blocking.**

---

## Positives

1. **Complete coverage:** All 6 files identified in the plan were updated. Zero `claude-skills` references remain across any of them (verified via grep).
2. **Correct path choice:** The new default uses `~/workspaces/claude-devkit` consistently, respecting the `validate_target_dir()` constraint that would reject `~/projects/claude-devkit` with exit code 2.
3. **Minimal, surgical changes:** Only the path strings were changed. No functional logic, no formatting, no unrelated edits. The diff is exactly what the plan prescribed.
4. **Functional defaults and documentation both updated:** The 3 functional default files (generate_skill.sh, generate_skill.py, test_skill_generator.sh) and the 3 documentation files (validate_skill.py, README.md, install.sh) are all consistent with each other.
5. **README.md section title updated:** The "Integration with claude-skills" section heading (line 556) was correctly renamed to "Integration with claude-devkit", not just the paths within it.

---

## File-by-File Verification

| # | File | Line(s) | Old Value | New Value | Status |
|---|------|---------|-----------|-----------|--------|
| 1 | `generators/generate_skill.sh` | 35 | `$HOME/workspaces/claude-skills` | `$HOME/workspaces/claude-devkit` | OK |
| 2 | `generators/generate_skill.py` | 533 | `'workspaces' / 'claude-skills'` | `'workspaces' / 'claude-devkit'` | OK |
| 2 | `generators/generate_skill.py` | 534 | `~/workspaces/claude-skills` | `~/workspaces/claude-devkit` | OK |
| 3 | `generators/test_skill_generator.sh` | 28 | `$HOME/workspaces/claude-skills` | `$HOME/workspaces/claude-devkit` | OK |
| 4 | `generators/validate_skill.py` | 9 | `~/workspaces/claude-skills/skills/dream/SKILL.md` | `~/workspaces/claude-devkit/skills/dream/SKILL.md` | OK |
| 5 | `generators/README.md` | 379 | `~/workspaces/claude-skills` | `~/workspaces/claude-devkit` | OK |
| 5 | `generators/README.md` | 461 | `~/workspaces/claude-skills/skills/dream/SKILL.md` | `~/workspaces/claude-devkit/skills/dream/SKILL.md` | OK |
| 5 | `generators/README.md` | 556-562 | "Integration with claude-skills" + paths | "Integration with claude-devkit" + paths | OK |
| 5 | `generators/README.md` | 703 | `claude-skills` | `claude-devkit` | OK |
| 6 | `scripts/install.sh` | 172 | `../claude-skills/skills/my-skill/SKILL.md` | `../claude-devkit/skills/my-skill/SKILL.md` | OK |

## Stale Reference Check

```
grep -n "claude-skills" across all 6 files: 0 matches
```

No remaining stale references.
