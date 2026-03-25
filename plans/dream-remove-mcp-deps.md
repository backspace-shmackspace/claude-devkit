# Plan: Remove MCP Agent-Factory Dependencies from /dream Skill

## Goals

1. **Eliminate all MCP agent-factory tool calls** from the `/dream` skill (Steps 0, 2, 3a, 3b, 3c, and 4).
2. **Replace with local project agents** (`.claude/agents/*.md`) and `Task` subagents as fallback.
3. **Remove permission prompt friction** — MCP tools are not in the global allowlist; `Task` and local agents are.
4. **Correct role misuse** — `redteam_v2` is PRODSECRM-specific but was being used as a generic plan critic.
5. **Bump version to 3.0.0** — breaking change (MCP dependency contract removed from `/dream`).

## Non-Goals

- Modifying the MCP `agent-factory` server itself or any agent definitions in `helper-mcps`.
- Changing the `/dream` workflow structure (step ordering, revision loop bounds, verdict logic).
- Adding new review dimensions or changing the plan output format.
- Modifying other skills (`/ship`, `/audit`, `/sync`). **Note:** `/audit` and `/sync` still reference MCP agent-factory tools (`agent_hardener`, `agent_librarian_v1`). Those are separate changes to be addressed in follow-up plans. The version bump to 3.0.0 applies only to `/dream`, not the entire devkit.
- Changing the local agent files (`.claude/agents/*.md`) — they are consumed as-is.
- Modifying `templates/skill-coordinator.md.template`. **Note:** The coordinator template still references MCP agent-factory tools as examples. This will be addressed in a separate plan after the `/dream`, `/audit`, and `/sync` MCP removals are complete.

## Assumptions

1. The local agents at `.claude/agents/senior-architect.md`, `.claude/agents/code-reviewer.md`, and `.claude/agents/security-analyst.md` are present in the claude-devkit project and remain valid for other projects using `gen-agent`.
2. `Task` subagent with `subagent_type=general-purpose` is universally available in Claude Code — no MCP dependency.
3. The `Task` tool, `Read`, `Glob`, `Edit`, `Write`, and `Bash` are all in the global allowlist and will not prompt for permission.
4. Projects that do NOT have local agents will get `Task` subagent fallbacks that are functionally equivalent (not identical) to the MCP agents they replace.
5. The `security-analyst.md` agent outputs STRIDE tables and compliance checklists, which do not match the expected red-team output format (PASS/FAIL verdict with Critical/Major/Minor severity ratings). The Task subagent fallback prompt, which explicitly requests the correct output format, is therefore the primary path for Step 3a. The `security-analyst.md` agent is used only when the project has security-specific plans where STRIDE analysis is relevant.

## Proposed Design

### Current Architecture (v2.3.0)

```
Step 0: Glob for senior-architect.md, code-reviewer.md
Step 2: Task subagent (architect) — MCP fallback if no local agent
Step 3a: mcp__agent-factory__agent_redteam_v2 (MCP, no fallback)
Step 3b: mcp__agent-factory__agent_librarian_v1 (MCP, no fallback)
Step 3c: .claude/agents/code-reviewer.md → MCP fallback
Step 4: Task subagent (revision) — same as Step 2
```

### Proposed Architecture (v3.0.0)

```
Step 0: Glob for senior-architect.md, code-reviewer.md, security-analyst.md
Step 2: .claude/agents/senior-architect.md → Task subagent fallback (no MCP)
Step 3a: Task subagent with red-team prompt (PRIMARY) → .claude/agents/security-analyst.md (OPTIONAL, security plans only)
Step 3b: Task subagent with CLAUDE.md alignment prompt (no agent needed)
Step 3c: .claude/agents/code-reviewer.md → Task subagent fallback (no MCP)
Step 4: Same architect as Step 2 (no MCP)
```

### Detailed Replacement Strategy

#### Step 0 — Pre-flight

**Change:** Add a third parallel glob for `.claude/agents/security-analyst.md`. Update messaging to remove MCP references.

