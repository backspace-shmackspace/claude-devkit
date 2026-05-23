# Red Team Review (Round 2): `/fix` Skill for Targeted Finding Remediation

**Reviewer:** Red Team (Critical Analysis + Security Analyst)
**Plan Version:** Rev 2 (2026-05-23)
**Review Date:** 2026-05-23
**Round:** 2 (re-review of Rev 2 addressing round 1 Major findings F-01, F-02, F-03)

## Verdict: PASS

All three round 1 Major findings are resolved. No new Critical or Major findings introduced by the revision. Two new Minor findings noted below.

---

## Round 1 Resolution

### F-01 (Major): Secrets scan bypass -- RESOLVED

**Round 1 issue:** Non-Goal 6 dismissed secrets scan as unnecessary, creating an unacknowledged bypass vector where a coder agent fixing a security finding could introduce a hardcoded credential.

**Rev 2 resolution:**

- Non-Goal 5 (renumbered) now explicitly acknowledges the gap and states a lightweight grep-based pattern check is included instead of a full `/secrets-scan` invocation.
- Step 2 adds a post-coder secret pattern check using `git diff -U0 | grep -inE` with a regex covering `api_key`, `api_secret`, `password`, `passwd`, `token`, `secret_key`, `access_key`, `private_key` patterns with assignment operators and minimum 8-character values.
- The check is warning-only (does not block), with redaction to first 4 / last 4 characters.
- The Security Controls section now lists "Secret Detection" as an explicit control.
- The Risks table includes "Coder introduces hardcoded secret in fix" with the grep check and code review as dual mitigations.

**Assessment:** The grep pattern is not exhaustive (e.g., it would miss `AWS_SECRET_ACCESS_KEY` without an assignment operator, base64-encoded credentials, or PEM private key blocks), but it provides a reasonable first-pass detection for the most common patterns. The warning-only approach is appropriate given that the code review in Step 3b provides a second check and `/fix` operates on small, focused diffs where a reviewer is more likely to notice secrets. The round 1 recommendation was to add a lightweight check or acknowledge the residual risk -- the revision does both. Resolved.

---

### F-02 (Major): Test numbering -- RESOLVED

**Round 1 issue:** Test insertion points were ambiguous. Test 57 in `test_skill_generator.sh` could run in the wrong location relative to Test 50 (Cleanup). Tests 28-29 in `test-integration.sh` needed explicit placement relative to Test 9 (Cleanup).

**Rev 2 resolution:**

- The test table now includes an "Insertion Point" column specifying exact placement:
  - Test 57: "Before Test 50 (Cleanup) block. Update header from 'up to 56 tests' to 'up to 57 tests'."
  - Tests 28-29: "Before Test 9 (Cleanup) block. Update header from '26 tests' to '28 tests'."
- The Rev 2 log confirms "numbers 57 and 28-29 confirmed correct."

**Verification against actual files:**

- `test_skill_generator.sh`: Tests 51-56 (audit logging) are placed between Test 49 and Test 50 (Cleanup) in the file. Test 50 (Cleanup) is the last test executed (line 568). The header says "up to 56 tests." Adding Test 57 before the Test 50 block is consistent with the existing pattern of out-of-sequence numbering (51-56 already follow this pattern). The implementer needs to insert Test 57 between line 566 (end of Test 54) and line 568 (Test 50 Cleanup). This is now clear.
- `test-integration.sh`: Test 27 is the last numbered test before Test 9 (Cleanup) at line 423. The header says "26 tests." Adding Tests 28-29 before the Test 9 block is correct.

**Assessment:** The insertion points are now unambiguous. An implementer following the plan will place tests correctly. Resolved.

---

### F-03 (Major): No structural file-scope enforcement -- RESOLVED

**Round 1 issue:** The coder was constrained only by prompt instructions and a Sonnet-class code review. No structural enforcement prevented modification of out-of-scope files.

**Rev 2 resolution:**

- Step 2 now includes a "Post-coder scope validation (structural enforcement)" substep with `git diff --name-only` checked against `$SCOPED_FILES`.
- Out-of-scope files are automatically reverted via `git checkout -- <out-of-scope-files>`.
- If ALL modified files are out-of-scope (no scoped files touched), the workflow stops entirely.
- Trust Boundary 2 now explicitly references "post-coder `git diff --name-only` scope validation."
- The STRIDE Elevation of Privilege row now lists four layers: "prompt scoping + structural validation + review + user confirmation."
- Failure Modes includes: "If coder modifies out-of-scope files: Out-of-scope changes reverted via `git checkout`. Scoped changes preserved."
- The Risks table lists the scope expansion risk with the full mitigation chain.

