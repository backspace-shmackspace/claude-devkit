# Feasibility Review (Round 2): Cross-Repo Plan Support

**Reviewed:** 2026-08-21
**Reviewer:** code-reviewer-specialist (feasibility)
**Plan:** cross-repo-plan-support.md (revised)
**Verdict:** PASS

---

## Round 1 Concern Resolution

### C-1 (Critical): Frontmatter parser assumption wrong -- RESOLVED

Round 1 identified that Assumption 5 incorrectly claimed the existing
`validate_skill.py` parser could handle `targets:` YAML lists. The revised plan
completely rewrites Assumption 5 (lines 65-153) with:

- Explicit acknowledgment that the parser is "new code, not a reuse" (line 146).
- A supported YAML subset definition (flat key-value + one-deep list-of-dicts).
- An explicit NOT-supported list (nested lists, multi-line values, anchors, flow
  syntax, tags, quoted keys, type coercion).
- Full parser pseudocode with a two-state machine (`top`/`in_list`), including regex
  patterns for each transition, error paths, and the flush-on-exit semantics.
- Atomic failure mode: `({}, "error description")` on any unparseable line.

I verified the state machine logic against the regex patterns:

- In `top` state: `/^([a-zA-Z_][\w_-]*)\s*:\s*(.+)$/` (flat k:v with value) and
  `/^([a-zA-Z_][\w_-]*)\s*:\s*$/` (list introducer, no value) are mutually exclusive
  and correctly ordered.
- In `in_list` state: the list-item regex (`\s+-\s+key:val`) and sub-key regex
  (`\s+key:val`) are non-ambiguous because `- ` is not `[a-zA-Z_]`. The
  back-to-top transition (`^([a-zA-Z_]...):` with no leading whitespace) correctly
  exits the list.
- The `(.+)` value capture requires at least one character, which correctly forces
  list-introducer lines (like `targets:`) to match the second pattern (no value).

The 50-80 line estimate is realistic for Python stdlib. No feasibility concern.

---

### M-1 (Major): Ref write ownership ambiguity -- RESOLVED

Round 1 identified that the plan conflated CLI-context and skill-context for writing
plan-ref files. The revised plan (Component 7, lines 548-576) introduces a clean
mechanism: the `/architect` skill calls `devkit plan sync "$DEVKIT_TARGET_0_PATH"`
via Bash in Step 4 PASS path.

This is neither the skill writing JSON directly (option A from round 1) nor the CLI
writing post-completion (option B). It is a third option that leverages the CLI's
`devkit plan sync` subcommand from within the skill's Bash tool. The plan explains
why this was chosen over alternatives (lines 555-559):

- The skill runs inside Claude Code (LLM + Bash tools), so it cannot call Python
  functions in `devkit_cli.py` directly.
- `devkit plan sync` is idempotent, handles validation, and does not require the
  skill to know the ref JSON schema.
- The CLI never needs to know which plan file was created (opacity preserved).

The mechanism is also used by `/ship` for archive-time ref cleanup via
`devkit plan archive` (line 646). Both call paths are Bash-based, consistent with
the skill execution model. The `write_plan_refs()` Python function serves the CLI
commands (`devkit plan sync`, `devkit plan validate`), not skills directly.

No feasibility concern.

---

### M-2 (Major): Thin test coverage -- RESOLVED

Round 1 said 15 tests was insufficient for the scope, recommending 25-30. The
revised plan has 29 tests (numbered 120-148), covering:

| Category | Tests | Count |
|----------|-------|-------|
| Frontmatter parser | 120-125 | 6 |
| devkit:// URI | 126-128 | 3 |
| Plan ref lifecycle | 129-131 | 3 |
| Multi-target shell | 132-134 | 3 |
| Multi-target dispatch | 135-137 | 3 |
| devkit plan subcommand | 138-142 | 5 |
| read_plan_refs | 143-144 | 2 |
| validate_plan_targets | 145-146 | 2 |
| cmd_path traversal | 147 | 1 |
| plan archive | 148 | 1 |

Round 1 specific gaps resolved:

- "No test for `devkit plan show`" -- Test 139 added.
- "No test for `devkit plan validate`" -- Tests 140-141 added (missing primary,
  uninitialized secondary).
- "No test for `devkit plan sync`" -- Test 142 added (rebuild + stale cleanup).
- "No test for `read_plan_refs()`" -- Tests 143-144 added (missing dir, oversized).
- "No negative test for `validate_plan_targets()`" -- Tests 145-146 added
  (duplicate primaries, no primary).
