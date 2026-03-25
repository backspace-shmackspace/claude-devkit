# Red Team Review: /retro Skill and /ship Integration (Round 2)

**Reviewed:** 2026-03-12
**Plan:** `./plans/retro-skill-and-ship-integration.md`
**Reviewer:** Red Team (Round 2)

---

## Verdict: PASS

No Critical findings. All 7 previously identified Critical/Major issues have been adequately resolved with concrete implementation details, acceptance criteria, and test cases. Three Minor and two Info-level findings were identified in the revisions; none are blocking.

---

## Previously Identified Issues -- Resolution Status

### 1. [Critical] Archive naming inconsistency -- RESOLVED

**Previous issue:** Artifact discovery used constructed paths like `plans/archive/<name>/<name>.code-review.md`, which break when inner filenames do not match the directory name.

**Resolution:** The plan now uses glob-based discovery throughout. Step 0 explicitly discovers artifacts via `plans/archive/<feature>/*.code-review.md`, `*.qa-report.md`, and `*.test-failure.log` patterns (lines 301-304). Ship Step 7 uses the same glob approach (lines 695-699). A test case for mismatched naming is included (line 828). Acceptance criteria item 7 explicitly requires glob-based discovery. Well resolved.

### 2. [Critical] No .test-failure.log in archives -- RESOLVED

**Previous issue:** Ship Step 6 did not archive `.test-failure.log` files, making them unavailable to `/retro`.

**Resolution:** Change 2 (lines 635-647) adds conditional archival of `.test-failure.log` in Ship Step 6. The retro Step 3 subagent prompt handles the absence case gracefully: "Test failure logs may not exist for all (or any) archives" (line 437). Acceptance criteria item 16 covers this. Well resolved.

### 3. [Major] Ship Step 7 dirty working directory -- RESOLVED

**Previous issue:** Step 7 wrote to `.claude/learnings.md` without committing, leaving the working tree dirty and blocking subsequent `/ship` pre-flight checks.

**Resolution:** Step 7 now includes an auto-commit block (lines 743-749) that handles both modified files (`git diff`) and newly created files (`git ls-files --others`). Commit failure is logged but non-blocking (line 752). The rollout plan includes explicit verification: "`git status --porcelain` should be empty" (line 806). Acceptance criteria item 20 covers this. Well resolved.

### 4. [Major] Deduplication underspecified -- RESOLVED

**Previous issue:** Deduplication relied on ">80% token overlap" without defining tokenization, similarity metric, or handling of semantically equivalent but lexically different descriptions.

**Resolution:** The plan replaces the numeric threshold with structured semantic guidance (lines 121-127): match on same root cause, same actor, same category; update `Seen in:` and date if matched; create new entry if not; err on the side of new entries. This guidance is repeated in Step 4 (lines 503-506) and Ship Step 7 (lines 720-723). The risk assessment correctly identifies both false-negative and false-positive deduplication as separate risks with distinct mitigations (lines 853-854). Acceptance criteria item 30 confirms semantic guidance over numeric thresholds. Well resolved.

### 5. [Major] Subagent prompts assume uniform format -- RESOLVED

**Previous issue:** Scan subagent prompts referenced specific section headers (e.g., "## Critical Issues") that may not exist in all review artifacts.

**Resolution:** All scan subagent prompts now include explicit format-resilience language. Step 1 (lines 322-323): "Read each file in its entirety. Extract findings regardless of the specific section header format used. Look for issues categorized by severity (critical, major, minor) or described as problems, concerns, or areas for improvement." Steps 2 and 3 have equivalent language (lines 382-383, 439). Ship Step 7 includes the same (line 701). Acceptance criteria items 9 and 21 cover this. Well resolved.

### 6. [Major] "recent" scope uses filesystem mtime -- RESOLVED

**Previous issue:** `ls -td` sorts by filesystem modification time, which is unreliable across git operations, clones, and different filesystems.

**Resolution:** The "recent" scope now uses `git log --diff-filter=A --name-only` to determine recency by git commit date (lines 273-278). The `full` scope retains `ls -d` which is appropriate since it only needs enumeration, not ordering. Acceptance criteria item 6 explicitly requires git log for "recent" scope. Well resolved.

### 7. [Major] Single-feature mode always INSUFFICIENT_DATA -- RESOLVED

**Previous issue:** Verdict logic required 2+ features for recurring patterns, making single-feature mode structurally incapable of producing useful output.

**Resolution:** The verdict rules now include cross-referencing (lines 566-568): single-feature mode returns LEARNINGS_FOUND if the feature's patterns match existing entries in `.claude/learnings.md` (updating `Seen in:` counts as an update). INSUFFICIENT_DATA only fires when fewer than 2 features are analyzed AND no existing learnings file exists (line 566). Two distinct test cases cover the with-learnings and without-learnings scenarios (lines 825-826). Acceptance criteria item 14 covers this. Well resolved.

