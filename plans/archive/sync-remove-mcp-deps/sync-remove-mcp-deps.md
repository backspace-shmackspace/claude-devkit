# Plan: Remove MCP Agent-Factory Dependency from /sync Skill

## Goals

1. **Eliminate the single MCP agent-factory tool call** from the `/sync` skill (Step 3 — librarian review).
2. **Replace with a Task subagent** using `subagent_type=general-purpose` and an explicit CLAUDE.md alignment prompt.
3. **Remove permission prompt friction** — MCP tools are not in the global allowlist; `Task` subagents are.
4. **Bump version to 3.0.0** — breaking change (MCP dependency contract removed from `/sync`).
5. **Update CLAUDE.md Skill Registry** to reflect the new version.

## Non-Goals

- Modifying the MCP `agent-factory` server itself or any agent definitions in `helper-mcps`.
- Changing the `/sync` workflow structure (step ordering, scope logic, verdict behavior, archive step).
- Modifying other skills (`/dream`, `/ship`, `/audit`). `/audit` still references `agent_hardener` — that is a separate follow-up.
- Adding new review dimensions or changing the review output format.
- Adding local agent fallback patterns (the librarian role is a simple read-and-compare task that does not benefit from a project-specific agent file).
- Modifying `templates/skill-coordinator.md.template` (addressed in a separate plan after all skill MCP removals are complete).

## Assumptions

1. `Task` subagent with `subagent_type=general-purpose` is universally available in Claude Code — no MCP dependency.
2. The `Task`, `Read`, `Glob`, `Edit`, `Write`, `Bash`, and `Grep` tools are all in the global allowlist and will not prompt for permission.
3. The librarian prompt in Step 3 is already self-contained — it reads `CLAUDE.md` and `README.md`, compares against recent changes, and writes a structured review. No specialized agent knowledge is required beyond what the prompt provides.
4. The dream skill's v2.3.0 to v3.0.0 migration (same pattern) has been completed successfully and is the established precedent.

## Proposed Design

### Current Architecture (v2.0.1)

```
Step 1: Bash (detect changes — coordinator does this)
Step 2: Grep + Read (detect env vars — coordinator does this)
Step 3: mcp__agent-factory__agent_librarian_v1 (MCP — librarian review)
Step 4: Task subagent (apply updates — already uses Task)
Step 5: Bash (verification — coordinator does this)
Step 6: Bash (archive — coordinator does this)
```

### Proposed Architecture (v3.0.0)

```
Step 1: Bash (detect changes — unchanged)
Step 2: Grep + Read (detect env vars — unchanged)
Step 3: Task subagent with CLAUDE.md alignment prompt (no MCP)
Step 4: Task subagent (apply updates — unchanged)
Step 5: Bash (verification — unchanged)
Step 6: Bash (archive — unchanged)
```

### Detailed Replacement Strategy

#### Step 3 — Librarian Review

**Change:** Replace `mcp__agent-factory__agent_librarian_v1` with `Task` subagent.

**Before (line 60):**
```
Tool: `mcp__agent-factory__agent_librarian_v1`
```

**After:**
```
Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`
```

The prompt block (lines 62-103) is **unchanged**. It is already self-contained — it tells the agent exactly what to read, what to compare, and what output structure to produce. The librarian role is "read CLAUDE.md and README.md, compare to recent code changes, check alignment" — this requires no specialized agent capabilities beyond what a general-purpose Task subagent provides.

The model remains `claude-sonnet-4-5` (matching the skill's declared model in frontmatter), consistent with the existing Step 4 Task subagent which also uses `claude-sonnet-4-5`.

#### All Other Steps

**No changes.** Steps 1, 2, 4, 5, and 6 do not reference MCP tools. Step 4 already uses a `Task` subagent correctly.

### Frontmatter Change

```yaml
# Before
version: 2.0.1

