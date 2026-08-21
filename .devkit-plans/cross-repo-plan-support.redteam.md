# Red Team + Security-Analyst Review (Round 2): Cross-Repo Plan Support

**Reviewer:** Red Team (with Security-Analyst supplement)
**Plan:** cross-repo-plan-support.md (revised)
**Date:** 2026-08-21
**Round:** 2 of 2
**Methodology:** (1) Verify resolution of all round 1 findings, (2) fresh critical review of revised plan, (3) STRIDE validation of revised Security Requirements section

---

## Verdict: PASS

All seven Major findings from round 1 are resolved in the revised plan. No new Critical findings. Five new Minor/Info findings identified in the revision (see New Findings below). The Security Requirements section now covers all three STRIDE gaps identified in round 1 with specific, testable mitigations.

---

## Round 1 Finding Resolution

### Finding 1: Assumption 5 wrong -- YAML parser
**Status: RESOLVED**

The original assumption that `targets:` is "flat key-value" and that the existing `validate_skill.py` parser "already handles" it has been completely replaced. Assumption 5 (lines 65-151) now:
- Explicitly states a **new** YAML-subset parser is required (~50-80 lines of new code).
- Defines the supported YAML subset (flat keys, one-deep list-of-dicts) and explicitly lists what is NOT supported (nested lists, block scalars, anchors, flow syntax, tags, quoted keys).
- Includes a complete parsing grammar as Python pseudocode with state machine logic (`"top" | "in_list"`), regex patterns for each line type, and explicit error returns.
- Specifies **atomic failure**: no partial target lists are ever returned. This directly addresses the round 1 concern about partial parse results.

The parser specification is precise enough to implement without ambiguity. The bespoke approach (vs. pulling in PyYAML) is consistent with the stdlib-only constraint.

---

### Finding 2: `--with` extraction complexity
**Status: RESOLVED**

Component 4 (lines 346-406) now includes:
- A complete `extract_with_targets()` function with Python code (not pseudocode).
- Explicit error handling: `--with` at end of args (exit 2), `--with` followed by another flag (exit 2).
- Pair consumption via `i += 2` (consumes both `--with` and its path argument).
- A worked example showing the full extraction ordering: `extract_with_targets()` runs FIRST, then `--detach` extraction, then `split_skill_args()`, then `validate_args()`.
- Explicit note that `--with` targets do NOT reach `validate_args()` (they are consumed before the split/validate pipeline).

The plan now correctly distinguishes this from the `--detach` boolean pattern (Deviations item 5, line 1289) rather than claiming equivalence.

---

### Finding 3: `/ship` target matching underspecified
**Status: RESOLVED**

Component 8 (lines 586-655) now specifies:
- **Step 1 matching algorithm**: expand `~`, resolve to absolute path, compare against `$CWD` (also resolved via `realpath`). Three outcomes: primary match (proceed), secondary match (warn + proceed with filtered work groups), no match (BLOCK).
- **Step 2b matching algorithm**: case-insensitive comparison of `**Target:** <name>` against `DEVKIT_TARGET_N_NAME` (project directory basename). Current project determined by matching `$CWD` against `DEVKIT_TARGET_N_PATH` values.
- **Unannotated work group**: treated as primary-target-only, logged as warning.
- **Mismatched target name** (typo): skipped with warning.
- **No matching work groups**: PASS (not an error -- user may be running `/ship` per-project in sequence).

All four edge cases from round 1 are addressed with defined behavior.

---

### Finding 4: Thin test coverage
**Status: RESOLVED**

The test plan has grown from 15 to 29 tests (lines 915-1101), meeting the round 1 recommendation of "25-30 tests minimum." Coverage improvements:

| Round 1 Gap | Addressed? | Tests |
|---|---|---|
| `devkit plan show`, `validate`, `sync` subcommands | Yes | 139, 140-141, 142 |
| Malformed/adversarial plan frontmatter | Yes | 124, 125 |
| `--with` combined with `--detach` | Yes | 137 |
| Single-project plan regression | Yes | 121 |
| Multiple `--with` flags | Yes | 135 (2 flags) |
| `devkit plan sync` rebuilding refs | Yes | 142 |
| Concurrent plan-ref writes | No | -- |
| `/ship` work group filtering | Structural only | Skill structural tests |
| `/architect` multi-target context | Structural only | Skill structural tests |

