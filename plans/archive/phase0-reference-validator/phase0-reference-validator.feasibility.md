# Feasibility Review (Rev 2): Phase 0 -- Reference Archetype Validator Support + Rollback Mechanism

**Reviewed:** 2026-03-05
**Reviewer:** Code Reviewer (code-reviewer agent)
**Plan:** `plans/phase0-reference-validator.md` (Rev 1.1)
**Previous Review:** Rev 1 feasibility review (same file, overwritten)
**Source files verified:** `generators/validate_skill.py`, `configs/skill-patterns.json`, `scripts/deploy.sh`, `generators/test_skill_generator.sh`

---

## Verdict: PASS

The revised plan adequately addresses all three Major findings from Rev 1. The implementation is technically feasible, backward-compatible, and well-scoped. The remaining concerns below are Minor and do not block implementation.

---

## Previous Findings Resolution Status

| Finding | Status | Assessment |
|---------|--------|------------|
| **M1: Path traversal in `--undeploy`** | RESOLVED | Rev 1.1 adds input sanitization to `undeploy_skill()` (plan lines 214-218) rejecting `/`, `..`, and `-` prefixes. The guard runs before any path construction. Test 32 and manual test plan section 6 cover both `../` traversal and flag-like names. The fix is correct and complete. |
| **M2: Test count inconsistency (32 vs 33)** | RESOLVED | Rev 1.1 consistently uses 33 throughout the plan: section 4 header (line 243), test plan (lines 334, 390), task breakdown (lines 499-501, 506-507), and verification (line 540). The arithmetic is correct: 26 existing tests + 6 new tests + 1 renumbered cleanup = 33 total (tests 1-26 unchanged, 27-32 new, 26 renumbered to 33). |
| **M3: `model` field requirement for Reference skills** | RESOLVED | Rev 1.1 adds a Design Decision section (lines 117-119) explicitly making `model` optional for Reference skills. The rationale is sound: Reference skills are non-executable behavioral documents, so requiring a model field would be semantically misleading. The implementation gates the model check in `validate_frontmatter()` via `is_reference=False` parameter (backward compatible default). The config reflects this with `requires_model: false`. Acceptance criteria include both with-model and without-model test cases (lines 398-399). |

---

## Source Verification Summary

### validate_skill.py (400 lines)

The plan's claims about this file are accurate:

- `validate_frontmatter()` signature at line 78: **confirmed** as `def validate_frontmatter(frontmatter: Dict[str, str], patterns_config: Dict) -> List[Dict]`. Adding `is_reference=False` is a backward-compatible signature change.
- `model` is checked as required at lines 91-98 (within the `required_fields` list `["name", "description", "model"]`). The plan's approach of gating this with `is_reference` is correct, but the implementer should note that `model` is embedded in the `required_fields` list, not checked separately. The implementation will need to either conditionally build the `required_fields` list or move the `model` check outside the loop. The plan's code snippet (lines 126-149) shows a separate `if not is_reference:` block for the model check, which means the `required_fields` list on line 91 must also be modified to exclude `model`. This is an implementation detail the plan does not fully specify -- see Minor concern m1 below.
- `frontmatter, body = parse_frontmatter(content)` at line 370: **exact match**.
- The five validation calls at lines 374-381: **confirmed** in exact order.
- `parse_frontmatter()` returns `(frontmatter_dict, body_content)` at line 43: **confirmed**. The `body` variable is already available in `main()` at line 370 but currently unused past that point. The plan correctly proposes passing it to `validate_reference_skill()`.

### configs/skill-patterns.json (127 lines)

- Two existing top-level keys: `patterns` (array of 10 objects) and `structural_requirements` (array of 5 objects): **confirmed**.
- Adding `archetypes` as a third top-level key is clean and non-conflicting.
- The `structural_requirements[1]` entry lists `"fields": ["name", "description", "model"]`. This is a documentation/config artifact only -- the validator code does not read `structural_requirements` dynamically for field checks. No conflict with the plan.