| Check | Found Message | Not-Found Message |
|-------|--------------|-------------------|
| `senior-architect.md` | "Using project-specific senior-architect" | "No project-specific senior-architect found. Will use generic Task subagent for planning. For project-tailored planning, generate one: `gen-agent . --type senior-architect`" |
| `code-reviewer.md` | "Using project-specific code-reviewer" | "No project-specific code-reviewer found. Will use generic Task subagent for feasibility checks. For project-tailored reviews, generate one: `gen-agent . --type code-reviewer`" |
| `security-analyst.md` | "Found project-specific security-analyst (available for security-focused plans)" | "No project-specific security-analyst found. Will use generic Task subagent for red team review. For project-tailored analysis, generate one: `gen-agent . --type security-analyst`" |

#### Step 2 — Architect Drafts Plan

**Change:** The current skill already uses `Task` subagent. The text says "If none found, fall back to `agent_senior_architect_v2` (MCP)." Remove the MCP fallback reference. The step should read:

- **If `.claude/agents/senior-architect.md` found (Step 0):** Invoke it as a project-level agent via `Task` with `subagent_type=general-purpose`.
- **If not found:** Use `Task` with `subagent_type=general-purpose` and `model=claude-opus-4-6`. The prompt is unchanged — the Task subagent is already general-purpose.

The prompt and output format are unchanged. The fallback execution path changes from MCP agent to Task subagent.

#### Step 3a — Red Team (Plan Critic)

**Change:** Replace `mcp__agent-factory__agent_redteam_v2` with Task subagent as the PRIMARY path, with optional security-analyst agent for security-specific plans only.

- **Primary path (always used):** Use `Task` with `subagent_type=general-purpose` and `model=claude-opus-4-6` with a focused red-team prompt:

```
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
```

- **Optional (security-specific plans only):** If `.claude/agents/security-analyst.md` was found in Step 0 AND the plan subject is security-related (e.g., authentication, authorization, cryptography, network), additionally invoke the security-analyst agent via `Task` and append its STRIDE analysis to the redteam artifact as a supplemental section. The Verdict from the primary Task subagent governs the pass/fail decision.

No MCP fallback.

#### Step 3b — Librarian (Rules Gate)

**Change:** Replace `mcp__agent-factory__agent_librarian_v1` with a `Task` subagent. No specialized agent needed — the librarian role is simply "read CLAUDE.md + plan, check alignment."

- **Always use:** `Task` with `subagent_type=general-purpose` and `model=claude-opus-4-6`.
- Prompt unchanged from current (the current prompt is already self-contained and does not depend on librarian-specific capabilities).

No MCP fallback. No local agent needed.

#### Step 3c — Feasibility Review

**Change:** Remove the MCP fallback clause `fallback to mcp__agent-factory__agent_code_reviewer_v1`.

- **If `.claude/agents/code-reviewer.md` found:** Use it (unchanged).
- **If not found:** Use `Task` with `subagent_type=general-purpose` and `model=claude-opus-4-6` with a feasibility review prompt (same content as current prompt).

No MCP fallback.

#### Step 4 — Revision Loop

**Change:** Update the re-invocation to match Step 2's new pattern (local agent preferred, Task subagent fallback, no MCP). No other changes.

#### Step 5 — Final Verdict Gate

**Change:** Update commit message version reference from `v2.3.0` to `v3.0.0`.

### Frontmatter Change

```yaml
# Before
version: 2.3.0

# After
version: 3.0.0
```

### CLAUDE.md Changes

#### Skill Registry Version Update

Update the dream row in the Skill Registry table from `2.3.0` to `3.0.0`.

#### Coordinator Pattern Example Update

Update the Coordinator Pattern example structure (lines ~393-397 of CLAUDE.md) to reflect the local-agent-first + Task-fallback pattern:

```markdown
# Before:
## Step 1 — Main work (delegate to agent)
Tool: MCP agent

## Step 2 — Parallel quality reviews (3 agents)
Tool: Multiple MCP agents in parallel (red team + librarian + feasibility)

# After:
## Step 1 — Main work (delegate to agent)
Tool: Task (via .claude/agents/ if found, otherwise subagent_type=general-purpose)

## Step 2 — Parallel quality reviews (3 agents)
Tool: Task (multiple subagents in parallel: red team + librarian + feasibility)
```

## Interfaces / Schema Changes

