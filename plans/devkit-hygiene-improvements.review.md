# Review: devkit-hygiene-improvements.md (Round 2)

**Reviewed:** 2026-03-27
**Reviewer:** Librarian (automated plan review)
**Plan revision:** Rev 2
**Verdict:** PASS

---

## Round 1 Required Edits Resolution

1. **Improvement numbering mismatch** -- RESOLVED. Rev 2 added a "Numbering note" (line 21) explaining that #4, #5, #7, #8 are inherited from the portfolio review where #1-#3 and #6 were addressed in the agentic-sdlc-next-phase plan. The Goals section retains 1-4 numbering for readability. No remaining ambiguity.

2. **CLAUDE.md test count inconsistency** -- RESOLVED. Rev 2 added an explicit note (line 302) in the "No Changes To" section: "the three test count references -- currently showing 46 and 45 inconsistently -- must be normalized to the correct post-expansion count in a follow-up /sync pass." This acknowledges the existing inconsistency (line 729: "46 tests"; line 919: "45 tests"; line 1068: "45 tests") and defers normalization to a /sync pass rather than silently leaving stale counts.

3. **Variable name inconsistency** -- RESOLVED. Rev 2 uses `$SKILLS_DIR` consistently throughout WG-1 code blocks (lines 105, 106, 113, 119, 137, 472, 478, 479, 495-501, 504) where the variable is defined in `test_skill_generator.sh`, and `$REPO_DIR` consistently throughout WG-3 code blocks (lines 613-615, 675, 691) where the variable is defined in the integration test script. Clarifying comments were added (lines 104, 495: "Note: $SKILLS_DIR resolves to the repo root (parent of generators/)").

---

## Conflicts with CLAUDE.md Rules

- **None.** All four improvements operate in the correct tiers: skill fix in `skills/` (Tier 1), tests in `generators/` (Tier 2), integration script in `scripts/`, documentation in `generators/`. The plan follows the "Edit source, not deployment" rule (WG-2 edits `skills/ship/SKILL.md`, not the deployed copy). New tests follow the existing `run_test()` harness pattern. The `--validate --contrib` test (Test 49) uses conditional skip, consistent with existing contrib tests (43-45). CI/CD integration is correctly deferred per CLAUDE.md Roadmap v1.2.

---

## Historical Alignment

- **Context Alignment section exists and is substantive.** Six CLAUDE.md patterns followed, three prior plans referenced, three deviations justified. Meets the standard established by prior approved plans.

- **Context metadata block is present and accurate.** `claude_md_exists: true` is correct. All three referenced plans (`agentic-sdlc-next-phase.md`, `security-guardrails-phase-b.md`, `secure-review-remediation.md`) exist in `./plans/`.

- **No contradiction with prior plans.** The hygiene plan extends `agentic-sdlc-next-phase.md` by adding test coverage for features that plan created but did not test. The settings precedence bug fix (WG-2) addresses a known issue from `security-guardrails-phase-b.md`, documented in `.claude/learnings.md` line 42. The plan's non-goals correctly defer CI/CD to v1.2 per CLAUDE.md roadmap.

- **Learnings file reference verified.** The plan cites `.claude/learnings.md` line 42 for the `--validate` test gap. The actual entry at line 42 reads: "New feature flag paths not covered by automated tests." This is accurate.

- **Test count baseline verified.** The plan claims 44 runtime tests with header saying 46 and numbers 26, 33, 35 skipped. Confirmed: `run_test` invocations cover tests 1-25, 27, 27b, 28-32, 34, 36-45, plus Test 46 (cleanup, manual increment) = 44 counted tests. The plan's analysis is accurate.

- **WG-3 duplication eliminated.** Rev 1 had integration Tests 3-4 duplicating WG-1 Tests 47-48 (deploy.sh --validate positive/negative). Rev 2 replaced them with a full lifecycle test (generate-validate-deploy-undeploy) and a meta-test (run the unit suite). No remaining duplication.

---

## Required Edits

None. All three Round 1 required edits have been addressed. The plan is technically sound, historically aligned, and internally consistent.

---

## Optional Suggestions

- **CLAUDE.md skill count note.** CLAUDE.md line 14 says "12 core reusable Claude Code workflows," line 919 says "All 12 core skills," and line 1068 says "all 12 core + 3 contrib skills validated." The Skill Registry table at lines 93-104 also lists 12 skills. The system-prompt version of CLAUDE.md references 13 (including `test-idempotent`), but the on-disk CLAUDE.md does not include `test-idempotent` in the registry. If `test-idempotent` is a deployed skill, the /sync pass that normalizes test counts should also normalize the skill count to 13.

- **Integration test Test 4 runtime cost.** The meta-test (running the full unit suite from within the integration test) approximately doubles the runtime when both test scripts are invoked in sequence (e.g., during development). Consider adding a `--skip-meta` flag or documenting the expected runtime.

- **WG-2 code block indentation.** The fixed code block (lines 553-570) uses 2-space indentation inside `if` blocks, which matches the existing code. No change needed, but the acceptance criteria (line 411) specifies `LOCAL_SET=0` at "line 95" -- the actual line number may shift if the prose replacement (line 89) changes the line count. Consider making the acceptance criteria reference relative positions (e.g., "on the line after `SECURITY_MATURITY='advisory'`") rather than absolute line numbers.

---

## Summary

Rev 2 resolves all three Round 1 required edits cleanly: the numbering gap is explained, the CLAUDE.md test count normalization is explicitly deferred to a /sync pass with the inconsistency acknowledged, and variable names are now consistent within their respective scripts. The four improvements remain independent, low-risk, and well-scoped. No conflicts with CLAUDE.md rules or prior plans. Verdict: **PASS**.
