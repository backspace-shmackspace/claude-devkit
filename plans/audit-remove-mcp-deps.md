# Plan: Remove MCP Agent-Factory Dependency from /audit Skill

## Goals

1. **Eliminate the single MCP agent-factory tool call** from the `/audit` skill (Step 2: `mcp__agent-factory__agent_hardener`).
2. **Replace with local `security-analyst.md` agent** (`.claude/agents/security-analyst.md`) as primary path, with `Task` subagent fallback for projects without the agent.
3. **Remove permission prompt friction** — MCP tools are not in the global allowlist; `Task` and local agents are.
4. **Bump version to 3.0.0** — breaking change (MCP dependency contract removed from `/audit`).
5. **Update CLAUDE.md skill registry** to reflect the new version and description.

## Non-Goals

- Modifying the MCP `agent-factory` server itself or agent definitions in `helper-mcps`.
- Changing the `/audit` workflow structure (step ordering, scope resolution, verdict logic, synthesis format).
- Adding new scan dimensions or changing the report output format.
- Modifying other skills (`/dream`, `/ship`, `/sync`). `/sync` still references MCP `agent_librarian_v1` — that is a separate plan.
- Changing the local agent file `.claude/agents/security-analyst.md` — it is consumed as-is.
- Modifying `templates/skill-scan.md.template`.

## Assumptions

1. The local agent at `.claude/agents/security-analyst.md` is present in the claude-devkit project and covers STRIDE, OWASP Top 10, DREAD frameworks, and compliance checklists — all directly relevant to the audit security scan role.
2. `Task` subagent with `subagent_type=general-purpose` is universally available in Claude Code — no MCP dependency.
3. The `Task` tool, `Read`, `Glob`, `Edit`, `Write`, and `Bash` are all in the global allowlist and will not prompt for permission.
4. Projects that do NOT have a local `security-analyst.md` will get a `Task` subagent fallback with an explicit security scan prompt that is functionally equivalent to the current hardener behavior.
5. The `security-analyst.md` agent IS suitable for this role (unlike the `/dream` red-team case) because audit Step 2 is a security scan — STRIDE/threat modeling, OWASP Top 10, and vulnerability analysis are exactly what this agent does.
6. The output file naming convention (`audit-[timestamp].hardener.md`) will be renamed to `audit-[timestamp].security.md` to reflect the tool change. The synthesis step references will be updated accordingly.

## Proposed Design

### Current Architecture (v2.0.1)

```
Step 1: Bash (scope detection) — coordinator direct
Step 2: mcp__agent-factory__agent_hardener (MCP, no fallback)
Step 3: Task subagent (performance scan)
Step 4: Task subagent (QA regression, conditional)
Step 5: Read + synthesis — coordinator direct
Step 6: Gate — coordinator direct
```

### Proposed Architecture (v3.0.0)

```
Step 1: Bash (scope detection) — coordinator direct (unchanged)
Step 2: .claude/agents/security-analyst.md → Task subagent fallback (no MCP)
Step 3: Task subagent (performance scan) — unchanged
Step 4: Task subagent (QA regression, conditional) — unchanged
Step 5: Read + synthesis — coordinator direct (updated artifact name)
Step 6: Gate — coordinator direct (unchanged)
```

### Detailed Replacement Strategy

#### Step 1 — Determine scope

**Change:** None. This step is coordinator-direct and has no MCP references.

#### Step 2 — Security scan

**Change:** Replace `mcp__agent-factory__agent_hardener` with a two-tier strategy: local agent primary, Task subagent fallback.

**New tool declaration:**

```
Tool: Task, subagent_type=general-purpose, model=claude-opus-4-6
```

**New pre-check (added before the scan):**

```
Pre-check: Glob for `.claude/agents/security-analyst*.md`

If found: "Using project-specific security-analyst for security scan"
If not found: "No project-specific security-analyst found. Using generic Task subagent for security scan. For project-tailored scanning, generate one: gen-agent . --type security-analyst"
```