**No external interface changes.** The plan output format, review artifact format, and file naming conventions remain identical.

**Internal changes:**
- Tool declarations in Steps 3a and 3b change from `mcp__agent-factory__*` to `Task`.
- Tool declaration in Step 3c removes MCP fallback clause.
- Step 0 adds one additional glob pattern.
- Step 3a output format is now explicitly specified in the prompt (Verdict heading + severity-rated findings).

## Data Migration

None required. Existing plan artifacts are compatible. No database, configuration file, or state file changes.

## Rollout Plan

### Phase 1: Edit Source

1. Edit `/Users/imurphy/projects/claude-devkit/skills/dream/SKILL.md` with all changes described above.
2. Edit `/Users/imurphy/projects/claude-devkit/CLAUDE.md` with version update and coordinator example update.
3. Validate: `validate-skill /Users/imurphy/projects/claude-devkit/skills/dream/SKILL.md`
4. Commit both files in a single commit.

### Phase 2: Deploy

1. Run `cd /Users/imurphy/projects/claude-devkit && ./scripts/deploy.sh dream`
2. Verify deployed file: `diff skills/dream/SKILL.md ~/.claude/skills/dream/SKILL.md`

### Phase 3: Verify (blocking gate before push)

1. Run `/dream` in a project with local agents — verify no MCP permission prompts.
2. Run `/dream` in a project without local agents — verify Task subagent fallbacks work.
3. Verify all three review artifacts are created (`.redteam.md`, `.review.md`, `.feasibility.md`).

### Rollback

Revert the commit containing both SKILL.md and CLAUDE.md changes, then redeploy:
```bash
git revert <commit-hash> && ./scripts/deploy.sh dream
```

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **Quality regression in red team review** — Task subagent may produce less thorough critique than specialized `redteam_v2` | Medium | Medium | The Task subagent prompt now explicitly specifies the output format (Verdict + severity-rated findings), which aligns with Step 4's revision trigger logic. The prompt is focused on plan critique, not security-specific analysis. |
| **Quality regression in librarian review** — Task subagent may miss CLAUDE.md nuances that a specialized librarian caught | Low | Low | The librarian prompt is already self-contained (reads CLAUDE.md, checks alignment). No specialized knowledge required beyond what the prompt provides. |
| **Missing local agents in other projects** — Projects without `.claude/agents/` will get generic Task subagents everywhere | Medium | Low | Task subagent fallbacks are functionally adequate. The Step 0 messaging now suggests `gen-agent` for all three agent types. |
| **Validation failure** — Skill validator may flag missing MCP tool references | Low | Low | The validator checks for tool declarations, not specific tool names. `Task` is a valid tool declaration. Run validator before committing. |
| **Cross-skill inconsistency** — `/audit` and `/sync` still use MCP agent-factory; coordinator template still shows MCP examples | Known | Low | Explicitly out of scope. Non-Goals section documents this. Follow-up plans will address `/audit`, `/sync`, and the coordinator template separately. The version bump messaging specifies "/dream" scope only. |

## Test Plan

### Test Command

```bash
cd /Users/imurphy/projects/claude-devkit && python3 generators/validate_skill.py skills/dream/SKILL.md
```

Expected: Exit code 0 (PASS).

### Manual Verification Checklist

1. **No MCP references remain in SKILL.md:**
   ```bash
   grep -c "mcp__" skills/dream/SKILL.md
   ```
   Expected: `0`

2. **No agent-factory references remain in SKILL.md:**
   ```bash
   grep -c "agent-factory\|agent_factory" skills/dream/SKILL.md
   ```
   Expected: `0`

3. **Version is 3.0.0 in SKILL.md:**
   ```bash
   head -6 skills/dream/SKILL.md | grep "version:"
   ```
   Expected: `version: 3.0.0`

4. **All three review steps still have Tool declarations:**
   ```bash
   grep -A1 "### 3a\|### 3b\|### 3c" skills/dream/SKILL.md | grep "Tool:"
   ```
   Expected: Three lines, each containing `Task` (not `mcp__`).

5. **Step 0 globs for security-analyst.md:**
   ```bash
   grep "security-analyst.md" skills/dream/SKILL.md
   ```
   Expected: At least one match.

