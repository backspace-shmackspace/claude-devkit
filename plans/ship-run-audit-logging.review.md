# Review: Ship Run Audit Logging (Round 2)

**Plan:** `plans/ship-run-audit-logging.md` (Rev 2, 2026-03-27)
**Reviewed against:** `CLAUDE.md` (2026-03-27), current skill sources, recent plans
**Date:** 2026-03-27
**Round:** 2 (previous: PASS_WITH_NOTES with 4 required edits)

## Verdict: PASS

All 4 required edits from Round 1 have been made. No new conflicts introduced by the revision.

---

## Round 1 Required Edits -- Verification

### Edit 1: Add `agentic-sdlc-next-phase.md` to parent plans

**Status: DONE.** Line 34 now lists `plans/agentic-sdlc-next-phase.md` (Status: APPROVED) in the Parent plans section with an accurate relationship note: "validate-all.sh, expanded test suite, quality infrastructure patterns."

### Edit 2: Add `agentic-sdlc-security-skills.md` to context metadata

**Status: DONE.** Line 1114 context metadata `recent_plans_consulted` now includes `agentic-sdlc-security-skills.md` alongside all other referenced plans. The metadata list matches the body references.

### Edit 3: Fix hardcoded `skill_version` 3.5.0 to 3.6.0

**Status: DONE.** All event examples and schema definitions in the Proposed Design section (lines 191, 231, 246, 263, 279, 297, 316, 333, 353) use `3.6.0`. The state file creation code (line 922) uses `3.6.0`. Remaining `3.5.0` references (lines 26, 106) correctly describe the *current* source version (the starting point), and transition references (lines 887, 966, 1023) correctly document the `3.5.0 -> 3.6.0` bump. No stale hardcoded values remain.

### Edit 4: Add `ship-always-worktree.md` to prior plans

**Status: DONE.** Line 35 lists `plans/ship-always-worktree.md` (Status: APPROVED) in the Parent plans section. Line 1071 includes it in the "Prior Plans Referenced" table with relationship: "Depends on: unified worktree isolation model. Step 3 sub-steps (3a-3f) in the instrumentation table exist because of this plan's worktree structure." This accurately describes the dependency.

---

## Conflicts with CLAUDE.md Rules

None. All previously identified non-conflicts remain non-conflicts. The revision did not introduce any new rule violations.

- **Artifact location convention:** The `plans/audit-logs/` deviation remains documented and justified in "Deviations from Established Patterns" (line 1079). CLAUDE.md update is specified in Phase 2 task list.
- **Development Rules compliance:** Source-first editing, validation before committing, registry updates -- all specified.
- **v2.0.0 patterns:** No new steps added. All bash blocks declare `Tool: Bash`. Existing step numbering preserved.
- **Skill source versions confirmed:** ship 3.5.0, architect 3.1.0, audit 3.1.0 in source match the plan's "Current skill versions" section.
- **Step 3 sub-steps (3a-3f):** Verified against `skills/ship/SKILL.md` source -- all six sub-steps exist and match the plan's instrumentation table.

---

## New Conflicts Introduced by Revision

None. The revision was limited to the 8 changes documented in the Revision Log (line 7), all of which are additive fixes addressing red team, feasibility, and librarian findings. No structural changes to the plan's architecture or scope.

Specific checks performed:

1. **Standalone helper script design** (replacing inline function) -- consistent throughout. The trade-off table (line 54) documents the rejected Option A. All references to the emission mechanism now point to `scripts/emit-audit-event.sh`.
2. **`python3 json.dumps()` for escaping** (replacing `_audit_escape`) -- consistent throughout. No residual references to bash string substitution for JSON escaping.
3. **Persisted HMAC key** (replacing ephemeral key) -- consistent throughout. The trade-off table (line 56), Security Requirements (lines 117, 172), and Proposed Design (lines 391-393) all describe the persisted key model. The old "ephemeral key" limitation discussion has been replaced with honest assessment of the persisted key's threat model.
4. **Duration computed at query time** (replacing `duration_ms` field) -- consistent throughout. Line 197 documents the design note. The query utility (line 596) includes a `timeline` command for computed durations.
5. **Sequence from `wc -l`** (replacing shell variable) -- consistent throughout. Lines 59, 74, 395-396, and 455 all describe the stateless derivation.
6. **`security_decision` event verification in Step 6** -- implemented at lines 533-544.
7. **OTel migration honesty** -- lines 21, 44, 623-641 consistently describe span hierarchy reconstruction as a non-trivial task.
8. **Context metadata updated** -- line 1114 lists all five referenced plans. Line 1116 documents the revision trigger.

---

## Required Edits

None.

---

## Optional Suggestions

1. **Revision log entry for Rev 2 is thorough but long.** The single-line summary (line 7) is 8 clauses. Consider whether future revisions should use a more compact format, but this is a style preference, not a rule violation.

2. **Test H (L3 HMAC chain) is a stub** (line 821: "Similar to Test G but..."). The acceptance criteria (criterion 9) require L3 chain verification. The test plan would be stronger with a concrete implementation rather than a description, but the query utility's `verify-chain` command (line 592) provides the verification mechanism.

3. **Line 598 still mentions "key was ephemeral"** in the `verify-chain` description: "If the key file is not found (key was ephemeral or file was deleted)." Since the design now persists the key, the "key was ephemeral" phrasing is slightly misleading -- the key file could be manually deleted, but it is not ephemeral by design. Minor wording nit.

---

**Reviewed by:** Librarian (automated review against CLAUDE.md and plan corpus)
