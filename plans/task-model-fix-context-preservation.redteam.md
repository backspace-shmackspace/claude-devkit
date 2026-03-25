# Red Team Re-Review: Task Model Fix + Context Preservation (Revised)

**Plan file:** `./plans/task-model-fix-context-preservation.md`
**Original review:** 2026-02-23
**Re-review:** 2026-02-23
**Reviewer:** security-analyst (red team mode)
**Review type:** Re-review of revised plan against 12 original findings

---

## Verdict: PASS

The revised plan resolves both Critical findings, all 3 Major findings that were addressable, all 4 Minor findings, and all 3 Info findings. No new Critical or Major findings were introduced by the revision. The plan is ready for implementation.

---

## Critical Findings: Status

### CRITICAL-01: Validator Will Reject "Step 0.5" and "Step 1b" Headers

**Status: RESOLVED**

The revised plan completely eliminates fractional and letter-suffixed step numbers. The approach chosen is Option A from the original review (renumber steps with sequential integers):

- **dream:** Steps renumbered 0-5 (6 total). New Step 1 (Context Discovery) inserted; old Steps 1-4 renumbered to 2-5.
- **ship:** Steps renumbered 0-6 (7 total). New Step 2 (Pattern Validation) inserted; old Steps 2-5 renumbered to 3-6.

Evidence of resolution:
- Plan line 36 adds an explicit constraint: "All step headers must use integer-only step numbers."
- Plan line 56 documents the trade-off decision (sequential integers chosen over fractional/letter suffixed).
- Plan line 65 states the principle: "Validator compliance: All step headers use integer-only numbers per Pattern #2."
- Sections 2.1 and 3.1 provide exhaustive renumbering tables and all internal cross-reference updates.
- Validation commands (sections 2.7 and 3.3) include grep checks that verify no `Step 0.5` or `Step 1b` headers exist and that all sequential integer steps are present.
- Acceptance criteria (lines 1270, 1279) explicitly require integer-only step headers.
- grep search of the revised plan confirms zero occurrences of `Step 0.5` or `Step 1b` text (except in the "Changes From Previous Plan Version" table which references the old finding, not a step header).

This finding is fully resolved.

---

### CRITICAL-02: CLAUDE.md Registry Already Stale -- "OLD" Text Will Not Match

**Status: RESOLVED**

The revised plan acknowledges the pre-existing drift and handles it correctly:

1. **Pre-existing drift documented.** Plan line 28 adds: "Pre-existing registry drift: CLAUDE.md shows dream version as `2.0.0`, but `skills/dream/SKILL.md` frontmatter is already `2.1.0`."
2. **OLD text matches actual CLAUDE.md content.** I verified the plan's OLD block (lines 1053-1058) against the actual CLAUDE.md registry (lines 70-74 of `/Users/imurphy/projects/claude-devkit/CLAUDE.md`). They match exactly. The plan correctly uses what CLAUDE.md actually contains, not what it should contain.
3. **Version jump explained.** Plan line 1071 explains: "dream: `2.0.0` -> `2.2.0` (correcting pre-existing drift from 2.1.0 and adding P1 changes)." The version gap from 2.0.0 to 2.2.0 in the registry is acceptable because 2.1.0 was never reflected in CLAUDE.md -- this plan corrects that omission.
4. **Phase 4 note added.** Plan line 1048 adds an explicit note about pre-existing drift before the Phase 4 instructions.
5. **Sync model drift also corrected.** CLAUDE.md shows `opus-4-6` for sync, but the actual frontmatter is `claude-sonnet-4-5`. The plan's NEW block (line 1066) correctly sets sync to `sonnet-4-5`.

This finding is fully resolved.

---

## Major Findings: Status

### MAJOR-01: Context Discovery Glob Exclusion Pattern Is Fragile

**Status: ACCEPTED (documented limitation)**

The revised plan explicitly accepts this limitation in the "Not addressed" section (line 1358): "MAJOR-01 (glob exclusion pattern fragility): Accepted as known limitation. Future iteration can switch to positive filtering."

This is a reasonable acceptance. The exclusion pattern works for the current set of artifact types, and the non-blocking nature of context discovery means the worst case is context pollution (extra review artifacts in the context block), not workflow failure. The plan's Risk Assessment (line 1301) captures this with appropriate probability/impact ratings.

No further action required for this plan revision.

---

### MAJOR-02: "Similar Plans" Keyword Matching Is Undefined

**Status: ACCEPTED (documented limitation)**

The revised plan explicitly accepts this in line 1359: "MAJOR-02 (plan similarity matching undefined): Accepted as LLM best-effort. Non-blocking by design."

The warnings-only architecture means false negatives in plan similarity detection do not block the workflow. This is acceptable.

No further action required for this plan revision.

---

### MAJOR-03: Pattern Validation Has No Structured Extraction Logic

**Status: ACCEPTED (documented limitation)**

The revised plan explicitly accepts this in line 1360: "MAJOR-03 (pattern validation has no structured extraction): Accepted as LLM best-effort. Non-blocking warnings-only design contains blast radius."

