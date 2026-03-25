---
plan: dream-remove-mcp-deps.md
qa_engineer: qa-engineer agent (claude-devkit specialist)
validated_at: 2026-02-26
files_checked:
  - skills/dream/SKILL.md
  - CLAUDE.md
---

# QA Report: dream-remove-mcp-deps

## Verdict: PASS

All 14 acceptance criteria are met. The skill validator exits 0. All 7 test-plan commands return expected values. One pre-existing validator warning exists (timestamped artifacts advisory) that is unrelated to this plan's scope.

---

## Verification Command Results

| # | Command | Expected | Actual | Result |
|---|---------|----------|--------|--------|
| 1 | `grep -c "mcp__" skills/dream/SKILL.md` | `0` | `0` | PASS |
| 2 | `grep -c "agent-factory\|agent_factory" skills/dream/SKILL.md` | `0` | `0` | PASS |
| 3 | `head -6 skills/dream/SKILL.md \| grep "version:"` | `version: 3.0.0` | `version: 3.0.0` | PASS |
| 4 | `grep "security-analyst.md" skills/dream/SKILL.md` | at least 1 match | 2 matches (Step 0 glob + Step 3a optional invocation clause) | PASS |
| 5 | `grep "v3.0.0" skills/dream/SKILL.md` | at least 1 match | 2 matches (both commit message templates in Step 5) | PASS |
| 6 | `grep 'dream.*3.0.0' CLAUDE.md` | 1 match | 1 match (Skill Registry table row) | PASS |
| 7 | `grep -A2 "Main work (delegate to agent)" CLAUDE.md \| grep "Tool:"` | contains `Task`, not `MCP agent` | `Tool: Task (via .claude/agents/ if found, otherwise subagent_type=general-purpose)` | PASS |

Additional command from test plan (check 4 — three Tool declarations with Task):
- `grep -n "### 3a\|### 3b\|### 3c\|Tool:" skills/dream/SKILL.md` confirms:
  - Line 143: `Tool: \`Task\`, \`subagent_type=general-purpose\`, \`model=claude-opus-4-6\`` (3a)
  - Line 167: `Tool: \`Task\`, \`subagent_type=general-purpose\`, \`model=claude-opus-4-6\`` (3b)
  - Line 188: `Tool: \`.claude/agents/code-reviewer.md\` (if found), fallback to \`Task\`...` (3c)
  - All three contain `Task`; none contain `mcp__`. PASS

Validator run: `python3 generators/validate_skill.py skills/dream/SKILL.md` — exit code 0, PASS with 2 pre-existing warnings (see Notes below).

---

## Acceptance Criteria Coverage

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `skills/dream/SKILL.md` contains zero references to `mcp__agent-factory` or any MCP tool | MET | `grep -c "mcp__"` returns `0`. Only remaining "MCP" text is the parenthetical `— no MCP` in Step 4 prose, which is documentation of the absence, not a tool invocation. |
| 2 | `skills/dream/SKILL.md` frontmatter version is `3.0.0` | MET | Line 5: `version: 3.0.0` |
| 3 | `validate-skill skills/dream/SKILL.md` passes (exit code 0) | MET | Exit code 0 confirmed. Two warnings are pre-existing and optional (timestamped artifacts advisory; Step 5 missing `Tool:` which validator itself notes "Coordinator/verdict steps may omit this"). |
| 4 | Step 0 checks for three local agents: `senior-architect.md`, `code-reviewer.md`, `security-analyst.md` | MET | Lines 20-22 in SKILL.md: Pattern 1, 2, and 3 glob for all three. All three have found/not-found message branches (lines 24-42). |
| 5 | Step 2 uses local `senior-architect.md` with Task subagent fallback (no MCP) | MET | Line 87: "Invoke the project-level architect. If none found, use a Task subagent with general-purpose prompt." Line 91: `Tool: \`Task\`, \`subagent_type=general-purpose\`, \`model=claude-opus-4-6\``. No MCP reference. |
| 6 | Step 3a uses Task subagent with explicit red-team prompt as PRIMARY path, optional `security-analyst.md` for security-specific plans only; output format (Verdict + severity ratings) specified in prompt | MET | Lines 143-163. Primary Task path is unconditional. Prompt specifies `## Verdict: PASS or FAIL` and severity ratings `Critical / Major / Minor / Info`. Optional security-analyst invocation is gated on both "found in Step 0" AND "plan subject is security-related". |
| 7 | Step 3b uses Task subagent directly (no agent file, no MCP) | MET | Line 167: `Tool: \`Task\`, \`subagent_type=general-purpose\`, \`model=claude-opus-4-6\``. No agent file reference, no MCP. |
| 8 | Step 3c uses local `code-reviewer.md` with Task subagent fallback (no MCP) | MET | Line 188: `Tool: \`.claude/agents/code-reviewer.md\` (if found), fallback to \`Task\`, \`subagent_type=general-purpose\`, \`model=claude-opus-4-6\``. No MCP reference. |
| 9 | Step 4 revision loop matches Step 2 pattern (no MCP) | MET | Line 210: "using the same pattern as Step 2 (local `.claude/agents/senior-architect.md` preferred, Task subagent fallback — no MCP)." Line 212: `Tool: \`Task\`, \`subagent_type=general-purpose\`, \`model=claude-opus-4-6\``. |
| 10 | Step 5 commit messages reference `v3.0.0` | MET | `grep "v3.0.0" skills/dream/SKILL.md` returns 2 matches: APPROVED commit message (line ~272) and FAIL commit message (line ~283). Both reference `/dream v3.0.0`. |
| 11 | All "not found" messages in Step 0 suggest `gen-agent` (not MCP generation) | MET | Lines 28, 35, 41: all three "not found" messages use `` `gen-agent . --type <agent-type>` ``. No MCP generation path. No `~/workspaces/` path reference. |
| 12 | Workflow structure (step ordering, revision bounds, verdict logic) is unchanged | MET | Steps 0-5 present in correct order. `Max 2 revision rounds total` preserved (line 228). PASS/FAIL verdict gate logic intact (lines 237, 297). `--fast` flag still skips red team (line 139). |
| 13 | CLAUDE.md Skill Registry table shows dream version `3.0.0` | MET | `grep 'dream.*3.0.0' CLAUDE.md` returns 1 match in the Skill Registry table. |
| 14 | CLAUDE.md coordinator pattern example uses `Task` instead of `MCP agent` | MET | Line 394 in CLAUDE.md: `Tool: Task (via .claude/agents/ if found, otherwise subagent_type=general-purpose)`. Line 397: `Tool: Task (multiple subagents in parallel: red team + librarian + feasibility)`. Both coordinator example steps use Task. |

