# Feasibility Review: journal-review-skill.md (Round 2)

**Reviewer:** Claude Opus 4.6 (code review mode)
**Date:** 2026-02-24
**Plan reviewed:** `plans/journal-review-skill.md` v1.1.0
**Previous review:** v1.0.0, same date, verdict PASS with 4 Major concerns
**Existing skills consulted:** `contrib/journal/SKILL.md`, `contrib/journal-recall/SKILL.md`

---

## Verdict: PASS

All four Major concerns from the v1.0.0 review have been addressed (3 fully resolved, 1 partially resolved). The new mechanisms introduced in v1.1.0 (filtered candidates audit trail, pagination, "restore" interaction) are technically sound. No new Critical or Major concerns. One prior Major downgraded to Minor. Five Minor concerns total (one carried forward, four new).

---

## Status of v1.0.0 Major Concerns

### M1. Trigger-word collision with journal-recall -- RESOLVED

The v1.1.0 `description` field (line 96-97) now uses differentiated trigger phrases: "journal audit", "review my entries for promotion", "extract decisions", "unlogged items", "what should I formalize", "untracked items". It also includes an explicit disambiguation clause: "NOT for weekly summaries -- use /journal-recall for 'weekly review' or 'review my journal'." This is exactly what was recommended. No overlap remains with `journal-recall`'s trigger set.

### M2. Learning template drift from /journal -- RESOLVED (policy level)

The plan now includes an explicit template duplication policy (line 420-422): "templates MUST be copied character-for-character from `/journal` SKILL.md (the authoritative source). Do NOT copy from this plan document, as plan-level templates may drift from the implementation." Each embedded template must include a version tracking comment. This is the correct approach.

Note: the plan document's own embedded `learning.md` template (line 512) still uses a bare code fence (` ``` `) while `/journal` SKILL.md uses ` ```python `. This is acceptable because the policy explicitly instructs implementers to copy from `/journal` SKILL.md, not from the plan. The plan-level templates serve as illustrative examples only.

### M3. "should"/"must" in ACTION_SIGNALS -- RESOLVED

The `ACTION_SIGNALS` list (line 114) now reads: `"- [ ]", "TODO", "follow up", "need to", "action item", "next step"`. The words "should" and "must" have been removed. The remaining signals are specific enough to produce useful results without excessive false positives.

### M4. No explicit exclusion of plans/ directory -- PARTIALLY RESOLVED

Step 1 (lines 143-163) scans only `daily/` and `meetings/`, which is correct behavior. However, the recommended addition to the Non-Goals section ("Scanning `plans/`, `projects/`, or other vault directories beyond `daily/` and `meetings/`") was not made. The behavior is correct but the omission is not documented.

Downgraded from Major to Minor since the implementation is correct and only the documentation is missing. See m1 below.

---

## Concerns

### Critical

None.

### Major

None.

### Minor

**m1. plans/ directory exclusion still not in Non-Goals (carried from M4)**

The scan scope is correctly limited to `daily/` and `meetings/` in Step 1, but the Non-Goals section does not explicitly state that `plans/`, `projects/`, `templates/`, and other vault directories are out of scope. A user reading the Non-Goals would not know whether the skill is supposed to scan those directories.

- **Impact:** Low. The Step 1 implementation is unambiguous. This is a documentation gap only.
- **Recommendation:** Add to Non-Goals: "Scanning vault directories beyond `daily/` and `meetings/` (e.g., `plans/`, `projects/`, `templates/`)."

**m2. Pagination "show more" interaction is stateful but state management is unspecified**

Step 4 (line 269) introduces pagination: "If any category contains more than 10 candidates, present the top 10... note: '{N} additional candidates found. Say show more {category} to see them.'" The "show more" interaction (line 337-338) requires the skill to remember which candidates have already been shown and present the next batch. In a Claude Code skill context, there is no persistent state between AskUserQuestion calls -- the entire candidate list is in the LLM's context window.

- **Impact:** Low. The LLM can track this in its working memory within a single session. The candidate list is finite and already loaded. This is not a true pagination problem but a presentation sequencing problem, which the LLM handles naturally.
- **Recommendation:** No change needed. The mechanism works because the full candidate list is in context. If the plan were delegating to a subagent, this would be a real concern, but it explicitly runs in-session (line 54: "no subagent delegation").

**m3. "restore" interaction for filtered candidates adds parsing complexity**

Step 4 introduces a "restore {category} {number}" command (lines 338, 340) that moves a filtered candidate back to the active list. This requires the LLM to parse a free-text response that may mix approval, dismissal, show-more, and restore commands in a single reply (e.g., "Decisions: 1, 3; restore learnings 2; show more actions"). The parsing is not specified.

- **Impact:** Low. The LLM is the parser, and Claude handles this kind of structured free-text instruction well. The risk is that an unusual phrasing is misinterpreted, but the consequences are low (wrong candidate approved or missed -- user can manually create entries with `/journal`).
- **Recommendation:** No change needed for v1.0.0. The free-text parsing approach is pragmatic. If parsing errors become common in practice, a future version could use numbered menus with explicit yes/no per item.

