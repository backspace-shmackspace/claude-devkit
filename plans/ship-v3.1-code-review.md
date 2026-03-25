# Code Review: /ship Skill v3.0.0 → v3.1.0

**Reviewed:** 2026-02-23
**Reviewer:** code-reviewer agent
**Scope:** Worktree isolation implementation for parallel work groups

---

## Code Review Summary

The v3.1.0 update adds git worktree isolation for parallel work groups, enabling true concurrent coder execution without file conflicts. The implementation introduces 6 new substeps (2a-2f) with proper validation gates, cleanup handlers, and fallback paths. While the overall architecture is sound, there are several critical bash scripting issues that must be addressed before deployment, including unsafe variable expansion, missing error handling, and potential race conditions.

---

## Critical Issues (Must Fix)

### 1. **Unsafe Variable Expansion in Step 2b**

**Location:** Step 2b — Create Worktrees (lines 125-146)

**Issue:** The script uses unquoted variables and placeholder syntax that will break during execution:

```bash
PLAN_NAME="[name]"  # from Step 1
WG_NUM="1"  # work group number (1, 2, 3, ...)
WG_NAME="[group-name]"  # from work group definition
```

**Why Critical:** These are literal strings, not actual variables. The coordinator will create worktrees with literal `[name]` in paths, causing failures and orphaned worktrees.

**Fix Required:**
```bash
# These should be template instructions, not executable code
# Option A: Add explicit coordinator instruction
# "Replace [name] with the plan name from Step 1, [group-name] with the work group name from the plan"

# Option B: Show proper variable usage
PLAN_NAME="${name}"  # derived in Step 1
WG_NUM="${work_group_index}"  # loop counter
WG_NAME="${work_group_name}"  # parsed from plan
```

**Impact:** Without this fix, all worktree operations will fail catastrophically.

---

### 2. **File Boundary Validation Has False Positives**

**Location:** Step 2d — File Boundary Validation (lines 197-229)

**Issue 1 — Word Boundary Matching:**
```bash
if ! echo "$scoped_files" | grep -qw "$file"; then
```

The `-w` flag matches word boundaries, which breaks for file paths:
- `scoped_files="src/types.ts src/utils.ts"`
- `file="src/types.ts"` → **MATCH** ✅
- `file="types.ts"` → **NO MATCH** ❌ (false violation if file is shortened)

**Issue 2 — Scoped Files Format Unclear:**
How is `$scoped_files` formatted in `.ship-worktrees.tmp`? Space-separated? Comma-separated? Line-separated?

If it's `"file-a.ts file-b.ts"` and `$file` is `src/file-a.ts`, grep will fail.

**Fix Required:**
```bash
# Normalize paths and use exact matching
# Assume scoped_files is space-separated list
FOUND=0
for scoped in $scoped_files; do
  # Normalize both paths (remove leading ./)
  normalized_file=$(echo "$file" | sed 's|^\./||')
  normalized_scoped=$(echo "$scoped" | sed 's|^\./||')

  if [ "$normalized_file" = "$normalized_scoped" ]; then
    FOUND=1
    break
  fi
done

if [ $FOUND -eq 0 ]; then
  VIOLATIONS="${VIOLATIONS}Work Group $wg_num ($wg_name) modified $file (not in scope)\n"
fi
```

**Impact:** False positives will stop valid implementations. False negatives will allow scope violations.

---

### 3. **Missing Error Handling in Worktree Creation**

**Location:** Step 2b (line 143)

**Issue:**
```bash
git worktree add "$WORKTREE_PATH" HEAD
```

No check if this succeeds. If it fails (e.g., path already exists, disk full, git errors), the script continues and writes bad data to `.ship-worktrees.tmp`.

**Fix Required:**
```bash
if ! git worktree add "$WORKTREE_PATH" HEAD 2>/dev/null; then
  echo "❌ Failed to create worktree at $WORKTREE_PATH"
  echo "Possible causes: path exists, disk full, git locked"
  # Cleanup any partial worktrees
  rm -f .ship-worktrees.tmp
  exit 1
fi
```

**Impact:** Silent failures lead to undefined behavior in subsequent steps.

---

### 4. **Race Condition in Scoped Files Array**

**Location:** Step 2b (line 145)

**Issue:**
```bash
echo "$WORKTREE_PATH|$WG_NUM|$WG_NAME|[scoped-files]" >> .ship-worktrees.tmp
```

