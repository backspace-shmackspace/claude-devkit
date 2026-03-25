# Feasibility Re-Review: Task Model Fix + Context Preservation (Revised Plan)

**Reviewer:** Code Reviewer Specialist
**Date:** 2026-02-23
**Plan:** `./plans/task-model-fix-context-preservation.md` (revised)
**Previous verdict:** FAIL (1 Critical, 5 Major)

---

## Verdict: PASS

The revised plan resolves all Critical and Major findings from the prior review. All OLD text blocks have been verified against the actual source files. The plan is implementable as written.

---

## Resolved Concerns

### C1: Step numbering now uses integer-only format matching validator regex -- RESOLVED

The validator at `/Users/imurphy/projects/claude-devkit/generators/validate_skill.py` line 137 uses the regex:

```python
step_pattern = r'^## Step (\d+)( —|--) (.+)$'
```

This regex matches `\d+` (one or more digits only). The revised plan correctly eliminates the previously proposed `Step 0.5` and `Step 1b` headers and instead renumbers all steps sequentially:

- Dream: Steps 0, 1, 2, 3, 4, 5 (6 total, up from 5)
- Ship: Steps 0, 1, 2, 3, 4, 5, 6 (7 total, up from 6)

The plan explicitly states the constraint on line 36: "All step headers must use integer-only step numbers." The validation commands in sections 2.7 and 3.3 include negative checks for `Step 0.5` and `Step 1b` patterns. The acceptance criteria on lines 1270 and 1279 both reiterate integer-only requirements. The changes-from-previous-version table on line 1345 explicitly traces the resolution of the original CRITICAL finding.

### M1: CLAUDE.md version drift acknowledged and handled -- RESOLVED

The plan explicitly documents the pre-existing drift on line 28:

> Pre-existing registry drift: CLAUDE.md shows dream version as `2.0.0`, but `skills/dream/SKILL.md` frontmatter is already `2.1.0`.

Verified against actuals:
- `CLAUDE.md` line 70 shows dream at version `2.0.0` -- confirmed, matches the OLD block on plan line 1054
- `skills/dream/SKILL.md` line 5 shows `version: 2.1.0` -- confirmed, drift exists

The plan accounts for this by jumping the registry from `2.0.0` to `2.2.0` in the NEW block (line 1063), matching the planned frontmatter bump from `2.1.0` to `2.2.0`. The Phase 4 OLD text block on lines 1054-1058 matches the actual content of `CLAUDE.md` lines 70-74 exactly.

### M2: Sync skill model reference corrected -- RESOLVED

The plan documents the discrepancy on line 28:

> CLAUDE.md also shows `opus-4-6` for the sync skill model, but `skills/sync/SKILL.md` uses `claude-sonnet-4-5`.

Verified against actuals:
- `CLAUDE.md` line 73 shows sync with model `opus-4-6` -- confirmed
- `skills/sync/SKILL.md` line 5 shows `model: claude-sonnet-4-5` -- confirmed, drift exists

The Phase 4 NEW block on line 1066 corrects the registry to show `sonnet-4-5` for sync. The change is explicitly called out in the changelog on line 1074 and the acceptance criteria on line 1287.

### M3: --fast flag interaction specified -- RESOLVED

The plan adds explicit documentation of the `--fast` flag behavior with context discovery at multiple locations:

- Plan line 57: Trade-offs table entry explaining the decision to always run context discovery
- Plan line 130: "Context discovery runs regardless of the `--fast` flag. The `--fast` flag only affects Step 3 (skipping the red team review)."
- Plan line 563 (inside the new Step 1 text): "This step runs regardless of the `--fast` flag."
- Plan line 1269: Acceptance criterion: "Context discovery runs regardless of `--fast` flag (explicitly documented in Step 1)"
- Plan lines 1129-1131: Integration smoke test for `--fast` that verifies context discovery runs and red team is skipped

The interaction is clearly specified and testable.

### M5: Nested code fence issue resolved -- RESOLVED

The plan replaces triple-backtick code fences with `---begin/end---` delimiters for content that would be embedded inside SKILL.md:

- Plan line 579: `---begin context block format---` / `---end context block format---`
- Plan line 653: `---begin metadata format---` / `---end metadata format---`
- Plan line 602: Implementation note explicitly warns: "The implementer should use these delimiters literally in the SKILL.md, not convert them to code fences."
- Plan line 673: Second implementation note reinforces the same guidance for the metadata format.
- Risk assessment on line 1300: Explicitly calls out this mitigation.

This prevents the triple-backtick nesting problem that would corrupt the SKILL.md markdown structure.

---

## Remaining Concerns

None from the prior review. All 1 Critical and 5 Major concerns from the previous FAIL verdict have been addressed.