The plan's Risk Assessment (line 1297) also captures this: "Pattern validation false positives in /ship: Medium probability, Low impact (warnings only)."

No further action required for this plan revision.

---

## Minor Findings: Status

### MINOR-01: Plan Author Self-Correction Visible

**Status: RESOLVED**

The "Wait -- let me re-examine" text has been removed from the revised plan. grep confirms zero occurrences of this phrase. The sync frontmatter details are now presented cleanly in section 1.4 (lines 296-308).

---

### MINOR-02: Context Metadata Hash Adds Complexity With Marginal Value

**Status: RESOLVED**

The `claude_md_hash` field has been replaced with `claude_md_exists: [true or false]` (plan line 656). The plan includes a clear rationale (line 675): "The original hash field required SHA256 computation that LLM agents cannot natively perform without a Bash call, creating a risk of hallucinated hash values. A simple boolean is sufficient because /ship Step 2 reads the current CLAUDE.md directly for pattern validation."

This is a better design. The boolean is trivially verifiable by the LLM, eliminates hallucination risk, and still provides the useful signal (was CLAUDE.md consulted during planning).

---

### MINOR-03: Version Bump Semantic Inconsistency

**Status: NO ACTION NEEDED (informational)**

This was an informational finding with no action required. The version bump semantics remain correct in the revised plan (patch bumps for bugfix-only skills, minor bumps for skills receiving new features).

---

### MINOR-04: Integration Smoke Test Lacks Failure Criteria

**Status: RESOLVED**

The revised smoke test (lines 1116-1131) now includes expected output criteria for each verification point:

- "expect to see 'Discovered Project Context' heading in coordinator output before architect is invoked"
- "expect `$CONTEXT_BLOCK` content visible in agent dispatch"
- "expect 'Pattern validation warnings' or 'Plan aligns with CLAUDE.md patterns' in output"
- "expect 'These warnings are informational' if warnings exist"
- "expect 'Historical alignment issues' in review output"

These are specific, observable expectations that a tester can verify.

---

## Info Findings: Status

### INFO-01: No Rollback Plan for Partial Deployment

**Status: RESOLVED**

The revised plan adds deploy rollback instructions in two locations:
- Line 1133: "After reverting any phase, re-run `./scripts/deploy.sh` to ensure deployed skills match the git state."
- Line 1313: Same instruction embedded in the Rollout Plan section.

---

### INFO-02: The --fast Flag Interaction With Context Discovery Is Unspecified

**Status: RESOLVED**

The revised plan explicitly documents this interaction in multiple locations:
- Line 57: Trade-off table entry documenting the decision to always run context discovery.
- Line 130: "Context discovery runs regardless of the `--fast` flag."
- Line 563: Same statement in the Step 1 description itself.
- Smoke test (line 1129-1131): Verification that `--fast` does not skip context discovery.

---

### INFO-03: Deploy Path Mismatch

**Status: RESOLVED**

The Phase 5.1 deploy command (line 1108) now uses the actual project path: `cd /Users/imurphy/projects/claude-devkit`.

---

## New Findings Introduced by Revision

### NEW-01: Sub-step Headers Use "####" Which May Not Match Validator Pattern

**Severity: Minor**
**Category: Validator Compatibility**
**Affected Phase: Phase 3 (ship)**

The ship skill renumbering in section 3.1 shows sub-step headers using `####` prefix (e.g., `#### Step 3a -- Shared Dependencies`). The validator regex (line 137 of `validate_skill.py`) matches `^## Step (\d+)`. The `####` sub-step headers will not be matched by this regex, which is the existing behavior (sub-steps were never validated as top-level steps). This is not a regression -- it is existing behavior preserved through the renumbering.

However, the plan should ensure the sub-step renumbering is internally consistent. I verified the renumbering tables in sections 3.1 and they are consistent: Steps 2a-2f become 3a-3f, Steps 3a-3c become 4a-4c, Steps 4a-4b become 5a-5b. All internal cross-reference updates are enumerated (lines 853-941).

**Risk: Low.** This is consistent with existing validator behavior. No action required.

---

### NEW-02: Phase Dependency Creates Serial Bottleneck

**Severity: Info**
**Category: Execution Efficiency**
**Affected Phase: All**

The revised plan states "Phase 1 must be applied first (version bump coordination)" for both Phase 2 and Phase 3. This is correct because dream and ship both receive Phase 1 changes (model aliases) AND Phase 2/3 changes (new steps), and the version bumps must be coordinated.

However, this means Phases 2 and 3 cannot be parallelized with Phase 1 -- they must be applied to the same files sequentially. This is a structural property of the plan, not a defect. The estimated total effort (30m + 1h + 45m + 15m + 15m = 2h 45m) assumes serial execution.

**Risk: None.** This is informational. Phases 2 and 3 are independent of each other and could be parallelized if applied by different engineers to different files (dream vs. ship).

---

### NEW-03: Nested Code Fence Avoidance Creates Non-Standard Delimiters

