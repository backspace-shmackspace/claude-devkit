# Code Review — security-guardrails-phase-b

**Reviewer:** code-reviewer-specialist (claude-devkit project)
**Date:** 2026-03-27
**Plan:** `plans/security-guardrails-phase-b.md` (Status: APPROVED, Rev 2)
**Files reviewed:**
- `skills/ship/SKILL.md` (target: v3.5.0)
- `skills/architect/SKILL.md` (target: v3.1.0)
- `skills/audit/SKILL.md` (target: v3.1.0)

---

## Verdict: PASS

No Critical or Major findings remain. All three skills implement the plan requirements correctly. The security gate architecture is sound and follows the plan's maturity-level-aware design. Minor findings below are optional improvements.

---

## Critical Findings

None.

---

## Major Findings

None.

---

## Minor Findings

### M1 — `/ship` Step 5b does not re-run secure-review in the revision loop

**File:** `skills/ship/SKILL.md`, Step 5b

**Observation:** Step 5b reads: "Re-run Step 4 in its entirety (all three parallel checks: code review + tests + QA)." The text still says "all three parallel checks" rather than "all three or four checks." At L2/L3, when secure-review BLOCKED triggers a revision loop (per the Step 4 L2/L3 matrix row: `REVISION_NEEDED + BLOCKED → Enter Step 5 loop`), Step 5b should re-run the secure-review alongside code review, tests, and QA so the post-revision evaluation matrix has a fresh secure-review verdict. The plan's result matrix and Step 4d both describe this re-run requirement, but Step 5b's prose does not explicitly include it. At L1 this is harmless (secure-review is non-blocking anyway). At L2/L3 the omission could produce a stale BLOCKED verdict from the first pass being used in the second-pass evaluation.

**Recommendation:** Update Step 5b to: "Re-run Step 4 in its entirety (all three or four parallel checks: code review + tests + QA + secure review if deployed)." This matches the existing Step 4d language about conditional secure-review dispatch.

**Severity:** Minor — the plan's intent is clear; Step 4d instructions already cover what to do. A reader executing Step 5b would likely re-run all checks. But the prose ambiguity could cause a future editor to exclude secure-review from revision-loop re-verification.

---

### M2 — `/ship` Step 0 security maturity check reads settings.json even when maturity was already overridden by local settings

**File:** `skills/ship/SKILL.md`, Step 0 (Security maturity level check)

**Observation:** The bash guard condition for falling back to project settings is:

```bash
if [ "$SECURITY_MATURITY" = "advisory" ] && [ -f ".claude/settings.json" ]; then
```

This means: if the local settings file explicitly sets `security_maturity` to `"advisory"`, the code will still read the project settings file and potentially override the local setting with whatever the project settings say. The intent is clearly "fall back to project settings only if local settings did not set anything." The correct condition should check whether the local file set any value, not whether the resulting value is "advisory." A user who intentionally downgrades to advisory via local settings can have that setting overridden by a project-level setting.

**Recommendation:** Track whether the local file provided a value using a separate flag:

```bash
LOCAL_SET=0
if [ -f ".claude/settings.local.json" ]; then
  LOCAL_MATURITY=$(python3 -c "..." 2>/dev/null || echo "")
  if [ -n "$LOCAL_MATURITY" ]; then
    SECURITY_MATURITY="$LOCAL_MATURITY"
    LOCAL_SET=1
  fi
fi

if [ "$LOCAL_SET" -eq 0 ] && [ -f ".claude/settings.json" ]; then
  ...
fi
```

**Severity:** Minor — the scenario (project settings set to enforced/audited while local settings explicitly set to advisory) is unlikely in practice. The current code silently overrides the local intent with the project value only when local explicitly says "advisory," which is an edge case. The plan's stated read precedence ("local overrides project") is violated in this edge case.

---

### M3 — `/architect` Step 0 Pattern 4 glob is appended outside the "run all three in parallel" block

**File:** `skills/architect/SKILL.md`, Step 0

**Observation:** The step header specifies "Run all three globs in parallel" and lists Patterns 1–3. Pattern 4 (`~/.claude/skills/threat-model-gate/SKILL.md`) is added after the three original patterns and their conditional output blocks. The threat-model-gate glob will naturally run sequentially after the three agent checks rather than in parallel with them. This is a minor efficiency gap — the glob is fast, but the structural intent of "run all in parallel" is not preserved.

**Recommendation:** Restructure Step 0 to list all four patterns under the parallel block header before their conditional output blocks:

```
Run all four globs in parallel:
- Pattern 1: ...
- Pattern 2: ...
- Pattern 3: ...
- Pattern 4: ~/.claude/skills/threat-model-gate/SKILL.md

[then conditional output blocks for each pattern]
```

**Severity:** Minor — correctness is not affected. The threat-model-gate result is available before Step 2 either way.

---

### M4 — `/audit` Step 2 `skip` instruction is structurally ambiguous

**File:** `skills/audit/SKILL.md`, Step 2

