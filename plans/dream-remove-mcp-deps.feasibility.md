# Feasibility Re-Review: Remove MCP Agent-Factory Dependencies from /dream Skill

**Plan:** `./plans/dream-remove-mcp-deps.md`
**Reviewer:** code-reviewer (feasibility mode)
**Date:** 2026-02-26
**Review type:** REVISION re-review (second pass)

## Verdict: PASS

The revised plan addresses all three Major concerns from the initial review. No new critical or major issues have been introduced. The plan is ready for implementation.

---

## Previous Major Concerns: Resolution Status

### Major #1 — CLAUDE.md listed as "Read-Only" but requires edits
**Status: RESOLVED**

The revised plan eliminates the contradiction entirely. CLAUDE.md now appears in the "Files to Modify" table (not "Read-Only") with two explicit changes: (1) Skill Registry version bump, and (2) Coordinator Pattern example update. Both changes have corresponding acceptance criteria (items 13 and 14) and test commands (items 7 and 8 in the Manual Verification Checklist). The `grep 'dream.*3.0.0' CLAUDE.md` test and the coordinator example test are both present and correct.

### Major #2 — Security-analyst agent output format mismatch
**Status: RESOLVED**

The revised plan inverts the priority: the Task subagent with an explicit red-team prompt is now the PRIMARY path for Step 3a, not a fallback. The `security-analyst.md` agent is demoted to an optional supplemental role, used only for security-specific plans where STRIDE analysis is relevant. This is a better design than either of the two options suggested in the initial review. The red-team prompt now includes explicit output format instructions:

```
## Verdict: PASS or FAIL
(FAIL if any Critical finding exists)

## Findings
(Each finding with severity rating: Critical / Major / Minor / Info)
```

This directly addresses the format mismatch. The Verdict from the primary Task subagent governs the pass/fail decision, so Step 4's revision trigger logic will parse correctly regardless of whether the security-analyst produces STRIDE tables. Assumption #5 in the plan explicitly acknowledges the format difference, which provides good documentation for future maintainers.

### Major #3 — Coordinator template still references MCP agents
**Status: RESOLVED**

The revised plan adds two explicit notes:
1. Non-Goals bullet: "Modifying `templates/skill-coordinator.md.template`. Note: The coordinator template still references MCP agent-factory tools as examples. This will be addressed in a separate plan after the `/dream`, `/audit`, and `/sync` MCP removals are complete."
2. Risks table: "Cross-skill inconsistency" row with "Known" probability and "Low" impact, documenting that `/audit`, `/sync`, and the coordinator template still use MCP references, with explicit follow-up plan commitment.

Additionally, the plan now includes updating the CLAUDE.md coordinator pattern example itself (the "Example Structure" under the Coordinator Pattern section), changing `Tool: MCP agent` to `Tool: Task (via .claude/agents/ if found, otherwise subagent_type=general-purpose)`. This means the canonical documentation matches the new architecture even while the template file itself remains out of scope.

---

## Previous Minor Concerns: Resolution Status

### Minor #4 — Task subagent fallback prompt for Step 3a underspecified
**Status: RESOLVED.** The red-team prompt now includes full output structure specification (Verdict heading, severity-rated findings, file output path). See Major #2 resolution above.

### Minor #5 — No automated integration test / integration test not a blocking gate
**Status: RESOLVED.** Phase 3 header now reads "Verify (blocking gate before push)" and the final line of the Test Plan states: "Phase 3 must complete successfully before the commit is pushed to any shared branch."

### Minor #6 — Model string not specified for all fallback Task subagents
**Status: RESOLVED.** All three fallback paths (Step 3a, 3b, 3c) now explicitly specify `model=claude-opus-4-6` in the Detailed Edit List items 4, 5, and 6.

### Minor #7 — gen-agent alias vs. full path / wrong base path
**Status: RESOLVED.** Detailed Edit List item 2 states: "Remove `~/workspaces/claude-devkit/generators/generate_agents.py` path and use `gen-agent` alias (also fixes pre-existing incorrect `~/workspaces/` path)." The acknowledgment of the pre-existing bug is present as recommended.

### Minor #8 — Version in commit message templates hardcoded
**Status: ACKNOWLEDGED (no action required).** This was informational and the plan correctly updates the hardcoded version from `v2.3.0` to `v3.0.0`. No change expected.

