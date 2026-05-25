# Librarian Review: Codebase Symbol Index (Re-review)

**Plan:** `plans/codebase-symbol-index.md`
**Reviewed:** 2026-05-25 (Round 2)
**Prior Review:** 2026-05-25 (Round 1 -- FAIL)
**Verdict:** PASS

---

## Original Findings Resolution

### R-01: `deploy.sh` scope ambiguity -- RESOLVED

The plan now commits to a single approach: scanner is invoked via `$CLAUDE_DEVKIT/scripts/codebase-scanner.py` with `./scripts/` local fallback. `deploy.sh` is explicitly NOT modified. The Revision Log entry (R-01) is clear, Decision 6 documents the rationale, and `deploy.sh` has been removed from the "Files to Modify" table. No ambiguity remains.

### R-02: Missing roadmap placement -- RESOLVED

The plan now includes a dedicated "Roadmap Placement" subsection under Context (lines 49-58) showing the exact v1.1 roadmap entry. Phase 5 step 1 explicitly lists "Roadmap section" as a CLAUDE.md update target with instructions to add the item and mark it complete. The roadmap item text matches the current CLAUDE.md v1.1 section format.

### R-03: Incomplete CLAUDE.md update spec in Phase 5 -- RESOLVED

Phase 5 step 1 (lines 777-784) now explicitly enumerates six CLAUDE.md update targets: Scripts section table, Roadmap section, `/configs` directory reference, Troubleshooting section (for `~/.claude-devkit/`), Recommended `.gitignore` section (noting no project-level entry is needed since cache is user-scoped), and Data Flow section. This covers all the items flagged in the original review plus the `.gitignore` and Data Flow points from the optional suggestions.

### R-04: Understated `.py`-in-scripts deviation -- RESOLVED

Context Alignment deviation 2 (lines 1028-1029) now explicitly states: "All existing scripts in `scripts/` are `.sh` files. The Python-in-scripts precedent is bash scripts wrapping embedded `python3 -c` blocks (`compute-run-score.sh`, `score-reflector.sh`), not standalone `.py` files. `codebase-scanner.py` is the first standalone `.py` file in this directory." This directly addresses the original finding with no hedging.

---

## New Conflicts Check

No new conflicts with CLAUDE.md were introduced by the revision. Specific checks:

- **Revision Log table** does not introduce any structural changes that conflict with CLAUDE.md rules.
- **Decision 5 (venv subprocess re-exec)** replaces the rejected `sys.path` manipulation approach (F-02). The new approach is consistent with CLAUDE.md's pattern of scripts invoking external tools via subprocess.
- **Decision 4 (cache relocation to `~/.claude-devkit/`)** resolves F-03 without introducing project-root artifacts that would conflict with `.gitignore` documentation.
- **Phase 6 (Measurement and Evaluation)** is additive. Its go/no-go thresholds are reasonable and do not conflict with any existing CLAUDE.md section.
- **`scanner_invocation` audit event** (STRIDE Repudiation row, SA-R) follows the established `emit-audit-event.sh` pattern documented in CLAUDE.md's Audit Logging section. The new event type would need to be added to the Event Types table in CLAUDE.md; the plan does not mention this, but it is a minor documentation follow-up during Phase 5, not a structural conflict.

---

## Context Alignment Section Assessment

The Context Alignment section (lines 1000-1029) is preserved and updated. It now lists 10 CLAUDE.md patterns followed (up from 8 in the original), 3 prior plans (unchanged), and 2 deviations (both rewritten per review feedback). The additions are:
- Item 9: Scanner invocation via `$CLAUDE_DEVKIT` env var (addressing R-01 resolution).
- Item 10: Audit event logging for scanner invocations (addressing SA-R).

Both additions are accurate and substantive.

## Context Metadata Block Assessment

The metadata block (lines 1058-1064) is intact:
```
discovered_at: 2026-05-25T11:24:00Z
revised_at: 2026-05-25T14:30:00Z
claude_md_exists: true
recent_plans_consulted: agentic-sdlc-security-skills.md, audit-remove-mcp-deps.md, devkit-hygiene-improvements.md
archived_plans_consulted: agentic-sdlc-next-phase.feasibility.md, agentic-sdlc-next-phase.secure-review.md
```
The `revised_at` timestamp has been added to reflect the revision. `claude_md_exists` is correctly `true`. No issues.

---

## Remaining Optional Notes (non-blocking)

1. **`scanner_invocation` audit event type** should be added to the CLAUDE.md Event Types table during Phase 5. The plan's Phase 5 step 1 lists six CLAUDE.md sections to update but does not explicitly mention the Audit Logging Event Types table. This is a minor omission -- the implementer will naturally encounter it when updating the Scripts section.

2. **`--self-test` consistency** (carried from Round 1 optional suggestions): Phase 5 step 4's validation sequence now includes `--self-test` in the "Exact Test Command" block at the end of the Test Plan section. Phase 5's own step 4 also includes it. Alignment is improved.

3. **`--max-file-size` unit clarity** (carried from Round 1): The CLI interface section (line 281) now consistently says "bytes" and the default exclusion section no longer mixes units. The STRIDE table (line 447) also says "bytes". Resolved.
