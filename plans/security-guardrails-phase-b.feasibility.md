# Feasibility Review: Security Guardrails Phase B (Rev 2)

**Plan:** `./plans/security-guardrails-phase-b.md`
**Reviewer:** code-reviewer agent (standalone)
**Date:** 2026-03-26
**Revision reviewed:** Rev 2 (post red-team FAIL + librarian + feasibility)
**Scope:** Technical feasibility of embedding security guardrails into /ship v3.4.0, /architect v3.0.0, and /audit v3.0.0

---

## Verdict: PASS

Rev 2 resolves all three prior Major feasibility concerns (F-M1, F-M2, F-M3) and the remaining revisions from the red team and librarian reviews are well-integrated. The plan remains technically feasible and implementable in a single `/ship` run. Two new Minor concerns are identified below but neither is blocking.

---

## Prior Concerns Resolution Status

### F-M1: `--security-override` parsing sequencing -- RESOLVED

**Original concern:** Parsing was not anchored to a specific location; `$ARGUMENTS` could leak `--security-override` into coder/reviewer prompts.

**How Rev 2 resolves it:** Task 7 in the implementation plan (line 627) now explicitly states: "Insert as the **very first action** in Step 0, BEFORE run ID generation, BEFORE any other use of `$ARGUMENTS`." The plan adds language: "After extraction, `$ARGUMENTS` contains ONLY the plan path for all subsequent steps." The Proposed Design section (line 181) mirrors this with: "Extract `--security-override` as the very first action in Step 0, before `$ARGUMENTS` is used for any other purpose."

**Verification against current skill:** The current `/ship` SKILL.md uses `$ARGUMENTS` in six locations (lines 10, 77, 89, 175, 254, 451, 486). The first non-declaration use is line 77 (Step 1 -- "Read the plan file at `$ARGUMENTS`"). The run ID generation in Step 0 (line 26) does not reference `$ARGUMENTS`. Therefore, placing the override extraction as the first Step 0 action is safe -- no `$ARGUMENTS` use precedes it in the current skill. The parsing block at line 631 correctly specifies storing the reason, stripping the flag, and leaving only the plan path. This is correct.

**Status:** Fully resolved. No remaining risk.

### F-M2: Internal contradiction in /audit output filenames -- RESOLVED

**Original concern:** The Interfaces section referenced `secure-review-[timestamp].summary.md` while the Implementation section correctly used `audit-[timestamp].security.md`.

**How Rev 2 resolves it:** Rev 2 change #3 (line 16) explicitly states: "Resolved audit output filename contradiction. Standardized on `audit-[timestamp].security.md` throughout." Verification: the Proposed Design (section 3a, line 236), Interfaces (line 293), Implementation Plan (Step B3, task 20, line 806-810), and the subagent prompt all consistently reference `audit-[timestamp].security.md`. The synthesis step (Step 5 in /audit) reads this filename at line 210, confirming zero synthesis-side changes are needed.

**Status:** Fully resolved. No remaining risk.

### F-M3: python3 for config read justification -- RESOLVED

**Original concern:** Inline `python3 -c` in a skill markdown file is unusual for a coordinator role that delegates work.

**How Rev 2 resolves it:** Rev 2 change #9 (line 22) adds a justification note in the implementation plan (lines 461-462): "Python 3 is available on all target platforms (macOS, Linux dev environments) and the `json` module handles edge cases (nested objects, whitespace, escaping) more reliably than regex-based alternatives. If `python3` is not available, the command silently fails and the maturity level defaults to `'advisory'` (L1) -- the safe default."

**Assessment:** The justification is sound. The silent failure behavior is the key property -- a missing `python3` binary or a malformed JSON file both result in the safe default (L1/advisory). The bash fallback semantics (`2>/dev/null || echo ""`) are correct. The `case` statement validation (line 479) catches invalid values from any source. This is acceptable.

**Status:** Fully resolved. No remaining risk.

---

## New Concerns Introduced by Rev 2

### Minor

**m1. The expanded keyword list (section 2b) includes high-frequency words that may cause false-positive threat model injection in `/architect`.**

