---
name: ship
description: Execute an approved plan using unattended implementation and validation with worktree isolation.
version: 3.5.0
model: claude-opus-4-6
---
# /ship Workflow

## Inputs
- Plan file: $ARGUMENTS   # e.g. ./plans/feature-x.md

## Role
You are the **work coordinator**. You dispatch work to agents and check their results.
You do NOT write code, explore the codebase, or run tests yourself — agents do that.
Your job: read the plan once, dispatch each step, check verdicts, gate progression.

## Step 0 — Pre-flight checks

Tool: `Bash` (git status, cleanup), `Glob` (agent checks) — **Run all checks in parallel in a single message**

**Parse --security-override flag (MUST be first action in Step 0):**

If `$ARGUMENTS` contains `--security-override`:
- Extract the reason string (quoted text after `--security-override`)
- Store as `$SECURITY_OVERRIDE_REASON`
- Remove the flag and reason from `$ARGUMENTS` before using it as the plan path
- After extraction, `$ARGUMENTS` contains ONLY the plan path for all subsequent steps
- Log: "Security override active. Reason: $SECURITY_OVERRIDE_REASON"

If `$ARGUMENTS` does not contain `--security-override`:
- Set `$SECURITY_OVERRIDE_REASON` to empty

**First: Generate a unique run ID for this invocation**

Tool: `Bash`

```bash
RUN_ID=$(date +%Y%m%d-%H%M%S)-$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 6)
echo "Ship run ID: $RUN_ID"
```

**Then: Clean up stale artifacts from previous runs**

Tool: `Bash`

```bash
# Prune orphaned worktrees
git worktree prune 2>/dev/null || true

# Clean up orphaned tracking files from aborted runs
for tracking_file in .ship-worktrees-*.tmp; do
  [ -f "$tracking_file" ] || continue
  ORPHANED=true
  while IFS='|' read -r wt_path _rest; do
    if git worktree list --porcelain | grep -q "^worktree $wt_path$"; then
      ORPHANED=false
      break
    fi
  done < "$tracking_file"
  if $ORPHANED; then
    rm -f "$tracking_file"
    echo "Cleaned up orphaned tracking file: $tracking_file"
  fi
done

# Clean up orphaned violation files
rm -f .ship-violations-*.tmp
```

**Then: Run validation checks in parallel:**

1. `git status --porcelain` (Bash)
2. Glob for `.claude/agents/coder*.md`
3. Glob for `.claude/agents/code-reviewer*.md`
4. Glob for `.claude/agents/qa-engineer*.md` or `.claude/agents/qa*.md`

**Fail fast if any check fails:**
- If git status is not empty: "❌ Working directory is not clean. Commit or stash changes before running /ship."
- If no coder agent found: "❌ No coder agent found. Generate one using:\n  `python3 ~/workspaces/claude-devkit/generators/generate_agents.py . --type coder`"
- If no code-reviewer agent found: "❌ No code-reviewer agent found. Generate one using:\n  `python3 ~/workspaces/claude-devkit/generators/generate_agents.py . --type code-reviewer`"
- If no qa-engineer agent found: "❌ No qa-engineer agent found. Generate one using:\n  `python3 ~/workspaces/claude-devkit/generators/generate_agents.py . --type qa-engineer`"

If **any** check fails, stop immediately and list all failures.

**Security maturity level check:**

Tool: `Bash`, `Read`

Read `.claude/settings.local.json` (if exists), then `.claude/settings.json` (if exists). Extract the `security_maturity` field. Local settings override project settings.

**Note:** This block uses `python3 -c` for JSON parsing. Python 3 is available on all target platforms (macOS, Linux dev environments) and the `json` module handles edge cases (nested objects, whitespace, escaping) more reliably than regex-based alternatives. If `python3` is not available, the command silently fails and the maturity level defaults to `"advisory"` (L1) — the safe default. This is analogous to existing `/ship` pre-flight checks that use `git` and other CLI tools.

```bash
SECURITY_MATURITY="advisory"  # Default: L1

# Read local settings first (takes precedence)
if [ -f ".claude/settings.local.json" ]; then
  LOCAL_MATURITY=$(python3 -c "import json; d=json.load(open('.claude/settings.local.json')); print(d.get('security_maturity',''))" 2>/dev/null || echo "")
  [ -n "$LOCAL_MATURITY" ] && SECURITY_MATURITY="$LOCAL_MATURITY"
fi

# Fall back to project settings
if [ "$SECURITY_MATURITY" = "advisory" ] && [ -f ".claude/settings.json" ]; then
  PROJECT_MATURITY=$(python3 -c "import json; d=json.load(open('.claude/settings.json')); print(d.get('security_maturity',''))" 2>/dev/null || echo "")
  [ -n "$PROJECT_MATURITY" ] && SECURITY_MATURITY="$PROJECT_MATURITY"
fi

# Validate value
case "$SECURITY_MATURITY" in
  advisory|enforced|audited) ;;
  *) echo "Warning: Invalid security_maturity value '$SECURITY_MATURITY'. Defaulting to 'advisory'."
     SECURITY_MATURITY="advisory" ;;
esac

echo "Security maturity level: $SECURITY_MATURITY"
```