6. **Commit message version updated:**
   ```bash
   grep "v3.0.0" skills/dream/SKILL.md
   ```
   Expected: At least one match (in the commit message template).

7. **CLAUDE.md Skill Registry shows dream version 3.0.0:**
   ```bash
   grep 'dream.*3.0.0' CLAUDE.md
   ```
   Expected: One match in the Skill Registry table.

8. **CLAUDE.md coordinator example uses Task, not MCP agent:**
   ```bash
   grep -A2 "Main work (delegate to agent)" CLAUDE.md | grep "Tool:"
   ```
   Expected: Contains `Task`, not `MCP agent`.

### Integration Test (Manual — blocking gate)

Run `/dream add a hello-world endpoint` in the `claude-devkit` project itself (which has all three local agents). Verify:
- No MCP permission prompts appear.
- All three review artifacts are created.
- The redteam artifact contains a Verdict heading and severity-rated findings.
- Plan is approved or fails on merit (not due to tool errors).

Phase 3 must complete successfully before the commit is pushed to any shared branch.

## Acceptance Criteria

1. `skills/dream/SKILL.md` contains zero references to `mcp__agent-factory` or any MCP tool.
2. `skills/dream/SKILL.md` frontmatter version is `3.0.0`.
3. `validate-skill skills/dream/SKILL.md` passes (exit code 0).
4. Step 0 checks for three local agents: `senior-architect.md`, `code-reviewer.md`, `security-analyst.md`.
5. Step 2 uses local `senior-architect.md` with Task subagent fallback (no MCP).
6. Step 3a uses Task subagent with explicit red-team prompt as the primary path, with optional `security-analyst.md` for security-specific plans only. Output format (Verdict + severity ratings) is specified in the prompt.
7. Step 3b uses Task subagent directly (no agent file, no MCP).
8. Step 3c uses local `code-reviewer.md` with Task subagent fallback (no MCP).
9. Step 4 revision loop matches Step 2 pattern (no MCP).
10. Step 5 commit messages reference `v3.0.0`.
11. All "not found" messages in Step 0 suggest `gen-agent` (not MCP generation).
12. The workflow structure (step ordering, revision bounds, verdict logic) is unchanged.
13. CLAUDE.md Skill Registry table shows dream version `3.0.0`.
14. CLAUDE.md coordinator pattern example uses `Task` instead of `MCP agent`.

## Task Breakdown

### Files to Modify

| File | Change |
|------|--------|
| `/Users/imurphy/projects/claude-devkit/skills/dream/SKILL.md` | All changes described in Proposed Design |
| `/Users/imurphy/projects/claude-devkit/CLAUDE.md` | Update dream version in Skill Registry table from `2.3.0` to `3.0.0`. Update coordinator pattern example to use `Task` instead of `MCP agent`. |

### Files to Verify (Read-Only)

| File | Purpose |
|------|---------|
| `/Users/imurphy/projects/claude-devkit/.claude/agents/senior-architect.md` | Confirm agent exists and is suitable for Step 2 |
| `/Users/imurphy/projects/claude-devkit/.claude/agents/security-analyst.md` | Confirm agent exists (used optionally for security-specific plans in Step 3a) |
| `/Users/imurphy/projects/claude-devkit/.claude/agents/code-reviewer.md` | Confirm agent exists and is suitable for Step 3c |

### Detailed Edit List for `SKILL.md`

