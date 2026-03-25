# Review: Phase 0 -- Reference Archetype Validator Support + Rollback Mechanism (Rev 2)

**Reviewer:** Librarian
**Date:** 2026-03-05
**Plan:** `./plans/phase0-reference-validator.md` (Rev 2)
**Parent Plan:** `./plans/superpowers-adoption-roadmap.md` (Phase 0)
**Previous Review:** Rev 1 review dated 2026-03-05

---

## Verdict: PASS

Rev 2 resolves all three Major/Required findings from the previous review. The plan is aligned with CLAUDE.md rules, consistent with the parent roadmap, and ready for implementation.

---

## Previous Findings Resolution Status

| # | Previous Finding | Severity | Status |
|---|-----------------|----------|--------|
| 1 | `rm -rf` not in global allowlist -- `--undeploy` will trigger permission prompt | Major | **RESOLVED.** Rev 2 chose option (c): accept the prompt and document it as expected behavior. Added code comment (line 227), `--help` output note (line 237), Context Alignment entry (line 38), and Risk table row (line 319). |
| 2 | Test count mismatch (32 vs 33) across sections | Major | **RESOLVED.** All references now consistently state 33 tests (lines 243, 302, 334, 410, 500, 506, 527, 540). |
| 3 | Path traversal protection missing from `undeploy_skill()` | Optional suggestion | **RESOLVED.** Rev 2 adds input sanitization rejecting `/`, `..`, and `-` prefixes (lines 215-218). Test coverage added (Test Plan section 6, lines 379-381). |
| 4 | CLAUDE.md Skill Registry not updated | Minor | **ACKNOWLEDGED.** Still deferred as Non-Goal (line 54). Acceptable because Phase 0 creates no new skills -- registry updates happen per-phase when skills ship. |
| 5 | v2.0.0 pattern count mismatch (Reference skips 7 of 10 patterns) | Minor | **ACKNOWLEDGED.** Documentation debt tracked by parent roadmap. Not a Phase 0 responsibility. |
| 6 | Internal task phases named "Phase 1-5" conflicting with parent roadmap "Phase 0-6" | Optional suggestion | **NOT ADDRESSED.** Internal task breakdown still uses "Phase 1" through "Phase 5." Non-blocking; the section headers and context make the scope clear. |

---

## Conflicts with CLAUDE.md Rules

None blocking.

- **Development Rule 4 ("Update registry"):** The plan defers CLAUDE.md registry updates as a Non-Goal. This is acceptable because Phase 0 adds no new skills -- only tooling changes. The rule applies when "adding/changing skills," which happens in Phases 1-6.

- **"All skills follow these 10 patterns" (Skill Architectural Patterns section):** Reference archetype intentionally skips patterns 2, 3, 4, 5, 7, 9, and 10. This is a known deviation documented in the parent roadmap's Reference Archetype Definition section. The validator correctly gates these checks behind `is_reference`. This becomes a documentation update item when the first Reference skill ships.

---

## Historical Alignment

- **Parent plan alignment: PASS.** The plan implements exactly what `superpowers-adoption-roadmap.md` Phase 0 specifies: validator Reference support, `skill-patterns.json` update, `--undeploy` flag. No scope creep. No scope gaps.

- **No contradictions with prior plans.** Checked `audit-remove-mcp-deps.md`, `sync-remove-mcp-deps.md` (archived), and the parent roadmap. None touch `validate_skill.py` archetype detection, `skill-patterns.json` archetypes key, or `deploy.sh --undeploy` in conflicting ways.

- **Pattern consistency with recent plans.** Follows the established pattern from audit/sync MCP removal plans: backward-compatible additions to existing scripts, extended test suite, single conventional commit. Explicitly noted in Context Alignment section (line 37).

- **`model` field optionality.** The parent roadmap's test fixture (line 218) includes `model: claude-sonnet-4-5`, but the Phase 0 plan makes `model` optional for Reference skills. These are not contradictory -- the roadmap fixture predates the design refinement. The plan documents the rationale clearly (lines 117-119): Reference skills are non-executable and never dispatched to a model.

---

## Context Alignment Section Review

- **Present and substantive: PASS.** The `## Context Alignment` section (lines 32-38) covers CLAUDE.md patterns, existing archetypes, validator internals, test suite state, deploy script structure, recent migration patterns, and tool permission implications.

- **Context metadata block: PASS.** Present at lines 561-567 with `claude_md_exists: true`, `recent_plans_consulted` listing three plans, `archived_plans_consulted` listing two plans, and `revision_1_reviews` listing three review files. All accurate.

---

## Required Edits

None. The plan is ready for implementation via `/ship`.

---

## Optional Suggestions

- **Internal task naming.** The plan's Task Breakdown uses "Phase 1" through "Phase 5" for implementation steps, which can be confused with the parent roadmap's "Phase 0" through "Phase 6" rollout phases. Consider renaming to "Task 1" through "Task 5" if a Rev 3 is produced for other reasons. (Carried forward from previous review, still unaddressed but non-blocking.)

- **`--undeploy --contrib` semantic clarity.** The `--contrib` flag on `--undeploy` is functionally identical to plain `--undeploy` since both core and contrib skills deploy to the same `~/.claude/skills/` directory. The plan acknowledges this (line 281: "contrib context, same target"). Consider whether the `--contrib` variant adds confusion without adding value, or whether it serves as documentation of intent for the operator.

- **`core_principle_patterns` extensibility.** The four patterns (`Iron Law`, `Core Principle`, `Fundamental Rule`, `The Gate`) cover all six planned superpowers skills. If future Reference skills use terms like "Discipline" or "Constraint," the config-only update path is clean. No action needed now.