The Rev 2 keyword list expansion (change #6) adds broad terms including: `file`, `path`, `url`, `import`, `export`, `query`, `database`, `backup`, `command`. These words appear frequently in non-security contexts:

- `/architect add CSV file import feature` -- triggers on "file" and "import"
- `/architect add database query optimization` -- triggers on "database" and "query"
- `/architect add URL shortener` -- triggers on "url"
- `/architect refactor command handler` -- triggers on "command"

The plan acknowledges this trade-off (line 211-212): "This heuristic is intentionally broad... It is better to include threat modeling in a plan that doesn't need it (minor overhead) than to skip it in a plan that does (security gap)." The plan's Deviation 3 (line 897) also documents this.

**Assessment:** The false-positive rate for words like `file`, `path`, `import`, `export`, `command`, and `query` will be high in practice. However, the plan correctly identifies the cost asymmetry: a false positive adds one `## Security Requirements` prompt to the architect (the architect can skip it or produce a brief "N/A" section), while a false negative misses threat modeling entirely. The keyword list is embedded inline in the skill, making it easy to tune after deployment.

**Recommendation:** Not blocking. After deployment, monitor false-positive rates on the first 5-10 `/architect` invocations. If more than 70% of non-security plans receive the threat model prompt, consider removing the highest-frequency offenders (`file`, `path`, `import`, `export`, `command`, `query`) or requiring two-keyword co-occurrence instead of single-keyword matching. This is a tuning exercise, not a design flaw.

**m2. The `REVISION_NEEDED + BLOCKED` revision loop entry (L2/L3 matrix, line 154) creates a compound remediation burden on coders with ambiguous priority.**

Rev 2 change #7 adds a row where code review returns REVISION_NEEDED and secure review returns BLOCKED. The action is: "Enter Step 5 (revision loop). Coders fix both code review and security findings. Re-run Step 4 after revision." This is correct behavior -- the coder should address both sets of findings before re-verification.

However, the coder's prompt in Step 5a (line 553-564 of current `/ship`) only references `./plans/[name].code-review.md`. The plan's Step 4 additions (line 605) say "Include security findings in coder instructions" but does not provide the exact prompt modification for Step 5a. The implementor will need to:

1. Detect that both code review (REVISION_NEEDED) and secure review (BLOCKED) require fixes
2. Modify the Step 5a coder prompt to reference BOTH `./plans/[name].code-review.md` AND `./plans/[name].secure-review.md`
3. Give the coder clear priority guidance (security findings first? code review findings first? interleaved?)

**Assessment:** This is implementable -- the coder prompt in Step 5a can be extended with a conditional append: "Also read `./plans/[name].secure-review.md` and address all security findings." The plan's intent is clear even if the exact prompt wording is not specified. The existing revision loop pattern (read review, fix issues, re-verify) applies naturally to both code review and security review findings.

**Recommendation:** Not blocking. When implementing task 4 (Step 4 additions), add an explicit note to task 7 (Step 0 parsing) or create a new sub-task specifying the Step 5a prompt extension for the compound case. Example: "If entering Step 5 due to both REVISION_NEEDED and BLOCKED, append to the coder prompt: 'Also read ./plans/[name].secure-review.md. Address all security findings alongside code review findings. Security findings take priority.'"

**m3. The `git diff HEAD -- <manifest>` approach (section 1c) has a timing dependency on Step 6's position in the workflow.**

Rev 2 change #5 switches dependency detection from plan-text heuristics to `git diff HEAD -- <manifest>`. This is an improvement over the Rev 1 approach (which scanned plan text). However, at Step 6 in `/ship`, the working directory contains uncommitted implementation changes but the WIP commits from Step 3a/5a may or may not have been created. The behavior of `git diff HEAD` depends on whether WIP commits exist:

- If Step 3a created a WIP commit AND Step 5a created a WIP commit: `HEAD` points to the Step 5a WIP commit. `git diff HEAD` shows only changes made after the last WIP commit.
- If Step 3a created a WIP commit but Step 5 was skipped: `HEAD` points to the Step 3a WIP commit. `git diff HEAD` shows changes made by coders in worktrees (merged in Step 3e).
- If no WIP commits were created (no shared deps, no revision loop): `HEAD` points to the pre-ship state. `git diff HEAD` shows all implementation changes.

In all three cases, manifest file changes will be visible in `git diff HEAD` because: (a) manifest files are rarely in shared dependencies, (b) even if a WIP commit staged manifest changes, the merged worktree output will include the final manifest state. The edge case is when a manifest file was modified in a shared dependency WIP commit but not subsequently changed -- `git diff HEAD` would show no diff because the WIP commit already contains the change. However, in practice, manifest changes from shared dependencies (e.g., adding a package) would be the exact scenario requiring a dependency audit.

**Assessment:** The `git diff HEAD` approach works correctly for the common case (manifest changed during implementation). The edge case (manifest changed only in shared deps WIP, then unchanged) means the audit might be skipped when it should run. This is a minor gap: shared dependency changes that add packages are rare, and the parent plan's Risk table already identifies dependency audit false negatives as low-probability.

**Recommendation:** Not blocking. Consider using `git diff HEAD~N` (where N is the number of WIP commits) or `git diff $(git rev-parse HEAD~N 2>/dev/null || echo HEAD)` to diff against the pre-ship baseline rather than the potentially-advanced HEAD. This would catch manifest changes from shared deps. However, this adds complexity to an already-complex Step 6. The current approach is acceptable for v1.0.

---

## What Went Well

1. **Comprehensive revision log.** Rev 2's detailed changes table (lines 10-22) maps every change to its source finding (C1, M1-M6, R2, F-M1, F-M3). This makes verification straightforward and demonstrates disciplined revision tracking.

2. **Maturity-level-aware result evaluation matrices are well-structured.** The L1 matrix (lines 137-144) correctly auto-downgrades secure-review BLOCKED to PASS_WITH_NOTES, while the L2/L3 matrix (lines 148-158) enforces hard stops. The matrices are complete -- every combination of code review, tests, QA, and secure review verdicts has a defined action. The addition of the `REVISION_NEEDED + BLOCKED` row (line 154) closes the gap identified by M6 in the red team review.

3. **The secrets-scan exception (Deviation 4) is correctly justified.** The argument that committed secrets require rotation (a permanent, costly remediation) and therefore justify blocking even at L1 is sound. The `--security-override` escape valve for false positives preserves developer ergonomics.

4. **The `git diff HEAD` manifest detection approach is a meaningful improvement over Rev 1's plan-text heuristic.** It catches unplanned dependency additions (a developer adds a package during implementation that wasn't in the plan) and avoids false positives from plans that mention manifest files for non-dependency reasons.