**Execution logic:**

- **If `.claude/agents/security-analyst.md` found:** Invoke via `Task` with `subagent_type=general-purpose` and `model=claude-opus-4-6`. The prompt instructs the subagent to read the security-analyst agent file for role context, then perform the scan. The three scope-specific prompts (plan/code/full) remain unchanged in content.
- **If not found:** Use `Task` with `subagent_type=general-purpose` and `model=claude-opus-4-6` with the same scope-specific prompts. The prompts are already self-contained and do not require specialist agent context to function.

**Output artifact rename:** `audit-[timestamp].hardener.md` becomes `audit-[timestamp].security.md` to reflect the tool change. This is a cosmetic change — the content format (findings rated Critical/High/Medium/Low) is unchanged.

#### Steps 3-4 — Performance scan & QA regression

**Change:** None. These steps already use `Task` subagent with no MCP dependencies.

#### Step 5 — Synthesis

**Change:** Update artifact references from `audit-[timestamp].hardener.md` to `audit-[timestamp].security.md` in:
- The list of reports to read
- The Reports section of the summary template

#### Step 6 — Gate

**Change:** None. The gate logic reads from the summary file, which is unaffected.

### Frontmatter Change

```yaml
# Before
version: 2.0.1

# After
version: 3.0.0
```

### CLAUDE.md Changes

#### Skill Registry Version Update

Update the audit row in the Skill Registry table:

```markdown
# Before
| **audit** | 2.0.1 | Scope detection (plan/code/full) → Security scan (hardener) + Performance scan → QA regression → Synthesis with PASS/PASS_WITH_NOTES/BLOCKED verdict → Structured reporting with timestamped artifacts. | opus-4-6 | 6 |

# After
| **audit** | 3.0.0 | Scope detection (plan/code/full) → Security scan (security-analyst agent or Task subagent) + Performance scan → QA regression → Synthesis with PASS/PASS_WITH_NOTES/BLOCKED verdict → Structured reporting with timestamped artifacts. | opus-4-6 | 6 |
```

## Interfaces / Schema Changes

**No external interface changes.** The audit report format, verdict logic (PASS/PASS_WITH_NOTES/BLOCKED), severity ratings (Critical/High/Medium/Low), and scope options (plan/code/full) remain identical.

**Internal changes:**
- Tool declaration in Step 2 changes from `mcp__agent-factory__agent_hardener` to `Task`.
- Step 2 gains a pre-check glob for `security-analyst.md`.
- Output artifact name changes from `*.hardener.md` to `*.security.md`.
- Step 5 references updated to match new artifact name.

## Data Migration

None required. Existing audit artifacts are not modified. New audits will produce `*.security.md` instead of `*.hardener.md`. The summary template's Reports section will reference the new name.

## Rollout Plan

### Phase 1: Edit Source

1. Edit `/Users/imurphy/projects/claude-devkit/skills/audit/SKILL.md` with all changes described above.
2. Edit `/Users/imurphy/projects/claude-devkit/CLAUDE.md` with version and description update in the Skill Registry.
3. Validate: `python3 generators/validate_skill.py skills/audit/SKILL.md`
4. Commit both files in a single commit.

### Phase 2: Deploy

1. Run `cd /Users/imurphy/projects/claude-devkit && ./scripts/deploy.sh audit`
2. Verify deployed file: `diff skills/audit/SKILL.md ~/.claude/skills/audit/SKILL.md`

### Phase 3: Verify (blocking gate before push)

1. Run `/audit code` in the `claude-devkit` project (which has `security-analyst.md`) — verify no MCP permission prompts.
2. Verify `audit-[timestamp].security.md` is created (not `*.hardener.md`).
3. Verify the summary report references `*.security.md`.

### Rollback

