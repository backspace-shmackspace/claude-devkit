# Code Review: Threat Model Consumption

**Plan:** `./plans/threat-model-consumption.md`
**Date:** 2026-04-08
**Reviewer:** code-reviewer agent (following code-reviewer.md standards)
**Files reviewed:**
- `skills/ship/SKILL.md` (v3.7.0)
- `skills/architect/SKILL.md` (v3.3.0)
- `skills/secure-review/SKILL.md` (v1.1.0)
- `CLAUDE.md`
- `scripts/test-integration.sh`

---

## Verdict: PASS

No Critical or Major findings. All plan requirements are implemented. Known coder patterns verified clean.

---

## Critical Findings

None.

---

## Major Findings

None.

---

## Minor Findings

### M1 — `/ship` Step 5b revision loop does not explicitly re-run `/secure-review` with threat model context

**Location:** `skills/ship/SKILL.md`, Step 5b

**Observation:** Step 5b reads:

> "Re-run Step 4 in its entirety (all three parallel checks: code review + tests + QA)."

This text was not updated to explicitly enumerate `/secure-review` as the fourth parallel check alongside "code review + tests + QA." A future editor may interpret "in its entirety" as the original three checks rather than four. The plan itself identified this as a known coder pattern: "Revision loop prose omits re-running newly added parallel check" (learnings.md, 2026-03-27).

**Note on severity:** The behavior is technically not broken — "in its entirety" plausibly covers secure-review — but the ambiguity is exactly the pattern flagged in learnings as a recurring maintenance trap. This is Minor because the correct intent is recoverable, but it is the most impactful minor issue in this change.

**Recommended fix:** Update Step 5b to explicitly name secure-review:

> "Re-run Step 4 in its entirety (all four parallel checks: code review + tests + QA + secure-review, the last conditional on skill deployment)."

---

### M2 — `/architect` commit message contains stale version reference in Step 5 auto-commit

**Location:** `skills/architect/SKILL.md`, Step 5 auto-commit block

The commit message template still reads `v3.0.0`:

```bash
Plan approved by /architect v3.0.0 with all review gates passed.
```

The skill is now at v3.3.0. This is a cosmetic inconsistency but ships into every auto-commit message for every plan approved after this change.

**Recommended fix:** Update to `v3.3.0` in the commit message template.

---

### M3 — `test-integration.sh` test numbering skips Test 5 and Test 9 is out-of-order

**Location:** `scripts/test-integration.sh`

Tests are numbered 1, 2, 3, 4, 6, 7, 8, 10–19, 9. Test 5 does not exist and Test 9 (cleanup) is placed after Test 19 in source order. This is confusing to read but does not affect execution. The comment header says "18 tests" and TOTAL_COUNT increments correctly, so pass/fail counting is accurate.

The out-of-order numbering is a pre-existing pattern (Test 9 cleanup was always placed at the end in earlier versions) but this change added 10 new tests (10–19) that further widen the gap.

**Recommended fix:** Either renumber sequentially (1–19 with Tests 5 and 9 in correct source position) or add an explanatory comment clarifying that Test 5 was intentionally removed and Test 9 is a run-order exception.

---

### M4 — Security maturity levels section in CLAUDE.md not updated with Step 1 threat model check behavior

**Location:** `CLAUDE.md`, Security Maturity Levels section

The plan's Task Breakdown Step 19 states:

> "Update the Security Maturity Levels section if needed (add note about Step 1 threat model check behavior at each level)"

The Security Maturity Levels section (around line 128–165) was not updated to describe the new Step 1 behavior (warns at L1, blocks at L2/L3 when a security-sensitive plan lacks `## Security Requirements`). The Security Gates subsection documents the three existing gates but does not mention this fourth gate-like check.

This omission means the Security Maturity Levels section is technically correct but incomplete — a user reading only that section won't know that Step 1 enforces threat model presence at L2/L3. The ship v3.7.0 description in the skill registry partially covers this ("Step 1 checks for threat model output and blocks if required gates are unmet") but the Security Gates and Override sections have no mention of it.

**Recommended fix:** Add a note to the Security Gates subsection:

> "4. **Threat model presence** (Step 1 plan validation): When a security-sensitive plan (detected via keyword heuristic) lacks a `## Security Requirements` section, /ship warns at L1 and blocks at L2/L3. Override available with `--security-override`."

---

## Positives

### Plan requirements fully implemented

All five gaps (G1–G5) are addressed:

- **G1:** `/ship` Step 1 now checks for `## Security Requirements` presence on security-sensitive plans and enforces maturity-level behavior (warn at L1, block at L2/L3). Implementation matches the plan's decision matrix exactly.

- **G2:** `/ship` Step 4d conditionally enriches the `/secure-review` Task prompt with extracted threat model content using `THREAT MODEL CONTEXT:` block. The fallback to the unchanged prompt when no threat model is present is clean and correct. Interface to `/secure-review` is preserved (no new `## Inputs` parameters).