### scripts/deploy.sh (151 lines)

- `set -euo pipefail` at line 11: **confirmed**.
- `deploy_contrib_skill` ending at line 47: **confirmed**.
- Case-based argument parsing at lines 118-150: **confirmed**.
- The `-*)` catch-all at line 142: **confirmed**.
- `DEPLOY_DIR="$HOME/.claude/skills"` at line 17: **confirmed**.
- The plan's `--undeploy)` case (lines 189-205) correctly inserts before `-*)`. The argument parsing logic handles both `--undeploy <name>` and `--undeploy --contrib <name>`.

### test_skill_generator.sh (331 lines)

- 26 existing tests: **confirmed** (Tests 1-26).
- Test 26 is "Cleanup" at line 301: **confirmed**.
- `TOTAL_COUNT` is dynamically incremented (line 22 initializes to 0, line 43 increments): **confirmed**. No hardcoded count to update.
- Header comment says "26 test cases" at line 4: **confirmed**, needs updating to 33.
- Pre-existing bug: `${BOLD}` is referenced on line 317 but never defined in the color constants (lines 13-17). Not related to this plan but the implementer will encounter it.

---

## Concerns

### Critical Issues

None.

### Major Concerns

None. All three Major concerns from Rev 1 have been resolved.

### Minor Concerns

**m1: The `required_fields` list in `validate_frontmatter()` includes `model` inline.**

The plan's code snippet (lines 126-149) shows a separate `if not is_reference:` block for the model check. However, the actual source at line 91 has `required_fields = ["name", "description", "model"]` and iterates over all three in a single loop (lines 92-98). The implementer must either:
- (a) Change the list to `["name", "description"]` and handle `model` separately below the loop, or
- (b) Conditionally build the list: `required_fields = ["name", "description"] if is_reference else ["name", "description", "model"]`

Both approaches work. The plan implies approach (a) based on the code snippet structure. This is a minor implementation detail that any competent implementer will resolve, but the plan could be more explicit about modifying line 91.

**m2: The `--undeploy --contrib <name>` flag combination is functionally identical to `--undeploy <name>`.**

Both paths call `undeploy_skill("$3")` or `undeploy_skill("$2")` respectively, and both resolve to `$DEPLOY_DIR/$skill` which is `$HOME/.claude/skills/$skill`. Since core and contrib skills deploy to the same directory, the `--contrib` modifier in undeployment is purely semantic. This is not wrong (it mirrors the deploy interface for user ergonomics), but it could confuse users who expect `--contrib` to target a different directory. The plan does not document this equivalence.

**Recommendation:** Add a comment in `undeploy_skill()` or the `--undeploy` case noting that core and contrib skills share the same deploy target, so `--contrib` is accepted for symmetry but functionally equivalent.

**m3: The `core_principle_patterns` matching still has an ambiguity between plan text and config values.**

Rev 1 raised this as minor concern m3. The plan text (line 115) says the validator checks for words: "Law", "Principle", "Rule", or "Gate". The config values (line 169) are phrases: "Iron Law", "Core Principle", "Fundamental Rule", "The Gate". The plan says matching is "case-insensitive substring" (line 431), which means a heading like `## The Iron Law of Testing` would match "Iron Law" as a substring. This works for the planned superpowers skills.

However, a heading like `## Rules for Code Review` would NOT match any config pattern ("Fundamental Rule" is not a substring of "Rules for Code Review"). If the intent is single-word matching, the config should list `["Law", "Principle", "Rule", "Gate"]`. If the intent is phrase matching, the plan text on line 115 should say "phrases" not "words."

Since all six planned superpowers skills use headings that contain one of the configured phrases (per the parent roadmap), this is not a blocking issue. But it could cause confusion for future Reference skills with non-standard heading conventions.

