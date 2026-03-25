# QA Report: Ship Skill -- Always Use Worktree Isolation

**Plan:** `/Users/imurphy/projects/claude-devkit/plans/ship-always-worktree.md`
**Skill Under Test:** `/Users/imurphy/projects/claude-devkit/skills/ship/SKILL.md`
**Registry Under Test:** `/Users/imurphy/projects/claude-devkit/CLAUDE.md`
**Date:** 2026-02-24
**QA Agent:** qa-engineer (v1.0.0, base qa-engineer-base v1.8.0)

---

## Verdict: PASS

---

## Acceptance Criteria Coverage

| # | Criterion | Met? | Evidence |
|---|-----------|------|----------|
| 1 | The string "Single Work Group Path (No Worktrees)" does not appear in `skills/ship/SKILL.md` | MET | Grep returns 0 matches |
| 2 | The string "If single work group (no worktrees)" does not appear in `skills/ship/SKILL.md` | MET | Grep returns 0 matches |
| 3 | The string "If work groups were used in Step 3" does not appear in `skills/ship/SKILL.md` | MET | Grep returns 0 matches |
| 4 | Frontmatter version is `3.3.0` | MET | Line 4: `version: 3.3.0` |
| 5 | Steps 3b-3f are present and unconditional (no branching based on work group count) | MET | Steps 3a-3f present at lines 166-435. No conditional gates based on work group count. Step 3a is correctly conditional on Shared Dependencies only. Steps 3b-3f execute unconditionally. |
| 6 | Step 3a remains conditional on `### Shared Dependencies` section existence | MET | Line 168: "**Trigger:** Plan contains `### Shared Dependencies` section. If no Shared Dependencies section exists, skip directly to Step 3b." |
| 7 | Step 3b uses `mktemp -d` instead of deterministic paths | MET | Line 213: `WORKTREE_PATH=$(mktemp -d /tmp/ship-XXXXXXXXXX)` |
| 8 | All references to `.ship-worktrees.tmp` use run-scoped format `.ship-worktrees-${RUN_ID}.tmp` | MET | 0 occurrences of `.ship-worktrees.tmp` (non-scoped). 9 occurrences of `.ship-worktrees-${RUN_ID}.tmp` across Steps 0, 3b, 3c, 3d, 3e, 3f. |
| 9 | Step 3d includes a known-limitation comment about `awk '{print $2}'` parsing | MET | Lines 310-313: comment about renamed files and spaces |
| 10 | Step 3e includes post-merge file existence validation (warning-level) | MET | Lines 389-396: warning loop checking `[ ! -f "$MAIN_DIR/$file" ]`; lines 399-401 confirm non-blocking semantics |
| 11 | Step 1 includes explicit `scoped_files` derivation for plans without `## Work Groups` | MET | Lines 108-112: derives from Files to Modify + Files to Create tables, stores as single implicit work group |
| 12 | Step 5a includes a WIP commit before worktree re-creation | MET | Lines 522-525: `git add -A && git commit -m "WIP: ship v3.3.0 first-pass implementation (pre-revision)"` |
| 13 | Step 5a has exactly one path -- always uses worktrees | MET | Lines 515-549: single unconditional path with worktree workflow. No conditional branching. |
| 14 | Skill passes `validate_skill.py` with exit code 0 | MET | Validator output: "PASS (with warnings)" -- 1 optional warning about timestamped artifacts (pre-existing, not introduced by this change). Exit code 0. |
| 15 | CLAUDE.md Skill Registry shows ship version `3.3.0` | MET | CLAUDE.md line 89: `| **ship** | 3.3.0 | ...` |
| 16 | CLAUDE.md Skill Registry description removes "(for work groups)" parenthetical | MET | Grep for "(for work groups)" returns 0 matches. Description reads: "Worktree isolation" without parenthetical qualifier. |
| 17 | CLAUDE.md "When NOT to use" section is updated to remove single-file guidance | MET | Lines 559-561: only "Read-only operations" and "Tightly coupled files" remain. "Single-file changes (no parallelism needed)" has been removed. |
| 18 | The Step 3a WIP commit message references `v3.3.0` | MET | Line 196: `Created by: /ship skill v3.3.0"` |

**Result: 18/18 criteria met.**

---

## Automated Validation

```
$ python3 generators/validate_skill.py skills/ship/SKILL.md

Skill Validation Report
File: skills/ship/SKILL.md
Skill: ship (v3.3.0)

Warnings (1):
  - Timestamped Artifacts: Pattern 5 (Timestamped Artifacts): Consider using
    timestamped filenames for artifact outputs.

PASS (with warnings)
  1 optional improvement(s) suggested.
```

Exit code: 0. The timestamped artifacts warning is pre-existing and unrelated to this change (ship uses plan-name-based artifacts rather than timestamped ones by design).

---

## Missing Tests or Edge Cases

No missing coverage was identified for the acceptance criteria. All 18 criteria are directly verifiable from the file contents.

The plan's manual smoke tests (single work group, multiple work groups, shared dependencies, revision loop, aborted run cleanup, concurrent runs) are not automatable in this validation pass. They require live `/ship` invocations against test plans. These are documented in the plan's Test Plan section and should be executed before the final merge.

---

## Notes

1. **Validator warning is pre-existing.** The "Timestamped Artifacts" warning from `validate_skill.py` exists in v3.2.0 as well. Ship uses plan-name-based artifact filenames (e.g., `[name].code-review.md`) by design, which is appropriate for its use case.

2. **Step 6 squash logic updated.** Line 572 correctly accounts for 0, 1, or 2 WIP commits (Step 3a shared deps and/or Step 5a pre-revision), matching the plan requirement.

3. **Run-scoped violation files.** The `.ship-violations-${RUN_ID}.tmp` scoping is also implemented (line 346), consistent with the tracking file scoping, though this was not an explicit acceptance criterion.

4. **Orphan-aware cleanup in Step 0.** Lines 39-52 implement the orphan-aware tracking file cleanup as specified, checking whether listed worktrees still exist before deleting tracking files.
