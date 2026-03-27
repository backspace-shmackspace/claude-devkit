# Technical Implementation Plan: Auto-Commit on /dream Approval

**Feature:** Add an auto-commit step to the /dream skill so that approved (and failed) plans are automatically committed to git, preventing plan loss from `git clean`, worktree cleanup, or working directory resets.

**Version:** dream v2.2.0 -> v2.3.0

## Goals

1. Automatically commit the plan file and all review artifacts to git after the final verdict gate (Step 5) resolves.
2. Commit on both APPROVED and FAIL outcomes to prevent loss of any /dream artifacts.
3. Follow the project's conventional commit format (`feat(skills): ...` / `chore(plans): ...`).
4. Ensure commit failures do not block the verdict outcome — the plan status is the source of truth, not the git commit.

## Non-Goals

1. **Push to remote** — The commit is local only. Users push manually.
2. **Commit during revision loops** — Only the final artifacts are committed, not intermediate revisions.
3. **Commit on --fast mode differently** — The commit logic is identical regardless of `--fast`; it simply stages whatever review artifacts exist.
4. **Archive artifacts** — Archival is /ship's responsibility. /dream only commits to prevent loss.
5. **Change the plan file format** — No changes to plan structure, metadata, or status format.

## Assumptions

1. The working directory is a git repository (if not, /dream already fails in other ways since it writes to `./plans/`).
2. `git add` and `git commit` are pre-authorized in `~/.claude/settings.json` (confirmed: `git add*` and `git commit*` are in the allowlist).
3. The `./plans/` directory already exists when Step 5 runs (created by Step 2).
4. Feature-name slug (`[feature-name]`) is available from Step 2 and passed through the workflow.
5. Review artifact filenames follow the established convention: `[feature-name].redteam.md`, `[feature-name].review.md`, `[feature-name].feasibility.md`.
6. `git add` treats a nonexistent pathspec as a fatal error (exit code 128) that stages nothing — not even valid files in the same command. Files must be added individually or with existence checks.

## Proposed Design

### Overview

Add a git commit sub-step within Step 5 (Final verdict gate) of `/dream`'s SKILL.md. The commit runs after the status determination (APPROVED or FAIL) but before the output message. Both outcomes trigger a commit, with different commit message prefixes.

### Detailed Changes to Step 5

The current Step 5 flow is:

```
1. Read review artifacts
2. Determine verdict (PASS or FAIL)
3. If PASS: append "## Status: APPROVED" to plan
4. Output message
```

The new Step 5 flow becomes:

```
1. Read review artifacts
2. Determine verdict (PASS or FAIL)
3. If PASS: append "## Status: APPROVED" to plan
4. ** NEW: Pre-flight checks, stage files, commit plan + artifacts to git **
5. Output message (unchanged, with added commit confirmation line)
```

### Commit Logic (Step 5, new sub-step)

**Tool:** `Bash`

**Pre-flight checks (skip commit with warning if any fail):**

```bash
# Check 1: Detached HEAD — commits would be orphaned and lost to GC
if ! git symbolic-ref HEAD >/dev/null 2>&1; then
  echo "Warning: detached HEAD state, skipping auto-commit"
  # skip to output message
fi

# Check 2: In-progress git operation — committing could finalize a merge or corrupt a rebase
if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ] || [ -f .git/MERGE_HEAD ] || [ -f .git/CHERRY_PICK_HEAD ]; then
  echo "Warning: git operation in progress, skipping auto-commit"
  # skip to output message
fi

# Check 3: Pre-existing staged changes — warn but do not abort (pathspec commit protects against sweep)
if [ -n "$(git diff --cached --name-only)" ]; then
  echo "Note: existing staged changes detected. Auto-commit will only include plan artifacts."
fi
```

**Stage files individually and build pathspec list dynamically (each iteration tolerates missing files via `|| true`):**

```bash
PLAN_FILES=""
for f in ./plans/[feature-name].md ./plans/[feature-name].redteam.md ./plans/[feature-name].review.md ./plans/[feature-name].feasibility.md; do
  [ -f "$f" ] && git add "$f" && PLAN_FILES="$PLAN_FILES $f" || true
done
```