1. **Frontmatter:** Change `version: 2.3.0` to `version: 3.0.0`.
2. **Step 0:** Add Pattern 3: `.claude/agents/security-analyst.md`. Update "not found" messages to remove MCP references and suggest `gen-agent`. Remove `~/workspaces/claude-devkit/generators/generate_agents.py` path and use `gen-agent` alias (also fixes pre-existing incorrect `~/workspaces/` path).
3. **Step 2 intro text:** Remove "fall back to `agent_senior_architect_v2` (MCP)" sentence. Replace with "If none found, use a Task subagent with general-purpose prompt."
4. **Step 3a tool declaration:** Change `Tool: mcp__agent-factory__agent_redteam_v2 (MCP)` to `Tool: Task, subagent_type=general-purpose, model=claude-opus-4-6`. Use the explicit red-team prompt with output format specification (Verdict heading + severity-rated findings) as the PRIMARY path. Optionally invoke `security-analyst.md` only for security-specific plans, appending STRIDE analysis as a supplemental section.
5. **Step 3b tool declaration:** Change `Tool: mcp__agent-factory__agent_librarian_v1 (MCP)` to `Tool: Task, subagent_type=general-purpose, model=claude-opus-4-6`. Prompt unchanged.
6. **Step 3c tool declaration:** Change `Tool: .claude/agents/code-reviewer.md (if found), fallback to mcp__agent-factory__agent_code_reviewer_v1 (MCP)` to `Tool: .claude/agents/code-reviewer.md (if found), fallback to Task subagent_type=general-purpose, model=claude-opus-4-6`. Remove MCP reference.
7. **Step 4:** Update to match Step 2 pattern (remove any MCP fallback language).
8. **Step 5 commit messages:** Change `v2.3.0` to `v3.0.0` in both APPROVED and FAIL commit message templates.

### Detailed Edit List for `CLAUDE.md`

1. **Skill Registry table:** Change dream version from `2.3.0` to `3.0.0`.
2. **Coordinator Pattern example:** Change `Tool: MCP agent` to `Tool: Task (via .claude/agents/ if found, otherwise subagent_type=general-purpose)`. Change `Tool: Multiple MCP agents in parallel (red team + librarian + feasibility)` to `Tool: Task (multiple subagents in parallel: red team + librarian + feasibility)`.

## Context Alignment

### CLAUDE.md Patterns Followed

| Pattern | How This Plan Follows It |
|---------|------------------------|
| **Edit source, not deployment** | All edits target `skills/dream/SKILL.md` and `CLAUDE.md`, not `~/.claude/skills/dream/SKILL.md` |
| **Validate before committing** | Test plan includes `validate-skill` as first check |
| **Coordinator pattern** | Preserves the coordinator archetype: delegates to specialists, parallel reviews, bounded revision loops, verdict gates |
| **v2.0.0 architectural patterns** | All 11 patterns maintained (numbered steps, tool declarations, verdict gates, bounded iterations, etc.) |
| **Tool permissions in global allowlist** | This change eliminates MCP tools (not in allowlist) in favor of `Task` (in allowlist), directly addressing the permission prompt issue |
| **Integration: skills can invoke local project agents from `.claude/agents/`** | Shifts from MCP-first to local-agent-first with Task subagent fallback |
| **Update registry** | CLAUDE.md Skill Registry table and coordinator pattern example are updated as part of this plan |

### Prior Plans Related

- **`dream-auto-commit.md`** — Established v2.3.0 (the version this plan upgrades from) and defined the auto-commit sub-step in Step 5. This plan preserves the auto-commit logic and only updates the version string in commit message templates.
- **`zerg-adoption-priorities.md`** — Discusses broader skill architecture evolution and MCP integration patterns. Contextually relevant but does not conflict with this plan.

### Deviations from Established Patterns

| Deviation | Justification |
|-----------|--------------|
| **Removing MCP integration from /dream coordinator** | The CLAUDE.md coordinator archetype example shows "MCP agent" in steps. This plan replaces MCP agents with local agents + Task subagents **and updates the coordinator example to match**. This is justified because: (1) MCP tools cause permission prompts, (2) the `redteam_v2` agent was being misused for a non-PRODSECRM workflow, (3) local agents provide equivalent or better project-specific context. The coordinator pattern itself (delegation, parallel reviews, revision loops, verdict gates) is preserved. Note: `/audit`, `/sync`, and the coordinator template still use MCP references; those are separate changes. |
| **Version jump from 2.3.0 to 3.0.0** | Follows semver: removing the MCP dependency contract is a breaking change for any tooling that expected MCP agent-factory to be invoked by `/dream`. This version bump applies to `/dream` only, not the entire devkit. |

## Status: APPROVED

<!-- Context Metadata
discovered_at: 2026-02-26T00:00:00Z
claude_md_exists: true
recent_plans_consulted: dream-auto-commit.md
archived_plans_consulted: none
-->
