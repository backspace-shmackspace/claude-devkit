# Review: MVP Meta-Harness for Claude Devkit (Second Pass)

**Reviewed:** 2026-08-19
**Plan Version:** R1 (revised per first-pass findings)
**Verdict:** PASS -- all prior blocking conflicts resolved; one new required clarification

---

## Previously Identified Conflicts -- Resolution Status

### Blocking Conflict 1: Path validation too broad

**Original finding:** `allowed_roots` defaulted to `["~/"]`, accepting any
directory under the user's home. Existing generators enforce specific allowlists
(`~/workspaces/`, `~/projects/`, devkit root, `/tmp/`).

**Status: RESOLVED.**

The plan now defaults `allowed_roots` to `["~/projects/", "~/workspaces/"]`
(lines 35-36, 365, 374-381). The devkit root and `/tmp/` are documented as
always-allowed regardless of config (line 375), matching `generate_agents.py`
behavior. The STRIDE analysis (line 497), TB-2 trust boundary (line 465), and
`configs/devkit-defaults.json` schema (line 365) are all consistent. Verified
against the actual generators: `generate_agents.py` line 359 allows
`~/workspaces/`, `~/projects/`, devkit root, `/tmp/`; `generate_skill.py`
line 128 allows `~/workspaces/`, devkit root, `/tmp/`. The plan's default aligns
with the more permissive generator (`generate_agents.py`).

### Blocking Conflict 2: CLI misplaced in generators/

**Original finding:** The devkit CLI is not a generator. CLAUDE.md defines
`/generators` as code generation scripts. The CLI is an orchestration tool.

**Status: RESOLVED.**

All references now use `scripts/devkit_cli.py` (lines 126, 341, 685, 929-930).
The Context Alignment section (lines 44-46) documents the placement rationale,
citing `codebase-scanner.py` as precedent for non-generator Python scripts in
`scripts/`. The CLAUDE.md update plan (Work Group B, lines 987-988) correctly
adds the entry to the Scripts section, not the Generator Registry.

## Previously Required Edits -- Resolution Status

### Edit 1: Narrow allowed_roots default

**Status: RESOLVED.** Same as Blocking Conflict 1. All instances updated
consistently across the plan (configs schema, Context Alignment, Security
Requirements, STRIDE analysis, Trust Boundaries, Acceptance Criteria).

### Edit 2: Relocate CLI to scripts/

**Status: RESOLVED.** Same as Blocking Conflict 2. Architecture diagram
(line 126), New Files table (line 341), Work Group A (line 685), bash wrapper
(line 929), install.sh plan (line 947) all reference `scripts/`.

### Edit 3: Harmonize state file permissions

**Status: RESOLVED.** State.json is now 0600 (lines 216-217, 509, 646),
matching registry.json. The design decision note (line 216-217) justifies the
consistency: "consistent with registry.json. Both files contain the same class
of data (project paths, timestamps, skill invocation metadata)."

### Edit 4: Add early flag verification to Rollout Plan

**Status: RESOLVED.** Rollout Plan step 1 (lines 556-559) is now the `--print`
flag verification: "Verify `--print` flag: Run `claude --print 'echo hello'` to
confirm non-interactive execution works with expected semantics. This is the
highest-risk assumption. If this fails, stop and reassess the invocation model
before any implementation." The revision log (line 7) confirms this as LR-4.

## New Issues Introduced by Revision

### Argument rejection contradicts skill flag forwarding (design ambiguity)

**Severity: Required clarification (not blocking)**

Lines 327-335 introduce an argument injection guard that rejects any argument
starting with `--`. Line 331 suggests the `--` separator as a workaround:
`devkit architect ~/foo -- --fast`. However, line 335 then states that arguments
after `--` "still cannot start with `--`," which would make the example on
line 331 fail.