If `$SECURITY_MATURITY` is `enforced` or `audited`:

Tool: `Glob`

Check for required security skills:
- Glob `~/.claude/skills/secrets-scan/SKILL.md`
- Glob `~/.claude/skills/secure-review/SKILL.md`
- Glob `~/.claude/skills/dependency-audit/SKILL.md`

If ANY are missing, stop immediately:
"Security maturity level '$SECURITY_MATURITY' requires all security skills to be deployed.
Missing skills:
- [list missing skills]

Deploy with:
  cd ~/projects/claude-devkit && ./scripts/deploy.sh secrets-scan secure-review dependency-audit"

**Secrets scan gate (pre-flight):**

Tool: `Glob`

Glob for `~/.claude/skills/secrets-scan/SKILL.md`

**If found:**

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

Prompt:
"You are running a pre-commit secrets scan as part of the /ship pre-flight check.

Read the secrets-scan skill definition at `~/.claude/skills/secrets-scan/SKILL.md`.
Execute it with scope `all` against the current repository working directory.

Report your verdict: PASS or BLOCKED.
If BLOCKED, list the confirmed secret types and file locations (NO actual secret values).
If PASS, report 'No secrets detected in working directory.'"

**If secrets scan returns BLOCKED:**
Secrets-scan BLOCKED blocks at ALL maturity levels (including L1). Committed secrets cannot be un-committed and require rotation.
- If `--security-override` flag is set: Log override reason. Downgrade to PASS_WITH_NOTES. Continue.
  Output: "Secrets scan BLOCKED — overridden: [reason]. Logged for audit trail."
- If `--security-override` flag is NOT set: Stop workflow.
  Output: "Secrets detected in working directory. Remove before shipping.
  If this is a false positive, re-run with: /ship $ARGUMENTS --security-override \"reason\""

**If not found:**
- If L1 (advisory): Log: "Security note: secrets-scan skill not deployed. Consider deploying for pre-commit secret detection."
- If L2/L3: Already caught by maturity level check above (will not reach here).

## Step 1 — Coordinator reads plan

Tool: `Read` (direct — coordinator does this)

Read the plan file at `$ARGUMENTS`. Extract:
- **Files to modify/create** (from the Task Breakdown section)
- **Test command** (from the Test Plan section)
- **Acceptance criteria** (from the Acceptance Criteria section)

**Validate plan structure:** Verify the plan contains all required sections:
- Task Breakdown (required)
- Test Plan (required)
- Acceptance Criteria (required)
- `## Status: APPROVED` marker (required)

If any section is missing or plan is not approved, stop with:
"Plan at `$ARGUMENTS` is incomplete or not approved. Required: Task Breakdown, Test Plan, Acceptance Criteria, and ## Status: APPROVED marker. Run `/architect` first."

Derive `[name]` from the plan filename (e.g. `./plans/feature-x.md` → `feature-x`).

**Parse work groups (optional):** Look for a `## Work Groups` section inside the Task Breakdown. Format:

```markdown
### Work Group 1: [name]
- file-a.ts
- file-b.ts

### Work Group 2: [name]
- file-c.ts
- file-d.ts

### Shared Dependencies
- src/types.ts (modify — implement before work groups)
```

If no `## Work Groups` section exists, treat the entire Task Breakdown as a single group. Derive the `scoped_files` list by extracting ALL files from the Task Breakdown section:
- All files listed in the `### Files to Modify` table
- All files listed in the `### Files to Create` table

Store these as the `scoped_files` for the single implicit work group. This list is used in Step 3d (boundary validation) and Step 3e (merge).

## Step 2 — Pattern Validation (warnings only)

Validate the plan against project patterns before implementation. This step produces warnings but does NOT block the workflow.

Tool: `Read` (direct — coordinator does this)

**Read `./CLAUDE.md`** (if exists). Extract:
- Directory structure conventions
- Naming conventions (files, variables, components)
- Required test patterns
- Architecture patterns (module boundaries, dependency direction)
- Technology stack constraints

**Compare plan against patterns:**

Check each file in the plan's Task Breakdown against CLAUDE.md conventions:

1. **Directory placement:** Are new files placed in the correct directories per CLAUDE.md structure?
2. **Naming conventions:** Do new file/component names follow established patterns?
3. **Test requirements:** Does the plan include tests where CLAUDE.md requires them?
4. **Architecture alignment:** Does the plan respect module boundaries and dependency rules?
5. **Context metadata:** Does the plan contain a `<!-- Context Metadata` block? (If yes, verify `claude_md_exists` is `true` when a CLAUDE.md exists)