The `[scoped-files]` placeholder is not defined. How is this populated? If the coordinator is supposed to substitute this, there's no instruction.

**Also:** If multiple worktrees are created in parallel (though unlikely given sequential bash), appending to the same file without locking could corrupt the file.

**Fix Required:**
```bash
# Explicitly document the scoped files format
# Example: "src/components/Button.tsx src/components/Icon.tsx"
SCOPED_FILES_STR=$(echo "${work_group_files[@]}" | tr '\n' ' ')
echo "$WORKTREE_PATH|$WG_NUM|$WG_NAME|$SCOPED_FILES_STR" >> .ship-worktrees.tmp
```

**Impact:** Undefined behavior. Step 2d cannot validate without knowing scoped files.

---

### 5. **Modified File Detection Logic is Fragile**

**Location:** Step 2d (lines 207-214)

**Issue:**
```bash
if git rev-parse HEAD~1 >/dev/null 2>&1; then
  MODIFIED=$(git diff --name-only HEAD~1 HEAD)
else
  MODIFIED=$(git diff --name-only --cached)
fi
```

**Problem 1:** Assumes files are committed or staged in the worktree. If the coder uses Edit/Write tools (which modify working directory), files won't show up in `--cached`.

**Problem 2:** If HEAD~1 doesn't exist (initial commit), falls back to `--cached`, which is a completely different set of files.

**Fix Required:**
```bash
# Check for any changes in working directory and index
MODIFIED=$(git diff --name-only HEAD 2>/dev/null || git ls-files --others --exclude-standard)

# Alternative: Use git status porcelain
MODIFIED=$(git status --porcelain | awk '{print $2}')
```

**Impact:** Coders can violate file boundaries undetected if they don't stage changes.

---

### 6. **Cleanup Failure is Silent**

**Location:** Step 2f (lines 280-286)

**Issue:**
```bash
git worktree remove "$wt_path" --force 2>/dev/null || \
  echo "Warning: Failed to remove worktree at $wt_path (run 'git worktree prune' manually)"
```

**Problem:** If cleanup fails but workflow continues, orphaned worktrees in `/tmp` accumulate. On long-running systems (servers, CI agents), this causes:
- Disk space exhaustion
- Git worktree list pollution
- Confusion about active worktrees

**Fix Required:**
```bash
CLEANUP_FAILURES=0

while IFS='|' read -r wt_path wg_num wg_name scoped_files; do
  if ! git worktree remove "$wt_path" --force 2>/dev/null; then
    echo "⚠️  Failed to remove worktree: $wt_path"
    CLEANUP_FAILURES=$((CLEANUP_FAILURES + 1))
  fi
done < .ship-worktrees.tmp

if [ $CLEANUP_FAILURES -gt 0 ]; then
  echo "⚠️  $CLEANUP_FAILURES worktree(s) failed to clean up. Run:"
  echo "    git worktree prune"
  echo "    rm -rf /tmp/ship-*"
fi

rm -f .ship-worktrees.tmp .ship-violations.tmp
```

**Impact:** Resource leaks on repeated failures.

---

## Major Improvements (Should Fix)

### 7. **Shared Dependencies Commit Message is Unclear**

**Location:** Step 2a (line 128)

**Issue:**
```bash
git commit -m "tmp: ship shared deps - base for worktrees"
```

This temporary commit will appear in `git log` if the workflow fails between Step 2a and Step 5. Users will see cryptic "tmp:" commits.

**Recommendation:**
```bash
git commit -m "WIP: /ship shared dependencies for [feature-name]

This is a temporary commit that will be squashed with the final implementation.
Created by: /ship skill v3.1.0"
```

**Impact:** Better debugging and git history hygiene.

---

### 8. **No Validation That Worktrees Were Actually Created**

**Location:** Between Step 2b and Step 2c

**Issue:** If Step 2b fails to create worktrees but doesn't exit (e.g., warning instead of error), Step 2c dispatches coders to non-existent paths.

**Recommendation:**
```bash
# After Step 2b, before Step 2c
if [ ! -f .ship-worktrees.tmp ] || [ ! -s .ship-worktrees.tmp ]; then
  echo "❌ No worktrees were created. Check Step 2b output."
  exit 1
fi

# Count worktrees
EXPECTED_COUNT=$(grep -c "^### Work Group" "$ARGUMENTS")  # from plan
ACTUAL_COUNT=$(wc -l < .ship-worktrees.tmp)

if [ "$ACTUAL_COUNT" -ne "$EXPECTED_COUNT" ]; then
  echo "⚠️  Expected $EXPECTED_COUNT worktrees, created $ACTUAL_COUNT"
fi
```

