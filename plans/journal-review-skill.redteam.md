# Red Team Review (Round 2): Journal Review Skill (`/journal-review`)

**Reviewer:** Red Team (Claude Opus 4.6)
**Review Date:** 2026-02-24
**Plan Under Review:** `plans/journal-review-skill.md` v1.1.0
**Review Type:** Second-round adversarial review — verifying remediation of Round 1 findings + scanning for regressions

---

## Verdict

**PASS**

All six blocking findings from Round 1 (2 Critical, 4 Major) have been addressed. Four are fully resolved; two are substantively resolved with minor residual concerns documented below. One new Minor finding was introduced by the revision. The plan is ready for implementation.

---

## Round 1 Finding Resolutions

### C1: Trigger Phrase Collision with `/journal-recall` — RESOLVED

**Original severity:** Critical
**Resolution status:** Fully resolved

**What changed:** The description field (line 96) now uses entirely distinct trigger phrases: `"journal audit"`, `"review my entries for promotion"`, `"extract decisions"`, `"unlogged items"`, `"what should I formalize"`, `"untracked items"`. The previously colliding phrases `"weekly review"` and `"review my journal"` have been removed. The description also includes an explicit negative disambiguation: `"NOT for weekly summaries — use /journal-recall for 'weekly review' or 'review my journal'."

**Verification against `/journal-recall`:** The deployed `/journal-recall` SKILL.md (line 5) still claims `"weekly review"`, `"review my journal"`, `"last week"`, `"summarize my week"`. There is zero overlap with the revised `/journal-review` trigger set.

**Assessment:** The collision is eliminated and the negative disambiguation provides a secondary safety net. No further action needed.

---

### C2: Semantic Cross-Referencing Has No Failure Mode / No Audit Trail — RESOLVED

**Original severity:** Critical
**Resolution status:** Fully resolved

**What changed (three additions):**

1. **Audit trail (lines 258-259, 316-327):** A "Filtered candidates" list preserves every candidate removed by cross-referencing, recording: the candidate text, the matched existing entry, and a one-line reason. This list is presented to the user in Step 4 under "Filtered by Cross-Reference" so they can audit the LLM's matching decisions.

2. **Uncertainty handling (line 256):** When the LLM is uncertain whether a candidate matches an existing entry, it keeps the candidate and annotates it: `"Possible duplicate of: {existing entry title}."` This prevents uncertain matches from being silently dropped.

3. **User override (line 338):** The user can say `"restore {category} {number}"` to recover an incorrectly filtered candidate.

**Assessment:** All three remediation items from the Round 1 recommendation were implemented. The one sub-recommendation not adopted — a 50-file limit for switching to title-only matching — is acceptable to omit at v1.0.0 given the 90-day safety limit on review periods (practical maximum of ~90 decision + learning files in most vaults). If vault growth becomes an issue, it can be added later.

---

### M1: No Handling of Malformed Entries — RESOLVED

**Original severity:** Major
**Resolution status:** Fully resolved

**What changed (line 171):** Step 2 now includes an explicit "Resilience note" stating: `"Scan the full file content for signal words using grep-style matching across the entire entry text, not only named sections. Section-scoped matches (e.g., content found under ## Decisions Made) are treated as higher-confidence candidates, but signal matches anywhere in the file are included. If an entry is missing expected sections (e.g., no ## Learnings heading), log a warning but still scan the full content."`

**Assessment:** This directly addresses all three sub-items from the Round 1 recommendation: (1) full-file scanning as primary, section-scoping as confidence refinement, (2) explicit warning-and-continue for missing sections, (3) the `**Learning:**` field inside work sessions is captured by full-content scanning. The two-tier confidence model (section-scoped = higher confidence, full-content = included) is a sound design choice.

---

### M2: "should"/"must" in ACTION_SIGNALS Cause False Positives — RESOLVED

**Original severity:** Major
**Resolution status:** Fully resolved

**What changed (line 114):** The `ACTION_SIGNALS` list is now: `"- [ ]", "TODO", "follow up", "need to", "action item", "next step"`. The words `"should"` and `"must"` have been removed entirely.

**Assessment:** The remaining signals are all high-precision action markers. `"need to"` could still generate some false positives in narrative text (e.g., "you need to understand the architecture"), but this is significantly lower-frequency than "should"/"must" and is mitigated by the candidate count cap (see M3 resolution). No further action needed.

---

### M3: No Candidate Count Limit for Large Reviews — RESOLVED

**Original severity:** Major
**Resolution status:** Fully resolved

**What changed (line 269):** Step 4 now specifies: `"If any category contains more than 10 candidates, present the top 10 (ranked by signal confidence: section-scoped matches first, then recency) and note: '{N} additional candidates found. Say show more {category} to see them.'"` Step 4 interaction (line 338) also supports `"show more {category}"` to paginate through additional candidates.

**Assessment:** The cap of 10 per category (with pagination) is conservative and appropriate. The ranking criteria (section-scoped first, then recency) are sensible. Combined with the removal of "should"/"must" (M2), the candidate overload scenario is effectively mitigated.

---

### M4: Template Duplication Drift Risk — RESOLVED (with residual concern)

**Original severity:** Major
**Resolution status:** Substantively resolved; one residual Minor finding

**What changed (lines 420-422):** The plan adds a "template duplication policy" stating: `"At implementation time, templates MUST be copied character-for-character from /journal SKILL.md (the authoritative source). Do NOT copy from this plan document, as plan-level templates may drift from the implementation."` Each embedded template must include a version tracking comment: `<!-- Template source: /journal SKILL.md v1.0.0 — re-sync if /journal templates change -->`.

The plan also adds on-disk override support (line 420): `"On-disk templates at ~/journal/templates/{type}.md override these if present."`

**Assessment:** The policy is sound procedurally: it designates `/journal` as authoritative, warns against copying from the plan, and adds version tracking. However, see New Finding N-NEW-1 below — the plan-level templates still contain the same drift artifacts identified in Round 1, which demonstrates that the policy is needed but has not yet been applied to the plan document itself. This is acceptable because the policy explicitly states the plan-level templates are not the implementation source. The risk is that an implementer ignores the policy and copies from the plan. The version tracking comment provides a secondary safeguard.

---

## New Findings Introduced by v1.1.0

### N-NEW-1: Plan-Level Templates Still Diverge from `/journal` Source

**Severity:** Minor
**Category:** Documentation consistency

The template duplication policy (line 422) correctly states that plan-level templates should not be used as the implementation source. However, the plan-level templates still contain the exact drift artifacts identified in Round 1:

- **Plan line 434:** `status: accepted` (hardcoded single value)
- **`/journal` SKILL.md line 375:** `status: accepted | rejected | superseded | deprecated` (pipe-separated options)
- **Plan line 512-514:** bare ` ``` ` fenced code block (no language hint)
- **`/journal` SKILL.md line 350:** ` ```python ` fenced code block

This is not a blocking issue because the policy explicitly directs implementers to copy from `/journal` SKILL.md, not from this plan. But it is confusing to have known-incorrect templates in the plan after a revision that introduced a policy to prevent exactly this kind of drift.

**Remediation (non-blocking):** Either update the plan-level templates to match `/journal` exactly, or add a visible note above each template: "These templates are illustrative only. Implementation MUST source from /journal SKILL.md per the duplication policy above."

---

### N-NEW-2: "show more" / "restore" Interaction Adds Implicit Iteration

**Severity:** Info
**Category:** Scope

The pagination (`"show more {category}"`) and restore (`"restore {category} {number}"`) interactions in Step 4 introduce additional AskUserQuestion rounds beyond the single approval pass described in the plan's "Bounded Iterations" section (line 537: "the user approves or dismisses each candidate once"). While these interactions are user-initiated and therefore bounded by user patience, they make the "bounded by the number of categories (4)" statement slightly misleading.

This is informational only — the design is correct, and user-initiated pagination is good UX. The "Bounded Iterations" section could be updated to acknowledge the pagination/restore interactions but this is not blocking.

---

## Round 1 Minor/Info Findings — Status Check

The following Round 1 findings were not blocking and were not required to be addressed. For completeness:

| ID | Finding | Status in v1.1.0 |
|----|---------|-------------------|
| N1 | "this sprint" defaults to 14 days | Unchanged — still defaults without user notification. Non-blocking. |
| N2 | Empty `decisions/` directory first-run UX | Unchanged. Non-blocking. |
| N3 | Session numbering gaps | Unchanged. Non-blocking. |
| N4 | Path sanitization empty-string fallback | Unchanged. Non-blocking. |
| N5 | Idempotency on re-runs | Partially addressed — Step 5 checks for existing files at target path. Candidate-stage filtering still relies on semantic cross-referencing. Acceptable for v1.0.0. |
| I1-I4 | Informational observations | No action required. |

---

## Summary

| Severity | Count | IDs | Blocking? |
|----------|-------|-----|-----------|
| Round 1 Critical — resolved | 2 | C1, C2 | No longer blocking |
| Round 1 Major — resolved | 4 | M1, M2, M3, M4 | No longer blocking |
| New Minor | 1 | N-NEW-1 | No |
| New Info | 1 | N-NEW-2 | No |
| Carried Minor (unchanged) | 5 | N1-N5 | No |

All blocking findings have been resolved. The plan is approved for implementation. The one new Minor finding (plan-level template drift) is a documentation quality issue that does not affect the implemented skill.

---

<!-- Context Metadata
discovered_at: 2026-02-24T15:30:00Z
review_type: red-team-round-2
plan_reviewed: journal-review-skill.md v1.1.0
prior_review: journal-review-skill.redteam.md (Round 1, v1.0.0)
verdict: PASS
blocking_findings: none
new_findings: N-NEW-1 (Minor), N-NEW-2 (Info)
-->