---

## Missing Tests or Edge Cases

### Tests Not Covered by the Automated Checklist

1. **`--fast` flag behavior.** The test plan has no automated check that `--fast` skips Step 3a. The SKILL.md text at line 139 correctly says "skip the red team call," but there is no grep or structural test validating this branch path. This is an integration-test gap, not a blocking issue.

2. **Step 3a optional security-analyst invocation — double-condition gate.** The plan specifies the optional invocation requires both (a) `security-analyst.md` found in Step 0 AND (b) plan subject is security-related. The automated checks only verify the glob is present and the reference to `security-analyst.md` exists. They do not validate that the "AND the plan subject is security-related" condition is present in the prose. Manual review of lines 163-164 confirms both conditions are present in the SKILL.md text.

3. **Validator warnings.** The validator emits two warnings:
   - "Timestamped Artifacts: Consider using timestamped filenames" — pre-existing advisory, unrelated to this plan. The `/dream` skill uses feature-name slugs, not timestamps, which is by design.
   - "Step(s) 5 missing 'Tool:' declaration" — the validator itself notes this is acceptable for coordinator/verdict steps. Step 5 does include a `Tool: \`Bash\`` declaration for the auto-commit sub-step. The warning appears to be triggered by the step's primary heading, not the sub-step. Pre-existing, not introduced by this plan.

4. **Integration test (Phase 3) not executed.** The plan's blocking gate — running `/dream` in a live Claude Code session with and without local agents — cannot be validated by static analysis. This report does not cover Phase 3. The plan correctly documents this as a manual gate.

5. **CLAUDE.md Scan Pattern still uses "MCP agents."** The Scan Pattern example (lines ~471) retains `Tool: Multiple MCP agents in parallel`. This is explicitly listed in the plan's Non-Goals ("Modifying other skills"). The Coordinator Pattern example (the target of AC-14) was correctly updated. No defect.

6. **`agent-factory` grep uses word boundary patterns.** The test command `grep -c "agent-factory\|agent_factory"` would not catch a hypothetical `agentfactory` reference. This edge case does not apply here since the old tool names used underscores and hyphens, and the grep count is 0 regardless.

---

## Notes

- The `grep -A1 "### 3a\|### 3b\|### 3c"` command in test plan item 4 fails to match the `Tool:` line because a blank line exists between the heading and the `Tool:` declaration (requires `-A2`). The underlying content is correct — all three steps have Task tool declarations — but the exact grep command from the test plan produces no output instead of three lines. This is a test plan documentation defect, not an implementation defect. Recommend updating the test plan to use `-A2`.

- The word "MCP" appears once in SKILL.md as documentation text (`— no MCP` in Step 4, line 210). This is not a tool invocation and is desirable: it clarifies intent for future maintainers. `grep -c "mcp__"` (which targets actual MCP tool call syntax) correctly returns 0.

- Both commit message templates (APPROVED and FAIL) in Step 5 correctly reference `v3.0.0`, satisfying AC-10.

- All three `gen-agent` suggestions in Step 0 use the correct alias syntax (`gen-agent . --type <type>`), fixing the pre-existing incorrect `~/workspaces/claude-devkit/generators/generate_agents.py` path that was documented in the plan's edit list.
