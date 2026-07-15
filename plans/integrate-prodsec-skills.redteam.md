# Red Team Review (Round 2): Integrate 10 Curated Prodsec-Skills into Claude Devkit

**Reviewer:** Red Team (critical analysis)
**Plan:** `plans/integrate-prodsec-skills.md` v1.1.0 (revised)
**Round:** 2 (re-review after revision)
**Date:** 2026-07-15

---

## Verdict: PASS

All Critical and Major findings from Round 1 are resolved or substantially resolved. One new Minor finding (test fixture path bug in Test 68) was introduced by the revision. The plan is executable with one mechanical fix described below.

---

## Round 1 Findings Resolution

### F1 (Critical): Source paths for 8/10 skills -- RESOLVED

**What changed:** The plan now specifies correct source paths for all 7 new skills:
- 5 skills use `.claude/skills/<name>/SKILL.md` (input-validation-injection, client-side-security, semgrep, build-yaml-misconfiguration, container-hardening)
- 2 skills use `module/skills/<name>/SKILL.md` (ai-code-review, threat-model)

**Verification:** All 7 paths confirmed to exist on disk in the prodsec-skills repository. The `threat-model/reference/` directory with `otm-schema.md` and `report-template.md` is co-located with the SKILL.md at `module/skills/threat-model/reference/`, which is consistent.

**Assumption 1 addendum:** The plan now says "The source commit SHA from the prodsec-skills repository should be recorded at implementation time in the commit message for traceability." This is a reasonable approach -- deferring SHA recording to implementation time avoids the plan going stale if the source repo receives commits between plan approval and execution. This also resolves Round 1 Finding 7.

No remaining issues.

---

### F2 (Major): threat-model vs. threat-model-gate naming confusion -- RESOLVED

**What changed:** The plan's Work Group 3 CLAUDE.md update now includes:

1. A dedicated clarification block distinguishing the two skills:
   - `threat-model-gate` = planning gate (behavioral discipline, `type: reference`), auto-invoked by `/architect` Stage 2 and `/ship` Step 1
   - `threat-model` = standalone methodology (domain knowledge, `type: knowledge-base`), loaded manually via `Using skills/threat-model/SKILL.md:` syntax

2. Explicit warning: "Do not attempt `/threat-model` -- knowledge-base skills have no workflow steps to execute."

3. A new "Knowledge-Base Pattern" subsection under Skill Architectural Patterns explaining invocation syntax with examples.

This is thorough and addresses all three sub-problems identified in Round 1 (slash-command confusion, registry ambiguity, cross-reference without invocation guidance).

No remaining issues.

---

### F3 (Major): Test plan gaps -- SUBSTANTIALLY RESOLVED

**What changed:** The test plan expanded from 9 tests (58-66) to 12 tests (58-69):

| Round 1 Gap | Resolution | Test # |
|-------------|-----------|--------|
| deploy.sh reference/ directory copy | Added | 68 |
| Knowledge-base missing `attribution` (negative) | Added | 67 |
| Enhanced skill grep pattern syntax validation | Added | 69 |

**Remaining gap:** The `--validate` flag with a knowledge-base skill is still not explicitly tested. Round 1 requested this as item (c). However, Test 65 validates a knowledge-base skill directly with `validate_skill.py`, and the `--validate` flag in deploy.sh simply invokes the same validator. The risk is low because the deploy.sh `--validate` codepath is already tested for other archetypes (Tests 47-49) and the knowledge-base validation dispatch is a new code path independent of the `--validate` flag. Acceptable gap.

**New issue with Test 68:** See New Findings below.

---

### F4 (Major): deploy.sh reference/ edge cases -- RESOLVED

**What changed:** The deploy.sh change was rewritten from:

```bash
# Round 1 (broken)
mkdir -p "$dst/reference"
cp -r "$src/reference/"* "$dst/reference/"
```

To:

```bash
# Round 2 (fixed)
if [ -d "$src/reference" ]; then
    rm -rf "$dst/reference"
    cp -r "$src/reference" "$dst/reference"
fi
```

**Edge case resolution:**

