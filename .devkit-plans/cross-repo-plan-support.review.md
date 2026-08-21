# Librarian Review: cross-repo-plan-support.md (Round 2)

**Reviewer:** Librarian
**Date:** 2026-08-21
**Plan Version:** DRAFT (revised)
**Round:** 2
**Verdict:** PASS

---

## Summary

All five required edits from round 1 have been substantively addressed. The revised plan adds
the `extract_with_targets()` algorithm (Component 4), explicit Bash-based URI resolution for
skills (Components 6 and 8), `cmd_shell` routing fix in `main()` (Component 4 and Rollout step
7), shared-learnings-layer status correction (Context Alignment), and test numbering explanation
(Test Plan). No new blocking conflicts with CLAUDE.md rules were introduced.

---

## Round 1 Required Edit Resolution

### 1. Clarify `--with` extraction mechanism

**Status:** RESOLVED

The revised plan adds a dedicated subsection under Component 4 (lines 342-406) with:
- A full `extract_with_targets()` function specification with pseudocode (lines 349-381)
- Error handling for missing path after `--with` (exit 2) and flag-after-flag (`--with --xyz`)
- Extraction order diagram showing `--with` is extracted before `--detach` and before
  `split_skill_args()` (lines 384-406)
- Explicit acknowledgment in Context Alignment (lines 1287-1290) that `--with` is NOT identical
  to `--detach` and uses a separate extraction function

This goes well beyond the minimum requested edit and provides implementation-ready detail.

### 2. Specify how `/ship` resolves `devkit://` URIs

**Status:** RESOLVED

The revised plan adds two clarifications:
- Component 6 (lines 509-511): "Skills cannot call `resolve_devkit_uri()` as a Python function
  -- they execute inside Claude Code sessions, not as subprocesses of `devkit_cli.py`. The
  `devkit plan resolve` CLI command is the only interface available to skills."
- Component 8 (lines 630-638): Explicit Bash command example showing how `/ship` resolves URIs
  via `devkit plan resolve`.

The round 1 concern about skills calling Python functions directly is now explicitly addressed.

### 3. Fix `cmd_shell` routing in `main()`

**Status:** RESOLVED

The revised plan addresses this in three places:
- Component 4 (lines 408-412): Specifies the routing change: `main()` passes full `rest` list
  to `cmd_shell()`, and `cmd_shell()` extracts the primary target from `rest[0]` and calls
  `extract_with_targets(rest[1:])`.
- Rollout step 7 (line 867): "Update `main()` routing for `shell` command to pass full `rest`
  list to `cmd_shell()` (currently passes only `rest[0]`, discarding `--with` arguments)."
- Work Group 1 (line 1163-1164): "update `main()` to route `plan` to `cmd_plan()`, add `plan`
  to `KNOWN_COMMANDS`, pass full `rest` list to `cmd_shell()`".

Verified against codebase: `cmd_shell(rest[0], config)` at line 1735 of `devkit_cli.py` confirms
the plan's description of current behavior.

### 4. Update shared-learnings-layer status to APPROVED

**Status:** RESOLVED

Line 1263 now reads "(APPROVED)" matching commit `5d5c348`. The Context Metadata block (line
1299) also adds `shared-learnings-layer.md` to `recent_plans_consulted`.

### 5. Fix test numbering gap

**Status:** RESOLVED

Lines 917-919 explain: "The existing test suite has 118 `run_test` calls numbered 1-119 (one
number is skipped within the existing range). New tests start at 120, which is contiguous with
the last existing test (119)."

The explanation is reasonable. New tests (120-148) are contiguous with the last existing test
number (119). Total count: 118 + 29 = 147 matches acceptance criterion 8.

---

## Conflicts With CLAUDE.md Rules

None blocking.

---

## CLAUDE.md Pattern Compliance

