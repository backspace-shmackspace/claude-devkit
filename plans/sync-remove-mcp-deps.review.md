# Librarian Review: sync-remove-mcp-deps.md

**Reviewed:** 2026-02-26
**Reviewer:** Librarian (Task subagent — general-purpose)
**Plan file:** `plans/sync-remove-mcp-deps.md`
**Reference:** `CLAUDE.md` (Last Updated: 2026-02-24)

---

## Verdict

PASS

---

## Conflicts

None identified. The plan contains no requirements that contradict CLAUDE.md rules, architectural patterns, or established project conventions.

---

## Required Edits

None. The plan is internally consistent and aligned with project rules as written.

---

## Context Alignment Analysis

### Context Alignment Section (plan lines 241–271)

The plan's own Context Alignment table is accurate and complete. Each row is verified below:

| Pattern Claimed | Verification |
|----------------|--------------|
| Edit source, not deployment | Correct. Both edits target `skills/sync/SKILL.md` and `CLAUDE.md`. No deployment path (`~/.claude/skills/`) is edited directly. Consistent with CLAUDE.md Development Rule 1. |
| Validate before committing | Correct. Rollout Phase 1 step 3 runs `python3 generators/validate_skill.py skills/sync/SKILL.md` before commit. Consistent with CLAUDE.md Development Rule 2. |
| Coordinator pattern | Correct. The `/sync` skill is a coordinator archetype (coordinator detects, subagent reviews, conditional subagent updates, user approval gate). Step ordering is preserved. The replacement in Step 3 swaps the tool type but retains the delegation semantics. |
| v2.0.0 architectural patterns | Correct. The plan preserves all 10 (11) patterns from CLAUDE.md's Skill Architectural Patterns section: numbered steps, Tool declarations, verdict gates, timestamped artifacts, structured reporting, bounded iterations, model selection, scope parameters, archive on success. |
| Tool permissions in global allowlist | Correct and directly addresses the stated problem. CLAUDE.md's allowlist table confirms `Task` is in the allowlist ("Low — spawns sub-agents"). MCP tools are not listed and therefore require permission prompts. The substitution is the correct remediation. |
| Update registry | Correct. CLAUDE.md Skill Registry sync row is updated from `2.0.1` to `3.0.0` as part of this plan. |

### Historical Alignment

**dream-remove-mcp-deps.md** is the stated precedent. That plan replaced multiple MCP agent-factory invocations in `/dream` (Steps 0, 2, 3a, 3b, 3c) with Task subagents and local project agents, bumping the version from 2.3.0 to 3.0.0. The `/sync` plan is a strict subset of that pattern: one MCP tool in one step replaced with one Task subagent, same version-bump rationale. The precedent is valid and directly applicable.

**Skill Registry state:** CLAUDE.md currently shows `dream: 3.0.0` (already migrated) and `sync: 2.0.1` (pre-migration). The plan's proposed state (`sync: 3.0.0`) matches the post-migration expectation.

**audit-remove-mcp-deps.md** is acknowledged in Non-Goals and the Risks table as a known, out-of-scope sibling plan. This is consistent with the Non-Goals section in `dream-remove-mcp-deps.md`, which also deferred `/audit` and `/sync` to separate plans.

### Pattern Compliance

All v2.0.0 patterns verified against the source `skills/sync/SKILL.md` and the proposed edits:

1. **Coordinator** — Role section present: "You are the documentation coordinator." Delegation language preserved. PASS.
2. **Numbered steps** — Steps 1–6 with `## Step N — [Action]` format. Plan edits Step 3 tool declaration only; step headers unchanged. PASS.
3. **Tool declarations** — Each step has a `Tool:` line. Step 3 changes from `mcp__agent-factory__agent_librarian_v1` to `Task, subagent_type=general-purpose, model=claude-sonnet-4-5`. Replacement is a valid tool declaration. PASS.
4. **Verdict gates** — Step 4 verdict gate (`CURRENT` / `UPDATES_NEEDED`) is unchanged. PASS.
5. **Timestamped artifacts** — `sync-[timestamp].review.md` pattern unchanged. PASS.
6. **Structured reporting** — Review output structure (Verdict, Required Updates, Suggested Updates, Rationale) preserved in the Step 3 prompt. PASS.
7. **Bounded iterations** — No revision loop in `/sync`; not applicable. PASS.
8. **Model selection** — `model: claude-sonnet-4-5` in frontmatter unchanged. Task subagent specifies same model. PASS.
9. **Scope parameters** — `## Inputs` with `$ARGUMENTS` (`recent` / `full`) unchanged. PASS.
10. **Archive on success** — Step 6 archive step unchanged. PASS.
11. **Worktree isolation** — Not applicable to `/sync` (no parallel implementation work). PASS.

---

## Suggestions

### 1. Clarify `model=claude-sonnet-4-5` vs. current model ID conventions

CLAUDE.md frontmatter examples use `claude-opus-4-6` as the canonical model ID format. The plan specifies `model=claude-sonnet-4-5` for the Task subagent. This matches the existing SKILL.md frontmatter and the existing Step 4 Task subagent, so it is internally consistent. However, the current Claude Code model is `claude-sonnet-4-6` (as of early 2026). Consider whether `claude-sonnet-4-5` is intentionally pinned for reproducibility or should be updated to `claude-sonnet-4-6` in a follow-up. This is not a blocker for this plan.

### 2. Test Plan check 6 — spot-check string may be fragile

The manual verification command:
```bash
grep "reviewing documentation for currency and accuracy" skills/sync/SKILL.md
```
This string appears in line 62 of the current SKILL.md. Since the plan explicitly states the prompt block (lines 62–103) is untouched, this check is valid. However, it is worth noting that if the prompt is ever reformatted, this check will produce a false negative. Consider a more structural check (e.g., grep for a line-count range) in a future test plan revision. Low priority.

### 3. Acceptance Criterion 3 — validator invocation form

Criterion 3 uses `python3 generators/validate_skill.py`. CLAUDE.md Quick Start and alias documentation uses `validate-skill` (the installed alias). Both are equivalent if the install is in place, but the plan targets the `claude-devkit` project root where the alias should be available. Aligning to the alias would be consistent with CLAUDE.md conventions. Minor.

### 4. No integration test for CURRENT verdict path

The integration test in Phase 3 verifies the happy path but only checks for the existence of a Verdict. If the sync skill runs against a recently-synced repo and returns `CURRENT`, the workflow terminates at Step 4 without reaching Step 6 (archive). The test plan should explicitly state this is a valid terminal state and the review artifact will remain in `./plans/` (not archived). This is a documentation gap in the test plan, not a plan defect.

---

## Rationale

The plan is a minimal, targeted, single-concern change: one tool declaration in one step, one version bump in one frontmatter, one row update in one registry table. Every claim in the Context Alignment section is verifiable against CLAUDE.md and the source SKILL.md. The precedent from `dream-remove-mcp-deps.md` is directly applicable and correctly cited. The Non-Goals section is appropriately bounded and consistent with the broader MCP migration series. No conflicts with project rules were found.