The structural tests for `/ship` and `/architect` are appropriate because those skills execute inside Claude Code (LLM interpretation), which cannot be functionally tested in a bash integration harness. Tests 129-131 are now functional tests (invoking `write_plan_refs()` and asserting behavior), resolving the round 1 concern about "code inspection" tests.

---

### Finding 5: No ref lifecycle management
**Status: RESOLVED**

The revised plan adds:
- `devkit plan archive <target> <plan-name>` (lines 282-328) with a 5-step algorithm: read ref file to find all projects, validate each, delete refs, move plan to archive.
- `devkit plan sync` step 6 (line 311): scans existing refs, checks if referenced plan still exists, deletes stale refs.
- `/ship` archive step (lines 646-650): calls `devkit plan archive` via Bash when archiving a cross-repo plan.

The lifecycle gap is closed: refs are created by `/architect`, cleaned by `devkit plan sync`, and removed by `/ship` or `devkit plan archive`.

---

### Finding 6: `/architect` Step 4 mechanism gap
**Status: RESOLVED**

Component 7 (lines 548-577) now explicitly specifies:
- The mechanism: `/architect` Step 4 PASS path calls `devkit plan sync "$DEVKIT_TARGET_0_PATH"` via Bash.
- The rationale for this choice: the skill runs inside Claude Code and cannot call Python functions in `devkit_cli.py` directly; the CLI cannot know which plan file was created; `devkit plan sync` is idempotent.
- Failure handling: ref creation failure is non-blocking (plan is already committed; refs can be rebuilt later).
- The exact markdown addition to Step 4.

This is a well-reasoned design choice with clear failure semantics.

---

### Finding 7: `cmd_path` traversal inconsistency
**Status: RESOLVED**

The revised plan:
- Adds Rollout Plan step 8 (lines 868-871): "Backfill path traversal protection on `cmd_path()`: reject `..` segments in subpath, validate resolved path is under project directory."
- References this in Security Controls (line 823): "`cmd_path` subpath also validates containment."
- Adds Test 147 (lines 1082-1085): verifies `cmd_path` rejects `../../etc/passwd` and accepts `plans/feature.md`.

Confirmed against the codebase: `cmd_path()` at `scripts/devkit_cli.py` line 1506-1507 currently does `print(str(project_dir / subpath))` with no containment check -- the plan correctly identifies and remediates this.

---

### Finding 8 (Minor): Env var naming collision risk
**Status: RESOLVED**

Component 4 (lines 421-435) specifies: `DEVKIT_TARGET_COUNT=1` and `DEVKIT_TARGET_0_*` vars are always set, even for single-target invocations. Skills can consistently use `DEVKIT_TARGET_0_PATH` without conditional checks. `DEVKIT_TARGET_COUNT > 1` is the multi-target indicator.

Context Alignment (line 1237) confirms: "Single-target invocations always set `DEVKIT_TARGET_COUNT=1` and `DEVKIT_TARGET_0_*` for interface consistency."

---

### Finding 9 (Minor): `devkit plan sync` algorithm unspecified
**Status: RESOLVED**

The `devkit plan sync` algorithm is now specified in 7 steps (lines 298-314), covering:
- Which plans are scanned (all `*.md` in `plans/`, not `archive/`).
- Uninitialized secondary targets: log warning, skip that target, do not fail entire sync.
- Invalid primary target: log error, skip entire plan.
- Stale ref cleanup: check if referenced plan still exists, delete stale refs.

---

### Finding 10 (Minor): Plan frontmatter `path` field contains user home directory
**Status: PARTIALLY RESOLVED**

The plan now specifies that ref files store absolute paths with no tildes (lines 256-259), matching the `state.json` pattern. However, the round 1 recommendation to "note this as a known limitation" for plan file portability is not addressed. Plan frontmatter still uses `path: ~/projects/...` (user-specific paths), and there is no explicit note that plan files are not portable across users.

