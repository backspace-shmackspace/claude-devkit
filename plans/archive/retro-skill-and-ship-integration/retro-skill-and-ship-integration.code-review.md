# Code Review: /retro Skill and /ship Integration

**Plan:** `plans/retro-skill-and-ship-integration.md`
**Files reviewed:**
- `skills/retro/SKILL.md` (new)
- `skills/ship/SKILL.md` (modified — Changes 1-6)
- `CLAUDE.md` (modified — Changes 7-8)

---

## Verdict: PASS

No Critical or Major findings. The implementation matches the plan faithfully and the new capability is well-constructed.

---

## Critical Findings

None.

---

## Major Findings

None.

---

## Minor Findings

### 1. `retro/SKILL.md` Step 0 — shell script has an unset `$SCOPE` variable

The bash snippet in Step 0 references `$SCOPE` but the skill instructs the coordinator (the LLM) to determine scope conceptually. The bash block reads:

```bash
if [ "$SCOPE" = "recent" ]; then
```

`$SCOPE` is never exported or assigned in the same bash invocation. In practice the coordinator reads this as prose guidance and expands the variable itself before running the command, which is the correct interpretation for a skill. However, the snippet would fail verbatim if a developer tried to run it directly. A comment clarifying that `SCOPE` must be set by the coordinator before invoking this block (e.g., `# Coordinator sets SCOPE from $ARGUMENTS before this block runs`) would remove the ambiguity.

**Recommendation:** Add a one-line comment: `# SCOPE is set by the coordinator from $ARGUMENTS (e.g., SCOPE=recent)` at the top of the bash block.

### 2. `retro/SKILL.md` Step 0 — `wc -w` word count is fragile for feature names containing spaces

```bash
FEATURE_COUNT=$(echo "$FEATURES" | wc -w | tr -d ' ')
```

If any feature directory name contained a space (unlikely but possible), `wc -w` would miscount. The plan's `Seen in:` list format also uses comma-separated feature names, so this is low-risk in practice. A more robust approach would use `wc -l` after ensuring one feature per line, or count with `awk 'END{print NR}'`.

**Recommendation:** Change to `FEATURE_COUNT=$(echo "$FEATURES" | grep -c .)` or use newline-delimited features throughout and count with `wc -l`.

### 3. `ship/SKILL.md` Step 7 auto-commit — `git diff --name-only` checks unstaged changes only

The Step 7 auto-commit check is:

```bash
if git diff --name-only -- .claude/learnings.md | grep -q .; then
```

`git diff` without `--cached` shows unstaged working-directory changes. If the Task subagent staged changes with `git add` internally (which subagents should not do), the check would miss them. The intent is correct for the expected usage pattern (subagent writes the file, coordinator stages and commits), but the comment on this line explaining why `--cached` is not used would help a future reader.

This is low-risk because the `elif` branch handles the new-file case separately.

**Recommendation:** Add a comment: `# checks working directory changes (subagent writes file; coordinator stages below)`.

### 4. `retro/SKILL.md` Step 0 — `ls -d "$ARCHIVE_DIR"/*/` in the `full` scope branch is not git-aware

```bash
FEATURES=$(ls -d "$ARCHIVE_DIR"/*/ 2>/dev/null | grep -v '/sync/$' | grep -v '/audit/$' | xargs -I{} basename {})
```

This discovers directories by filesystem presence, not git history. A directory created locally but not yet committed would be included. The `recent` branch correctly uses `git log --diff-filter=A`, but `full` does not. This creates a minor inconsistency in the semantics of "full" (filesystem-based) vs. "recent" (git-history-based). For most users running against a clean repo this is harmless.

**Recommendation:** Document this difference with a comment in the script: `# 'full' mode uses filesystem discovery; 'recent' uses git history`. Optionally, align `full` to git: `git log --diff-filter=A --name-only --format='' -- "$ARCHIVE_DIR"/*/ | grep -E '^plans/archive/[^/]+/$' | ... | sort -u`.

### 5. `ship/SKILL.md` Step 5a — WIP commit message still says `v3.3.0`