This contradicts CLAUDE.md's documented skill interfaces:
- `/architect` "Supports `--fast`" (CLAUDE.md Skill Registry)
- `/ship` "Supports `--security-override`" (CLAUDE.md Skill Registry)

If both pre-separator and post-separator `--` arguments are rejected, these
documented skill features become unreachable via the harness.

The underlying security concern (CLI flag injection via `--system-prompt` or
similar) is valid, but the mitigation is already handled structurally: skill
arguments are embedded inside the prompt string
(`["claude", "--print", "/architect --fast"]`), not passed as separate `claude`
CLI arguments. Combined with list-form `subprocess.run` (no `shell=True`),
injection into Claude CLI flags is not possible through the prompt string.

**Required clarification:** Amend lines 333-335 to state that arguments after
the `--` separator are forwarded verbatim without the `--` rejection check.
The rejection applies only to arguments before `--` (which devkit parses as
its own flags). Alternatively, remove the blanket `--` rejection entirely and
rely on the structural mitigation (prompt string embedding + list-form
subprocess). Either approach is safe; the current wording is contradictory.

Test 55 (line 610) is correct as-is -- it tests rejection of `--system-prompt`
without a `--` separator, which should fail regardless of the resolution.

## CLAUDE.md Alignment

- **Python generator patterns (stdlib only, atomic writes, exit codes):**
  Confirmed compliant throughout.
- **Path validation:** Now matches established generator patterns.
- **Script placement:** Consistent with `codebase-scanner.py` precedent.
- **State-on-disk:** Follows `emit-audit-event.sh` per-run state model.
- **Install integration:** Follows `install.sh` marker comment and backup
  pattern.
- **Test integration:** Follows `test-integration.sh` `run_test()` harness.
- **Security maturity model:** Explicitly preserved, not duplicated.
- **Audit logging:** Explicitly preserved in existing locations.

No conflicts with CLAUDE.md rules or directory conventions detected beyond the
argument handling ambiguity noted above.

## Context Alignment and Metadata

- **Context Alignment section (lines 29-66):** Updated to reflect R1 changes.
  Script placement rationale added with `codebase-scanner.py` precedent
  reference. Prior plans section unchanged and still accurate.
- **Deviations section (lines 63-71):** Two deviations documented (`.devkit/`
  directory, global registry). Both are justified and do not conflict with
  existing patterns.
- **Context metadata block (lines 1024-1029):** Present. `claude_md_exists:
  true` is correct. `recent_plans_consulted` lists three relevant plans.
  `discovered_at` timestamp is reasonable. No issues.

## Revision Quality

The Revision Log (lines 5-7) is thorough -- it maps each change back to
specific findings (RT-1, RT-2, RT-7, LR-1 through LR-4, FR-M1 through FR-M3).
Additions from the revision are well-integrated:
- TB-5 for `devkit-defaults.json` (lines 448-455) -- clean addition
- Hardcoded fallback defaults (lines 383-386, 696-710) -- addresses missing
  failure mode
- Skill name regex and validation (lines 128-129, 319-325, 711) -- clean
- Security tests 51-55 (lines 898-910) -- cover the new security controls
- Total test count updated to 13 consistently (lines 589, 597, 877, 1016)

## Optional Suggestions (carried forward)

Previous optional suggestions that remain relevant:

- **`devkit validate` command.** Still a natural addition to round out the CLI.
- **Explicit roadmap placement.** The plan still does not state where the
  meta-harness sits on the CLAUDE.md roadmap (v1.2 or v1.3).
- **Registry pruning command.** Placeholder `devkit prune` would reserve the
  command name.

---

**Summary:** All four required edits and both blocking conflicts from the
first-pass review have been resolved. The revisions are well-integrated and
do not introduce architectural issues. One new design ambiguity was introduced
by the argument injection guard (the `--` separator semantics contradict skill
flag forwarding). This is a straightforward clarification, not an architectural
problem, and can be resolved during implementation. The plan is approved for
implementation.
