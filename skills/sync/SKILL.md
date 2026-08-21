---
name: sync
description: Synchronize CLAUDE.md and README with recent code changes.
version: 3.0.0
model: claude-sonnet-4-6
---
# /sync Workflow

## Inputs
- Scope: $ARGUMENTS (optional: "recent", "full")
  - `recent`: Last 5 commits (default)
  - `full`: Full codebase scan

## Role
You are the **documentation coordinator**. You detect changes, delegate review to the librarian, and present diffs for user approval.
You do NOT make documentation changes yourself — you coordinate the process.

## Step 1 — Detect changes

**Resolve devkit paths (MUST be first action in Step 1):**

Tool: `Bash`

```bash
# --- Devkit Path Resolution ---
DEVKIT_SCRIPTS="${CLAUDE_DEVKIT:-$HOME/.claude-devkit}/scripts"

# Source path resolution helper
if [ -f "$DEVKIT_SCRIPTS/resolve-project-dir.sh" ]; then
  . "$DEVKIT_SCRIPTS/resolve-project-dir.sh"
  DEVKIT_PROJECT_DIR_RESOLVED=$(resolve_devkit_project_dir) || {
    echo "Failed to resolve project directory" >&2; exit 1
  }
elif [ -n "${DEVKIT_PROJECT_DIR:-}" ]; then
  DEVKIT_PROJECT_DIR_RESOLVED="$DEVKIT_PROJECT_DIR"
else
  echo "WARNING: devkit is not installed. Using deprecated .devkit/ fallback." >&2
  DEVKIT_PROJECT_DIR_RESOLVED=".devkit"
fi

PLANS_DIR="$DEVKIT_PROJECT_DIR_RESOLVED/plans"
mkdir -p "$PLANS_DIR"
echo "Plans directory: $PLANS_DIR"
```

Tool: `Bash` (direct — coordinator does this)

**Determine scope:**
- If `$ARGUMENTS` is empty: scope = "recent"
- Else: scope = `$ARGUMENTS`

Validate scope is one of: `recent`, `full`. If not, stop with:
"Invalid scope. Use: /sync [recent|full]"

**If scope is "recent":**
Run: `git log -5 --oneline --name-status`

**If scope is "full":**
Run: `git log -20 --oneline --name-status`

Extract:
- Changed files (from --name-status)
- Commit messages (from --oneline)

Derive timestamp: `[timestamp]` = current ISO datetime (e.g., `2026-02-07T12-30-00`)

## Step 2 — Detect new environment variables

Tool: `Grep`, `pattern=process\.env|os\.getenv|ENV\[|getenv\(|std::env`, `output_mode=content`

Search for environment variable references in:
- Source code files (not test files)
- Configuration files
- Documentation files

Generate list of environment variables found.

Tool: `Read` (direct — coordinator does this)

Read `CLAUDE.md` and check which environment variables are already documented.

Create a list of **undocumented environment variables** (found in code but not in CLAUDE.md).

## Step 3 — Librarian review

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-6`

Prompt: "You are reviewing documentation for currency and accuracy.

**Recent changes:**
[Paste commit list and changed files from Step 1]

**Undocumented environment variables:**
[List from Step 2]

**Task:**
1. Read the current `CLAUDE.md` and `README.md` files
2. Compare them against the recent code changes
3. Identify documentation that is now stale, missing, or incorrect

Write `$PLANS_DIR/sync-[timestamp].review.md` with this structure:

## Verdict
[CURRENT / UPDATES_NEEDED]

## Required Updates
(Changes that must be made for accuracy)

### CLAUDE.md
- [ ] Update tech stack version (e.g., 'React 17' → 'React 18')
- [ ] Add missing environment variable: VAR_NAME
- [ ] Remove deprecated pattern: [pattern name]
- [ ] Update build command: [old] → [new]

### README.md
- [ ] Update installation steps
- [ ] Add new dependency: [name]
- [ ] Update example usage
- [ ] Fix broken link: [url]

## Suggested Updates
(Optional improvements)

- [ ] Add example for new feature
- [ ] Clarify ambiguous section: [section name]
- [ ] Add troubleshooting for common issue

## Rationale
(Why these changes are needed - reference specific commits or code changes)"

## Step 4 — Update documentation (conditional)

Read `$PLANS_DIR/sync-[timestamp].review.md` and check verdict.

**If verdict is CURRENT:**
Output: "✅ Documentation is current. No updates needed.

Review: $PLANS_DIR/sync-[timestamp].review.md"

Stop the workflow.

**If verdict is UPDATES_NEEDED:**

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-6`

Prompt: "You are updating project documentation based on a librarian review.

Read the review at `$PLANS_DIR/sync-[timestamp].review.md`.

Apply all **Required Updates** to `CLAUDE.md` and `README.md`.
Use the Edit tool to make precise changes.

Follow markdown best practices:
- Use proper heading hierarchy
- Keep lines under 100 characters
- Use code blocks with language specifiers
- Use relative links for local files
- Keep tables aligned

Do NOT add suggested updates unless they're critical.
Do NOT change formatting or structure unnecessarily."

## Step 5 — Verification

Tool: `Bash` (direct — coordinator does this)

Run: `git diff CLAUDE.md README.md`

Present the diff output to the user with this message:

"📝 Documentation changes ready for review:

[Show git diff output]

---

**Review the changes above.**

To accept these changes:
```bash
git add CLAUDE.md README.md
git commit -m \"docs: sync with codebase

Updates documentation to reflect recent code changes.

Review: $PLANS_DIR/sync-[timestamp].review.md

Co-Authored-By: Claude Sonnet <noreply@anthropic.com>\"
```

To reject:
```bash
git restore CLAUDE.md README.md
```

Review: $PLANS_DIR/sync-[timestamp].review.md"

## Step 6 — Archive review

Tool: `Bash` (direct — coordinator does this)

Run: `mkdir -p $PLANS_DIR/archive/sync && mv $PLANS_DIR/sync-[timestamp].review.md $PLANS_DIR/archive/sync/`

Output: "Review archived to $PLANS_DIR/archive/sync/sync-[timestamp].review.md"