- **G3:** `/architect` Step 3 correctly upgrades from "Recommended" to "Required (when threat-model-gate is deployed and plan is security-sensitive)" with a well-designed fallback to generic Task subagent when `.claude/agents/security-analyst.md` is not found. The three conditions for "Required" are explicitly stated.

- **G4:** `/ship` Step 7 retro capture now includes threat-model-gap pattern detection, reading the archived secure-review artifact for `## Threat Model Coverage` section, rating `NOT_IMPLEMENTED` threats as High, and routing reverse gaps (High findings not in plan) as Medium. The note clarifying that the secure-review artifact is read from the archive (because Step 6 moves it there before Step 7 runs) is exactly the kind of defensive documentation that prevents future confusion.

- **G5:** `/architect` Step 2 Stage 2 plan content scan is well-implemented. The placement logic (Stage 2 fires only when Stage 1 did not), the bounded re-invocation (max 1 additional call), and the Edit-tool-based insertion approach (surgical, not full rewrite) match the plan exactly.

### Backward compatibility preserved

Plans without `## Security Requirements` sections ship at L1 without any warning (if the plan lacks security signals in content). The conditional in Step 1 correctly handles all three branches: section found, section missing but signals found, section missing and no signals.

### Audit event extended correctly

The `security_requirements_present` boolean field was added to the Step 1 `step_end` audit event emission. This follows the existing event extension pattern from `ship-audit-logging-gaps` and is emitted before the state file is deleted (correct event ordering — no recurrence of the previously documented event-after-deletion bug).

### `secure-review` interface preserved

The `## Inputs` section is unchanged. The `## Threat Model Coverage` section is conditional on invocation context, correctly scoped to Step 2 synthesis, and explicitly marked as informational (does not change verdict logic). Standalone `/secure-review` invocations are unaffected.

### Integration tests are complete and well-designed

All 10 structural integration tests (Tests 10–19) are present and correctly match the plan's specified grep patterns. The test for the removed `SECURITY CONTEXT:` marker (Test 19) is a good regression guard. The tests are grep-based and structurally correct — they verify content presence without requiring a live Claude session.

### Learnings check

Verified the following known coder patterns from `.claude/learnings.md ## Coder Patterns > ### Missed by coders, caught by reviewers`:

- **Stale internal step cross-references** [Low, 2026-03-26]: Not present. Step references in the revision loop are consistent.
- **Script returns false success when inputs are absent** [Low, 2026-03-27]: Not applicable to SKILL.md changes; `test-integration.sh` already guards correctly.
- **Settings precedence tests outcome rather than source** [Minor, 2026-03-27]: Not present. Step 0 still uses `LOCAL_SET=1` flag pattern correctly (unchanged).
- **Revision loop prose omits re-running newly added parallel check** [Minor, 2026-03-27]: Present as Minor finding M1 above. Step 5b does not enumerate secure-review explicitly.
- **Conditional branching uses implicit else** [Minor, 2026-03-27]: Not present in new code. All conditional branches in Step 1 and Step 3a use explicit if/else framing.
- **`rm -rf` without `|| true` under `set -e`** [Major, 2026-03-27]: Not present. No new `rm -rf` calls introduced by this change.
- **Variable assigned inside test block, depended on by later tests** [Low, 2026-03-27]: Not present. No new cross-test dependencies introduced in test-integration.sh.
- **Plan-specified instrumentation points partially skipped** [Medium, 2026-03-28]: Not present. The `security_requirements_present` field in the Step 1 `step_end` event is implemented. No other new instrumentation points were specified.
- **Event emitted after resource it depends on has been deleted** [Low, 2026-03-28]: Not present. All new audit emit calls in Steps 1 and 7 are placed before state file cleanup.

Verified the `## Reviewer Patterns > ### Overcorrected` section:

- **Self-refuted cosmetic observations**: The minor findings above (M1–M4) are all actionable — none are pre-emptively dismissed as cosmetic. M2 (stale version string) and M3 (test numbering) are genuinely low-stakes but not self-refuted.

---

## Recommendations

1. **(Optional, Minor)** Update Step 5b prose to explicitly name secure-review as the fourth parallel check (M1). This closes a known pattern from learnings and costs one line of text.
2. **(Optional, Minor)** Fix the stale `v3.0.0` version string in the `/architect` Step 5 auto-commit message template (M2).
3. **(Optional, Minor)** Update the CLAUDE.md Security Gates subsection to document the new Step 1 threat model presence check and its maturity-level behavior (M4). This is the highest-value documentation gap given the behavioral impact of the L2/L3 block.
4. **(Optional, Cosmetic)** Add a comment to test-integration.sh explaining the Test 5 gap and Test 9 ordering exception (M3).
