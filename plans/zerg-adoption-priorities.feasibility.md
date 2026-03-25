# Feasibility Re-Review: Zerg Adoption Priorities for Claude-Devkit (Revision 2)

**Reviewed:** 2026-02-23
**Reviewer:** code-reviewer (feasibility re-review)
**Plan File:** `./plans/zerg-adoption-priorities.md` (Revision 2)
**Previous Review:** `./plans/zerg-adoption-priorities.feasibility.md` (Revision 1, verdict: PASS with 2 critical unknowns)
**Referenced Source Files:**
- `skills/ship/SKILL.md` (v3.1.0, 526 lines)
- `skills/dream/SKILL.md` (v2.1.0, 151 lines)

---

## Verdict: PASS

The revised plan resolves both critical unknowns and all 6 major concerns from the previous feasibility review. The fundamental strategic shift -- from "delete worktree code and replace with zerg" to "fix worktree bugs, deprecate, replace only after zerg is proven" -- eliminates the most dangerous failure mode (capabilities gap with no rollback). The integration redesign around CLI/subprocess invocation rather than a non-existent Python API is sound and realistic.

Three new concerns are noted below, all Minor severity. None block implementation.

---

## Resolved

### C1 -- Zerg Python API assumptions (Critical, now Resolved)

**Original finding:** The plan assumed `from zerg import ZERGOrchestrator, TaskGraph, WorkerPool` which does not exist. The entire P1.1 implementation was built on a non-existent Python API.

**Resolution:** The revised plan explicitly abandons the Python API assumption. Key changes:

1. **Assumption 4** (line 63) is rewritten: "The integration point is CLI/subprocess invocation (`zerg rush`, `zerg status`, etc.), NOT a Python import."
2. **P0.0** (lines 676-694) adds a mandatory evaluation task that installs zerg, inspects the actual CLI surface, documents the real interface, and determines the viable integration path before any integration code is written.
3. **P1 is gated on P0.0 results** (line 798): "P1 tasks should NOT begin until P0.0 is complete and the zerg evaluation confirms a viable integration path."
4. The new `scripts/zerg-adapter.sh` design (lines 357-390) encapsulates all zerg interaction behind a shell script interface (`detect`, `validate`, `execute`, `status`), making the actual zerg invocation method an implementation detail of the adapter.

This is a thorough resolution. The plan no longer assumes any specific API exists and includes a dedicated evaluation step to discover the real interface before committing to implementation.

---

### C2 -- Task-graph.json schema was invented, not adopted from zerg (Critical, now Resolved)

**Original finding:** The plan defined a custom task-graph.json schema and presented it as "the contract between `/dream` output and `/ship` execution" without verifying compatibility with zerg's native format.

**Resolution:** The revised plan explicitly declares the schema as a claude-devkit-defined contract, not zerg's schema:

1. The `$schema` value is renamed from `task-graph-v1` to `claude-devkit-task-graph-v1` (line 473), clearly signaling ownership.
2. The adapter is responsible for translating between claude-devkit's format and whatever zerg expects (line 384): "Translates claude-devkit task-graph.json to zerg's native format (determined in P0.0)."
3. The plan explicitly acknowledges divergence is expected and managed via the adapter (risk R7, line 554).
4. P0.0 includes inspecting zerg's actual task-graph format (line 685): "Inspect `.gsd/specs/` directory for task-graph format."

This is a clean resolution. By owning the schema and delegating translation to the adapter, the plan avoids the fragility of depending on an undocumented external format while still enabling interoperability.

---

### M1 -- Version discrepancy: /dream 2.1.0 vs 2.0.0 in docs (Major, now Resolved)

**Original finding:** CLAUDE.md Skill Registry shows `/dream` at v2.0.0 while the actual `skills/dream/SKILL.md` is v2.1.0.

**Resolution:** P0.3 (lines 777-795) now explicitly reconciles the discrepancy:
- Step 1: "Update Skill Registry `/dream` version to 2.1.0"
- The plan notes (line 501): "CLAUDE.md Skill Registry currently shows v2.0.0 but actual SKILL.md is v2.1.0. P0.3 reconciles this before the v2.2.0 bump."
- The librarian findings resolution matrix (line 1307) confirms: "P0.3 reconciles CLAUDE.md to 2.1.0 before P1.1 bumps to 2.2.0."

This creates a clean version audit trail: 2.0.0 (documented) -> 2.1.0 (reconciled in P0.3) -> 2.2.0 (bumped in P1.1).

