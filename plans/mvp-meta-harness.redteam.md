# Red Team Review: MVP Meta-Harness for Claude Devkit (Round 2)

**Reviewed:** 2026-08-19
**Reviewer:** Security Analyst (Red Team, Second Pass)
**Plan:** `plans/mvp-meta-harness.md`
**Prior Review:** Round 1 (2026-08-19) -- 0 Critical, 3 Major, 5 Minor, 3 Info

## Verdict: PASS

All three Major findings from Round 1 have been resolved with substantive changes. No new Critical findings. One new Major design issue identified (argument restriction blocks documented skill flags), but this is a design ambiguity resolvable during implementation -- not a security regression. The overall security posture of the revised plan is significantly improved.

---

## Previously Identified Findings -- Resolution Status

### RT-1: `allowed_roots` Default Diverges from Existing Validation (Major)

**Status: RESOLVED**

The plan now defaults `allowed_roots` to `["~/projects/", "~/workspaces/"]` (line 370) with `$CLAUDE_DEVKIT` and `/tmp/` always allowed (line 375). This matches the existing `validate_target_dir()` patterns in `generate_agents.py` and `generate_skill.py`. The Context Alignment section, STRIDE table, trust boundary TB-2, and `configs/devkit-defaults.json` schema are all consistent.

**Assessment:** Substantive fix, not cosmetic. The attack surface for path-based privilege widening is now equivalent to the existing generator validation.

---

### RT-2: Argument Injection via Skill Args Passed to `--print` (Major)

**Status: RESOLVED (with new design concern -- see New Findings)**

The plan now includes:
- Skill name regex validation: `^[a-z][a-z0-9-]*$` (line 711)
- Argument rejection for `--` prefixed args (line 329)
- `validate_args()` function in pseudocode (lines 728-730)
- STRIDE table entry for "Skill name or args inject Claude CLI flags" (line 498)
- Architecture diagram updated (lines 129-131)
- Trust boundary TB-1 updated with validation details (lines 454-455)

**Assessment:** The injection vector is closed. However, the argument restriction introduces a new usability issue documented below as New Finding NF-1.

---

### RT-3: TOCTOU Race in Target Validation (Minor)

**Status: RESOLVED**

The plan now explicitly states: "The resolved path (from `Path.resolve()`) is always passed to `subprocess.run(cwd=...)`, not the user-provided string" (lines 278-280). The `cmd_run_skill` pseudocode says "Validate target (get resolved path)" (line 775) and "All operations after `validate_target()` use the resolved absolute path, never the user-provided string" (line 875).

**Assessment:** Clear and unambiguous. The TOCTOU gap is closed.

---

### RT-4: `os.execvp` in `cmd_shell` Replaces Process Without State Update (Minor)

**Status: RESOLVED**

The `cmd_shell` pseudocode (lines 787-792) now updates state and registry before `execvp`. The Known Limitation section (lines 222-225) documents that `exit_code` remains `null` because the harness never regains control. This is the correct trade-off.

**Assessment:** Adequate. The documentation is honest about the limitation.

---

### RT-5: No Locking on Registry File (Minor)

**Status: RESOLVED**

The Concurrent Access section (lines 259-263) documents this as a known limitation with explicit reasoning: "`tempfile + os.replace()` prevents partial writes but not lost updates."

**Assessment:** Adequate. Correct call to accept rather than over-engineer.

---

### RT-6: `devkit deploy` Passes Raw Args to Shell Script (Minor)

**Status: UNCHANGED (was acceptable as-is)**

The `cmd_deploy` design is unchanged. The original review rated this acceptable and recommended documenting as a design decision. The list-form `subprocess.run` prevents shell injection.

**Assessment:** No action needed. Remains acceptable.

---

### RT-7: Test Coverage Gaps -- No Negative Tests for Security Controls (Major)

**Status: RESOLVED**

The plan now includes 5 security-focused tests (Tests 51-55):