**Impact:** Fail fast instead of cascading failures.

---

### 9. **Worktree Merge is Not Atomic**

**Location:** Step 2e (lines 258-269)

**Issue:** Files are copied one at a time. If the process is interrupted (crash, timeout, Ctrl+C), the main directory is in a partially merged state.

**Recommendation:**
```bash
# Use a staging directory for atomic merge
MERGE_STAGING=$(mktemp -d)

while IFS='|' read -r wt_path wg_num wg_name scoped_files; do
  for file in $scoped_files; do
    if [ -f "$wt_path/$file" ]; then
      mkdir -p "$MERGE_STAGING/$(dirname "$file")"
      cp "$wt_path/$file" "$MERGE_STAGING/$file"
    fi
  done
done < .ship-worktrees.tmp

# Atomic move
rsync -a "$MERGE_STAGING/" "$MAIN_DIR/"
rm -rf "$MERGE_STAGING"
```

**Impact:** Prevents corrupt state on interruption.

---

### 10. **Step 4a Revision Loop Lacks Context**

**Location:** Step 4a (lines 370-379)

**Issue:** When re-running worktree workflow in revision loop, the prompt says:
```
"Address all Critical and Major findings within your worktree at {WORKTREE_PATH}."
```

But the code review is written for the **merged** files in the main directory. The paths won't match worktree paths.

**Recommendation:**
```
"Read the code review at `./plans/[name].code-review.md`.
Address all Critical and Major findings.

**IMPORTANT:** Your code review references files in the main directory (e.g., src/Button.tsx).
You are working in a worktree at {WORKTREE_PATH}.
Translate paths: src/Button.tsx → {WORKTREE_PATH}/src/Button.tsx

Do not change anything else.
Read `.claude/agents/` to find the coder agent and follow its standards."
```

**Impact:** Coders may be confused or unable to find files mentioned in review.

---

### 11. **No Disk Space Check Before Creating Worktrees**

**Location:** Step 2b (before worktree creation)

**Issue:** Git worktrees are full repository copies. Creating N worktrees for a large repo (e.g., 500MB × 3 = 1.5GB in `/tmp`) can fill disk.

**Recommendation:**
```bash
# Check available space in /tmp
AVAILABLE_KB=$(df /tmp | tail -1 | awk '{print $4}')
REQUIRED_KB=$((500000 * NUM_WORK_GROUPS))  # estimate 500MB per worktree

if [ $AVAILABLE_KB -lt $REQUIRED_KB ]; then
  echo "⚠️  Low disk space in /tmp: ${AVAILABLE_KB}KB available, ~${REQUIRED_KB}KB needed"
  echo "Consider cleaning /tmp or using a different WORKTREE_PATH"
fi
```

**Impact:** Prevent disk full errors mid-workflow.

---

### 12. **Timestamp Collision Risk**

**Location:** Step 2b (line 136)

**Issue:**
```bash
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
```

If two work groups are created in the same second (likely in testing), paths collide.

**Recommendation:**
```bash
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")-$$  # append PID
# or
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S-%N")  # nanoseconds (Linux only)
```

**Impact:** Rare but catastrophic if it occurs.

---

## Minor Suggestions (Consider)

### 13. **Hard-Coded /tmp Path**

**Location:** Step 2b (line 141)

**Issue:** `/tmp` may not be ideal on all systems (e.g., small tmpfs, cleared on reboot).

**Suggestion:**
```bash
WORKTREE_BASE="${WORKTREE_BASE:-/tmp}"  # allow override via env var
WORKTREE_PATH="$WORKTREE_BASE/ship-${PLAN_NAME}-wg${WG_NUM}-${TIMESTAMP}"
```

**Benefit:** Flexibility for users with large codebases.

---

### 14. **Verbose Output Could Be Clearer**

**Location:** Step 2b output (line 148)

**Issue:**
```
"✓ Created worktree for Work Group N: [group-name] at $WORKTREE_PATH"
```

**Suggestion:**
```
"✓ Created worktree for Work Group 1: Authentication
   Path: /tmp/ship-add-auth-wg1-20260223-143052
   Files: src/auth.ts, src/middleware.ts"
```

**Benefit:** Easier to debug and verify.

---

### 15. **No Mention of Worktree Limitations**

