# Code Review: Ship Skill -- Always Use Worktree Isolation

**Plan:** `/Users/imurphy/projects/claude-devkit/plans/ship-always-worktree.md`
**Reviewer:** code-reviewer agent v1.0.0
**Date:** 2026-02-24
**Files Reviewed:**
- `/Users/imurphy/projects/claude-devkit/skills/ship/SKILL.md`
- `/Users/imurphy/projects/claude-devkit/CLAUDE.md`

## Code Review Summary

The implementation correctly unifies the dual-path worktree logic into a single, always-on isolation path. All 18 acceptance criteria from the plan are satisfied. The SKILL.md changes are well-structured, the CLAUDE.md registry is updated consistently, and the skill passes validation. No critical or major issues were found.

## Verdict: PASS

---

## Acceptance Criteria Verification

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | "Single Work Group Path (No Worktrees)" absent from SKILL.md | PASS | Grep confirms 0 matches |
| 2 | "If single work group (no worktrees)" absent from SKILL.md | PASS | Grep confirms 0 matches |
| 3 | "If work groups were used in Step 3" absent from SKILL.md | PASS | Grep confirms 0 matches |
| 4 | Frontmatter version is 3.3.0 | PASS | Line 4: `version: 3.3.0` |
| 5 | Steps 3b-3f present and unconditional | PASS | Steps 3b (line 199), 3c (line 248), 3d (line 294), 3e (line 368), 3f (line 406) -- no conditional branching on work group count |
| 6 | Step 3a remains conditional on Shared Dependencies | PASS | Line 167-168: "Trigger: Plan contains `### Shared Dependencies` section. If no Shared Dependencies section exists, skip directly to Step 3b." |
| 7 | Step 3b uses `mktemp -d` | PASS | Line 213: `WORKTREE_PATH=$(mktemp -d /tmp/ship-XXXXXXXXXX)` |
| 8 | All `.ship-worktrees.tmp` refs use run-scoped format | PASS | All 10 references use `.ship-worktrees-${RUN_ID}.tmp`; zero references to bare `.ship-worktrees.tmp` |
| 9 | Step 3d includes awk known-limitation comment | PASS | Line 310: `# Known limitation: awk '{print $2}' does not correctly handle renamed files` |
| 10 | Step 3e includes post-merge file existence validation | PASS | Lines 389-396: warning-level loop checking `[ ! -f "$MAIN_DIR/$file" ]` |
| 11 | Step 1 includes explicit scoped_files derivation | PASS | Lines 108-112: "Derive the `scoped_files` list by extracting ALL files from the Task Breakdown section" |
| 12 | Step 5a includes WIP commit before worktree re-creation | PASS | Lines 522-524: `git commit -m "WIP: ship v3.3.0 first-pass implementation (pre-revision)"` |
| 13 | Step 5a has exactly one path (always worktrees) | PASS | Lines 515-549: single unconditional path with worktree workflow |
| 14 | Skill passes validate_skill.py with exit code 0 | PASS | Validator output: "PASS (with warnings)" -- the single warning (timestamped artifacts) is pre-existing and unrelated to this change |
| 15 | CLAUDE.md Skill Registry shows ship version 3.3.0 | PASS | CLAUDE.md line 89: `| **ship** | 3.3.0 |` |
| 16 | CLAUDE.md description removes "(for work groups)" | PASS | CLAUDE.md line 89: description reads "Worktree isolation" without parenthetical |
| 17 | CLAUDE.md "When NOT to use" updated (single-file guidance removed) | PASS | CLAUDE.md lines 559-561: only "Read-only operations" and "Tightly coupled files" remain |
| 18 | Step 3a WIP commit message references v3.3.0 | PASS | Line 196: `Created by: /ship skill v3.3.0"` |

All 18 of 18 acceptance criteria pass.

## Detailed Edit Verification (12 plan edits)