| Test | What it validates | Original recommendation |
|------|-------------------|------------------------|
| 51 | Symlink rejection | Yes (recommended) |
| 52 | `allowed_roots` enforcement | Yes (recommended) |
| 53 | Oversized state.json handling | Yes (recommended) |
| 54 | Invalid skill name rejected | Yes (recommended) |
| 55 | Arg injection (`--system-prompt`) rejected | New (beyond recommendation) |

Total test count increased from 8 to 13. All four originally recommended tests are present, plus one additional security test.

**Assessment:** Substantive improvement. Test coverage now matches the documented security controls.

---

### RT-8: `--print` Flag with Multi-Step Skills (Minor)

**Status: RESOLVED**

Manual testing step 5 (lines 622-624) now explicitly tests `/architect` in `--print` mode. Rollout step 1 (lines 558-560) verifies `--print` semantics before any implementation. Assumption 2 (lines 106-108) is updated.

**Assessment:** Adequate. The highest-risk assumption is verified first.

---

### RT-9: `.devkit/` Directory Permissions Inconsistency (Info)

**Status: RESOLVED**

State file permissions changed to 0600 (line 217), consistent with registry. Acceptance criteria updated (line 646). Design decisions section explains the rationale (lines 217-218).

**Assessment:** Clean fix.

---

### RT-10: No Schema Migration Strategy (Info)

**Status: RESOLVED**

Schema migration policy added (lines 228-229): "warn to stderr and proceed with best-effort parsing."

**Assessment:** Matches the existing audit event schema pattern.

---

### RT-11: `allowed_roots` vs Existing Patterns (Info)

**Status: RESOLVED**

Both `~/projects/` and `~/workspaces/` are now included in `allowed_roots` (line 370). The plan references the `generate_agents.py` behavior for the always-allowed devkit root and `/tmp/` paths (line 376).

**Assessment:** Consistent with existing patterns.

---

### Security-Analyst Supplement Items (from Round 1)

| Item | Status |
|------|--------|
| Missing TB-5 for `devkit-defaults.json` | **RESOLVED** -- Added as TB-5 (lines 448-452) with integrity rationale |
| Missing failure mode for corrupt config file | **RESOLVED** -- Added hardcoded fallback defaults (lines 383-386, 539-540, 696-709) |
| Field length limits unspecified | **RESOLVED** -- Schema table with max lengths (lines 397-403): project_name 255, skill 64, timestamps 30, args 1024 |

---

## New Findings

### NF-1: `--` Argument Restriction Blocks Documented Skill Flags

**Severity: Major**

The plan rejects all arguments starting with `--` (line 329) and suggests a `--` separator workaround: `devkit architect ~/foo -- --fast` (line 330). However, line 335 then states that arguments after `--` "still cannot start with `--`." This is self-contradictory: the workaround suggested for the restriction does not actually work under the restriction.

More critically, three documented skill flags are incompatible with this restriction:

| Skill | Flag | Purpose | CLAUDE.md Reference |
|-------|------|---------|---------------------|
| `/architect` | `--fast` | Skip red team review | Skill Registry table |
| `/ship` | `--security-override "reason"` | Override security gates at L2/L3 | Security Maturity Levels section |
| `/fix` | `--dry-run` | Preview without committing | Skill Registry table |

Under the current design, `devkit ship ~/foo plans/bar.md --security-override "reason"` would be rejected at arg validation, even though `--security-override` is a security infrastructure feature that users explicitly need at L2/L3 maturity. The interactive workaround (`devkit shell`) exists but defeats the purpose of non-interactive execution.

**Root cause:** The original RT-2 finding identified CLI flag injection as the threat. The mitigation is overly broad. Since args are concatenated into a single `--print` prompt string (`["claude", "--print", "/skill args"]`), the `--` prefixed args cannot be interpreted as Claude CLI flags -- they are text inside the prompt argument. The injection vector does not exist in this invocation model.

