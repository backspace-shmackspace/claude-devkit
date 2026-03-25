# Librarian Review: zerg-adoption-priorities.md (Revision 2)

**Reviewer:** Librarian agent
**Date:** 2026-02-23
**Plan revision:** 2
**Review round:** 2
**Source of truth:** `./CLAUDE.md` (v1.0.0, last updated 2026-02-18)
**Previous verdict:** FAIL (7 conflicts, 3 factual inaccuracies, 7 required edits)

---

## Verdict: PASS

All 7 original conflicts have been resolved. No blocking new conflicts were introduced by the revision. Two minor observations are noted below for awareness but do not warrant a FAIL verdict.

---

## Resolved (7/7 original conflicts fixed)

### Conflict 1: Version mismatch (/dream 2.0.0 vs 2.1.0) -- RESOLVED

**Original issue:** The plan referenced `/dream` v2.1.0 but CLAUDE.md Skill Registry shows v2.0.0. The actual `skills/dream/SKILL.md` has `version: 2.1.0`, confirming CLAUDE.md is stale.

**Resolution:** P0.3 (plan lines 783-784) explicitly reconciles CLAUDE.md: "Update `/dream` version from 2.0.0 to 2.1.0 (matches actual SKILL.md)." The plan also acknowledges the discrepancy inline (plan line 501): "Note: CLAUDE.md Skill Registry currently shows v2.0.0 but actual SKILL.md is v2.1.0. P0.3 reconciles this before the v2.2.0 bump." The Resolution Matrix (plan line 1307) cross-references this fix. Verified that `skills/dream/SKILL.md` does contain `version: 2.1.0`.

### Conflict 2: Pattern 11 removal without versioning -- RESOLVED

**Original issue:** Rev 1 proposed removing Pattern 11 (Worktree Isolation) from the pattern table without incrementing the pattern version or updating the header that says "these 10 patterns" (already wrong -- table has 11 rows).

**Resolution:** Rev 2 reverses the approach entirely. Pattern 11 is now deprecated with a note, not removed (plan line 786): "Pattern 11 (Worktree Isolation): Add deprecation note: 'Deprecated in /ship v3.2.0. Will be replaced by external orchestrator integration (zerg or Anthropic Swarms) in v4.0.0.'" The header count is also fixed (plan line 785): "Fix 'these 10 patterns' to 'these 11 patterns'." This preserves the documentation while signaling the future direction. The approach is consistent with the overall "fix, deprecate, replace" strategy.

### Conflict 3: Undocumented artifact types (task-graph.json, zerg-results.json) -- RESOLVED

**Original issue:** The plan introduced `[feature-name].task-graph.json` and `[feature-name].zerg-results.json` as new artifact types without adding them to the Artifact Locations section of CLAUDE.md.

**Resolution:** P2.3 (plan lines 1000-1001) explicitly scopes this update: "Artifact Locations: Add `[feature-name].task-graph.json` and `[feature-name].zerg-results.json`." The Plan Metadata section (plan line 1269) also catalogues these as "New Artifact Types (for CLAUDE.md)." The After P2 verification commands (plan lines 1203-1204) confirm both entries will be validated after implementation. This fully addresses the Structured Reporting pattern (Pattern 6) compliance concern.

### Conflict 4: Generator rules not enforced for generate_zerg_config.py -- RESOLVED

**Original issue:** Rev 1 did not specify that `generate_zerg_config.py` must follow the Development Rules for Generators (atomic writes, input validation, rollback on failure).

**Resolution:** Rev 2 adds an explicit "Generator rules compliance" subsection (plan lines 347-351) that maps each CLAUDE.md rule to a concrete implementation requirement:
- Atomic writes: "Write to temp file, rename on success" (line 348)
- Input validation: "Validate target-dir exists and is writable. Validate `--workers` is a positive integer. Validate `--mode` is a valid enum" (line 349)
- Rollback on failure: "If any file write fails, clean up all generated files. Use try/finally or atexit handler" (line 350)

P1.3 task steps (plan lines 918-928) reinforce these with explicit step numbers. The acceptance criteria (plan lines 1127-1128) verify "uses atomic writes, input validation, and rollback on failure." This is thorough.

### Conflict 5: Naming convention violation (gen-zerg -> gen-zerg-config) -- RESOLVED

**Original issue:** Rev 1 proposed `gen-zerg` as the alias. The `gen-<noun>` convention requires the noun to describe what is generated. `gen-zerg` implies generating a zerg, not a zerg configuration.

**Resolution:** Rev 2 renames the alias to `gen-zerg-config` throughout (plan lines 332, 1022, 1137). The rationale is documented inline (plan line 1022): "follows `gen-<noun>` convention where the noun is what is generated." The P2.4 acceptance criterion (plan line 1137) enforces this with explicit language: "`install.sh` has `gen-zerg-config` alias (NOT `gen-zerg`)."

### Conflict 6: Breaking deploy.sh behavior unaddressed -- RESOLVED

**Original issue:** Rev 1 proposed `/ship` v4.0.0 as a breaking change but did not address whether `deploy.sh` needed modification to handle the version jump or warn users.

