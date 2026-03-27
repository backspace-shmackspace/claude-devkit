# QA Report — security-guardrails-phase-b

**Date:** 2026-03-27
**Plan:** `plans/security-guardrails-phase-b.md`
**QA Agent:** qa-engineer v1.0.0 (inherits qa-engineer-base.md v1.8.0)
**Validation commands run:** All three `validate_skill.py` invocations + full `test_skill_generator.sh`

---

## Verdict: PASS_WITH_NOTES

All acceptance criteria are met. The three skills are functionally complete and all automated tests pass. Notes are non-blocking observations about edge cases and known learning patterns applicable to this implementation.

---

## Acceptance Criteria Coverage

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `skills/ship/SKILL.md` updated to v3.5.0 with all security gates | MET | Frontmatter `version: 3.5.0` confirmed; all four security gate blocks present (Step 0 maturity check, Step 0 secrets scan, Step 4d secure review, Step 6 dependency audit) |
| 2 | `skills/architect/SKILL.md` updated to v3.1.0 with threat-model-gate awareness | MET | Frontmatter `version: 3.1.0` confirmed; threat-model-gate Glob in Step 0, injection block in Step 2, security-analyst recommendation in Step 3a |
| 3 | `skills/audit/SKILL.md` updated to v3.1.0 with secure-review composability | MET | Frontmatter `version: 3.1.0` confirmed; Secure-review composability check block present at top of Step 2 |
| 4 | All three modified skills pass `validate-skill` with zero errors | MET | All three returned `PASS (with warnings)` — zero errors; warnings are optional improvements only (see Notes) |
| 5 | Full test suite passes (`bash generators/test_skill_generator.sh`) | MET | 33/33 tests PASS, 0 failures |
| 6 | `/ship` runs normally when security skills are NOT deployed (backward compatibility at L1) | MET | Step 0 secrets scan gate: "If not found — If L1 (advisory): Log note." Step 0 maturity check only aborts for L2/L3. Step 4d: "If not found: Log note, set verdict to not-run." Step 6 dep audit: "If not found: Log note." All gates gracefully degrade. |
| 7 | `/ship` runs security gates when security skills ARE deployed (L1: advisory, L2: enforced) | MET | Gates are dispatched via Task subagent when respective skill Glob succeeds. L1/L2 result evaluation matrix is correctly differentiated in Step 4 Result evaluation. |
| 8 | `/ship` aborts at Step 0 when L2/L3 maturity is set and security skills are missing | MET | Explicit block in Step 0 maturity check: if enforced/audited and any of the three security skill Globs fail, stop immediately with deployment instructions. |
| 9 | `/ship` secrets scan gate delegates to `/secrets-scan` via Task subagent (no inline patterns) | MET | Step 0 secrets scan gate uses `Tool: Task, subagent_type=general-purpose`. The subagent reads and executes the secrets-scan SKILL.md — no inline regex patterns present in /ship. |
| 10 | `/ship` secure-review runs parallel with code review, tests, and QA in Step 4 | MET | Step 4 header: "Run these verification tasks in parallel (3 or 4 tasks depending on security skill deployment)." Steps 4a, 4b, 4c, 4d are defined at the same level. Step 4d is dispatched via Task subagent. |
| 11 | `/ship` dependency-audit runs before commit in Step 6 (only when new deps added) | MET | Step 6 "Dependency audit gate (conditional)" block placed before the commit logic. Manifest diff check gates whether the Task subagent is dispatched. "If no dependency changes detected: Skip dependency audit." |
| 12 | `/ship --security-override "reason"` downgrades security BLOCKED to PASS_WITH_NOTES | MET | Override parsing present as first action in Step 0. All three gates (secrets scan, secure review, dependency audit) reference `--security-override` check and downgrade BLOCKED to PASS_WITH_NOTES when set. |
| 13 | Override reason logged in commit message footer | MET | Step 6 commit message block: "If `--security-override` was used, append `Security-Override: $SECURITY_OVERRIDE_REASON` to commit message." |
| 14 | `/architect` detects threat-model-gate deployment in Step 0 | MET | Step 0 Pattern 4: `~/.claude/skills/threat-model-gate/SKILL.md`. If found: "Threat model gate active. Security-related plans will include threat modeling requirements." |
| 15 | `/architect` injects threat modeling requirements for security-sensitive plans | MET | Step 2 conditional injection block present with full keyword heuristic and STRIDE/Security Requirements section requirement. |
| 16 | `/architect` does NOT inject threat modeling for non-security plans | MET | Step 2: "If not security-sensitive: Do not append. Standard planning prompt only." |
| 17 | `/architect` recommends (not requires) security-analyst invocation at Step 3a | MET | Step 3a text: "**Recommended** (when threat-model-gate is deployed and plan subject is security-related)..." — language changed from "Optional" to "Recommended" as specified. |
| 18 | `/audit` delegates security scan to `/secure-review` when deployed (code/full scope) | MET | Step 2 composability check: "If found AND scope is NOT 'plan'": dispatches Task subagent reading secure-review SKILL.md with scope mapping (code→changes, full→full). |
| 19 | `/audit` uses built-in security scan when `/secure-review` not deployed (backward compatible) | MET | Step 2: "If not found OR scope is 'plan'... Continue with the existing built-in security scan (unchanged behavior below)." Existing scan logic remains intact. |
| 20 | `/audit` uses built-in scan for "plan" scope regardless of `/secure-review` deployment | MET | Step 2: condition is "If found AND scope is NOT 'plan'". When scope is "plan", the composability check short-circuits even if the skill is deployed. Explicit output: "Scope is 'plan' — using built-in plan security analysis." |
| 21 | All skills deploy successfully via `./scripts/deploy.sh` | MET | `./scripts/deploy.sh` completed successfully. Deployed files confirmed at `~/.claude/skills/{ship,architect,audit}/SKILL.md` with timestamps matching this run. |

