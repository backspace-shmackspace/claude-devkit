# Red Team Review: Phase 0 -- Reference Archetype Validator Support + Rollback Mechanism (Rev 2)

**Reviewed:** 2026-03-05
**Reviewer:** Security Analyst (Red Team)
**Plan:** `plans/phase0-reference-validator.md` (Rev 2)
**Previous Review:** Rev 1 (2026-03-05)
**Parent Plan:** `plans/superpowers-adoption-roadmap.md` (Phase 0)

---

## Verdict: PASS

No Critical findings. Rev 2 addressed all three Major findings from Rev 1. The remaining findings are Minor or Info-level and can be addressed during or after implementation without blocking.

---

## Findings

### Finding 1: `--undeploy --contrib` Argument Order Is Fragile and Untested

**Severity: Minor**

The `--undeploy` case block parses `$2` to check for `--contrib`, then uses `$3` as the skill name. However, the argument parsing uses a simple positional `case` on `$1`, meaning the following edge cases are not handled:

- `deploy.sh --contrib --undeploy journal` -- would try to deploy a skill named `--undeploy`, which the `-*` guard at line 122 would catch (good), but the error message ("Invalid skill name: --undeploy") would be confusing since the user intended an undeploy operation.
- `deploy.sh --undeploy` with no further arguments -- the plan handles this with an argument count check (good).
- `deploy.sh --undeploy --undeploy` -- would be parsed as "undeploy the contrib skill named..." which is nonsensical but would fail gracefully since `undeploy_skill` would report "not found."

None of these are exploitable, but the test suite (Tests 31-32) only covers the happy path and the idempotent case. No test covers the `--undeploy --contrib <name>` variant.

**Recommendation:** Add a test case for `--undeploy --contrib <name>` to confirm end-to-end behavior, even if it is functionally identical to `--undeploy <name>`.

---

### Finding 2: `validate_reference_skill` Does Not Receive the Raw `content` String

**Severity: Minor**

The plan's proposed code block passes `(frontmatter, body, patterns_config)` to `validate_reference_skill()`. The `body` variable comes from `parse_frontmatter()` which returns everything after the closing `---`. This is correct for the "non-empty body" check.

However, the "core principle heading" check searches for markdown headings in `body`. If the plan's implementation uses `body` (post-frontmatter content), this works. But the plan's description says "Search all headings (`^#{1,6} .+`)" without specifying whether it searches `content` (full file) or `body` (post-frontmatter). If someone passes `content`, the frontmatter delimiter `---` line and frontmatter keys would also be searched, though this would not cause false positives since frontmatter lines do not start with `#`.

This is a clarity issue, not a correctness issue. The plan's function signature makes the intent clear enough.

**Recommendation:** No action needed. The function signature disambiguates.

---

### Finding 3: `core_principle_patterns` Config Fallback Is Silent

**Severity: Minor**

The plan states that `validate_reference_skill` loads patterns from `patterns_config.get("archetypes", {}).get("reference", {})`. If `skill-patterns.json` is missing the `archetypes` key (e.g., someone edits the config and removes it), the function would get an empty dict. The `core_principle_patterns` list would then be empty, and the heading check would either (a) pass vacuously (if the loop checks "any pattern matches" and there are no patterns), or (b) fail with a confusing error.

The plan does not specify the behavior when patterns are missing from config. Given that `skill-patterns.json` is version-controlled and deployed alongside the validator, this is unlikely to happen in practice.

**Recommendation:** Add a guard in `validate_reference_skill` that emits an error if `core_principle_patterns` is empty or missing from the config, rather than silently passing or failing.

---

### Finding 4: No Negative Test for Reference Skills Containing Step Headers

**Severity: Minor**

Rev 1 Finding 6 noted that the plan does not validate what Reference skills must NOT have (e.g., `## Step 0 -- Do something` with `Tool: Bash`). Rev 2 did not address this.

A Reference skill that contains numbered steps and tool declarations would pass validation, despite being semantically wrong (it should be a Pipeline/Coordinator/Scan skill, not a Reference). This is not a security risk, but it undermines the purpose of archetype classification.

**Recommendation:** Consider adding a warning (not error) in `validate_reference_skill` if `## Step \d+` headers are detected. This catches misclassified skills.

---

### Finding 5: The `attribution` Field Format Is Unconstrained

**Severity: Info**

The plan requires an `attribution` field for Reference skills but does not specify any format constraints beyond "non-empty." The example value is `"Adapted from superpowers plugin (v4.3.1) by Jesse Vincent, MIT License"`, which includes source, version, author, and license -- all useful metadata.

If someone writes `attribution: "yes"`, it would pass validation. This is acceptable for Phase 0 (the reviewer gate in `/dream` catches low-quality attributions), but a future enhancement could validate that attribution contains recognizable license or source information.

**Recommendation:** Document the expected attribution format in the Reference skill template (Phase 1+). No action needed in Phase 0.

---

### Finding 6: `--undeploy --contrib` and `--undeploy` Are Functionally Identical

**Severity: Info**

