# Feasibility Review: Integrate 10 Curated Prodsec-Skills into Claude Devkit

**Reviewer:** code-reviewer-specialist
**Plan reviewed:** `plans/integrate-prodsec-skills.md` v1.1.0
**Date:** 2026-07-15
**Round:** 2 (revision review)

---

## Verdict: PASS

All Critical and Major findings from Round 1 have been resolved. One new Major issue was introduced in the test specification (test 68 creates a fixture in the wrong directory). The fix is a two-line change and does not affect the plan's architecture, infrastructure design, or skill content. The plan is ready for implementation with this single adjustment applied.

---

## Round 1 Findings Resolution

### C1. Source paths corrected -- RESOLVED

**Round 1:** All 10 skills had source paths pointing to `module/skills/`, but 8 only existed under `.lola/modules/prodsec-skills/module/skills/` (or equivalently `.claude/skills/`).

**Resolution:** The plan now uses two valid path prefixes:
- 5 skills use `.claude/skills/` (input-validation-injection, client-side-security, semgrep, build-yaml-misconfiguration, container-hardening)
- 2 skills use `module/skills/` (ai-code-review, threat-model)

All 7 paths verified to exist on disk. The `threat-model/reference/` subdirectory (otm-schema.md, report-template.md) exists at the `module/skills/threat-model/reference/` path used by the plan. The `.claude/skills/threat-model/` path does NOT have a `reference/` subdirectory, so using `module/skills/` for threat-model is the only correct choice.

The two path styles are cosmetically inconsistent but functionally correct.

### C2. validate_frontmatter() is_reference fix -- RESOLVED

**Round 1:** Knowledge-base skills would fail validation because `validate_frontmatter()` requires `model:` when `is_reference` is `False`.

**Resolution:** The plan now explicitly specifies the fix in two places:
- Interfaces section (line 177): "Update the `validate_frontmatter()` call to pass `is_reference=(is_reference or is_knowledge_base)`"
- Task Breakdown, Shared Dependencies item 2 (line 372): Same instruction with rationale

The fix correctly reuses the existing `is_reference` parameter rather than adding a new code path into `validate_frontmatter()`.

### M1. Multi-line YAML description flattening -- RESOLVED

**Round 1:** Prodsec skills use YAML folded block scalars (`>` or `>-`) that devkit's line-by-line `parse_frontmatter()` cannot handle. The plan's examples showed single-line format without acknowledging the conversion requirement.

**Resolution:** Appendix A now includes an explicit "Multi-line description flattening (required)" section (lines 972-985) with:
- Explanation of why flattening is needed (line-by-line parser limitation)
- Before/after example showing the exact conversion from `>` block scalar to double-quoted single-line string
- Instruction to collapse whitespace, wrap in double quotes, and preserve full text

Verified against actual prodsec frontmatter: all 7 source skills use `>` or `>-` for descriptions (confirmed by inspecting input-validation-injection, semgrep, and ai-code-review). The guidance is necessary and correctly specified.

### m1 through m5 (Minor findings) -- Status

| Finding | Status | Notes |
|---------|--------|-------|
| m1: deploy.sh glob pattern | RESOLVED | Uses direct `cp -r "$src/reference" "$dst/reference"` with `rm -rf` stale cleanup (lines 376-380). No glob expansion risk. |
| m2: File count off by one | RESOLVED | Appendix B header now reads "Files Created (9)" (line 989). |
| m3: `gh` CLI repo-name mapping | UNCHANGED | Non-blocking. The plan provides `{owner}/{repo}` placeholder syntax with graceful degradation guidance. Implementer improvisation is acceptable for the mapping heuristic. |
| m4: Test count arithmetic | RESOLVED | Plan specifies 12 new tests (58-69), total 69. Acceptance criterion 12 (line 315) reads "existing 57 + 12 new = 69 total". |
| m5: skill-patterns.json field naming | UNCHANGED | Cosmetic. The `validate_knowledge_base_skill()` function reads requirements from code, not from this config entry. |

---

## New Concerns

### N1. Test 68 creates fixture in wrong directory (Major)

**Impact:** Test 68 ("deploy.sh copies reference/ directory") will fail every run. The test creates a fixture skill, deploys it, and verifies the reference directory was copied -- but the fixture is created where deploy.sh cannot find it.

**Details:**

The test creates the fixture at `$TEST_DIR/skills/test-ref-deploy/` (which resolves to `/tmp/sg-test/skills/test-ref-deploy/`). It then runs:
```bash
cd '$SKILLS_DIR' && bash scripts/deploy.sh test-ref-deploy
```

Inside deploy.sh, `deploy_skill()` resolves the skill path as `$REPO_DIR/skills/test-ref-deploy/` (line 31 of deploy.sh: `local src="$SKILLS_DIR/$skill"`). Since the fixture lives in `/tmp/`, not in the repo's `skills/` directory, deploy.sh prints `ERROR: Skill 'test-ref-deploy' not found` and exits 1. The test expects exit 0.