**Summary: 21/21 criteria MET.**

---

## Test Commands Run

```
python3 generators/validate_skill.py skills/ship/SKILL.md       → PASS (1 warning)
python3 generators/validate_skill.py skills/architect/SKILL.md  → PASS (2 warnings)
python3 generators/validate_skill.py skills/audit/SKILL.md      → PASS (3 warnings)
bash generators/test_skill_generator.sh                          → 33/33 PASS
./scripts/deploy.sh                                              → All 13 skills deployed
```

---

## Missing Tests or Edge Cases

The following edge cases are not exercised by the automated test suite. They are documented here for awareness; none block the verdict.

1. **`--security-override` with whitespace-only reason** — The plan says to extract the quoted text after `--security-override`. An empty quoted string (`--security-override ""`) would set `$SECURITY_OVERRIDE_REASON` to empty, making the commit footer entry `Security-Override:` with no value. This is a minor cosmetic issue, not a security concern.

2. **L2/L3 maturity level — partial skills deployment** — The Step 0 maturity check globs for all three security skills and lists which are missing. The test suite does not exercise the partial-deployment path (e.g., secrets-scan deployed but secure-review missing at L2). The code handles it correctly (lists individual missing skills), but no automated test covers this combination.

3. **Dependency audit when manifest diff produces only removals** — Step 6 checks "if any manifest file diff shows additions in dependency sections." A diff with only removals (downgraded versions, deleted packages) would not trigger the audit. This is correct behavior but represents an untested edge path; removed packages could theoretically introduce vulnerabilities via version downgrades.

4. **`/architect` non-security topic keyword false positives** — The security-sensitive heuristic is intentionally broad. Keywords like "file" (in File/Process category) would trigger threat modeling for a plan to "add file download button" which may be intentional but adds overhead. Not a defect; documented in Deviation 3 of the plan. No test verifies the keyword boundary cases.

5. **`/audit` scope="plan" with `/secure-review` deployed — test suite gap** — Test 5 validates the audit skill structurally, but does not simulate the composability branch. This is consistent with the existing test suite's scope (static validation, not behavioral simulation). Already noted in learnings.

