# Plan: Task Model Fix + Context Preservation

## Context

### Problem Statement

Three issues affect the claude-devkit skill suite:

1. **P0 -- Vertex AI Incompatibility:** 15 `Task` tool calls across 5 skills use short model aliases (`model=opus`, `model=sonnet`). These aliases resolve correctly on Anthropic's API but fail on Vertex AI, which requires fully-qualified model IDs (`claude-opus-4-6`, `claude-sonnet-4-5`).

2. **P1 -- No Architectural Context in /dream:** The `/dream` skill's architect step operates without knowledge of existing project patterns, prior plans, or historical decisions. This produces plans that may conflict with established conventions or duplicate prior work.

3. **P2 -- No Pattern Validation in /ship:** The `/ship` skill implements plans without verifying alignment to CLAUDE.md patterns. Plans from external sources or stale plans can introduce inconsistencies.

### Current State

| Skill | Version | Short Aliases | Affected Lines |
|-------|---------|---------------|----------------|
| dream | 2.1.0 | 2 (`model=opus`) | 42, 116 |
| ship | 3.1.0 | 6 (`model=sonnet`) | 91, 117, 194, 371, 401, 463 |
| audit | 2.0.0 | 2 (`model=sonnet`) | 79, 144 |
| sync | 2.0.0 | 1 (`model=sonnet`) | 118 |
| test-idempotent | 1.0.0 | 4 (`model=sonnet`) | 54, 78, 105, 139 |
| **Total** | | **15** | |

> **Note:** The original request referenced 16 instances. The actual count is 15. The 5 frontmatter `model:` fields already use full IDs (`claude-opus-4-6`, `claude-sonnet-4-5`) and do not need changes.

> **Pre-existing registry drift:** CLAUDE.md shows dream version as `2.0.0`, but `skills/dream/SKILL.md` frontmatter is already `2.1.0`. CLAUDE.md also shows `opus-4-6` for the sync skill model, but `skills/sync/SKILL.md` uses `claude-sonnet-4-5`. This plan corrects both pre-existing inconsistencies.

### Constraints

- All changes must be backward-compatible with Anthropic API (full IDs work on both platforms).
- `/dream` context discovery must not add more than ~5 seconds to wall-clock time (parallel reads).
- `/ship` pattern validation must be warnings-only (non-blocking) to avoid breaking existing workflows.
- Version numbers must be bumped for each modified skill.
- **All step headers must use integer-only step numbers** to satisfy the skill validator regex `r'^## Step (\d+)( —|--) (.+)$'`. Fractional (0.5) and letter-suffixed (1b) step numbers are invalid.

---

## Architectural Analysis

### Key Drivers

1. **Platform Portability** -- Skills must work on both Anthropic API and Vertex AI.
2. **Plan Quality** -- Architects need historical context to produce plans aligned with existing patterns.
3. **Implementation Safety** -- Catching pattern violations before coding prevents rework.

### Trade-offs

| Decision | Option A | Option B | Chosen | Rationale |
|----------|----------|----------|--------|-----------|
| Model ID format | Full IDs everywhere | Alias mapping layer | A (Full IDs) | Simpler, no runtime dependency, works on all platforms |
| Context discovery depth | Last 3 plans + 2 archived | All plans | 3+2 | Balances context breadth vs. token cost; most relevance is recent |
| Pattern validation strictness | Hard block | Warnings only | Warnings | Non-blocking preserves user autonomy; avoids false-positive stalls |
| Context metadata location | Inline in plan | Separate metadata file | Inline | Single file is simpler; metadata is small; easier for /ship to parse |
| Step numbering for new steps | Fractional/letter suffixed | Renumber all steps sequentially | Sequential integers | Validator regex requires `\d+`; fractional/letter steps are invisible to validation |
| Context discovery + --fast | Skip context discovery with --fast | Always run context discovery | Always run | Context discovery improves plan quality even for fast/low-risk plans; overhead is <5s with parallel reads |

### Principles Applied

- **Fail-safe defaults:** Pattern validation warns but does not block.
- **Single source of truth:** CLAUDE.md is the canonical pattern reference.
- **Minimal coupling:** Context discovery reads existing files; no new dependencies.
- **Backward compatibility:** All changes are additive; no existing behavior is removed.
- **Validator compliance:** All step headers use integer-only numbers per Pattern #2.

---

## Goals

1. Replace all 15 short model aliases with fully-qualified model IDs across all 5 skills.
2. Add a new "Step 1 -- Context Discovery" phase to `/dream` (renumbering existing Steps 1-4 to Steps 2-5) that gathers project context before the architect runs.
3. Enhance the `/dream` architect prompt to incorporate discovered context.
4. Enhance the `/dream` librarian review to check historical alignment.
5. Add a "Context Alignment" section requirement to `/dream` plan output.
6. Add context metadata block to `/dream` plan output format.
7. Add a new "Step 2 -- Pattern Validation" phase to `/ship` (renumbering existing Steps 2-5 to Steps 3-6) that validates plans against CLAUDE.md patterns.
8. Update CLAUDE.md skill registry with new version numbers, correct sync model, and accurate step counts.

## Non-Goals

- Migrating MCP agent invocations (these do not use model aliases).
- Adding context discovery to `/audit` or `/sync` (out of scope for this iteration).
- Making pattern validation a hard gate in `/ship` (explicitly warnings-only).
- Changing the `model:` field in YAML frontmatter (already uses full IDs).
- Adding new dependencies or external tools.
- Modifying the skill validator regex (step headers must comply with the existing regex).

## Assumptions

1. `claude-opus-4-6` and `claude-sonnet-4-5` are the correct full model IDs for the current deployment.
2. The `Task` tool accepts `model=claude-opus-4-6` and `model=claude-sonnet-4-5` as valid values.
3. `Glob` and `Read` tools are available for context discovery (already used in existing steps).
4. Plans in `./plans/` follow the naming convention `[feature-name].md`.
5. Archived plans live in `./plans/archive/[feature-name]/`.

---

## Proposed Design

### Part 1 (P0): Model Alias Fix

**Approach:** Find-and-replace all 15 instances of short aliases with full IDs. No logic changes.

- `model=opus` --> `model=claude-opus-4-6`
- `model=sonnet` --> `model=claude-sonnet-4-5`