---

### M2 -- Claim that worktree code "never passed integration test" was inaccurate (Major, now Resolved)

**Original finding:** The plan claimed no tests existed, but `test_ship_worktree.sh` has 847 lines with 6 test scenarios.

**Resolution:** The revised plan acknowledges the test suite throughout:
- Line 120-121: "The worktree code has a test suite (`test_ship_worktree.sh`, 847 lines, 6 test scenarios) that validates the isolation logic."
- Line 137: "generators/test_ship_worktree.sh -- replaced by zerg integration tests" is moved to P3.1 (future), not deleted in P0.
- The verification steps (line 1158) include: "Worktree tests pass (NOT deleted -- still needed)."
- The resolution matrix (line 1325) explicitly addresses the finding.

The revised characterization is factually accurate.

---

### M3 -- Ambiguity about what to remove in Step 5 conditional (Major, now Resolved)

**Original finding:** The original plan's P0.1 step 4 said to remove `git reset --soft HEAD~1` but was ambiguous about whether to remove just the command or the entire conditional block.

**Resolution:** This concern is no longer applicable. The revised plan retains the worktree code (including the `git reset --soft HEAD~1` conditional in Step 5), fixes the bugs, and marks it as deprecated rather than deleting it (line 1299): "No longer applicable -- `git reset` stays as part of worktree flow."

Confirmed by reading `skills/ship/SKILL.md`: Step 5 (lines 489-492) still contains the conditional block "If shared deps were committed in Step 2a: Soft reset to combine with final commit" followed by the `git reset --soft HEAD~1`. This block remains valid because Step 2a still exists in the worktree path.

---

### M4 -- Removing Pattern 11 loses documentation about why file isolation matters (Major, now Resolved)

**Original finding:** Deleting the entire Worktree Isolation Pattern section from CLAUDE.md would lose architectural reasoning about why file isolation matters for parallel work.

**Resolution:** Pattern 11 is now deprecated with a note rather than deleted (line 786): "Pattern 11 (Worktree Isolation): Add deprecation note: 'Deprecated in /ship v3.2.0. Will be replaced by external orchestrator integration (zerg or Anthropic Swarms) in v4.0.0.'" The pattern section header count is also fixed from "10 patterns" to "11 patterns" (line 785).

This preserves the architectural documentation while signaling the planned migration path.

---

### M5 -- Path traversal check would reject ~/projects/ paths (Major, now Resolved)

**Original finding:** Existing generators enforce target directory must be under `~/workspaces/` or `/tmp/`, which would reject typical project directories.

**Resolution:** The revised plan explicitly documents the deviation and its rationale (lines 347-351):
- "Target directory: Accepts any writable directory (unlike skill generator which restricts to `~/workspaces/`)."
- "Rationale: zerg config lives in project directories, not in claude-devkit."

The resolution matrix (line 1328) confirms the finding was addressed with documented justification.

---

### M6 -- Test coverage gaps (Major, now Resolved)

**Original finding:** The test plan had gaps: no negative tests for zerg detection, no strict-mode validation, and critical tests were manual-only.

**Resolution:** The revised plan addresses all three sub-concerns:

1. **Adapter-based tests added:** The `scripts/zerg-adapter.sh` provides testable commands (`detect`, `validate`) that can be exercised in automated tests (lines 599-604). P1.4 (lines 936-955) creates `generators/test_zerg_integration.sh` with 8-10 tests covering schema validation, cycle detection, file ownership, and both found/not-found detection paths.

2. **Strict-mode validation added:** The P1.4 test coverage list (line 939-940) specifies: "/ship SKILL.md validates after changes (strict mode)" and "/dream SKILL.md validates after changes (strict mode)."

3. **Automated/manual distinction clarified:** The test matrix (lines 658-667) clearly labels which scenarios are automated versus manual. The two manual scenarios (zerg parallel execution, zerg mid-execution failure) are the ones that genuinely require a live Claude Code session with zerg installed -- this is an acceptable trade-off.

4. **Cycle detection test:** An explicit cycle detection test is included (lines 609-633) with a concrete test fixture and expected output.

---

## Remaining

No concerns from the previous review remain unresolved.

---

## New Concerns

### N1. P0.1 bug fix verification may overstate work remaining (Minor)

