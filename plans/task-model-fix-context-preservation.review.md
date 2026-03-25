# Librarian Re-Review: Task Model Fix + Context Preservation (Revised Plan)

**Plan:** `./plans/task-model-fix-context-preservation.md`
**Reviewed against:** `./CLAUDE.md` (project rules, v1.0.0)
**Date:** 2026-02-23
**Prior verdict:** FAIL (2 blocking conflicts: step numbering, CLAUDE.md version drift)
**Review type:** Re-review of revised plan

---

## Verdict: PASS

All original blocking conflicts are resolved. No new blocking issues introduced.

---

## Resolved (2/2 original blocking conflicts fixed)

### 1. Step numbering -- RESOLVED

**Original finding:** The plan used `## Step 0.5` (dream) and `## Step 1b` (ship), both of which fail the skill validator regex `r'^## Step (\d+)( —|--) (.+)$'` (Pattern #2). These steps would be invisible to validation and break sequential numbering.

**Resolution in revised plan:**

- Dream steps are renumbered as sequential integers 0-5 (6 steps total). The new Context Discovery step is `## Step 1`, and former Steps 1-4 become Steps 2-5. (Plan sections 2.1, lines 435-552.)
- Ship steps are renumbered as sequential integers 0-6 (7 steps total). The new Pattern Validation step is `## Step 2`, and former Steps 2-5 become Steps 3-6. All sub-step headers (2a-2f to 3a-3f, 3a-3c to 4a-4c, 4a-4b to 5a-5b) are updated. (Plan section 3.1, lines 809-941.)
- The constraint is documented in the Constraints section (line 36): "All step headers must use integer-only step numbers."
- The Trade-offs table includes the numbering decision (line 56).
- Exhaustive internal cross-reference update lists are provided for both skills, covering step-to-step jumps, sub-step references, and version strings in WIP commit messages.
- Validation commands explicitly check for absence of `Step 0.5` and `Step 1b` (lines 772-773, 1018-1019, 1197-1199) and verify all integer steps exist.

This is thoroughly resolved.

### 2. CLAUDE.md version drift -- RESOLVED

**Original finding:** Phase 4 OLD block showed dream at `2.0.0`, but `skills/dream/SKILL.md` frontmatter was already `2.1.0`. The plan did not acknowledge this pre-existing inconsistency.

**Resolution in revised plan:**

- Pre-existing drift is explicitly documented in the Current State section (line 28): "CLAUDE.md shows dream version as `2.0.0`, but `skills/dream/SKILL.md` frontmatter is already `2.1.0`. CLAUDE.md also shows `opus-4-6` for the sync skill model, but `skills/sync/SKILL.md` uses `claude-sonnet-4-5`."
- Phase 4 includes a dedicated explanatory note (line 1048) about correcting pre-existing inconsistencies.
- Phase 4 OLD block (lines 1052-1058) matches the **actual current CLAUDE.md content** (verified: dream `2.0.0`, ship `3.1.0`, audit `2.0.0`, sync `2.0.0` with `opus-4-6` model, test-idempotent `1.0.0`). This is correct -- the OLD block should show what CLAUDE.md currently says, not what the skill files say.
- Phase 4 NEW block (lines 1062-1068) shows dream at `2.2.0` (skipping past the stale `2.0.0` in the registry, acknowledging the actual `2.1.0` in the skill file, and adding the `2.2.0` feature bump).
- Phase 4 NEW block corrects sync model from `opus-4-6` to `sonnet-4-5`.
- The change summary (lines 1070-1075) explains each delta.

I independently verified the pre-existing drift claims by reading the actual skill frontmatter:
- `skills/dream/SKILL.md`: `version: 2.1.0` (CLAUDE.md says `2.0.0` -- confirmed stale)
- `skills/sync/SKILL.md`: `model: claude-sonnet-4-5` (CLAUDE.md says `opus-4-6` -- confirmed inaccurate)

This is thoroughly resolved.

---

## Previously Non-Blocking Issues (status)

| Issue | Prior Status | Revised Plan Status |
|-------|-------------|---------------------|
| Dream step count in registry (was wrong) | Non-blocking | Fixed: Phase 4 NEW shows `6` for dream (line 1063) |
| `--fast` flag interaction unspecified | Non-blocking (from Red Team) | Fixed: Explicitly documented at line 130 and Step 1 (line 563) |
| `claude_md_hash` requires SHA256 LLMs cannot compute | Non-blocking (from Red Team) | Fixed: Replaced with `claude_md_exists: [true or false]` (line 675) |
| Nested code fence risk | Non-blocking (from Feasibility) | Fixed: Uses `---begin/end---` delimiters with implementation notes (lines 602, 673) |
| Integration smoke test lacked expected outputs | Non-blocking (from Red Team) | Fixed: Expected output snippets added (lines 1119-1131) |
| Deploy path used `~/workspaces/` instead of actual path | Non-blocking (from Red Team) | Fixed: Phase 5 uses `/Users/imurphy/projects/claude-devkit` (line 1108) |

All addressed.

---

## Remaining (0 blocking issues)

None. Both original blocking conflicts are fully resolved.

---

## New Issues

### Non-blocking: Pattern count header mismatch in CLAUDE.md (pre-existing)

CLAUDE.md line 305 states "All skills follow these 10 patterns:" but the table below lists 11 patterns (1 through 11, including Worktree isolation at #11). This is a **pre-existing inconsistency** in CLAUDE.md, not introduced by this plan. The plan does not modify this section.

**Recommendation:** Address in a separate `/sync` pass. Does not block this plan.

### Non-blocking: Worktree Isolation example structure in CLAUDE.md uses old step numbering

The Worktree Isolation Pattern example in CLAUDE.md (lines 448-466) shows `## Step 2a` through `## Step 2f`. After ship renumbering, the actual skill will use Step 3a-3f. However, the CLAUDE.md examples are generic archetype illustrations, not live references to specific skill versions, so they remain valid as-is.

**Recommendation:** No action needed. The examples are archetype templates, not live references.

---

## Required Edits

None. The plan is ready for implementation.

---

## Pattern Compliance Checklist (Updated)

| # | Pattern | Compliance | Notes |
|---|---------|-----------|-------|
| 1 | Coordinator | PASS | New steps use coordinator-does-this-directly pattern (Glob, Read) |
| 2 | Numbered steps | **PASS** | All steps use integer-only `## Step N` format (previously FAIL) |
| 3 | Tool declarations | PASS | Both new steps declare tools (Glob/Read for dream, Read for ship) |
| 4 | Verdict gates | PASS | Pattern validation is non-blocking (warnings only); context discovery is non-blocking |
| 5 | Timestamped artifacts | PASS | Context metadata includes ISO timestamp |
| 6 | Structured reporting | PASS | Outputs go to `./plans/` |
| 7 | Bounded iterations | PASS | No new iteration loops introduced |
| 8 | Model selection | PASS | All 15 aliases replaced with valid full IDs |
| 9 | Scope parameters | PASS | No changes to existing scope parameters |
| 10 | Archive on success | PASS | No changes to archive behavior |
| 11 | Worktree isolation | PASS | No changes to worktree logic (sub-step headers renumbered correctly) |

---

## Step Count Verification

| Skill | Current Steps (CLAUDE.md) | Current Steps (actual SKILL.md) | Post-change Steps | Plan Says | Match? |
|-------|---------------------------|--------------------------------|-------------------|-----------|--------|
| dream | 4 | 5 (Steps 0-4) | 6 (Steps 0-5) | 6 | Yes |
| ship | 6 | 6 (Steps 0-5) | 7 (Steps 0-6) | 7 | Yes |
| audit | 6 | 6 (Steps 0-5) | 6 (unchanged) | 6 | Yes |
| sync | 6 | 6 (Steps 0-5) | 6 (unchanged) | 6 | Yes |
| test-idempotent | 7 | 7 (Steps 0-6) | 7 (unchanged) | 7 | Yes |

All step counts are accurate.

---

## Version Transition Accuracy

| Skill | CLAUDE.md (current) | SKILL.md (current) | Plan target | Transition valid? |
|-------|--------------------|--------------------|-------------|-------------------|
| dream | 2.0.0 | 2.1.0 | 2.2.0 | Yes (minor bump from actual 2.1.0 for new feature) |
| ship | 3.1.0 | 3.1.0 | 3.2.0 | Yes (minor bump for new feature) |
| audit | 2.0.0 | 2.0.0 | 2.0.1 | Yes (patch for bugfix only) |
| sync | 2.0.0 | 2.0.0 | 2.0.1 | Yes (patch for bugfix only) |
| test-idempotent | 1.0.0 | 1.0.0 | 1.0.1 | Yes (patch for bugfix only) |

All version transitions follow semver correctly.

---

## Summary

The revised plan comprehensively addresses both original blocking conflicts. The "Changes From Previous Plan Version" table (lines 1339-1361) provides full traceability from each review finding to its resolution. The plan is well-structured, internally consistent, and fully compliant with CLAUDE.md project rules. No new blocking issues were introduced by the revision.

**Reviewed by:** Librarian Agent
**Review file:** `./plans/task-model-fix-context-preservation.review.md`