### Part 2 (P1): Context Discovery in /dream

**Approach:** Insert a new step and renumber all subsequent steps.

**New step numbering for /dream (6 steps total):**

| Old Step | New Step | Name |
|----------|----------|------|
| Step 0 | Step 0 | Pre-flight (optional) |
| (new) | Step 1 | Context Discovery |
| Step 1 | Step 2 | Architect drafts plan |
| Step 2 | Step 3 | Red Team + Librarian + Feasibility review (parallel) |
| Step 3 | Step 4 | Revision loop (conditional) |
| Step 4 | Step 5 | Final verdict gate |

**New Step 1 -- Context Discovery:**
1. Read `CLAUDE.md` (project patterns and conventions).
2. Glob for `./plans/*.md` and read the 3 most recent plans (by modification time).
3. Glob for `./plans/archive/**/*.md` and read the 2 most recent archived plans.
4. All reads happen in parallel (single message with multiple tool calls).
5. Construct a `$CONTEXT_BLOCK` variable containing discovered patterns and plan summaries.

**Context discovery runs regardless of the `--fast` flag.** The `--fast` flag only affects Step 3 (skipping the red team review). Context discovery is lightweight (<5s with parallel reads) and improves plan quality even for low-risk changes.

**Enhanced Step 2 prompt:** Inject `$CONTEXT_BLOCK` into the architect's prompt so it has full project awareness.

**Enhanced Step 3b librarian prompt:** Add instruction to check historical alignment.

**New plan output requirement:** Plans must include a `## Context Alignment` section and a metadata block.

### Part 3 (P2): Pattern Validation in /ship

**Approach:** Insert a new step and renumber all subsequent steps.

**New step numbering for /ship (7 steps total):**

| Old Step | New Step | Name |
|----------|----------|------|
| Step 0 | Step 0 | Pre-flight checks |
| Step 1 | Step 1 | Coordinator reads plan |
| (new) | Step 2 | Pattern Validation (warnings only) |
| Step 2 | Step 3 | Implementation (with worktree isolation) |
| Step 3 | Step 4 | Parallel verification |
| Step 4 | Step 5 | Revision loop (conditional) |
| Step 5 | Step 6 | Commit gate |

**New Step 2 -- Pattern Validation:**
1. Read `CLAUDE.md` to extract key patterns.
2. Compare plan contents against patterns (naming conventions, directory structure, test requirements).
3. Output warnings for mismatches.
4. User can acknowledge warnings and continue (non-blocking).

---

## Implementation Plan

### Phase 1: Fix Model Aliases (P0)

**Priority:** P0 (Critical -- blocks Vertex AI users)
**Estimated effort:** 30 minutes
**Files modified:** 5

#### 1.1 Fix `skills/dream/SKILL.md` (2 instances)

**Change 1 -- Line 42 (Step 1 architect invocation, which becomes Step 2 after renumbering):**

OLD:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=opus`
```

NEW:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`
```

**Change 2 -- Line 116 (Step 3 revision loop architect invocation, which becomes Step 4 after renumbering):**

OLD:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=opus`
```

NEW:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`
```

#### 1.2 Fix `skills/ship/SKILL.md` (6 instances)

**Change 1 -- Line 91 (Step 2 single work group coder, which becomes Step 3 after renumbering):**

OLD:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=sonnet`
```

NEW:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`
```

**Change 2 -- Line 117 (Step 2a shared dependencies coder, which becomes Step 3a after renumbering):**

OLD:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=sonnet`
```

NEW:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`
```

**Change 3 -- Line 194 (Step 2c parallel worktree coders, which becomes Step 3c after renumbering):**

OLD:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=sonnet` — **dispatch one coder per work group in parallel (multiple Task calls in single message)**
```

NEW:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5` — **dispatch one coder per work group in parallel (multiple Task calls in single message)**
```

**Change 4 -- Line 371 (Step 3a code review, which becomes Step 4a after renumbering):**

OLD:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=sonnet`
```

NEW:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`
```

**Change 5 -- Line 401 (Step 3c QA validation, which becomes Step 4c after renumbering):**

OLD:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=sonnet`
```

NEW:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`
```

**Change 6 -- Line 463 (Step 4a coder fixes, single work group path, which becomes Step 5a after renumbering):**

OLD:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=sonnet`
```

NEW:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`
```

#### 1.3 Fix `skills/audit/SKILL.md` (2 instances)

**Change 1 -- Line 79 (Step 3 performance scan):**

OLD:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=sonnet`
```

NEW:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`
```

**Change 2 -- Line 144 (Step 4 QA regression):**

OLD:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=sonnet`
```

NEW:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`
```

#### 1.4 Fix `skills/sync/SKILL.md` (1 instance)

**Change 1 -- Line 118 (Step 4 documentation updater):**

OLD:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=sonnet`
```

NEW:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`
```

#### 1.5 Fix `skills/test-idempotent/SKILL.md` (4 instances)

> **Note:** This skill uses parentheses format instead of backtick format. Preserve the existing style.

**Change 1 -- Line 54 (Step 2 execute main task):**

OLD:
```
Tool: `Task` (subagent_type=general-purpose, model=sonnet)
```

NEW:
```
Tool: `Task` (subagent_type=general-purpose, model=claude-sonnet-4-5)
```

**Change 2 -- Line 78 (Step 3 quality review):**

OLD:
```
Tool: `Task` (subagent_type=general-purpose, model=sonnet)
```

NEW:
```
Tool: `Task` (subagent_type=general-purpose, model=claude-sonnet-4-5)
```

**Change 3 -- Line 105 (Step 4a fix issues):**

OLD:
```
Tool: `Task` (subagent_type=general-purpose, model=sonnet)
```

NEW:
```
Tool: `Task` (subagent_type=general-purpose, model=claude-sonnet-4-5)
```

**Change 4 -- Line 139 (Step 6 final QA validation):**

OLD:
```
Tool: `Task` (subagent_type=general-purpose, model=sonnet)
```

NEW:
```
Tool: `Task` (subagent_type=general-purpose, model=claude-sonnet-4-5)
```

#### 1.6 Update Version Numbers

After applying all model fixes, bump versions in YAML frontmatter:

