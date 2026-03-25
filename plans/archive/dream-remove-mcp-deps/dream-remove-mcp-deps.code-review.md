---
reviewer: code-reviewer
plan: dream-remove-mcp-deps.md
files_reviewed:
  - skills/dream/SKILL.md
  - CLAUDE.md
reviewed_at: 2026-02-26
---

# Code Review: dream-remove-mcp-deps

## Verdict: PASS

All plan requirements are satisfied. No Critical or Major findings remain.

---

## Critical Findings (Must Fix)

None.

---

## Major Findings (Should Fix)

None.

---

## Minor Findings (Optional)

### M1 — CLAUDE.md Pipeline Pattern example still contains "MCP agent or Task"

**File:** `CLAUDE.md`, line 434
**Finding:** The Pipeline Pattern example structure (`#### Pipeline Pattern (like /ship)`) contains:
```
Tool: MCP agent or Task
```
This is the `/ship` pipeline archetype example — which the plan explicitly placed out of scope (Non-Goals: "Modifying other skills (`/ship`, `/audit`, `/sync`)"). The Scan Pattern example at line 471 similarly retains `Tool: Multiple MCP agents in parallel` for the `/audit` archetype.

These are pre-existing, known inconsistencies documented in the plan's Risks section ("Cross-skill inconsistency") and Non-Goals section. They are not regressions introduced by this change set, and the plan explicitly defers them to follow-up plans for `/audit`, `/sync`, and the coordinator template.

**Impact:** None for `/dream`. Informational only — future reviewers should not flag these as omissions from this change set.

**Recommendation:** Add a `<!-- TODO: update after audit/sync MCP removal plans -->` comment next to the two out-of-scope Pipeline and Scan pattern Tool lines, so future reviewers know they are pending work, not oversights.

### M2 — Integration Points section references MCP for base agent invocation

**File:** `CLAUDE.md`, line 719
**Finding:**
```
- Skills can invoke base agents via MCP
```
This sentence in the "With Workspaces Architecture" section references MCP as the integration mechanism. This is a pre-existing reference, unrelated to the `/dream` changes, and is explicitly out of scope for this plan. However, it is a stale description given the direction to move away from MCP dependencies.

**Recommendation:** Track in a follow-up cleanup plan. No action required for this review.

---

## Positives

### P1 — All 8 SKILL.md edits applied correctly

Verified against the plan's "Detailed Edit List for SKILL.md":

| # | Edit | Status |
|---|------|--------|
| 1 | Frontmatter: `version: 2.3.0` → `version: 3.0.0` | PASS — confirmed `version: 3.0.0` in frontmatter |
| 2 | Step 0: Added Pattern 3 (`.claude/agents/security-analyst.md`); updated not-found messages to use `gen-agent` (removed `~/workspaces/` path) | PASS — all three glob patterns present; `gen-agent . --type` in all three not-found messages |
| 3 | Step 2 intro: Removed "fall back to `agent_senior_architect_v2` (MCP)"; replaced with Task subagent fallback | PASS — "If none found, use a Task subagent with general-purpose prompt." present; no MCP reference |
| 4 | Step 3a: Changed from `mcp__agent-factory__agent_redteam_v2` to `Task, subagent_type=general-purpose, model=claude-opus-4-6` with explicit red-team prompt and optional security-analyst clause | PASS — correct Tool declaration; full red-team prompt with Verdict/Findings structure; optional security-analyst clause present |
| 5 | Step 3b: Changed from `mcp__agent-factory__agent_librarian_v1` to `Task, subagent_type=general-purpose, model=claude-opus-4-6` | PASS — confirmed Tool declaration changed; prompt unchanged |
| 6 | Step 3c: Removed MCP fallback `mcp__agent-factory__agent_code_reviewer_v1`; replaced with Task subagent | PASS — Tool declaration now: `.claude/agents/code-reviewer.md` (if found), fallback to `Task, subagent_type=general-purpose, model=claude-opus-4-6` |
| 7 | Step 4: Updated to match Step 2 pattern (no MCP); explicit "no MCP" language added | PASS — "local `.claude/agents/senior-architect.md` preferred, Task subagent fallback — no MCP" present |
| 8 | Step 5 commit messages: `v2.3.0` → `v3.0.0` in both APPROVED and FAIL templates | PASS — both commit message templates reference `v3.0.0` |

