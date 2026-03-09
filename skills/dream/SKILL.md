---
name: dream
description: Research and create a technical blueprint for a new feature.
model: claude-opus-4-6
version: 3.0.0
---
# /dream Workflow

## Inputs
- Feature request: $ARGUMENTS
- Flags: `--fast` skips the red team review (use for low-risk changes)

## Step 0 — Pre-flight (optional)

**Check for project-specific agents (parallel):**

Tool: `Glob` (direct — coordinator does this)

Run all three globs in parallel:
- Pattern 1: `.claude/agents/senior-architect.md`
- Pattern 2: `.claude/agents/code-reviewer.md`
- Pattern 3: `.claude/agents/security-analyst.md`

**If senior-architect found:**
- Output: "✅ Using project-specific senior-architect from .claude/agents/"

**If senior-architect not found:**
- Output note: "💡 No project-specific senior-architect found. Will use generic Task subagent for planning.\n   For project-tailored planning, generate one:\n   `gen-agent . --type senior-architect`"
- Continue to Step 1 (do not block).

**If code-reviewer found:**
- Output: "✅ Using project-specific code-reviewer from .claude/agents/"

**If code-reviewer not found:**
- Output note: "💡 No project-specific code-reviewer found. Will use generic Task subagent for feasibility checks.\n   For project-tailored reviews, generate one:\n   `gen-agent . --type code-reviewer`"

**If security-analyst found:**
- Output: "✅ Found project-specific security-analyst (available for security-focused plans)"

**If security-analyst not found:**
- Output note: "💡 No project-specific security-analyst found. Will use generic Task subagent for red team review.\n   For project-tailored analysis, generate one:\n   `gen-agent . --type security-analyst`"

Continue to Step 1.

## Step 1 — Context Discovery

Gather project context to inform the architect. All reads run in parallel (single message with multiple tool calls). This step runs regardless of the `--fast` flag.

Tool: `Glob`, `Read` (direct — coordinator does this)

**Parallel reads (single message):**

1. **Project patterns:** Read `./CLAUDE.md` (if exists). Extract key sections: architecture, conventions, tech stack, development rules.

2. **Recent plans:** Glob `./plans/*.md` (exclude `*.redteam.md`, `*.review.md`, `*.feasibility.md`, `*.code-review.md`, `*.qa-report.md`, `*.test-failure.log`, `*.summary.md`, `*.hardener.md`, `*.performance.md`, `*.qa.md`). Sort by modification time (newest first). Read up to 3 most recent plan files.

3. **Archived plans:** Glob `./plans/archive/*/*.md` (exclude `*.code-review.md`, `*.qa-report.md`). Sort by modification time (newest first). Read up to 2 most recent archived plan files.

**Construct `$CONTEXT_BLOCK`:**

Assemble the discovered context into a structured block:

---begin context block format---
## Discovered Project Context

### Project Patterns (from CLAUDE.md)
[Key architecture, conventions, tech stack, and development rules extracted from CLAUDE.md]
[If CLAUDE.md not found: "No CLAUDE.md found. Architect should establish project patterns."]

### Recent Plans
[For each of up to 3 recent plans: filename, title/goal line, status (APPROVED or not)]
[If no plans found: "No prior plans found. This appears to be the first planned feature."]

### Historical Plans (Archived)
[For each of up to 2 archived plans: filename, title/goal line]
[If no archived plans found: "No archived plans found."]
---end context block format---

**If CLAUDE.md does not exist:** Set patterns section to "No CLAUDE.md found." Continue to Step 2 (do not block).

**If no plans exist:** Set plans sections to "No prior plans found." Continue to Step 2 (do not block).

Continue to Step 2.

## Step 2 — Architect drafts plan

Invoke the project-level architect. If none found, use a Task subagent with general-purpose prompt.