This is acceptable for a single-user tool and does not block implementation. A one-line "Known limitation" note in the Non-Goals or Risks section would close this fully.

---

### Finding 11 (Minor): No mechanism to discover which projects a plan touches
**Status: RESOLVED**

`devkit plan show` displays target information from ref files (lines 269-270). `devkit plan archive` reads `all_targets` from ref files to find all involved projects (lines 319-323). The ref file schema includes `all_targets` (lines 226-236) which answers the inverse query.

---

### Finding 12 (Info): `max_cross_repo_targets` in defaults vs constant
**Status: RESOLVED**

Lines 696-703 and line 1147 explicitly state: "The Python code reads this via `config.get("max_cross_repo_targets", 10)` -- no separate `MAX_CROSS_REPO_TARGETS` constant." Context Alignment (line 1249) confirms consistency with the `max_state_file_bytes` pattern.

---

### Finding 13 (Info): Rollout Phase 4 is sequenced last but contains regression-critical tests
**Status: NOT EXPLICITLY ADDRESSED**

The rollout phases are unchanged (Phase 4 for tests, after Phases 1-3 for code). The round 1 recommendation to write parser tests before the parser implementation was not adopted. This is Info severity and does not affect the verdict -- the plan's test coverage is adequate regardless of writing order.

---

### STRIDE Gap S-1: External plan file threat vector
**Status: RESOLVED**

New Tampering row added (line 807): "Plan file received from an external source (e.g., colleague shares a plan file via chat). The `targets:` paths would be attacker-controlled." Mitigation: `validate_target()` checks `allowed_roots`, rejects symlinks, requires devkit initialization.

---

### STRIDE Gap S-2: Codebase-scanner output crosses sensitivity boundary
**Status: RESOLVED**

New Information Disclosure row added (line 812): "Codebase-scanner output from multiple targets combined in architect agent context." Risk accepted with justification that the user explicitly initiated the multi-target session and output does not persist beyond the session context window.

---

### STRIDE Gap S-3: Ref file tampering
**Status: RESOLVED**

New Tampering row added (line 809): "Modified ref file: `primary_plan_path` changed to point to a different plan or arbitrary file." Mitigation: informational-only defense, validation on read (must be under valid project dir, no `..` segments, file must exist), `[STALE]` for invalid refs.

---

## New Findings

### New Finding 1: `/ship` Step 1 frontmatter parsing mechanism is underspecified

**Severity: Minor**

Component 8 (line 591) says `/ship` parses frontmatter via "`parse_plan_frontmatter()` (called as a Python one-liner via Bash, since `/ship` runs inside Claude Code and cannot call the function directly)."

`parse_plan_frontmatter()` is a 50-80 line function inside `devkit_cli.py`. A "Python one-liner via Bash" cannot invoke this function without either:

1. Importing from `devkit_cli.py` (fragile -- it is a CLI script, not a library, and the import path depends on `$CLAUDE_DEVKIT` or `sys.path` manipulation).
2. Duplicating the parser inline (defeats the purpose of a shared parser).
3. Using `devkit plan validate` or `devkit plan show` as CLI commands (the natural choice, but not what the plan says).

This is the same class of mechanism gap that round 1 Finding 6 identified for `/architect`, but the `/architect` case was resolved cleanly (it uses `devkit plan sync`). For `/ship`, the equivalent solution would be: the LLM reads the plan frontmatter directly (it already reads the full plan in Step 1), extracts target paths, and invokes `devkit plan validate` to confirm validity. The "Python one-liner" phrasing creates implementation ambiguity.

**Recommendation:** Replace "called as a Python one-liner via Bash" with a concrete mechanism. The simplest option: `/ship` Step 1 calls `devkit plan validate "$DEVKIT_TARGET_0_PATH" "<plan-file>"` via Bash (which internally calls `parse_plan_frontmatter()` and reports validation results). The LLM interprets the validation output to determine target matching.

---

### New Finding 2: `devkit plan list` deduplication between `plans/` and `plan-refs/` not specified

**Severity: Minor**

The plan ref schema (line 247) states: "The primary project gets a ref file too (with `"role": "primary"`)." This means a cross-repo plan's primary project has BOTH the plan file in `plans/` AND a ref file in `plan-refs/`.

