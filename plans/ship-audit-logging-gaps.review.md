# Librarian Review: ship-audit-logging-gaps (Rev 2)

**Plan:** `plans/ship-audit-logging-gaps.md`
**Revision:** 2 (2026-03-28)
**Reviewer:** Librarian (context alignment review)
**Date:** 2026-03-28
**Checked against:** `CLAUDE.md`, parent plan `ship-run-audit-logging.md`, archived QA report and code review, current source files, red team review, feasibility review

---

## Verdict: PASS

The revised plan addresses all required edits from the previous review and all Critical/Major findings from the red team review. No conflicts with CLAUDE.md rules or prior approved plans. No new required edits.

---

## Previous Edits Status

### Required Edit 1: Line number references replaced with section-relative anchors

**Status: ADDRESSED.**

The previous review flagged specific line number references (1185-1188, 1203-1206, 1288-1291) that could mislead the coder. The revised plan replaces these with section-relative anchors throughout:

- Section 2: "After the 'Result evaluation' section (after the L1/L2 result matrix and the stop/continue decision prose, before the 'If stopping' output paragraph)"
- Section 3: "Before the '### 5a -- Coder fixes' header (inside the Step 5 conditional section, after the trigger paragraph)"
- Section 4: "After the commit gate verdict evaluation" with structural descriptions
- Detailed Change List: Uses "Insert after the Result evaluation section" and similar anchors

The only remaining specific line reference is line 124 of `emit-audit-event.sh` for the `wc -l` bug. This is accurate (verified against the current file) and refers to the helper script, not the SKILL.md, so it is appropriate.

### Required Edit 2: Goals section aligned with Proposed Design

**Status: ADDRESSED (design also changed).**

The previous review flagged that the Goals section implied per-substep boundary events for Steps 4a-4d, while the Proposed Design used a single `step_4_verification` wrapper. The revision resolves this by changing both:

- Goals (line 30) now reads: "retrospective per-substep step_start/step_end markers emitted during the coordinator's sequential result evaluation (after parallel Tasks complete), plus verdict events for code review, tests, QA, and a security_decision event for secure review"
- Proposed Design section 2 (lines 82-150) now emits per-substep pairs (`step_4a_code_review`, `step_4b_tests`, `step_4c_qa`, `step_4d_secure_review`) during result evaluation, matching the parent plan's per-substep identifiers
- Deviations table (line 632) documents the retrospective timing caveat

The Goals and Design are now consistent with each other and with the parent plan's instrumentation table.

---

## Red Team Findings Status

| Finding | Severity | Status | Notes |
|---------|----------|--------|-------|
| F1 (Step 4 per-substep deviation) | Critical | **ADDRESSED** | Design changed to emit retrospective per-substep markers preserving parent plan identifiers. Deviation documented with justification in Deviations table. |
| F2 (FAIL path state file) | Major | **ADDRESSED** | Section 4 restructures Step 6: finalization block wrapped under PASS-path conditional, dedicated FAIL-path bash block with step_end + run_end + cleanup. |
| F3 (test output suppression) | Major | **ADDRESSED** | `run_test` modified to capture output to temp file and display first 20 lines on failure (lines 274-291). |
| F4 (test variable escaping) | Major | **ADDRESSED** | Tests rewritten to write python3 verification to temp script files via heredocs, eliminating triple-level escaping (lines 294-296). |
| F5 (Step 5 conditional emit calls) | Major | **ADDRESSED** | Explicit conditional language added: "MUST NOT execute if Step 5 is skipped" (line 155), plus matching language in Step 5 step_end (line 177). |
| F6 (missing run_end on early exits) | Minor | Acknowledged in Non-Goals (out of scope for this plan) | Acceptable scope boundary. |
| F7 (stale commit_sha) | Minor | Not addressed | Pre-existing limitation documented in schema. Not in scope. |
| F8 (wc -l fix edge case) | Minor | Not addressed | Permission errors on just-created files are unlikely. The conditional fix is standard practice. |
| F9 (minimum event count threshold) | Minor | Not addressed | Noted as known gap. Acceptable for a gap-fill plan. |
| F10 (no version bump ambiguity) | Info | Documented in Deviations table | Justification is reasonable. |
| F11 (rollout ordering) | Info | Informational only | Ships as single commit. |
| F12 (HMAC test key ordering) | Info | **ADDRESSED** | Comment added to Test H (lines 413-415) noting the ordering assumption. |

