# Red Team Review: Security Guardrails Phase B (Rev 2)

**Plan reviewed:** `./plans/security-guardrails-phase-b.md` (Rev 2)
**Reviewer:** Security Analyst (red team role)
**Date:** 2026-03-26
**Standards applied:** STRIDE threat model, DREAD risk rating, project security-analyst agent standards
**Prior review:** Rev 1 red team review (FAIL, C1 present)

---

## Verdict: PASS

No Critical findings. The revision addressed the single Critical finding (C1) with a sound approach -- maturity-level-aware result evaluation with a justified deviation for secrets-scan. Six Major findings were addressed, five effectively and one partially. Two new findings introduced by the revision (one Major, one Minor). The plan is implementable.

---

## Prior Findings Resolution

### C1 -- L1 BLOCKED Behavior Contradicts Parent Plan: RESOLVED

The revision makes the result evaluation matrix maturity-level-aware (lines 135-161). At L1, secure-review and dependency-audit BLOCKED verdicts are auto-downgraded to PASS_WITH_NOTES with a prominent warning. This aligns with the parent plan's L1 definition: "BLOCKED verdicts are reported but do not prevent commit."

The plan correctly introduces an exception for secrets-scan: BLOCKED from secrets-scan blocks at ALL maturity levels including L1 (line 162, Deviation 4 in Context Alignment, lines 899). The justification is sound -- committed secrets require rotation, which is a uniquely costly remediation that justifies blocking even at advisory maturity. The `--security-override` escape valve still applies for false positives. This is a well-reasoned deviation, properly documented with its own Context Alignment entry.

Manual test 1 (line 361) has been updated to verify the L1 non-blocking semantics for non-secrets gates, confirming the test plan aligns with the new behavior.

**Status: Resolved.** The approach is clean and the deviation is well-justified.

---

### M1 -- Override Governance Gap: RESOLVED

The revision adds a "Known limitation (v1.0)" paragraph to section 1d (lines 183). It explicitly documents that `--security-override` is a blanket override with no per-finding scoping, no approver field, and no structured audit record. It states this is "insufficient for full L3 compliance audit requirements" and defers per-finding granularity to a future enhancement.

This is exactly what was recommended: document the limitation rather than pretend it does not exist. The language is clear and appropriately scoped -- acceptable for L1/L2, explicitly insufficient for L3.

**Status: Resolved.**

---

### M2 -- Secrets Scan Scope (Staged vs All): RESOLVED

The revision changes the secrets scan scope from `staged` to `all` (line 121, line 525). The rationale is documented in Rev 2 change #2: "Step 0 requires a clean working directory so there are no staged files; scanning 'all' catches secrets in the codebase."

The scope `all` scans the entire working directory, which catches secrets in any tracked or untracked file. This addresses the original concern that scanning staged files would scan an empty set. The subagent prompt (line 525) explicitly says "scope `all` against the current repository working directory."

**Status: Resolved.**

---

### M3 -- Dependency Audit Uses Actual File Changes: RESOLVED

The revision replaces the plan-text heuristic with actual `git diff HEAD` on manifest files (lines 166-168, implementation at lines 656-664). The bash script iterates over eight known manifest file types and diffs each against HEAD. This catches both planned and unplanned dependency additions, addressing the original false-negative concern about unplanned `npm install malicious-package`.

The approach is sound. One observation: the `git diff HEAD` output includes all changes to the manifest file, not just dependency-section additions. A version bump in `package.json`'s `version` field would produce a diff, which the coordinator must then interpret. The plan's language says "If any manifest file diff shows additions in dependency sections" (line 666), which means the coordinator (an LLM) makes the judgment call about whether the diff represents actual dependency changes. This is acceptable -- the LLM can distinguish a version field change from a new dependency entry, and a false positive (running dependency audit on a non-dependency change) is low cost.

**Status: Resolved.**

---

### M4 -- Keyword List Expanded: RESOLVED

The revision expands the security-sensitive keyword list with five new categories (lines 207-210): file operations, cryptography/network, data/compliance, file/process, and payment. The expanded list covers OWASP Top 10 (injection via `exec`/`eval`/`sql`, SSRF via `redirect`/`proxy`/`url`, broken access control via `rbac`/`acl`/`permission`) and CWE Top 25 (path traversal via `path`/`upload`, command injection via `exec`/`shell`/`subprocess`).