| File | Old Version | New Version | Reason |
|------|-------------|-------------|--------|
| `skills/dream/SKILL.md` | 2.1.0 | 2.2.0 | P0 + P1 (new feature) |
| `skills/ship/SKILL.md` | 3.1.0 | 3.2.0 | P0 + P2 (new feature) |
| `skills/audit/SKILL.md` | 2.0.0 | 2.0.1 | P0 only (bugfix) |
| `skills/sync/SKILL.md` | 2.0.0 | 2.0.1 | P0 only (bugfix) |
| `skills/test-idempotent/SKILL.md` | 1.0.0 | 1.0.1 | P0 only (bugfix) |

**Exact frontmatter changes:**

`skills/dream/SKILL.md`:
```
OLD: version: 2.1.0
NEW: version: 2.2.0
```

`skills/ship/SKILL.md`:
```
OLD: version: 3.1.0
NEW: version: 3.2.0
```

`skills/audit/SKILL.md`:
```
OLD: version: 2.0.0
NEW: version: 2.0.1
```

`skills/sync/SKILL.md`:
```
OLD: version: 2.0.0
NEW: version: 2.0.1
```

`skills/test-idempotent/SKILL.md`:
```
OLD: version: 1.0.0
NEW: version: 1.0.1
```

#### 1.7 Validation

```bash
# Verify no short aliases remain
grep -rn 'model=opus\b\|model=sonnet\b' skills/*/SKILL.md
# Expected: no output (exit code 1)

# Verify full IDs are present
grep -rn 'model=claude-opus-4-6\|model=claude-sonnet-4-5' skills/*/SKILL.md
# Expected: 15 lines

# Run skill validator on all skills
python3 generators/validate_skill.py skills/dream/SKILL.md
python3 generators/validate_skill.py skills/ship/SKILL.md
python3 generators/validate_skill.py skills/audit/SKILL.md
python3 generators/validate_skill.py skills/sync/SKILL.md
python3 generators/validate_skill.py skills/test-idempotent/SKILL.md
# Expected: all exit code 0
```

---

### Phase 2: Context Discovery in /dream (P1)

**Priority:** P1 (Important -- improves plan quality)
**Estimated effort:** 1 hour
**Files modified:** 1 (`skills/dream/SKILL.md`)
**Dependencies:** Phase 1 must be applied first (version bump coordination)

#### 2.1 Renumber Existing Steps

All existing steps must be renumbered to accommodate the new Step 1. The following step header changes are required:

**Step 0 stays as Step 0** (no change to header):
```
## Step 0 — Pre-flight (optional)
```

The internal reference at the end of Step 0 must change:

OLD:
```
Continue to Step 1.
```

NEW:
```
Continue to Step 1.
```

(No change needed -- "Continue to Step 1" is still correct since the new step IS Step 1.)

**Old Step 1 becomes Step 2:**

OLD:
```
## Step 1 — Architect drafts plan
```

NEW:
```
## Step 2 — Architect drafts plan
```

**Old Step 2 becomes Step 3:**

OLD:
```
## Step 2 — Red Team + Librarian + Feasibility review (parallel)
```

NEW:
```
## Step 3 — Red Team + Librarian + Feasibility review (parallel)
```

Sub-step headers also renumber:

OLD:
```
### 2a — Red Team
### 2b — Librarian (rules gate)
### 2c — Feasibility review
```

NEW:
```
### 3a — Red Team
### 3b — Librarian (rules gate)
### 3c — Feasibility review
```

**Old Step 3 becomes Step 4:**

OLD:
```
## Step 3 — Revision loop (conditional)
```

NEW:
```
## Step 4 — Revision loop (conditional)
```

Internal references within Step 4 must update:

OLD (line 112):
```
**If no Critical/Major findings and no FAIL verdict:** skip to Step 4.
```

NEW:
```
**If no Critical/Major findings and no FAIL verdict:** skip to Step 5.
```

OLD (line 127):
```
Then re-run Step 2 (all three reviews in parallel) on the revised plan.
```

NEW:
```
Then re-run Step 3 (all three reviews in parallel) on the revised plan.
```

OLD (line 129):
```
**Max 2 revision rounds total.** If after 2 rounds the plan still has Critical findings or a FAIL verdict, proceed to Step 4 (which will halt the workflow).
```

NEW:
```
**Max 2 revision rounds total.** If after 2 rounds the plan still has Critical findings or a FAIL verdict, proceed to Step 5 (which will halt the workflow).
```

**Old Step 4 becomes Step 5:**

OLD:
```
## Step 4 — Final verdict gate
```

NEW:
```
## Step 5 — Final verdict gate
```

#### 2.2 Insert Step 1 -- Context Discovery

Insert the following new section between the end of Step 0 (after `Continue to Step 1.`) and the renamed Step 2 (formerly Step 1):

**Insert AFTER `Continue to Step 1.` and BEFORE the renamed `## Step 2 — Architect drafts plan`:**

```
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
```

> **Implementation note:** The context block format above uses `---begin/end---` delimiters instead of triple-backtick code fences to avoid nested fence issues when this is embedded inside the SKILL.md file. The implementer should use these delimiters literally in the SKILL.md, not convert them to code fences.

#### 2.3 Enhance Step 2 (formerly Step 1) Architect Prompt

Replace the existing architect prompt block in the renamed Step 2 with an enhanced version that includes the discovered context.

OLD:
```
Prompt:
"Analyze the codebase and draft a Technical Implementation Plan for: $ARGUMENTS."

Hard requirements for the plan:
- Must be self-contained and runnable by an Engineer without follow-ups.
- Must include: Goals, Non-Goals, Assumptions, Proposed Design, Interfaces/Schema changes, Data migration (if any), Rollout plan, Risks, Test plan (including the exact test command to run), Acceptance criteria, Task breakdown (listing every file to create or modify).

File output requirement:
- Save the plan to: `./plans/[feature-name].md`

Feature-name rules:
- Derive `[feature-name]` from $ARGUMENTS as a short slug:
  - lowercase
  - alphanumeric + hyphen only
  - max 40 chars
  - no trailing hyphen
```

NEW:
```
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
```

> **Implementation note for nested code fences:** The context metadata format above uses `---begin/end metadata format---` delimiters to avoid triple-backtick nesting in the SKILL.md. The implementer should use these delimiters literally, not convert them to markdown code fences. The actual metadata block that the architect appends to plans uses HTML comments (`<!-- -->`), which do not require code fencing.