In the revision loop setup:

```bash
git commit -m "WIP: ship v3.3.0 first-pass implementation (pre-revision)"
```

The skill is now version 3.4.0. This message will be stale in git history immediately.

**Recommendation:** Update the commit message to reference `v3.4.0`: `"WIP: ship v3.4.0 first-pass implementation (pre-revision)"`.

### 6. `CLAUDE.md` — `retro` artifacts not listed in the Artifact Locations tree

The plan (Change 8) specifies adding retro artifact entries to the Artifact Locations section. The skill registry table was correctly updated, but the `./plans/` directory tree under "Artifact Locations" does not show the new `retro-[timestamp].*` entries or the `plans/archive/retro/` directory. The plan required both additions.

**Recommendation:** Add the following to the Artifact Locations tree in CLAUDE.md under `./plans/`:

```
├── retro-[timestamp].coder-scan.md
├── retro-[timestamp].reviewer-scan.md
├── retro-[timestamp].test-scan.md
├── retro-[timestamp].summary.md
└── archive/
    ├── retro/
    │   └── retro-[timestamp]/
```

And add a note beneath the tree: `.claude/learnings.md` -- Project-level learnings (lives outside `./plans/`, created by `/retro` and `/ship` Step 7).

This is a documentation gap, not a functional gap, so it does not change the PASS verdict, but it should be fixed before the next `/sync` run to avoid a stale CLAUDE.md.

---

## Positives

**Strong plan fidelity.** The implementation matches the plan specification closely across all three files. The detailed plan made verification straightforward — every step, prompt, and bash block is present and faithful to the design.

**Non-blocking Step 7 is correctly implemented.** The `ship/SKILL.md` Step 7 non-blocking contract is correctly enforced: the failure path outputs a degraded message and explicitly states the Step 6 commit is unaffected. The auto-commit bash correctly checks both modified and new-file cases with the `elif` branch.

**Format-resilient prompts.** Steps 1-3 of `retro/SKILL.md` explicitly instruct the scan subagents to "extract findings regardless of the specific section header format used." This is an important design choice given that archived code review files may have varying structures. The same language appears in the Step 7 prompt in ship. Well done.

**Severity ratings throughout.** The plan requires severity-rated findings (Critical/High/Medium/Low), and the implementation includes severity in every output format: scan report templates, learnings entries, and the Step 7 extraction task. Consistent execution.

**Deduplication semantics are precise.** The "Seen in:" update-vs-append logic is stated clearly in both the `/retro` synthesis step and the `/ship` Step 7 prompt. The "err on the side of creating new entries" guidance aligns with the plan's stated preference and avoids incorrect merges.

**Version bump and step count correctly updated.** `ship` frontmatter shows `3.4.0`, the CLAUDE.md registry correctly shows `8` steps (7 numbered steps + shared Step 0), and the description is updated to include "Retro capture" and "Learnings consumption."

**Worktree path in Step 3c learnings prompt is scoped correctly.** The coder learnings instruction is placed inside the worktree coder prompt, after the hard rules, so it does not interfere with the scope or file path constraints. The instruction to "not mention the learnings file in your output" is a clean UX touch.

**`test-failure.log` archive (Change 2) is correctly conditional.** The `if [ -f ... ]` guard ensures the archive step does not fail on runs with no test failures. The placement in Step 6 ensures the log is available to Step 7's Task subagent.

---

## Recommendations (priority order)

1. Fix the stale `v3.3.0` reference in the Step 5a WIP commit message in `ship/SKILL.md`. This is a one-line change with no functional impact but leaves misleading git history on every revision-loop run.

2. Add the missing retro artifact entries to the CLAUDE.md Artifact Locations tree (Change 8 from the plan). The skill registry table is present; the artifact tree is the missing half of the required change.

3. Add a comment in the Step 0 bash block clarifying that `$SCOPE` is set by the coordinator before the block runs.

4. Optionally document the `full`-mode filesystem vs. `recent`-mode git-history inconsistency in a comment.

Items 3 and 4 are polish-level. Items 1 and 2 are the only changes worth making before deploying.