| Edge Case | Round 1 Status | Round 2 Status |
|-----------|---------------|----------------|
| Glob expansion on empty dir | Broken (literal `*` passed to cp) | Fixed (no glob) |
| Hidden files not copied | Broken (`*` skips dotfiles) | Fixed (cp -r copies all) |
| Stale files on redeploy | Broken (no cleanup) | Fixed (rm -rf before copy) |
| Symlinks followed | Noted (minor) | Same (acceptable) |

The `rm -rf "$dst/reference"` before `cp -r` ensures clean state on redeployment. The `if [ -d "$src/reference" ]` guard prevents errors for the 19 skills without reference/ directories. The same change is applied to both `deploy_skill()` and `deploy_contrib_skill()`.

No remaining issues.

---

### Round 1 Minor Findings Status

| Finding | Status | Notes |
|---------|--------|-------|
| F5 (file count) | Resolved | Appendix B now says "9 files created, 9 files modified, 1 directory created" |
| F6 (KB invocation UX) | Resolved | Knowledge-Base Pattern section with invocation examples added |
| F7 (no source commit SHA) | Resolved | Deferred to implementation-time commit message |
| F8 (context budget) | Acknowledged | Risk table updated. Plan keeps enhancements targeted rather than wholesale copies. |
| F9 (backward compat) | Partially addressed | Acceptance Criteria items 8, 12, 13 cover regression. Strict-mode and self-scan smoke tests remain as recommendations. |

---

## New Findings

### NF1: Test 68 creates fixture in wrong directory [Minor]

Test 68 (deploy.sh reference/ copy) creates its test fixture in `$TEST_DIR/skills/test-ref-deploy/` (which resolves to `/tmp/sg-test/skills/test-ref-deploy/`):

```bash
mkdir -p "$TEST_DIR/skills/test-ref-deploy/reference"
```

But then runs:

```bash
cd '$SKILLS_DIR' && bash scripts/deploy.sh test-ref-deploy
```

`deploy.sh` resolves its own `SKILLS_DIR` to `$REPO_DIR/skills/`, which is the repository's `skills/` directory -- NOT `/tmp/sg-test/skills/`. The deploy will fail with "Skill 'test-ref-deploy' not found."

**Fix:** Follow the existing pattern used by Test 51 (line 520-525 of `test_skill_generator.sh`), which creates fixtures in `$SKILLS_DIR/skills/` and cleans up after:

```bash
mkdir -p "$SKILLS_DIR/skills/test-ref-deploy/reference"
cat > "$SKILLS_DIR/skills/test-ref-deploy/SKILL.md" << 'REFEOF'
...
REFEOF
echo "# Test reference file" > "$SKILLS_DIR/skills/test-ref-deploy/reference/test-ref.md"
run_test 68 "deploy.sh copies reference/ directory" \
    "cd '$SKILLS_DIR' && bash scripts/deploy.sh test-ref-deploy && test -f ~/.claude/skills/test-ref-deploy/reference/test-ref.md" \
    0
rm -rf "$SKILLS_DIR/skills/test-ref-deploy"
rm -rf ~/.claude/skills/test-ref-deploy
```

This is a mechanical fix that does not affect the plan's architecture or design decisions.

---

### NF2: Appendix A multi-line description flattening is a good addition [Info]

The revision added guidance for flattening YAML folded block scalars (`>` or `>-`) into single-line double-quoted strings. This proactively addresses a parser compatibility issue that would have caused silent failures during implementation (devkit's `parse_frontmatter()` is line-by-line and cannot handle multi-line YAML values). Well done.

---

## Summary

| Category | Count | IDs |
|----------|-------|-----|
| Round 1 Critical resolved | 1 | F1 |
| Round 1 Major resolved | 3 | F2, F3, F4 |
| Round 1 Minor resolved | 4 | F5, F6, F7, F9 |
| Round 1 Minor acknowledged | 1 | F8 |
| New Minor findings | 1 | NF1 |
| New Info findings | 1 | NF2 |

The plan's architecture (knowledge-base archetype, frontmatter adaptation, additive skill enhancements, backward-compatible infrastructure changes) remains sound. All Critical and Major issues from Round 1 are resolved. The single new finding (NF1) is a test fixture path bug with an obvious fix that does not affect the plan's design or execution strategy.

**The plan is ready for implementation** with the NF1 fix applied during Test 68 creation.
