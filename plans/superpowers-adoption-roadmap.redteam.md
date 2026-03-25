# Red Team Review (Round 2): Superpowers Adoption Roadmap

**Reviewed:** 2026-03-05
**Plan:** `./plans/superpowers-adoption-roadmap.md` (Rev 2)
**Reviewer:** Critical Review Agent
**Previous Review:** Round 1 (Rev 1) -- 2 Critical, 4 Major, 3 Minor, 2 Info

---

## Verdict: PASS

No critical findings remain. Both prior Critical findings have been substantively addressed. Several residual concerns at Major and Minor levels warrant attention during implementation but do not block approval.

---

## Round 1 Critical Findings -- Disposition

### Critical 1 (was: No behavioral testing at all) -- RESOLVED, with residual concern (Minor)

Rev 2 adds a manual behavioral acceptance test to every Reference skill phase (Phases 1-5). Each test specifies a concrete prompt, expected behavioral markers as checkboxes, and the instruction to document results in the PR description. This directly addresses the original finding.

**Residual concern (see Finding 2 below):** The behavioral tests are manual-only and lack pass/fail criteria beyond subjective judgment. This is acceptable for an initial rollout but should not remain the permanent state.

### Critical 2 (was: No conflict resolution for simultaneous triggering) -- RESOLVED

Rev 2 adds a thorough "Activation Scoping and Conflict Resolution" section (lines 124-158) with:
- Explicit activation domains per skill (activates on / does NOT activate on)
- Multi-activation scenario table with resolutions
- Iron Law priority ordering (debugging > TDD > verification, receiving-code-review isolated)
- Context window cost analysis with worst-case estimate (~30-40KB for 2-skill co-activation)

The analysis is credible. The activation domains are genuinely non-overlapping for the common cases. The priority ordering resolves the specific contradiction I raised (investigate-first vs. test-first).

---

## Round 1 Major Findings -- Disposition

### Major 3 (was: Reference archetype without validator support) -- RESOLVED

Phase 0 now adds `type: reference` frontmatter detection to `validate_skill.py`, with Reference-specific checks. The dead `skill-patterns.json` proposal is now connected to the validator. Goal 6 explicitly states "no `|| echo` suppressions." This is a clean fix.

### Major 4 (was: No rollback plan) -- RESOLVED

Phase 0 adds `deploy.sh --undeploy <skill-name>`. Manual fallback is documented. Rollback procedure is in both the Rollout Plan and Risk Assessment sections.

### Major 5 (was: Embedded appendices context window concern) -- RESOLVED

Context window cost analysis added with measured data. Worst-case simultaneous load estimated at ~30-40KB with escape hatch ("narrow descriptions to reduce co-activation"). Size estimate corrected from ~15KB to ~20KB per feasibility review.

### Major 6 (was: No licensing analysis) -- RESOLVED

MIT license identified, attribution requirement documented, `attribution` frontmatter field added to all skills and to the Reference archetype required fields. Clean.

---

## New Findings (Rev 2)

### 1. Behavioral tests have no failure criteria or iteration protocol (Major)

**Description:** Every behavioral acceptance test says "run this prompt, check these markers, document results in PR." But none of them define what happens when the behavioral test fails. If the agent does NOT exhibit the expected markers -- does the phase fail? Does the skill get iterated? Is there a maximum number of description-wording iterations before the approach is abandoned?

The tests are structured as checklists but there is no gate: a skill could be merged with 0 of 4 behavioral markers satisfied, as long as the implementer documents "results" in the PR. Compare this to the structural tests, which have hard pass/fail (`validate_skill.py` exits 0 or non-zero). The behavioral tests are observation-only with no enforcement mechanism.

**Recommendation:** Add a behavioral gate: "At least N of M behavioral markers must be observed. If fewer than N are observed, iterate on the skill description wording and re-test. If 3 iterations fail to produce satisfactory behavior, escalate to plan review." This converts the behavioral test from documentation to an actual gate.

---

### 2. Conflict resolution assumes Claude Code loads only matching skills -- this is unverified (Major)

**Description:** The context window cost analysis states: "Claude Code's skill matching loads only skills whose descriptions match the current context -- it does not load all deployed skills simultaneously." This is the cornerstone assumption for the entire conflict resolution strategy. If Claude Code actually loads all deployed skills (or loads more broadly than assumed), the activation domain analysis is irrelevant and the context window cost could be 5x the estimate (~60-75KB of behavioral instructions on every prompt).

The plan does not cite documentation, source code, or empirical evidence for this assumption. It is stated as fact. Given that this assumption underpins the safety of deploying 5 description-triggered behavioral skills simultaneously, it needs verification.