**Recommendation:** Resolve the `--` separator contradiction. Two options:
1. **Allow `--` args after separator:** Validate that args before `--` do not start with `--`, but forward args after `--` verbatim. This is safe because all forwarded args become part of the prompt string, not separate CLI arguments. Update `validate_args()` pseudocode accordingly.
2. **Drop `--` rejection entirely:** Since the invocation model uses list-form subprocess with all args inside a single prompt string element, there is no injection vector. Replace the `--` rejection with a documentation note explaining why it is safe. This is the simpler approach but loses the defense-in-depth posture.

Option 1 is recommended. It preserves the conservative default while enabling documented skill workflows.

---

### NF-2: `--` Separator Pseudocode Ambiguity in `validate_args()`

**Severity: Minor**

The `validate_args()` pseudocode (lines 728-730) says "Reject any arg starting with `--`" without mentioning the `--` separator logic described in the Input Validation section (lines 333-335). The argparse strategy section (lines 849-853) discusses `parse_known_args()` but does not describe how the `--` separator interacts with skill dispatch. An implementer following the pseudocode would reject all `--` args unconditionally, which may or may not be the intent.

**Recommendation:** Align the `validate_args()` pseudocode with the Input Validation prose. If the `--` separator allows `--` prefixed args after it (per NF-1 recommendation), update the pseudocode to reflect this: "Reject any arg starting with `--` that appears before the `--` separator. Args after `--` are forwarded verbatim."

---

### NF-3: STRIDE Table Missing Explicit Entry for TB-5 Config Tampering

**Severity: Minor**

Trust boundary TB-5 (`configs/devkit-defaults.json`) is well-defined (lines 448-452) and the Asset table includes the file (line 431). However, the STRIDE analysis table (lines 492-498) has no entry for config file tampering. The `claude_command` field is the highest-risk config value -- if tampered, it controls which binary `subprocess.run()` executes. The trust model (integrity depends on git history) is correct, but a STRIDE entry would complete the analysis.

**Recommendation:** Add a STRIDE row:

| Threat | Category | Vector | Mitigation | Residual Risk |
|--------|----------|--------|-----------|---------------|
| Attacker modifies devkit-defaults.json to change `claude_command` or widen `allowed_roots` | **Tampering** | Supply chain or direct file modification | File is in devkit repo, trusted at code level. Hardcoded fallback used if file is corrupt. `claude_command` is validated as executable on PATH before invocation. | Low -- same trust as any source file |

---

### NF-4: `devkit status` Reads `.claude/settings.json` from Potentially Untrusted Projects

**Severity: Info**

The `cmd_status` pseudocode (line 798) reads `.claude/settings.json` from target projects to display `security_maturity`. If a project was cloned from an untrusted source, this file could contain crafted JSON. The state.json read has explicit type/length validation (TB-4), but the `.claude/settings.json` read is not described with the same rigor.

**Impact:** Very low. The value is used for display only (in `status` output), and `json.loads()` parsing prevents code execution. A malicious value would at worst display garbage in the status table.

**Recommendation:** Add a note that `.claude/settings.json` values used in `status` display are treated as untrusted strings and truncated for display (e.g., max 20 chars for `security_maturity`).

---

## Security-Analyst Supplement

### STRIDE Re-Validation

The STRIDE analysis has been materially improved since Round 1. All six categories are present with specific, actionable mitigations.

| Category | Round 1 Assessment | Round 2 Assessment | Change |
|----------|-------------------|-------------------|--------|
| **Spoofing** | Adequate | Adequate | `allowed_roots` tightened, now matches existing patterns |
| **Tampering** | Adequate | Adequate | Skill name regex and arg rejection added. TB-5 config trust documented. Minor gap: no explicit STRIDE entry for TB-5 (NF-3) |
| **Repudiation** | Adequate | Adequate | No change needed |
| **Information Disclosure** | Adequate | Adequate | state.json permissions harmonized to 0600 |
| **Denial of Service** | Adequate | Adequate | No change needed |
| **Elevation of Privilege** | Weakened by broad `allowed_roots` | Adequate | Default narrowed to `~/projects/` + `~/workspaces/` |

