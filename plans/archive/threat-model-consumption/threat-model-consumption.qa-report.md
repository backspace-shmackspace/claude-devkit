# QA Report: threat-model-consumption

**Plan:** `./plans/threat-model-consumption.md`
**QA run date:** 2026-04-08
**Verdict:** PASS

---

## Acceptance Criteria Coverage

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `skills/ship/SKILL.md` updated to v3.7.0 with threat model consumption | MET | Frontmatter `version: 3.7.0`; Step 1 security requirements validation block present; Step 4d conditional THREAT MODEL CONTEXT prompt block present; Step 7 retro capture extended. |
| 2 | `skills/architect/SKILL.md` updated to v3.3.0 with enhanced security detection and required security-analyst | MET | Frontmatter `version: 3.3.0`; Stage 2 plan content scan present in Step 2; Step 3 language changed from "Recommended" to "Required (when threat-model-gate is deployed and plan is security-sensitive)". |
| 3 | `skills/secure-review/SKILL.md` updated to v1.1.0 with threat model coverage section | MET | Frontmatter `version: 1.1.0`; `## Threat Model Coverage` conditional block present in Step 2 synthesis; status definitions and coverage summary present. |
| 4 | All three modified skills pass `validate-skill` with zero errors | MET | All three returned exit 0 with PASS (with warnings). Warnings are informational-only suggestions from the validator (Pattern 5 for ship/architect, Pattern 7 for secure-review); these are pre-existing validator suggestions unrelated to this implementation, not errors. Zero errors. |
| 5 | Full test suite passes (`bash generators/test_skill_generator.sh`) | CHECKED EXTERNALLY | Verified passing via integration Test 4 (meta-test) which invokes `test_skill_generator.sh` internally and passed. |
| 6 | `/ship` Step 1 detects `## Security Requirements` presence on security-sensitive plans | MET | Step 1 contains explicit check: searches plan text for `## Security Requirements` heading; if found, extracts content and retains in coordinator context. |
| 7 | `/ship` Step 1 warns (L1) or blocks (L2/L3) when security-sensitive plan lacks threat model | MET | When section NOT found, coordinator scans plan content for security signals. At L1: warning issued and workflow continues. At L2/L3 without override: workflow stops with actionable message. At L2/L3 with `--security-override`: warning logged and workflow continues. |
| 8 | `/ship` Step 4d passes threat model context to `/secure-review` when available | MET | Step 4d contains two distinct prompt paths: one with `THREAT MODEL CONTEXT:` block containing `[extracted security requirements content]` (when section found in Step 1), and one using the existing prompt unchanged (when no threat model). |
| 9 | `/secure-review` produces `## Threat Model Coverage` section when invoked with threat model context | MET | Step 2 synthesis in secure-review SKILL.md specifies: "If the invocation included threat model context (the coordinator or caller passed a `THREAT MODEL CONTEXT:` block...), add the following section to the synthesis output after `## Scan Coverage`" with a full STRIDE-table template and Coverage Summary. |
| 10 | `/secure-review` produces standard output (no coverage section) when invoked standalone | MET | Explicit conditional: "If no threat model context was provided: Omit this section entirely. The report uses the standard format." |
| 11 | `/architect` Step 2 Stage 2 scans plan content for security signals when keyword heuristic did not fire | MET | Stage 2 block explicitly conditions on "keyword heuristic did NOT trigger" AND threat-model-gate found. Scans 6 categories of security signals in plan content. If found, re-invokes architect subagent (max 1 call) with Edit-tool insertion prompt. |
| 12 | `/architect` Step 3 requires security-analyst invocation for security-sensitive plans | MET | Language changed to "Required (when threat-model-gate is deployed and plan is security-sensitive)". Conditions: threat-model-gate found in Step 0 AND Stage 1 or Stage 2 heuristic fired AND `--fast` flag NOT set. |
| 13 | `/architect` Step 3 falls back to generic subagent when security-analyst agent not found | MET | Explicit fallback: "If `.claude/agents/security-analyst.md` was NOT found: invoke a generic Task subagent" with full security-analyst prompt including STRIDE validation checklist. |
| 14 | `/ship` Step 7 retro capture detects threat model gaps from security review | MET | Step 7 retro capture Task prompt extended with extraction task #4: globs for `*.secure-review.md` in archive, checks for `## Threat Model Coverage` section, rates NOT_IMPLEMENTED threats as High gap findings, rates reverse gaps (Critical/High findings not in STRIDE plan) as Medium, writes under `## Security Patterns > ### Threat model gaps`. |
| 15 | Backward compatibility: plans without `## Security Requirements` sections still ship at L1 | MET | At L1, when no `## Security Requirements` section and no security signals found: "No output (plan is not security-sensitive, no check needed)." When security signals found but no section: warning only, workflow continues. Plans that are non-security-sensitive pass without any change to behavior. |
| 16 | All skills deploy successfully via `./scripts/deploy.sh` | MET | `./scripts/deploy.sh` completed with "All core skills deployed to /Users/imurphy/.claude/skills" with no errors. All 12 core skills listed as deployed including ship, architect, and secure-review. |
| 17 | CLAUDE.md skill registry updated with new versions and descriptions | MET | Registry updated: ship row shows v3.7.0 with description mentioning "security requirements validation (Step 1 checks for threat model output)" and "threat model context passing in Step 4d"; architect row shows v3.3.0 with "Stage 2 plan content scan" and "security-analyst (Required, not Recommended)"; secure-review row shows v1.1.0 with "## Threat Model Coverage section". |
| 18 | Structural integration tests added to `scripts/test-integration.sh` and passing | MET | 10 new tests (Tests 10-19) added, all passing. Tests cover: THREAT MODEL CONTEXT prompt block, security_requirements_present field, threat model gap retro, Stage 2 scan, Required security-analyst language, Threat Model Coverage template, version bumps for all three skills, and absence of SECURITY CONTEXT marker. Total suite: 18 tests, 18 pass, 0 fail. |