**Recommendation:** Before Phase 0 implementation, verify Claude Code's skill loading behavior empirically. Deploy two skills with non-overlapping descriptions, issue a prompt that matches only one, and check whether both appear in the context. Document the finding. If all skills are loaded regardless of matching, the activation scoping strategy needs fundamental rework (e.g., skills would need internal "When NOT to apply" guards rather than relying on selective loading).

---

### 3. Phase 6 `--contrib` flag for deploy.sh still unverified (Minor)

**Description:** This was Finding 8 (Minor) in Round 1. Rev 2 adds a risk table entry ("deploy.sh does not support `--contrib` flag" -- Low probability, High impact) with mitigation "Verify before Phase 6 implementation." The risk is acknowledged but the verification is deferred rather than performed. Since Phase 6 is last in the rollout and low priority, this is acceptable, but it remains an unresolved assumption.

**Recommendation:** No change needed -- the deferral is reasonable given Phase 6's priority. Just ensure the verification happens before the Phase 6 /dream cycle begins.

---

### 4. Canary deployment strategy relies on a single subjective data point (Minor)

**Description:** The rollout plan deploys Phase 4 (receiving-code-review) as a canary before the higher-impact skills. The canary criteria are implicit: "If the Reference archetype causes problems in practice (unexpected triggering, context issues), the issue will surface in a low-impact context." But there is no defined observation period, no criteria for declaring the canary successful, and no minimum usage threshold before proceeding.

A canary that runs for 5 minutes before the implementer proceeds to Phase 2 is not meaningfully different from no canary. Conversely, a canary with no success criteria could block rollout indefinitely.

**Recommendation:** Define a minimum canary period (e.g., "use receiving-code-review in at least 3 real code review sessions over at least 2 days") and explicit success criteria (e.g., "no unexpected triggering observed, no context window issues, behavioral markers consistently present"). Then gate Phase 2 deployment on canary success.

---

### 5. All 5 Reference skills share identical model field with no discussion of whether it is operative (Minor)

**Description:** This was Finding 7 (Minor) in Round 1. Rev 2 does not address it. All skills specify `model: claude-sonnet-4-5` but the plan still does not clarify whether the `model` frontmatter field controls which model Claude Code uses when the skill activates, or whether it is purely informational for description-triggered skills. The feasibility review (N4) also flagged this.

If the field is informational, specifying it adds noise. If it is prescriptive, it forces a model downgrade for any user running Opus, which may not be desirable for behavioral constraint skills where reasoning quality matters.

**Recommendation:** Verify whether `model` is operative for passively-triggered skills. If informational, note this in the Reference archetype definition. If prescriptive, consider whether Sonnet is the right choice for behavioral constraint enforcement, or whether omitting the field (inheriting the session model) would be better.

---

### 6. No deduplication audit against target CLAUDE.md (Info)

**Description:** This was Finding 9 (Minor) in Round 1. Rev 2 does not address it. The plan adds 5 behavioral discipline skills but does not audit whether `claude-devkit/CLAUDE.md` already contains overlapping behavioral instructions (e.g., "always verify before claiming done"). This is low risk because the skills are additive, but redundant instructions waste context.

**Recommendation:** Quick audit of `claude-devkit/CLAUDE.md` during Phase 0 for behavioral instructions that overlap with the 5 proposed skills. Remove or consolidate duplicates.

---

### 7. Success metrics still undefined (Info)

**Description:** This was Finding 11 (Info) in Round 1. Rev 2 does not add success metrics for the overall adoption. The verification checklist confirms deployment and structural correctness but does not define how to evaluate whether the skills improved agent behavior over time. Without metrics, the 6 skills will persist indefinitely regardless of value.

**Recommendation:** After all phases are deployed, define a lightweight retrospective checkpoint (e.g., "After 4 weeks, review: Are the skills triggering appropriately? Have any been --undeployed? Would you re-deploy them if starting fresh?"). This does not need to be quantitative, just intentional.

---

## Summary of Findings

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 1 | Behavioral tests lack failure criteria / iteration protocol | Major | New |
| 2 | Skill loading assumption (only matching skills loaded) is unverified | Major | New |
| 3 | Phase 6 `--contrib` flag unverified (deferred) | Minor | Carried (R1 #8) |
| 4 | Canary deployment has no observation period or success criteria | Minor | New |
| 5 | `model` field operative vs. informational still unclear | Minor | Carried (R1 #7) |
| 6 | No deduplication audit against target CLAUDE.md | Info | Carried (R1 #9) |
| 7 | Success metrics undefined | Info | Carried (R1 #11) |

**Bottom line:** Rev 2 made substantive improvements. Both Critical findings are genuinely resolved -- not papered over. The conflict resolution analysis is thorough, Phase 0 is well-scoped, and behavioral tests exist for every Reference skill. The two new Major findings (behavioral test enforcement and skill loading assumption) are real gaps but not plan-blocking: they can be addressed during Phase 0 implementation without restructuring the plan. The plan is ready for implementation with these caveats noted.