**Output format:**

If warnings found, output:

    Pattern validation warnings (non-blocking):

    1. [Warning description -- e.g., "New file src/utils/auth.ts -- CLAUDE.md places utilities in lib/"]
    2. [Warning description]
    ...

    These warnings are informational. The workflow will continue.
    To address these, revise the plan and re-run /ship.

If no warnings, output:

    Plan aligns with CLAUDE.md patterns.

**If CLAUDE.md does not exist:**

    No CLAUDE.md found. Skipping pattern validation.
    Consider running /sync to generate project documentation.

Continue to Step 3 regardless of warnings.

## Step 3 — Implementation (with worktree isolation)

Every implementation runs in isolated git worktrees, regardless of how many work groups
the plan defines. This ensures concurrent sessions cannot interfere with the implementation.

#### Step 3a — Shared Dependencies (conditional)

**Trigger:** Plan contains `### Shared Dependencies` section. If no Shared Dependencies
section exists, skip directly to Step 3b.

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

Implement shared files in main working directory with single coder agent:

"You are implementing shared dependencies for a plan. Read the plan at `$ARGUMENTS`.
Then read the `.claude/agents/` directory to find the coder agent that matches this work.

**Your scope:** Shared Dependencies
**Your files:**
- [list files from Shared Dependencies section]

Hard rules:
- Only modify files listed in Shared Dependencies. Do not touch work group files.
- Follow the plan exactly. These files will be used by all work groups.
- If blocked, write `BLOCKED.md` in the project root and stop."

Then commit to local history (temporary commit for worktree base):

Tool: `Bash`

Command:
```bash
git add <shared-files> && git commit -m "WIP: /ship shared dependencies for ${name}

This is a temporary commit that will be squashed with the final implementation in Step 6.
Created by: /ship skill v3.5.0"
```

#### Step 3b — Create Worktrees

Tool: `Bash`

For each work group (parsed in Step 1), create isolated worktree.

**Coordinator instructions:**
- Replace `${name}` with the plan name from Step 1 (e.g., "add-user-auth")
- Replace `${wg_num}` with work group index (1, 2, 3, ...)
- Replace `${wg_name}` with work group name from plan (e.g., "Authentication")
- Replace `${scoped_files}` with space-separated file list from plan (e.g., "src/auth.ts src/middleware.ts")

```bash
# Create worktree with secure, unique path
WORKTREE_PATH=$(mktemp -d /tmp/ship-XXXXXXXXXX)

# These variables come from Step 1 plan parsing
WG_NUM="${wg_num}"   # e.g., 1, 2, 3
WG_NAME="${wg_name}" # e.g., "Authentication"
SCOPED_FILES="${scoped_files}"  # e.g., "src/auth.ts src/middleware.ts"

# Create worktree with error handling
if ! git worktree add "$WORKTREE_PATH" -b "ship-wg${WG_NUM}-${RUN_ID}" HEAD 2>/dev/null; then
  echo "❌ Failed to create worktree at $WORKTREE_PATH"
  echo "Possible causes: path exists, disk full, git locked"
  rm -f .ship-worktrees-${RUN_ID}.tmp
  exit 1
fi

# Store worktree info (pipe-delimited: path|num|name|files)
echo "$WORKTREE_PATH|$WG_NUM|$WG_NAME|$SCOPED_FILES" >> .ship-worktrees-${RUN_ID}.tmp
```

Using `mktemp -d` ensures:
- The directory is created with 0700 permissions (not world-readable)
- The path contains a random suffix, eliminating symlink/TOCTOU attacks
- Kernel-guaranteed uniqueness, no PID or timestamp collisions

**Validation:** After creating all worktrees, verify tracking file exists:

```bash
if [ ! -f .ship-worktrees-${RUN_ID}.tmp ] || [ ! -s .ship-worktrees-${RUN_ID}.tmp ]; then
  echo "❌ No worktrees were created. Check Step 3b output."
  exit 1
fi
```

Output: "✓ Created worktree for Work Group ${wg_num}: ${wg_name} at $WORKTREE_PATH"

