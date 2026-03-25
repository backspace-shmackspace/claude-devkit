# Red Team Review (Round 2): Ship Skill — Always Use Worktree Isolation

**Plan:** `/Users/imurphy/projects/claude-devkit/plans/ship-always-worktree.md`
**Reviewer:** Security Analyst (security-analyst agent)
**Date:** 2026-02-24
**Round:** 2 (re-review after plan revision)
**Skill Under Review:** `/ship` v3.2.0 -> v3.3.0

---

## Verdict: PASS

All 1 Critical and 5 Major findings from Round 1 have been addressed in the revised plan. The remaining open items are Minor or Info severity and do not block implementation. The plan is ready to ship.

---

## Round 1 Finding Disposition

### Finding 1: Symlink / TOCTOU Attack in /tmp (was Critical) — RESOLVED

**Status:** Addressed.

The revised plan replaces the deterministic path format with `mktemp -d /tmp/ship-XXXXXXXXXX` in Step 3b (lines 177-189). The plan correctly documents three properties of `mktemp -d`: 0700 permissions, random suffix eliminating symlink/TOCTOU, and kernel-guaranteed uniqueness. The Proposed Structure diagram (line 71) and Detailed Edits item 6 (lines 518-522) are consistent with this change.

No residual risk from this finding.

---

### Finding 2: PID-Based Uniqueness (was Major) — RESOLVED

**Status:** Addressed. Subsumed by Finding 1's resolution.

The switch to `mktemp -d` eliminates the PID-based path entirely. The plan no longer references `$$` in any path construction. The `RUN_ID` (lines 117-121) uses `/dev/urandom` for the random component, which is separate from and stronger than PID-based uniqueness. The `RUN_ID` is used for tracking filenames and branch names, not for directory creation — `mktemp -d` handles directory uniqueness independently.

No residual risk from this finding.

---

### Finding 3: Silent Data Loss During Merge (was Major) — RESOLVED

**Status:** Addressed.

The revised plan adds post-merge file existence validation in Step 3e (lines 218-233). The implementation checks each scoped file with `[ ! -f "$MAIN_DIR/$file" ]` and emits a WARNING. The plan correctly documents that this is non-blocking because:

1. Files listed under "Files to Modify" may already exist and not need re-creation.
2. The code review in Step 4 catches genuinely missing files.

This is a reasonable design. A blocking error would produce false positives for "modify" files that the coder chose not to change. The warning provides visibility without over-blocking.

**Residual (Minor):** The post-merge validation distinguishes "file not created" but does not distinguish between "file was supposed to be created (Files to Create) vs. modified (Files to Modify)." A stronger implementation could block on missing "Files to Create" entries while warning on missing "Files to Modify" entries. This is a refinement, not a gap. Severity: Minor.

---

### Finding 4: Boundary Validation git status Parsing (was Major) — RESOLVED

**Status:** Addressed as accepted risk with documentation.

The revised plan adds a known-limitation comment to Step 3d (lines 206-211) documenting that `awk '{print $2}'` does not correctly handle renamed files or paths with spaces. The plan correctly identifies that the merge step (which copies only scoped files) is the primary safety boundary, and boundary validation is defense-in-depth. Improving the parsing is explicitly deferred to a follow-up change (line 29, Non-Goals).

The documentation is clear and the risk acceptance is reasonable. The merge-as-primary-boundary argument is sound — out-of-scope modifications in a worktree are never merged regardless of validation.

No residual risk from this finding (accepted and documented).

---

### Finding 5: PID-Based Uniqueness (was Major) — RESOLVED

**Status:** Addressed. Same resolution as Finding 2 — `mktemp -d` replaces all PID-based path construction.

---

### Finding 6: Concurrent Runs / Step 0 Cleanup (was Major, merged with Finding 7) — RESOLVED

**Status:** Addressed.

The revised plan introduces two complementary mechanisms:

1. **Run-scoped tracking filenames** (lines 122-128): `.ship-worktrees-${RUN_ID}.tmp` and `.ship-violations-${RUN_ID}.tmp` replace the shared `.ship-worktrees.tmp`. Each run writes to its own file, eliminating write contention.

