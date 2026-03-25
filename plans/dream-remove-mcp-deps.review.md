# Re-Review: Remove MCP Agent-Factory Dependencies from /dream Skill

**Plan:** `plans/dream-remove-mcp-deps.md`
**Reviewed Against:** `CLAUDE.md` (v1.0.0, updated 2026-02-24)
**Date:** 2026-02-26
**Review Type:** Revision re-review

---

## Verdict: PASS

All three required edits from the previous review have been addressed. No new conflicts with CLAUDE.md were introduced. The plan is ready for implementation.

---

## Required Edits Status (from previous review)

### 1. Fix "Files to Verify (Read-Only)" table — RESOLVED

The CLAUDE.md row has been removed from the "Files to Verify (Read-Only)" table. The table now contains only the three agent files (senior-architect.md, security-analyst.md, code-reviewer.md), all of which are genuinely read-only checks. CLAUDE.md is correctly listed under "Files to Modify" with both the version update and the coordinator pattern example update.

### 2. Update context metadata — RESOLVED

`recent_plans_consulted` changed from `none` to `dream-auto-commit.md` (line 366 of plan).

### 3. Update "Prior Plans Related" section — RESOLVED

The section now references both `dream-auto-commit.md` (established v2.3.0, the baseline being modified) and `zerg-adoption-priorities.md` (broader architecture context). Both entries include brief justifications for relevance.

---

## Previously Optional Suggestions — Status

| Suggestion | Status | Notes |
|-----------|--------|-------|
| Update Coordinator Pattern example in CLAUDE.md | **Adopted** | Now included as an explicit change in "CLAUDE.md Changes" section (lines 146-162), the "Detailed Edit List for CLAUDE.md" (lines 331-333), and acceptance criterion #14. |
| Integration Patterns line 720 staleness | Not adopted | Remains optional. Can be caught by a `/sync` pass post-implementation. |
| Red-team minimum coverage note | Not adopted | Remains optional. The prompt now specifies the output format explicitly, which partially addresses the concern. |

---

## New Conflicts Check

No new conflicts with CLAUDE.md were introduced in this revision. Specific checks:

- **Rule 1 (Edit source, not deployment):** Plan targets `skills/dream/SKILL.md` and `CLAUDE.md`, not deployed copies. Correct.
- **Rule 2 (Validate before committing):** Rollout Phase 1 includes `validate-skill` before commit. Correct.
- **Rule 4 (Update registry):** Plan updates both the Skill Registry version and the Coordinator Pattern example. Correct.
- **Rule 5 ("all 10 patterns"):** Plan says "all 11 patterns" (line 344). This is the same pre-existing inconsistency noted in the previous review (CLAUDE.md says 10 in Rule 5 text but lists 11 in the table). Not a plan defect.
- **Tool permissions:** Plan replaces MCP tools (not in allowlist) with Task (in allowlist). Aligned with CLAUDE.md allowlist documentation.
- **Coordinator archetype:** Plan preserves the coordinator structure (delegation, parallel reviews, bounded loops, verdict gates) while updating the tooling. The archetype documentation update is now included. Correct.

---

## Remaining Notes (non-blocking)

- The pre-existing CLAUDE.md inconsistency (Rule 5 says "10 patterns" but 11 are listed) persists. A future `/sync` pass should correct Rule 5 to say "all 11 architectural patterns."
- The Integration Patterns section (line 720 of CLAUDE.md: "Skills can invoke base agents via MCP") will become partially stale after this plan lands. A `/sync` pass post-implementation would catch this.

---

<!-- Review Metadata
reviewer: claude-opus-4-6
review_type: revision_re-review
plan_version: DRAFT (revised)
claude_md_version: 1.0.0
required_edits_resolved: 3/3
new_conflicts: 0
verdict: PASS
-->
