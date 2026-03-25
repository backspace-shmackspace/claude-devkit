# Red Team Review: Remove MCP Agent-Factory Dependencies from /dream Skill

**Plan:** `dream-remove-mcp-deps.md`
**Reviewer:** Red Team (Task subagent, critical reviewer mode)
**Date:** 2026-02-26
**Review Round:** 2 (revision re-review)

## Verdict: PASS

The revised plan adequately addresses the two Critical and four Major findings from the first review. The cross-skill MCP inconsistency is now explicitly scoped and documented. The CLAUDE.md coordinator example update is in scope. The security-analyst misuse has been corrected. The rollback plan is strengthened. No new Critical or Major issues were introduced. The remaining findings are Minor or Info-level and do not block execution.

---

## Resolution of Previous Findings

### Finding 1 (was Critical): Other skills/templates still reference MCP agent-factory
**Status: Resolved (Minor residual)**

The revised plan addresses this in three places:
- Non-Goals (line 16): Explicitly states "/audit and /sync still reference MCP agent-factory tools (agent_hardener, agent_librarian_v1). Those are separate changes to be addressed in follow-up plans."
- Non-Goals (line 18): Explicitly states the coordinator template "will be addressed in a separate plan after the /dream, /audit, and /sync MCP removals are complete."
- Risks table: Adds a "Cross-skill inconsistency" row rated Known/Low with clear mitigation language.
- Deviations section: Acknowledges "/audit, /sync, and the coordinator template still use MCP references; those are separate changes."

The version bump messaging now specifies "/dream only" scope (lines 9, 16, 213, 359). This is sufficient. A user reading the plan or commit message will not mistake this for a devkit-wide MCP removal.

**Residual risk (Minor):** There is no explicit timeline or plan reference for the follow-up `/audit` and `/sync` MCP removals. The Non-Goals say "follow-up plans" but do not name them or commit to a timeframe. This is acceptable for a plan document but worth noting.

### Finding 2 (was Critical): CLAUDE.md coordinator pattern example becomes stale
**Status: Resolved**

The revised plan now includes a dedicated "Coordinator Pattern Example Update" subsection (lines 146-162) with explicit before/after diffs. The CLAUDE.md is listed in "Files to Modify" (line 309) with the coordinator pattern update in scope. Acceptance criteria 14 (line 300) validates this: "CLAUDE.md coordinator pattern example uses Task instead of MCP agent." Test plan item 8 (lines 269-272) provides a grep verification command. This is thorough.

### Finding 3 (was Major): Security-analyst is a threat modeler, not a plan critic
**Status: Resolved**

This was the most significant revision. The plan now correctly treats the Task subagent with an explicit red-team prompt as the PRIMARY path for Step 3a (line 77). The security-analyst agent is demoted to OPTIONAL, used "only for security-specific plans where STRIDE analysis is relevant" (line 98). Assumption 5 (line 26) explicitly acknowledges that "security-analyst.md agent outputs STRIDE tables and compliance checklists, which do not match the expected red-team output format." This is the right design decision.

### Finding 4 (was Major): No quality baseline for Task subagent vs MCP agent output
**Status: Partially Resolved (Minor residual)**

The revised plan improves the red-team prompt (lines 79-95) by explicitly specifying the output format: Verdict heading + severity-rated findings with PASS/FAIL logic. This is a concrete improvement over the original vague prompt. The Risks table (line 209) now explains the mitigation: "The Task subagent prompt now explicitly specifies the output format (Verdict + severity-rated findings), which aligns with Step 4's revision trigger logic."

However, the plan still does not include a parallel comparison run against the MCP agents. The original recommendation was to run 2-3 existing plans through both paths and compare. This remains unaddressed, but I am downgrading to Minor because: (a) the `redteam_v2` MCP agent was being misused (PRODSECRM-specific agent used for generic plan critique, as the plan now correctly identifies), so it is not a reliable quality baseline to compare against, and (b) the explicit output format specification makes the Task subagent's behavior more predictable and testable.

### Finding 5 (was Major): CLAUDE.md listed as read-only but requires edits
**Status: Resolved**

CLAUDE.md is now listed under "Files to Modify" (line 309), not "Files to Verify (Read-Only)." The edit scope is complete: version update in Skill Registry table AND coordinator pattern example update (line 309). The "Detailed Edit List for CLAUDE.md" section (lines 332-333) specifies both changes explicitly.

### Finding 6 (was Major): Rollback plan is incomplete
**Status: Resolved**

The rollback plan (lines 200-203) now says "Revert the commit containing both SKILL.md and CLAUDE.md changes" (implying a single commit), and the Rollout Plan Phase 1 step 4 (line 186) specifies "Commit both files in a single commit." This eliminates the multi-commit concern. The rollback uses `git revert <commit-hash>` (not `git revert HEAD`), addressing the HEAD assumption issue.

### Finding 7 (was Minor): No test for --fast flag path
**Status: Not addressed**

The plan still has no test case for the `--fast` flag path. The `--fast` flag skips Step 3a (red team review). After the changes, this means `--fast` will skip the new Task subagent red-team path. The test plan only covers the full path (integration test at line 277). This remains a gap but is Minor -- the `--fast` path is simpler (skips a step), so there is less that can go wrong.

### Finding 8 (was Minor): No verification that gen-agent --type security-analyst works
**Status: Not addressed**

The plan still suggests `gen-agent . --type security-analyst` in the Step 0 "not found" message but does not verify this command works. I checked the generators directory -- there is no evidence in the README or source that `--type security-analyst` is a valid standalone argument (the `generate_agents.py` script supports `--type all` and potentially individual types, but this is unverified). This remains Minor.