2. **Orphan-aware Step 0 cleanup** (lines 130-134): Instead of `rm -f .ship-worktrees.tmp`, Step 0 now reads each `.ship-worktrees-*.tmp` file, checks whether the listed worktrees still exist via `git worktree list`, and only deletes tracking files whose worktrees are gone. Active runs' tracking files are preserved.

This is a correct and complete resolution. The two mechanisms work together: run-scoped names prevent write collisions, and orphan-aware cleanup prevents deletion of active state.

**Residual (Info):** The orphan check relies on `git worktree list` which reports worktrees registered in `.git/worktrees/`. If a worktree directory was manually deleted but not `git worktree remove`-d, `git worktree list` still shows it (marked as "prunable"). The orphan check should handle this correctly since the tracking file's listed paths would not exist on disk, but the `git worktree list` comparison might produce a false negative (worktree listed but directory gone). The `git worktree prune` in Step 0 (already present in v3.2.0, line 30 of SKILL.md) handles this case by cleaning up stale worktree registrations before the orphan check runs. No action needed.

---

## New Findings (Round 2)

### 11. RUN_ID Generation Uses Pipe With head -c (Minor)

**Category:** Reliability — Correctness
**Severity:** Minor

The `RUN_ID` generation command (line 120):

```bash
RUN_ID=$(date +%Y%m%d-%H%M%S)-$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 6)
```

This works correctly on both macOS and Linux but has a minor inefficiency: `cat /dev/urandom` produces an infinite stream, and `head -c 6` terminates the pipe after 6 matching characters. The `tr` filter discards non-matching bytes, so the pipeline reads significantly more than 6 bytes from `/dev/urandom`. This is functionally correct and the entropy is sufficient (36^6 = ~2.2 billion combinations), but a cleaner alternative would be:

```bash
RUN_ID=$(date +%Y%m%d-%H%M%S)-$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6)
```

This avoids the unnecessary `cat` process (UUOC). Not a functional issue.

**Recommendation:** No action required. Cosmetic improvement only.

---

### 12. WIP Commit in Step 5a Uses `git add -A` (Minor)

**Category:** Security — Data Integrity
**Severity:** Minor

Step 5a (lines 265-267) performs:

```bash
git add -A
git commit -m "WIP: ship v3.3.0 first-pass implementation (pre-revision)"
```

The `git add -A` stages everything in the working directory, including any files that may have been created outside the `/ship` workflow (IDE temp files, editor swap files, `.env` changes). These get committed into the WIP commit and propagated to revision-loop worktrees.

This is mitigated by:
1. Step 0 pre-flight requires a clean working directory (`git status --porcelain` must be empty).
2. Between Step 0 and Step 5a, only `/ship`-controlled operations modify files (merge from Step 3e).
3. The WIP commit is squashed away in Step 6.

The risk window is narrow: something would have to create an untracked file between Step 3e (merge) and Step 5a (WIP commit) — for example, a background file watcher or IDE plugin. The worktree isolation itself mitigates this since the revision coder works in a worktree, not the main directory.

**Recommendation:** No action required. The existing mitigations are sufficient. If desired, the WIP commit could stage only scoped files (`git add $scoped_files`) instead of `git add -A`, but this adds complexity for marginal benefit.

---

### 13. Post-Merge Validation Does Not Check for Corrupt/Truncated Files (Info)

**Category:** Reliability — Data Integrity
**Severity:** Info

The post-merge validation (lines 222-228) checks `[ ! -f "$MAIN_DIR/$file" ]` — file existence only. It does not validate that the merged file has non-zero size or matches the worktree version. A `cp` failure (disk full, permission denied) could produce a zero-byte or partial file that passes the existence check.

This is a theoretical concern. In practice:
1. `cp` returns a non-zero exit code on failure, which would surface in bash error output.
2. The code review in Step 4 reads the actual file content.
3. Tests in Step 4 would fail on truncated files.

**Recommendation:** No action required. Defense-in-depth from Step 4 is sufficient.

---

### 14. Branch Name `ship-wg${WG_NUM}-${RUN_ID}` Could Accumulate (Info)