`devkit plan list` (lines 286-296) shows plans from both sources. If a plan appears in `plans/*.md` (local file) and also in `plan-refs/*.ref.json` (self-referencing ref), it could appear twice in the listing unless deduplication is applied.

The output example (lines 288-293) shows no duplicates, implying deduplication exists, but the algorithm is not specified in `cmd_plan()`.

**Recommendation:** Specify deduplication: when a plan name appears in both `plans/` (as a file) and `plan-refs/` (as a ref with `role: primary`), show one row with the information from the plan file (which is richer -- it has the actual frontmatter). Ref-only entries (role: secondary, plan file elsewhere) appear separately.

---

### New Finding 3: Work group target basename collision

**Severity: Minor**

Step 2b matching (line 609) compares `**Target:** <name>` against `DEVKIT_TARGET_N_NAME` values, which are project directory basenames. If two projects have the same basename under different parent directories (e.g., `~/projects/cve-api` and `~/workspaces/cve-api`), the basename `cve-api` would match both `DEVKIT_TARGET_0_NAME` and `DEVKIT_TARGET_1_NAME`.

In practice this is unlikely (a cross-repo plan involving two different directories both named `cve-api` is unusual). But the matching algorithm does not specify tie-breaking behavior for duplicate basenames.

**Recommendation:** Add a note that if basenames collide, the first matching target index wins. Or use project-id rather than basename for matching (more robust but less human-readable in plan markdown).

---

### New Finding 4: "No structural changes to /ship" contradicts actual changes

**Severity: Info**

Line 654 states: "No structural changes to /ship." However, the plan adds:
- Target validation logic to Step 1 (lines 588-601).
- Work group filtering logic to Step 2b (lines 603-626).
- Ref cleanup via `devkit plan archive` Bash call to the archive step (lines 646-650).

These are structural changes (new logic in existing steps, new Bash tool calls). The statement likely means "no changes to the worktree isolation or file boundary validation patterns," but the wording "no structural changes" is misleading and could cause a reviewer or implementer to underestimate the scope of `/ship` modifications.

**Recommendation:** Reword to: "No changes to `/ship`'s worktree isolation, file boundary validation, or security gate patterns."

---

### New Finding 5: Task Breakdown and Work Groups sections contain duplicated content

**Severity: Info**

The plan contains a "Task Breakdown" section (lines 1140-1192) and a separate "Work Groups" section (lines 1194-1217). Both list the same work groups (1: Core CLI Infrastructure, 2: Skill Updates, 3: Tests and Documentation) with the same file change lists. The Task Breakdown provides slightly more detail in places, but the duplication creates a maintenance burden: any change must be applied in both sections to avoid inconsistency.

**Recommendation:** Remove one of the two sections. The "Work Groups" section at the end appears to be the canonical format for `/ship` consumption. The "Task Breakdown" narrative can be folded into the Work Groups section as inline commentary.

---

## Security-Analyst Supplement

### STRIDE Validation of Revised Section

The Security Requirements section (lines 766-853) has been substantially improved since round 1.

#### All Six STRIDE Categories: PRESENT and COMPLETE

| Category | Entries | Round 1 Assessment | Round 2 Assessment |
|---|---|---|---|
| **Spoofing** | 1 | Adequate | Adequate (unchanged) |
| **Tampering** | 4 (was 2) | Adequate + 2 gaps | Complete -- both gaps filled |
| **Repudiation** | 1 | Adequate | Adequate (unchanged) |
| **Information Disclosure** | 2 (was 1) | Adequate + 1 gap | Complete -- scanner output gap filled |
| **Denial of Service** | 1 | Adequate | Adequate (unchanged) |
| **Elevation of Privilege** | 1 | Adequate | Adequate (unchanged) |

#### Round 1 STRIDE Gap Resolution

**Gap S-1 (Tampering: external plan file):** RESOLVED. New row (line 807) explicitly enumerates the threat vector (plan file received from external source with attacker-controlled paths) and documents that `validate_target()` covers this via `allowed_roots` enforcement and symlink rejection. The mitigation is the same function used for all user-supplied paths -- no special case, consistent trust boundary.