The `|| true` ensures the loop always exits 0 regardless of which files exist or are missing. Without it, if the last iterated file does not exist, `[ -f "$f" ]` returns 1, and any `&&` chaining after `done` would skip the commit. The `PLAN_FILES` variable accumulates only the paths that were actually staged, so the commit pathspec never references nonexistent files.

**Commit with dynamic pathspec limiting (APPROVED case):**

```bash
[ -n "$PLAN_FILES" ] && git commit -m "$(cat <<'EOF'
feat(plans): approve [feature-name] blueprint

Plan approved by /dream v2.3.0 with all review gates passed.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)" -- $PLAN_FILES
```

**Commit with dynamic pathspec limiting (FAIL case):**

```bash
[ -n "$PLAN_FILES" ] && git commit -m "$(cat <<'EOF'
chore(plans): save failed [feature-name] blueprint

Plan did not pass /dream v2.3.0 review gates. Committing artifacts for reference.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)" -- $PLAN_FILES
```

**The staging loop and commit are connected through the `PLAN_FILES` variable — if no files were staged, `PLAN_FILES` is empty and the `[ -n "$PLAN_FILES" ]` guard skips the commit:**

```bash
# Full command (APPROVED example):
PLAN_FILES=""
for f in ./plans/[feature-name].md ./plans/[feature-name].redteam.md ./plans/[feature-name].review.md ./plans/[feature-name].feasibility.md; do
  [ -f "$f" ] && git add "$f" && PLAN_FILES="$PLAN_FILES $f" || true
done
[ -n "$PLAN_FILES" ] && git commit -m "$(cat <<'EOF'
feat(plans): approve [feature-name] blueprint

Plan approved by /dream v2.3.0 with all review gates passed.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)" -- $PLAN_FILES
```

**Key design decisions:**

1. **Individual file staging with existence checks and `|| true`** — `git add` treats a nonexistent pathspec as a fatal error (exit 128) that stages nothing, even for valid files in the same command. Staging each file individually with `[ -f "$f" ]` guards ensures only existing files are staged. The `|| true` at the end of each loop iteration ensures the loop always exits 0 regardless of which files exist — without it, a missing file on the last iteration would cause the loop to exit 1 and break any downstream chaining. This is critical for `--fast` mode where `redteam.md` does not exist.

2. **Dynamic pathspec list (`PLAN_FILES` variable)** — The staging loop accumulates successfully staged paths into `PLAN_FILES`. The commit uses `-- $PLAN_FILES` instead of a hardcoded list of all four paths. This prevents `git commit` from failing with `error: pathspec '...' did not match any file(s) known to git` when a file does not exist (e.g., `redteam.md` in `--fast` mode). The `[ -n "$PLAN_FILES" ]` guard skips the commit entirely if no files were staged, preventing empty commits or committing previously staged user files.

3. **Pathspec-limited `git commit -- $PLAN_FILES`** — The `--` pathspec limits the commit to only the plan artifact paths that were actually staged, even if the user has other files staged. This prevents sweeping unrelated staged changes into the auto-commit.

