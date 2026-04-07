# Feasibility Review (Round 2) -- Threat Model Consumption Plan

**Plan:** `./plans/threat-model-consumption.md`
**Reviewer:** Code Reviewer (feasibility)
**Date:** 2026-04-07
**Round:** 2 (revision review)

## Verdict: PASS

The revised plan addresses all three Major concerns from round 1. No new blocking issues were introduced by the revisions. The plan is ready for implementation.

---

## Round 1 Resolution Status

### M1. Step 7 retro glob path (archive vs plans) -- RESOLVED

**Round 1 concern:** The plan should explicitly state that Step 7 reads the secure-review artifact from the archive directory (not `./plans/`), because Step 6 moves it there before Step 7 runs. An implementer unfamiliar with the archive step could place the glob in the wrong directory.

**Resolution:** The revised plan adds an explicit parenthetical note in the Step 7 modification (section 1c, Implementation Plan Step 6):

> `Glob for ./plans/archive/[name]/*.secure-review.md`
> `(Note: the secure-review artifact is read from the archive directory because Step 6 moves it there before Step 7 runs.)`

This matches the actual `/ship` SKILL.md behavior at lines 1248-1252, where `./plans/[name].secure-review.md` is moved to `./plans/archive/[name]/` during Step 6 artifact cleanup. The glob path and the explanatory note are both correct.

**Status:** Fully resolved.

### M2. $SECURITY_REQUIREMENTS_CONTENT shell notation vs coordinator context -- RESOLVED

**Round 1 concern:** The plan used `$SECURITY_REQUIREMENTS_CONTENT` throughout as if it were a persistent shell variable. In reality, the coordinator agent holds this information in its context window. The variable notation could mislead an implementer into building a file-based persistence mechanism.

**Resolution:** The revised plan replaces all `$SECURITY_REQUIREMENTS_CONTENT` references with the phrase "extracted security requirements content" and adds a dedicated clarification paragraph in section 1a (after the decision matrix):

> **Coordinator context variable clarification:** Throughout this plan, references to "the extracted security requirements content" [...] refer to text held in the coordinator agent's conversation context -- the same mechanism used for existing coordinator-level state like the plan name, work group definitions, and security override reasons. This is NOT a shell environment variable or file-based state.

The paragraph correctly identifies the mechanism (Read tool in Step 1, carried in context window, substituted inline in Step 4d prompt) and explicitly rules out file-based persistence. The Implementation Plan steps (3-5) consistently use "extracted security requirements content" instead of the `$VARIABLE_NAME` notation.

**Status:** Fully resolved.

### M3. Stage 2 re-invocation should use Edit tool instead of full rewrite -- RESOLVED

**Round 1 concern:** The Stage 2 re-invocation prompt instructed the subagent to add a `## Security Requirements` section, but the "do not modify any other section" instruction was fragile because LLM subagents typically use Read + Write, risking subtle modifications to the rest of the plan during rewrite.

**Resolution:** The revised plan updates the Stage 2 re-invocation prompt (section 2a) to explicitly instruct the subagent to use the Edit tool for surgical insertion:

> "Use the Edit tool to insert a `## Security Requirements` section into the existing plan, placing it after the last existing section and before any `## Status` or metadata sections."

The Implementation Plan Step 10 mirrors this with the same Edit-tool-based prompt. This is the correct approach -- the Edit tool performs targeted insertion at a specific location without touching the rest of the file, eliminating the risk of accidental modification during a full rewrite.

**Status:** Fully resolved.

---

## New Concerns Introduced by Revision

### Minor

**m5. Keyword heuristic breadth acknowledged but deferred.**

The revised plan adds two explanatory notes (in section 1a) about the breadth of the inherited keyword heuristic: "Note on Stage 2 keyword overlap" and "Note on inherited keyword breadth." Both notes correctly observe that the heuristic includes broad terms (`file`, `path`, `url`, `database`) that match many non-security plans, and that this is a pre-existing characteristic inherited without modification.

The plan explicitly defers heuristic refinement to a future plan (see Next Steps item 5). This is the right call for scope control. However, the downstream consumption chain does amplify the impact of false positives slightly: at L2/L3, a non-security plan that matches the broad heuristic will now be *blocked* (not just warned) if it lacks a `## Security Requirements` section. The plan's decision matrix handles this correctly (the block only triggers when "plan content has security signals"), but the keywords defining "security signals" in `/ship` Step 1 are the same broad set from `/architect` Stage 1. A plan about "add CSV file upload to admin dashboard" would match on `file` and `upload`, trigger the security-sensitivity check, and potentially block at L2/L3.

