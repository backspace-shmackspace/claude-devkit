# Feasibility Review (Second Pass): MVP Meta-Harness

**Plan:** `plans/mvp-meta-harness.md` (Revision R1)
**Reviewed:** 2026-08-19
**Reviewer:** code-reviewer-specialist (opus-4-6)
**Review Type:** Second-pass verification of Major concern resolution

## Verdict: PASS

All three previously identified Major concerns have been resolved with technically
sound changes. The revisions stay within the plan's "front door, not a rebuild"
philosophy and do not introduce new Major concerns. The updated time estimate of
8-10 hours is realistic given the expanded test surface and documentation scope.

---

## Previously Identified Concerns -- Resolution Status

### M1. Permission prompts in `--print` mode are unaddressed.

**Status: RESOLVED**

The plan now addresses this at four distinct points:

1. **Pre-Flight Check 6** (line 311-315): Reads `~/.claude/settings.json` and
   warns when `allowedTools` is empty or missing. Correctly implemented as a
   warning rather than a hard block (project-level settings may provide the
   allowlist).

2. **Assumption 7** (line 116): Explicitly calls out the permission allowlist
   requirement as an assumption with cross-reference to the Tool Permissions
   section.

3. **Risks table** (line 577): "Permission prompts block non-interactive
   execution" row with Medium likelihood, High impact, and concrete mitigation
   (pre-flight warning, documentation, future `--permission-mode` forwarding).

4. **CLAUDE.md Troubleshooting** (line 996-998): Planned troubleshooting entry
   for permission prompt stalls.

The resolution correctly chose Option 3 from the original review (document and
warn) which fits the plan's minimal-viable approach. The pre-flight warning is
the right balance -- it surfaces the issue without blocking users who have
project-level allowlists.

### M2. Test coverage has meaningful gaps for the security-critical paths.

**Status: RESOLVED**

The plan expanded from 8 to 13 new tests, including all critical security paths:

| Original Gap | New Test | Verified |
|---|---|---|
| Symlink rejection | Test 51: `devkit init` on symlink-to-git-repo exits 1 | Yes |
| `allowed_roots` enforcement | Test 52: `devkit init` on path outside allowed_roots exits 1 | Yes |
| Oversized state.json | Test 53: 100KB state.json produces warning, status still works | Yes |
| Skill name injection | Test 54: `devkit ../../etc/passwd <target>` exits 1 | Yes |
| Argument injection | Test 55: `devkit audit <target> --system-prompt foo` exits 1 | Yes |

Two items from the original review's test gap list (registry file permissions,
re-init idempotency) are not explicitly tested. These are acceptable omissions:
registry permissions are a defense-in-depth measure behind the 0700 parent
directory, and idempotency can be covered in manual testing during rollout step 4.

The five security-focused tests (51-55) map directly to the STRIDE analysis rows
and trust boundary definitions, which is a stronger prioritization than the
original review suggested.

### M3. `devkit shell` cannot update state post-exit.

**Status: RESOLVED**

The plan now documents this as an explicit "Known limitation" (lines 220-225)
in the State Model section. Key details captured:

- `os.execvp()` replaces the harness process -- harness never regains control.
- `last_invocation` is not updated after interactive sessions.
- Pre-invocation timestamp IS written before `execvp` so the registry records
  access.
- `exit_code` is recorded as `null` for shell sessions.
- Users running `devkit status` will see stale `last_touched` for projects
  primarily accessed via `shell`.

The `cmd_shell` pseudocode (lines 786-795) explicitly notes that steps 3-4 run
before `execvp` "because the harness never regains control after process
replacement." This is thorough documentation of an inherent limitation.

---

## Minor Concern Resolutions (from First Pass)