> **Change from v1:** `claude_md_hash` has been replaced with `claude_md_exists: [true or false]`. The original hash field required SHA256 computation that LLM agents cannot natively perform without a Bash call, creating a risk of hallucinated hash values. A simple boolean is sufficient because `/ship` Step 2 reads the current CLAUDE.md directly for pattern validation.

#### 2.4 Enhance Step 3b (formerly Step 2b) Librarian Prompt

Add historical alignment checking to the librarian's review task.

OLD:
```
### 2b — Librarian (rules gate)

Tool: `mcp__agent-factory__agent_librarian_v1` (MCP)

Task:
"Review `./plans/[feature-name].md` against `./CLAUDE.md` project rules.
Identify conflicts, required adjustments, or missing constraints.
Write `./plans/[feature-name].review.md` with:
- Verdict: PASS or FAIL
- Conflicts (bullet list, cite relevant rule headings)
- Required edits (minimal, actionable)
- Optional suggestions"
```

NEW:
```
### 3b — Librarian (rules gate)

Tool: `mcp__agent-factory__agent_librarian_v1` (MCP)

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
```

#### 2.5 Enhance Step 4 (formerly Step 3) Revision Loop Prompt

Update the revision architect prompt to preserve context alignment during revisions.

OLD:
```
Tool: `Task`, `subagent_type=general-purpose`, `model=opus`

Prompt:
"Revise the plan at `./plans/[feature-name].md` to address the findings in:
- `./plans/[feature-name].redteam.md` (if exists)
- `./plans/[feature-name].review.md`
- `./plans/[feature-name].feasibility.md`

Only change what is necessary to resolve Critical, Major, and FAIL-causing issues.
Do not expand scope. Overwrite `./plans/[feature-name].md` with the revised plan."
```

NEW:
```
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
```

#### 2.6 Update Step 5 (formerly Step 4) Internal References

The renamed Step 5 references review artifacts from Step 3 (formerly Step 2). The sub-step references within the verdict gate already use filenames, not step numbers, so no changes are needed to the artifact paths. The step header change is covered in section 2.1.

#### 2.7 Validation (Phase 2)

```bash
# Validate dream skill structure (must pass with integer step numbers)
python3 generators/validate_skill.py skills/dream/SKILL.md
# Expected: exit code 0

# Verify Step 1 Context Discovery exists with integer header
grep -c '## Step 1 — Context Discovery' skills/dream/SKILL.md
# Expected: 1

# Verify old Step 0.5 does NOT exist
grep -c 'Step 0.5' skills/dream/SKILL.md
# Expected: 0

# Verify step renumbering: Steps 0-5 exist
grep -c '## Step 0' skills/dream/SKILL.md   # Expected: 1
grep -c '## Step 1' skills/dream/SKILL.md   # Expected: 1
grep -c '## Step 2' skills/dream/SKILL.md   # Expected: 1
grep -c '## Step 3' skills/dream/SKILL.md   # Expected: 1
grep -c '## Step 4' skills/dream/SKILL.md   # Expected: 1
grep -c '## Step 5' skills/dream/SKILL.md   # Expected: 1

# Verify Context Alignment requirement
grep -c 'Context Alignment' skills/dream/SKILL.md
# Expected: at least 2 (one in Step 2, one in Step 3b)

# Verify context metadata block template
grep -c 'Context Metadata' skills/dream/SKILL.md
# Expected: 1

# Verify no short aliases remain
grep -c 'model=opus' skills/dream/SKILL.md
# Expected: 0

# Verify --fast flag documentation
grep -c 'regardless of the .--fast. flag' skills/dream/SKILL.md
# Expected: 1
```

---

### Phase 3: Pattern Validation in /ship (P2)

**Priority:** P2 (Enhancement -- improves implementation safety)
**Estimated effort:** 45 minutes
**Files modified:** 1 (`skills/ship/SKILL.md`)
**Dependencies:** Phase 1 must be applied first (version bump coordination)

#### 3.1 Renumber Existing Steps

All steps from Step 2 onward must be renumbered to accommodate the new Step 2.

**Steps 0 and 1 stay unchanged:**
```
## Step 0 — Pre-flight checks
## Step 1 — Coordinator reads plan
```

**Old Step 2 becomes Step 3:**

OLD:
```
## Step 2 — Implementation (with worktree isolation)
```

NEW:
```
## Step 3 — Implementation (with worktree isolation)
```

Sub-step headers also renumber:

OLD:
```
#### Step 2a — Shared Dependencies (if exists)
#### Step 2b — Create Worktrees
#### Step 2c — Dispatch Coders to Worktrees
#### Step 2d — File Boundary Validation
#### Step 2e — Merge Worktrees
#### Step 2f — Cleanup Worktrees
```

NEW:
```
#### Step 3a — Shared Dependencies (if exists)
#### Step 3b — Create Worktrees
#### Step 3c — Dispatch Coders to Worktrees
#### Step 3d — File Boundary Validation
#### Step 3e — Merge Worktrees
#### Step 3f — Cleanup Worktrees
```

Internal references within Step 3 sub-steps must also update:

- "Skip to Step 3" (in single work group path) becomes "Skip to Step 4"
- "continue to Step 2e" becomes "continue to Step 3e"
- "do not proceed to Step 2e" becomes "do not proceed to Step 3e"
- "Step 2b" references within Step 4a become "Step 3b"
- "Step 2c" references become "Step 3c"
- "Step 2d" references become "Step 3d"
- "Step 2e" references become "Step 3e"
- "Step 2f" references become "Step 3f"
- The WIP commit message referencing "v3.1.0" should update to "v3.2.0"

**Old Step 3 becomes Step 4:**

OLD:
```
## Step 3 — Parallel verification
```

NEW:
```
## Step 4 — Parallel verification
```

Sub-step headers renumber:

OLD:
```
### 3a — Code review
### 3b — Run tests
### 3c — QA validation
```

NEW:
```
### 4a — Code review
### 4b — Run tests
### 4c — QA validation
```

Internal reference: "Proceed to Step 5 (commit)" becomes "Proceed to Step 6 (commit)"

**Old Step 4 becomes Step 5:**

OLD:
```
## Step 4 — Revision loop (conditional)
```