This is a design choice, not a bug. The `--security-override` escape valve exists for false positives. No action required for this plan, but the future heuristic refinement plan should prioritize this surface.

**m6. Structural integration test at line 467-468 has a shell syntax issue.**

The plan's structural integration test section includes this test:

```bash
grep -q "## Security Requirements" skills/ship/SKILL.md | grep -q "security_requirements_present" skills/ship/SKILL.md || fail "..."
```

The pipe between the two `grep -q` commands is incorrect. `grep -q` produces no output (quiet mode), so the second `grep` would receive empty stdin and would actually be running independently (the `skills/ship/SKILL.md` file argument saves it from failing on empty stdin, but the pipe is misleading). This should be two separate assertions joined by `&&`:

```bash
grep -q "## Security Requirements" skills/ship/SKILL.md && grep -q "security_requirements_present" skills/ship/SKILL.md || fail "..."
```

This is a minor test correctness issue -- the test would still pass in practice because the second `grep` operates on the file argument, not stdin. But the logical intent (both patterns must be present) requires `&&`, not `|`.

---

## Insertion Point Re-verification (Round 2)

All insertion points remain accurate against the current skill file sources:

| Plan Reference | Verified Against | Status |
|----------------|-----------------|--------|
| `/ship` Step 1: after plan structure validation block ending at line 274 | `skills/ship/SKILL.md` lines 266-275 | Correct. Line 275 begins the "Derive `[name]`" instruction. Insertion after the `## Status: APPROVED` check and before `[name]` derivation is clean. |
| `/ship` Step 4d: the secure-review dispatch prompt at lines 840-857 | `skills/ship/SKILL.md` lines 840-857 | Correct. The `**If found:**` block contains the exact prompt text. The plan's conditional replacement (two code paths) accurately targets this block. |
| `/ship` Step 7: retro capture prompt tasks 1-3 at lines 1317-1328 | `skills/ship/SKILL.md` lines 1317-1328 | Correct. Task 3 (test failures) ends at line 1328. Task 4 (security review) appends after it. Existing task 4 (deduplication) renumbers to 5. |
| `/architect` Step 2: after "If not security-sensitive" at line 222 | `skills/architect/SKILL.md` line 222 | Correct. Stage 2 inserts after this line, before the Step 2 `step_end` emit block at line 224. |
| `/architect` Step 3a: "Recommended" block at line 270 | `skills/architect/SKILL.md` line 270 | Correct. The single paragraph starting with `**Recommended (when threat-model-gate...` is the exact replacement target. |
| `/secure-review` Step 2: after synthesis output template closing at line 234 | `skills/secure-review/SKILL.md` lines 186-234 | Correct. The conditional `## Threat Model Coverage` section inserts after the template's closing code fence. |

---

## Round 1 Minor Concerns Status

| ID | Concern | Status in Revised Plan |
|----|---------|----------------------|
| m1 | Keyword heuristic overlap wider than stated | Acknowledged in two new explanatory notes. Heuristic refinement deferred to future plan. Acceptable. |
| m2 | Threat Model Coverage table assumes exactly six STRIDE rows | Not explicitly addressed in the revision, but the plan's template shows one row per STRIDE category as a *starting template*. The `/secure-review` subagent will naturally produce the right structure based on the plan's actual STRIDE analysis content. Low risk. |
| m3 | `security_requirements_present` field should be validated against audit event schema | Not addressed. Still a valid suggestion for implementation. The schema uses `additionalProperties` patterns that make this non-blocking. |
| m4 | `/architect` Step 5 auto-commit message references stale `v3.0.0` | Not addressed in the revised plan. The implementer should update the version string in the auto-commit message at `skills/architect/SKILL.md` line 424 from `v3.0.0` to `v3.3.0` during the version bump. This is a cosmetic fix that does not affect plan feasibility. |

---

## Final Assessment

The revised plan resolves all three Major concerns cleanly:

1. The archive path dependency is now explicit and correct.
2. The coordinator context mechanism is clearly documented with no risk of implementer confusion.
3. The Edit tool instruction eliminates the fragile full-rewrite pattern.

No new Major or Critical concerns were introduced. The two new Minor observations (m5: keyword breadth amplification at L2/L3, m6: integration test shell syntax) are non-blocking.

The plan is technically feasible and ready for implementation via `/ship plans/threat-model-consumption.md`.