5. **Override governance limitations are honestly documented.** The "Known limitation (v1.0)" paragraph (lines 183) explicitly states that the blanket override lacks per-finding granularity, approver tracking, and structured audit records. This is the right approach -- ship the simple version, document its limitations, and defer the full L3 solution.

---

## Recommended Adjustments

Prioritized by importance:

1. **(Minor)** Add explicit Step 5a prompt modification for the `REVISION_NEEDED + BLOCKED` compound case. The coder needs to know to read both the code review and secure review artifacts. A one-line addition to the implementation plan's Step 4 section is sufficient.

2. **(Minor)** Monitor the expanded keyword list false-positive rate post-deployment. Consider a two-keyword co-occurrence threshold if single-keyword matching generates excessive threat model prompts for non-security plans.

3. **(Minor)** Consider using `git diff` against the pre-ship baseline (rather than current HEAD) for manifest detection in Step 6, to catch dependency changes made in shared deps WIP commits.

---

## Implementation Complexity Assessment (Updated)

| Work Group | Estimated Complexity | Notes |
|------------|---------------------|-------|
| B1: /ship security integration | **High** | 11 insertion points across Steps 0, 4, 5, and 6. New flag parsing (must be first). Two maturity-level-aware result evaluation matrices. Security override persistence across revision loops. Most complex of the three. |
| B2: /architect threat-model integration | **Low** | 3 insertion points. One new Glob, one conditional prompt append with keyword matching, one text replacement. Straightforward. |
| B3: /audit secure-review composability | **Low-Medium** | 1 insertion point at top of Step 2 with conditional logic to preserve fallback. Filename consistency confirmed -- no synthesis changes needed. |

The overall plan is implementable in a single `/ship` run with three parallel work groups. Rev 2 has increased the B1 complexity slightly (two matrices instead of one, compound revision loop case) but not enough to change the complexity rating or feasibility verdict.

---

<!-- Context Metadata
discovered_at: 2026-03-26T22:30:00Z
claude_md_exists: true
recent_plans_consulted: security-guardrails-phase-b.md
archived_plans_consulted: none
-->
