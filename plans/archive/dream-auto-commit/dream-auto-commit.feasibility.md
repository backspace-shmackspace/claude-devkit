# Feasibility Review (Round 3): Auto-Commit on /dream Approval

**Plan:** `dream-auto-commit.md`
**Reviewer:** code-reviewer (feasibility gate, round 3)
**Date:** 2026-02-24
**Prior reviews:** Round 1 FAIL (C1, M1), Round 2 FAIL (N1, N2)

## Verdict: PASS

The revised plan correctly resolves both Major defects from Round 2 (N1 and N2). The bash logic is correct end-to-end. No new issues were introduced. The design integrates cleanly with the current SKILL.md Step 5 structure.

---

## Round 2 Resolution Status

### N1 (for-loop exit code order-dependent): RESOLVED

The loop body now uses `|| true` (lines 88, 126):

```bash
[ -f "$f" ] && git add "$f" && PLAN_FILES="$PLAN_FILES $f" || true
```

This ensures the loop always exits 0 regardless of which files exist or in what order they are iterated. The `|| true` absorbs all three failure modes:
- `[ -f "$f" ]` returns 1 (file does not exist)
- `git add "$f"` fails (unlikely but possible)
- The entire `&&` chain short-circuits at any point

The loop exit code is now deterministic (always 0) rather than dependent on whether the last-iterated file exists. Verified correct.

### N2 (hardcoded pathspecs in git commit): RESOLVED

The plan now builds a dynamic `PLAN_FILES` variable in the staging loop and uses it in the commit:

```bash
PLAN_FILES=""
for f in ./plans/[feature-name].md ...; do
  [ -f "$f" ] && git add "$f" && PLAN_FILES="$PLAN_FILES $f" || true
done
[ -n "$PLAN_FILES" ] && git commit -m "..." -- $PLAN_FILES
```

Key properties verified:
1. Only files that pass both `[ -f ]` and `git add` are added to `PLAN_FILES`.
2. In `--fast` mode, `redteam.md` does not exist, so it is excluded from `PLAN_FILES` and the commit pathspec never references it.
3. The `[ -n "$PLAN_FILES" ]` guard prevents a commit when no files were staged (e.g., all files missing, or all `git add` calls fail).
4. The commit pathspec `-- $PLAN_FILES` contains only paths that were actually staged.

The plan also includes clear documentation of why the dynamic list is necessary (lines 92, 140-142), including the explanation that `git commit` treats nonexistent pathspecs as fatal errors (exit 1).

---

## End-to-End Bash Logic Verification

Traced the full command sequence for all three execution paths:

### Path A: APPROVED, all four files exist (normal mode)

1. Pre-flight checks pass (on a branch, no in-progress operations).
2. Loop iterates four files; all pass `[ -f ]`; all are staged; `PLAN_FILES` = all four paths.
3. `[ -n "$PLAN_FILES" ]` is true; commit runs with `feat(plans):` message and `-- $PLAN_FILES`.
4. Result: commit contains all four artifacts. Correct.

### Path B: APPROVED, three files exist (--fast mode, no redteam.md)

1. Pre-flight checks pass.
2. Loop iterates four files; `redteam.md` fails `[ -f ]`; `|| true` absorbs the failure; `PLAN_FILES` = three paths.
3. `[ -n "$PLAN_FILES" ]` is true; commit runs with three-path pathspec.
4. Result: commit contains plan + review + feasibility. Correct.

### Path C: FAIL, commit failure is non-blocking

1. Pre-flight checks pass.
2. Loop stages files; `PLAN_FILES` is populated.
3. `git commit` fails (e.g., pre-commit hook rejects).
4. Verdict remains FAIL (commit failure does not alter verdict per Goal 4).
5. Warning message displayed with manual commit instructions.
6. Result: plan on disk is correct, user is informed. Correct.

### Path D: Detached HEAD or in-progress operation

1. Pre-flight check fails; commit is skipped entirely.
2. No staging occurs, no commit attempted.
3. Warning message displayed.
4. Result: no orphan commits, no corrupted rebase/merge state. Correct.

### Path E: No files exist at all (edge case)

1. Loop iterates; no files pass `[ -f ]`; `PLAN_FILES` remains empty.
2. `[ -n "$PLAN_FILES" ]` is false; commit is skipped.
3. Result: no empty commit, no error. Correct.

---

## Unquoted $PLAN_FILES Assessment

The `$PLAN_FILES` variable is intentionally unquoted in `-- $PLAN_FILES` to allow word splitting into separate pathspec arguments. This is safe because:

- File paths are under `./plans/[feature-name].md` where `[feature-name]` is a slug constrained to lowercase alphanumeric + hyphen (Step 2, feature-name rules).
- No spaces, glob characters, or special characters can appear in these paths.
- The `./plans/` prefix is a literal with no spaces.

If the slug constraints were ever relaxed to allow spaces, this would break. But that is outside the scope of this plan and would require changes throughout the entire skill.

---

## Integration with Current SKILL.md

The current Step 5 (SKILL.md lines 207-226) has this structure:

```
1. Read review artifacts
2. Determine verdict
3. If PASS: append "## Status: APPROVED"
4. Output message
```

The plan inserts the auto-commit block between steps 3 and 4, which is the correct insertion point:
- The plan file already has its final content (APPROVED status appended) before the commit.
- The output message can include the commit confirmation/failure line.
- The FAIL path also commits before outputting the failure message.

No conflicts with existing Step 5 logic. The insertion is additive and does not modify any existing behavior.

---

## Items Verified as Correct (carried forward from Round 2)

1. **Pre-flight checks**: Detached HEAD detection via `git symbolic-ref HEAD`, in-progress operation detection via `.git/` directory checks. Sound.
2. **Pathspec-limited commit**: `-- $PLAN_FILES` prevents sweeping pre-staged user files.
3. **HEREDOC commit message**: `cat <<'EOF'` prevents variable expansion. Matches /ship pattern.
4. **Non-blocking error handling**: Commit failure does not change verdict. Manual instructions provided.
5. **Version bump 2.2.0 -> 2.3.0**: Correct semver.
6. **Test plan**: All 8 test cases cover the relevant scenarios, including --fast mode (test 3), commit failure (test 4), pre-staged files (test 5), detached HEAD (test 6), and in-progress merge (test 7).
7. **Context alignment**: Pattern expansion documented with CLAUDE.md updates planned.

---

## Concerns

None. All prior defects have been resolved. The bash logic is correct and handles all execution paths. The design integrates cleanly with the existing skill.

---

## Summary

Three rounds of review have produced a sound implementation plan. Round 1 identified fundamental issues with `git add` and `git commit` handling of nonexistent paths. Round 2 confirmed those fixes but found two new defects in the loop exit code and commit pathspec. Round 3 confirms both N1 and N2 are properly resolved: the `|| true` ensures the loop always exits 0, and the dynamic `PLAN_FILES` variable ensures the commit pathspec only references files that actually exist and were staged. The plan is ready for implementation.
