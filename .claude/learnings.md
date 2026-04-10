# Project Learnings

Last updated: 2026-04-08 (threat-model-consumption)

Source: `/retro` skill — mines archived code review and QA artifacts for recurring patterns.
Consumed by: `/ship` Step 2 (pattern validation) and coder/reviewer agents.

---

## Reviewer Patterns

### Consistently caught

- **Checklist-driven content verification** [Medium] — Reviewers using explicit, grep-verifiable checklists produce reviews that QA can independently reproduce. More reliable than impressionistic assessment. Seen in: receiving-code-review, phase0-reference-validator. #reviewer #process (2026-03-12)

- **Backward-compatibility regression check** [High] — Verifying that adjacent production skills still validate after infrastructure changes catches regressions early. Seen in: phase0-reference-validator, audit-remove-mcp-deps. #reviewer #regression (2026-03-12)

- **Security input sanitization verification** [High] — Confirming path traversal and flag injection rejection prevents shell injection vectors from going unverified. Seen in: phase0-reference-validator. #reviewer #security (2026-03-12)

- **Plan-to-implementation fidelity check** [Medium] — Explicitly verifying implementation matches the approved plan. Especially valuable for Reference archetype skills where the content IS the implementation. Seen in: receiving-code-review, phase0-reference-validator. #reviewer #fidelity (2026-03-12)

### Overcorrected

- **Self-refuted cosmetic observations** [Low] — Reviewers surface findings they immediately dismiss as acceptable ("accept the gap as cosmetic", "no action needed"). These should either be omitted or folded into Positives as design tradeoffs acknowledged. Adds noise without actionability. Seen in: phase0-reference-validator. #reviewer #noise (2026-03-12)

---

## QA Patterns

### Coverage gaps

- **Validator not executed at QA time** [High] — `validate_skill.py` listed as acceptance criterion but marked NOT VERIFIED. QA agent relied on static inspection rather than running the tool. Structural failures in the validator could merge undetected. Seen in: audit-remove-mcp-deps. #qa #coverage #validator (2026-03-12)

- **[2026-03-28] Integration/e2e tests not executed** [High] — Live skill invocation deferred out of QA with "no automated mechanism exists." No QA report shows evidence of a live smoke test. Structural review is used as a substitute, leaving runtime regressions undetected. Pattern seen again in ship-run-audit-logging: `test-integration.sh` was created but omitted the three audit-logging-specific tests (G: multi-call JSONL, H: L3 HMAC chain, J: 10+ call state persistence) that were explicitly required by the plan. The most important runtime correctness claim — that the multi-call architecture works — remained unverified by any automated test. Seen in: audit-remove-mcp-deps, receiving-code-review, security-guardrails-phase-b, devkit-hygiene-improvements, ship-run-audit-logging. #qa #coverage #integration (2026-03-28)

- **Full test suite skipped** [Medium] — `bash generators/test_skill_generator.sh` skipped as "long-running" in multiple features. Only phase0-reference-validator ran the full suite. Seen in: receiving-code-review, audit-remove-mcp-deps. #qa #coverage #test-suite (2026-03-12)

- **Strict mode not tested for new skill types** [Low] — `--strict` mode validation not explicitly tested for new archetypes (Reference skills). If strict-mode behavior diverges, it would go undetected. Seen in: receiving-code-review, phase0-reference-validator. #qa #coverage #strict-mode (2026-03-12)

- **[2026-03-26] New skills not added to test suite** [Medium] — When security skills were added in Phase A (`secrets-scan`, `compliance-check`, etc.), none were added to `test_skill_generator.sh`. The test suite validated only `dream`, `ship`, `audit`, and `sync`. New skills that are later modified have reduced structural safety net. Recommended action: add `validate_skill.py` invocation for each new skill to the test suite at skill creation time. Seen in: secure-review-remediation. #qa #coverage #test-suite (2026-03-26)

- **[2026-03-27] Test assertions verify exit code only, not artifact presence** [Low] — When writing deployment or generation tests, verifying exit code 0 is necessary but not sufficient. A script can return 0 without creating expected output files (e.g., due to a silent write failure or path mismatch). Pattern: after any test that should produce a file, assert `[ -f expected/path ]` as a second condition. Seen in: devkit-hygiene-improvements (test_skill_generator.sh Test 47 verifies exit 0 but not that the skill file was copied to the deploy directory). #qa #coverage #test-assertions