6. **Revision loop + BLOCKED interaction (L2/L3)** — The result matrix at L2/L3 includes a `REVISION_NEEDED + BLOCKED` row where coders must fix both code review and security issues. The `5b — Re-verify in parallel` section says "Re-run Step 4 in its entirety." It does not explicitly state that after the revision loop, secure review re-runs. This is implied by "Re-run Step 4 in its entirety" but could be made explicit. Low ambiguity risk; noting for future clarity.

---

## Learnings Gap Check

Per `.claude/learnings.md` QA Patterns and Test Patterns, checking known recurring coverage gaps:

| Known Gap | Applicable? | Status in This Implementation |
|-----------|-------------|-------------------------------|
| **Validator not executed at QA time** [High] — QA agent relied on static inspection rather than running the tool. | Yes | ADDRESSED. All three `validate_skill.py` invocations were run and results verified. No static-only inspection. |
| **Full test suite skipped** [Medium] — `bash generators/test_skill_generator.sh` skipped in multiple prior features. | Yes | ADDRESSED. Full test suite run: 33/33 PASS. |
| **Integration/e2e tests not executed** [High] — Live skill invocation deferred. | Partially applicable | PARTIALLY ADDRESSED. Manual tests 1-11 from the plan are defined but require a live Claude Code session with skills deployed — not automated. This is the same structural limitation as prior features. The structural test suite (33 tests) plus validator execution provide meaningful but incomplete coverage. No new mechanism for live smoke tests was introduced in this plan. |
| **New skills not added to test suite** [Medium] — Phase A security skills not added to test suite. | Not applicable (no new skills created) | N/A. Phase B modifies existing skills only. No new skills created. However, the pre-existing Phase A skills (secrets-scan, secure-review, dependency-audit, threat-model-gate) which are now invoked as dependencies of Phase B are still not in the test suite. This predates Phase B and is not a regression. |
| **Strict mode not tested for new skill types** [Low] | Not applicable | N/A. No new archetypes introduced. |

---

## Notes (Non-Blocking)

**N1 — Validator warnings on all three skills (pre-existing pattern)**

All three skills emit warnings from `validate_skill.py`:
- `ship`: "Timestamped Artifacts" — /ship uses `[name]` placeholders, not `[timestamp]`. Pre-existing behavior, not a regression.
- `architect`: "Timestamped Artifacts" + "Step 5 missing Tool: declaration" — Pre-existing; Step 5 is a verdict/gate step where Tool omission is acceptable per validator note.
- `audit`: "Bounded Iterations" + "Archive on Success" + "Step 6 missing Tool: declaration" — All pre-existing. The plan did not change Step 6 (gate) or add a revision loop to /audit.

These warnings exist on the pre-Phase-B versions and are not regressions from this implementation.

**N2 — `--security-override` parsing is prose-based, not code-based**

The flag is parsed by the coordinator LLM reading `$ARGUMENTS` string, not by a shell script. This is correct for a skill (skills are LLM-executed instructions), but the parsing behavior for edge cases (flag at beginning vs. end of $ARGUMENTS, missing closing quote, flag without reason) is only defined for the happy path. The plan's known limitation (v1.0) section documents the blanket-override scope limitation. The parsing ambiguity is a separate, undocumented edge case. Low impact at L1/L2; higher impact at L3.

**N3 — Stale step cross-reference risk (from learnings)**

The learnings file records a Low-severity pattern: "Stale internal step cross-references in skill documentation" from the prior /ship revision. The Phase B additions reference "Step 3a" (shared deps) and "Step 5a" (revision loop) in the /ship skill correctly. No stale references were introduced. Verified by reading the relevant cross-reference prose in Steps 5 and 6.

**N4 — L3 override flag documented but audit trail is minimal**

The plan explicitly documents in section 1d that the `--security-override` at L3 produces only a commit message footer entry — no structured audit record, no approver field, no per-finding granularity. This is acknowledged as "insufficient for full L3 compliance" and deferred. The implementation correctly reflects this limitation. Flagging here for Phase C awareness.

---

*Generated by qa-engineer v1.0.0 — 2026-03-27*
