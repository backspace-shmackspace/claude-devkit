# Plan Review: audit-remove-mcp-deps.md

**Reviewed:** 2026-02-26
**Plan file:** `plans/audit-remove-mcp-deps.md`
**Rules file:** `CLAUDE.md`
**Reviewer:** Claude Code (claude-sonnet-4-6)

---

## Verdict: PASS

The plan is internally consistent, correctly scoped, and well-aligned with CLAUDE.md rules. All development rules are followed, all pattern compliance claims are accurate, and the precedent from `dream-remove-mcp-deps.md` is correctly applied. One stale artifact reference in CLAUDE.md is flagged as a required edit; the remaining items are suggestions.

---

## Conflicts

None. No conflicts between the plan's stated approach and CLAUDE.md rules were found.

---

## Required Edits

### 1. CLAUDE.md Artifact Locations — stale `*.hardener.md` reference (must update)

The plan correctly identifies that `audit-[timestamp].hardener.md` becomes `audit-[timestamp].security.md` in the SKILL.md artifact name, but the CLAUDE.md Artifact Locations section (lines 544-557) still documents `audit-[timestamp].hardener.md`:

```
# Current CLAUDE.md (lines 545-546):
├── audit-[timestamp].summary.md           # Audit summaries
├── audit-[timestamp].hardener.md          # Security scan results
```

The plan's Task Breakdown (Detailed Edit List for `CLAUDE.md`) only lists two edits:
1. Skill Registry table version bump
2. Skill Registry description update

It does not include an edit to the Artifact Locations section. This is an omission. If the artifact name changes in SKILL.md and in the Skill Registry description but not in the Artifact Locations tree, the CLAUDE.md will be internally inconsistent.

**Required addition to the plan's Detailed Edit List for `CLAUDE.md`:**

```markdown
3. **Artifact Locations section:** Change `audit-[timestamp].hardener.md` to
   `audit-[timestamp].security.md` in the `./plans/` directory tree.
```

**Required addition to Acceptance Criteria:**

```markdown
11. CLAUDE.md Artifact Locations section references `audit-[timestamp].security.md`
    (not `audit-[timestamp].hardener.md`).
```

**Required addition to Test Plan (Manual Verification Checklist):**

```bash
# Check 9 — CLAUDE.md artifact tree updated:
grep "hardener.md" CLAUDE.md
# Expected: 0 matches (should only appear in Workflow 2 example if that is also updated)
```

**Note:** CLAUDE.md also contains a Workflow 2 example (lines 270-275) that lists `audit-[timestamp].hardener.md` as a named artifact. That section is documentation of current behavior and would also need to be updated. The plan should either include it explicitly or call it out as a known omission.

---

## Context Alignment Check

### CLAUDE.md Patterns (from Context Alignment section of the plan)

| Pattern Claimed | Verification | Status |
|----------------|--------------|--------|
| Edit source, not deployment | Plan targets `skills/audit/SKILL.md` and `CLAUDE.md`, not `~/.claude/skills/audit/SKILL.md`. Rollout Phase 1 uses source paths. | CONFIRMED |
| Validate before committing | Test Plan Step 1 is `validate_skill.py`. Validate precedes commit in Phase 1. | CONFIRMED |
| Scan pattern archetype preserved | Step ordering (1-6) unchanged. Scope detection, parallel scans, synthesis, gate all preserved. | CONFIRMED |
| Tool permissions in allowlist | MCP tool `mcp__agent-factory__agent_hardener` is not in the CLAUDE.md allowlist. `Task` is listed as "Low — spawns sub-agents". The plan correctly characterizes this as eliminating prompt friction. | CONFIRMED |
| Local-agent-first integration | Step 2 pre-check globs `.claude/agents/security-analyst*.md` before falling back to Task subagent. Matches the pattern established by `/dream` v3.0.0. | CONFIRMED |
| Update registry | Skill Registry table update is in the plan's Task Breakdown and Acceptance Criteria. | CONFIRMED (with gap noted in Required Edits above) |

### Historical Alignment (vs. dream-remove-mcp-deps.md precedent)