The P0.1 task breakdown (lines 699-740) lists all 6 critical bugs from the code review, but then notes (lines 716-719): "Review of the actual v3.1.0 SKILL.md shows that many of the code review's critical bugs were already addressed in the v3.1.0 implementation (the code review may have been against an earlier draft)."

Reading the actual `skills/ship/SKILL.md` (v3.1.0) confirms this. The current code at:
- Step 2b (lines 145-188): Already uses `${name}`, `${wg_num}`, `${wg_name}`, `${scoped_files}` template variables with coordinator instructions, has error handling with `if ! git worktree add`, and cleans up `.ship-worktrees.tmp` on failure.
- Step 2d (lines 240-303): Already uses `sed 's|^\./||'` normalization and exact path matching in a loop.
- Step 2f (lines 338-361): Already tracks `CLEANUP_FAILURES` and reports without blocking.

The plan correctly identifies this situation but phrases P0.1 as "Fix 6 critical bash bugs" in the heading while the body says "Verify all 6 critical bug fixes are correctly implemented." The heading may create confusion about the actual scope of work. The task is more accurately described as "verify and finalize" rather than "fix."

**Impact:** Low. The steps (lines 732-739) are correctly scoped as verification with conditional fixing. An implementer reading the full task will understand the actual scope.

**Recommended adjustment:** Consider updating the P0.1 heading from "Fix 6 critical bash bugs" to "Verify 6 critical bash bug fixes and add deprecation warning" for accuracy.

---

### N2. The zerg adapter shell script has an implicit dependency on jq or Python for JSON operations (Minor)

The adapter design (lines 357-390) specifies four commands: `detect`, `validate`, `execute`, `status`. The `validate` command must parse JSON (task-graph.json), validate schema structure, check exclusive file ownership, and detect cycles in the dependency graph. The `execute` command must translate the claude-devkit task-graph to zerg's native format and parse zerg's output.