# After
version: 3.0.0
```

### CLAUDE.md Changes

Update the sync row in the Skill Registry table:

**Before:**
```
| **sync** | 2.0.1 | Detect changes (recent/full) → Detect undocumented env vars → Librarian review with CURRENT/UPDATES_NEEDED verdict → Apply updates → User verification with git diff → Archive review. | claude-sonnet-4-5 | 6 |
```

**After:**
```
| **sync** | 3.0.0 | Detect changes (recent/full) → Detect undocumented env vars → Librarian review with CURRENT/UPDATES_NEEDED verdict → Apply updates → User verification with git diff → Archive review. | claude-sonnet-4-5 | 6 |
```

Only the version number changes. The description remains accurate — "Librarian review" is a role description, not a tool reference.

## Interfaces / Schema Changes

**No external interface changes.** The review artifact format (`sync-[timestamp].review.md`), verdict values (`CURRENT` / `UPDATES_NEEDED`), and file naming conventions remain identical.

**Internal change:** Tool declaration in Step 3 changes from `mcp__agent-factory__agent_librarian_v1` to `Task`.

## Data Migration

None required. Existing review artifacts are compatible. No database, configuration file, or state file changes.

## Rollout Plan

### Phase 1: Edit Source

1. Edit `/Users/imurphy/projects/claude-devkit/skills/sync/SKILL.md`:
   - Update frontmatter version from `2.0.1` to `3.0.0`.
   - Replace `mcp__agent-factory__agent_librarian_v1` tool declaration with `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`.
2. Edit `/Users/imurphy/projects/claude-devkit/CLAUDE.md`:
   - Update sync version in Skill Registry table from `2.0.1` to `3.0.0`.
3. Validate: `python3 generators/validate_skill.py skills/sync/SKILL.md`
4. Commit both files in a single commit.

### Phase 2: Deploy

1. Run `cd /Users/imurphy/projects/claude-devkit && ./scripts/deploy.sh sync`
2. Verify deployed file: `diff skills/sync/SKILL.md ~/.claude/skills/sync/SKILL.md`

### Phase 3: Verify (blocking gate before push)

1. Run `/sync recent` in a project with recent commits — verify no MCP permission prompts.
2. Verify the review artifact is created at `./plans/sync-[timestamp].review.md`.
3. Verify the review artifact contains a Verdict (`CURRENT` or `UPDATES_NEEDED`).

### Rollback

Revert the commit containing both SKILL.md and CLAUDE.md changes, then redeploy:
```bash
git revert <commit-hash> && ./scripts/deploy.sh sync
```

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **Quality regression in librarian review** — Task subagent may miss CLAUDE.md nuances that a specialized librarian caught | Low | Low | The librarian prompt is already self-contained (reads CLAUDE.md, compares to changes, produces structured output). No specialized knowledge is required. The dream skill's identical replacement (Step 3b) established that Task subagents produce equivalent results. |
| **Validation failure** — Skill validator may flag missing MCP tool reference | Low | Low | The validator checks for tool declarations, not specific tool names. `Task` is a valid tool declaration. Run validator before committing. |
| **Cross-skill inconsistency** — `/audit` still uses MCP `agent_hardener` | Known | Low | Explicitly out of scope. Non-Goals section documents this. `/audit` will be addressed in a separate follow-up plan. |

## Test Plan

### Test Command

```bash
cd /Users/imurphy/projects/claude-devkit && python3 generators/validate_skill.py skills/sync/SKILL.md
```

Expected: Exit code 0 (PASS).

### Manual Verification Checklist

1. **No MCP references remain in SKILL.md:**
   ```bash
   grep -c "mcp__" skills/sync/SKILL.md
   ```
   Expected: `0`

2. **No agent-factory references remain in SKILL.md:**
   ```bash
   grep -c "agent-factory\|agent_factory" skills/sync/SKILL.md
   ```
   Expected: `0`

3. **Version is 3.0.0 in SKILL.md:**
   ```bash
   head -6 skills/sync/SKILL.md | grep "version:"
   ```
   Expected: `version: 3.0.0`

4. **Step 3 has Task tool declaration:**
   ```bash
   grep -A1 "## Step 3" skills/sync/SKILL.md | grep "Tool:"
   ```
   Expected: Contains `Task` (not `mcp__`).

5. **CLAUDE.md Skill Registry shows sync version 3.0.0:**
   ```bash
   grep 'sync.*3.0.0' CLAUDE.md
   ```
   Expected: One match in the Skill Registry table.

6. **Prompt block is unchanged (spot check):**
   ```bash
   grep "reviewing documentation for currency and accuracy" skills/sync/SKILL.md
   ```
   Expected: One match (prompt content preserved).

### Integration Test (Manual — blocking gate)

Run `/sync recent` in the `claude-devkit` project. Verify:
- No MCP permission prompts appear.
- Review artifact is created with correct structure (Verdict + Required Updates + Suggested Updates + Rationale).
- If verdict is `UPDATES_NEEDED`, Step 4 Task subagent applies changes correctly.
- The workflow completes end-to-end without errors.

Phase 3 must complete successfully before the commit is pushed to any shared branch.

## Acceptance Criteria

1. `skills/sync/SKILL.md` contains zero references to `mcp__agent-factory` or any MCP tool.
2. `skills/sync/SKILL.md` frontmatter version is `3.0.0`.
3. `python3 generators/validate_skill.py skills/sync/SKILL.md` passes (exit code 0).
4. Step 3 uses `Task` with `subagent_type=general-purpose` and `model=claude-sonnet-4-5`.
5. The librarian review prompt content is unchanged.
6. Steps 1, 2, 4, 5, and 6 are unchanged.
7. The workflow structure (step ordering, scope logic, verdict behavior, archive step) is unchanged.
8. CLAUDE.md Skill Registry table shows sync version `3.0.0`.
9. No local agent file is introduced (the librarian role does not warrant one).

## Task Breakdown

### Files to Modify

| File | Change |
|------|--------|
| `/Users/imurphy/projects/claude-devkit/skills/sync/SKILL.md` | Update frontmatter version to `3.0.0`. Replace `mcp__agent-factory__agent_librarian_v1` tool declaration with `Task, subagent_type=general-purpose, model=claude-sonnet-4-5`. |
| `/Users/imurphy/projects/claude-devkit/CLAUDE.md` | Update sync version in Skill Registry table from `2.0.1` to `3.0.0`. |

### Detailed Edit List for `SKILL.md`

1. **Frontmatter (line 4):** Change `version: 2.0.1` to `version: 3.0.0`.
2. **Step 3 tool declaration (line 60):** Change `Tool: \`mcp__agent-factory__agent_librarian_v1\`` to `Tool: \`Task\`, \`subagent_type=general-purpose\`, \`model=claude-sonnet-4-5\``.

