# Red Team Review (Round 2): Add Code Anti-Pattern Reviewer to /audit

**Reviewed:** 2026-08-21
**Plan:** `.devkit/plans/add-anti-pattern-reviewer.md`
**Revision reviewed:** 2026-08-21 (revised plan addressing Round 1 findings)
**Reviewer:** Red team (adversarial analysis, Round 2 re-review)

---

## Verdict: PASS

All Round 1 Major findings are resolved. All Minor findings are addressed. No new Critical or Major findings introduced by the revision.

---

## Round 1 Finding Resolutions

### Finding 1 -- Plan scope noise (6 of 8 code-level categories ran for plan scope)

**Original severity:** Major
**Status:** RESOLVED

The revised plan skips the anti-pattern scan entirely for `plan` scope (lines 13, 55-56, 125-127). The Trigger line reads: "Only run if scope is `code` or `full` (skip for `plan`)." This matches the existing QA regression step pattern (confirmed in `skills/audit/SKILL.md` line 276). The rationale is explicit: "six of seven anti-pattern categories are code-level concerns that cannot be detected in a plan document" (Assumption 5, line 34). Clean resolution.

---

### Finding 2 -- Complexity overlap with existing performance scan (double-counting risk)

**Original severity:** Major
**Status:** RESOLVED

The revised plan removes the "Complexity violations" category entirely, reducing the category count from eight to seven (lines 13, 62). The Non-Goals section explicitly states: "Not duplicating complexity analysis. The existing performance scan already covers algorithm complexity (O(n^2) analysis, cyclomatic complexity). The anti-pattern scan excludes complexity violations to avoid double-counting findings in the synthesis step" (line 26). The subagent prompts additionally include boundary guidance: "Do not flag error handling or architectural issues that are primarily security vulnerabilities (those belong in the security scan)" (lines 142, 165). Both the structural removal and the prompt-level boundary are in place.

---

### Finding 3 -- Critical severity over-calibrated (god classes)

**Original severity:** Minor
**Status:** RESOLVED

God classes downgraded from Critical to High (line 76). Critical is now reserved exclusively for "Dead code that masks security vulnerabilities" with a high evidentiary bar: "the finding must identify both the dead code and the specific vulnerability it masks" (line 75). The severity mapping is now proportionate -- a 501-line utility class no longer triggers BLOCKED at the same level as a SQL injection.

---

### Finding 4 -- Sequential latency acknowledgment

**Original severity:** Minor
**Status:** RESOLVED

The Deviations from Established Patterns section (lines 330-331) explicitly documents the archetype deviation: "The CLAUDE.md Scan Pattern archetype describes 'Runs parallel analysis tasks' as a core characteristic, but the existing `/audit` skill runs Steps 2-4 (security, performance, QA) sequentially. This plan adds a fourth sequential scan (Step 4, anti-pattern), inheriting the pre-existing deviation." The Non-Goals section (line 25) adds: "Steps 2-4 are designed to be independent (no cross-step data dependencies), enabling future parallelization without structural changes." Both the deviation acknowledgment and the forward-compatibility note are present.

---

### Finding 5 -- Test depth

**Original severity:** Minor
**Status:** RESOLVED

The test plan expanded from 3 to 6 structural tests (lines 251-268). The three new tests cover the renamed step identifiers (`step_5_qa_regression`, `step_6_synthesis`, `step_7_gate`), directly addressing the Round 1 recommendation. The tests use `grep -q` existence checks rather than count-based `grep -c >= 2` verification, which is consistent with every other test in `test-integration.sh`. Adopting the established test convention is acceptable.

---

### Finding 6 -- Test count arithmetic is wrong

**Original severity:** Minor
**Status:** RESOLVED

The revised plan correctly identifies 54 actual `run_test` invocations (confirmed via `grep -c 'run_test' scripts/test-integration.sh` = 54) and notes the header comment says 55 -- a pre-existing discrepancy. The arithmetic is now correct: 54 + 6 = 60. The plan commits to fixing the pre-existing discrepancy by setting the header to 60 (line 269, acceptance criterion 12).

---

### Finding 7 -- Missing artifact archival update

**Original severity:** Minor
**Status:** RESOLVED

The revised plan adds CLAUDE.md artifact location updates in three places: Goal 4 (line 16), acceptance criterion 8 (line 291), and Work Group 2 description (line 313), all specifying `audit-[timestamp].antipatterns.md` in the Artifact Locations tree.

---

## New Findings

### Finding N1 -- Implementation detail ordering inconsistency with Trigger specification

**Severity: Info**

The step specification defines the Trigger at the top: "Only run if scope is `code` or `full` (skip for `plan`)" (line 56). The Implementation Detail section (lines 120+) shows step_start audit event emission (line 121) followed by the scope check (line 125). In the existing QA regression step (`skills/audit/SKILL.md` line 276-284), the Trigger line precedes the step_start emission, meaning the entire step -- including audit events -- is skipped for plan scope.

The plan's Trigger specification is correct and matches the existing pattern. The Implementation Detail section's ordering (emit first, check second) is slightly inconsistent with that intent, but since the Trigger line controls the overall behavior and the Implementation Detail is guidance for the implementer, this has no practical impact. The implementer should follow the existing QA regression ordering: Trigger check first, then audit event emission.

Not actionable -- implementation-time concern only.

---

## Summary

| Category | Count | Details |
|----------|-------|---------|
| Round 1 Major findings | 2/2 RESOLVED | Plan scope skip (#1), Complexity removal (#2) |
| Round 1 Minor findings | 5/5 RESOLVED | Severity calibration (#3), Latency acknowledgment (#4), Test depth (#5), Test count (#6), Artifact archival (#7) |
| New Critical/Major findings | 0 | -- |
| New Minor findings | 0 | -- |
| New Info findings | 1 | Implementation detail ordering (#N1) |

The revision is thorough and well-crafted. All Major findings are cleanly resolved (scope skip and complexity removal), all Minor findings are addressed with explicit plan text and acceptance criteria, and no new issues of substance were introduced. The plan is ready for implementation.