**Required fix:** Create the fixture in the repo's `skills/` directory instead of `$TEST_DIR`:

```bash
# Test 68: deploy.sh copies reference/ directory
mkdir -p "$SKILLS_DIR/skills/test-ref-deploy/reference"
cat > "$SKILLS_DIR/skills/test-ref-deploy/SKILL.md" << 'REFEOF'
---
name: test-ref-deploy
description: Test fixture for reference directory deployment
type: knowledge-base
version: 1.0.0
attribution: "Test fixture"
---

# Test Reference Deploy

Skill with a reference subdirectory.
REFEOF
echo "# Test reference file" > "$SKILLS_DIR/skills/test-ref-deploy/reference/test-ref.md"
run_test 68 "deploy.sh copies reference/ directory" \
    "cd '$SKILLS_DIR' && bash scripts/deploy.sh test-ref-deploy && test -f ~/.claude/skills/test-ref-deploy/reference/test-ref.md" \
    0
rm -rf "$SKILLS_DIR/skills/test-ref-deploy"
rm -rf ~/.claude/skills/test-ref-deploy
```

Note: `$SKILLS_DIR` in the test script is the repo root (line 44: `SKILLS_DIR="$(dirname "$SCRIPT_DIR")"`), so `$SKILLS_DIR/skills/` is the correct `skills/` directory that deploy.sh searches.

### N2. Tests 58-64 lack file-existence guards (Minor)

Existing skill validation tests (tests 5-36) wrap the validation call in `if [[ -f "$SKILLS_DIR/skills/<name>/SKILL.md" ]]; then` guards. The 7 new skill validation tests (58-64) do not use these guards.

If the test file is committed before the WG1 skills are created (e.g., merged in a separate commit), tests 58-64 will fail with file-not-found errors. This is unlikely given the Phase ordering (Phase 4 runs after Phase 2), but the guard pattern provides resilience if the test suite is run independently.

This is not blocking. The implementer can add guards for consistency or omit them if the tests and skills are committed together.

### N3. Inconsistent source path style across WG1 tasks (Minor)

WG1 tasks use two different path prefixes for prodsec sources:
- `.claude/skills/<name>/SKILL.md` (5 skills)
- `module/skills/<name>/SKILL.md` (2 skills: ai-code-review, threat-model)

Both are valid locations with identical content (confirmed in Round 1). The `module/skills/` path is necessary for threat-model because its `reference/` subdirectory only exists there. Using `module/skills/` for ai-code-review maintains consistency with threat-model, but using `.claude/skills/` for the other 5 introduces a split.

This does not affect correctness. An implementer could normalize all paths to `.claude/skills/` except threat-model (which must use `module/skills/` for the reference directory), but the current specification works as written.

---

## Assessment of Revised Plan Claims

### "All 7 source paths are valid" -- True

All 7 WG1 source paths verified to exist on disk. The threat-model `reference/` subdirectory with both files (otm-schema.md, report-template.md) exists at the specified `module/skills/threat-model/reference/` path.

### "validate_frontmatter() fix prevents model: requirement for knowledge-base" -- True

The `is_reference=(is_reference or is_knowledge_base)` approach reuses the existing exemption mechanism (lines 100-107 of validate_skill.py). When `is_reference` is `True`, the `model:` check is skipped entirely. Knowledge-base skills will inherit this exemption. The fix cannot break existing reference or standard skill validation because the boolean expression only expands the exemption -- it never narrows it.

### "Description flattening guidance is sufficient for the implementer" -- True

Appendix A provides clear before/after examples of the exact conversion needed. The implementer has explicit instructions to collapse whitespace, wrap in double quotes, and preserve full text. Combined with validator feedback (validate_skill.py will catch empty or malformed descriptions), this is sufficient.

### "12 new tests cover the integration" -- True, with N1 caveat

The test coverage is well-designed:
- 7 positive tests (58-64) validate each new skill
- 3 negative tests (65-67) verify knowledge-base archetype constraints (empty body, missing attribution)
- 1 deploy test (68) verifies reference/ directory copying -- **will fail as specified due to N1**
- 1 smoke test (69) validates grep pattern syntax for the secrets-scan enhancement

Test 68 needs the N1 fix to work. The remaining 11 tests are correctly specified.

### "Work group boundaries remain independent after revision" -- True

Verified: WG1 creates files in `skills/<new-name>/`, WG2 modifies files in `skills/<existing-name>/`, WG3 modifies `CLAUDE.md` and `generators/test_skill_generator.sh`. No file overlap. Shared dependencies (skill-patterns.json, validate_skill.py, deploy.sh) are correctly isolated as prerequisites committed before worktree creation.

---

## Recommended Adjustments

1. **Fix test 68 fixture directory** (N1): Replace `$TEST_DIR/skills/test-ref-deploy/` with `$SKILLS_DIR/skills/test-ref-deploy/` in both the mkdir/cat/echo lines and the cleanup rm lines. This is the only change required before implementation.
