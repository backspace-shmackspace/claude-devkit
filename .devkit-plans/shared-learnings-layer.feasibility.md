# Feasibility Review -- shared-learnings-layer

**Reviewer:** code-reviewer-specialist
**Date:** 2026-08-21
**Plan:** shared-learnings-layer.md
**Verdict:** PASS
**Revision:** R1 (re-review after plan revision addressing M-1, M-2)

---

## Summary

The plan is technically feasible, well-structured, and follows established devkit patterns (stdlib-only Python, atomic writes, validation tuples, `run_test()` harness, central storage). The security analysis is thorough and the rollout is properly phased.

Both Major concerns from the initial review have been addressed:

- **M-1 (compute_project_id):** The plan now uses `compute_project_id()` from `devkit_cli.py` for `source_project` identifiers throughout the aggregation logic (Component 2 step 2, Task Breakdown Step 2, Context Alignment section). A `source_project_display` field provides the human-readable relative-to-home path. This eliminates the basename collision risk entirely.

- **M-2 (/retro mine early-branch):** The plan now includes an explicit early-branch specification in the workflow section ("the skill skips Steps 0 artifact discovery through Step 5 entirely...and proceeds directly to Step 6"), the Modified Files table ("early-branch: skip Steps 0-5 for mine scope"), and the Task Breakdown Step 5 ("If `$ARGUMENTS` is `mine`, set scope to `mine`, skip all archive discovery, skip Steps 1-5, and proceed directly to Step 6"). The coder will have unambiguous guidance.

The revisions also introduced tag-based correlation as the primary cross-project detection mechanism (more robust than title-only matching), which directly addresses the false-negative risk noted in M-3 from the original review. Title-based matching is retained as a secondary, stricter mechanism. This is a sound structural improvement.

No new feasibility issues were introduced by the revisions. Five Minor concerns from the original review remain as notes below (none are blockers).

---

## Resolved Concerns

### Major (both resolved)

**M-1: `source_project` derived from path basename is not guaranteed unique** -- RESOLVED

The plan now specifies `compute_project_id()` for internal dedup keys (producing `<sanitized-basename>-<sha256[:12]>` identifiers) and `source_project_display` for human-readable presentation. The function is a pure computation importable from `devkit_cli.py` without invoking the CLI as a subprocess, which is consistent with Assumption 3.

**M-2: `/retro mine` scope integration requires explicit early-branch specification** -- RESOLVED

The plan now contains an explicit early-branch clause in three locations: the workflow description (lines 298-301), the Modified Files table (line 400), and the Task Breakdown Step 5 (lines 750-753). The specification is clear and consistent across all three references.

---

## Remaining Minor Concerns (from initial review, unchanged)

**M-3: Title-based deduplication has inherent false-negative risk** -- MITIGATED

The plan revision elevated tag-based correlation to the primary detection mechanism, which substantially reduces this risk. Title-based matching remains as a secondary mechanism. The Risks table now explicitly acknowledges false negatives. No further action needed.

**M-4: Nested subcommand parsing for `devkit learnings promotions` is novel** -- ACKNOWLEDGED

Still the first multi-level subcommand in the CLI. The plan documents thin dispatch delegation to external scripts. No code change needed.

**M-5: `promotions.json` has no schema migration path** -- ACCEPTABLE FOR v1

The `schema_version` field enables future migration. The promotion set will be small in v1 and manual migration is feasible. No change needed now.

**M-6: Test plan does not cover empty learnings files or entry-less projects** -- MINOR GAP

Still 18 tests with no explicit empty-file test case. The parser specifies graceful degradation so this is low risk. A T19 for the zero-entry base case would increase confidence but is not blocking.

**M-7: "learnings" becomes a reserved command name** -- RESOLVED

The plan now documents this explicitly: "Note: `learnings` is a reserved devkit command and cannot be used as a skill name" (Task Breakdown Step 4).

---

## Validation of Plan Assumptions

| Assumption | Verified? | Notes |
|------------|-----------|-------|
| 14 projects with learnings files | Yes | 15 files found, 1 in `_backup_` directory (correctly excluded). 14 non-backup projects. |
| ~420 entries total | Yes | Actual count is ~420+ entries across 14 projects. |
| Registry lists registered projects | Partially | Registry has 4 projects; remaining 10-11 are found via `allowed_roots` scan. Discovery strategy is correct. |
| Format: `- **[date] Title** [Severity]` | Yes | Universal entry boundary pattern. Some entries omit date or severity. |
| Tags: `#lowercase-hyphenated` | Yes | Verified across all projects. Tags always appear at end of entry line. |
| `compute_project_id()` is importable | Yes | Pure function at line 161 of `devkit_cli.py` -- takes a path, returns a string, no side effects. Standard Python import. |
| Python 3.8+ stdlib sufficient | Yes | All operations (json, hashlib, re, pathlib.glob, os, tempfile) are in stdlib. |

## Breaking Changes / Backward Compatibility

No breaking changes identified. All modifications are additive. Existing learnings files are read-only (never modified by the aggregator). Existing `/retro` behavior is preserved for all current scope modes. The early-branch clause ensures `mine` mode diverges cleanly before any per-project processing begins.

## Time Estimate Assessment

The plan estimates 12-16 hours. Work group estimates sum to 10-18 hours. The phased work group structure with explicit dependency ordering is sound. The tag-based correlation addition (compared to the initial plan) adds minimal implementation effort -- it is a straightforward counting operation during the aggregation pass.