#### Step 3c — Dispatch Coders to Worktrees

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5` — **dispatch one coder per work group (parallel if multiple, single Task call if one group)**

Each coder receives this prompt (scoped to its worktree):

"You are implementing part of a plan in an isolated worktree. Read the plan at `$ARGUMENTS`.

**CRITICAL: You are working in an isolated worktree at:**
`{WORKTREE_PATH}`

All file operations must use absolute paths within this worktree. The worktree is a complete copy of the repository with shared dependencies already applied.

**Your scope:** Work Group N: [group-name]
**Your files:**
- [list files from this work group only]

**File operation examples:**
- Read: Read tool with {WORKTREE_PATH}/src/components/Button.tsx
- Edit: Edit tool with {WORKTREE_PATH}/src/components/Button.tsx
- Write: Write tool with {WORKTREE_PATH}/src/utils/helpers.ts

Hard rules:
- Only modify files listed in your scope within {WORKTREE_PATH}.
- Do not access files outside your worktree.
- Follow the plan exactly. Do not expand scope.
- If blocked on something you cannot resolve, write `BLOCKED.md` at {WORKTREE_PATH}/BLOCKED.md and stop.

**Learnings (optional):**
If the file `.claude/learnings.md` exists, read the `## Coder Patterns` section before starting implementation. Apply any relevant learnings to avoid known recurring issues. Do not mention the learnings file in your output — just apply the patterns silently."

**After all coders finish:**

Tool: `Bash`

Check for BLOCKED.md in any worktree:

```bash
while IFS='|' read -r wt_path wg_num wg_name scoped_files; do
  if [ -f "$wt_path/BLOCKED.md" ]; then
    echo "Implementation blocked in Work Group $wg_num. See worktree at $wt_path"
    cat "$wt_path/BLOCKED.md"
    exit 1
  fi
done < .ship-worktrees-${RUN_ID}.tmp
```

If any worktree has BLOCKED.md, stop workflow and output: "❌ Implementation blocked. See output above."

#### Step 3d — File Boundary Validation

Tool: `Bash`

For each worktree, verify agents only modified scoped files:

```bash
VIOLATIONS=""
MAIN_DIR=$(pwd)

while IFS='|' read -r wt_path wg_num wg_name scoped_files; do
  cd "$wt_path"

  # Get all modified files (working directory + index + committed)
  # This catches Edit/Write tool changes even if not staged
  MODIFIED=$(git status --porcelain | awk '{print $2}')
  # Known limitation: awk '{print $2}' does not correctly handle renamed files
  # (R old -> new captures only 'old') or file paths containing spaces.
  # The merge step (3e) is the primary safety boundary — it copies only scoped files.
  # Improving this parsing is deferred to a follow-up change.

  # If nothing modified, check against HEAD~1 (for committed changes)
  if [ -z "$MODIFIED" ] && git rev-parse HEAD~1 >/dev/null 2>&1; then
    MODIFIED=$(git diff --name-only HEAD~1 HEAD)
  fi

  # Validate each modified file is in scoped files (exact match)
  for file in $MODIFIED; do
    FOUND=0

    # Normalize paths (remove leading ./)
    normalized_file=$(echo "$file" | sed 's|^\./||')

    # Check against each scoped file (space-separated list)
    for scoped in $scoped_files; do
      normalized_scoped=$(echo "$scoped" | sed 's|^\./||')

      if [ "$normalized_file" = "$normalized_scoped" ]; then
        FOUND=1
        break
      fi
    done

    if [ $FOUND -eq 0 ]; then
      VIOLATIONS="${VIOLATIONS}Work Group $wg_num ($wg_name) modified $file (not in scope: $scoped_files)\n"
    fi
  done

  cd "$MAIN_DIR"
done < .ship-worktrees-${RUN_ID}.tmp

if [ -n "$VIOLATIONS" ]; then
  echo -e "$VIOLATIONS" > .ship-violations-${RUN_ID}.tmp
fi
```

**Verdict gate:**

Read `.ship-violations-${RUN_ID}.tmp`. If exists and non-empty:

Output:
```
❌ File boundary violations detected:

[contents of .ship-violations-${RUN_ID}.tmp]

Agents modified files outside their assigned scope. This is a critical error.
Workflow stopped. Review agent behavior and retry.
```

**STOP workflow** — do not proceed to Step 3e.

If no violations, continue to Step 3e.

#### Step 3e — Merge Worktrees

Tool: `Bash`

For each worktree, copy scoped files to main working directory:

```bash
MAIN_DIR=$(pwd)

while IFS='|' read -r wt_path wg_num wg_name scoped_files; do
  echo "Merging Work Group $wg_num: $wg_name"

  for file in $scoped_files; do
    if [ -f "$wt_path/$file" ]; then
      mkdir -p "$MAIN_DIR/$(dirname "$file")"
      cp "$wt_path/$file" "$MAIN_DIR/$file"
      echo "  ✓ Merged $file"
    fi
  done
done < .ship-worktrees-${RUN_ID}.tmp

# Post-merge validation: verify all scoped files exist in main directory
while IFS='|' read -r wt_path wg_num wg_name scoped_files; do
  for file in $scoped_files; do
    if [ ! -f "$MAIN_DIR/$file" ]; then
      echo "WARNING: Scoped file $file was not created by coder in worktree"
    fi
  done
done < .ship-worktrees-${RUN_ID}.tmp
```

