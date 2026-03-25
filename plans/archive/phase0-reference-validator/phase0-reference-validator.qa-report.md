# QA Report: Phase 0 -- Reference Archetype Validator Support + Rollback Mechanism

**Plan:** `plans/phase0-reference-validator.md`
**QA Date:** 2026-03-08
**QA Agent:** qa-engineer
**Verdict:** PASS_WITH_NOTES

---

## Acceptance Criteria Coverage

| # | Criterion | Met? | Evidence |
|---|-----------|------|----------|
| 1 | `validate_skill.py` accepts `type: reference` in frontmatter and skips inapplicable checks (numbered steps, verdict gates, inputs section, workflow header, minimum steps) | MET | Reference fixture without model validated with exit 0. Code at lines 457-463 gates standard checks behind `if is_reference` branch. |
| 2 | `validate_skill.py` exits 0 for a valid Reference skill without a `model` field | MET | Manual fixture test (no model field) returned exit 0. Test 27 in suite passes. |
| 3 | `validate_skill.py` exits 0 for a valid Reference skill with a `model` field (optional but accepted) | MET | Manual fixture test (with model field) returned exit 0. Test 27b in suite passes. |
| 4 | `validate_skill.py` exits non-zero for Reference skills missing required frontmatter fields (`attribution`, `version`, `type`) | MET | Test 28 (missing attribution) passes with non-zero exit. Manual test of missing `version` returned exit 1. `type` is inherently present since it triggers the Reference path. |
| 5 | `validate_skill.py` exits non-zero for Reference skills with empty body | MET | Test 29 passes with non-zero exit. |
| 6 | `validate_skill.py` exits non-zero for Reference skills without a core principle heading (Law/Principle/Rule/Gate) | MET | Test 30 passes with non-zero exit. Fixture uses headings "Overview" and "Details" which correctly fail. |
| 7 | Existing Pipeline/Coordinator/Scan skills (dream, ship, audit, sync, test-idempotent) continue to validate without changes | MET | All 5 production skills validated with exit 0 (warnings only, no errors). Tests 3-6 in suite also pass. |
| 8 | `configs/skill-patterns.json` contains `archetypes.reference` definition with all required fields including `requires_model: false` | MET | JSON parses successfully. `archetypes.reference` contains all 9 fields specified in the plan: `description`, `required_frontmatter`, `required_sections`, `core_principle_patterns`, `requires_numbered_steps`, `requires_tool_declarations`, `requires_verdict_gates`, `requires_artifacts`, `requires_inputs_section`, `requires_workflow_header`, `requires_model`. All boolean flags are `false`. `required_frontmatter` omits `model`. |
| 9 | `deploy.sh --undeploy <name>` removes the skill directory from `~/.claude/skills/` | MET | Test 31 creates directory, runs undeploy, verifies removal. Manual test also confirmed. |
| 10 | `deploy.sh --undeploy` rejects skill names containing `/`, `..`, or starting with `-` | MET | Manual tests: `../../../tmp` rejected with "ERROR: Invalid skill name", `--flag-name` rejected with "ERROR: Invalid skill name". Both return exit 1. |
| 11 | `deploy.sh --undeploy --contrib <name>` removes contrib skill directory | MET | Manual test created `~/.claude/skills/test-contrib-undeploy`, ran `--undeploy --contrib test-contrib-undeploy`, verified directory removed with exit 0. |
| 12 | `deploy.sh --undeploy` on a nonexistent skill exits cleanly (idempotent) | MET | Test 32 passes. `undeploy_skill()` prints WARN to stderr and returns 0. |
| 13 | `deploy.sh --help` documents the `--undeploy` flag and notes the permission prompt | MET | Help output includes both `--undeploy <name>` and `--undeploy --contrib <name>` with "(triggers permission prompt)" note. |
| 14 | Test suite extended to 33 tests and all pass | MET | Suite reports "Total: 33, Pass: 33, Fail: 0". All tests pass. |

**Result: 14/14 criteria met.**

---

## Test Execution Summary

| Test Category | Result |
|---------------|--------|
| Full test suite (33 tests) | All 33 PASS |
| Production skill regression (5 skills) | All 5 PASS (warnings only) |
| Manual Reference fixture (no model) | PASS, exit 0 |
| Manual Reference fixture (with model) | PASS, exit 0 |
| Manual Reference fixture (missing version) | PASS, exit 1 (correctly rejected) |
| JSON output for Reference skill | PASS, valid JSON with `"passed": true` |
| Undeploy path traversal (`../../../tmp`) | PASS, rejected with error |
| Undeploy flag-like name (`--flag-name`) | PASS, rejected with error |
| Undeploy --contrib path | PASS, directory removed |
| deploy.sh --help | PASS, --undeploy documented |

---

## Notes (non-blocking observations)

### 1. Test numbering gap at test 26

The test suite jumps from Test 25 to Test 27, with no Test 26. The plan specified renumbering the old Test 26 (Cleanup) to Test 33, but the gap was left unfilled. Instead, Test 27b (Reference skill with model) was added as a sub-test to compensate, bringing the total to 33. This is cosmetically inconsistent but functionally correct -- the total count is accurate and all tests execute.

### 2. `--undeploy --contrib` routes to the same `undeploy_skill()` function

The plan specifies `--undeploy --contrib <name>` as a separate path, but both `--undeploy <name>` and `--undeploy --contrib <name>` call the same `undeploy_skill()` function targeting `$DEPLOY_DIR/$skill`. This is correct behavior since contrib and core skills deploy to the same `~/.claude/skills/` directory. The `--contrib` flag in the undeploy context is purely for user intent clarity, not a functional difference. This matches the plan's description: "(same target, contrib context)".

### 3. No `--strict` mode test for Reference skills

The test suite does not test `--strict` mode with Reference skills. Since Reference skills produce no warnings in the current implementation, this is not a gap in practice, but could become relevant if warning-level checks are added to Reference validation in the future.

### 4. `validate_frontmatter` model warning still applies to Reference skills

If a Reference skill includes a `model` field with an unrecognized value (e.g., `model: invalid-model`), the validator will emit a warning (not an error). This is correct behavior -- model is optional but validated when present.

---

## Missing Tests or Edge Cases

| Edge Case | Risk | Recommendation |
|-----------|------|----------------|
| Reference skill with unknown `type` value (e.g., `type: unknown`) | Low | Currently emits warning, not error. Covered by `validate_frontmatter` type validation logic but not explicitly tested in the suite. Consider adding in a future test expansion. |
| `--undeploy` with empty string argument | Low | The bash `set -euo pipefail` and argument count check should handle this, but it is not explicitly tested. |
| Reference skill with `model` field set to an invalid value | Low | Would produce a warning but still pass. Not tested but correct behavior per design. |
| Concurrent undeploy operations | Very Low | Not applicable for single-user CLI tool. |

None of these are blocking. The implementation covers all acceptance criteria and the test suite is comprehensive for the defined scope.

---

## Files Validated

- `/Users/imurphy/projects/claude-devkit/generators/validate_skill.py`
- `/Users/imurphy/projects/claude-devkit/configs/skill-patterns.json`
- `/Users/imurphy/projects/claude-devkit/scripts/deploy.sh`
- `/Users/imurphy/projects/claude-devkit/generators/test_skill_generator.sh`