### Trust Boundary Changes

Round 1 identified four trust boundaries (TB-1 through TB-4). Round 2 adds TB-5 for `configs/devkit-defaults.json`.

**TB-5 Assessment:** The trust model is correct -- the config file is in the same repo as the code and has the same integrity guarantees. The hardcoded fallback defaults (lines 696-709) ensure that a deleted or corrupted config file does not widen the attack surface or break functionality. The fallback values match the config schema exactly. This is a good defense-in-depth pattern.

**No trust boundaries were removed or weakened by the revision.**

### Mitigation Specificity Re-Assessment

| Control | Round 1 | Round 2 | Notes |
|---------|---------|---------|-------|
| Symlink rejection | Specific | Specific | Unchanged |
| Allowed roots | Overly permissive default | Specific | Tightened to named directories |
| No shell=True | Specific | Specific | Unchanged |
| Atomic writes | Specific | Specific | Unchanged |
| Size limits | Specific | Specific | Unchanged |
| File permissions | Inconsistent (0644 vs 0600) | Specific | Harmonized to 0600 |
| Field validation | Partially specified | Specific | Max lengths now in schema table |
| Skill name validation | Not present | Specific | Regex `^[a-z][a-z0-9-]*$` |
| Arg injection guard | Not present | Overly broad | Blocks documented skill flags (NF-1) |
| Config fallback | Not present | Specific | Hardcoded defaults match schema |

### Failure Modes Re-Assessment

Round 1 identified a missing failure mode (corrupt config file). This is now addressed with hardcoded fallback defaults. Two additional failure modes were added for skill name validation and arg rejection.

All documented failure modes are fail-secure (exit 1 or warn-and-continue with safe defaults).

---

## Summary of Findings

### Round 1 Findings -- All Resolved

| # | Severity | Finding | Status |
|---|----------|---------|--------|
| RT-1 | **Major** | `allowed_roots` default too broad | RESOLVED |
| RT-2 | **Major** | Argument injection via skill args | RESOLVED |
| RT-7 | **Major** | No security-focused tests | RESOLVED |
| RT-3 | Minor | TOCTOU in target validation | RESOLVED |
| RT-4 | Minor | `shell` command untracked | RESOLVED |
| RT-5 | Minor | No registry file locking | RESOLVED (documented) |
| RT-6 | Minor | Deploy args passthrough | Unchanged (acceptable) |
| RT-8 | Minor | `--print` mode with multi-step skills | RESOLVED |
| RT-9 | Info | state.json permissions inconsistency | RESOLVED |
| RT-10 | Info | No schema migration strategy | RESOLVED |
| RT-11 | Info | allowed_roots vs existing patterns | RESOLVED |

### New Findings (Round 2)

| # | Severity | Finding | Action Required |
|---|----------|---------|-----------------|
| NF-1 | **Major** | `--` arg restriction blocks `--fast`, `--security-override`, `--dry-run` | Resolve `--` separator contradiction; allow skill flags after separator |
| NF-2 | Minor | `validate_args()` pseudocode omits `--` separator logic | Align pseudocode with prose |
| NF-3 | Minor | STRIDE table lacks entry for TB-5 config tampering | Add STRIDE row for config file integrity |
| NF-4 | Info | `status` reads `.claude/settings.json` from untrusted projects | Add display-truncation note |

<!-- Red Team Review Metadata (Round 2)
plan: plans/mvp-meta-harness.md
reviewed_at: 2026-08-19T20:30:00Z
reviewer: security-analyst (red team, second pass)
round: 2
verdict: PASS
prior_verdict: PASS_WITH_NOTES
critical_count: 0
major_count: 1 (new)
minor_count: 2 (new)
info_count: 1 (new)
resolved_from_round_1: 11/11
-->