NEW:
```
## Step 5 — Revision loop (conditional)
```

Sub-step headers renumber:

OLD:
```
### 4a — Coder fixes
### 4b — Re-verify in parallel
```

NEW:
```
### 5a — Coder fixes
### 5b — Re-verify in parallel
```

Internal references:
- "Step 3 code review" becomes "Step 4 code review"
- "Step 3 all checks PASS: skip to Step 5" becomes "Step 4 all checks PASS: skip to Step 6"
- "Re-run Step 3 in its entirety" becomes "Re-run Step 4 in its entirety"
- "Step 3" references in result matrix become "Step 4"

**Old Step 5 becomes Step 6:**

OLD:
```
## Step 5 — Commit gate
```

NEW:
```
## Step 6 — Commit gate
```

Internal references:
- "committed in Step 2a" becomes "committed in Step 3a"

#### 3.2 Insert Step 2 -- Pattern Validation

Insert the following new section between the end of Step 1 and the renamed Step 3 (formerly Step 2):

OLD (the transition from Step 1 to Step 2):
```
If no `## Work Groups` section exists, treat the entire Task Breakdown as a single group (current behavior).

## Step 2 — Implementation (with worktree isolation)
```

NEW:
```
If no `## Work Groups` section exists, treat the entire Task Breakdown as a single group (current behavior).

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
```

#### 3.3 Validation (Phase 3)

```bash
# Validate ship skill structure (must pass with integer step numbers)
python3 generators/validate_skill.py skills/ship/SKILL.md
# Expected: exit code 0

# Verify Step 2 Pattern Validation exists with integer header
grep -c '## Step 2 — Pattern Validation' skills/ship/SKILL.md
# Expected: 1

# Verify old Step 1b does NOT exist
grep -c 'Step 1b' skills/ship/SKILL.md
# Expected: 0

# Verify step renumbering: Steps 0-6 exist
grep -c '## Step 0' skills/ship/SKILL.md   # Expected: 1
grep -c '## Step 1' skills/ship/SKILL.md   # Expected: 1
grep -c '## Step 2' skills/ship/SKILL.md   # Expected: 1
grep -c '## Step 3' skills/ship/SKILL.md   # Expected: 1
grep -c '## Step 4' skills/ship/SKILL.md   # Expected: 1
grep -c '## Step 5' skills/ship/SKILL.md   # Expected: 1
grep -c '## Step 6' skills/ship/SKILL.md   # Expected: 1

# Verify pattern validation is warnings-only
grep -c 'warnings only' skills/ship/SKILL.md
# Expected: at least 1

# Verify no short aliases remain
grep -c 'model=sonnet' skills/ship/SKILL.md
# Expected: 0
```

---

### Phase 4: Update CLAUDE.md Skill Registry

**Priority:** P1 (must reflect new versions)
**Estimated effort:** 15 minutes
**Files modified:** 1 (`CLAUDE.md`)

> **Note on pre-existing drift:** CLAUDE.md currently shows dream version as `2.0.0`, but `skills/dream/SKILL.md` frontmatter is already `2.1.0`. CLAUDE.md also shows `opus-4-6` as the model for the sync skill, but `skills/sync/SKILL.md` uses `claude-sonnet-4-5`. This phase corrects both pre-existing inconsistencies in addition to reflecting the new changes from this plan.

#### 4.1 Update Skill Registry Table

OLD (this is the actual current content of CLAUDE.md lines 70-74):
```
| **dream** | 2.0.0 | Architect → Red Team + Librarian (parallel) → Revision loop → Approval gate. Supports `--fast`. | opus-4-6 | 4 |
| **ship** | 3.1.0 | Pre-flight check → Read plan → Worktree isolation (for work groups) → Parallel coders → File boundary validation → Merge → Code review + tests + QA (parallel) → Revision loop → Commit gate. Structural conflict prevention. | opus-4-6 | 6 |
| **audit** | 2.0.0 | Scope detection (plan/code/full) → Security scan (hardener) + Performance scan → QA regression → Synthesis with PASS/PASS_WITH_NOTES/BLOCKED verdict → Structured reporting with timestamped artifacts. | opus-4-6 | 6 |
| **sync** | 2.0.0 | Detect changes (recent/full) → Detect undocumented env vars → Librarian review with CURRENT/UPDATES_NEEDED verdict → Apply updates → User verification with git diff → Archive review. | opus-4-6 | 6 |
| **test-idempotent** | 1.0.0 | Test skill idempotency and determinism. Runs skill multiple times, validates consistent outputs, reports variances. | opus-4-6 | 7 |
```

NEW:
```
| **dream** | 2.2.0 | Context discovery → Architect (with project context) → Red Team + Librarian + Feasibility (parallel) → Revision loop → Approval gate. Supports `--fast`. Context alignment and metadata in output. | opus-4-6 | 6 |
| **ship** | 3.2.0 | Pre-flight check → Read plan → Pattern validation (warnings) → Worktree isolation (for work groups) → Parallel coders → File boundary validation → Merge → Code review + tests + QA (parallel) → Revision loop → Commit gate. Structural conflict prevention. | opus-4-6 | 7 |
| **audit** | 2.0.1 | Scope detection (plan/code/full) → Security scan (hardener) + Performance scan → QA regression → Synthesis with PASS/PASS_WITH_NOTES/BLOCKED verdict → Structured reporting with timestamped artifacts. | opus-4-6 | 6 |
| **sync** | 2.0.1 | Detect changes (recent/full) → Detect undocumented env vars → Librarian review with CURRENT/UPDATES_NEEDED verdict → Apply updates → User verification with git diff → Archive review. | sonnet-4-5 | 6 |
| **test-idempotent** | 1.0.1 | Test skill idempotency and determinism. Runs skill multiple times, validates consistent outputs, reports variances. | opus-4-6 | 7 |
```

**Changes in the NEW block:**
- dream: `2.0.0` -> `2.2.0` (correcting pre-existing drift from 2.1.0 and adding P1 changes), description adds context discovery and feasibility, steps `4` -> `6`
- ship: `3.1.0` -> `3.2.0`, description adds pattern validation, steps `6` -> `7`
- audit: `2.0.0` -> `2.0.1` (P0 bugfix only)
- sync: `2.0.0` -> `2.0.1` (P0 bugfix only), model `opus-4-6` -> `sonnet-4-5` (correcting pre-existing inaccuracy to match actual frontmatter)
- test-idempotent: `1.0.0` -> `1.0.1` (P0 bugfix only)

#### 4.2 Validation (Phase 4)

```bash
# Verify CLAUDE.md has updated versions
grep '2.2.0\|3.2.0\|2.0.1\|1.0.1' CLAUDE.md
# Expected: 5 lines matching the new versions

