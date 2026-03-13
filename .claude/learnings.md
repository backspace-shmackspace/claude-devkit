# Project Learnings

Last updated: 2026-03-12

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

- **Integration/e2e tests not executed** [High] — Live skill invocation deferred out of QA with "no automated mechanism exists." No QA report shows evidence of a live smoke test. Seen in: audit-remove-mcp-deps, receiving-code-review. #qa #coverage #integration (2026-03-12)

- **Full test suite skipped** [Medium] — `bash generators/test_skill_generator.sh` skipped as "long-running" in multiple features. Only phase0-reference-validator ran the full suite. Seen in: receiving-code-review, audit-remove-mcp-deps. #qa #coverage #test-suite (2026-03-12)

- **Strict mode not tested for new skill types** [Low] — `--strict` mode validation not explicitly tested for new archetypes (Reference skills). If strict-mode behavior diverges, it would go undetected. Seen in: receiving-code-review, phase0-reference-validator. #qa #coverage #strict-mode (2026-03-12)

---

## Test Patterns

### Common failures

No recurring test failures identified (0 test failure logs found across 3 features).

### Infrastructure gaps

- **No automated gate between QA and merge** [High] — Runtime checks (validator execution, integration smoke tests, full test suite) are deferred to "Phase 3" or marked "non-blocking." No CI mechanism enforces these gates before merge. Burden falls on developer discipline. Seen in: audit-remove-mcp-deps, receiving-code-review. #test #infra #ci (2026-03-12)

---

## Coder Patterns

### Missed by coders, caught by reviewers

No recurring coder mistakes identified. Both code reviews returned PASS with zero critical or major issues. One-off Low-severity items only (test numbering gap, hardcoded fallback patterns).