### Finding 9 (was Minor): Model cost implications not addressed
**Status: Not addressed**

No changes related to cost. Remains Minor. The MCP agents' model configuration is unknown, so the cost impact is unknowable without investigation. Acceptable to defer.

### Finding 10 (was Minor): Acceptance criterion 12 is untestable
**Status: Not addressed**

Criterion 12 ("The workflow structure is unchanged") still has no automated verification. Remains Minor.

### Finding 11 (was Info): "No functional change" claim is misleading
**Status: Resolved**

The plan now correctly states (line 71): "The prompt and output format are unchanged. The fallback execution path changes from MCP agent to Task subagent."

### Finding 12 (was Info): Stale ~/workspaces/ path reference
**Status: Resolved**

The plan addresses this in Detailed Edit List item 2 (line 322): "Remove ~/workspaces/claude-devkit/generators/generate_agents.py path and use gen-agent alias (also fixes pre-existing incorrect ~/workspaces/ path)."

---

## New Issues Introduced by Revision

### 13. Security-plan detection heuristic is undefined (Minor)

**Description:** Step 3a (line 98) says the security-analyst agent is invoked "AND the plan subject is security-related (e.g., authentication, authorization, cryptography, network)." This heuristic is not defined. How does the coordinator determine whether a plan subject is "security-related"? Is it keyword matching on $ARGUMENTS? On the plan content? On the plan title?

Without a concrete detection mechanism, this will be implemented inconsistently. One run might trigger the security-analyst supplement for a plan titled "add API endpoint" (because APIs involve authentication), while another might not.

**Risk:** Inconsistent behavior across runs. The security-analyst supplement is either always triggered (noisy) or never triggered (useless), depending on the implementer's interpretation.

**Recommendation:** Either (a) define the heuristic explicitly (e.g., "if $ARGUMENTS contains any of: auth, security, encrypt, credential, token, RBAC, ACL, TLS, CORS, CSRF, XSS, injection"), (b) make it a flag (`--security` triggers the supplement), or (c) drop the optional security-analyst invocation entirely and rely solely on the Task subagent red-team prompt. Option (c) is simplest and the plan already works without this optional path.

### 14. Acceptance criterion 6 is compound and hard to verify (Minor)

**Description:** Criterion 6 (line 292) packs multiple requirements into one: "Step 3a uses Task subagent with explicit red-team prompt as the primary path, with optional security-analyst.md for security-specific plans only. Output format (Verdict + severity ratings) is specified in the prompt."

This is three separate verifiable conditions crammed into one criterion. During acceptance testing, a reviewer might check that the Task subagent is used but miss that the output format specification is present in the prompt text, or vice versa.

**Risk:** Incomplete acceptance verification.

**Recommendation:** Split into: (6a) Step 3a tool declaration is `Task`, not `mcp__*`. (6b) Step 3a prompt specifies output format (Verdict heading + severity ratings). (6c) Security-analyst invocation is conditional on plan subject.

### 15. The coordinator template is explicitly deferred but no tracking mechanism exists (Info)

**Description:** The plan says the coordinator template update "will be addressed in a separate plan after the /dream, /audit, and /sync MCP removals are complete" (line 18). There is no issue, ticket, or plan stub created to track this. If the follow-up plans are never written, the template will remain stale indefinitely.

**Risk:** Template drift. New skills generated from the coordinator template will scaffold MCP references that are no longer the recommended pattern.

**Recommendation:** Create a placeholder plan file (`plans/update-coordinator-template-post-mcp.md`) with status DRAFT, or add a TODO comment in the coordinator template itself.

---

## Summary Table

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 1 | Other skills/templates still reference MCP agent-factory | ~~Critical~~ Minor | Resolved (residual: no follow-up timeline) |
| 2 | CLAUDE.md coordinator pattern example becomes stale | ~~Critical~~ | Resolved |
| 3 | Security-analyst agent is not a plan critic | ~~Major~~ | Resolved |
| 4 | No quality baseline for Task subagent vs MCP agent output | ~~Major~~ Minor | Partially resolved (output format specified; no parallel comparison) |
| 5 | CLAUDE.md listed as read-only but requires edits | ~~Major~~ | Resolved |
| 6 | Rollback plan is incomplete | ~~Major~~ | Resolved |
| 7 | No test for `--fast` flag path | Minor | Open |
| 8 | No verification that `gen-agent --type security-analyst` works | Minor | Open |
| 9 | Model cost implications not addressed | Minor | Open |
| 10 | Acceptance criterion 12 is untestable as written | Minor | Open |
| 11 | "No functional change" claim is misleading | ~~Info~~ | Resolved |
| 12 | Stale `~/workspaces/` path reference | ~~Info~~ | Resolved |
| 13 | Security-plan detection heuristic is undefined (NEW) | Minor | Open |
| 14 | Acceptance criterion 6 is compound (NEW) | Minor | Open |
| 15 | No tracking for deferred coordinator template update (NEW) | Info | Open |

**Critical: 0 | Major: 0 | Minor: 7 | Info: 1**

---

## Conclusion

The revision addressed all six blocking findings (2 Critical, 4 Major) from the first review. The key improvements are:

1. Cross-skill inconsistency is explicitly scoped and documented with follow-up plan references.
2. CLAUDE.md coordinator example update is now in scope with verification tests.
3. Security-analyst agent is correctly relegated to optional/supplemental role; Task subagent with explicit red-team prompt is the primary path.
4. CLAUDE.md is properly listed as a write target with complete edit scope.
5. Rollback plan uses single commit with explicit hash-based revert.
6. Misleading "no functional change" language is corrected.

The remaining 7 Minor and 1 Info findings are quality-of-life improvements that do not block execution. The plan is ready to proceed.