| Concern | Status | Notes |
|---|---|---|
| m1. Line count estimate optimistic | RESOLVED | Updated to 400-500 lines (line 685) |
| m2. Signal handling during skill execution | RESOLVED | `try/finally` block specified (lines 870-871) |
| m4. `allowed_roots` default broader than existing validators | RESOLVED | Default narrowed to `["~/projects/", "~/workspaces/"]` (line 367), matching existing `validate_target_dir()` patterns. Better than just documenting the deviation -- the plan eliminated it. |
| m5. Parent directory permissions | No change needed | Correctly noted as defense-in-depth |
| m6. `--add-dir` for cross-directory access | No change needed | Deferred to rollout testing |

---

## New Concerns Introduced by R1

### Minor

**N1. Blanket `--` argument rejection breaks documented skill flags.**

The argument sanitization (lines 327-335) rejects ALL arguments starting with
`--` to prevent Claude CLI flag injection. However, both `/architect` and `/ship`
have documented flags that start with `--`:

- `/architect --fast` (CLAUDE.md line 115)
- `/ship --security-override "reason"` (CLAUDE.md line 116, 156, 190)

The invocation model constructs a single prompt string:
`["claude", "--print", "/{skill} {args}"]`. Arguments are embedded within the
prompt string value, not passed as separate CLI arguments. The CLI flag injection
risk this guard protects against does not exist with the list-form subprocess call
and string concatenation pattern.

Additionally, the error message suggests `devkit architect ~/foo -- --fast` as a
workaround, but lines 333-335 state that args after `--` "still cannot start with
`--`." The suggested workaround does not work.

Users CAN work around this by quoting args as a single string
(`devkit architect ~/foo "add auth --fast"`), but this is non-obvious and
undocumented.

**Recommendation:** Either (a) remove the blanket `--` rejection since the
list-form subprocess call prevents injection by construction, or (b) keep the
guard but exempt args that appear after the target path position (since they
become prompt text, not CLI flags), or (c) at minimum, fix the error message
to suggest the quoting workaround instead of the `--` separator.

**N2. `configs/devkit-defaults.json` controls `claude_command` -- supply chain note.**

TB-5 (lines 447-452) correctly identifies that `configs/devkit-defaults.json`
controls security-critical settings including `claude_command` (the binary to
execute). The plan correctly notes integrity depends on git history and code
review. The hardcoded fallback defaults (lines 383-386) ensure a corrupted config
cannot change the command to an arbitrary binary. This is well-handled but worth
noting: the fallback defaults should be the ONLY source for `claude_command` --
allowing it to be overridden via a config file is a broader attack surface than
necessary. Consider hardcoding `claude_command` and `claude_print_flag` rather
than making them configurable.

---

## Time Estimate Assessment

The revised estimate of 8-10 hours (up from 6-8) is realistic:

| Component | Estimated Effort | Notes |
|---|---|---|
| CLI core (devkit_cli.py, 400-500 lines) | 3-4 hours | Well-specified pseudocode reduces ambiguity |
| Shell wrapper + install.sh | 0.5 hours | Trivial additions |
| configs/devkit-defaults.json | 0.25 hours | Static JSON, already fully specified |
| 13 integration tests | 2-2.5 hours | Existing `run_test()` harness; temp git repo setup; 5 security tests require symlink and oversized file creation |
| CLAUDE.md updates (7 sections) | 1.5-2 hours | Documentation-heavy, well-enumerated in plan |
| Manual validation (rollout steps 1, 4) | 0.5-1 hour | `--print` flag verification and end-to-end runs |
| **Total** | **7.75-10.25 hours** | **8-10 is a well-calibrated range** |

The upper end (10 hours) accounts for edge cases discovered during implementation
and the CLAUDE.md documentation breadth. The lower end (8 hours) is achievable if
`--print` flag verification (rollout step 1) confirms the assumption immediately.

---

## Summary

| Category | Count | Details |
|---|---|---|
| Previously Major -- RESOLVED | 3/3 | M1 (permission prompts), M2 (test gaps), M3 (shell state) |
| Previously Major -- UNRESOLVED | 0/3 | -- |
| New Major concerns | 0 | -- |
| New Minor concerns | 2 | N1 (arg rejection breaks skill flags), N2 (configurable claude_command) |
| Time estimate | Realistic | 8-10 hours is well-calibrated for the expanded scope |