4. **Pre-flight checks** — Detached HEAD would create orphan commits lost to GC (contradicting Goal #1). In-progress merge/rebase could be finalized by the commit (destructive). Both are checked before staging.

5. **Commit on FAIL too** — The user's stated problem is plan loss. Failed plans contain valuable review feedback. Committing them with a `chore(plans):` prefix (instead of `feat(plans):`) distinguishes them in git log without losing the work. The FAIL commit message uses "save" instead of "archive" to avoid semantic overlap with /ship's archive step.

6. **Non-blocking on commit failure** — If `git commit` fails (e.g., pre-commit hooks, nothing to commit because files were already tracked), the workflow warns but does not change the verdict. The plan file on disk is the source of truth.

7. **HEREDOC commit message** — Matches the pattern used by /ship's commit gate (Step 6 of ship/SKILL.md).

8. **Version bump to 2.3.0** — Minor version bump since this adds new behavior without changing existing interfaces. Follows semver convention.

### Error Handling

The commit step wraps in a conditional:

```
If pre-flight checks fail (detached HEAD, in-progress operation):
  - Skip staging and commit entirely.
  - Add to output: "⚠️ Auto-commit skipped ([reason]). Plan artifacts remain as untracked files. You can commit manually:
    git add ./plans/[feature-name].* && git commit -m 'chore(plans): save [feature-name] blueprint'"
  - Do NOT change the verdict. Do NOT stop the workflow.

If git commit succeeds:
  - Add to output: "📦 Plan and review artifacts committed to git."

If git commit fails:
  - Add to output: "⚠️ Auto-commit failed (plan artifacts remain as untracked files). You can commit manually:
    git add ./plans/[feature-name].* && git commit -m 'chore(plans): save [feature-name] blueprint'"
  - Do NOT change the verdict. Do NOT stop the workflow.
```

## Interfaces / Schema Changes

None. This change is entirely within SKILL.md's Step 5 prose. No frontmatter changes beyond the version bump. No new inputs, outputs, or external dependencies.

## Data Migration

None. Existing plans are unaffected. The change only affects future /dream runs.

## Rollout Plan

1. **Edit** `skills/dream/SKILL.md` — Add the commit sub-step to Step 5 and bump version.
2. **Validate** — Run `validate-skill skills/dream/SKILL.md` to confirm the skill still passes validation.
3. **Test** — Run a /dream session in a test project. Minimum gate: test cases 1 and 3 (APPROVED + --fast) must pass before proceeding.
4. **Update registry** — Update the version in `CLAUDE.md` skill registry table (dream row: 2.2.0 -> 2.3.0).
5. **Update CLAUDE.md** — Add a note to the Coordinator Pattern section that coordinators may perform non-blocking git commits for artifact durability.
6. **Commit** — `git add skills/dream/SKILL.md CLAUDE.md && git commit -m "feat(skills): add auto-commit to /dream approval gate"`
7. **Deploy** — `./scripts/deploy.sh dream`

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Commit fails silently, user thinks plan is saved | Low | Medium | Explicit warning message on failure; user sees "committed" or "failed" in output |
| Pre-commit hooks reject the commit | Low | Low | Non-blocking design; warn and continue |
| Working directory has staged changes from user | Medium | None | `git commit -- <paths>` pathspec limiting ensures only plan artifacts are committed; user's staged files are untouched |
| Feature-name slug not available in Step 5 | Very Low | High | The slug is derived in Step 2 and used throughout Steps 3-4; it is already available by Step 5 |
| `--fast` mode missing redteam.md causes staging or commit error | Medium | None | Files are staged individually with existence checks and `|| true`; commit pathspec is built dynamically from staged files only; missing files are excluded from both staging and commit |
| Detached HEAD creates orphan commits | Low | High | Pre-flight check detects detached HEAD and skips commit with warning |
| In-progress merge/rebase finalized by auto-commit | Low | Critical | Pre-flight check detects merge/rebase/cherry-pick state and skips commit with warning |
| Concurrent /dream runs in same worktree cause race conditions | Very Low | Medium | Not supported. Concurrent runs may interleave staging and commit, producing incorrect commits. This is a known limitation; use separate worktrees for concurrent plans. |

## Test Plan

### Manual Test Procedure

**Test command:**
```bash
cd ~/projects/claude-devkit
# Create a test project to run /dream against
mkdir -p /tmp/dream-autocommit-test && cd /tmp/dream-autocommit-test
git init && git commit --allow-empty -m "init"
# Run /dream and verify commit happens
# /dream add hello world feature
```

**Test cases:**

1. **APPROVED plan creates a commit:**
   - Run `/dream add trivial test feature`
   - Verify plan is approved
   - Run `git log --oneline -1` — should show `feat(plans): approve ...`
   - Run `git show --stat HEAD` — should list plan + review artifacts

2. **FAIL plan creates a commit:**
   - Run `/dream add intentionally vague feature` (craft input likely to fail review)
   - Verify plan fails
   - Run `git log --oneline -1` — should show `chore(plans): save failed ...`

3. **--fast mode commits without redteam.md:**
   - Run `/dream --fast add simple feature`
   - Run `git show --stat HEAD` — should list plan, review, feasibility but NOT redteam

4. **Commit failure is non-blocking:**
   - Create a git repo with a pre-commit hook that exits 1: `echo 'exit 1' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit`
   - Run `/dream add test feature`
   - Verify the plan is still written to disk and the APPROVED/FAIL status is correct
   - Verify warning message appears

5. **Pre-existing staged changes are not swept into commit:**
   - Stage an unrelated file: `echo test > unrelated.txt && git add unrelated.txt`
   - Run `/dream add test feature`
   - Verify `git show --stat HEAD` does NOT include `unrelated.txt`
   - Verify `unrelated.txt` is still staged: `git diff --cached --name-only` includes it

6. **Detached HEAD skips commit with warning:**
   - `git checkout --detach HEAD`
   - Run `/dream add test feature`
   - Verify plan is written to disk with correct status
   - Verify warning about detached HEAD appears
   - Verify no orphan commit was created

7. **In-progress merge skips commit with warning:**
   - Create a merge conflict state
   - Run `/dream add test feature`
   - Verify warning about in-progress operation appears
   - Verify merge state is not finalized

8. **Validation passes:**
   - `validate-skill ~/projects/claude-devkit/skills/dream/SKILL.md` — exit code 0

### Validation Command

```bash
cd ~/projects/claude-devkit && python3 generators/validate_skill.py skills/dream/SKILL.md
```

## Acceptance Criteria

1. After `/dream` approves a plan, `git log --oneline -1` shows a commit with the plan and review artifact files.
2. After `/dream` fails a plan, `git log --oneline -1` shows a commit with `chore(plans):` prefix.
3. The commit message follows conventional commit format and includes `Co-Authored-By`.
4. If git commit fails, the plan verdict is unchanged (APPROVED stays APPROVED, FAIL stays FAIL).
5. If git commit fails, a warning message is displayed to the user.
6. `validate-skill skills/dream/SKILL.md` passes with exit code 0.
7. The version in SKILL.md frontmatter is `2.3.0`.
8. The version in CLAUDE.md skill registry is updated to `2.3.0`.
9. In `--fast` mode, the commit only includes artifacts that exist (no redteam.md).
10. Pre-existing staged changes are not included in the auto-commit (pathspec-limited commit).
11. Detached HEAD state skips the commit with a warning (no orphan commits).
12. In-progress git operations (merge, rebase, cherry-pick) skip the commit with a warning.

## Task Breakdown

### Files to Modify

| # | File | Change |
|---|------|--------|
| 1 | `skills/dream/SKILL.md` | Add auto-commit sub-step in Step 5; bump version 2.2.0 -> 2.3.0 |
| 2 | `CLAUDE.md` | Update dream version in Skill Registry table: 2.2.0 -> 2.3.0; add "auto-commits artifacts on verdict" to description; add note to Coordinator Pattern that coordinators may perform non-blocking git commits for artifact durability |

### Files to Create

None.

### Detailed Task List

**Task 1: Modify `skills/dream/SKILL.md`**

1.1. Update frontmatter version from `2.2.0` to `2.3.0`.

1.2. In Step 5 (Final verdict gate), after the PASS block that appends `## Status: APPROVED`, add a new sub-section for the git commit. Insert the following between the "append APPROVED" action and the "Output" line:

```markdown
**Auto-commit plan and review artifacts:**

Tool: `Bash`

Pre-flight checks — skip commit with warning if any fail:

1. Detached HEAD check: `git symbolic-ref HEAD >/dev/null 2>&1` — if this fails, HEAD is detached and commits would be orphaned.
2. In-progress operation check: test for `.git/rebase-merge`, `.git/rebase-apply`, `.git/MERGE_HEAD`, or `.git/CHERRY_PICK_HEAD` — if any exist, committing could finalize or corrupt the operation.
3. Pre-existing staged changes: if `git diff --cached --name-only` is non-empty, log a note but continue (pathspec commit protects against sweep).

Stage files individually with existence checks and build dynamic pathspec list (do NOT use a single `git add` with all paths — nonexistent paths cause fatal exit 128 and stage nothing; use `|| true` so the loop always exits 0 regardless of which files exist):

```bash
PLAN_FILES=""
for f in ./plans/[feature-name].md ./plans/[feature-name].redteam.md ./plans/[feature-name].review.md ./plans/[feature-name].feasibility.md; do
  [ -f "$f" ] && git add "$f" && PLAN_FILES="$PLAN_FILES $f" || true
done
```

Commit only if files were staged, using the dynamic pathspec list (do NOT hardcode all four paths — nonexistent paths in the pathspec cause `git commit` to fail with exit 1). Use `--` pathspec to limit commit to plan files only (do not sweep user's staged changes):

If APPROVED:
```bash
[ -n "$PLAN_FILES" ] && git commit -m "$(cat <<'EOF'
feat(plans): approve [feature-name] blueprint

Plan approved by /dream v2.3.0 with all review gates passed.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)" -- $PLAN_FILES
```

If FAIL:
```bash
[ -n "$PLAN_FILES" ] && git commit -m "$(cat <<'EOF'
chore(plans): save failed [feature-name] blueprint