The keywords are organized by threat category (Identity/Auth, Cryptography/Network, Data/Compliance, File/Process, Payment), which makes maintenance easier. The list is present in both the Proposed Design (section 2b, lines 207-210) and the Implementation Plan (Step B2, task 15, lines 746-750), which is consistent.

**Status: Resolved.**

---

### M5 -- /audit Scope Mapping "code" to "changes": NOT RESOLVED (Misattributed)

The Rev 2 change log (line 17, change #3) claims to resolve "M5 (Red Team)" but addresses the audit output filename issue, which was **m1** (minor) in the original review, not M5. The actual M5 finding -- that mapping audit scope `code` to secure-review scope `changes` is semantically wrong when the working directory is clean -- was not addressed.

The plan still maps `audit code` to `secure-review changes` (line 242, line 804). The original concern remains: when a developer runs `/audit code` standalone (not during `/ship`), the working directory may be clean because the developer already committed. The `changes` scope in `/secure-review` examines uncommitted modifications, which would be empty, producing a vacuous "no findings" result.

However, on re-evaluation, this is a narrower issue than originally framed. The `/audit` skill's own definition of `code` scope (verified in the actual skill file at `skills/audit/SKILL.md`) says: "Scan uncommitted changes" -- so `/audit code` is designed for uncommitted changes, and the mapping to `changes` is actually semantically correct within the `/audit` skill's own scope definition. The concern about developers running `/audit code` after committing is valid but is a pre-existing limitation of `/audit`'s scope model, not a flaw introduced by this plan.

**Status: Partially Resolved.** The mapping is consistent with `/audit`'s existing scope definitions. The concern about post-commit usage is a pre-existing limitation. However, the Rev 2 change log misattributes the m1 filename fix as the M5 resolution, which is a documentation error. The actual M5 finding should be acknowledged with a note that the mapping is correct per `/audit`'s scope model.

---

### M6 -- REVISION_NEEDED + BLOCKED Enters Revision Loop: RESOLVED

The revision adds a dedicated row to the L2/L3 result evaluation matrix (line 154, line 604-605):

> `REVISION_NEEDED | Any | Any | BLOCKED | Enter Step 5 (revision loop). Coders fix security AND code review findings. Re-run Step 4 after revision.`

This explicitly addresses the dead-end scenario where code review returns REVISION_NEEDED and secure review returns BLOCKED simultaneously. The coder now enters the revision loop and addresses both sets of findings. BLOCKED only stops the workflow after the revision loop is exhausted (line 158, line 609).

An additional row handles the post-revision case (line 158): `Any | Any | Any | BLOCKED (no override, revision loop exhausted) | Stop workflow.`

This is the exact behavior recommended in the original finding.

**Status: Resolved.**

---

### m1 -- /audit Output Filename Consistency: RESOLVED

The Rev 2 change log (change #3) standardizes on `audit-[timestamp].security.md` throughout. The old reference to `secure-review-[timestamp].summary.md` has been eliminated (confirmed: no matches for that pattern in the revised plan). The Proposed Design (line 236), Interfaces section (line 293), and Implementation Plan (lines 806, 810) all use the audit naming convention consistently. Step 5 requires no changes.

**Status: Resolved.**

---

### m2 -- Python3 Config Read Justification: RESOLVED

The revision adds a justification note (lines 461-462): "Python 3 is available on all target platforms (macOS, Linux dev environments) and the `json` module handles edge cases (nested objects, whitespace, escaping) more reliably than regex-based alternatives." It also documents the safe failure mode: "If `python3` is not available, the command silently fails and the maturity level defaults to `'advisory'` (L1) -- the safe default."

**Status: Resolved.** The justification is reasonable and the failure mode is documented.

---

### m3 -- No Test for --security-override Without Reason String: NOT RESOLVED

The revision does not add a negative test for invoking `--security-override` without a reason string. The manual test plan (lines 361-381) still contains 11 tests, unchanged from Rev 1. This was a minor finding and remains minor.

**Status: Not Resolved.** Severity remains Minor -- not blocking.

---

### m4 -- Test Suite Renamed Skill References: NOT RESOLVED

The revision does not add a concrete pre-condition check for stale `dream` references in the test suite. The risk table (line 337) still acknowledges this as a risk but provides no mitigation step. This was a minor finding and remains minor.

**Status: Not Resolved.** Severity remains Minor -- not blocking.

---

### m5 -- Rollback Assumes Single Commit: NOT RESOLVED

The revision does not update the rollback command (line 322) to use a specific commit hash instead of relative `HEAD~1`. The rollback still assumes all three files are committed in a single commit. This was a minor finding and remains minor. The feasibility review (m7) made the same observation and suggested adding a note about the single-commit assumption.

**Status: Not Resolved.** Severity remains Minor -- not blocking.

---

### m6 -- Secrets Scan Subagent Model Consistency: NOT RESOLVED

The revision does not address the question of whether the dispatcher's model choice should match the skill's declared model. The secrets-scan subagent is still dispatched with `model=claude-sonnet-4-5` (line 519) and the secure-review subagent with `model=claude-opus-4-6` (line 555). This was a minor finding and remains minor -- the model choices appear intentional and are not incorrect.

**Status: Not Resolved.** Severity remains Minor -- not blocking.

---

### i1 -- CLAUDE.md Registry Stale: NO ACTION NEEDED

Informational. Correctly deferred to Phase C.

---

### i2 -- Parallel Work Groups: NO ACTION NEEDED

Informational. No change expected.

---

## Prior Findings Resolution Summary

| # | Severity | Finding | Status |
|---|----------|---------|--------|
| C1 | Critical | L1 BLOCKED behavior contradicts parent plan | **Resolved** |
| M1 | Major | Override governance gap | **Resolved** |
| M2 | Major | Secrets scan scope (staged vs all) | **Resolved** |
| M3 | Major | Dependency audit uses plan metadata | **Resolved** |
| M4 | Major | Keyword list gaps | **Resolved** |
| M5 | Major | /audit scope mapping code to changes | **Partially Resolved** (misattributed in change log, but mapping is correct per audit scope model) |
| M6 | Major | REVISION_NEEDED + BLOCKED dead-end | **Resolved** |
| m1 | Minor | /audit output filename consistency | **Resolved** |
| m2 | Minor | Python3 config read justification | **Resolved** |
| m3 | Minor | No test for override without reason | **Not Resolved** (remains Minor) |
| m4 | Minor | Test suite renamed skill references | **Not Resolved** (remains Minor) |
| m5 | Minor | Rollback assumes single commit | **Not Resolved** (remains Minor) |
| m6 | Minor | Subagent model consistency | **Not Resolved** (remains Minor) |
| i1 | Info | CLAUDE.md registry stale | No action needed |
| i2 | Info | Parallel work groups | No action needed |

**Critical resolved:** 1/1 | **Major resolved:** 5/6 (1 partially) | **Minor resolved:** 2/6 | **Info:** N/A

---

## New Findings

### N-M1 -- Rev 2 Change Log Misattributes M5 Resolution (Major)

**Description:** The Rev 2 change log (line 17, change #3) claims to resolve "M5 (Red Team)" but the change described -- standardizing audit output filenames -- actually resolves **m1** (Minor), not **M5** (Major). The original M5 finding was: "/audit Scope Mapping 'code' to 'changes' Is Semantically Wrong." The original m1 finding was: "/audit Output Filename Change Creates Fragile Coupling."

This misattribution means:
1. The change log falsely claims a Major finding is resolved when it actually resolved a Minor finding.
2. The actual M5 finding is unaddressed in the change log (though it is partially mitigated by the fact that the mapping is consistent with `/audit`'s scope model).

**Impact:** Traceability. Anyone reviewing the revision history would believe M5 (scope mapping) was addressed, when in fact it was m1 (filename consistency) that was addressed. If this plan is audited for compliance with the red team review process, the misattribution would raise questions about review rigor.

**Recommendation:** Correct the change log entry to attribute the filename fix to "m1 (Red Team) + R2 (Librarian) + F-M2 (Feasibility)". Add a separate entry for M5 acknowledging that the scope mapping is correct per `/audit`'s existing scope definitions, with a note that the concern about post-commit usage is a pre-existing limitation of `/audit`'s scope model, not a Phase B issue.

---

### N-m1 -- Security Override Persistence Across Revision Loops Unspecified (Minor)

**Description:** The feasibility review (m6) raised this concern: when Step 5 (revision loop) re-runs Step 4, does the `--security-override` flag persist? The plan does not explicitly state whether the override applies only to the first Step 4 execution or to all subsequent re-runs during revision loops.

The Rev 2 change log does not list the feasibility review's m6 finding as addressed. The plan's Step 4 and Step 5 sections do not mention override persistence. This creates an ambiguity: if a developer uses `--security-override` and enters the revision loop, the re-run of Step 4 may or may not apply the override to the new secure-review results.

**Impact:** At L2, if the override does not persist, the revision loop could produce a BLOCKED verdict on the re-run even though the developer already provided an override. This would be confusing. If the override does persist, the developer might bypass a new security finding introduced during the revision (a different finding from the original false positive). Both interpretations have trade-offs.

**Recommendation:** Add explicit language to the Step 4/Step 5 interaction: "The `--security-override` flag is a per-invocation setting that applies to all Step 4 executions within the same `/ship` run, including re-runs during the revision loop." This is the simpler and more predictable behavior.

---

### N-m2 -- Manifest File List Missing Lock Files (Minor)

**Description:** The dependency audit manifest file list (line 659) includes: `package.json requirements.txt pyproject.toml Pipfile go.mod Cargo.toml pom.xml Gemfile`. This list does not include lock files (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Pipfile.lock`, `go.sum`, `Cargo.lock`, `Gemfile.lock`).

Dependency additions are often more visible in lock files than in manifest files. A developer using `npm install --save-dev some-package` modifies both `package.json` and `package-lock.json`, but a developer using `npm install some-package` without `--save` modifies only `package-lock.json` (on older npm versions) or both (on newer npm versions). More importantly, lock file diffs are authoritative -- they show exactly which transitive dependencies were resolved, including potentially vulnerable sub-dependencies.

**Impact:** Low. The primary manifest files (`package.json`, etc.) are the correct trigger for dependency audits because they represent intentional dependency changes. Lock file changes without manifest file changes typically indicate transitive dependency resolution, which the dependency-audit skill's CLI scanners (`npm audit`, `pip-audit`, etc.) will examine anyway when invoked. However, edge cases exist where lock-file-only changes introduce vulnerable transitive dependencies that would be missed by the manifest-only trigger.

**Recommendation:** Consider adding lock files to the manifest list in a future iteration. For Phase B v1.0, the manifest-only approach is acceptable because the dependency-audit skill itself runs the CLI scanner against the full dependency tree, not just the diff.

---

### N-i1 -- Feasibility Review Findings Not Fully Tracked in Change Log (Info)

**Description:** The Rev 2 change log tracks three feasibility review findings (F-M1, F-M2, F-M3) but the feasibility review raised seven findings (M1/F-M1, M2/F-M2, M3/F-M3, plus m1 through m7). Of the feasibility minor findings, m5 (WIP commit message version) and m6 (override persistence across revision loops) are not addressed in the revision. The m6 finding is elevated to N-m1 above as a new finding because it was not addressed.

**Impact:** Informational. The unaddressed feasibility minor findings are low severity.

---

## STRIDE Analysis (Supplemental)

### Spoofing: Can security gates be bypassed by spoofing inputs?

**Risk Level:** Medium (unchanged from Rev 1)

**Rev 2 Assessment:** The original STRIDE analysis identified that `.claude/settings.local.json` can override `.claude/settings.json` to downgrade maturity from L2 to L1. Rev 2 does not address this -- it is inherent in the Claude Code settings precedence model. The plan correctly documents that local overrides project settings (line 261).

**New concern from Rev 2:** The secrets-scan exception (Deviation 4) means that even at L1, secrets-scan BLOCKED halts the workflow. This actually reduces the spoofing surface for secrets -- even if a developer downgrades maturity to L1, secrets scanning still blocks. However, secure-review and dependency-audit BLOCKED verdicts are now non-blocking at L1, so the maturity downgrade attack is more effective for non-secrets security findings.

**DREAD Rating:**
- Damage Potential: 6/10 (security vulnerabilities can ship at L1)
- Reproducibility: 9/10 (trivial to create `.claude/settings.local.json`)
- Exploitability: 9/10 (no special skill required)
- Affected Users: 3/10 (only teams that set L2/L3 are affected by downgrade)
- Discoverability: 4/10 (requires knowledge of settings precedence)
- **DREAD Score:** 6.2/10

**Mitigation:** Documented as a known limitation. For teams requiring enforcement, commit `.claude/settings.json` with maturity level to git and monitor for `.claude/settings.local.json` overrides.

### Tampering: Can maturity levels or override flags be tampered with?

**Risk Level:** Medium (unchanged from Rev 1)

**Rev 2 Assessment:** The override governance documentation (M1 resolution) explicitly acknowledges that the blanket override is insufficient for L3 compliance. This transparency is a mitigation in itself -- the plan no longer implies L3 compliance that does not exist.

The free-text override reason remains unvalidated. A developer can still use `--security-override "."` to bypass with a meaningless reason. Rev 2 does not add reason validation (minimum length, structured format, ticket reference). This is acceptable for L1/L2 but, as the plan now explicitly states, insufficient for L3.

**DREAD Rating:**
- Damage Potential: 5/10 (security findings bypassed with weak justification)
- Reproducibility: 9/10 (trivial to provide a meaningless reason)
- Exploitability: 9/10 (no special skill required)
- Affected Users: 5/10 (all users of `--security-override`)
- Discoverability: 7/10 (flag is documented and visible)
- **DREAD Score:** 7.0/10

**Mitigation:** The override reason appears in the git commit message (`Security-Override: [reason]`), which provides a compensating control via code review of commit history. For L3, per-finding override governance is documented as a future enhancement.

### Repudiation: Are security overrides properly logged?

**Risk Level:** Low-Medium (unchanged from Rev 1)

**Rev 2 Assessment:** The logging approach is unchanged. Override reasons are logged in commit message footers and (at L3) in archived security reports. The git commit author serves as an implicit record of who used the override.

The Rev 2 Known Limitation section (line 183) explicitly calls out the lack of an approver field as a gap. This is honest documentation rather than a mitigation, but it prevents the plan from claiming audit capabilities it does not have.

**DREAD Rating:**
- Damage Potential: 4/10 (override is traceable via git, just not structured)
- Reproducibility: 3/10 (requires an override scenario to test)
- Exploitability: 5/10 (moderate -- commit author is implicit, not explicit)
- Affected Users: 3/10 (only L3 teams need structured audit)
- Discoverability: 6/10 (commit messages are visible to reviewers)
- **DREAD Score:** 4.2/10

**Mitigation:** Acceptable for v1.0. The commit message provides reasonable non-repudiation. Structured audit records are a documented future enhancement.

### Information Disclosure: Do security scan results leak sensitive data?

**Risk Level:** Low (unchanged from Rev 1)

**Rev 2 Assessment:** Redaction rules are unchanged. All three subagent prompts include the "CRITICAL: Never include actual secret values" instruction. The prompt-based approach remains the primary control with no programmatic post-verification.

No new information disclosure risks introduced by Rev 2.

**DREAD Rating:**
- Damage Potential: 7/10 (leaked secrets in reports are high impact)
- Reproducibility: 2/10 (LLM redaction failure is rare)
- Exploitability: 1/10 (requires LLM to malfunction)
- Affected Users: 2/10 (only affects users with secrets in codebase)
- Discoverability: 5/10 (reports are readable by anyone with repo access)
- **DREAD Score:** 3.4/10

**Mitigation:** Acceptable for v1.0. Defense-in-depth (running secrets-scan against generated reports) remains a future enhancement recommendation.

### Denial of Service: Can security gates create workflow deadlocks?

**Risk Level:** Low (unchanged from Rev 1)

**Rev 2 Assessment:** The revision loop interaction with security BLOCKED (M6 resolution) actually reduces the DoS risk. In Rev 1, REVISION_NEEDED + BLOCKED was a dead-end. In Rev 2, the workflow enters the revision loop and gives the coder a chance to fix security findings. BLOCKED only stops the workflow after the revision loop is exhausted. This is a more resilient design.

The concern about subagent timeouts remains a pre-existing limitation of the `/ship` workflow, not a Phase B issue.

**DREAD Rating:**
- Damage Potential: 3/10 (workflow blocked, but retryable)
- Reproducibility: 2/10 (requires subagent to hang)
- Exploitability: 1/10 (not intentionally exploitable)
- Affected Users: 10/10 (all `/ship` users)
- Discoverability: 8/10 (obvious when workflow hangs)
- **DREAD Score:** 4.8/10

**Mitigation:** Acceptable. The revision loop improvement reduces the effective DoS surface.

### Elevation of Privilege: Can --security-override bypass intended controls?

**Risk Level:** Medium (reduced from Rev 1 due to L1 non-blocking)

**Rev 2 Assessment:** The blanket override concern from Rev 1 remains -- `--security-override` bypasses all three security gates simultaneously. However, the risk is reduced at L1 because security gates are non-blocking at L1 anyway (except secrets-scan). The override is only needed at L2/L3, where a developer is already operating in a more security-conscious context.

The Known Limitation section (line 183) explicitly documents the blanket override as a gap, which reduces the risk of implicit trust in the override's granularity.

The original attack scenario (developer uses a false positive in secrets-scan to simultaneously bypass secure-review BLOCKED) is still possible at L2/L3 but is now explicitly documented as a known limitation rather than an unacknowledged gap.

**DREAD Rating:**
- Damage Potential: 6/10 (collateral bypass of genuine security findings)
- Reproducibility: 5/10 (requires a false positive to justify the override)
- Exploitability: 4/10 (requires developer to intentionally misuse the override)
- Affected Users: 3/10 (only L2/L3 users need overrides)
- Discoverability: 7/10 (override is visible in commit messages)
- **DREAD Score:** 5.0/10

**Mitigation:** Documented as a known limitation. Per-gate override granularity is a documented future enhancement.

### STRIDE Summary

| Category | Risk | Rev 1 | Rev 2 | Trend | Notes |
|----------|------|-------|-------|-------|-------|
| Spoofing | Local settings downgrade | Medium | Medium | Stable | Inherent in settings model |
| Tampering | Weak override reason | Medium | Medium | Stable | Now documented as known limitation |
| Repudiation | No approver field | Low-Medium | Low-Medium | Stable | Now documented as known limitation |
| Information Disclosure | Secret leakage in reports | Low | Low | Stable | Prompt-based redaction adequate for v1.0 |
| Denial of Service | Workflow deadlocks | Low | Low | Improved | Revision loop reduces dead-end risk |
| Elevation of Privilege | Blanket override bypass | Medium | Medium | Improved | Now documented; L1 non-blocking reduces surface |

**Overall STRIDE Assessment:** The security architecture is sound for a v1.0 implementation. The primary risks (maturity level spoofing, blanket override) are inherent in the trust model and are appropriately documented as known limitations. No STRIDE finding reaches Critical severity. The revision improved the DoS and EoP posture through the revision loop fix and L1 non-blocking semantics.

---

## New Findings Summary

| # | Severity | Finding |
|---|----------|---------|
| N-M1 | Major | Rev 2 change log misattributes M5 resolution (filename fix attributed to M5 instead of m1; actual M5 scope mapping issue unacknowledged) |
| N-m1 | Minor | Security override persistence across revision loops unspecified |
| N-m2 | Minor | Manifest file list missing lock files |
| N-i1 | Info | Feasibility review minor findings not fully tracked in change log |

**Critical:** 0 | **Major:** 1 | **Minor:** 2 | **Info:** 1

---

## Overall Assessment

The Rev 2 revision demonstrates thorough engagement with the original findings. The Critical finding (C1) was resolved with a nuanced approach that balances the parent plan's L1 definition with the practical reality of secrets exposure. The maturity-level-aware result evaluation matrix is well-designed and covers the edge cases (REVISION_NEEDED + BLOCKED, post-revision exhaustion).

The single new Major finding (N-M1) is a documentation/traceability issue, not an architectural flaw. It does not affect the technical correctness of the plan. The two new Minor findings are edge cases that can be addressed in future iterations.

The plan is ready for implementation.

---

<!-- Review Metadata
reviewed_at: 2026-03-26T23:30:00Z
plan_version: Rev 2
prior_review_version: Rev 1
parent_plan: agentic-sdlc-security-skills.md (Rev 3)
standards_applied: STRIDE, DREAD, embedding-security-in-agentic-sdlc.md, security-analyst agent
verdict: PASS (no Critical findings)
prior_findings_resolved: C1, M1, M2, M3, M4, M6, m1, m2
prior_findings_partially_resolved: M5
prior_findings_not_resolved: m3, m4, m5, m6
new_findings: N-M1 (Major), N-m1 (Minor), N-m2 (Minor), N-i1 (Info)
-->