**IMPORTANT:** When calling the Task tool, you MUST pass the exact model string `claude-opus-4-6` — do NOT use shorthand like `opus` which resolves to a different model.

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`

Prompt:
"Analyze the codebase and draft a Technical Implementation Plan for: $ARGUMENTS.

**Project Context (from Step 1 discovery):**

$CONTEXT_BLOCK

Use this context to:
- Align with existing project patterns and conventions from CLAUDE.md
- Avoid duplicating or conflicting with prior plans
- Reference relevant historical decisions where applicable
- Follow established naming conventions, directory structures, and architectural patterns"

Hard requirements for the plan:
- Must be self-contained and runnable by an Engineer without follow-ups.
- Must include: Goals, Non-Goals, Assumptions, Proposed Design, Interfaces/Schema changes, Data migration (if any), Rollout plan, Risks, Test plan (including the exact test command to run), Acceptance criteria, Task breakdown (listing every file to create or modify).
- Must include a `## Context Alignment` section documenting:
  - Which CLAUDE.md patterns this plan follows
  - Which prior plans (if any) this relates to or builds upon
  - Any deviations from established patterns, with justification

Context metadata block (append to end of plan):

---begin metadata format---
<!-- Context Metadata
discovered_at: [ISO timestamp]
claude_md_exists: [true or false]
recent_plans_consulted: [comma-separated list of plan filenames, or "none"]
archived_plans_consulted: [comma-separated list of plan filenames, or "none"]
-->
---end metadata format---

File output requirement:
- Save the plan to: `./plans/[feature-name].md`

Feature-name rules:
- Derive `[feature-name]` from $ARGUMENTS as a short slug:
  - lowercase
  - alphanumeric + hyphen only
  - max 40 chars
  - no trailing hyphen

## Step 3 — Red Team + Librarian + Feasibility review (parallel)

Run all three reviews **in parallel** — three `Task` tool calls in a single message.

**If `--fast` flag is set:** skip the red team call; run librarian and feasibility only.

### 3a — Red Team

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`

Task:
"You are a critical reviewer. Your job is to find weaknesses in the plan.

Critically analyze the plan at `./plans/[feature-name].md`.
Challenge assumptions, identify risks, find gaps in the rollout plan,
and stress-test the proposed design for failure modes.
Rate each finding: Critical / Major / Minor / Info.

Structure your output as:
## Verdict: PASS or FAIL
(FAIL if any Critical finding exists)

## Findings
(Each finding with severity rating: Critical / Major / Minor / Info)

Write your analysis to `./plans/[feature-name].redteam.md`
with the Verdict as the first heading after the metadata."

**Optional (security-specific plans only):** If `.claude/agents/security-analyst.md` was found in Step 0 AND the plan subject is security-related (e.g., authentication, authorization, cryptography, network), additionally invoke the security-analyst agent via `Task` and append its STRIDE analysis to the redteam artifact as a supplemental section. The Verdict from the primary Task subagent governs the pass/fail decision.

### 3b — Librarian (rules gate)

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`

Task:
"Review `./plans/[feature-name].md` against `./CLAUDE.md` project rules.
Identify conflicts, required adjustments, or missing constraints.

Additionally, check historical alignment:
- Verify the plan's `## Context Alignment` section exists and is substantive
- Confirm the plan does not contradict decisions documented in prior plans (check recent plans in `./plans/` if any exist)
- Confirm the plan follows patterns established in CLAUDE.md
- Flag if the context metadata block is missing or has `false` for claude_md_exists when a CLAUDE.md exists

Write `./plans/[feature-name].review.md` with:
- Verdict: PASS or FAIL
- Conflicts (bullet list, cite relevant rule headings)
- Historical alignment issues (bullet list, if any)
- Required edits (minimal, actionable)
- Optional suggestions"

### 3c — Feasibility review

Tool: `.claude/agents/code-reviewer.md` (if found), fallback to `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`

Task:
"Review `./plans/[feature-name].md` for technical feasibility.
Assess:
- Implementation complexity (realistic estimates vs. over-simplification)
- Missing edge cases or error handling
- Test coverage adequacy
- Breaking changes or backward compatibility risks
- Dependency/library assumptions

Write `./plans/[feature-name].feasibility.md` with:
- Verdict: PASS or FAIL
- Concerns (categorized: Critical / Major / Minor)
- Recommended adjustments"

## Step 4 — Revision loop (conditional)

**Trigger:** Step 3 produced any Critical or Major findings, OR a FAIL verdict from any reviewer.

**If no Critical/Major findings and no FAIL verdict:** skip to Step 5.