---

## New Findings

### NF-1. [Minor] "recent" scope bash pipeline has a regex that will not match git log output

**Rating: Minor**

The git log command (lines 273-278) pipes through `grep -E '^plans/archive/[^/]+/$'`, expecting paths with a trailing slash. However, `git log --name-only` outputs file paths (e.g., `plans/archive/feature-x/feature-x.code-review.md`), not directory paths. The trailing-slash grep will produce zero matches, causing "recent" scope to always find zero features.

The subsequent `sed 's|plans/archive/||;s|/||'` and `awk '!seen[$0]++'` suggest the intent is to extract unique directory names from file paths, which would work with a corrected regex like `'^plans/archive/[^/]+/'` (no `$` anchor, no trailing slash requirement). The `sed` would then strip the prefix and first slash, but would leave the filename portion, so it also needs adjustment (e.g., `sed 's|plans/archive/\([^/]*\)/.*|\1|'`).

This is an implementation-level bug in the illustrative bash snippet, not a structural plan deficiency. The intent is unambiguous and the fix is straightforward.

**Recommendation:** During implementation, test the bash pipeline against actual `git log` output for this repository. The corrected pipeline should extract directory basenames from file paths, deduplicate, and take the first 3.

### NF-2. [Minor] Step 7 auto-commit creates a second commit after the /ship commit gate

**Rating: Minor**

Ship Step 6 commits the implementation. Step 7 creates a separate `chore: update project learnings` commit. Every successful `/ship` run that produces learnings will result in two commits. Over many runs, this adds noise to git history.

This is a deliberate and acknowledged design choice -- Step 7 is post-commit, so the implementation commit is already finalized. Amending it would introduce risk (force-push implications if already pushed, potential for `--amend` to include unintended changes). The trade-off is reasonable.

**Recommendation:** No change needed for v1.0.0. If users report git-history noise as a pain point, a future enhancement could squash the learnings commit into the implementation commit via `git commit --amend --no-edit` (with appropriate safeguards).

### NF-3. [Minor] Coder prompt instructs silent application of learnings, limiting observability

**Rating: Minor**

Change 3 (line 656) instructs coders: "Do not mention the learnings file in your output -- just apply the patterns silently." This means there is no observable signal that a coder read or applied any learning. If a recurring pattern persists despite learnings existing, it is impossible to distinguish between:
- The coder ignored the learnings entirely
- The coder read them but the context was too different to apply
- The coder applied them but the issue recurred for a different reason

The reviewer prompt (Change 4, line 664) partially addresses this by asking reviewers to "reference it in your findings" when they detect a known pattern, which provides some observability. The QA prompt (Change 5) does the same. But there is a gap on the coder side.

**Recommendation:** This is acceptable for v1.0.0. Coders should not clutter implementation output with meta-commentary about learnings. The reviewer/QA cross-check provides sufficient observability. If learnings prove ineffective for coders, a future iteration could add a brief "Learnings applied: [list]" footer to coder output.

### NF-4. [Info] Full scope uses `ls -d` with grep piped to `xargs basename`, which may break on directories with spaces

**Rating: Info**

Line 280: `ls -d "$ARCHIVE_DIR"/*/ 2>/dev/null | grep -v '/sync/$' | grep -v '/audit/$' | xargs -I{} basename {}` -- if any archive directory name contains spaces (unlikely given current conventions), this pipeline will break. Current archive naming uses kebab-case so this is not a practical concern.

**Recommendation:** No action needed. Naming conventions prevent this from being an issue. If it ever matters, `find ... -print0 | xargs -0` would be the fix.

### NF-5. [Info] Acceptance criteria are comprehensive and well-aligned with revisions

**Rating: Info (positive observation)**

The 31 acceptance criteria (lines 864-894) cover all 7 previously identified issues with specific, testable items: item 6 (git log for recent), item 7 (glob-based discovery), item 9 (format-resilient prompts), item 14 (cross-reference in single-feature mode), item 16 (archive .test-failure.log), item 20 (auto-commit learnings), item 30 (semantic deduplication guidance). The test plan includes matching manual test cases. This is thorough.

---

## Summary

| Severity | Count | Details |
|----------|-------|---------|
| Critical | 0 | -- |
| Major | 0 | -- |
| Minor | 3 | Bash regex bug in illustrative snippet (NF-1), two-commit behavior (NF-2), coder observability gap (NF-3) |
| Info | 2 | Space-in-path edge case (NF-4), positive note on acceptance criteria (NF-5) |

The revised plan has addressed all 7 previously identified issues with substantive changes, not just acknowledgments. Each fix includes implementation details, is covered by at least one acceptance criterion, and has a corresponding test case. The three Minor findings are implementation-level concerns that do not require plan revision -- they should be addressed during coding. The plan is ready for implementation.