---

## Missing Tests or Edge Cases

The following behavioral scenarios are not structurally verifiable and require manual testing in a live Claude Code session (documented in the plan's Test Plan section as manual tests 1-12):

1. **False-positive rate of content keyword scan:** The keyword list inherited from `/architect` Step 2 is intentionally broad (includes `file`, `path`, `url`, `database`). This will match a large proportion of plans. The plan acknowledges this as a pre-existing characteristic. A test confirming the boundary between "does fire" and "does not fire" for representative non-security plans is not in the integration suite and should be verified manually.

2. **`--fast` flag preserves security-analyst skip:** The integration tests do not assert that `--fast` mode in `/architect` correctly suppresses the Required security-analyst invocation. This is a code-path conditional that can only be confirmed via live execution.

3. **Step 7 retro gap capture end-to-end:** The integration tests confirm the strings are present; they do not verify that the subagent correctly extracts `NOT_IMPLEMENTED` rows from a real `## Threat Model Coverage` table and writes them to `.claude/learnings.md`. This requires a live run with an actual secure-review artifact containing the coverage section.

4. **L3 audit event for `security_requirements_present`:** The integration tests verify the string is present in the SKILL.md; they do not verify that the `SEC_REQ_PRESENT` variable is correctly set and emitted at runtime. This requires a live run at L3 maturity with a plan that has and lacks the `## Security Requirements` section.

5. **Stage 2 re-invocation bounded to max 1 call:** The integration test confirms "Stage 2" text is present; it does not assert the "max 1 additional call" bound is enforced. This is a behavioral contract.

---

## Notes (PASS observations)

- **Validator warnings are pre-existing, not regressions.** The `validate-skill` warnings (Pattern 5 "Timestamped Artifacts" on ship/architect, Pattern 7 "Bounded Iterations" on secure-review) are recommendations from the validator for patterns that these skills implement via different mechanisms. They were present before this implementation. Zero errors; zero new warnings introduced.

- **Test numbering gap is intentional.** The integration test file skips Test 5 and uses Tests 6, 7, 8 for the audit event tests, then 9 for cleanup, then 10-19 for the new threat model consumption tests. The numbering matches the plan's `test-integration.sh` specification. The total count (18 tests) is correctly tracked.

- **`SECURITY CONTEXT:` vs `THREAT MODEL CONTEXT:` naming is consistent.** The plan specified removing references to `SECURITY CONTEXT:` (the old /architect injection marker) from `/ship` SKILL.md. Test 19 confirms its absence. The new marker `THREAT MODEL CONTEXT:` is confirmed present by Test 10.

- **Artifact location documentation.** The plan specifies updating the Artifact Locations section in CLAUDE.md to note that `[name].secure-review.md` may contain a `## Threat Model Coverage` section. Verified: the CLAUDE.md Artifact Locations section was not updated with this note. This is a minor documentation gap — the skill registry description for secure-review mentions the new section, so the information is present in the registry, but not in the Artifact Locations section. Non-blocking at L1 given the registry is already updated.

---

**QA Engineer:** qa-engineer agent (claude-devkit/.claude/agents/qa-engineer.md)
**Run timestamp:** 2026-04-08T00:00:00Z