Re-invoke the architect to revise the plan using the same pattern as Step 2 (local `.claude/agents/senior-architect.md` preferred, Task subagent fallback — no MCP). MUST use exact model string `claude-opus-4-6`:

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`

Prompt:
"Revise the plan at `./plans/[feature-name].md` to address the findings in:
- `./plans/[feature-name].redteam.md` (if exists)
- `./plans/[feature-name].review.md`
- `./plans/[feature-name].feasibility.md`

Only change what is necessary to resolve Critical, Major, and FAIL-causing issues.
Do not expand scope. Overwrite `./plans/[feature-name].md` with the revised plan.

Preserve the `## Context Alignment` section and context metadata block.
If the review flagged historical alignment issues, address them in the revision."

Then re-run Step 3 (all three reviews in parallel) on the revised plan.

**Max 2 revision rounds total.** If after 2 rounds the plan still has Critical findings or a FAIL verdict, proceed to Step 5 (which will halt the workflow).

## Step 5 — Final verdict gate

Read the latest review artifacts:
- `./plans/[feature-name].review.md` (librarian)
- `./plans/[feature-name].redteam.md` (if exists — skipped in `--fast` mode)
- `./plans/[feature-name].feasibility.md` (code reviewer)

**If PASS (no unresolved Critical/Major, no FAIL verdict from any reviewer):**
- Append the following to `./plans/[feature-name].md`:

```
## Status: APPROVED
```

**Auto-commit plan and review artifacts (runs for both PASS and FAIL):**

Tool: `Bash`

Pre-flight checks — skip commit with warning if any fail:

1. Detached HEAD check: `git symbolic-ref HEAD >/dev/null 2>&1` — if this fails, HEAD is detached and commits would be orphaned.
2. In-progress operation check: test for `.git/rebase-merge`, `.git/rebase-apply`, `.git/MERGE_HEAD`, or `.git/CHERRY_PICK_HEAD` — if any exist, committing could finalize or corrupt the operation.
3. Pre-existing staged changes: if `git diff --cached --name-only` is non-empty, log a note but continue (pathspec commit protects against sweep).

Stage files individually with existence checks and build dynamic pathspec list (do NOT use a single `git add` with all paths — nonexistent paths cause fatal exit 128 and stage nothing; use `|| true` so the loop always exits 0 regardless of which files exist):

````bash
PLAN_FILES=""
for f in ./plans/[feature-name].md ./plans/[feature-name].redteam.md ./plans/[feature-name].review.md ./plans/[feature-name].feasibility.md; do
  [ -f "$f" ] && git add "$f" && PLAN_FILES="$PLAN_FILES $f" || true
done
````

Commit only if files were staged, using the dynamic pathspec list (do NOT hardcode all four paths — nonexistent paths in the pathspec cause `git commit` to fail with exit 1). Use `--` pathspec to limit commit to plan files only (do not sweep user's staged changes):

If APPROVED:
````bash
[ -n "$PLAN_FILES" ] && git commit -m "$(cat <<'EOF'
feat(plans): approve [feature-name] blueprint

Plan approved by /dream v3.0.0 with all review gates passed.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)" -- $PLAN_FILES
````

If FAIL:
````bash
[ -n "$PLAN_FILES" ] && git commit -m "$(cat <<'EOF'
chore(plans): save failed [feature-name] blueprint

Plan did not pass /dream v3.0.0 review gates. Committing artifacts for reference.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)" -- $PLAN_FILES
````

If git commit succeeds: append to output: "Plan and review artifacts committed to git."

If pre-flight checks fail or git commit fails: append to output: "Auto-commit skipped/failed ([reason]). Files remain on disk. Commit manually: `git add ./plans/[feature-name].* && git commit -m 'chore(plans): save [feature-name] blueprint'`"

Do NOT change the verdict based on commit success or failure.

- Output (PASS): "Plan approved. Run `/ship plans/[feature-name].md` to implement."

**If FAIL or unresolved Critical findings after max revisions:**
- Do NOT append approval status.
- Run the **Auto-commit** step above (same pre-flight checks, staging loop, and commit — but use the FAIL commit message with `chore(plans):` prefix).
- Output: "Plan not approved. Blocking issues:" followed by the unresolved Critical/Major findings from all reviewers.
- Stop the workflow.