These operations -- JSON parsing, graph cycle detection, schema validation -- are non-trivial to implement in pure bash. The adapter will require either `jq` (an external dependency not currently in the project's dependency list) or delegation to `python3` for JSON processing.

The plan does not explicitly state which JSON processing approach the adapter will use. The existing project has no `jq` dependency, but does use `python3` extensively in generators.

**Impact:** Low. The implementer will naturally choose the appropriate tool when building the adapter. Since `python3` is already a project dependency (generators require it), using `python3 -c "..."` or a small Python helper script within the shell adapter is the path of least resistance.

**Recommended adjustment:** Add a note to the P1.2 adapter specification that JSON processing should use `python3` (already a project dependency) rather than introducing `jq` as a new dependency.

---

### N3. The version bump strategy creates a non-standard semver transition (Minor)

The plan proposes `/ship` v3.2.0 for the bug fixes + deprecation + zerg detection (P0-P1), then `/ship` v4.0.0 for worktree code removal (P3.1). However, the v3.2.0 release adds a new execution path (zerg parallel) which, while opt-in and non-breaking, is a significant feature addition. Standard semver would suggest v3.2.0 for bug fixes only and v3.3.0 or higher for the zerg execution path feature.

The plan bundles the bug fixes (P0.1), zerg detection (P0.2), and zerg execution path (P1.2) all under v3.2.0. This means the v3.2.0 version covers changes spanning weeks of work across multiple priority tiers.

**Impact:** Minimal. The project does not appear to have external consumers who depend on semver for upgrade decisions. This is an internal toolkit.

**Recommended adjustment:** Consider splitting into v3.2.0 (P0 -- bug fixes and deprecation warning) and v3.3.0 (P1 -- zerg execution path). This would give a clean version to deploy and validate after P0 before the more complex P1 changes land. The frontmatter would be updated twice, which is trivial.

---

## Implementation Complexity Re-Assessment

| Task | Rev 1 Assessment | Rev 2 Assessment | Change |
|------|------------------|-------------------|--------|
| P0.0 (Evaluate zerg) | Not in Rev 1 | Low risk. Install, inspect, document. | New task, well-scoped |
| P0.1 (Fix worktree bugs) | "under an hour" (was deletion) | Lower risk than Rev 1. Most bugs already fixed in v3.1.0 -- work is verification + deprecation warning + version bump. | Reduced scope, reduced risk |
| P0.2 (Zerg detection) | Part of P0 week | Low risk. Adapter-based detection is cleaner than inline `pip show`. | Improved design |
| P0.3 (CLAUDE.md reconciliation) | Not in Rev 1 | Low risk. Documentation updates only. | New task, straightforward |
| P1.1 (Dream task-graph) | Was P0.3, Medium risk | Medium risk. Same scope but now gated on P0.0 evaluation results. The gate reduces risk of building on wrong assumptions. | Risk reduced by evaluation gate |
| P1.2 (Ship zerg execution path) | Was P1.1, High risk | Medium risk. CLI/subprocess design is more realistic than Python API. Adapter encapsulation limits blast radius. | Significantly reduced risk |
| P1.3 (generate_zerg_config.py) | Was P1.2, Realistic | Realistic. Now includes explicit atomic writes, input validation, and rollback requirements. | Better specified |
| P1.4 (Test suites) | Was P1.3, Realistic | Realistic. Standalone test suite with clear scope. | Similar |

The overall implementation risk has decreased from Medium-High (Rev 1) to Medium-Low (Rev 2), primarily because:
1. The capabilities gap is eliminated (worktree code is fixed, not deleted).
2. The integration design is based on a realistic interface assumption (CLI, not Python API).
3. P0.0 evaluation provides a go/no-go gate before committing to integration work.
4. The adapter pattern limits the blast radius of zerg API instability.

---

## Files Correctly Identified

The revised plan accurately identifies all files requiring modification:

- `/Users/imurphy/projects/claude-devkit/skills/ship/SKILL.md` -- Confirmed: v3.1.0, contains worktree code at Steps 2a-2f that will be verified/fixed and marked deprecated. Version bump to 3.2.0. Zerg detection and execution path to be added.
- `/Users/imurphy/projects/claude-devkit/skills/dream/SKILL.md` -- Confirmed: v2.1.0, task-graph generation to be added to Step 1 in P1.1. Version bump to 2.2.0.
- `/Users/imurphy/projects/claude-devkit/CLAUDE.md` -- Confirmed: version discrepancies exist (dream at 2.0.0 vs actual 2.1.0, pattern count header says 10 but table has 11). P0.3 reconciles these.
- New files correctly scoped: `scripts/zerg-adapter.sh`, `generators/generate_zerg_config.py`, `configs/zerg-integration.json`, `CHANGELOG.md`, `plans/zerg-evaluation.md`.
- Unchanged files correctly marked: `skills/audit/SKILL.md`, `skills/sync/SKILL.md`, `generators/generate_skill.py`, `generators/validate_skill.py`, `generators/generate_agents.py`.

---

## Cross-Review Alignment

The revised plan includes an Appendix (lines 1281-1330) that maps every Critical and Major finding from all three reviews (red team, librarian, feasibility) to its resolution. I have verified this matrix against my original findings and confirm:

- All 2 Critical findings (C1, C2) are resolved as described.
- All 6 Major findings (M1-M6) are resolved as described.
- All 5 Minor findings (N1-N5) from the original review are addressed (N2 about recursive skill invocation is now in the Security Considerations section, N4 about the three-way routing is now covered by an explicit truth table in P2.1).

The resolution matrix also correctly maps the red team's 13 findings and the librarian's 7 conflicts + 3 factual inaccuracies to specific plan changes. This level of traceability is commendable.

---

## Summary

The Revision 2 plan is a substantial and well-executed rework. The strategic pivot from "delete and replace" to "fix, deprecate, and replace when proven" is the correct call given the high vendor risk (25 stars, single maintainer, 16 days old, pre-1.0). The CLI/subprocess integration design is realistic and testable. The P0.0 evaluation gate prevents committing to integration work before the actual zerg interface is known.

The three new minor concerns (P0.1 heading accuracy, adapter JSON dependency, semver transition) are non-blocking and can be addressed during implementation.

---

**Reviewed by:** code-reviewer (feasibility re-review)
**Review timestamp:** 2026-02-23T17:30:00Z
**Files reviewed:**
- `plans/zerg-adoption-priorities.md` (Revision 2, 1330 lines)
- `skills/ship/SKILL.md` (v3.1.0, 526 lines)
- `skills/dream/SKILL.md` (v2.1.0, 151 lines)
- `plans/zerg-adoption-priorities.feasibility.md` (previous review, 225 lines)
- `plans/zerg-adoption-priorities.redteam.md` (red team review, 356 lines)
- `plans/zerg-adoption-priorities.review.md` (librarian review, 145 lines)
- `plans/ship-v3.1-code-review.md` (code review, partial)
- `CLAUDE.md` (project rules, 907 lines)