**Observation:** The text reads: "Skip the existing built-in security scan below. Proceed to Step 3 (Performance scan)." This instruction appears inside the `**If found AND scope is NOT "plan":**` block, which is where the `/secure-review` delegation Task prompt lives. The built-in security scan code block then follows under `**If not found OR scope is "plan":**`. The structural flow is correct, but the phrase "Skip the existing built-in security scan below" inside the `if found` branch is relying on reading comprehension to jump past the `if not found` branch. An executing agent could misread this as an instruction to skip a separate section it has not yet reached and then still enter the `if not found` branch.

**Recommendation:** Make the skip explicit by restructuring the `if not found` branch opening to read: "**If not found OR scope is 'plan' (only execute this branch if the above branch was NOT taken):**" or use a more explicit `else` framing consistent with how other skills express conditional branching.

**Severity:** Minor — the current structure will likely be interpreted correctly by any competent LLM agent, but reducing ambiguity in control flow language prevents misinterpretation.

---

### M5 — `/ship` commit message still references `Claude Opus 4.6` (old attribution style)

**File:** `skills/ship/SKILL.md`, Step 6 commit message template

**Observation:** The commit message template in Step 6 includes:

```
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

The WIP commit in Step 3a also uses this form. This is a pre-existing pattern (not introduced by this plan), so it is not a regression. Noting it as a minor observation for awareness.

**Severity:** Minor / Informational — pre-existing, not introduced by this change.

---

## Positives

**Plan fidelity is high.** All three skills implement the exact changes specified in the plan's Implementation Plan section. Version bumps are correct (ship 3.4.0→3.5.0, architect 3.0.0→3.1.0, audit 3.0.0→3.1.0). The plan's numbered checklist items are all present in the implementation.

**`--security-override` is parsed first, as required.** The plan's Rev 2 critical fix (F-M1: override parsing pinned to Step 0 first action, before run ID generation or `$ARGUMENTS` use) is correctly implemented. The parsing block appears at the top of Step 0 before the run ID bash block.

**Maturity-level-aware result evaluation matrix is complete and correct.** The L1 and L2/L3 matrices in Step 4 match the plan exactly, including the `REVISION_NEEDED + BLOCKED` row that enters the revision loop (plan Rev 2 change M6). Both tables are well-structured and the L1 behavior (auto-downgrade with warning) is clearly distinguished from L2/L3 (hard stop unless overridden).

**Secrets-scan exception (blocks at all maturity levels) is correctly implemented.** Step 0 secrets scan gate correctly blocks at ALL levels, including L1, with the `--security-override` escape valve. This matches Deviation 4 from the plan and is the appropriate security posture for secrets detection.

**`/audit` secure-review composability correctly handles the "plan" scope edge case.** The `**If found AND scope is NOT "plan":**` conditional correctly prevents `/secure-review` from being dispatched when the audit scope is `plan`. The plan's scope mapping table (audit `plan` → use built-in) is faithfully implemented.

**Backward compatibility is preserved at L1.** Missing security skills produce log notes rather than errors. The security gates are strictly additive — they do not modify existing Step 0 fail-fast logic, the code review/tests/QA flow, or the commit gate for projects without security skills deployed.

**`/ship` dependency audit uses `git diff HEAD` (not plan-text heuristic).** Plan Rev 2 change M3 (switch from plan-text heuristic to actual git diff of manifest files) is correctly implemented. The manifest file list covers all common ecosystems (npm, pip, pyproject, Pipfile, Go, Cargo, Maven, Bundler).

**Security artifact archival is included.** Step 6 correctly archives both `[name].secure-review.md` and `[name].dependency-audit.md` to `./plans/archive/[name]/` alongside the existing code review and QA report archival.

**Known limitations are documented inline.** The `--security-override` blanket override limitation (no per-finding scoping, no approver field, no structured audit record) is documented in the plan. The `python3` justification note in Step 0 is present. Stale cross-reference comment from v3.4.0 (`Step 3a` reference) has not been re-introduced.

**Learnings check (known coder patterns):**

Checking `## Coder Patterns > ### Missed by coders, caught by reviewers`:

- **Stale internal step cross-references:** No stale step number references introduced by this change. The new blocks reference other steps generically ("Step 5 revision loop", "Step 3", etc.) without hardcoding step numbers that could become stale.
- **Generator continues-on-write-error but exits 0:** Not applicable (no generator changes in this plan).

No known coder mistakes from learnings.md are present in this implementation.

**Checking `## Reviewer Patterns > ### Overcorrected`:**

- **Self-refuted cosmetic observations:** Minor findings above (M1–M5) are all actionable and have not been flagged then immediately dismissed. Each has a concrete recommendation.

---

## Summary

The implementation correctly delivers all goals from the plan:
- `/ship` v3.5.0 with secrets-scan gate (Step 0), secure-review parallel verification (Step 4d), dependency audit gate (Step 6), maturity-level-aware result evaluation, and `--security-override` flag
- `/architect` v3.1.0 with threat-model-gate detection (Step 0), threat modeling injection for security-sensitive plans (Step 2), and strengthened security-analyst recommendation (Step 3a)
- `/audit` v3.1.0 with `/secure-review` composability (Step 2) and backward-compatible fallback to built-in scan

The five minor findings are low-risk — they do not affect correctness at L1 (the default maturity level) and are either edge-case logic gaps (M2), prose clarity issues (M1, M4), structural organization (M3), or pre-existing patterns (M5). None warrant blocking the implementation.