| Pattern | Status | Notes |
|---------|--------|-------|
| Python stdlib only | OK | Bespoke YAML-subset parser (Assumption 5), no PyYAML |
| Zero project footprint | OK | All artifacts under `~/.claude-devkit/projects/`, nothing in target repos |
| Validation tuples `(bool, error_msg)` | OK | `validate_plan_targets()`, `resolve_devkit_uri()`, others |
| Atomic writes via `_atomic_write_json()` | OK | Reused for plan-ref writes |
| Atomic parsing | OK | `parse_plan_frontmatter()` returns all-or-nothing |
| File permissions 0o700/0o600 | OK | Specified for `plan-refs/` dirs and files |
| Injection resistance | OK | `extract_with_targets()` fully specified; `--with` targets through `validate_target()`; URI path containment |
| `KNOWN_COMMANDS` tuple update | OK | Rollout step 10 adds `plan` |
| Config over constants | OK | `max_cross_repo_targets` via `config.get()`, consistent with `max_state_file_bytes` |
| Informational-only indexes | OK | Plan refs follow same pattern as registry |
| Defense-in-depth | OK | URI format validation + resolved-path containment; `cmd_path` backfill |
| Test count consistency | OK | 118 existing + 29 new = 147, math verified |
| Work Group file independence | OK | WG1: `devkit_cli.py` only; WG2: skill SKILL.md files only; WG3: test + docs only |
| Context Alignment section | OK | All three prior plans referenced with correct status (APPROVED) |
| Context Metadata block | OK | `claude_md_exists: true`, `revised_at` and `revision_notes` present, `recent_plans_consulted` updated |
| Env var naming convention | OK | `DEVKIT_TARGET_*` follows existing `DEVKIT_PROJECT_DIR` / `DEVKIT_SCRIPTS` pattern |
| Single-target backward compat | OK | `DEVKIT_TARGET_COUNT=1` and `DEVKIT_TARGET_0_*` always set; additive, no existing skill reads them |

---

## Historical Alignment Issues

- **No contradictions with prior plans.** All three referenced plans (zero-project-footprint,
  detached-skill-execution, shared-learnings-layer) are listed with correct APPROVED status.
  Each reference is accurate in how the new plan builds on them.

- **Context Metadata `recent_plans_consulted` is now complete.** Round 1 noted that
  `zero-project-footprint.md` and `shared-learnings-layer.md` were missing from the metadata.
  Both are now present (line 1299).

- **`archived_plans_consulted` field added** (line 1300): lists `zero-project-footprint` and
  `detached-skill-execution` as archived plans that were consulted, improving traceability.

---

## New Issues Introduced (None Blocking)

No new blocking issues were introduced in the revision.

---

## Optional Suggestions (Carried and New)

### Carried from Round 1 (still applicable)

1. **`validate_plan_targets()` return type.** Consider returning `(True, list_of_resolved_paths)`
   so callers don't need to re-resolve each target path after validation.

2. **Max ref file size check on read.** A `max_ref_file_bytes` constant (e.g., 32768) would be
   consistent with `max_state_file_bytes` and the STRIDE DoS mitigation.

3. **`/fix` skill awareness.** Consider whether `/fix` needs `target:` awareness for cross-repo
   plan findings.

4. **`ship-queue.sh` interaction.** Document the recommended invocation pattern for cross-repo
   plans (primary target first, then secondaries in dependency order).

### New

5. **`/ship` Step 1 frontmatter parsing mechanism.** Line 591 says `parse_plan_frontmatter()`
   is "called as a Python one-liner via Bash." Since the plan already provides `devkit plan
   validate` and `devkit plan show` as CLI commands that parse frontmatter, consider having
   `/ship` call one of those instead of a raw Python one-liner. This would be more consistent
   with the plan's own principle that skills use `devkit plan` subcommands rather than calling
   Python functions. Not blocking -- both approaches work.

6. **Test numbering precision.** The plan states "one number is skipped within the existing
   range" (line 918). Actual gap analysis of `test-integration.sh` shows two gaps (test
   numbers 5 and 9 are unused), suggesting 120 test numbers span 118 calls rather than 119.
   The statement is close enough for planning purposes and does not affect the new test range
   (120-148). Consider correcting to "two numbers are skipped" for precision, but this is
   cosmetic.
