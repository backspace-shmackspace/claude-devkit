# Librarian Review: Scanner Value Instrumentation (Round 2)

**Reviewer:** Librarian Agent
**Date:** 2026-05-25
**Plan:** `plans/scanner-instrumentation.md` v1.1
**Verdict:** PASS

---

## Prior Edit Resolution Status

Two required edits were issued in the Round 1 review. Both have been addressed:

| Edit | Status | Evidence |
|------|--------|----------|
| **L-01:** Remove `jq` from Assumptions point 5 | RESOLVED | Assumptions point 5 (line 82) now reads: "Python 3.10+ is available (consistent with `compute-run-score.sh` and `score-reflector.sh` dependencies). No `jq` dependency -- new scripts use embedded Python only." Correctly excludes jq. |
| **L-02:** Add explicit "update test count from 37 to 42" to Work Group 3 CLAUDE.md scope | RESOLVED | Work Group 3 (line 606) now reads: "update test count from 37 to 42" explicitly. |

Additionally, the optional suggestion about `"unknown"` vs `"absent"` sentinel confusion in the Data Migration section has been addressed via finding Feas-M3. The section now uses a single sentinel (`"absent"`) with clear documentation (line 421).

---

## Conflicts with CLAUDE.md

None found. All artifacts, patterns, and conventions are consistent with CLAUDE.md rules:

- **New script location:** `scripts/scanner-value-report.sh` follows the Scripts directory reference (CLAUDE.md line 74, 910+).
- **New config location:** `configs/scanner-value-thresholds.json` follows the Configs directory reference alongside `score-dimensions.json` and `audit-event-schema.json`.
- **No jq dependency for new scripts:** Consistent with `compute-run-score.sh` and `score-reflector.sh` (CLAUDE.md Quantitative Scoring section).
- **Exit code convention:** Analysis scripts exit 0 on all paths, consistent with `compute-run-score.sh` and `score-reflector.sh` documented behavior.
- **JSONL audit logging:** Enriched events follow established format. `scanner_invocation` is already documented in CLAUDE.md's Event Types table but was missing from the schema enum -- closing this gap is a correction.
- **Work Groups structure:** Shared Dependencies + 3 numbered Work Groups matches the established `/ship` plan format.
- **Rollback plan:** Present with per-component steps.
- **Risk table:** Present with probability/impact/mitigation columns.
- **Test plan:** Present with 5 integration tests (38-42) and manual validation steps.
- **Acceptance criteria:** 12 numbered items, specific and verifiable.
- **Non-Goals:** 6 items, clearly scoped. Non-Goal 6 (no scoring for `/architect`) is well-justified.

---

## Historical Alignment

- **Consistent with codebase-symbol-index.md (APPROVED).** The plan correctly positions itself as extending Phase 6 (Measurement and Evaluation) from the original scanner plan. Phase 6 proposed a manual 5-run baseline/treatment comparison; this plan replaces it with automated, ongoing instrumentation. No contradiction.
- **Consistent with devkit-hygiene-improvements.md (APPROVED).** That plan established `test-integration.sh`. This plan extends it with 5 new tests following the same `run_test()` pattern. No contradiction.
- **Schema gap acknowledged honestly.** `scanner_invocation` is documented in CLAUDE.md's Event Types table but missing from `configs/audit-event-schema.json`'s `event_type` enum (confirmed by reading the schema -- lines 27-37 show the enum without `scanner_invocation`). Closing this gap is a correction.
- **Broken grep pattern confirmed.** The plan's claim that `/architect` (line 131-132) and `/ship` (line 349-350) use `Files scanned:` / `Total symbols:` while the scanner outputs `Files:` / `Symbols:` (codebase-scanner.py line 1206) is verified against the actual source files. Change 0 is a legitimate bug fix.
- **No contradictions found** with other recent plans (`agentic-sdlc-security-skills.md`, `audit-remove-mcp-deps.md`).

---

## Context Alignment Section

- **Present and substantive.** The `## Context Alignment` section (line 610) lists 8 specific CLAUDE.md patterns followed, 2 prior plans consulted with relationship explained, and 3 deviations with justification. Exceeds minimum bar.
- **Context metadata block is present and correct** (line 636). `claude_md_exists: true` (accurate -- CLAUDE.md exists), `discovered_at` timestamp present, `recent_plans_consulted` lists 3 plans, `archived_plans_consulted` lists 1 plan.

---

## Red Team / Feasibility Finding Resolution

All 10 findings from the Revision Log have been addressed in the plan body. Spot-checked:

- **F-01 (Critical):** `/architect` scoping confirmed throughout -- lines 48, 102-103, 126, 164, 168, 306-309, 317, 490, 493. The plan consistently states `/architect` emits enriched events but is excluded from correlation analysis. No residual causal claims about `/architect` data.
- **F-03 (Major):** `parser_mode` enum (line 362) correctly lists only `["tree-sitter-partial", "regex-fallback"]`. `"tree-sitter"` is reserved for future use (line 351) but not in the enum. Consistent.
- **F-04 (Major):** Example output (line 199-203) uses `[Correlation]` prefix and includes `[Caution]` block with confounder acknowledgment. Caveat section (line 177-179) explicitly states "Correlations below do NOT imply causation." No causal framing found.
- **Feas-M2 (Major):** `file_count` and `symbol_count` are integer type (line 364-365, and Change 0 defaults to `"0"` which is numeric). Consistent.
- **Feas-M3 (Major):** Single sentinel `"absent"` used throughout (lines 159, 161, 351, 419, 421). No `"unknown"` sentinel remains.

---

## Required Edits

None.

---

## Optional Suggestions

- **Consider documenting `scanner-value-report.sh` in the Audit Logging Query Utility section of CLAUDE.md** in addition to the Scripts section. Users looking for analysis tooling may check the "Query Utility" subsection first. A cross-reference would improve discoverability. (Carried forward from Round 1 -- still relevant.)

- **Acceptance criterion 12** ("5 new integration tests pass") and the test plan (Tests 38-42) are consistent with the Work Group 3 CLAUDE.md update ("update test count from 37 to 42"). If additional tests are added during implementation, remember to update all three references.