The plan correctly claims to follow the `/dream` removal pattern. Verification:

| Dimension | /dream plan | /audit plan | Aligned |
|-----------|------------|------------|---------|
| Local agent primary, Task fallback | Yes | Yes | Yes |
| Version bump to 3.0.0 | 2.3.0 → 3.0.0 | 2.0.1 → 3.0.0 | Yes (same target, different base) |
| Registry update required | Yes | Yes | Yes |
| Non-Goals list scope-adjacent skills | Lists `/audit`, `/sync` as separate follow-ups | Lists `/sync` as separate follow-up | Yes |
| Phase structure (Edit, Deploy, Verify) | 3 phases | 3 phases | Yes |
| Rollback via git revert + redeploy | Yes | Yes | Yes |
| Pre-check glob with gen-agent suggestion | Yes (Step 0) | Yes (Step 2 pre-check) | Yes |
| Acceptance Criteria count | 13 | 10 | Acceptable — scope is narrower |

The plan correctly cites the dream plan as precedent in the Prior Plans Related section and the Deviations table.

**One historical deviation warranting mention:** In the dream plan, the security-analyst agent was explicitly deemed unsuitable as the PRIMARY path for red-team review (Assumption 5), because its output format (STRIDE tables) does not match the red-team artifact format. The audit plan correctly inverts this: the security-analyst IS suitable as the primary path for Step 2 because the audit security scan role (STRIDE, OWASP Top 10, vulnerability findings rated Critical/High/Medium/Low) is exactly what the agent produces. This is a deliberate and correct differentiation — the audit plan makes this argument explicitly in Assumption 5 and the Deviations table. The logic is sound and consistent with the agent's stated capabilities in `.claude/agents/security-analyst.md`.

### Assumption Verification

| Assumption | Verified Against Source | Status |
|-----------|------------------------|--------|
| 1. security-analyst.md exists and covers STRIDE/OWASP/DREAD | File confirmed at `.claude/agents/security-analyst.md`. Covers STRIDE, DREAD, OWASP Top 10, compliance checklists. | CONFIRMED |
| 2. Task subagent universally available | Listed in CLAUDE.md allowlist as globally authorized. | CONFIRMED |
| 3. Task, Read, Glob, Edit, Write, Bash in global allowlist | All five tools appear in CLAUDE.md allowlist table (lines 752-762). | CONFIRMED |
| 4. Projects without security-analyst.md get Task fallback | Plan design documents this path explicitly. | CONFIRMED |
| 5. security-analyst.md suitable for audit Step 2 | Agent output format (STRIDE analysis, risk table, OWASP checklist, severity ratings) maps well to audit Step 2 requirements (Critical/High/Medium/Low ratings, OWASP Top 10). The agent does NOT produce a `Verdict: PASS/FAIL` header — but that is not required in the audit context; the verdict is produced by Step 5 synthesis, not Step 2. | CONFIRMED |
| 6. Artifact rename from *.hardener.md to *.security.md | Internal rename, all internal references updated in plan's edit list. Gap: CLAUDE.md Artifact Locations not listed (see Required Edits). | PARTIAL — gap noted |

---

## Pattern Compliance

### v2.0.0 Skill Architectural Patterns (all 11)

| Pattern | Current SKILL.md State | Plan Preserves? |
|---------|----------------------|----------------|
| 1. Coordinator | Role section present, delegation language present | Yes — unchanged |
| 2. Numbered steps | Steps 1-6 with `## Step N` headers | Yes — unchanged |
| 3. Tool declarations | Every step has `Tool:` line | Yes — Step 2 declaration changes from MCP to Task |
| 4. Verdict gates | PASS/PASS_WITH_NOTES/BLOCKED in Step 5-6 | Yes — unchanged |
| 5. Timestamped artifacts | `[timestamp]` present in all artifact names | Yes — `audit-[timestamp].security.md` preserves convention |
| 6. Structured reporting | Outputs to `./plans/` | Yes — unchanged |
| 7. Bounded iterations | No revision loop in audit skill (scan archetype); N/A | N/A |
| 8. Model selection | `model: claude-opus-4-6` in frontmatter | Yes — unchanged |
| 9. Scope parameters | `## Inputs` with `$ARGUMENTS` (plan/code/full) | Yes — unchanged |
| 10. Archive on success | References `./plans/archive/` in Step 6 (implied) | Yes — unchanged |
| 11. Worktree isolation | Not applicable to scan archetype | N/A |