### Feasibility Review M1 (HMAC key ordering comment)

**Status: ADDRESSED.** Test H includes the recommended comment (lines 413-415): "NOTE: This test assumes json.dumps preserves insertion order (CPython 3.7+). If emit-audit-event.sh changes its JSON serialization order, this test will fail with an HMAC mismatch -- not a chain corruption bug."

---

## Conflicts with CLAUDE.md Rules

None found. The plan operates within established patterns:

- **"Edit source, not deployment"** -- Plan modifies `skills/ship/SKILL.md` (source), not `~/.claude/skills/ship/SKILL.md`. Compliant.
- **"Validate before committing"** -- Test plan includes `validate-all.sh` and the full test suite. Compliant.
- **"Follow v2.0.0 patterns"** -- No new steps added. Emit calls are additive instrumentation within existing numbered steps. Compliant.
- **"One skill per directory"** -- No new skills created. Compliant.
- **Numbered steps pattern** -- Plan preserves existing step numbering. Emit calls map 1:1 to existing steps (Steps 4, 5, 6, 7). Compliant.
- **Verdict gates pattern** -- Verdict events capture values at existing gates. No new verdicts introduced. Compliant.
- **Bounded iterations pattern** -- Step 5 emit calls respect the existing "Max 2 revision rounds" constraint. Compliant.
- **Worktree isolation pattern** -- No changes to worktree behavior. Compliant.
- **Timestamped artifacts** -- No new artifact types. Existing JSONL format unchanged. Compliant.
- **Archive on success** -- No changes to archival behavior. Compliant.

---

## Historical Alignment

### Context Alignment Section

Present and substantive. The plan documents:
- Five CLAUDE.md patterns followed (numbered steps, verdict gates, timestamped artifacts, bounded iterations, archive on success)
- Three prior plans referenced with relationship descriptions
- Two archived plans consulted with specific findings cited
- Three deviations with justifications (no version bump, state file cleanup relocation, retrospective timing markers)

### Context Metadata Block

Present at end of file. `claude_md_exists: true` correctly set. `review_artifacts_addressed` field lists the red team, librarian, and feasibility reviews. Accurate.

### Consistency with Parent Plan

The plan now faithfully implements the parent plan's instrumentation table (lines 504-507) using retrospective per-substep markers. The identifiers match: `step_4a_code_review`, `step_4b_tests`, `step_4c_qa`, `step_4d_secure_review`. The timing caveat (retrospective markers reflect evaluation order, not parallel execution timing) is clearly documented in both the Proposed Design (lines 83-85) and the Deviations table (line 632).

### Consistency with Prior Plans

- **No contradictions** with `ship-run-audit-logging.md` (APPROVED). The follow-up plan completes committed work.
- **No contradictions** with `devkit-hygiene-improvements.md` (APPROVED). Follows the test-first, validate-all pattern.
- **No contradictions** with `agentic-sdlc-next-phase.md` (APPROVED). Extends the integration test suite.

---

## Required Edits

None.

---

## Optional Suggestions

- **FAIL-path completeness.** The plan adds `step_end` and `run_end` emissions to the Step 6 FAIL path but does not add them to early-stop paths in Step 4 result evaluation (code review FAIL, tests fail, QA FAIL) or Step 0/1/3 failures. This is correctly scoped out by this plan, but if full audit trail coverage on all failure paths is a future goal, a separate follow-up plan tracking these gaps would be useful. The red team's F6 finding documents this gap.

- **EXPECTED_MIN threshold.** The red team's F9 noted that the Step 6 minimum event count threshold (`EXPECTED_MIN=5`) is too low after full instrumentation. With retrospective per-substep markers for Steps 4a-4d, a successful run reaching Step 6 will have 25+ events, making a threshold of 5 nearly meaningless for detecting regressions. Consider raising this in a future change.

- **Cleanup test conversion.** The plan renumbers the Cleanup test from Test 5 to Test 9 but preserves its inline structure (not using `run_test()`). Converting it to use `run_test` for consistency would be a small improvement, as noted in the previous review.

---

## Summary

The Rev 2 plan is well-revised. All required edits from the previous librarian review are addressed. All Critical and Major findings from the red team review are addressed, with clear design changes (retrospective per-substep markers, PASS-path conditional wrapping, temp-file test scripts, explicit conditional language). The feasibility review's M1 comment about HMAC key ordering is also addressed. No conflicts with CLAUDE.md rules or prior approved plans exist. The plan is ready for approval.