---

## New Issues Introduced by Revision

### Minor

#### 1. CLAUDE.md coordinator example update scope is ambiguous

The plan says to update the Coordinator Pattern example in CLAUDE.md (lines ~393-397), changing `Tool: MCP agent` to `Tool: Task (via .claude/agents/ if found, otherwise subagent_type=general-purpose)`. However, the actual CLAUDE.md Coordinator Pattern example (under "Archetype Patterns") has five steps, and TWO of them reference MCP:

```
## Step 1 — Main work (delegate to agent)
Tool: MCP agent

## Step 2 — Parallel quality reviews (3 agents)
Tool: Multiple MCP agents in parallel (red team + librarian + feasibility)
```

The plan shows both lines being updated, which is correct. However, the Pipeline Pattern and Scan Pattern examples in the same CLAUDE.md section also reference `Tool: MCP agent or Task` and `Tool: Multiple MCP agents in parallel`. The plan does not address these. Since the Pipeline and Scan archetypes (`/ship`, `/audit`) are explicitly out of scope for MCP removal, leaving their examples unchanged is consistent -- but this means CLAUDE.md will show the Coordinator example using Task while Pipeline and Scan examples still show MCP. This is a minor documentation inconsistency that could confuse a reader who scans all three examples together.

**Recommendation:** No action required for this plan. When the follow-up plans for `/audit` and `/sync` MCP removal are implemented, update the Pipeline and Scan examples at that time.

#### 2. Acceptance criterion 14 introduces a new CLAUDE.md change not in the original skill

Acceptance criterion 14 ("CLAUDE.md coordinator pattern example uses `Task` instead of `MCP agent`") is a documentation improvement that goes slightly beyond the strict scope of "remove MCP deps from `/dream` SKILL.md." This is a positive change -- it keeps the canonical example aligned with the actual implementation -- but it means the commit touches CLAUDE.md in two places (registry table + coordinator example) rather than just one. The rollback instruction correctly covers this ("Revert the commit containing both SKILL.md and CLAUDE.md changes"), so there is no operational risk.

**Recommendation:** No action required. This is noted for completeness only.

#### 3. Step 3a "security-specific plans only" condition is subjective

The plan states the security-analyst agent is invoked "only for security-specific plans" with examples: "authentication, authorization, cryptography, network." This condition is evaluated by the coordinator (the LLM running the skill), which introduces subjectivity. A plan about "add rate limiting to the API" could reasonably be classified as either security-specific or not. This is not a defect -- any heuristic here will be fuzzy -- but it means the security-analyst supplemental path will activate inconsistently across runs.

**Recommendation:** No action required. The security-analyst path is supplemental (it does not affect the Verdict), so inconsistent activation has low impact. The primary red-team Task subagent always runs regardless.

---

## Implementation Complexity Assessment (Updated)

| Area | Plan's Implied Complexity | Actual Complexity | Notes |
|------|--------------------------|-------------------|-------|
| SKILL.md edits | Low (single file, text replacements) | Low | Accurate. All changes are find-and-replace or paragraph rewrites. |
| Step 0 changes | Low (add one glob) | Low | Accurate. Trivial addition. |
| Step 3a replacement | Medium (Task subagent as primary, optional security-analyst) | Medium | Improved from initial review. The inverted priority (Task primary, agent optional) simplifies the implementation compared to the original agent-primary design. |
| Step 3b replacement | Low (drop-in Task subagent) | Low | Accurate. |
| Step 3c replacement | Low (remove fallback clause) | Low | Accurate. |
| CLAUDE.md updates | Low (two targeted edits) | Low | Now properly scoped with test coverage. |
| Rollback | Low (single revert) | Low | Accurate. |

**Overall estimate:** 1-2 hours of implementation work. No change from initial review.

---

## Summary of Remaining Concerns

| # | Severity | Concern | Action Required |
|---|----------|---------|----------------|
| 1 | Minor | CLAUDE.md Pipeline/Scan archetype examples still show MCP | None (follow-up plans) |
| 2 | Minor | CLAUDE.md coordinator example update extends commit scope slightly | None (already covered by rollback plan) |
| 3 | Minor | "Security-specific plans only" condition is subjective | None (supplemental path, low impact) |

No Critical or Major concerns remain.