**Resolution:** Rev 2 resolves this on two fronts. First, the version strategy changed: `/ship` goes from v3.1.0 to v3.2.0 (minor), not v4.0.0. The worktree code is fixed and deprecated, not removed. This is explicitly not a breaking change (plan line 488): "NOT 4.0.0 because this is not a breaking change -- existing worktree behavior is preserved and fixed, not removed." Second, `deploy.sh` is explicitly marked "UNCHANGED" in the architecture diagram (plan line 253), which is correct because the adapter script and config live in the repo and are invoked from there, not deployed to `~/.claude/skills/`. I verified that `deploy.sh` only copies `SKILL.md` files from `skills/*/` directories, confirming no change is needed. Additionally, P2.5 adds a `CHANGELOG.md` (plan lines 1035-1060) to document all changes.

### Conflict 7: Vendor-prefixed skill name (/zerg-status -> /status-zerg) -- RESOLVED

**Original issue:** Rev 1 proposed `/zerg-status` using a `[tool]-[action]` prefix pattern, inconsistent with the existing `[action]-[qualifier]` convention (e.g., `test-idempotent`).

**Resolution:** Rev 2 renames the skill to `/status-zerg` (plan lines 215, 1083). The rationale is documented (plan line 1083): "Renamed from `/zerg-status` to `/status-zerg` to follow the `[action]-[qualifier]` naming convention (like `test-idempotent`)." The Resolution Matrix (plan line 1313) cross-references this fix.

---

## Remaining (0/7)

All original conflicts have been resolved. None persist.

---

## New Issues

No blocking issues were introduced by the revision. Two non-blocking observations:

### Observation 1 (Informational): CLAUDE.md Development Rules also says "10 patterns"

P0.3 correctly fixes the Skill Architectural Patterns section header from "10 patterns" to "11 patterns" (plan line 785). However, CLAUDE.md also says "Follow v2.0.0 patterns -- Use all 10 architectural patterns" in Development Rules for Skills (CLAUDE.md line 515). P0.3 step 5 ("Verify no other stale references") should catch this, but it is not explicitly called out. This is a pre-existing CLAUDE.md inconsistency, not introduced by this plan.

**Impact:** None if P0.3 step 5 is executed thoroughly.

### Observation 2 (Informational): scripts/ directory reference in CLAUDE.md

The plan adds `scripts/zerg-adapter.sh` but CLAUDE.md's `/scripts` directory reference (CLAUDE.md lines 604-608) only lists `deploy.sh`, `install.sh`, and `uninstall.sh`. P2.3 scopes CLAUDE.md updates broadly but does not explicitly mention updating the scripts directory listing. This is minor and will naturally be caught during P2.3 execution.

**Impact:** None if P2.3 is executed thoroughly.

---

## Required Edits

None. All 7 original conflicts are resolved. The two observations above are non-blocking and are already covered by existing plan tasks (P0.3 step 5 and P2.3).

---

## Optional Suggestions

1. **P0.3 step 5 scope clarification:** When executing "Verify no other stale references," explicitly check CLAUDE.md line 515 ("Use all 10 architectural patterns") and update it to say 11. This avoids leaving a stale reference that contradicts the corrected header.

2. **P2.3 scripts directory listing:** When updating CLAUDE.md in P2.3, add `zerg-adapter.sh` to the `/scripts` directory reference section alongside `deploy.sh`, `install.sh`, and `uninstall.sh`.

3. **Test suite count stability:** CLAUDE.md references "26 tests" for the existing test suite. The plan wisely creates a separate `test_zerg_integration.sh` (plan line 936) rather than modifying the existing suite, which avoids count drift. If any tests are later added to `test_skill_generator.sh`, update the documented count.

---

## Previous Review Factual Inaccuracies -- Status

The 3 factual inaccuracies from the first review are also addressed:

- **F1** (CLAUDE.md `/dream` version 2.0.0 vs actual 2.1.0): Fixed by P0.3. Plan line 1314 confirms.
- **F2** ("10 patterns" header with 11 rows): Fixed by P0.3. Plan line 1315 confirms.
- **F3** (`plans/ship-v3.1-code-review.md` location): Corrected to `plans/archive/ship-v3.1/ship-v3.1.code-review.md`. Plan line 1316 confirms.

---

## Summary

Revision 2 is a substantial and well-executed rework of the original plan. Every one of the 7 conflicts, 3 factual inaccuracies, and 7 required edits from the first review has been addressed with explicit, traceable resolutions. The Resolution Matrix appendix (plan lines 1281-1330) provides a comprehensive cross-reference of all findings to their resolutions, which is exemplary documentation practice.

Key improvements in Revision 2:
- **Strategy reversal:** "Fix, deprecate, replace" instead of "delete and replace" -- eliminates the capabilities gap risk
- **Vendor risk upgrade:** Zerg risk correctly assessed as HIGH with three concrete design mitigations
- **Anthropic Swarms evaluation:** Added as a credible alternative with adapter-swap design
- **CLI-first integration:** Redesigned around subprocess invocation instead of an unverified Python API
- **P0.0 evaluation gate:** All integration work is gated on actually verifying zerg's interface first
- **Complete compliance:** All naming conventions, generator rules, artifact documentation, and pattern versioning rules are now followed

The plan is approved for implementation.