Post-merge validation emits warnings but does not block the workflow. A file may legitimately
not need creation if it already existed in the main directory before the worktree was
created (e.g., a file listed under "Files to Modify" that the coder chose not to change).
The code review in Step 4 serves as the catch for genuinely missing files.

Output: "✓ Merged N work groups (X files total)"

#### Step 3f — Cleanup Worktrees

Tool: `Bash`

Remove all worktrees and temporary files:

```bash
CLEANUP_FAILURES=0

while IFS='|' read -r wt_path wg_num wg_name scoped_files; do
  if ! git worktree remove "$wt_path" --force 2>/dev/null; then
    echo "⚠️  Failed to remove worktree: $wt_path"
    CLEANUP_FAILURES=$((CLEANUP_FAILURES + 1))
  else
    echo "✓ Removed worktree for Work Group $wg_num"
  fi
done < .ship-worktrees-${RUN_ID}.tmp

# Report cleanup failures but don't block workflow
if [ $CLEANUP_FAILURES -gt 0 ]; then
  echo "⚠️  $CLEANUP_FAILURES worktree(s) failed to clean up. Manual cleanup:"
  echo "    git worktree prune"
  echo "    rm -rf /tmp/ship-*"
fi

# Clean up tracking files
rm -f .ship-worktrees-${RUN_ID}.tmp .ship-violations-${RUN_ID}.tmp
```

**Note:** Cleanup failures are logged but don't block the workflow. Orphaned worktrees can be cleaned manually with `git worktree prune` or automatically by the pre-flight check in Step 0.

## Step 4 — Parallel verification

Tool: `Task` (code review, QA), `Bash` (tests) — **Run all three checks in parallel in a single message**

Run these verification tasks in parallel (3 or 4 tasks depending on security skill deployment):

### 4a — Code review

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

Prompt:
"You are reviewing code changes against a plan. Read the plan at `$ARGUMENTS`.
Then read the `.claude/agents/` directory to find the code-reviewer agent.
Follow that agent's review standards.

Review all files listed in the plan's task breakdown. Compare the current file contents
against the plan's requirements.

Write your review to `./plans/[name].code-review.md` with this structure:
- **Verdict:** PASS / REVISION_NEEDED / FAIL
- **Critical findings** (must fix — correctness, security, data loss)
- **Major findings** (should fix — performance, maintainability, missing requirements)
- **Minor findings** (optional — style, naming, minor improvements)
- **Positives** (what was done well)

A PASS verdict means no Critical or Major findings remain.

**Learnings (optional):**
If the file `.claude/learnings.md` exists, read the `## Coder Patterns > ### Missed by coders, caught by reviewers` section. Explicitly verify that none of these known coder mistakes are present in the implementation. If you find a known pattern, reference it in your findings.
Also read `## Reviewer Patterns > ### Overcorrected` to avoid flagging known false positives."

### 4b — Run tests

Tool: `Bash` (direct — coordinator does this)

Run the test command extracted from the plan in Step 1.

If exit code is non-zero:
- Write the test output to `./plans/[name].test-failure.log`

### 4c — QA validation

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

Prompt:
"You are a QA engineer validating that an implementation meets its plan.
Read the plan at `$ARGUMENTS`.
Then read the `.claude/agents/` directory to find the qa-engineer agent.
Follow that agent's validation standards.

Check every acceptance criterion in the plan against the current code.
Run any test commands from the plan if they haven't been run.

Write `./plans/[name].qa-report.md` with:
- **Verdict:** PASS / PASS_WITH_NOTES / FAIL
- **Acceptance criteria coverage** (checklist: criterion → met/not met)
- **Missing tests or edge cases**
- **Notes** (for PASS_WITH_NOTES — non-blocking observations)

**Learnings (optional):**
If the file `.claude/learnings.md` exists, read the `## QA Patterns` and `## Test Patterns` sections. Verify that known recurring coverage gaps are addressed in this implementation. If you find a known gap, reference it in your report."

### 4d — Secure review (conditional)

Tool: `Glob`

Glob for `~/.claude/skills/secure-review/SKILL.md`

