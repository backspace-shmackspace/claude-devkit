# Review: Red Hat Internal Browser MCP Server Plan (Second Pass)

**Reviewed:** 2026-02-24
**Plan file:** `./plans/redhat-internal-browser-mcp.md`
**Reviewer:** devkit-architect
**Review type:** Second pass -- verifying 3 required edits from first review
**Verdict:** PASS

---

## Required Edit Status

### 1. Fix context metadata to cite prior plans -- RESOLVED

**First review finding:** Context metadata had `recent_plans_consulted: none` despite relevant prior plans existing.

**Current state (line 1011):**
```
recent_plans_consulted: journal-skill-blueprint.md, zerg-adoption-priorities.md
```

Both plans are now cited. The metadata also includes `revised_at: 2026-02-24` and `revision_trigger: red team FAIL + feasibility REVISE + librarian required edits`, which provides good provenance for the revision.

**Verdict:** Fully addressed.

### 2. Acknowledge contrib/ precedent in Context Alignment -- RESOLVED

**First review finding:** The Context Alignment section did not acknowledge that `contrib/` was the prior decision for personal tools, or explain why MCP servers warrant a different directory.

**Current state (lines 956-957, 967):**

The Context Alignment table row for "Personal tools in contrib/" now reads:

> **Deviation:** Using `mcp-servers/` instead of `contrib/` because MCP servers require different deployment (process lifecycle, venv, CLI) vs skill deployment (copy SKILL.md). The `contrib/` directory was established for optional skills (journal-skill-blueprint.md, APPROVED), but MCP servers differ in deployment model (running processes with venvs vs. markdown files copied by `deploy.sh`), justifying a distinct top-level directory.

The "Deviations with Justification" section (item 1, line 967) reinforces this:

> This is consistent with the `contrib/` precedent (journal-skill-blueprint.md, APPROVED) which chose `contrib/` specifically for optional *skills* -- MCP servers are not skills.

The zerg-adoption-priorities.md precedent is also cited in the table (line 957) with specific alignment points (opt-in, loosely coupled, swappable).

**Verdict:** Fully addressed. The justification is clear and the prior decisions are properly cited.

### 3. Expand Phase 6 with specific CLAUDE.md sections -- RESOLVED

**First review finding:** Phase 6 was vague about the scope of CLAUDE.md changes.

**Current state (lines 736-764):** Phase 6 now enumerates six specific CLAUDE.md changes:

1. **Architecture section** -- Rename heading, add `mcp-servers/` to directory tree with annotation
2. **MCP Server Registry** -- New section parallel to Skill Registry, with table schema and initial row
3. **Data Flow diagram** -- Updated to show MCP server path (`install.sh` -> `claude mcp add`)
4. **Development Rules** -- "For MCP Servers" subsection with five specific rules (pinned deps, pip-audit, permissions, audit logging, data classification)
5. **Directory Reference** -- New `/mcp-servers` section
6. **Recommended `.gitignore`** -- Add `mcp-servers/*/.venv/`

Each item includes concrete content (directory tree snippets, table schema, rule list). This is sufficient detail for an implementer to execute without ambiguity.

**Verdict:** Fully addressed.

---

## New Conflict Check

Verified that the revisions did not introduce new conflicts with CLAUDE.md rules:

| Check | Result |
|-------|--------|
| Architecture patterns still consistent | No conflict -- `mcp-servers/` is justified as a new tier |
| No new unbounded loops introduced | N/A -- this is not a skill |
| No external dependency violations | N/A -- generators are stdlib-only; MCP servers are a different component type with their own dependency model |
| Deployment model documented | Yes -- Phase 6 includes Data Flow update showing the MCP-specific path |
| Version field present | Yes -- Plan Metadata includes `Version: 1.0.0` (line 992) |
| Context metadata complete | Yes -- all fields populated with accurate values |
| Revision provenance tracked | Yes -- `revised_at` and `revision_trigger` fields present |

No new conflicts detected.

---

## Verdict Rationale

The plan receives **PASS** because:

1. All three required edits from the first review have been fully addressed
2. Context metadata now correctly cites both prior plans (journal-skill-blueprint.md, zerg-adoption-priorities.md)
3. The Context Alignment section clearly acknowledges the `contrib/` precedent and justifies the deviation
4. Phase 6 now contains specific, actionable CLAUDE.md update instructions with concrete content
5. No new conflicts were introduced by the revisions
6. The architecture remains sound with proper justification for the new directory tier

No further edits required. The plan is ready for implementation.