Plan did not pass /dream v2.3.0 review gates. Committing artifacts for reference.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)" -- $PLAN_FILES
```

If git commit succeeds: append to output: "📦 Plan and review artifacts committed to git."

If pre-flight checks fail or git commit fails: append to output: "⚠️ Auto-commit skipped/failed ([reason]). Files remain on disk. Commit manually: `git add ./plans/[feature-name].* && git commit -m 'chore(plans): save [feature-name] blueprint'`"

Do NOT change the verdict based on commit success or failure.
```

1.3. Move the FAIL block's commit logic to also trigger before the FAIL output message (same staging and commit commands, different commit message prefix).

**Task 2: Update `CLAUDE.md`**

2.1. In the Skill Registry table, update dream row:
- Version: `2.2.0` -> `2.3.0`
- Description: Add "Auto-commits artifacts on verdict." to the end of the Purpose cell.

2.2. In the Coordinator Pattern section, add a note: "Coordinators may perform non-blocking git commits for artifact durability (e.g., /dream auto-commits plan artifacts after verdict)."

## Context Alignment

### CLAUDE.md Patterns Followed

- **Coordinator pattern:** This change preserves the coordinator archetype; it adds a tool invocation (Bash for git) within the existing Step 5, consistent with how /ship uses Bash for git operations in its commit gate.
- **Conventional commits:** Commit messages use `feat(plans):` and `chore(plans):` prefixes, matching the project's documented format in CLAUDE.md.
- **Tool permissions:** `git add*` and `git commit*` are already in the pre-authorized allowlist, so no permission changes are needed.
- **Verdict gates:** The commit step does not alter verdict logic; PASS/FAIL determination remains unchanged.
- **Edit source, not deployment:** The change targets `skills/dream/SKILL.md` (source), not `~/.claude/skills/dream/SKILL.md` (deployment).
- **Update registry:** CLAUDE.md registry is updated alongside the skill change.