**If found:**

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`

Prompt:
"You are running a semantic security review as part of the /ship verification step.

Read the secure-review skill definition at `~/.claude/skills/secure-review/SKILL.md`.
Execute its scanning workflow (vulnerability, data flow, auth/authz scans) against the
files modified in this implementation.

Scope: `changes` (uncommitted modifications in the working directory).

Write your security review summary to `./plans/[name].secure-review.md` with the
standard secure-review output format including verdict (PASS / PASS_WITH_NOTES / BLOCKED),
severity-rated findings, and redacted secrets (if any).

CRITICAL: Never include actual secret values in your report. Redact to first 4 / last 4 characters."

**If not found:**
- Log: "Security note: secure-review skill not deployed. Security code review skipped."
- Set secure review verdict to "not-run"

### Result evaluation

Coordinator reads all outputs (three or four, depending on secure-review deployment) and evaluates.

**The result evaluation matrix is maturity-level-aware:**

**At L1 (advisory):**

| Code Review | Tests | QA | Secure Review | Action |
|---|---|---|---|---|
| PASS | Pass (exit 0) | PASS or PASS_WITH_NOTES | PASS / PASS_WITH_NOTES / BLOCKED / not-run | Proceed to Step 6. If BLOCKED: log prominent warning ("Security review found critical issues"), auto-downgrade to PASS_WITH_NOTES. |
| REVISION_NEEDED | Any | Any | Any | Enter Step 5 (revision loop) |
| FAIL | Any | Any | Any | Stop workflow |
| Any | Fail (non-zero) | Any | Any | Stop workflow |
| PASS | Pass | FAIL | Any | Stop workflow |

At L1, secure-review BLOCKED is reported but does not stop the workflow (parent plan L1 definition).

**At L2/L3 (enforced/audited):**

| Code Review | Tests | QA | Secure Review | Action |
|---|---|---|---|---|
| PASS | Pass (exit 0) | PASS or PASS_WITH_NOTES | PASS or PASS_WITH_NOTES or not-run | Proceed to Step 6 (commit) |
| PASS | Pass (exit 0) | PASS or PASS_WITH_NOTES | BLOCKED | If --security-override: Proceed to Step 6 (log override). Else: Stop workflow. |
| REVISION_NEEDED | Any | Any | Any (not BLOCKED) | Enter Step 5 (revision loop) |
| REVISION_NEEDED | Any | Any | BLOCKED | Enter Step 5 (revision loop). Include security findings in coder instructions. Coders fix both code review and security issues. Re-run Step 4 after revision. |
| FAIL | Any | Any | Any | Stop workflow |
| Any | Fail (non-zero) | Any | Any | Stop workflow |
| PASS | Pass | FAIL | Any | Stop workflow |
| Any | Any | Any | BLOCKED (no override, revision loop exhausted) | Stop workflow |

If stopping due to secure review BLOCKED (L2/L3, post-revision):
- "Secure review BLOCKED after revision loop. See `./plans/[name].secure-review.md`. Fix security findings or re-run with --security-override."

If proceeding with security override (L2/L3):
- Log: "Secure review BLOCKED — overridden: [reason]. Proceeding with PASS_WITH_NOTES."

If auto-downgrading at L1:
- Log: "Secure review BLOCKED (L1 advisory — non-blocking). Review findings: `./plans/[name].secure-review.md`."

If stopping, output appropriate message:
- "Code review FAIL. See `./plans/[name].code-review.md`."
- "Tests failed. See `./plans/[name].test-failure.log`."
- "QA validation FAIL. See `./plans/[name].qa-report.md`."

## Step 5 — Revision loop (conditional)

**Trigger:** Step 4 code review verdict is `REVISION_NEEDED` (and no FAIL verdicts from any check).

**If Step 4 all checks PASS:** skip to Step 6.

### 5a — Coder fixes (with worktree isolation)

Before re-creating worktrees, commit the current working directory state so that
worktrees created from HEAD contain the first-pass implementation code:

Tool: `Bash`

**IMPORTANT:** The coordinator MUST enumerate the specific files from the plan's task breakdown and shared dependencies. Build the file list by concatenating: (1) shared dependency files committed in Step 2a, and (2) each work group's "Files modified" list from the plan being shipped. Use `git add <file1> <file2> ...` with explicit paths. Never use `git add -A` or `git add .` as this risks staging secrets, `.env` files, or other sensitive content that may have been created during implementation. After staging, run `git status --porcelain` and verify that only expected files are staged.

```bash
# Stage only files scoped by the plan's task breakdown.
# The coordinator MUST construct this list from:
#   1. Shared dependency files (from Step 2a)
#   2. Each work group's "Files modified" list from the plan
# Example: git add src/auth.ts src/auth.test.ts lib/helpers.ts
# NEVER use git add -A or git add .
git add $SHARED_DEP_FILES $WG1_FILES $WG2_FILES ...
git commit -m "WIP: ship v3.5.0 first-pass implementation (pre-revision)"
```

This ensures revision-loop worktrees are based on the first-pass code, not the
pre-implementation state. The coder can then read the code review feedback and
apply targeted fixes to the existing implementation rather than re-implementing
from scratch.

Then proceed with the standard worktree workflow:

- Re-create worktrees (Step 3b) — these now branch from the WIP commit containing first-pass code
- Dispatch coders to worktrees (Step 3c) with modified prompt:
  "Read the code review at `./plans/[name].code-review.md`.
  Address all Critical and Major findings.

  **IMPORTANT:** The code review references files in the main directory (e.g., src/Button.tsx).
  You are working in an isolated worktree at {WORKTREE_PATH}.
  Translate paths when reading/editing files:
  - Code review mentions: src/Button.tsx
  - You must access: {WORKTREE_PATH}/src/Button.tsx

  Do not change anything else.
  Read `.claude/agents/` to find the coder agent and follow its standards."
- Validate file boundaries (Step 3d)
- Merge worktrees (Step 3e) — including post-merge validation
- Cleanup worktrees (Step 3f)

### 5b — Re-verify in parallel

Re-run Step 4 in its entirety (all three parallel checks: code review + tests + QA).

Evaluate results using the same result matrix from Step 4.

**Max 2 revision rounds total.** If still REVISION_NEEDED or FAIL after 2 rounds:
stop the workflow. Output: "Code review did not converge after 2 rounds. See `./plans/[name].code-review.md`."

**Note:** Yes, this re-runs tests and QA on code that may be revised. This is an acceptable tradeoff because:
- Most implementations pass code review on the first try (parallelism saves time in the common case)
- Re-running tests/QA is cheaper than sequential workflows

## Step 6 — Commit gate

Read `./plans/[name].qa-report.md`. Check the verdict.

**If PASS or PASS_WITH_NOTES:**

**Dependency audit gate (conditional):**

Tool: `Glob`

Glob for `~/.claude/skills/dependency-audit/SKILL.md`

**If found:**

Detect actual dependency changes by diffing manifest files against HEAD:

Tool: `Bash`

```bash
# Check each known manifest file for dependency-section changes
for manifest in package.json requirements.txt pyproject.toml Pipfile go.mod Cargo.toml pom.xml Gemfile; do
  if [ -f "$manifest" ]; then
    git diff HEAD -- "$manifest" 2>/dev/null
  fi
