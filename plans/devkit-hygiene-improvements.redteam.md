# Red Team Review: Devkit Hygiene Improvements (Round 2)

**Reviewed:** 2026-03-27
**Plan:** `plans/devkit-hygiene-improvements.md` (Rev 2)
**Reviewer:** Red Team (critical analysis)
**Round:** 2 (reviewing revisions to address Round 1 findings)

## Verdict: PASS

No Critical findings. One Minor finding carried forward (partially resolved). Two new Minor findings from the revisions. Overall, the Rev 2 changes substantially improved the plan.

---

## Round 1 Findings Resolution

### Finding #1 (Major): Integration test modifies the live source tree under `skills/`

**Status: Resolved.**

Rev 2 addressed this comprehensively:

1. The integration test (WG-3) no longer creates temporary directories in the real `skills/` directory. Rev 1's `skills/smoke-invalid/` test was removed entirely. The integration tests now only create artifacts in `/tmp/` and `~/.claude/skills/` (the deployment target), never in the source tree.

2. The unit test (WG-1, Test 48) still creates a temporary directory in the real `skills/` directory (`skills/test-validate-invalid/`), which is inherent to what it's testing (that `deploy.sh --validate` rejects an invalid skill). However, Rev 2 adds a `trap cleanup_on_exit EXIT INT TERM` handler at the script top (lines 136-139 of the plan) plus explicit `rm -rf` after the test. This is a belt-and-suspenders approach that handles SIGINT and SIGTERM. Only SIGKILL (untrappable) would leave the stale directory, which is an acceptable residual risk.

3. The stale directory risk to `deploy_all_core()` and `validate-all.sh` is substantially mitigated. If a stale directory were to persist (SIGKILL scenario), `deploy.sh` without `--validate` would deploy the garbage file (copying `# No frontmatter` to `~/.claude/skills/test-validate-invalid/SKILL.md`), and `validate-all.sh` would fail on it. However, the trap handler makes this scenario very unlikely, and the directory name `test-validate-invalid` is clearly identifiable as a test artifact for manual cleanup.

**Assessment:** The mitigation is proportionate to the risk. Resolved.

### Finding #2 (Major): Test count discrepancy -- plan claims 46 tests but numbering has gaps

**Status: Resolved.**

Rev 2 addressed this thoroughly:

1. The "Current state" section (line 24) now accurately documents: "44 tests at runtime" with detailed explanation of the gaps (numbers 26, 33, 35 skipped; 27b is a string label; conditional contrib tests 43-45 may reduce count further).

2. The "Total test count after expansion" line (130) correctly states: "Up to 47 runtime tests (44 existing + 3 new deploy-validate tests; Test 49 is conditional)."

3. The header comment update is included as an acceptance criterion (WG-1, line 406): "Test suite header comment updated to reflect accurate test inventory."

**Assessment:** The plan now accurately represents the test counting reality. Resolved.

### Finding #3 (Minor): Settings precedence fix may exist in other skills

**Status: Resolved.**

I verified via search that the `security_maturity` settings-reading pattern exists only in `skills/ship/SKILL.md`. No other skill reads `.claude/settings.local.json` or `.claude/settings.json` for this field. The bug is isolated. The plan's Non-Goal of "Modifying any skill other than `skills/ship/SKILL.md`" is justified.

### Finding #4 (Minor): Improvement numbering is non-sequential (#4, #5, #7, #8)

**Status: Resolved.**

Rev 2 added a "Numbering note" at line 21 explaining that numbers are inherited from the portfolio review where items #1-#3 and #6 were addressed in the agentic-sdlc-next-phase plan. Clear and sufficient.

### Finding #5 (Minor): Integration test duplicates unit test coverage

**Status: Resolved.**

Rev 2 replaced the duplicate Tests 3-4 in the integration suite with genuinely different tests: a full generate-validate-deploy-undeploy lifecycle (Test 3) and a meta-test that runs the entire unit suite (Test 4). The explanation at line 252 documents the rationale. No duplication remains.

### Finding #6 (Minor): `set -e` conflicts with `run_test()` error handling

**Status: Not explicitly addressed, but acceptable.**

The integration test still uses `set -e` globally with `set +e` inside `run_test()`. However, since the Rev 2 integration test no longer modifies the source tree, the consequence of a setup failure under `set -e` is limited to leaving artifacts in `/tmp/` and `~/.claude/skills/smoke-*`, both of which are cleaned by the trap handler. The risk is now proportionate. This is an established pattern in the existing test suite.

### Finding #7 (Minor): `deploy.sh --validate` flag order not tested

