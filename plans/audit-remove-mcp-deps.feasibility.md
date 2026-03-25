---
plan: audit-remove-mcp-deps.md
reviewed_at: 2026-02-26
reviewer: feasibility-analysis
---

# Feasibility Review — audit-remove-mcp-deps.md

## Verdict: PASS

The plan is technically sound and follows an established pattern (`dream-remove-mcp-deps.md`). The core operation — replacing `mcp__agent-factory__agent_hardener` with a `Task` subagent and the local `security-analyst.md` agent — is a low-risk, high-confidence change. All concerns below are Minor or Info; none are blockers.

---

## Concerns

### Critical

None.

---

### Major

None.

---

### Minor

#### 1. `dream/SKILL.md` glob exclusion list references `.hardener.md` — not `.security.md`

**File:** `/Users/imurphy/projects/claude-devkit/skills/dream/SKILL.md`, line 55

**Current text:**
```
Glob `./plans/*.md` (exclude `*.redteam.md`, `*.review.md`, `*.feasibility.md`, `*.code-review.md`, `*.qa-report.md`, `*.test-failure.log`, `*.summary.md`, `*.hardener.md`, `*.performance.md`, `*.qa.md`)
```

**Problem:** After this plan ships, audit scans will produce `audit-[timestamp].security.md`. The `/dream` skill excludes `.hardener.md` from its "recent plans" glob to avoid surfacing audit artifacts as plan candidates. Once the artifact is renamed to `.security.md`, that pattern no longer excludes it. Audit security artifacts could appear as candidates in `/dream`'s "Recent Plans" list.

**Scope gap:** The plan's Non-Goals and task breakdown do not include editing `skills/dream/SKILL.md`. The plan's task breakdown lists only two files to modify: `skills/audit/SKILL.md` and `CLAUDE.md`.

**Recommendation:** Add `skills/dream/SKILL.md` to the task breakdown. Replace `*.hardener.md` with `*.security.md` in the exclusion list on line 55. This is a one-line edit.

---

#### 2. `CLAUDE.md` Artifact Locations section references `.hardener.md` in two places — plan only updates the Skill Registry

**File:** `/Users/imurphy/projects/claude-devkit/CLAUDE.md`

**Current references (not in plan's edit list):**

Line 272 (Workflow 2 — Security Audit):
```
- `plans/audit-[timestamp].hardener.md` — Security findings
```

Line 546 (Artifact Locations directory tree):
```
├── audit-[timestamp].hardener.md          # Security scan results
```

**Problem:** The plan's CLAUDE.md edit list (Section: Detailed Edit List for CLAUDE.md) specifies only one change — the Skill Registry table row. The Workflow 2 artifact listing and the Artifact Locations directory tree both contain `.hardener.md` and will be stale after the rename.

**Recommendation:** Add these two locations to the CLAUDE.md edit list. Both are documentation-only and carry no functional risk, but will create misleading docs for users following the Workflow 2 example.

---

#### 3. `README.md` does not reference `.hardener.md` but may reference audit artifacts

**File:** `/Users/imurphy/projects/claude-devkit/README.md`

**Finding:** A grep for `hardener` in `README.md` returned no matches. This concern is informational only — the README does not need updating for this plan.

---

#### 4. `templates/skill-scan.md.template` references `mcp__agent-factory__agent_hardener`

**File:** `/Users/imurphy/projects/claude-devkit/templates/skill-scan.md.template`, line 40

**Current text:**
```
Tool: MCP agent (e.g., `mcp__agent-factory__agent_hardener`) or `Task`
```

**Problem:** The template still cites the hardener as an example. This is a template (not a deployed skill), so it carries no runtime impact. However, it documents a pattern that this plan is explicitly removing.

**Scope:** The plan's Non-Goals state "Modifying templates/skill-scan.md.template" is explicitly out of scope. This is an accepted gap.

**Recommendation:** No action required in this plan. A follow-up task to update the template example would be appropriate after this plan ships.

---

#### 5. `security-analyst.md` output format differs from current `agent_hardener` output format

**File reviewed:** `/Users/imurphy/projects/claude-devkit/.claude/agents/security-analyst.md`

**Finding:** The `security-analyst.md` agent has a prescribed output format (lines 74–130) that uses sections: `Executive Summary`, `Threat Model`, `Assets`, `Trust Boundaries`, `Attack Vectors`, `STRIDE Analysis`, `Risk Assessment` (table), `Security Architecture`, `Compliance Checklist`, `Implementation Plan`, `Verification Strategy`.

The current `/audit` skill's Step 2 prompts instruct the agent to:
- Rate findings as `Critical / High / Medium / Low`
- Write output to `./plans/audit-[timestamp].hardener.md` (soon `.security.md`)

The plan's Step 5 synthesis reads the security artifact and aggregates findings by severity (Critical/High/Medium/Low counts). If the `security-analyst.md` agent follows its own output format (STRIDE tables, risk assessment matrix with Likelihood/Impact/Risk Score/Priority columns), the Step 5 coordinator must parse a significantly different structure than what the current hardener produces.

**Risk assessment:** The plan addresses this implicitly — it instructs the Task subagent to follow the scope-specific prompts (which mandate the Critical/High/Medium/Low format). However, the `security-analyst.md` agent file's own output format section takes precedence for an agent invoked via `Task` with `subagent_type=general-purpose`. The model may default to the agent's prescribed format.

**Recommendation:** The Step 2 prompt (in SKILL.md) should explicitly override the output format for audit context: instruct the Task subagent to use the audit's severity rating convention (Critical/High/Medium/Low counts) rather than the STRIDE table format. A single explicit instruction such as "Output format: rate each finding as Critical / High / Medium / Low, not as a STRIDE table" would prevent synthesis ambiguity. Alternatively, update Step 5 synthesis to handle both formats. This is the only concern that could affect functional correctness.

---

### Info

#### 6. Fallback Task subagent uses `model=claude-opus-4-6` but Step 3 uses `model=claude-sonnet-4-5`

**Finding:** The plan proposes Step 2 (security scan) use `model=claude-opus-4-6` for both the primary and fallback Task invocations. Step 3 (performance scan) currently uses `claude-sonnet-4-5`. This is intentional and consistent with the current SKILL.md, where the MCP `agent_hardener` implicitly uses whatever model the MCP server defaults to. Using opus-4-6 for Step 2 is a defensible choice for security-critical scanning. No issue.

#### 7. `gen-agent` suggestion in the pre-check message is not validated against actual generator capability

**Finding:** The plan's pre-check messaging suggests:
```
gen-agent . --type security-analyst
```
The `generate_agents.py` generator exists and the `security-analyst.md.template` is present in `templates/agents/`. This suggestion is valid. No issue.

#### 8. Acceptance criteria item 4 uses glob pattern `security-analyst*.md` (wildcard) but agent file is exactly `security-analyst.md`

**Finding:** Acceptance criterion 4 and the plan's pre-check glob use pattern `.claude/agents/security-analyst*.md`. The actual agent file is `security-analyst.md` (no suffix after the name). The wildcard (`*`) accommodates future variants (e.g., `security-analyst-v2.md`) and matches the current file. This is a deliberate defensive pattern consistent with how `/audit` Step 4 handles the QA agent (`qa-engineer*.md` or `qa*.md`). No issue.

#### 9. Semver jump from 2.0.1 to 3.0.0 skips minor versions

**Finding:** The plan justifies the major version bump as a breaking change. The precedent from `/dream` (2.3.0 → 3.0.0) supports this. No issue.

#### 10. Test plan does not include negative-path testing (projects without security-analyst.md)

**Finding:** Phase 3 integration test only covers the happy path (claude-devkit project, which has `security-analyst.md`). There is no explicit integration test for the fallback path (a project without `.claude/agents/security-analyst.md`). This is acceptable for a plan-level test; a full end-to-end test in a bare project would exceed reasonable scope. The unit-level grep checks (acceptance criteria 1–10) cover the code path mechanically.

---

## Summary Table

| # | Severity | Concern | Action Required |
|---|----------|---------|-----------------|
| 1 | Minor | `dream/SKILL.md` exclusion glob uses `.hardener.md` — will not exclude renamed `.security.md` | Add `skills/dream/SKILL.md` to task breakdown; update glob exclusion |
| 2 | Minor | `CLAUDE.md` has two additional `.hardener.md` references not in the edit list | Add both locations to CLAUDE.md edit list |
| 3 | Info | `README.md` has no `.hardener.md` references — no action needed | None |
| 4 | Minor | `templates/skill-scan.md.template` cites hardener as an example — explicitly out of scope | Track as follow-up after plan ships |
| 5 | Minor | `security-analyst.md` has a prescribed STRIDE output format that differs from audit's Critical/High/Medium/Low severity format; synthesis may need to handle both | Add explicit output format override to Step 2 prompt or update Step 5 to handle STRIDE table output |
| 6 | Info | Model choice (opus-4-6 for Step 2) is intentional and consistent | None |
| 7 | Info | `gen-agent` suggestion is valid | None |
| 8 | Info | Wildcard glob pattern is defensive and correct | None |
| 9 | Info | Semver 2.0.1 → 3.0.0 is justified by precedent | None |
| 10 | Info | No negative-path integration test; acceptable scope | None |

---

## Recommended Adjustments Before Implementation

1. **Add `skills/dream/SKILL.md` to the task breakdown.** In Step 1 of that skill, replace `*.hardener.md` with `*.security.md` in the glob exclusion list. This is a one-line change that prevents audit security artifacts from appearing as plan candidates.

2. **Add two additional CLAUDE.md edits to the edit list:** the artifact reference in the Workflow 2 example (line 272) and the Artifact Locations directory tree entry (line 546). Both should change `.hardener.md` to `.security.md`.

3. **Add explicit output format instruction to Step 2 prompt.** When the Task subagent is instructed to use `security-analyst.md` for role context, add a line such as: "Output format: rate each finding individually as Critical / High / Medium / Low using the audit severity convention. Do not use STRIDE table format for the main findings." This prevents the agent's own prescribed output template from overriding the audit's synthesis-compatible format.

Concerns 1 and 2 are omissions in the task breakdown — they do not change the design, they only add missing files to the edit list. Concern 5 is the only concern that touches execution logic and could affect correctness of the Step 5 synthesis.

None of these adjustments require design changes. The overall approach is sound.