# Verify sync model is now sonnet-4-5
grep 'sync.*sonnet-4-5' CLAUDE.md
# Expected: 1 line

# Verify dream step count is 6
grep 'dream.*| 6 |' CLAUDE.md
# Expected: 1 line

# Verify ship step count is 7
grep 'ship.*| 7 |' CLAUDE.md
# Expected: 1 line
```

---

### Phase 5: Deploy and Integration Test

**Priority:** Required
**Estimated effort:** 15 minutes
**Dependencies:** Phases 1-4 complete

#### 5.1 Deploy All Skills

```bash
cd /Users/imurphy/projects/claude-devkit
./scripts/deploy.sh
```

#### 5.2 Integration Smoke Test

Manual verification in a Claude Code session:

1. Start a new Claude Code session in a test project.
2. Run `/dream add a health check endpoint` and verify:
   - **Step 1** Context Discovery runs (expect to see "Discovered Project Context" heading in coordinator output before architect is invoked).
   - Architect prompt includes discovered context (expect `$CONTEXT_BLOCK` content visible in agent dispatch).
   - Output plan contains `## Context Alignment` section.
   - Output plan contains `<!-- Context Metadata` block with `claude_md_exists:` field.
   - **Step 3b** Librarian checks historical alignment (expect "Historical alignment issues" in review output).
3. Run `/ship plans/add-a-health-check-endpoint.md` and verify:
   - **Step 2** Pattern Validation runs after plan reading (expect "Pattern validation warnings" or "Plan aligns with CLAUDE.md patterns" in output).
   - Warnings are displayed but do not block (expect "These warnings are informational" if warnings exist).
   - Implementation proceeds to Step 3 normally.
4. Run `/audit code` and verify no model resolution errors.
5. Run `/sync` and verify no model resolution errors.
6. Run `/dream --fast add something simple` and verify:
   - Context Discovery (Step 1) still runs (not skipped by `--fast`).
   - Red Team review (Step 3a) is skipped.

**After reverting any phase, re-run `./scripts/deploy.sh`** to ensure deployed skills match the git state.

---

## Task Breakdown

### Files to Modify

| # | File | Changes | Phase |
|---|------|---------|-------|
| 1 | `skills/dream/SKILL.md` | Replace 2 model aliases, renumber Steps 1-4 to Steps 2-5, insert new Step 1 (Context Discovery), enhance Step 2 architect prompt, enhance Step 3b librarian prompt, enhance Step 4 revision prompt, add Context Alignment requirement, add context metadata format, bump version to 2.2.0 | 1, 2 |
| 2 | `skills/ship/SKILL.md` | Replace 6 model aliases, renumber Steps 2-5 to Steps 3-6 (including all sub-steps), insert new Step 2 (Pattern Validation), bump version to 3.2.0 | 1, 3 |
| 3 | `skills/audit/SKILL.md` | Replace 2 model aliases, bump version to 2.0.1 | 1 |
| 4 | `skills/sync/SKILL.md` | Replace 1 model alias, bump version to 2.0.1 | 1 |
| 5 | `skills/test-idempotent/SKILL.md` | Replace 4 model aliases, bump version to 1.0.1 | 1 |
| 6 | `CLAUDE.md` | Update skill registry table (versions, descriptions, step counts, sync model) | 4 |

### Files to Create

None.

---

## Test Plan

### Automated Tests

```bash
# 1. Verify no short model aliases remain in any skill
grep -rn 'model=opus\b\|model=sonnet\b' skills/*/SKILL.md
# Expected: no output, exit code 1

# 2. Verify all 15 instances now use full model IDs
grep -c 'model=claude-opus-4-6\|model=claude-sonnet-4-5' skills/dream/SKILL.md
# Expected: 2

grep -c 'model=claude-opus-4-6\|model=claude-sonnet-4-5' skills/ship/SKILL.md
# Expected: 6

grep -c 'model=claude-opus-4-6\|model=claude-sonnet-4-5' skills/audit/SKILL.md
# Expected: 2

grep -c 'model=claude-opus-4-6\|model=claude-sonnet-4-5' skills/sync/SKILL.md
# Expected: 1

grep -c 'model=claude-opus-4-6\|model=claude-sonnet-4-5' skills/test-idempotent/SKILL.md
# Expected: 4

# 3. Run skill validator on all modified skills
python3 generators/validate_skill.py skills/dream/SKILL.md && \
python3 generators/validate_skill.py skills/ship/SKILL.md && \
python3 generators/validate_skill.py skills/audit/SKILL.md && \
python3 generators/validate_skill.py skills/sync/SKILL.md && \
python3 generators/validate_skill.py skills/test-idempotent/SKILL.md
# Expected: all exit code 0

# 4. Run full test suite
bash generators/test_skill_generator.sh
# Expected: 26/26 tests pass

# 5. Verify new Step 1 exists in dream (integer format)
grep -c '## Step 1 — Context Discovery' skills/dream/SKILL.md
# Expected: 1

# 6. Verify NO fractional or lettered step numbers exist
grep -c 'Step 0\.5\|Step 1b' skills/dream/SKILL.md skills/ship/SKILL.md
# Expected: 0

# 7. Verify dream has 6 sequential integer steps (0-5)
grep -c '## Step [0-5]' skills/dream/SKILL.md
# Expected: 6

# 8. Verify new Step 2 exists in ship (integer format)
grep -c '## Step 2 — Pattern Validation' skills/ship/SKILL.md
# Expected: 1

# 9. Verify ship has 7 sequential integer steps (0-6)
grep -c '## Step [0-6]' skills/ship/SKILL.md
# Expected: 7

# 10. Verify Context Alignment requirement in dream
grep -c 'Context Alignment' skills/dream/SKILL.md
# Expected: at least 2

# 11. Verify context metadata block template in dream
grep -c 'Context Metadata' skills/dream/SKILL.md
# Expected: 1

# 12. Verify --fast flag interaction is documented
grep -c 'regardless of the .--fast. flag' skills/dream/SKILL.md
# Expected: 1

# 13. Verify CLAUDE.md registry versions updated
grep -c '2.2.0' CLAUDE.md     # Expected: at least 1 (dream)
grep -c '3.2.0' CLAUDE.md     # Expected: at least 1 (ship)

# 14. Verify sync model corrected in CLAUDE.md
grep 'sync.*sonnet-4-5' CLAUDE.md
# Expected: 1 line

# 15. Verify version bumps in frontmatter
head -6 skills/dream/SKILL.md | grep 'version: 2.2.0'
head -6 skills/ship/SKILL.md | grep 'version: 3.2.0'
head -6 skills/audit/SKILL.md | grep 'version: 2.0.1'
head -7 skills/sync/SKILL.md | grep 'version: 2.0.1'
head -6 skills/test-idempotent/SKILL.md | grep 'version: 1.0.1'
# Expected: all produce output (exit code 0)
```