**Status: Not addressed, acceptable.**

No reversed-order test was added. This is a low-probability issue (the pre-processing loop is order-independent by design) and would be caught during `deploy.sh` refactoring. Not worth blocking.

---

## New Findings

### N1. Integration test meta-test (Test 4) makes the integration suite slow and recursive

**Severity: Minor**

Integration Test 4 runs `bash '$REPO_DIR/generators/test_skill_generator.sh'` -- the entire unit test suite -- from within the integration test. This means:

1. **Runtime cost:** The unit suite takes a non-trivial amount of time (generates skills, validates all 13+ core skills, validates contrib skills). Running it as a sub-test of the integration suite means the integration test takes at least 2x the unit test time (its own tests + the embedded unit run). For a developer running both suites sequentially (as the Test Plan section recommends), the unit suite runs twice.

2. **Nested failure attribution:** If the unit suite fails inside the integration test, the integration test reports "Test 4: FAIL" with no output (the `run_test()` function suppresses all output via `> /dev/null 2>&1`). The developer must then re-run the unit suite separately to diagnose the failure. The meta-test adds runtime cost without adding diagnostic value.

3. **Circular dependency risk:** If someone adds the integration test as a pre-commit check, it transitively runs the entire unit suite. If the unit suite is also a pre-commit check, it runs twice. The plan does not document this relationship.

This is not blocking -- the test is optional and can be removed without affecting coverage -- but the cost-benefit ratio is unfavorable. Consider replacing Test 4 with a lighter-weight validation (e.g., verify `test_skill_generator.sh` exists and is executable) or simply removing it and noting in the integration test header that the unit suite should be run separately.

### N2. Trap handler in `test_skill_generator.sh` interferes with the existing cleanup test (Test 50)

**Severity: Minor**

The plan adds a trap handler at the script top:

```bash
trap cleanup_on_exit EXIT INT TERM
```

The `cleanup_on_exit` function removes `skills/test-validate-invalid/`. This is correct for interruption safety. However, the trap fires on `EXIT` -- which means it fires when the script completes normally, including after Test 50 (cleanup). This is benign for the `test-validate-invalid` directory (it's already cleaned up by the explicit `rm -rf` after Test 48).

But the existing script also has Test 50 (renumbered from 46) which cleans up `$TEST_DIR` (`/tmp/sg-test`). The trap handler does NOT clean up `$TEST_DIR`. This means: if the script is interrupted between Test 1 and Test 48 (before any `test-validate-invalid` directory is created), the trap fires but does not clean up `/tmp/sg-test`. The trap handler only protects against the specific stale directory introduced by Test 48, not against the general test directory.

This is fine as designed (the trap's purpose is specifically to prevent source tree contamination), but it means `$TEST_DIR` (`/tmp/sg-test`) will persist on interruption. This is the existing behavior and is low-risk since `/tmp/` is cleaned by the OS. No action required, but worth noting that the trap handler's scope is intentionally narrow.

### N3. `$BOLD` variable undefined in test_skill_generator.sh

**Severity: Info**

The existing `test_skill_generator.sh` uses `${BOLD}` at line 505 in the "Test Summary" header, but never defines a `BOLD` variable. The plan's proposed integration test (`scripts/test-integration.sh`) does not replicate this bug -- it uses no `BOLD` reference. This is a pre-existing issue unrelated to the plan, noted for completeness. The plan does not introduce the same defect in the new script.

### N4. CLAUDE.md normalization deferred but not tracked

**Severity: Info**

The plan notes at line 302: "the three test count references -- currently showing 46 and 45 inconsistently -- must be normalized to the correct post-expansion count in a follow-up `/sync` pass." This is sensible (CLAUDE.md updates should happen after implementation, not speculatively). However, there is no tracking mechanism to ensure this follow-up actually happens. It is not listed in the acceptance criteria, the test plan, or any work group. The risk is that CLAUDE.md continues to show "46 tests" after the suite expands to 47+. A one-line note in the "Post-implementation" section or a task tracking entry would close this loop.

---

## Summary

The Rev 2 plan is substantially improved over Rev 1. All four Major findings from Round 1 were adequately addressed:

- The source-tree contamination risk (Finding #1) is mitigated with trap handlers
- The test count discrepancy (Finding #2) is accurately documented
- The duplicate integration tests (Finding #5) were replaced with unique tests
- The numbering gap (Finding #4) is explained

The two new Minor findings (N1: meta-test performance, N2: trap scope) are worth considering during implementation but are not blocking. The plan is ready for implementation.