**m4. Filtered candidates section may be large and obscure the actual candidates**

The "Filtered by Cross-Reference" section (lines 316-327) is presented alongside active candidates. In a mature vault with many existing decisions and learnings, the filtered list could be larger than the active candidate list, pushing the actual approval prompt far down the output. This could confuse the user about what needs action.

- **Impact:** Low. In practice, the journal vault is small (currently 0 decisions, 1 learning). At steady state, the filtered list will grow but so will the user's familiarity with the workflow. The filtered section is at the end, after all active candidates.
- **Recommendation:** Consider collapsing the filtered section by default: present only the count ("N items filtered by cross-reference -- say 'show filtered' to see details") rather than the full list. This is a UX preference and acceptable as-is for v1.0.0.

**m5. Resilience note in Step 2 may interact unexpectedly with signal-word matching in template boilerplate**

Step 2 (line 171) specifies: "Scan the full file content for signal words using grep-style matching across the entire entry text, not only named sections." This means template boilerplate like `<!-- What is the issue that we're seeing that is motivating this decision? -->` could match decision signals ("decision"), and `<!-- Link to decision records if significant -->` could also match. The daily template's `## Decisions Made` heading itself contains "decision".

- **Impact:** Low. The section-heading matches are handled separately as "higher-confidence" candidates. HTML comments and headings are unlikely to produce meaningful candidate text once the LLM extracts context. The user approval gate filters any remaining noise.
- **Recommendation:** Add a note to Step 2: "Exclude matches found only in HTML comments (`<!-- ... -->`) or section headings (`## ...`) with no substantive content below them."

---

## Assessment of New v1.1.0 Mechanisms

### Filtered candidates audit trail (Step 3, Step 4)

**Assessment: Well-designed.** The two-tier approach (confident matches are filtered with audit trail, uncertain matches are kept with "Possible duplicate" annotation) is sound. Preserving filtered candidates for user review addresses the false-match risk without adding excessive interaction overhead. The one-line reason per filtered item provides transparency.

### Pagination (Step 4, 10-candidate cap per category)

**Assessment: Appropriate.** The 10-candidate cap per category is a reasonable threshold. The ranking criteria (section-scoped matches first, then recency) produces sensible ordering. The "show more" mechanism works within the LLM's session context without requiring external state.

### "restore" command for filtered items (Step 4)

**Assessment: Workable.** The ability to recover incorrectly filtered candidates is important for trust. The free-text parsing approach is pragmatic for v1.0.0. See m3 above for a minor concern about parsing complexity.

### Template duplication policy (Embedded Templates section)

**Assessment: Correct approach.** The policy of copying from `/journal` SKILL.md at implementation time, with version tracking comments, is the right tradeoff between DRY principles and practical simplicity. A shared-template mechanism would be over-engineering for a 2-skill (soon 3-skill) ecosystem.

### Disambiguation clause in description field

**Assessment: Effective.** The "NOT for weekly summaries -- use /journal-recall" clause is a clean solution to the trigger-word collision. This pattern could be adopted by other skills with adjacent trigger sets.

---

## Consistency with Existing Skills

| Aspect | /journal | /journal-recall | /journal-review (v1.1.0) | Consistent? |
|--------|----------|-----------------|--------------------------|-------------|
| JOURNAL_BASE | `~/journal/` | `~/journal/` | `~/journal/` | Yes |
| Model | claude-opus-4-6 | claude-opus-4-6 | claude-opus-4-6 | Yes |
| Frontmatter format | name, version, model, description | name, version, model, description | name, version, model, description | Yes |
| Path sanitization | Documented, same rules | N/A (read-only) | Same rules as /journal | Yes |
| Template format | Embedded + on-disk override | N/A | Embedded + on-disk override (with copy-from-source policy) | Yes |
| Verdict format | PASS/FAIL | PASS (never FAIL for zero results) | PASS/FAIL | Yes |
| Archetype | Pipeline (6 steps) | Pipeline (4 steps) | Pipeline (6 steps) | Yes |
| Stub sections | 3 stubs | 3 stubs | 3 stubs | Yes |
| Trigger phrases | No overlap | No overlap with v1.1.0 | No overlap with recall | Yes -- fixed |

---

## Recommended Adjustments

1. **Add plans/ exclusion to Non-Goals (m1):** Add: "Scanning vault directories beyond `daily/` and `meetings/` (e.g., `plans/`, `projects/`, `templates/`)."
2. **Exclude template boilerplate from signal matching (m5):** Add note to Step 2: "Exclude matches found only in HTML comments or section headings with no substantive content below them."
3. **Consider collapsing filtered section by default (m4):** Present count only, with "show filtered" command to expand. Optional UX improvement.

All three are Minor and none block implementation.

---

<!-- Feasibility review metadata
reviewed_plan: plans/journal-review-skill.md
plan_version: 1.1.0
review_round: 2
review_date: 2026-02-24
verdict: PASS
critical_count: 0
major_count: 0
minor_count: 5
prior_major_resolved: 3
prior_major_downgraded: 1
-->
