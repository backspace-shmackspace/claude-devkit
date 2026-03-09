---
name: test-idempotent
description: Test idempotency
model: claude-opus-4-6
version: 1.0.1
---
# /test-idempotent Workflow

## Role

This skill is a **pipeline coordinator**. It orchestrates a sequential workflow with validation checkpoints at each stage. It delegates work to specialized agents, runs verification steps, and gates progression based on quality verdicts.

## Inputs
- Input file or parameters: $ARGUMENTS

## Step 0 — Pre-flight checks

Verify the environment is ready for the workflow.

Tool: `Bash` (direct — coordinator does this)

**Checks:**
- Git working directory is clean: `git status --porcelain` returns empty
- [TODO: Add other environment checks]

**If checks fail:**
- Output clear error message about which check failed
- Stop the workflow

## Step 1 — Read and validate input

Parse and validate the input from $ARGUMENTS.

Tool: `Read` (if reading a file) or direct validation (if parsing arguments)

**Extract from input:**
- [TODO: List key parameters to extract]
- [TODO: Define validation rules]

**Validate structure:**
- [TODO: Required sections or fields]
- [TODO: Format requirements]

**If validation fails:**
- Output: "Input validation failed: [specific issue]"
- Stop the workflow

Derive `[name]` from input (e.g., filename without extension).

## Step 2 — Execute main task

Delegate the core work to a specialized agent.

Tool: `Task` (subagent_type=general-purpose, model=claude-sonnet-4-5)

Prompt:
"You are executing a task. [TODO: Describe the task].

Read the `.claude/agents/` directory to find the appropriate agent (coder, analyst, etc.) and follow its standards.

**Requirements:**
- [TODO: Specify output format]
- [TODO: Specify quality criteria]
- [TODO: Specify file outputs]

Hard rules:
- Follow the specifications exactly
- Do not expand scope
- If blocked, write `BLOCKED.md` explaining why and stop"

Expected outputs:
- [TODO: List expected files or state changes]

## Step 3 — Quality review

Review the output from Step 2 for quality and correctness.

Tool: `Task` (subagent_type=general-purpose, model=claude-sonnet-4-5)

Prompt:
"You are reviewing work output. [TODO: Describe what to review].

Read the `.claude/agents/` directory to find the code-reviewer or qa-engineer agent and follow its review standards.

Review [TODO: specify what to review] against [TODO: specify criteria].

Write your review to `./plans/[name].review.md` with:
- **Verdict:** PASS / REVISION_NEEDED / FAIL
- **Critical findings** (must fix)
- **Major findings** (should fix)
- **Minor findings** (optional improvements)
- **Positives** (what was done well)

PASS means no Critical or Major findings remain."

## Step 4 — Revision loop (conditional)

**Trigger:** Step 3 verdict is `REVISION_NEEDED`.

**If Step 3 verdict is PASS:** Skip to Step 5.
**If Step 3 verdict is FAIL:** Stop the workflow with error message.

### 4a — Fix issues

Tool: `Task` (subagent_type=general-purpose, model=claude-sonnet-4-5)

Prompt:
"Read the review at `./plans/[name].review.md`.
Address all Critical and Major findings. Do not change anything else.
Read `.claude/agents/` to find the appropriate agent and follow its standards."

### 4b — Re-review

Re-run Step 3 (same tool, same prompt). This produces an updated `./plans/[name].review.md`.

**Max 2 revision rounds total.** If still REVISION_NEEDED or FAIL after 2 rounds:
- Stop the workflow
- Output: "Review did not converge after 2 rounds. See `./plans/[name].review.md`."

## Step 5 — Automated validation

Run automated tests or validation checks.

Tool: `Bash` (direct — coordinator does this)

**Test command:** [TODO: Specify test command from input or standard location]

If exit code is 0: Proceed to Step 6.

If exit code is non-zero:
- Write test output to `./plans/[name].test-failure.log`
- Stop the workflow
- Output: "Automated validation failed. See `./plans/[name].test-failure.log`."

## Step 6 — Final QA validation

Perform final acceptance testing against criteria.

Tool: `Task` (subagent_type=general-purpose, model=claude-sonnet-4-5)

Prompt:
"You are performing final QA validation.

Read `.claude/agents/` to find the qa-engineer agent and follow its validation standards.

Validate against these criteria:
- [TODO: List acceptance criteria]

Write `./plans/[name].qa-report.md` with:
- **Verdict:** PASS / PASS_WITH_NOTES / FAIL
- **Coverage checklist** (criterion → met/not met)
- **Missing tests or edge cases**
- **Notes** (non-blocking observations)"

## Step 7 — Completion gate

Read `./plans/[name].qa-report.md` and check the verdict.

Tool: `Read`

**If PASS or PASS_WITH_NOTES:**

1. [TODO: Define success actions - e.g., commit, deploy, notify]

2. Archive artifacts:
   - Tool: `Bash`
   - Command:
     ```bash
     mkdir -p ./plans/archive/[name]/[timestamp]
     mv ./plans/[name].review.md ./plans/[name].qa-report.md ./plans/archive/[name]/[timestamp]/
     ```

3. Output success message:
   - "✅ Workflow complete. [TODO: Next steps]"
   - "Artifacts archived to ./plans/archive/[name]/[timestamp]/"

**If FAIL:**
- Do NOT proceed with success actions
- Output: "❌ Final validation failed. See `./plans/[name].qa-report.md`."
- Stop the workflow

<!-- Generated by claude-tools/generators/generate_skill.py v1.0.0 -->
<!-- Archetype: pipeline | Generated: 2026-02-08T15-26-24 -->