**Issue:** Git worktrees have limitations:
- Cannot check out the same branch in multiple worktrees
- Lock files can interfere with parallel operations
- Some git commands behave differently in worktrees

**Suggestion:** Add a note in Step 2 introduction:

```markdown
**Worktree Limitations:**
- Each worktree is on a detached HEAD (not a branch)
- If coders attempt git operations (commit, branch), they may see unexpected behavior
- Worktrees share the same .git directory (parallel git operations may conflict)
```

**Benefit:** Set correct expectations.

---

### 16. **Cleanup Could Be More Robust**

**Location:** Step 2f (line 286)

**Suggestion:**
```bash
# Additional cleanup for edge cases
rm -f .ship-worktrees.tmp .ship-violations.tmp BLOCKED.md

# Clean orphaned worktrees from previous runs
find /tmp -maxdepth 1 -name "ship-*-wg*" -type d -mtime +1 -exec git worktree remove {} --force \; 2>/dev/null || true
```

**Benefit:** Handle aborted runs and stale worktrees.

---

## What Went Well

### ✅ Backward Compatibility
The single work group path (no worktrees) is unchanged. Existing plans continue to work without modification.

### ✅ Clear Separation of Concerns
Each substep (2a-2f) has a single responsibility: create, dispatch, validate, merge, cleanup. Easy to reason about.

### ✅ Proper Verdict Gates
Step 2d validates file boundaries before merging. This prevents scope violations from polluting the main directory.

### ✅ Graceful Degradation
If cleanup fails, the workflow continues. Orphaned worktrees are annoying but not catastrophic.

### ✅ Explicit Worktree Paths in Prompts
Coders are told **exactly** where they're working (`{WORKTREE_PATH}`), reducing confusion.

### ✅ Revision Loop Handles Worktrees
Step 4a correctly re-creates worktrees for revisions, maintaining isolation consistency.

### ✅ Shared Dependencies Design
Step 2a correctly implements shared files first, then creates worktrees from that base. This avoids duplicate work.

### ✅ Temporary Commit Strategy
Committing shared deps before worktree creation is the right approach. Step 5 correctly squashes it with `git reset --soft HEAD~1`.

---

## Recommendations

### Priority 1 (Must Fix Before v3.1.0 Release)
1. Fix variable substitution in Step 2b (Critical #1)
2. Fix file boundary validation logic (Critical #2)
3. Add error handling to worktree creation (Critical #3)
4. Define scoped files format and population (Critical #4)
5. Fix modified file detection (Critical #5)

### Priority 2 (Should Fix Before v3.1.0 Release)
6. Add worktree creation validation (Major #8)
7. Improve revision loop prompt clarity (Major #10)

### Priority 3 (Can Address in v3.1.1)
8. Improve cleanup failure handling (Critical #6 → demote to Major if resource leaks are acceptable)
9. Add disk space check (Major #11)
10. Fix timestamp collision (Major #12)

### Testing Checklist Before Deployment

- [ ] Test with plan containing 0 work groups (single group path)
- [ ] Test with plan containing 1 work group (should use single path, not worktrees)
- [ ] Test with plan containing 2+ work groups (worktree path)
- [ ] Test with shared dependencies section
- [ ] Test with work group that violates file boundaries
- [ ] Test with BLOCKED.md in one worktree
- [ ] Test with worktree creation failure (simulate by filling /tmp)
- [ ] Test revision loop with worktrees
- [ ] Test cleanup after successful run
- [ ] Test cleanup after failed run (verify orphaned worktrees)
- [ ] Verify final commit squashes temporary shared deps commit

---

## Verdict

**REVISION_NEEDED**

The worktree isolation design is architecturally sound and solves a real problem (parallel coder conflicts). However, the bash implementation has multiple critical correctness and robustness issues that will cause failures in production.

**Must fix before merge:**
- Variable substitution (Critical #1)
- File boundary validation (Critical #2)
- Worktree creation error handling (Critical #3)
- Scoped files definition (Critical #4)
- Modified file detection (Critical #5)

**Estimated revision time:** 2-3 hours to address critical issues and test thoroughly.

Once these are resolved, v3.1.0 will be a significant improvement over v3.0.0 for multi-file feature development.

---

**Reviewed by:** code-reviewer agent v1.0.0
**Review timestamp:** 2026-02-23T12:15:00Z
**Files reviewed:** skills/ship/SKILL.md (v3.0.0 → v3.1.0 diff)