### P2 — Both CLAUDE.md edits applied correctly

Verified against the plan's "Detailed Edit List for CLAUDE.md":

| # | Edit | Status |
|---|------|--------|
| 1 | Skill Registry table: dream version `2.3.0` → `3.0.0` | PASS — confirmed `3.0.0` in Skill Registry row for dream |
| 2 | Coordinator Pattern example: `Tool: MCP agent` → `Tool: Task (via .claude/agents/ if found, otherwise subagent_type=general-purpose)`; `Tool: Multiple MCP agents in parallel (red team + librarian + feasibility)` → `Tool: Task (multiple subagents in parallel: red team + librarian + feasibility)` | PASS — both lines updated correctly at lines 394 and 397 |

### P3 — Zero MCP references remain in SKILL.md

`grep -c "mcp__"` returns `0`. `grep -c "agent-factory"` returns `0`. The only remaining MCP-adjacent text in SKILL.md is the parenthetical `(no MCP)` in Step 4, which is intentional explanatory language, not a tool reference.

### P4 — All acceptance criteria satisfied

All 14 acceptance criteria from the plan verified:

1. Zero `mcp__agent-factory` or MCP tool references in SKILL.md — PASS
2. SKILL.md frontmatter version is `3.0.0` — PASS
3. Step 0 globs for all three local agents — PASS
4. Step 2 uses local `senior-architect.md` with Task subagent fallback — PASS
5. Step 3a uses Task subagent as primary, optional security-analyst for security-specific plans — PASS
6. Step 3b uses Task subagent directly — PASS
7. Step 3c uses local `code-reviewer.md` with Task subagent fallback — PASS
8. Step 4 revision loop matches Step 2 pattern — PASS
9. Step 5 commit messages reference `v3.0.0` — PASS
10. All Step 0 not-found messages suggest `gen-agent` — PASS
11. Workflow structure unchanged (step ordering, revision bounds, verdict logic) — PASS
12. CLAUDE.md Skill Registry shows dream `3.0.0` — PASS
13. CLAUDE.md coordinator pattern example uses `Task` instead of `MCP agent` — PASS

(Note: Criterion 3 from the plan — `validate-skill` passing — is a runtime check not verifiable by static review. It remains a blocking gate per Phase 3 before push.)

### P5 — Red-team prompt output format matches plan specification exactly

The Step 3a prompt structure matches the plan specification verbatim, including:
- `## Verdict: PASS or FAIL` heading with explicit FAIL condition
- `## Findings` with severity rating instruction (Critical / Major / Minor / Info)
- File output instruction to `./plans/[feature-name].redteam.md`
- `Verdict as the first heading after the metadata` requirement

### P6 — Model string hygiene preserved

The IMPORTANT note in Step 2 (`do NOT use shorthand like 'opus'`) is preserved and correctly applies to both Step 2 and Step 4. All Tool declarations explicitly use `model=claude-opus-4-6`.

### P7 — Pre-existing bug fixed as a side effect

The plan noted that the old Step 0 messages referenced `~/workspaces/claude-devkit/generators/generate_agents.py`, which was an incorrect path (should be `~/projects/claude-devkit`). The replacement with `gen-agent . --type <type>` eliminates the incorrect path entirely, fixing a pre-existing bug.

---

## Summary

The implementation is clean, complete, and precisely scoped. All 8 SKILL.md edits and both CLAUDE.md edits were applied correctly. No MCP references remain in SKILL.md. The version is 3.0.0 in both files. The two Minor findings (M1 and M2) are pre-existing out-of-scope items explicitly called out in the plan's Non-Goals and Risks sections — they do not represent regressions or omissions from this change set.

The only remaining gate before push is the runtime `validate-skill` check (Test Plan step 1) and the manual integration test (Phase 3).

<!-- Context Metadata
reviewed_at: 2026-02-26T00:00:00Z
plan: dream-remove-mcp-deps.md
verdict: PASS
critical_count: 0
major_count: 0
minor_count: 2
-->