**Assessment:** The `git diff --name-only` check provides a structural guarantee that was missing in Rev 1. The automatic revert behavior is a good design choice -- it preserves the workflow rather than blocking it, which is appropriate for the small-fix use case where the coder might have touched an import statement in a related file. The "stop if no scoped files modified" guard prevents the degenerate case. Resolved.

---

## Round 1 Security-Analyst Supplement Gaps

The round 1 security-analyst supplement identified three gaps "requiring action":

1. **No structural file-scope enforcement (F-03):** Resolved (see above).
2. **Secrets scan exclusion (F-01):** Resolved (see above).
3. **Missing "Not applicable" annotations for Encryption, Rate Limiting, Secrets Management controls:** NOT addressed in Rev 2. However, this was documented as a gap within an "ADEQUATE" rating, not as a severity-rated finding. It remains a minor documentation gap. See NF-02 below.

Additional round 1 supplement gaps (not labeled as "requiring action"):

- **Trust boundary between coordinator and user:** Not added. The user gate exists at Step 1 ("Proceed? [Y/n]") but is not listed as an explicit trust boundary. This was an Info-level observation. Unchanged.
- **Failure mode for /secure-review crashing mid-execution:** Not added. The plan covers /secure-review not being deployed (graceful degradation) but not mid-execution crash. This was an Info-level observation. Unchanged.

**Assessment:** The two actionable security gaps (F-01, F-03) are resolved. The remaining gaps are documentation completeness items rated Info and do not affect the verdict.

---

## New Findings

### NF-01: Scope validation does not account for new (untracked) files (Minor)

**Location:** Step 2, post-coder scope validation

The `git diff --name-only` command only lists modifications to tracked files. If the coder creates a new file (e.g., a test fixture, a helper module), the new file would not appear in `git diff --name-only` output. It would appear in `git status` as an untracked file but would not be caught by the scope validation.

For a `/fix` use case (1-2 file fixes), new file creation is unlikely but not impossible -- for example, a coder fixing a missing error handler might create a new error types file.

**Recommendation:** Add `git ls-files --others --exclude-standard` to the scope check to catch untracked files. Or note this as a known limitation. This is Minor because the code review in Step 3b would likely catch unexpected new files.

---

### NF-02: Security Controls section still omits N/A annotations (Minor)

**Location:** Security Requirements > Security Controls

The round 1 security-analyst supplement noted that the threat-model-gate template expects explicit "Not applicable" entries for Encryption, Rate Limiting, and Secrets Management controls. Rev 2 added the "Secret Detection" control (addressing F-01) but did not add the N/A annotations for the remaining inapplicable controls.

This is a documentation completeness issue, not a security gap. The controls genuinely do not apply to a CLI skill that reads local files and delegates to subagents.

**Recommendation:** Add brief N/A annotations during implementation:
- Encryption: Not applicable (no network transmission, no data at rest encryption beyond git).
- Rate Limiting: Not applicable (CLI skill, single invocation).
- Secrets Management: Partially addressed by Secret Detection control; no secrets consumed or stored by this skill.

---

## Summary of Findings by Severity

| Severity | Count | Finding IDs |
|----------|-------|-------------|
| Critical | 0 | -- |
| Major | 0 | -- |
| Minor | 2 | NF-01, NF-02 |
| Info | 0 | -- |

## Round 1 Major Resolution Summary

| Finding | Status | Notes |
|---------|--------|-------|
| F-01 (secrets scan bypass) | RESOLVED | Lightweight grep check added to Step 2 + acknowledged in Non-Goal 5 and Risks table |
| F-02 (test numbering) | RESOLVED | Insertion Point column added, verified against actual file structure |
| F-03 (no file-scope enforcement) | RESOLVED | `git diff --name-only` structural check with auto-revert added to Step 2 |

**Verdict rationale:** All three round 1 Major findings are resolved with specific, verifiable changes. No new Critical or Major findings introduced. The two new Minor findings (NF-01: untracked file gap in scope check, NF-02: missing N/A annotations) are low-risk documentation and edge-case items that can be addressed during implementation without plan revision. The plan is ready for implementation.