Two edits total. Prompt block (lines 62-103) is untouched.

### Detailed Edit List for `CLAUDE.md`

1. **Skill Registry table (line 87):** Change sync version from `2.0.1` to `3.0.0`.

One edit total.

## Context Alignment

### CLAUDE.md Patterns Followed

| Pattern | How This Plan Follows It |
|---------|------------------------|
| **Edit source, not deployment** | All edits target `skills/sync/SKILL.md` and `CLAUDE.md`, not `~/.claude/skills/sync/SKILL.md` |
| **Validate before committing** | Test plan includes `validate_skill.py` as first check |
| **Coordinator pattern** | Preserves the coordinator archetype: coordinator detects changes, delegates review to a subagent, conditionally delegates updates, presents results for user approval |
| **v2.0.0 architectural patterns** | All patterns maintained (numbered steps, tool declarations, verdict gates, etc.) |
| **Tool permissions in global allowlist** | This change eliminates the MCP tool (not in allowlist) in favor of `Task` (in allowlist), directly addressing the permission prompt issue |
| **Update registry** | CLAUDE.md Skill Registry table is updated as part of this plan |

### Prior Plans Related

- **`dream-remove-mcp-deps.md`** — Established the pattern for replacing MCP agent-factory tools with Task subagents. The `/sync` change follows the identical pattern used for Step 3b (librarian) in the dream plan. That plan's successful execution validates this approach.

### Deviations from Established Patterns

| Deviation | Justification |
|-----------|--------------|
| **Version jump from 2.0.1 to 3.0.0** | Follows semver: removing the MCP dependency contract is a breaking change for any tooling that expected `agent_librarian_v1` to be invoked by `/sync`. This is the same versioning rationale used for the dream skill's v2.3.0 to v3.0.0 jump. |

## Status: DRAFT

<!-- Context Metadata
discovered_at: 2026-02-26T12:00:00Z
claude_md_exists: true
recent_plans_consulted: dream-remove-mcp-deps.md
archived_plans_consulted: none
-->

## Status: APPROVED