done
```

If any manifest file diff shows additions in dependency sections (new packages, version changes):

**If dependency changes detected:**

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

Prompt:
"You are running a dependency audit as part of the /ship commit gate.

Read the dependency-audit skill definition at `~/.claude/skills/dependency-audit/SKILL.md`.
Execute it against the current project.

Report your verdict: PASS, PASS_WITH_NOTES, INCOMPLETE, or BLOCKED.
If BLOCKED, list the Critical CVE findings.
Write your report to `./plans/[name].dependency-audit.md`."

**If dependency audit returns BLOCKED:**
- At L1 (advisory): Log prominent warning. Auto-downgrade to PASS_WITH_NOTES. Continue.
  Output: "Dependency audit BLOCKED (L1 advisory — non-blocking). Review findings: `./plans/[name].dependency-audit.md`."
- At L2/L3: If `--security-override`: Downgrade to PASS_WITH_NOTES. Log override reason. Else: Stop workflow.
  Output: "Dependency audit BLOCKED. Critical vulnerabilities found. See `./plans/[name].dependency-audit.md`."

**If dependency audit returns INCOMPLETE:**
- Log: "Dependency audit INCOMPLETE — no scanner available for this ecosystem. Install the appropriate scanner for full CVE scanning."
- Continue (INCOMPLETE does not block at any level).

**If no dependency changes detected:** Skip dependency audit.
- Log: "No dependency changes detected (manifest files unchanged vs HEAD). Skipping dependency audit."

**If not found:**
- Log: "Security note: dependency-audit skill not deployed. Dependency audit skipped."

1. **If WIP commits exist from Step 3a and/or Step 5a:** Soft reset to squash them with the final commit
   - Tool: `Bash`
   - Count the number of WIP commits to squash (0, 1, or 2 depending on whether Step 3a shared deps and Step 5a pre-revision commits were created)
   - **Branch protection:** The coordinator MUST verify the current branch is not `main` or `master` before executing `git reset --soft`. If running on a protected branch, the workflow stops with an error. This prevents accidental history rewriting on the default branch.
   - Run the branch protection check first:
     ```bash
     # Branch protection check: refuse to rewrite history on main/master
     CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "DETACHED")
     if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
         echo "ERROR: /ship is running on protected branch '$CURRENT_BRANCH'."
         echo "Refusing to run 'git reset --soft' on a protected branch."
         echo "Create a feature branch first: git checkout -b feature/<name>"
         exit 1
     fi
     ```
   - Command: `git reset --soft HEAD~N` (where N is the number of WIP commits)

2. Stage changed files:
   - Tool: `Bash`
   - Command: `git add <files from plan task breakdown + shared deps>`

3. Create commit with proper format:
   - Tool: `Bash`
   - Command:
     ```bash
     git commit -m "$(cat <<'EOF'
     <imperative summary from plan goals>

     <why this change was needed - one sentence from plan context>

     Implements: ./plans/[name].md

     Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
     EOF
     )"
     ```
   - If `--security-override` was used, append to commit message:
     ```
     Security-Override: $SECURITY_OVERRIDE_REASON
     ```

4. Clean up artifacts:
   - Tool: `Bash`
   - Command: `mkdir -p ./plans/archive/[name] && mv ./plans/[name].code-review.md ./plans/[name].qa-report.md ./plans/archive/[name]/ && if [ -f ./plans/[name].feasibility.md ]; then mv ./plans/[name].feasibility.md ./plans/archive/[name]/; fi`
   - Then, archive test failure log if it exists:
     ```bash
     if [ -f "./plans/[name].test-failure.log" ]; then
       mv "./plans/[name].test-failure.log" "./plans/archive/[name]/"
     fi
     ```
   - Then, archive security review and dependency audit artifacts if they exist:
     ```bash
     if [ -f "./plans/[name].secure-review.md" ]; then
       mv "./plans/[name].secure-review.md" "./plans/archive/[name]/"
     fi
     if [ -f "./plans/[name].dependency-audit.md" ]; then
       mv "./plans/[name].dependency-audit.md" "./plans/archive/[name]/"
     fi
     ```

5. Output success message:
   - "✅ Implementation complete and committed.
   - QA report: `./plans/archive/[name]/[name].qa-report.md`
   - **Next step:** Run `/sync` to update documentation."

**If FAIL:**
- Do NOT commit.
- Output: "❌ QA validation failed. See `./plans/[name].qa-report.md`."
- Stop the workflow.

## Step 7 — Retro capture (post-commit, non-blocking)

**Trigger:** Step 6 committed successfully (PASS or PASS_WITH_NOTES verdict).
If Step 6 did not commit (FAIL), skip Step 7 entirely.

**This step is non-blocking.** If it fails for any reason, log the error and report success from Step 6. The commit is already done — Step 7 is best-effort learning capture.

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

Prompt:
"You are extracting learnings from a completed /ship run.

Read the archived review artifacts using glob-based discovery:
- `./plans/archive/[name]/*.code-review.md`
- `./plans/archive/[name]/*.qa-report.md`

If any test failure logs exist, also read:
- `./plans/archive/[name]/*.test-failure.log`

Read each file in its entirety. Extract findings regardless of the specific section header format used. Look for issues by severity, positive observations, coverage gaps, and test failures regardless of how the document is structured.

Read the existing learnings file (if it exists):
- `.claude/learnings.md`

**Your task:**

1. From the code review, extract:
   - Any Critical or Major findings (these are things the coder missed). Rate each: Critical / High / Medium / Low.
   - Any Minor findings that represent a recurring pattern (check if similar issues exist in learnings.md)
   - Positives are informational only — do not write them to learnings

2. From the QA report, extract:
   - Missing tests or edge cases. Rate each: Critical / High / Medium / Low.
   - Acceptance criteria that were not fully met

3. From test failures (if any), extract:
   - Failure categories (what type of test failed and why). Rate each: Critical / High / Medium / Low.

4. **Deduplication:** For each finding:
   - Check if an existing learning in `.claude/learnings.md` describes the same underlying issue (same root cause, same actor, same category)
   - If it does: update the date to today and append `[name]` to the `Seen in:` list using the Edit tool
   - If it is a new issue: append as a new entry under the appropriate section

5. **Write learnings:**
   - If `.claude/learnings.md` does not exist, create it with the standard header and sections
   - Use this format for each entry:
     `- **[YYYY-MM-DD] [Pattern Title]** — [Description]. Seen in: [feature-list]. #category #tags`
   - Place entries under the correct section based on source:
     - Code review Critical/Major findings -> `## Coder Patterns > ### Missed by coders, caught by reviewers`
     - QA missing coverage -> `## QA Patterns > ### Coverage gaps`
     - Test failures -> `## Test Patterns > ### Common failures`
   - Update the `Last updated:` timestamp in the header

6. **Report** what you wrote (or that no new learnings were found) to stdout. Do NOT write any report files — just output a summary."

**After Task completes:**

Tool: `Bash`

Auto-commit the learnings file if it was modified:
```bash
if git diff --name-only -- .claude/learnings.md | grep -q .; then
  git add .claude/learnings.md
  git commit -m "chore: update project learnings from /ship run"
elif git ls-files --others --exclude-standard -- .claude/learnings.md | grep -q .; then
  git add .claude/learnings.md
  git commit -m "chore: add project learnings from /ship run"
fi
```

If the commit fails, log the error but do not fail the step.

If Task succeeded, output:
"Retro capture complete. See `.claude/learnings.md` for updated project learnings."

If Task failed, output:
"Retro capture skipped (non-blocking). The commit from Step 6 is unaffected.
Error: [Task error message]
Run `/retro` manually to capture learnings."