**Gap S-2 (Information Disclosure: scanner output):** RESOLVED. New row (line 812) documents the sensitivity boundary crossing when `codebase-scanner` runs on multiple targets in a single `/architect` session. Risk accepted with explicit justification: user-initiated, output does not persist beyond the session context window. This is the correct assessment -- the user's `--with` flag is an explicit consent to cross-project visibility.

**Gap S-3 (Tampering: ref file modification):** RESOLVED. New row (line 809) enumerates the threat (modified `primary_plan_path` in ref file) and documents defense-in-depth: ref files are informational-only, `primary_plan_path` is validated on read (containment check under valid project dir, no `..` segments, file existence required), and invalid refs are shown as `[STALE]`.

#### Trust Boundaries: Unchanged and Well-Defined

Five trust boundaries (TB-1 through TB-5) remain from round 1. No new trust boundaries were introduced by the revision, which is correct -- the revision addressed gaps in existing boundary coverage rather than adding new boundaries.

#### Failure Modes: Now Complete

Five failure modes are defined (was four). The new entry (line 848) addresses the `parse_plan_frontmatter()` partial result concern raised in round 1: "If `parse_plan_frontmatter()` encounters a malformed line: The entire parse fails atomically." The safe default is specified: unparseable frontmatter causes the plan to be treated as single-project (no `targets:` extracted). This prevents the most dangerous failure mode (cross-repo plan silently treated as single-project with a subset of targets).

#### Security Controls: Consistent with Codebase

The `cmd_path` backfill (Security Controls bullet, line 823) is consistent with the actual codebase. Verified: `cmd_path()` at `scripts/devkit_cli.py` line 1506-1507 currently does `print(str(project_dir / subpath))` with no traversal check. The plan correctly identifies and remediates this gap.

The "Atomic Parsing" control (line 830) is a meaningful addition. The parser specification's state machine design (Assumption 5) supports this claim structurally -- the function has a single return point for success (after all lines are parsed) and early-return error points that always return `({}, error)`.

#### Residual Risk Assessment

All entries rate residual risk as "Low." This is appropriate because:
1. The threat model is local-only (single-user machine, no network exposure).
2. All paths pass through `validate_target()`, which is the established trust boundary.
3. Ref files are informational-only -- no security decision depends on their content.
4. The `devkit://` URI scheme has defense-in-depth (URI format validation AND resolved-path containment).

No security control gaps remain. The STRIDE table is now comprehensive for the feature's scope.

---

## Summary of Findings by Severity

### Round 1 Resolution

| Finding | Severity | Status |
|---|---|---|
| 1. Assumption 5 YAML parser | Major | RESOLVED |
| 2. `--with` extraction complexity | Major | RESOLVED |
| 3. `/ship` target matching underspecified | Major | RESOLVED |
| 4. Thin test coverage | Major | RESOLVED |
| 5. No ref lifecycle management | Major | RESOLVED |
| 6. `/architect` Step 4 mechanism gap | Major | RESOLVED |
| 7. `cmd_path` traversal inconsistency | Major | RESOLVED |
| 8. Env var naming collision risk | Minor | RESOLVED |
| 9. `plan sync` algorithm unspecified | Minor | RESOLVED |
| 10. Path portability | Minor | PARTIALLY RESOLVED |
| 11. Inverse plan lookup | Minor | RESOLVED |
| 12. Config vs constant | Info | RESOLVED |
| 13. Test sequencing | Info | NOT EXPLICITLY ADDRESSED |
| S-1. External plan file threat vector | STRIDE | RESOLVED |
| S-2. Scanner output sensitivity | STRIDE | RESOLVED |
| S-3. Ref file tampering | STRIDE | RESOLVED |

### New Findings (Round 2)

| Severity | Count | Findings |
|---|---|---|
| **Critical** | 0 | -- |
| **Major** | 0 | -- |
| **Minor** | 3 | `/ship` frontmatter parsing mechanism, `plan list` deduplication, basename collision |
| **Info** | 2 | "No structural changes" wording, duplicated Task Breakdown/Work Groups sections |