### Manual Smoke Tests

1. **Vertex AI model resolution:** Deploy skills and invoke `/audit code` in a Vertex AI environment. Verify no "model not found" errors.
2. **Context discovery:** Run `/dream add a small feature` in a project with CLAUDE.md and existing plans. Verify the architect receives context. Expect "Discovered Project Context" in output.
3. **Pattern validation:** Run `/ship` with a plan that places files in non-standard directories. Verify warnings appear but workflow continues. Expect "Pattern validation warnings (non-blocking)" in output.
4. **Backward compatibility:** Run `/dream --fast add something simple` and verify `--fast` still works. Context discovery (Step 1) should run; red team review (Step 3a) should be skipped.

---

## Acceptance Criteria

### P0 -- Model Alias Fix
- [ ] All 15 `Task` tool calls use fully-qualified model IDs.
- [ ] Zero instances of `model=opus` or `model=sonnet` (short form) remain in any skill file.
- [ ] All 5 skill validators pass (exit code 0).
- [ ] Existing test suite (26 tests) passes.
- [ ] Skills deploy successfully via `deploy.sh`.

### P1 -- Context Discovery in /dream
- [ ] Step 1 (integer) exists and reads CLAUDE.md, recent plans (3), and archived plans (2) in parallel.
- [ ] Step 2 (formerly Step 1) architect prompt includes `$CONTEXT_BLOCK` with discovered context.
- [ ] Plan output requires `## Context Alignment` section.
- [ ] Plan output includes `<!-- Context Metadata` HTML comment block with `claude_md_exists` field.
- [ ] Step 3b (formerly Step 2b) librarian checks for historical alignment and context metadata presence.
- [ ] Step 4 (formerly Step 3) revision prompt preserves context alignment section.
- [ ] Dream skill version is 2.2.0.
- [ ] Graceful degradation: missing CLAUDE.md or no plans does not block the workflow.
- [ ] Context discovery runs regardless of `--fast` flag (explicitly documented in Step 1).
- [ ] All step headers use integer-only numbers (Steps 0-5).
- [ ] All internal step cross-references are updated to reflect new numbering.

### P2 -- Pattern Validation in /ship
- [ ] Step 2 (integer) exists between Step 1 (read plan) and Step 3 (implementation).
- [ ] Pattern validation reads CLAUDE.md and compares plan files against conventions.
- [ ] Warnings are displayed but do NOT block the workflow.
- [ ] Missing CLAUDE.md gracefully skips validation with informational message.
- [ ] Ship skill version is 3.2.0.
- [ ] All step headers use integer-only numbers (Steps 0-6).
- [ ] All internal step cross-references are updated to reflect new numbering.
- [ ] All sub-step headers (3a-3f, 4a-4c, 5a-5b) are updated to reflect new parent step numbers.

### Registry
- [ ] CLAUDE.md skill registry reflects new versions (2.2.0, 3.2.0, 2.0.1, 2.0.1, 1.0.1).
- [ ] CLAUDE.md skill descriptions updated to mention context discovery and pattern validation.
- [ ] CLAUDE.md step counts updated (dream: 6, ship: 7).
- [ ] CLAUDE.md sync model corrected from `opus-4-6` to `sonnet-4-5`.

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Full model IDs not recognized by Task tool | Low | High (blocks all skills) | Test on both Anthropic API and Vertex AI before committing. Full IDs are documented as the canonical format. |
| Context discovery adds latency to /dream | Low | Medium (slower planning) | All reads are parallel (single message). Cap at 3+2 plans. CLAUDE.md is typically small. |
| Pattern validation false positives in /ship | Medium | Low (warnings only) | Non-blocking by design. User can ignore and proceed. Pattern validation is best-effort and non-deterministic. |
| Step renumbering breaks internal cross-references | Medium | Medium (skill malfunction) | Exhaustive list of all cross-reference updates in Phases 2-3. Validator catches sequential numbering issues. Manual review of each cross-reference. |
| Large CLAUDE.md exceeds context window | Low | Medium (truncated context) | Read tool handles large files. Architect can work with partial context. Future iteration could extract only key sections. |
| Nested code fences corrupt SKILL.md during implementation | Low | High (broken skill) | Plan uses `---begin/end---` delimiters instead of triple-backtick fences for nested content. Implementation note warns against backtick conversion. |
| Glob exclusion pattern for plans misses new artifact types | Medium | Low (context pollution) | Documented as known limitation. Future iteration can switch to positive filtering (check for `## Status: APPROVED`). |

---

## Rollout Plan

1. **Phase 1 first** -- Apply model alias fixes and deploy. This is the safest change and unblocks Vertex AI users immediately.
2. **Phase 2 second** -- Apply context discovery to /dream (including step renumbering). Test in a project with existing plans.
3. **Phase 3 third** -- Apply pattern validation to /ship (including step renumbering). Test with plans that have varying alignment.
4. **Phase 4 last** -- Update CLAUDE.md registry after all skill changes are validated.
5. **Phase 5** -- Full deploy and integration test.

Each phase can be committed independently. If any phase introduces regressions, it can be reverted without affecting prior phases. **After reverting any phase, re-run `./scripts/deploy.sh`** to ensure deployed skills match the git state.

---

## Verification