The plan also explicitly documents three accepted limitations (lines 1358-1360) from prior reviews that were intentionally not addressed:
- Glob exclusion pattern fragility (accepted as known limitation)
- Plan similarity matching undefined (accepted as LLM best-effort)
- Pattern validation has no structured extraction (accepted as non-blocking warnings-only design)

These are reasonable design decisions documented with rationale.

---

## New Concerns

### Minor-1: OLD block line numbers may drift during multi-phase implementation

The plan references specific line numbers in source files (e.g., "Line 42", "Line 116" for dream; "Line 91", "Line 117" for ship). These line numbers are accurate against the current source files as verified below. However, when Phase 2 inserts new content into `skills/dream/SKILL.md`, the line numbers for other changes in that file will shift. Similarly for Phase 3 in `skills/ship/SKILL.md`.

**Verification performed (all 15 model alias locations confirmed):**

| File | Plan Line # | Actual Line # | Content Match |
|------|-------------|---------------|---------------|
| `skills/dream/SKILL.md` | 42 | 42 | `model=opus` -- exact match |
| `skills/dream/SKILL.md` | 116 | 116 | `model=opus` -- exact match |
| `skills/ship/SKILL.md` | 91 | 91 | `model=sonnet` -- exact match |
| `skills/ship/SKILL.md` | 117 | 117 | `model=sonnet` -- exact match |
| `skills/ship/SKILL.md` | 194 | 194 | `model=sonnet` -- exact match |
| `skills/ship/SKILL.md` | 371 | 371 | `model=sonnet` -- exact match |
| `skills/ship/SKILL.md` | 401 | 401 | `model=sonnet` -- exact match |
| `skills/ship/SKILL.md` | 463 | 463 | `model=sonnet` -- exact match |
| `skills/audit/SKILL.md` | 79 | 79 | `model=sonnet` -- exact match |
| `skills/audit/SKILL.md` | 144 | 144 | `model=sonnet` -- exact match |
| `skills/sync/SKILL.md` | 118 | 118 | `model=sonnet` -- exact match |
| `skills/test-idempotent/SKILL.md` | 54 | 54 | `model=sonnet` -- exact match |
| `skills/test-idempotent/SKILL.md` | 78 | 78 | `model=sonnet` -- exact match |
| `skills/test-idempotent/SKILL.md` | 105 | 105 | `model=sonnet` -- exact match |
| `skills/test-idempotent/SKILL.md` | 139 | 139 | `model=sonnet` -- exact match |

**Mitigation:** The plan orders Phase 1 (model alias replacement) before Phases 2 and 3 (step insertion/renumbering). Phase 1 uses find-and-replace on literal text strings (not line-number-based edits), so it will work correctly. Phases 2 and 3 use OLD/NEW text blocks for step header renaming and insertion, which are content-addressed rather than line-addressed. The line numbers in the plan are informational context for the implementer, not execution targets.

**Severity:** Minor (informational). No action required.

### Minor-2: Sub-step headers use inconsistent markdown heading levels

The dream skill uses `### 2a` (h3) for sub-steps while the ship skill uses `#### Step 2a` (h4) with the `Step` prefix. The plan preserves this inconsistency in the renumbered headers (dream sub-steps become `### 3a`, `### 3b`, `### 3c`; ship sub-steps become `#### Step 3a`, `#### Step 3b`, etc.). This is a pre-existing style difference, not introduced by this plan.

**Severity:** Minor (cosmetic, pre-existing). No action required.

### Minor-3: Ship internal cross-reference completeness

The plan lists many internal cross-references to update in section 3.1 (lines 853-941). A careful reading of the actual `skills/ship/SKILL.md` confirms the plan captures the key cross-references:

- Line 107: "Skip to Step 3" -- plan addresses (becomes "Skip to Step 4")
- Line 304: "do not proceed to Step 2e" -- plan addresses (becomes "Step 3e")
- Line 306: "continue to Step 2e" -- plan addresses (becomes "Step 3e")
- Line 424: "Proceed to Step 5 (commit)" -- plan addresses (becomes "Step 6")
- Line 425: "Enter Step 4 (revision loop)" -- plan addresses (becomes "Step 5")
- Line 437: "Step 3 code review" -- plan addresses (becomes "Step 4")
- Line 439: "Step 3 all checks PASS: skip to Step 5" -- plan addresses (becomes "Step 4 ... Step 6")
- Line 472: "Re-run Step 3 in its entirety" -- plan addresses (becomes "Step 4")
- Line 489: "Step 2a" -- plan addresses (becomes "Step 3a")

The coverage appears comprehensive. As a safety net, the implementer should run `grep -n 'Step [2345]' skills/ship/SKILL.md` after applying changes to catch any missed references. The plan's validation section (3.3) already includes validator checks that would flag sequential numbering issues.

**Severity:** Minor (implementation hygiene).

---

## OLD Text Block Verification Summary

