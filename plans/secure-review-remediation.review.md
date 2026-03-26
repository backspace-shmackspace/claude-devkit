# Librarian Review: secure-review-remediation.md (Rev 2)

**Reviewed:** 2026-03-26
**Reviewer:** Librarian (automated)
**Plan:** Secure Review Remediation (High + Medium Findings) -- Revision 2
**Prior Review:** Rev 1 review issued PASS with 3 required edits
**Verdict:** PASS

---

## Summary

Revision 2 of the remediation plan incorporates all feedback from the red team (FAIL with 2 Critical, 4 Major), the feasibility review (PASS with 3 Major recommendations), and the prior librarian review (PASS with 3 required edits). The plan now remediates all 5 High and 8 Medium findings (with 4 Medium explicitly deferred with justification), across 6 work groups with clean file boundaries, and is ready for `/ship` execution.

---

## Prior Required Edits -- Resolution Status

### R-1: Remove WG-5 Step 3 (`git rm --cached`) -- RESOLVED

**Original issue:** The previous plan revision contained a WG-5 Step 3 that ran `git rm --cached .claude/settings.local.json` on a file that was already untracked. This would fail at runtime.

**Resolution:** Rev 2 removes the step entirely. The WG-5 section (line 668) now includes an explicit note: "`.claude/settings.local.json` is already NOT tracked by git (`git ls-files .claude/settings.local.json` returns empty). No `git rm --cached` is needed." The WG-5 validation section (lines 709-719) correctly expects the file is already untracked. Acceptance Criterion 6 (line 874) states: "file was already untracked; gitignore prevents accidental future tracking." Verified: `git ls-files .claude/settings.local.json` returns empty on the current repo.

### R-2: Phase 3 Step 1 structural ambiguity -- RESOLVED

**Original issue:** Phase 3 Step 1 described the `deploy.sh` path traversal fix as if it were a Phase 3 deliverable, when it was already fully specified in WG-2.

**Resolution:** Rev 2 replaces Phase 3 Step 1 with a forward reference (line 798): "Note: The `deploy.sh` path traversal fix is included in Phase 1 WG-2 (Steps 5-8 above). No separate Phase 3 work is needed for `deploy.sh`." The deploy.sh steps (Steps 5-8) are now integrated directly into the WG-2 step list (lines 393-428), and the previously orphaned section is removed. The WG-2 file list correctly includes `scripts/deploy.sh`. No ambiguity remains.

### R-3: Wording about settings.local.json tracking status -- RESOLVED

**Original issue:** Assumption 3 incorrectly stated the file "should not be tracked in git going forward," implying it was currently tracked.

**Resolution:** Rev 2 Assumption 3 (line 37) now reads: "The `.claude/settings.local.json` file is machine-specific and is not currently tracked in git; adding it to `.gitignore` prevents accidental future tracking." This is factually accurate.

---

## Conflicts with CLAUDE.md Rules

None found. The plan follows all applicable CLAUDE.md development rules:

- **"Edit source, not deployment"** -- All skill modifications target `skills/*/SKILL.md`, not `~/.claude/skills/` (verified for WG-3 and WG-6).
- **"Validate before committing"** -- The plan includes `validate_skill.py` runs for both modified skills (`secrets-scan`, `ship`) in the validation sections and Phase 3 Step 3.
- **"Follow v2.0.0 patterns"** -- Modified skills retain all 10 architectural patterns. No structural patterns are removed.
- **"One skill per directory"** -- No directory structure changes.
- **"Core vs Contrib"** -- WG-4 modifies contrib skills appropriately (PII scrubbing in `contrib/journal/SKILL.md` and `contrib/journal-review/SKILL.md`).
- **Conventional commits** -- `fix(security):` prefix specified in the rollout plan (line 822).
- **Generators must use atomic writes** -- Enforced by porting `atomic_write()` to both `generate_agents.py` (WG-2) and `generate_senior_architect.py` (WG-1).
- **Three-tier architecture** -- Changes respect tier boundaries: skills (WG-3, WG-6), generators (WG-1, WG-2), templates (WG-4), configs (WG-5).

---

## Historical Alignment

- **Consistent with `agentic-sdlc-security-skills.md` (APPROVED, Phase A shipped in bcdce1f).** The parent plan created the 5 security skills. This remediation plan fixes implementation-level issues found by running those skills. The `/secrets-scan` temp file fix (WG-3) and `/ship` hardening (WG-6) are natural corrections not foreseen by the parent plan. No design contradictions.

- **Consistent with `agentic-sdlc-security-skills.md` Phase B scope.** WG-6 modifies `skills/ship/SKILL.md` for safety hardening (replacing `git add -A`, adding branch protection). Phase B of the parent plan also targets `/ship` for security gate integration. The changes are orthogonal -- safety hardening vs. workflow integration -- and should not conflict. The implementer should be aware that Phase B will also modify `/ship`.

- **Consistent with prior worktree isolation changes.** WG-6 changes to `/ship` do not affect worktree isolation mechanics (Step 2a-2f).

- **No contradictions found with any other plan** in `./plans/`.

---

## Context Alignment Section

The `## Context Alignment` section (lines 899-917) is substantive. It includes:

1. **CLAUDE.md Patterns Followed** -- 6 specific patterns mapped with explanations (lines 901-907).
2. **Prior Plans Referenced** -- 3 prior plans cited with their status and relationship to this plan (lines 909-912). All 3 referenced plans exist on disk and have been verified.
3. **Deviations from Established Patterns** -- 3 explicit deviations with justifications (lines 914-917): gitignore addition, deprecation-over-deletion, and M-2 deferral. Each deviation is explained and defensible.

---

## Context Metadata Block

The context metadata block (lines 929-936) is present and accurate:

- `discovered_at: 2026-03-26T14:42:00Z` -- matches the scan archive timestamp.
- `revised_at: 2026-03-26` -- accurate for Rev 2.
- `claude_md_exists: true` -- verified, CLAUDE.md exists.
- `recent_plans_consulted` -- lists 3 plans; all exist on disk.
- `archived_plans_consulted` -- references `secure-review-2026-03-26T14-42-21` with 4 report types (summary, vulnerability, dataflow, authz); all 4 files exist in the archive directory.
- `review_files_addressed` -- lists all 3 review files (redteam, librarian, feasibility) with their original verdicts and resolution status. All 3 review files exist on disk.

---

## Work Group / `/ship` Compatibility

- **File boundaries are clean.** No file appears in more than one work group across all 6 WGs. Verified against the Task Breakdown Summary table (lines 888-896). The Rev 2 consolidation (all `generate_senior_architect.py` changes into WG-1) resolved the prior file boundary violation flagged by the red team (F-3).

- **All 6 work groups are parallel-safe** within their respective phases. Phase 1 (WG-1 through WG-4) has no inter-dependencies. Phase 2 (WG-5 and WG-6) has no inter-dependencies.

- **Phase ordering is correctly specified.** Phase 2 does not depend on Phase 1 outputs. Phase 3 depends on both Phase 1 and Phase 2.

- **Validation sections are concrete.** Each work group includes bash validation commands that can be executed by a `/ship` QA step. The Test Plan (lines 838-866) includes 20 manual verification items covering all work groups.

---

## Red Team and Feasibility Findings -- Integration Verification

Rev 2 claims to address all red team required actions (F-1 through F-6, F-10) and all feasibility Major recommendations (M-1 through M-4). Verification:

| Finding | Resolution in Rev 2 | Status |
|---------|---------------------|--------|
| **RT F-1** (generate_skill.py format_map dropped) | Added to WG-2 Step 4 (lines 372-391) | Resolved |
| **RT F-2** (generate_senior_architect.py missing validate_target_dir/atomic_write) | Consolidated into WG-1 Steps 3-4 (lines 131-209) | Resolved |
| **RT F-3** (file boundary violation) | All generate_senior_architect.py changes in WG-1 only (lines 90-257) | Resolved |
| **RT F-4** (WG-6 git add under-specified) | Rewritten with concrete pattern and instruction paragraph (lines 733-755) | Resolved |
| **RT F-5** (deploy.sh fix placement) | Integrated into WG-2 Steps 5-8 (lines 393-428) | Resolved |
| **RT F-6** (double-brace validation) | Added WG-1 Step 7 with grep validation command (lines 224-228) | Resolved |
| **RT F-10** (acceptance criterion count) | Criterion 2 now reflects 4 deferred Medium findings (line 870) | Resolved |
| **Feasibility M-1** (bare except in generate_senior_architect.py) | WG-1 Step 5 (lines 211-220) | Resolved |
| **Feasibility M-2** (non-atomic writes in generate_senior_architect.py) | WG-1 Step 4 (lines 170-209) | Resolved |
| **Feasibility M-3** (no validate_target_dir in generate_senior_architect.py) | WG-1 Step 3 (lines 131-168) | Resolved |

---

## Required Edits

None.

---

## Optional Suggestions

1. **WG-2 code duplication.** The `validate_target_dir()` and `atomic_write()` functions are copied from `generate_skill.py` to both `generate_agents.py` (WG-2) and `generate_senior_architect.py` (WG-1). This creates three copies of the same functions. Consider a follow-up task to extract them into a shared module (e.g., `generators/utils.py`). Out of scope for a security remediation plan but worth noting for the Low-severity hardening pass.

2. **WG-3 trap handler scope.** The plan places a `trap ... EXIT` handler in the secrets-scan skill definition. Since each Bash tool invocation runs in a separate shell, the trap will only persist within a single code block. The plan addresses this at line 543 ("should not be relied upon as the primary cleanup mechanism since each Bash tool invocation runs in a separate shell") and uses explicit `rm -f` as the primary cleanup. This is correct and sufficient.

3. **PII validation excludes all of `plans/`.** The WG-4 validation commands (lines 641-642) use `--exclude-dir=plans`, which also excludes the current plan file itself. The plan file contains "Ian Murphy" in its "before" examples (Assumptions, Steps). This is acceptable since plan files are ephemeral artifacts, but the red team's suggestion to narrow to `--exclude-dir=plans/archive` (F-7) remains valid for stricter auditing in future scans.

4. **Git history scrubbing.** The red team noted (F-12, STRIDE Information Disclosure) that PII remains in git history even after source file scrubbing. The plan does not address this. If the repository remains public, a `git filter-repo` pass may be warranted as a follow-up. This is correctly out of scope for a code-level remediation plan.

---

## Verdict: PASS

All 3 prior required edits have been applied. The plan is well-structured, follows CLAUDE.md conventions, maintains clean file boundaries across 6 work groups, correctly integrates all red team and feasibility feedback, and is ready for `/ship` execution. No required edits remain.