**Recommendation:** Decide which matching granularity is intended and align the plan text with the config. Phrase matching (as configured) is more precise and less prone to false positives.

**m4: Test 22 in the existing suite has a fragile pass condition.**

Test 22 ("Validator detects missing Tool declaration") creates a fixture with `model: opus` (not a valid model name). It passes because the fixture also lacks verdict gate keywords (PASS/FAIL/BLOCKED), which is Pattern 4 with severity `error`. If Pattern 4's severity were ever changed to `warning`, this test would break. This is a pre-existing issue unrelated to this plan, noted for awareness.

**m5: The `structural_requirements` config entry still lists `model` as required.**

`configs/skill-patterns.json` line 103 has `"fields": ["name", "description", "model"]` in the `structural_requirements` section. The validator does not read this array dynamically (it hardcodes its own checks), so this is purely a documentation concern. After this plan lands, the config would have `structural_requirements` saying `model` is required while `archetypes.reference.required_frontmatter` omits `model`. This is technically accurate (model IS required for non-reference skills) but could confuse someone reading the config file.

**Recommendation:** Add a comment or note in the `structural_requirements` entry clarifying that the `model` requirement applies to executable skills only, or add a `"note": "model not required for type: reference"` field.

---

## Implementation Complexity Assessment

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Implementation complexity | Low | Straightforward conditional branching, no new dependencies |
| Breaking change risk | None | Fully additive; `is_reference=False` default preserves all existing behavior |
| Test coverage | Adequate | 6 new tests cover happy path, 3 negative cases, 2 deploy/undeploy cases |
| Edge case coverage | Good | Path traversal, idempotent undeploy, model-optional, model-present all covered |
| Effort estimate | Accurate | Plan says "~150-170 lines" (revised from Rev 1's ~100). Actual is likely ~160 lines. |
| Dependency assumptions | None | Pure Python stdlib, no new imports needed |

---

## What the Plan Gets Right

1. **All Rev 1 Major findings addressed substantively.** The path traversal fix is correct and tested. The test count is consistent. The model-optional decision is well-reasoned and documented.

2. **Backward compatibility is guaranteed by design.** The `is_reference` parameter defaults to `False`. Skills without `type: reference` take the existing code path with zero changes. The `--undeploy` flag is a new case branch that does not affect existing argument parsing.

3. **The validation branching architecture is sound.** Routing Reference skills to a dedicated `validate_reference_skill()` function that skips inapplicable checks (steps, tools, verdicts, inputs, workflow header) is the cleanest approach. The alternative (making every existing function tolerate Reference skills) would be more invasive and fragile.

4. **Test coverage is well-designed.** The 6 new tests cover the key boundaries: valid Reference skill (without model), missing attribution, empty body, no principle heading, undeploy success, and idempotent undeploy. The manual test plan adds path traversal and flag-like name rejection.

5. **Config-driven pattern matching** allows future Reference skills to use different heading conventions without code changes.

---

## Recommendations

1. Clarify how `required_fields` list at line 91 of `validate_skill.py` should be modified to exclude `model` for Reference skills (Minor m1).
2. Add a code comment noting that `--undeploy --contrib` is functionally equivalent to `--undeploy` since both target `$DEPLOY_DIR` (Minor m2).
3. Align heading match granularity between plan text and config values (Minor m3).
4. Consider adding a note to `structural_requirements` in the config about `model` not applying to Reference skills (Minor m5).

None of these recommendations are blocking. The plan is ready for implementation.

---

<!-- Feasibility Review Metadata
reviewed_at: 2026-03-05
revision: 2
verdict: PASS
previous_verdict: PASS
previous_major_concerns: 3 (all resolved)
concerns_critical: 0
concerns_major: 0
concerns_minor: 5
files_verified: generators/validate_skill.py, configs/skill-patterns.json, scripts/deploy.sh, generators/test_skill_generator.sh
-->
