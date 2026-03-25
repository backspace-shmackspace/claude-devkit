# Feasibility Review: Remove MCP Agent-Factory Dependency from /sync Skill

**Plan:** `./plans/sync-remove-mcp-deps.md`
**Reviewer:** Feasibility (code-reviewer mode)
**Date:** 2026-02-26
**Skill reviewed:** `skills/sync/SKILL.md` (v2.0.1)
**Precedent:** `dream-remove-mcp-deps.md` (APPROVED), `dream-remove-mcp-deps.feasibility.md` (PASS)

---

## Verdict: PASS

The plan is technically sound, accurately scoped, and directly precedented by the approved and executed `/dream` MCP removal. Implementation complexity is minimal: two line-level edits across two files. No edge cases in the `/sync` skill are affected by the tool swap. The validator will continue to pass. No breaking changes to external consumers exist. The plan is ready for implementation as written.

---

## Implementation Complexity Assessment

| Area | Plan's Implied Complexity | Actual Complexity | Notes |
|------|--------------------------|-------------------|-------|
| SKILL.md frontmatter bump | Trivial | Trivial | One-field change: `2.0.1` → `3.0.0`. |
| Step 3 tool declaration swap | Low | Low | Single-line replacement. Prompt block (lines 62–103) is already self-contained and unchanged. |
| CLAUDE.md registry update | Trivial | Trivial | One cell in a table row: version string only. |
| Validator pass confirmation | Low | Low | Validator checks for `Tool:` keyword presence (not tool identity), `## Step N` structure, `CURRENT/UPDATES_NEEDED` verdict gates, `[timestamp]` artifacts, `./plans/archive/` reference, `## Inputs` section. All of these are present and unaffected by the change. |
| Rollback | Trivial | Trivial | Single `git revert` + `deploy.sh`. |

**Overall estimate:** 15–30 minutes of implementation work. Significantly less than the dream MCP removal (which required 8 targeted edits across Steps 0, 2, 3a, 3b, 3c, 4, and 5).

---

## Concerns

### Critical

None.

---

### Major

None.

---

### Minor

#### 1. The plan's line-number references in the Task Breakdown may be stale

The plan states "Step 3 tool declaration (line 60)" and "Frontmatter (line 4)." The current SKILL.md confirms these line numbers are accurate at the time of plan authorship. However, if any other edit touches SKILL.md before this plan is executed, those references will be wrong.

**Impact:** Low. The edit targets a unique string (`mcp__agent-factory__agent_librarian_v1`) that appears exactly once in the file. The actual Edit tool will match on content, not line number. Line-number references in the plan prose are navigation hints, not operational instructions.

**Recommendation:** No action required. The implementation should match on the literal string, not the line number. The plan's acceptance criteria (grep checks, not line checks) are correctly specified.

---

#### 2. Model string `claude-sonnet-4-5` is not the current frontier model

The plan specifies `model=claude-sonnet-4-5` for the replacement Task subagent, matching the existing Step 4 Task subagent and the skill's frontmatter. The validator's model allowlist includes `claude-sonnet-4-5` as a valid value. However, `claude-sonnet-4-5` is one generation behind the current frontier (`claude-sonnet-4-6` or `claude-opus-4-6`).

**Impact:** Low. The `/sync` skill is explicitly a sonnet-tier workflow (documentation review, not architecture planning). Using `claude-sonnet-4-5` is consistent with the skill's declared model and existing Step 4 subagent. This is a pre-existing design choice, not introduced by this plan.

**Recommendation:** No action required for this plan. If a model upgrade is desired, it should be a separate version bump that updates all model references in sync/SKILL.md together.

---

#### 3. The plan does not update the Step 4 Task subagent's `model=` parameter

Step 4 of the current SKILL.md already uses `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5` (line 118). The plan correctly leaves Step 4 unchanged. However, the plan also does not note that Step 4's model is already set — a reader who scans only the "Proposed Architecture" table sees `Task subagent (apply updates — unchanged)` but may not know Step 4 already correctly specifies the model.

**Impact:** None. This is a documentation clarity issue in the plan, not an implementation risk. The implementation instructions are unambiguous: only two edits, both enumerated.

**Recommendation:** No action required.

---

#### 4. No mention of deployed file synchronization in acceptance criteria

The acceptance criteria (items 1–9) check the source file `skills/sync/SKILL.md` and `CLAUDE.md`. They do not include a check that the deployed file `~/.claude/skills/sync/SKILL.md` matches. The rollout plan (Phase 2) does include a `diff` check, but it is not an acceptance criterion.

**Impact:** Low. The deploy script (`./scripts/deploy.sh sync`) is deterministic — it copies the source file verbatim. A `diff` mismatch post-deploy would indicate a deploy script bug, which is out of scope for this change.

**Recommendation:** No action required. The Phase 2 diff check in the rollout plan adequately covers this. Elevating it to an acceptance criterion would be slightly redundant.

---

## Edge Case Analysis