### Prior Plans This Relates To

- **ship-always-worktree.md** — That plan addressed structural isolation for /ship. This plan addresses a related durability concern for /dream: artifacts created before /ship runs were vulnerable to loss. The auto-commit bridges the gap.
- **journal-skill-blueprint.md** — Established the pattern of skills writing artifacts and committing them (journal entries are committed automatically). This plan brings similar durability to /dream artifacts.

### Deviations from Established Patterns

- **New behavior: /dream now writes to git.** Previously, only /ship and /sync performed git writes. This is justified because /dream's artifacts are the primary input to /ship, and losing them defeats the purpose of the planning workflow. The git write is minimal (add + commit, no push) and non-blocking on failure.
- **Auto-commit in a core coordinator skill is a new pattern.** The journal-skill-blueprint.md precedent established auto-commit for a contrib/pipeline skill, not a core coordinator. Bringing git-write behavior into a core coordinator is a broader pattern expansion. This is documented as an intentional evolution: coordinator skills that produce durable artifacts (plans, blueprints) benefit from the same commit-for-durability pattern. The Coordinator Pattern section in CLAUDE.md will be updated to reflect this (see Task 2.2 in Rollout Plan).

## Status: APPROVED

<!-- Context Metadata
discovered_at: 2026-02-24T22:20:00Z
claude_md_exists: true
recent_plans_consulted: journal-review-skill.md, ship-always-worktree.md, journal-skill-blueprint.md
archived_plans_consulted: none
-->