Carried forward from Rev 1 Finding 7. Both paths call `undeploy_skill()` with the same `$DEPLOY_DIR`. The plan still does not document this equivalence. Users who deploy a contrib skill and later try `--undeploy <name>` (without `--contrib`) would succeed, which could be confusing if they expect symmetry with the deploy interface.

**Recommendation:** Add a comment in `show_help()` noting that `--undeploy` works for any skill regardless of whether it was deployed as core or contrib.

---

### Finding 7: YAML Parser Fragility With Colons in Attribution Values

**Severity: Info**

Carried forward from Rev 1 Finding 9. The simple YAML parser splits on the first `:`, so `attribution: "Source: foo"` would parse correctly (key=`attribution`, value=`"Source: foo"` after stripping quotes). However, unquoted values like `attribution: Source: foo` would parse as key=`attribution`, value=`Source: foo` -- which is actually correct because the split is on the FIRST colon only.

On re-examination, this is less fragile than Rev 1 suggested. The `line.split(':', 1)` on line 70 of `validate_skill.py` splits on the first colon only, so subsequent colons remain in the value. The real risk is multi-line YAML values (using `|` or `>` block scalars), which the parser does not support. Since `attribution` is a single-line field, this is acceptable.

**Recommendation:** No action needed for Phase 0. Document the single-line constraint in the Reference skill template.

---

## Previous Findings Resolution

### Rev 1 Finding 1: Path Traversal in `--undeploy` (Major)

**Status: RESOLVED**

Rev 2 adds input sanitization in `undeploy_skill()` that rejects skill names containing `/`, `..`, or starting with `-`. The guard `[[ "$skill" == */* ]] || [[ "$skill" == *..* ]] || [[ "$skill" == -* ]]` covers the attack vector identified in Rev 1. Test Plan section 6 includes explicit path traversal rejection tests. The sanitization is applied before any path construction, which is the correct placement.

---

### Rev 1 Finding 2: `model` Field Requirement Ambiguity (Major)

**Status: RESOLVED**

Rev 2 adds a dedicated "Design Decision" section explaining why `model` is optional for Reference skills. The implementation adds `is_reference=False` parameter to `validate_frontmatter()` and gates the `model` check behind `if not is_reference`. The `archetypes.reference.required_frontmatter` config omits `model`, and `requires_model: false` is explicitly set. Test 27 validates a Reference skill without `model`. The semantic mismatch and silent coupling concerns from Rev 1 are both addressed.

---

### Rev 1 Finding 3: `validate_patterns()` Regression Risk (Major)

**Status: RESOLVED (partially)**

Rev 2 adds a code comment (line 97 of the plan's proposed code) explaining why `validate_patterns` must not run for Reference skills. However, the structural guard suggested in Rev 1 (a test with `--strict` to confirm no spurious errors) is not explicitly added. Test 27 validates a Reference skill passes, which implicitly confirms `validate_patterns` is not running. This is sufficient -- the comment plus the passing test provide adequate protection.

---

### Rev 1 Finding 4: Test Count Discrepancy (Minor)

**Status: RESOLVED**

Rev 2 consistently says "33 tests" across all sections: Rollout Plan (line 302), Task Breakdown Phase 4, Phase 5 Validation, and Verification.

---

### Rev 1 Finding 5: Permissive Pattern Matching (Minor)

**Status: ACKNOWLEDGED (acceptable)**

Not addressed in Rev 2, but the Rev 1 review itself rated this as acceptable for Phase 0. The `/dream` approval gate provides the real quality check.

---

### Rev 1 Finding 6: No Negative Validation for Reference Steps (Minor)

**Status: OPEN (carried forward as Finding 4 above)**

Not addressed in Rev 2. Severity remains Minor.

---

### Rev 1 Finding 7: Redundant `--undeploy --contrib` (Info)

**Status: OPEN (carried forward as Finding 6 above)**

Not addressed in Rev 2. Severity remains Info.

---

### Rev 1 Finding 8: No Self-Rollback Documentation (Info)

**Status: RESOLVED**

Rev 2 adds "To revert these changes if needed: `git revert <commit-sha>` and redeploy" to the Rollout Plan (line 307).

---

### Rev 1 Finding 9: Fragile YAML Parser (Info)

**Status: RESOLVED (re-evaluated)**

On deeper analysis, the `line.split(':', 1)` approach handles colons in values correctly. The real constraint is multi-line values, which is acceptable for the `attribution` field. Carried forward as Finding 7 (Info) with reduced concern.

---

## Summary

| Severity | Count | Findings |
|----------|-------|----------|
| Critical | 0 | -- |
| Major | 0 | -- |
| Minor | 4 | Untested --contrib undeploy variant, silent config fallback, no negative step validation, content vs body ambiguity |
| Info | 3 | Unconstrained attribution format, redundant --contrib flag, YAML parser single-line constraint |

Rev 2 successfully resolves all three Major findings from Rev 1. The plan is well-scoped, the code changes are backward-compatible, and the test coverage is adequate. The remaining Minor findings are implementation-quality improvements that can be addressed during the `/ship` phase without requiring a plan revision.