| Edge Case | Affected? | Assessment |
|-----------|-----------|------------|
| **`/sync` invoked with no CLAUDE.md in target project** | No | Step 3 prompt already handles this: "Read the current `CLAUDE.md` and `README.md` files." If CLAUDE.md is absent, the subagent will discover that during execution. This behavior is identical whether the tool is MCP or Task. |
| **`/sync full` scope produces large git log output injected into Step 3 prompt** | No | The Task subagent receives the same prompt content as the MCP agent did. Large context is handled by the LLM runtime regardless of whether the outer tool is MCP or Task. |
| **Review artifact already exists at `./plans/sync-[timestamp].review.md`** | No | Timestamp collision is astronomically unlikely and is a pre-existing condition unrelated to this change. |
| **Step 4 reads a review file written by Step 3's Task subagent vs. MCP agent** | No | The review file format (Verdict heading, Required Updates, Suggested Updates, Rationale) is specified in the Step 3 prompt and is unchanged. Step 4's conditional logic (`If verdict is CURRENT` / `If verdict is UPDATES_NEEDED`) parses the same markers. |
| **Validator flags `Task` as an unexpected tool declaration** | No | The validator (`validate_skill.py`) checks for the presence of `Tool:` keyword in step content. It does not check the tool's identity. `Tool: \`Task\`` satisfies the check identically to `Tool: \`mcp__agent-factory__agent_librarian_v1\``. See `validate_patterns()` in the validator source. |
| **Permission prompt regression** | No — this is the fix | `mcp__agent-factory__agent_librarian_v1` is not in the global allowlist. `Task` is. The change eliminates the prompt source entirely. |

---

## Test Coverage Assessment

The plan's test coverage is complete for the scope of change:

| Test | Coverage Quality | Notes |
|------|-----------------|-------|
| `validate_skill.py` exit code 0 | Adequate | Confirms structural integrity post-edit. |
| `grep -c "mcp__"` returns 0 | Adequate | Primary removal verification. |
| `grep -c "agent-factory\|agent_factory"` returns 0 | Adequate | Belt-and-suspenders MCP removal check. |
| `head -6 \| grep "version:"` returns `3.0.0` | Adequate | Confirms frontmatter change. |
| `grep -A1 "## Step 3" \| grep "Tool:"` | Adequate | Confirms Step 3 has a `Tool:` declaration (not that it's `Task` specifically). See gap below. |
| Prompt content spot-check | Adequate | Confirms prompt body was not accidentally truncated. |
| CLAUDE.md registry grep | Adequate | Confirms registry update. |
| Manual integration test (blocking gate) | Strong | End-to-end verification before push. |

**One gap:** Test item 4 (`grep -A1 "## Step 3" | grep "Tool:"`) verifies that Step 3 has a `Tool:` declaration but does not verify the specific value `Task`. A more precise check would be:

```bash
grep -A1 "## Step 3" skills/sync/SKILL.md | grep "Tool:.*Task"
```

**Impact:** Low. The prompt content spot-check (test item 6) confirms the MCP tool name is gone. The `grep -c "mcp__"` check (test item 1) would catch any residual MCP reference. The gap is belt-and-suspenders precision, not a coverage hole.

**Recommendation:** Optional improvement. Add `| grep "Tool:.*Task"` to test item 4 for precision. Not blocking.

---

## Breaking Change Assessment

**External consumers:** No external system or workflow depends on `/sync` invoking `agent_librarian_v1`. The MCP tool call is an implementation detail internal to the skill. The skill's public contract — inputs (`recent` / `full` scope), outputs (review artifact at `./plans/sync-[timestamp].review.md`, verdict values `CURRENT` / `UPDATES_NEEDED`, archive at `./plans/archive/sync/`) — is unchanged.

**Semver rationale:** The plan justifies the `2.0.1 → 3.0.0` major bump as removing the MCP dependency contract. This is correctly classified as a breaking change under semver if any consumer expected the MCP tool to be invoked (e.g., for audit logging, observability, or agent-factory telemetry). The version bump follows the established precedent from the dream skill (`2.3.0 → 3.0.0`). No objection.

---

## Precedent Validation

The dream skill's Step 3b librarian replacement is structurally identical to this plan's Step 3 replacement:

| Dimension | dream Step 3b | sync Step 3 |
|-----------|--------------|-------------|
| MCP tool replaced | `mcp__agent-factory__agent_librarian_v1` | `mcp__agent-factory__agent_librarian_v1` |
| Replacement | `Task, subagent_type=general-purpose, model=claude-opus-4-6` | `Task, subagent_type=general-purpose, model=claude-sonnet-4-5` |
| Prompt changed | No | No |
| Output format changed | No | No |
| dream plan status | APPROVED, executed successfully | — |

The `/sync` change is a strict subset of what was already validated and executed for `/dream`. The only difference is the model tier (`opus` vs. `sonnet`), which is appropriate for the respective skills' declared models.

---

## Omissions and Gaps in the Plan

None identified that require action. The following non-issues are noted for completeness:

1. **No mention of `task-model-fix-context-preservation.md`** — That plan (visible in `plans/`) contains a historical snapshot of the sync skill's Step 3 using `mcp__agent-factory__agent_librarian_v1`. This is expected: plans archive the state at time of writing. The snapshot in that plan is a record, not a live reference. No cleanup required.

2. **`audit-remove-mcp-deps.md` is a sibling plan** — The audit MCP removal plan is in DRAFT status. Its Non-Goals explicitly lists `/sync` as out of scope. No interaction risk with this plan.

3. **Coordinator template** — `templates/skill-coordinator.md.template` still references MCP agent-factory examples. The plan explicitly excludes this as a Non-Goal, consistent with the sequence established in `dream-remove-mcp-deps.md`. No objection.

---

## Summary of Concerns

| # | Severity | Concern | Action Required |
|---|----------|---------|----------------|
| 1 | Minor | Line-number references in Task Breakdown may be stale at execution time | None — implementation should match on content string, not line number |
| 2 | Minor | `claude-sonnet-4-5` is not the current frontier model | None — pre-existing design choice, separate concern |
| 3 | Minor | Step 4 model consistency not noted in plan prose | None — implementation instructions are unambiguous |
| 4 | Minor | Deployed file diff check is in rollout plan but not acceptance criteria | None — adequately covered by Phase 2 |
| 5 | Minor | Test item 4 could be more precise about verifying `Task` specifically | Optional improvement — not blocking |

No Critical or Major concerns.
