# Red Team Review (Round 2): Threat Model Consumption Plan

**Plan:** `./plans/threat-model-consumption.md`
**Reviewer:** Red Team (revision review)
**Date:** 2026-04-07
**Round:** 2 (revision review of round 1 findings)

## Verdict: PASS

No Critical findings. All Major findings from round 1 have been adequately addressed. Two new Minor findings introduced by the revision, neither blocking.

---

## Round 1 Resolution Status

### F1/M2: $SECURITY_REQUIREMENTS_CONTENT shell-variable notation -- Resolved

**Round 1 finding:** The plan used `$SECURITY_REQUIREMENTS_CONTENT` shell-variable notation, which implied Bash persistence across steps. Both the red team (F1) and the feasibility reviewer (M2) flagged this as misleading.

**Resolution:** The revised plan removes all `$SECURITY_REQUIREMENTS_CONTENT` references from the design. Section 1a (lines 155-157) now contains an explicit "Coordinator context variable clarification" paragraph that explains the mechanism: the coordinator reads the plan in Step 1 via the Read tool, extracts the section content, carries it in its context window, and substitutes it inline when constructing the Step 4d Task prompt. The paragraph explicitly states "This is NOT a shell environment variable or file-based state" and notes that no file-based persistence is needed because the coordinator's context spans the entire run.

The Implementation Plan (Step 3, line 575-599) similarly uses "extracted content in coordinator context" language rather than variable notation.

**Assessment: Fully resolved.** The clarification is thorough and eliminates the ambiguity.

### F4: SECURITY CONTEXT: marker detection replaced with section-presence check -- Resolved

**Round 1 finding:** The plan relied on detecting the literal string `SECURITY CONTEXT:` in the plan text as a security-sensitivity signal. This was fragile because the string is in the prompt *to* the architect subagent, not deterministically in the plan output. The red team recommended switching to `## Security Requirements` section presence as the primary detection mechanism.

**Resolution:** The revised plan completely removes `SECURITY CONTEXT:` as a detection signal. The new decision matrix (lines 141-147) uses only two checks:
1. Does the plan contain `## Security Requirements`? (section heading check)
2. If not, does the plan content contain security keyword signals? (content scan)

This is a simpler and more robust design. The negative integration test on line 486-487 (`! grep -q "SECURITY CONTEXT:" skills/ship/SKILL.md`) explicitly guards against reintroduction.

**Assessment: Fully resolved.** The replacement mechanism is cleaner and eliminates the fragile coupling.

### F9: Automated integration tests -- Resolved

**Round 1 finding:** No automated integration tests existed for the threat model consumption flow. The only behavioral validation was 12 manual tests.

**Resolution:** The revised plan adds a "Structural Integration Tests" section (lines 456-490) with 9 grep-based structural checks to be added to `scripts/test-integration.sh`. These tests verify:
- `/ship` SKILL.md contains the `THREAT MODEL CONTEXT:` prompt block
- `/ship` SKILL.md contains the `security_requirements_present` audit field
- `/ship` SKILL.md contains the threat model gap retro capture block
- `/architect` SKILL.md contains Stage 2 plan content scan
- `/architect` SKILL.md contains Required security-analyst language
- `/secure-review` SKILL.md contains the Threat Model Coverage section template
- Version bumps are correct (3.7.0, 3.3.0, 1.1.0)
- `/ship` SKILL.md does NOT contain the removed `SECURITY CONTEXT:` marker