- "No test for multi-target with `--detach`" -- Test 137 added.
- "Tests 129, 132, 133 are code inspection tests" -- All three are now functional
  tests that invoke code paths and assert behavior (not structure).

Test numbering is verified correct: 118 existing `run_test` calls (numbered 1-119,
one gap), 29 new tests starting at 120. Total: 147 `run_test` calls, last numbered
148 (header count updated to 147 per line 1187).

No feasibility concern.

---

### m-1 (Minor): URI edge cases -- PARTIALLY RESOLVED

Round 1 listed six edge cases: no path component, trailing slash, empty path,
URL-encoded characters, nested subdirectories, and empty authority.

The revised plan addresses security-critical cases through defense-in-depth:

- Path traversal: rejected via `..` segment check and path containment validation
  (TB-3, line 791; STRIDE, lines 806-808; Test 127).
- Invalid project-id: rejected via regex format check (TB-3; Test 128).
- Resolved path containment: validated to be under `~/.claude-devkit/projects/<id>/`.

The remaining edge cases (empty path, trailing slash, URL-encoded characters) are
not explicitly defined but would fail at the filesystem level (file not found) or
at the path containment check. This is acceptable behavior -- these are malformed
inputs, not attack vectors.

One note: the STRIDE analysis (line 808) says URI paths must "start with `plans/`"
but Component 6 shows URIs like `devkit://<id>/plans/archive/<feature>/<file>` which
are deeper paths. The implementation should allow arbitrary depth under the project
root, not just `plans/`. The plan's `resolve_devkit_uri()` containment check
(resolved path must be under `~/.claude-devkit/projects/<valid-id>/`) handles this
correctly regardless. The "start with `plans/`" comment in the STRIDE table is
inaccurate but not harmful -- the containment check is the actual security control.

Not a blocker.

---

### m-2 (Minor): `--with` extraction algorithm -- RESOLVED

Round 1 asked for an explicit extraction algorithm. The revised plan provides a
complete Python function specification in Component 4 (lines 349-406) with:

- Full `extract_with_targets()` implementation with pair consumption.
- Error handling: missing path after `--with` (exit 2), flag instead of path (exit 2).
- Extraction order diagram showing interaction with `--detach` and `--` (lines 387-406).
- Explicit statement that this is NOT identical to `--detach` (Deviation 5, line 1289).

The algorithm is sound. I verified it against the existing `--detach` extraction
(lines 1802-1805 of `devkit_cli.py`): `--detach` is a simple list filter,
`extract_with_targets` is a pair-consuming linear scan. They are correctly ordered
(with-extraction first, then detach extraction).

---

### m-3 (Minor): `/ship` work group filtering behavior -- RESOLVED

Round 1 asked for defined behavior for unannotated work groups, matching semantics,
and no-match scenarios. The revised plan (Component 8, lines 605-626) specifies:

- **Matching:** Case-insensitive comparison of `**Target:** <name>` against
  `DEVKIT_TARGET_N_NAME` (basename of project directory).
- **Unannotated work group:** Treated as primary-target-only with logged warning.
- **Mismatched target name (typo):** Skipped with warning.
- **No matching work groups:** PASS with informational log (not an error).

All three round 1 edge cases are addressed.

---

### m-4 (Minor): `devkit plan list` performance -- NOT ADDRESSED (acceptable)

The revised plan does not add output limits or caching for `devkit plan list`. The
scan algorithm (lines 300-314) parses all `*.md` files in `plans/` and reads all
`.ref.json` files in `plan-refs/`.

This remains a theoretical concern, but in practice, the number of plans per project
is naturally bounded (tens, not thousands). Combined with the max-10-targets limit
and the fast-fail frontmatter parser (no file larger than a few KB), performance is
not a realistic blocker. Acceptable as-is.

---

### m-5 (Minor): Tilde paths in ref files -- RESOLVED

The revised plan explicitly addresses this in three places:

1. Component 2 (lines 257-259): "All paths in ref files are absolute (no tildes).
   Paths are expanded via `Path.expanduser().resolve()` before writing."
2. Ref schema (lines 670-691): Path fields specified as `<string, max 4096, absolute,
   no tildes>`.
3. Test 131 (lines 988-989): Asserts `primary_plan_path` and `project_path` fields
   contain no `~` character.

Thoroughly addressed.

---

### m-6 (Minor): Test numbering -- RESOLVED