Revert the commit containing both SKILL.md and CLAUDE.md changes, then redeploy:
```bash
git revert <commit-hash> && ./scripts/deploy.sh audit
```

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **Quality regression in security scan** — Task subagent may produce less thorough findings than the specialized `agent_hardener` | Low | Medium | The `security-analyst.md` agent covers STRIDE, OWASP Top 10, DREAD, and compliance frameworks — equal or broader coverage than the hardener. The fallback Task subagent prompt is already self-contained with explicit vulnerability categories. |
| **Artifact name change breaks external tooling** — scripts or workflows that reference `*.hardener.md` will not find the new `*.security.md` files | Low | Low | The artifact names are internal to the audit skill and are consumed only by Step 5 (synthesis) within the same run. No external tooling references these intermediate artifacts. |
| **Missing security-analyst agent in other projects** — projects without `.claude/agents/` get generic Task subagent | Medium | Low | Task subagent fallback prompt is self-contained and explicitly lists all vulnerability categories. The pre-check messaging suggests `gen-agent` for project-tailored scanning. |

## Test Plan

### Test Command

```bash
cd /Users/imurphy/projects/claude-devkit && python3 generators/validate_skill.py skills/audit/SKILL.md
```

Expected: Exit code 0 (PASS).

### Manual Verification Checklist

1. **No MCP references remain in SKILL.md:**
   ```bash
   grep -c "mcp__" skills/audit/SKILL.md
   ```
   Expected: `0`

2. **No agent-factory references remain in SKILL.md:**
   ```bash
   grep -c "agent-factory\|agent_factory\|agent_hardener" skills/audit/SKILL.md
   ```
   Expected: `0`

3. **Version is 3.0.0 in SKILL.md:**
   ```bash
   head -6 skills/audit/SKILL.md | grep "version:"
   ```
   Expected: `version: 3.0.0`

4. **Step 2 uses Task tool declaration:**
   ```bash
   grep -A1 "## Step 2" skills/audit/SKILL.md | grep "Tool:"
   ```
   Expected: Contains `Task` (not `mcp__`).

5. **Security-analyst agent referenced:**
   ```bash
   grep "security-analyst" skills/audit/SKILL.md
   ```
   Expected: At least one match.

6. **Artifact name updated:**
   ```bash
   grep "\.security\.md" skills/audit/SKILL.md
   ```
   Expected: Multiple matches (Step 2 output, Step 5 read, Step 5 summary).

7. **No hardener artifact references remain:**
   ```bash
   grep "\.hardener\.md" skills/audit/SKILL.md
   ```
   Expected: `0` matches.

8. **CLAUDE.md Skill Registry shows audit version 3.0.0:**
   ```bash
   grep 'audit.*3.0.0' CLAUDE.md
   ```
   Expected: One match in the Skill Registry table.

### Integration Test (Manual — blocking gate)

Run `/audit code` in the `claude-devkit` project (which has `.claude/agents/security-analyst.md`). Verify:
- No MCP permission prompts appear.
- `audit-[timestamp].security.md` is created.
- Summary report references `*.security.md` (not `*.hardener.md`).
- Verdict is produced correctly (PASS, PASS_WITH_NOTES, or BLOCKED).

Phase 3 must complete successfully before the commit is pushed to any shared branch.

## Acceptance Criteria

1. `skills/audit/SKILL.md` contains zero references to `mcp__agent-factory`, `agent_hardener`, or any MCP tool.
2. `skills/audit/SKILL.md` frontmatter version is `3.0.0`.
3. `python3 generators/validate_skill.py skills/audit/SKILL.md` passes (exit code 0).
4. Step 2 includes a pre-check glob for `.claude/agents/security-analyst*.md` with found/not-found messaging.
5. Step 2 uses `security-analyst.md` as primary path with `Task` subagent fallback (no MCP).
6. Step 2 output artifact is `audit-[timestamp].security.md`.
7. Step 5 synthesis reads `audit-[timestamp].security.md` (not `*.hardener.md`).
8. Steps 3, 4, and 6 are unchanged.
9. The workflow structure (step ordering, scope resolution, verdict logic, severity ratings) is unchanged.
10. CLAUDE.md Skill Registry table shows audit version `3.0.0` with updated description.