All critical OLD text blocks in the plan were verified against the actual source files:

| Source File | Plan Section | Content Verified | Match |
|-------------|-------------|------------------|-------|
| `skills/dream/SKILL.md` line 38 | Section 2.1, line 462 | `## Step 1 -- Architect drafts plan` | Exact |
| `skills/dream/SKILL.md` line 42 | Section 1.1, line 176 | `model=opus` tool declaration | Exact |
| `skills/dream/SKILL.md` line 61 | Section 2.1, line 474 | `## Step 2 -- Red Team...` | Exact |
| `skills/dream/SKILL.md` lines 67, 77, 90 | Section 2.1, lines 486-488 | Sub-step headers `2a`, `2b`, `2c` | Exact |
| `skills/dream/SKILL.md` lines 77-88 | Section 2.4, lines 682-694 | Librarian section full text | Exact |
| `skills/dream/SKILL.md` line 108 | Section 2.1, line 502 | `## Step 3 -- Revision loop` | Exact |
| `skills/dream/SKILL.md` line 112 | Section 2.1, line 514 | `skip to Step 4` | Exact |
| `skills/dream/SKILL.md` line 116 | Section 1.1, line 188 | `model=opus` tool declaration | Exact |
| `skills/dream/SKILL.md` lines 116-125 | Section 2.5, lines 727-736 | Revision prompt full text | Exact |
| `skills/dream/SKILL.md` line 127 | Section 2.1, line 524 | `re-run Step 2` | Exact |
| `skills/dream/SKILL.md` line 129 | Section 2.1, line 534 | `proceed to Step 4` | Exact |
| `skills/dream/SKILL.md` line 131 | Section 2.1, line 546 | `## Step 4 -- Final verdict gate` | Exact |
| `skills/dream/SKILL.md` lines 44-59 | Section 2.3, lines 610-626 | Architect prompt full text | Exact |
| `skills/ship/SKILL.md` lines 83-85 | Section 3.2, lines 948-950 | Transition text to Step 2 | Exact |
| `skills/ship/SKILL.md` line 85 | Section 3.1, line 822 | `## Step 2 -- Implementation` | Exact |
| `skills/ship/SKILL.md` lines 113-145 | Section 3.1, lines 835-841 | Sub-step headers `2a`-`2f` | Exact |
| `skills/ship/SKILL.md` line 363 | Section 3.1, line 869 | `## Step 3 -- Parallel verification` | Exact |
| `skills/ship/SKILL.md` lines 369, 390, 399 | Section 3.1, lines 881-883 | Sub-step headers `3a`-`3c` | Exact |
| `skills/ship/SKILL.md` line 435 | Section 3.1, line 899 | `## Step 4 -- Revision loop` | Exact |
| `skills/ship/SKILL.md` lines 441, 470 | Section 3.1, lines 911-912 | Sub-step headers `4a`-`4b` | Exact |
| `skills/ship/SKILL.md` line 483 | Section 3.1, line 931 | `## Step 5 -- Commit gate` | Exact |
| `CLAUDE.md` lines 70-74 | Section 4.1, lines 1054-1058 | Registry table (all 5 rows) | Exact |

---

## Conclusion

The revised plan is a thorough, well-structured implementation plan that addresses all previously raised concerns:

| Prior Finding | Severity | Resolution Status |
|---------------|----------|-------------------|
| C1: Validator rejects non-integer step headers | Critical | Resolved -- sequential integer renumbering |
| M1: CLAUDE.md version drift for dream | Major | Resolved -- drift acknowledged, version corrected |
| M2: Sync model misrepresented in registry | Major | Resolved -- registry corrected to `sonnet-4-5` |
| M3: `--fast` interaction unspecified | Major | Resolved -- explicitly documented |
| M5: Nested code fence corruption risk | Major | Resolved -- `---begin/end---` delimiters used |

Three new minor concerns were noted (line number drift, heading level inconsistency, cross-reference completeness), none of which affect implementability. All 15 model alias locations and all OLD text blocks have been verified against the current source files. The plan is ready for implementation.

---

**Files reviewed:**
- `/Users/imurphy/projects/claude-devkit/plans/task-model-fix-context-preservation.md`
- `/Users/imurphy/projects/claude-devkit/skills/dream/SKILL.md`
- `/Users/imurphy/projects/claude-devkit/skills/ship/SKILL.md`
- `/Users/imurphy/projects/claude-devkit/skills/audit/SKILL.md`
- `/Users/imurphy/projects/claude-devkit/skills/sync/SKILL.md`
- `/Users/imurphy/projects/claude-devkit/skills/test-idempotent/SKILL.md`
- `/Users/imurphy/projects/claude-devkit/CLAUDE.md`
- `/Users/imurphy/projects/claude-devkit/generators/validate_skill.py`