| Edit | Description | Status |
|------|-------------|--------|
| 1 | Frontmatter version bump to 3.3.0 | Done |
| 2 | Step 0: RUN_ID generation + orphan-aware cleanup | Done (lines 21-56) |
| 3 | Step 1: scoped_files derivation for no-Work-Groups plans | Done (lines 108-112) |
| 4 | Step 3: Remove single-group path, remove dual headers, add intro paragraph | Done (lines 161-164) |
| 5 | Step 3a: commit message v3.2.0 -> v3.3.0 | Done (line 196) |
| 6 | Step 3b: mktemp -d + run-scoped tracking file | Done (lines 213, 229) |
| 7 | Step 3c: tool line clarification for single-group | Done (line 250) |
| 8 | Step 3d: run-scoped filenames + awk known-limitation comment | Done (lines 310-313, 343, 346, 352) |
| 9 | Step 3e: run-scoped filenames + post-merge validation | Done (lines 387, 389-396) |
| 10 | Step 3f: run-scoped filenames + tracking file cleanup | Done (lines 422, 432) |
| 11 | Step 5a: remove dual-path, unconditional worktrees, WIP commit | Done (lines 515-549) |
| 12 | Step 6: squash logic accounts for Step 5a WIP commit | Done (lines 570-573) |

## Critical Issues (Must Fix)

None.

## Major Improvements (Should Fix)

None.

## Minor Suggestions (Consider)

1. **Step 0 orphan cleanup deletes all violation files indiscriminately** (SKILL.md line 55).
   The cleanup for `.ship-violations-*.tmp` uses `rm -f .ship-violations-*.tmp` without the same orphan-awareness applied to `.ship-worktrees-*.tmp` files. This means a concurrent run's violation file could be deleted mid-check. In practice, this is unlikely to cause problems because violation files are only read immediately after creation in the same step, and the window for a concurrent Step 0 to delete them is narrow. However, for consistency with the run-scoped design philosophy, consider applying the same orphan-check logic or simply leaving violation files for their own run to clean up in Step 3f (which already does `rm -f .ship-violations-${RUN_ID}.tmp`).

2. **Pre-existing validator warning** (timestamped artifacts pattern).
   The skill validator emits one warning about timestamped artifact filenames. This is pre-existing from before this change and is not a regression. Consider addressing it in a future change if desired.

## What Went Well

- **Clean removal of dual-path logic.** The single-group and multi-group paths have been unified without leaving any stale references to the old paths. All three removed-string acceptance criteria pass cleanly.

- **Thorough run-scoping.** Both `.ship-worktrees` and `.ship-violations` tracking files are consistently scoped with `${RUN_ID}` across all steps (3b, 3c, 3d, 3e, 3f, and cleanup in Step 0/3f). No references to the old unscoped filenames remain.

- **Security improvement with `mktemp -d`.** Replacing deterministic `/tmp/ship-${name}-wg${num}-${TIMESTAMP}` paths with `mktemp -d /tmp/ship-XXXXXXXXXX` eliminates symlink/TOCTOU attack vectors. The explanatory comment (lines 232-235) clearly documents the rationale.

- **Orphan-aware cleanup in Step 0.** The pre-flight cleanup correctly checks whether worktrees listed in tracking files still exist before deleting the files, preventing interference with concurrent runs.

- **WIP commit strategy in Step 5a.** The addition of a WIP commit before revision-loop worktree creation ensures revision coders get the first-pass implementation rather than the pre-implementation state. The corresponding Step 6 squash logic correctly accounts for 0, 1, or 2 WIP commits.

- **Post-merge validation is appropriately warning-level.** The implementation correctly emits warnings rather than blocking, with clear rationale for why missing files may be legitimate (lines 399-402).

- **CLAUDE.md updates are consistent.** The registry version, description, benefits list, and "When to use"/"When NOT to use" guidance all reflect the new always-worktree behavior.

- **Plan-code alignment is excellent.** Every one of the 12 detailed edits in the plan maps to a corresponding change in the implementation, and all 18 acceptance criteria are met.

## Recommendations

1. Consider the minor suggestion about violation file cleanup consistency (item 1 above) in a follow-up change.
2. Proceed with deployment and manual smoke testing per the plan's Phase 4.