The revised plan (lines 917-919) correctly documents the existing test state:
118 `run_test` calls numbered 1-119 (one gap). New tests start at 120, contiguous
with the last existing test. I verified this against the actual test file.

---

## New Concerns

### n-1 (Minor): STRIDE table inaccuracy on URI path prefix

The STRIDE analysis (line 808) states that URI paths "must start with `plans/`" but
the `devkit://` URI examples in Component 6 include paths like
`plans/archive/<feature>/<file>` (which starts with `plans/` but goes deeper). The
actual security control is the resolved-path containment check (must be under
`~/.claude-devkit/projects/<valid-id>/`), not a `plans/` prefix check.

The implementation should use the containment check as the authoritative control and
not enforce a `plans/`-only prefix -- otherwise `devkit plan resolve` would reject
archive paths. The plan's `resolve_devkit_uri()` specification (line 863) says
"path containment check" without mentioning a prefix restriction, so the STRIDE table
text is merely inaccurate documentation, not a design flaw.

**Impact:** None. The implementer will follow the `resolve_devkit_uri()` spec, not
the STRIDE table prose. No code change needed.

---

### n-2 (Minor): No test for single-target `DEVKIT_TARGET_0_*` env var propagation

The plan specifies (lines 421-435) that `DEVKIT_TARGET_COUNT=1` and
`DEVKIT_TARGET_0_*` vars are always set for single-target invocations. This is a
behavioral change (additive, backward-compatible). However, no test verifies that
single-target invocations set these new vars. Test 132 covers multi-target (count=2)
but does not assert the single-target case.

**Impact:** Low. Acceptance criterion AC-6 mentions single-target is unaffected, and
the env var setting is straightforward code. An implementer could add a quick
assertion to an existing single-target test.

---

### n-3 (Minor): `cmd_shell` signature change not shown explicitly

The plan (lines 409-411) says `main()` routing changes from `cmd_shell(rest[0], config)`
to `cmd_shell(rest, config)`, with the function extracting the primary target from
`rest[0]` internally. This is a signature change to an existing function. The plan
describes the intent but does not show the new function signature (e.g., first
parameter changes from `target_str: str` to `args: list`).

**Impact:** None. The implementer will see the routing change and adjust the function
signature accordingly. This is a normal level of implementation detail for a plan.

---

## Time Estimate Assessment

The revised plan estimates 18-22 hours (line 8), up from round 1's 14-20 hours.
Round 1 assessed 18-23 hours. The revised estimate aligns well with the round 1
assessment.

| Work Group | Plan Estimate | Assessed Estimate | Notes |
|------------|--------------|-------------------|-------|
| WG1: CLI infrastructure | ~10h (implied) | 10-12h | Parser spec is detailed enough to implement directly. `cmd_plan()` with 6 actions is substantial but straightforward (each action is ~30-50 lines). |
| WG2: Skill updates | ~3h (implied) | 3-4h | Architect changes are well-scoped. Ship changes are minimal and advisory. |
| WG3: Tests + docs | ~5h (implied) | 5-6h | 29 tests at the detailed specification level provided. CLAUDE.md updates touch many sections. |
| **Total** | **18-22h** | **18-22h** | Aligned. |

---

## Work Group Partition Assessment

Work groups remain correctly partitioned with no cross-group file conflicts:

- **WG1** modifies `scripts/devkit_cli.py` and `configs/devkit-defaults.json`
- **WG2** modifies `skills/architect/SKILL.md` and `skills/ship/SKILL.md`
- **WG3** modifies `scripts/test-integration.sh` and `CLAUDE.md`

No file appears in more than one work group. The shared dependency (constants in
`devkit_cli.py` lines 46-77) is correctly listed and belongs to WG1. The
coordination dependency (WG2 references env var names defined by WG1) is documented
in the Interfaces table.

---

## Verdict: PASS

All three required pre-implementation fixes from round 1 are resolved:

1. **C-1 (frontmatter parser):** Fully rewritten with detailed state machine spec,
   regex patterns, atomic failure semantics, and realistic size estimate. Feasible
   with Python stdlib.
2. **M-1 (ref write ownership):** Resolved with a clean mechanism (`devkit plan sync`
   called via Bash from skills). Execution model boundary is clear.
3. **M-2 (test coverage):** Expanded from 15 to 29 tests, covering all identified
   gaps. Test count matches the recommended 25-30 range.

All six minor concerns from round 1 are resolved or accepted (m-4 plan list
performance is acceptable without changes).

Three new minor concerns identified (n-1 through n-3), none of which are blockers.
The plan is ready for implementation.