**Severity: Minor**
**Category: Implementation Clarity**
**Affected Phase: Phase 2**

The revised plan uses `---begin context block format---` / `---end context block format---` and `---begin metadata format---` / `---end metadata format---` delimiters (lines 579, 593, 653, 660) to avoid triple-backtick nesting issues in the SKILL.md file. Implementation notes (lines 602-603, 673-674) warn against converting these to code fences.

This is a reasonable workaround, but the non-standard delimiter format could confuse an implementer who expects markdown code fences. The delimiter text itself contains `---` which resembles YAML frontmatter delimiters, potentially creating visual ambiguity.

**Risk: Low.** The implementation notes are clear. The delimiters are literal text in the SKILL.md, not parsed syntax. An implementer reading the plan carefully will understand the intent.

---

### NEW-04: Cross-Reference Completeness Is Difficult to Verify From Plan Alone

**Severity: Minor**
**Category: Verification Gap**
**Affected Phase: Phases 2, 3**

The plan enumerates many internal cross-reference updates (e.g., "Skip to Step 3" becomes "Skip to Step 4", "continue to Step 2e" becomes "continue to Step 3e"). These updates are listed narratively in sections 2.1 and 3.1, but there is no exhaustive grep-based verification command that checks ALL cross-references were updated.

The validation sections (2.7 and 3.3) check step header existence and specific features but do not verify that every textual reference like "continue to Step N" points to the correct step number. A missed cross-reference would cause the skill to jump to the wrong step during execution.

The plan's Risk Assessment (line 1298) rates this as "Medium probability, Medium impact" with mitigation of "Exhaustive list of all cross-reference updates" and "Manual review."

**Recommended mitigation:** After implementation, grep the modified skill files for all patterns like `Step \d` and manually verify each reference points to the correct step. This is a post-implementation verification step, not a plan defect.

**Risk: Medium for implementation, but mitigable.** The plan's approach of listing every cross-reference change is thorough. The risk manifests only if the implementer misses one during execution.

---

## Summary Table

| # | Finding | Original Severity | Status | Notes |
|---|---------|-------------------|--------|-------|
| CRITICAL-01 | Validator rejects Step 0.5 / Step 1b | Critical | RESOLVED | Steps renumbered to sequential integers |
| CRITICAL-02 | CLAUDE.md OLD text stale | Critical | RESOLVED | Pre-existing drift documented; OLD text matches actual file |
| MAJOR-01 | Glob exclusion fragile | Major | ACCEPTED | Documented limitation; future iteration |
| MAJOR-02 | Plan similarity undefined | Major | ACCEPTED | LLM best-effort; non-blocking design |
| MAJOR-03 | Pattern validation unstructured | Major | ACCEPTED | Warnings-only contains blast radius |
| MINOR-01 | Author self-correction visible | Minor | RESOLVED | Text removed |
| MINOR-02 | claude_md_hash complexity | Minor | RESOLVED | Replaced with claude_md_exists boolean |
| MINOR-03 | Version bump semantics | Minor | NO ACTION NEEDED | Informational only |
| MINOR-04 | Smoke test lacks criteria | Minor | RESOLVED | Expected outputs added |
| INFO-01 | No deploy rollback | Info | RESOLVED | Rollback instructions added |
| INFO-02 | --fast interaction unspecified | Info | RESOLVED | Explicitly documented in multiple locations |
| INFO-03 | Deploy path mismatch | Info | RESOLVED | Uses actual project path |
| NEW-01 | Sub-step #### headers not validated | Minor (new) | NOTED | Existing behavior, not a regression |
| NEW-02 | Serial phase dependency | Info (new) | NOTED | Structural property, not a defect |
| NEW-03 | Non-standard delimiters | Minor (new) | NOTED | Implementation notes are clear |
| NEW-04 | Cross-reference verification gap | Minor (new) | NOTED | Recommend post-implementation grep check |

**Original findings resolved:** 9 of 12 (3 accepted as documented limitations)
**New findings:** 4 (0 Critical, 0 Major, 3 Minor, 1 Info)

---

## Conclusion

The revised plan demonstrates thorough response to all 12 original findings. Both Critical findings are fully resolved through step renumbering (CRITICAL-01) and registry drift documentation (CRITICAL-02). The plan author made the correct design decisions: sequential integer renumbering over validator modification, `claude_md_exists` boolean over SHA256 hash, and explicit `--fast` interaction documentation.

The three Major findings that were accepted as documented limitations (glob exclusion fragility, plan similarity matching, pattern validation structure) are all contained by the plan's warnings-only, non-blocking architecture. This is the right design choice -- these are inherent limitations of LLM-interpreted instructions, and hard-blocking on imprecise heuristics would be worse than surfacing best-effort warnings.

The four new findings introduced by the revision are all Minor or Info severity. None require plan changes before implementation. The most actionable is NEW-04 (cross-reference verification gap), which should be addressed during implementation with a post-edit grep check, not a plan revision.

**Recommendation: Proceed with implementation.** No further plan revision is needed.
