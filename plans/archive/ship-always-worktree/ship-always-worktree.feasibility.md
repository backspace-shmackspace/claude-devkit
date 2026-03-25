# Feasibility Review: Ship Skill -- Always Use Worktree Isolation

**Plan:** `/Users/imurphy/projects/claude-devkit/plans/ship-always-worktree.md`
**Reviewed against:** `/Users/imurphy/projects/claude-devkit/skills/ship/SKILL.md` (v3.2.0)
**Review round:** 2 (re-review after revision)
**Date:** 2026-02-24
**Reviewer:** code-reviewer agent

---

## Verdict: PASS

The revised plan addresses both Major concerns from the first review round and is technically feasible. Two minor issues remain that can be handled during implementation without blocking approval.

---

## First-Round Concern Resolution

### Concern 1: `scoped_files` derivation for single-group plans -- RESOLVED

The plan now includes explicit derivation instructions in the "Step 1 -- Plan Parsing" section (lines 136-146). The contract is unambiguous: when no `## Work Groups` section exists, extract ALL files from both `### Files to Modify` and `### Files to Create` tables in the Task Breakdown. This is reinforced in Assumption 4 (line 36), detailed edit item 3 (lines 512-513), and acceptance criterion at line 480.

### Concern 2: Revision loop worktrees lacking first-pass code -- RESOLVED

The plan adds a WIP commit in Step 5a (lines 265-270) before re-creating worktrees. Worktrees created from HEAD after this commit will contain the first-pass implementation. The coder can then read code review feedback and apply targeted fixes rather than re-implementing from scratch. This is documented in the risk table (line 415) and acceptance criteria (line 481).

---

## Concerns

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

#### 1. Step 6 squash logic is under-specified (lines 296-301)

The plan acknowledges that the number of WIP commits to squash varies depending on which steps executed, but provides only a descriptive comment rather than explicit conditional logic. The possible states are:

| Shared Deps (3a) | Revision (5a) | WIP Commits | Squash Command |
|---|---|---|---|
| No | No | 0 | No reset needed |
| Yes | No | 1 | `git reset --soft HEAD~1` |
| No | Yes | 1 | `git reset --soft HEAD~1` |
| Yes | Yes | 2 | `git reset --soft HEAD~2` |

**Recommendation:** Add this matrix to the plan's Step 6 section, or specify that the coordinator should count WIP commits by searching `git log --oneline` for messages matching `"WIP: /ship"` and reset by that count. Either approach would make the squash logic unambiguous for the implementer.

**Risk if unaddressed:** Low. An experienced implementer will derive the correct conditional, but an explicit specification reduces the chance of an off-by-one error in the reset count.

#### 2. `git add -A` in Step 5a captures unintended files (line 265)

The WIP commit uses `git add -A`, which stages everything in the working directory. At the point Step 5a executes, the working directory may contain:
- Artifact files (`./plans/[name].code-review.md`, `./plans/[name].qa-report.md`)
- Test failure logs (`./plans/[name].test-failure.log`)

These files would be included in the WIP commit and subsequently in revision worktrees.

**Recommendation:** Replace `git add -A` with `git add <files from plan task breakdown>` to stage only the implementation files. This matches the selective staging pattern already used in Step 6 (line 542 of current SKILL.md).

**Risk if unaddressed:** Low. The WIP commit is squashed in Step 6, so the extra files never appear in the final commit. The only side effect is that revision worktrees would contain plan artifacts, which is harmless but untidy.

---

## What the Plan Gets Right

1. **Single code path elimination.** Removing the dual-path conditional is the highest-value change. The current v3.2.0 has two maintenance surfaces in Step 3 and two in Step 5. The unified path reduces cognitive load and eliminates a class of bugs where one path is updated but the other is forgotten.

2. **`mktemp -d` for worktree paths.** Replacing the deterministic `/tmp/ship-${name}-wg${num}-${TIMESTAMP}` pattern with `mktemp -d /tmp/ship-XXXXXXXXXX` eliminates the TOCTOU window between path construction and directory creation. The 0700 permissions are a meaningful security improvement.

3. **Run-scoped tracking files.** The `${RUN_ID}` suffix on `.ship-worktrees-${RUN_ID}.tmp` and `.ship-violations-${RUN_ID}.tmp` correctly prevents concurrent `/ship` runs from corrupting each other's state. The orphan-aware cleanup in Step 0 is a sensible approach.

4. **Post-merge validation.** The warning-level file existence check in Step 3e (lines 222-228) catches the case where a coder fails to produce a scoped file without blocking the workflow. This is the right severity level -- the code review in Step 4 is the authoritative check.

5. **Known limitation documentation.** Explicitly documenting the `awk '{print $2}'` parsing limitation for renames and spaces (lines 206-211) is better than leaving it as a latent bug. Noting that the merge step is the primary safety boundary (since it copies only scoped files) correctly identifies why this limitation is acceptable.

6. **Backward compatibility.** The plan correctly identifies that Steps 3b-3f already work for a single work group since the bash loops iterate over the tracking file which will have exactly one line. No structural changes to the loop logic are needed.

7. **Comprehensive acceptance criteria.** The 17-item checklist (lines 470-487) covers both the removal of old code paths and the addition of new mechanics. The string-absence checks are particularly good -- they catch incomplete removals that a visual review might miss.

---

## Recommendations

Prioritized action items:

1. **(Minor)** Specify the Step 6 squash count logic explicitly, either as a conditional matrix or a `git log --grep` approach. This costs a few lines in the plan and removes ambiguity.

2. **(Minor)** Replace `git add -A` in Step 5a with selective staging of plan task breakdown files, matching the pattern already used in Step 6.

Both items can be addressed during implementation without requiring a plan revision.

---

## Verdict: PASS

The plan is technically feasible and well-designed. Both Major concerns from the first review round have been resolved with clear, correct solutions. The two remaining Minor concerns are implementation details that do not affect the plan's structural soundness. The change reduces code complexity, eliminates a maintenance burden, and provides consistent isolation guarantees for all `/ship` runs.