- All 15 model aliases replaced with full IDs
- Dream skill has Step 1 (Context Discovery) with integer header and parallel reads
- Dream architect prompt includes `$CONTEXT_BLOCK`
- Dream plan output requires Context Alignment section and metadata block (with `claude_md_exists` instead of hash)
- Dream librarian checks historical alignment
- Dream context discovery runs regardless of `--fast` flag (documented)
- Dream steps are sequential integers 0-5 (6 total)
- Ship skill has Step 2 (Pattern Validation) with integer header and warnings-only behavior
- Ship steps are sequential integers 0-6 (7 total)
- All sub-step headers updated to match parent step numbers
- All internal cross-references updated for new numbering
- All 5 skill validators pass
- Full test suite (26 tests) passes
- CLAUDE.md registry reflects updated versions, descriptions, step counts
- CLAUDE.md sync model corrected to `sonnet-4-5`
- Skills deploy successfully
- No nested code fence issues in SKILL.md files

---

## Changes From Previous Plan Version

This is a revision addressing findings from three reviews:

| Finding | Source | Resolution |
|---------|--------|------------|
| **CRITICAL:** Validator rejects `Step 0.5` and `Step 1b` headers (regex requires `\d+` integers) | Librarian (FAIL), Red Team (CRITICAL-01), Feasibility (C1) | Renumbered all steps sequentially with integers. Dream: Steps 0-5. Ship: Steps 0-6. All internal cross-references updated. |
| **CRITICAL:** CLAUDE.md registry OLD text shows dream `2.0.0` but skill is `2.1.0` | Librarian (BLOCKING), Red Team (CRITICAL-02), Feasibility (M1) | Acknowledged pre-existing drift. Plan now documents that CLAUDE.md was already stale. Phase 4 OLD block matches actual CLAUDE.md content. Version jumps from 2.0.0 to 2.2.0 in registry (matching 2.2.0 in frontmatter). |
| **MAJOR:** Sync skill model in CLAUDE.md shows `opus-4-6` but frontmatter is `claude-sonnet-4-5` | Feasibility (M2) | Fixed: Phase 4 NEW block now shows `sonnet-4-5` for sync. |
| **MAJOR:** `--fast` flag interaction with context discovery unspecified | Red Team (INFO-02), Feasibility (M3) | Added explicit documentation: "Context discovery runs regardless of the `--fast` flag." |
| **MAJOR:** Nested code fences in architect prompt may corrupt SKILL.md | Feasibility (M5) | Replaced triple-backtick fences with `---begin/end---` delimiters in plan. Added implementation notes. |
| **MINOR:** `claude_md_hash` requires SHA256 computation LLMs cannot natively perform | Red Team (MINOR-02), Feasibility (m3) | Replaced `claude_md_hash` with `claude_md_exists: [true or false]`. Simpler, no computation needed, no hallucination risk. |
| **MINOR:** Plan author self-correction visible ("Wait -- let me re-examine") | Red Team (MINOR-01) | Removed. Sync frontmatter details presented cleanly. |
| **MINOR:** Dream step count in registry was wrong (plan said 5, should be 6) | Librarian (NON-BLOCKING) | Fixed: dream step count is now 6 in registry. |
| **MINOR:** Integration smoke test lacks expected output criteria | Red Team (MINOR-04) | Added expected output snippets for each verification point. |
| **INFO:** Deploy path uses `~/workspaces/` but actual path is `/Users/imurphy/projects/` | Red Team (INFO-03) | Fixed: Phase 5 uses actual project path. |
| **INFO:** No deploy rollback instructions | Red Team (INFO-01) | Added: "After reverting any phase, re-run `./scripts/deploy.sh`." |

**Not addressed (accepted as documented limitations):**
- MAJOR-01 (glob exclusion pattern fragility): Accepted as known limitation. Future iteration can switch to positive filtering.
- MAJOR-02 (plan similarity matching undefined): Accepted as LLM best-effort. Non-blocking by design.
- MAJOR-03 (pattern validation has no structured extraction): Accepted as LLM best-effort. Non-blocking warnings-only design contains blast radius.

---

## Next Steps

1. **Execute Phase 1** -- An engineer should apply all 15 model alias replacements across 5 skill files. This can be done with a series of Edit tool calls. Commit with message: `fix(skills): replace short model aliases with full IDs for Vertex AI compatibility`

2. **Execute Phase 2** -- Same or different engineer applies context discovery changes to `skills/dream/SKILL.md`, including renumbering all steps from 1-4 to 2-5 and inserting new Step 1. Commit with message: `feat(dream): add context discovery step for architectural awareness`

3. **Execute Phase 3** -- Apply pattern validation changes to `skills/ship/SKILL.md`, including renumbering all steps from 2-5 to 3-6 and inserting new Step 2. Commit with message: `feat(ship): add pattern validation step with warnings-only gate`

4. **Execute Phase 4** -- Update `CLAUDE.md` skill registry (versions, descriptions, step counts, sync model). Commit with message: `docs: update skill registry with new versions and correct sync model`

5. **Deploy and test** -- Run `./scripts/deploy.sh` and perform manual smoke tests.

---

## Plan Metadata

- **Plan File:** `./plans/task-model-fix-context-preservation.md`
- **Affected Components:** `skills/dream/SKILL.md`, `skills/ship/SKILL.md`, `skills/audit/SKILL.md`, `skills/sync/SKILL.md`, `skills/test-idempotent/SKILL.md`, `CLAUDE.md`
- **Validation:**
  ```bash
  # Full validation suite
  grep -rn 'model=opus\b\|model=sonnet\b' skills/*/SKILL.md && echo "FAIL: short aliases remain" || echo "PASS: no short aliases"
  grep -c 'Step 0\.5\|Step 1b' skills/dream/SKILL.md skills/ship/SKILL.md && echo "FAIL: non-integer step numbers" || echo "PASS: all integer steps"
  python3 generators/validate_skill.py skills/dream/SKILL.md
  python3 generators/validate_skill.py skills/ship/SKILL.md
  python3 generators/validate_skill.py skills/audit/SKILL.md
  python3 generators/validate_skill.py skills/sync/SKILL.md
  python3 generators/validate_skill.py skills/test-idempotent/SKILL.md
  bash generators/test_skill_generator.sh
  ```

## Status: APPROVED


## Status: APPROVED