- **[2026-03-27] New feature flag paths not covered by automated tests** [Medium] — When a new flag or mode is added to a script (e.g., `--validate`, `--validate --contrib`), the test suite is not updated to exercise the new execution paths. Source code inspection confirms the logic is present, but no automated test verifies: (a) the flag blocks on invalid input, or (b) the flag applies correctly in all invocation combinations. Pattern: for every new CLI flag, add at minimum one positive test (flag works) and one negative test (flag correctly blocks/rejects). Seen in: agentic-sdlc-next-phase (deploy.sh `--validate` and `--validate --contrib` paths). #qa #coverage #test-suite (2026-03-27)

---

## Test Patterns

### Common failures

No recurring test failures identified (0 test failure logs found across 3 features).

### Infrastructure gaps

- **No automated gate between QA and merge** [High] — Runtime checks (validator execution, integration smoke tests, full test suite) are deferred to "Phase 3" or marked "non-blocking." No CI mechanism enforces these gates before merge. Burden falls on developer discipline. Seen in: audit-remove-mcp-deps, receiving-code-review. #test #infra #ci (2026-03-12)

---

## Coder Patterns

### Missed by coders, caught by reviewers

No recurring coder mistakes identified in early features. Both initial code reviews returned PASS with zero critical or major issues. One-off Low-severity items only (test numbering gap, hardcoded fallback patterns).

- **[2026-03-26] Stale internal step cross-references in skill documentation** [Low] — When step numbers are renumbered during development, prose and bash comments that reference other steps by number become stale. Example: Step 5a referred to "Step 2a" but the shared dependency work was in Step 3a. These label-only errors do not affect behavior but create confusion for future editors. Seen in: secure-review-remediation (ship SKILL.md Step 5a). #coder #documentation #maintenance (2026-03-26)

- **[2026-03-27] Script returns false success when expected inputs are absent** [Low] — Scripts that iterate over inputs (agents, skills, files) can silently exit 0 when the input set is empty, producing a false-positive "all passed" result. Two instances: (1) `generate_agents.py` continued past write failures and exited 0 even when agents failed to write; (2) `validate-all.sh` exits 0 with "All skills validated successfully" when no SKILL.md files are found, masking a mispointed REPO_DIR or intermediate repo state. Pattern: after any loop over expected inputs, guard with `if [ "$COUNT" -eq 0 ]; then ... exit 1; fi` before reporting success. Seen in: secure-review-remediation (generate_agents.py), agentic-sdlc-next-phase (validate-all.sh). #coder #error-handling #generators #scripts (2026-03-27)

- **[2026-03-27] Settings precedence check tests outcome rather than source** [Minor] — When implementing a local-overrides-project settings precedence rule, coders check whether the resolved value equals the default rather than tracking whether the local source actually provided a value. This silently breaks the precedence when a user intentionally sets a value that happens to match the default. Pattern: use a separate boolean flag (`LOCAL_SET=0/1`) to track whether the local source provided a value, independent of what that value is. Seen in: security-guardrails-phase-b (ship SKILL.md Step 0 security maturity check). #coder #logic #settings (2026-03-27)

- **[2026-04-08] Revision loop prose omits re-running newly added parallel check** [Minor] — When a new parallel verification step (e.g., secure-review) is added to an existing verification stage, the revision loop step that says "Re-run Step N in its entirety" is not updated to explicitly enumerate the new check. This creates ambiguity: a future editor may not realize the loop must re-run the new check, and "in its entirety" may be interpreted as referring to the original set. Pattern: when adding a parallel check to a stage, update all revision loop re-run prose to explicitly name or enumerate the new check alongside existing ones. Seen in: security-guardrails-phase-b (ship SKILL.md Step 5b), threat-model-consumption (ship SKILL.md Step 5b). #coder #documentation #revision-loop (2026-04-08)

- **[2026-03-27] Conditional branching in skill prose uses implicit else rather than explicit else guard** [Minor] — When a skill step has two mutually exclusive branches (if-found / if-not-found), the second branch is sometimes introduced without an explicit "only if the above branch was not taken" guard. An executing agent may enter the second branch after completing the first, or misread a "skip" instruction inside the first branch as an instruction that applies to a later section. Pattern: frame the second branch as an explicit else: "If not found (only execute this branch if the above branch was not taken):" or use consistent if/else framing across all conditional blocks in a skill. Seen in: security-guardrails-phase-b (audit SKILL.md Step 2). #coder #skill-authoring #control-flow (2026-03-27)