## Task Breakdown

### Files to Modify

| File | Change |
|------|--------|
| `/Users/imurphy/projects/claude-devkit/skills/audit/SKILL.md` | All changes described in Proposed Design |
| `/Users/imurphy/projects/claude-devkit/CLAUDE.md` | Update audit version and description in Skill Registry table |

### Files to Verify (Read-Only)

| File | Purpose |
|------|---------|
| `/Users/imurphy/projects/claude-devkit/.claude/agents/security-analyst.md` | Confirm agent exists and covers STRIDE/OWASP/DREAD (confirmed) |

### Detailed Edit List for `SKILL.md`

1. **Frontmatter:** Change `version: 2.0.1` to `version: 3.0.0`.
2. **Step 2 tool declaration:** Change `Tool: mcp__agent-factory__agent_hardener` to `Tool: Task, subagent_type=general-purpose, model=claude-opus-4-6`.
3. **Step 2 pre-check:** Add glob for `.claude/agents/security-analyst*.md` before the scan, with found/not-found messaging and `gen-agent` suggestion.
4. **Step 2 execution logic:** Add branching: if agent found, instruct subagent to read it for role context; if not found, use self-contained prompt.
5. **Step 2 output artifact:** Rename `audit-[timestamp].hardener.md` to `audit-[timestamp].security.md` (3 occurrences in Step 2).
6. **Step 5 read list:** Change `audit-[timestamp].hardener.md` to `audit-[timestamp].security.md`.
7. **Step 5 summary template Reports section:** Change `Security: ./plans/audit-[timestamp].hardener.md` to `Security: ./plans/audit-[timestamp].security.md`.

### Detailed Edit List for `CLAUDE.md`

1. **Skill Registry table:** Change audit version from `2.0.1` to `3.0.0`. Update description to replace `(hardener)` with `(security-analyst agent or Task subagent)`.

## Context Alignment

### CLAUDE.md Patterns Followed

| Pattern | How This Plan Follows It |
|---------|------------------------|
| **Edit source, not deployment** | All edits target `skills/audit/SKILL.md` and `CLAUDE.md`, not `~/.claude/skills/audit/SKILL.md` |
| **Validate before committing** | Test plan includes `validate_skill.py` as first check |
| **Scan pattern archetype** | Preserves the scan archetype: scope detection, parallel specialist scans, synthesis, verdict gate |
| **Tool permissions in global allowlist** | Eliminates MCP tool (not in allowlist) in favor of `Task` (in allowlist), removing permission prompt friction |
| **Integration: skills can invoke local project agents from `.claude/agents/`** | Shifts from MCP-first to local-agent-first with Task subagent fallback |
| **Update registry** | CLAUDE.md Skill Registry table updated as part of this plan |

### Prior Plans Related

- **`dream-remove-mcp-deps.md`** — Established the pattern for MCP removal (v2.3.0 to v3.0.0). This plan follows the same strategy: local agent primary, Task subagent fallback, version bump, registry update. The dream plan's Non-Goals section explicitly noted `/audit` as a follow-up.

### Deviations from Established Patterns

| Deviation | Justification |
|-----------|--------------|
| **Artifact rename from `*.hardener.md` to `*.security.md`** | The `hardener` name was tied to the MCP agent identity. With the MCP dependency removed, the artifact name should reflect the function (security scan) rather than the removed tool. This is a cosmetic change — all references are internal to the skill and updated in this plan. |
| **Version jump from 2.0.1 to 3.0.0** | Follows semver and the precedent set by `/dream` (2.3.0 to 3.0.0): removing the MCP dependency contract is a breaking change for any tooling that expected `agent_hardener` to be invoked by `/audit`. |

## Status: DRAFT

<!-- Context Metadata
discovered_at: 2026-02-26T12:00:00Z
claude_md_exists: true
recent_plans_consulted: dream-remove-mcp-deps.md
archived_plans_consulted: none
-->

## Status: APPROVED