The plan does not introduce any pattern regressions.

### Scan Archetype Compliance

The CLAUDE.md scan archetype template (lines 466-483) documents:
- Step 0: Detect scope — Tool: Glob, Read
- Step 1: Parallel scans — Tool: Multiple MCP agents in parallel
- Step 2: Synthesis
- Step 3: Verdict gate

The existing SKILL.md already deviates from the template's archetype example (the template still shows MCP agents, which is a known stale reference from before the `/dream` removal). The plan's changes move the skill further from the stale template and closer to the intended local-agent-first pattern. The template itself is listed as a future cleanup item in `dream-remove-mcp-deps.md` Non-Goals. No action required in this plan.

---

## Suggestions

### S1. Step 3 (Performance scan) model inconsistency

The current SKILL.md Step 3 uses `model=claude-sonnet-4-5`:

```
Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`
```

The plan does not change Steps 3-4, and correctly calls this out in Non-Goals. However, CLAUDE.md lists `claude-sonnet-4-5` nowhere — the standard model referenced throughout is `claude-opus-4-6` (skill frontmatter) and `claude-sonnet-4-5` for the `/sync` skill. `claude-sonnet-4-5` is valid but is one version behind the current model naming convention (`claude-sonnet-4-6` is implied by the current model stack). This is a pre-existing issue and explicitly out of scope for this plan. Consider a follow-up plan to normalize the model version in Step 3.

### S2. Step 4 (QA scan) uses gen-agent path with ~/workspaces prefix

The current SKILL.md Step 4 "not found" message references:

```
python3 ~/workspaces/claude-devkit/generators/generate_agents.py
```

This uses the `~/workspaces/` path rather than the `~/projects/` path documented in CLAUDE.md (line 1023: `Repository: ~/projects/claude-devkit`). The `dream-remove-mcp-deps.md` plan noted fixing this same path error in Step 0's gen-agent suggestion. Since the audit plan explicitly does not change Steps 3-4, this pre-existing path bug persists. Consider including it in the Step 2 pre-check update — or flagging it for a dedicated clean-up commit. Specifically: the Step 4 not-found message could be updated to use the `gen-agent` alias (as the dream plan did) instead of the raw `python3` path.

### S3. Integration test scope could be broader

The Rollout Phase 3 integration test only covers the `security-analyst.md` found path (`/audit code` in `claude-devkit`). Consider adding a second integration test step for the not-found fallback path:

```
3b. Run `/audit code` in a project WITHOUT `.claude/agents/security-analyst.md`
    — verify Task subagent fallback runs without permission prompts.
    — verify `audit-[timestamp].security.md` is still created.
```

This would complete bilateral coverage of the two-tier strategy.

### S4. Context Metadata — discovered_at timestamp

The plan's Context Metadata block reads:

```
discovered_at: 2026-02-26T12:00:00Z
```

The timestamp uses noon UTC as a placeholder. If the actual discovery time is known, it should be filled in. If not known, the placeholder is acceptable. The dream plan used `2026-02-26T00:00:00Z` as its timestamp, suggesting these are approximate values rather than precise records. No action required, but note the convention.

---

## Summary

| Category | Count | Items |
|----------|-------|-------|
| Conflicts | 0 | — |
| Required edits | 1 | CLAUDE.md Artifact Locations section + Workflow 2 artifact list not included in plan's edit scope |
| Suggestions | 4 | S1: sonnet-4-5 model version, S2: ~/workspaces path bug in Step 4, S3: bilateral integration test, S4: metadata timestamp |

The plan is approved to execute after incorporating the required edit to include the CLAUDE.md Artifact Locations section in the scope of changes.