- **[2026-03-27] `rm -rf` in cleanup blocks under `set -e` without `|| true` guard** [Major] — In shell scripts running under `set -e`, a bare `rm -rf` on a path that does not exist at cleanup time causes the script to exit non-zero. When cleanup runs after the test has already passed, this produces a spurious FAIL before the summary is printed. Pattern: always append `|| true` to every `rm -rf` inside cleanup functions and trap handlers. Ensure consistency with the trap handler's own style — if the trap uses `|| true`, every manual cleanup block in the same script must also use it. Seen in: devkit-hygiene-improvements (test-integration.sh Test 5 cleanup block). #coder #bash #error-handling #cleanup (2026-03-27)

- **[2026-03-27] Variable assigned inside a test block and implicitly depended on by later tests** [Low] — In shell test suites, a variable initialized inside one test's setup block (rather than at the top-level declarations) creates a hidden dependency: if that test is ever skipped, reordered, or removed, later tests that rely on the variable will fail with an empty or unbound value. Pattern: assign script-wide variables (paths, flags, identifiers shared across tests) in the top-level declarations section alongside other globals. Reserve inline assignments for variables that are truly local to a single test. Seen in: devkit-hygiene-improvements (test_skill_generator.sh `DEPLOY_SCRIPT` assigned in Test 31 block, used by Tests 47-49). #coder #bash #test-hygiene (2026-03-27)

- **[2026-03-28] Plan-specified instrumentation points partially skipped during implementation** [Medium] — When a plan includes an explicit table of required emit/instrumentation calls per step, coders implement the first and last steps correctly but skip middle steps. In ship-run-audit-logging, the plan's instrumentation table explicitly required `step_start`, verdict, and `step_end` events for Steps 4a (code review), 4b (tests), 4c (QA), 4d (secure review), and Step 5 (revision loop) — all absent from the delivered `SKILL.md`. These were the most operationally significant events (capturing reviewer verdicts and security gate outcomes). Pattern: when a plan contains an instrumentation or event-coverage table, treat each row as a checklist item and verify each row is addressed before marking implementation complete. Seen in: ship-run-audit-logging (ship SKILL.md Steps 4–5). #coder #instrumentation #plan-fidelity (2026-03-28)

- **[2026-03-28] Event emitted after the resource it depends on has been deleted** [Low] — When a multi-step finalization block deletes a state file or resource partway through, any emit or logging call placed after the deletion silently drops its output if it depends on the deleted resource. In ship-run-audit-logging, the `step_end` event for Step 6 was emitted after `rm -f ".ship-audit-state-${RUN_ID}.json"` — because `emit-audit-event.sh` checks for the state file and exits 0 silently when missing, every audit log is permanently missing the `step_end` for Step 6. Pattern: emit all telemetry/logging calls before any cleanup that deletes resources those calls depend on. Order within a finalization block should be: (1) emit closing events, (2) delete state/temp files. Seen in: ship-run-audit-logging (ship SKILL.md Step 6 audit finalization block). #coder #event-ordering #cleanup #telemetry (2026-03-28)

- **[2026-04-08] Stale version string in skill auto-commit message template** [Low] — When a skill's version number is bumped in its frontmatter, hardcoded version strings embedded in auto-commit message templates (e.g., `Plan approved by /architect v3.0.0`) are not updated to match. The commit message template ships into every auto-commit for every future plan approval, embedding an outdated version string in git history. Pattern: treat version strings in commit message templates as a second update site whenever the frontmatter version changes — include in the same diff or add to a checklist. Seen in: threat-model-consumption (architect SKILL.md Step 5 auto-commit, still read `v3.0.0` after bump to v3.3.0). #coder #documentation #versioning (2026-04-08)

- **[2026-04-08] Security Maturity Levels documentation not updated when new maturity-gated behavior is added** [Low] — When a new gate or check is added to `/ship` that has different behavior at L1 vs L2/L3 (e.g., a new structural validation step that warns at L1 and blocks at L2/L3), the Security Maturity Levels section in CLAUDE.md and the Security Gates subsection are not updated to document the new gate. Users reading only the Security Maturity Levels section won't know the new behavior exists or what it does at each level. Pattern: when implementing any maturity-level-conditional behavior in a skill, update both (a) the skill registry description and (b) the Security Gates subsection in CLAUDE.md at the same time. Seen in: threat-model-consumption (ship SKILL.md Step 1 threat model presence check at L1/L2/L3 not added to CLAUDE.md Security Gates subsection). #coder #documentation #security-maturity (2026-04-08)