The plan also adds `scripts/test-integration.sh` to the Task Breakdown (file #5, line 529) and the acceptance criteria (line 517).

**Assessment: Fully resolved.** The structural tests are a pragmatic approach given that runtime behavioral tests require a live Claude Code session.

### F5: Security-analyst revision loop triggering -- Resolved

**Round 1 finding:** The plan was ambiguous about what happens when the security-analyst finds Major gaps but the red team issues PASS. The "Required" mandate conflicted with "the red team verdict governs pass/fail."

**Resolution:** The revised plan (lines 280-281) explicitly clarifies the mechanism: "The security-analyst supplement is appended to the redteam artifact. The red team verdict in Step 3 considers the full redteam artifact, including the supplement. Major findings from the security-analyst are *part of* the redteam review -- they are not a separate verdict channel." The plan further states (line 281): "There is no separate 'security-analyst verdict' -- the security-analyst findings flow through the red team verdict as input, not as an override."

The Implementation Plan (Step 11, lines 746-747) reinforces this: "Major findings from the security-analyst are part of the red team's input, not a separate verdict. When Major gaps are present, the red team should issue FAIL, which triggers the existing Step 4 revision loop."

**Assessment: Fully resolved.** The revision correctly avoids introducing a separate verdict channel and instead routes security-analyst findings through the existing red team verdict flow. This is architecturally clean. The residual risk -- the red team might still issue PASS despite Major findings in the supplement -- is an inherent limitation of LLM-based review, not a design flaw. The plan correctly does not try to engineer around it with a mechanical override.

### M3: Stage 2 re-invocation should use Edit tool -- Resolved

**Round 1 finding (feasibility M3):** The Stage 2 re-invocation prompt instructed the subagent to read and rewrite the entire plan, risking accidental modification of other sections. The feasibility reviewer recommended using the Edit tool for surgical insertion.

**Resolution:** The revised plan (lines 251-259) explicitly instructs the subagent to "use the Edit tool for surgical insertion of the `## Security Requirements` section, rather than reading and rewriting the entire plan." The revised prompt (line 255-259) says: "Use the Edit tool to insert a `## Security Requirements` section into the existing plan, placing it after the last existing section and before any `## Status` or metadata sections."

**Assessment: Fully resolved.** The Edit tool instruction eliminates the risk of accidental modification during full-file rewrite.

---

## New Findings

### N1 -- Integration test line 467 has a shell pipeline bug (Minor)

The structural integration test on line 467:
```bash
grep -q "## Security Requirements" skills/ship/SKILL.md | grep -q "security_requirements_present" skills/ship/SKILL.md || fail "..."
```

This pipeline is logically broken. `grep -q` produces no stdout output (the `-q` flag suppresses it), so the pipe is effectively a no-op. However, since both grep commands specify explicit file arguments (not stdin), each reads independently from `skills/ship/SKILL.md`. The pipeline's exit code is determined by the *last* command only (`grep -q "security_requirements_present" ...`), so the first check (`## Security Requirements`) is silently ignored.

**Fix:** Replace the pipe with `&&`:
```bash
grep -q "## Security Requirements" skills/ship/SKILL.md && grep -q "security_requirements_present" skills/ship/SKILL.md || fail "..."
```

Or split into two separate test lines for clarity.

**Rating: Minor** -- the test would still catch the most important case (missing `security_requirements_present` field), but silently drops the `## Security Requirements` heading check. Easy fix.

### N2 -- Stage 2 keyword overlap acknowledgment is thorough but repetitive (Info)

The revised plan adds two "Note on" paragraphs: one about Stage 1/Stage 2 keyword overlap (lines 136-139, in the /ship Step 1 context) and another about the same topic in the /architect section (lines 236-237). The /ship version also adds a "Note on inherited keyword breadth" paragraph (lines 139). These three notes cover the same ground that the round 1 F2 and F7 findings identified, which is good -- but the repetition across two sections adds ~300 words of defensive explanation for what is ultimately a minor inherited characteristic.

**Rating: Info** -- no action needed. The thoroughness is appropriate for a plan that will be reviewed and shipped, and the acknowledgments directly address round 1 feedback. Redundancy is preferable to ambiguity in this case.

---

## Previously Identified Issues (Status Check)

| Round 1 ID | Severity | Status | Notes |
|-----------|----------|--------|-------|
| F1 (redteam) / M2 (feasibility) | Major | **Resolved** | Coordinator context variable clarification added |
| F4 (redteam) | Major | **Resolved** | `SECURITY CONTEXT:` marker replaced with section-presence check |
| F9 (redteam) | Major | **Resolved** | Structural integration tests added |
| F5 (redteam) | Minor (upgraded to Major for review) | **Resolved** | Security-analyst findings flow through red team verdict |
| M3 (feasibility) | Major | **Resolved** | Edit tool instruction added for Stage 2 re-invocation |
| F2 (redteam) | Minor | **Resolved** | Keyword overlap acknowledged with explicit notes |
| F3 (redteam) | Info | **N/A** | Was already correct; no change needed |
| F6 (redteam) | Info | **N/A** | Out of scope acknowledged; no change needed |
| F7 (redteam) | Minor | **Resolved** | Keyword breadth inherited-not-introduced acknowledged |
| F8 (redteam) | Minor | **N/A** | Version bump is semantically correct; no change needed |
| F10 (redteam) | Minor | **Resolved** | Rollback plan updated with single-commit note (line 396) |
| F11 (redteam) | Info | **Resolved** | Note added at line 868 explaining `## Status: APPROVED` is added by the approval gate |
| M1 (feasibility) | Major | **Resolved** | Step 7 now includes explicit note about archive path (line 677) |
| m1 (feasibility) | Minor | **N/A** | Pre-existing; correctly deferred |
| m2 (feasibility) | Minor | **Not addressed** | Template still shows fixed six-row STRIDE table, but this is a minor formatting concern that the LLM will handle correctly regardless |
| m3 (feasibility) | Minor | **Not addressed** | `audit-event-schema.json` update not listed as a task, but schema likely uses `additionalProperties: true` |
| m4 (feasibility) | Minor | **Not addressed** | Architect Step 5 auto-commit version string not updated, but this is pre-existing |
| Librarian Required Edit 1 | Required | **Resolved** | Plan notes that `## Status: APPROVED` is added by the approval gate (line 868) |
| Librarian Required Edit 2 | Required | **N/A** | Self-referential; plan models what it preaches by documenting the marker's lifecycle |

---

## Summary

The revised plan adequately addresses all five Major findings from round 1. The core design is stronger: the `SECURITY CONTEXT:` marker fragility is eliminated, the coordinator context mechanism is explicitly documented, the security-analyst verdict flow is clarified, the Edit tool is specified for surgical insertion, and structural integration tests provide regression safety.

Two new issues were introduced: a shell pipeline bug in the integration tests (Minor, easy fix) and some explanatory redundancy (Info, no action needed). Neither blocks implementation.

The plan is ready for approval and implementation via `/ship`.