**Category:** Reliability — Resource Cleanup
**Severity:** Info

Step 3b creates branches named `ship-wg${WG_NUM}-${RUN_ID}` (line 180). Step 3f removes the worktrees but the plan does not explicitly state whether the branches are also deleted. `git worktree remove` detaches the worktree but does not delete the branch. Over many runs, `ship-wg*` branches will accumulate.

This is a pre-existing behavior from v3.2.0 (the branch naming format changed but the cleanup behavior did not). The branches are local-only and lightweight. Periodic `git branch | grep ship-wg | xargs git branch -D` cleans them up.

**Recommendation:** No action required. Consider adding branch cleanup to Step 3f as a future enhancement.

---

## Round 1 Findings Not Re-Reviewed (Unchanged)

The following Round 1 findings were Minor or Info severity and did not require plan changes. Their status is unchanged:

| # | Finding | Round 1 Severity | Status |
|---|---------|-----------------|--------|
| 5 | No fallback if worktrees unsupported | Minor | Open — recovery guidance recommended but not blocking |
| 8 | git status parsing fragile | Minor | Open — technical debt, deferred to follow-up |
| 9 | Force cleanup discards uncommitted | Info | Closed — correct behavior, no action needed |
| 10 | Plan name not sanitized for shell | Minor | Open — `mktemp -d` eliminates the path injection vector from Finding 1, but `$PLAN_NAME` is still used in the branch name (`ship-wg${WG_NUM}-${RUN_ID}`) which does not include the plan name. The plan name appears only in Step 1 parsing context where it is read from a file path argument. Reduced risk but not eliminated for all uses. |

---

## Risk Summary (Round 2)

| # | Finding | Severity | Round 1 Severity | Status |
|---|---------|----------|-----------------|--------|
| 1 | Symlink/TOCTOU in /tmp | -- | Critical | **Resolved** (mktemp -d) |
| 2 | PID uniqueness insufficient | -- | Major | **Resolved** (mktemp -d) |
| 3 | Silent data loss during merge | -- | Major | **Resolved** (post-merge validation) |
| 4 | Boundary validation parsing | -- | Major | **Resolved** (documented as accepted risk) |
| 5 | No fallback if worktrees unsupported | Minor | Minor | Open (unchanged) |
| 6 | Concurrent runs corrupt tracking | -- | Major | **Resolved** (run-scoped filenames) |
| 7 | Step 0 deletes active run state | -- | Major | **Resolved** (orphan-aware cleanup) |
| 8 | git status parsing fragile | Minor | Minor | Open (unchanged, deferred) |
| 9 | Force cleanup discards uncommitted | Info | Info | Closed (correct behavior) |
| 10 | Plan name not sanitized | Minor | Minor | Reduced risk (mktemp eliminates path vector) |
| 11 | RUN_ID UUOC in pipe | Minor | N/A | New — cosmetic, no action |
| 12 | WIP commit uses git add -A | Minor | N/A | New — mitigated by Step 0 clean check |
| 13 | Post-merge no size/content check | Info | N/A | New — mitigated by Step 4 review |
| 14 | Worktree branches accumulate | Info | N/A | New — pre-existing, cosmetic |

**Critical findings:** 0 (was 1)
**Major findings:** 0 (was 5)
**Minor findings:** 5 (Findings 5, 8, 10, 11, 12)
**Info findings:** 3 (Findings 9, 13, 14)

---

## Verdict Rationale

PASS. All Critical and Major findings from Round 1 have been substantively addressed in the revised plan:

1. **mktemp -d** eliminates the symlink/TOCTOU attack surface and PID collision risk (Findings 1, 2, 5/duplicate).
2. **Run-scoped tracking files** with **orphan-aware cleanup** prevent concurrent run interference (Findings 6, 7).
3. **Post-merge file existence validation** provides visibility into missing scoped files (Finding 3).
4. **Known-limitation documentation** on `awk` parsing with merge-as-primary-boundary rationale properly frames the accepted risk (Finding 4).

The remaining Minor and Info findings are refinements and technical debt items that do not affect the correctness or safety of the plan. The plan is ready for implementation.
