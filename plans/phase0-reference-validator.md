# Plan: Phase 0 -- Reference Archetype Validator Support + Rollback Mechanism

## Revision Log

| Rev | Date | Author | Changes |
|-----|------|--------|---------|
| 1.0 | 2026-03-05 | Senior Architect | Initial plan |
| 1.1 | 2026-03-05 | Senior Architect | Address red team, librarian, and feasibility review findings: (1) add path traversal sanitization to `undeploy_skill()`, (2) fix test count to 33 everywhere, (3) make `model` optional for Reference skills, (4) document `rm -rf` permission prompt as expected behavior |

**Date:** 2026-03-05
**Author:** Senior Architect
**Target Repo:** `~/projects/claude-devkit`
**Affects:** `generators/validate_skill.py`, `configs/skill-patterns.json`, `scripts/deploy.sh`, `generators/test_skill_generator.sh`
**Parent Plan:** `plans/superpowers-adoption-roadmap.md` (Phase 0)

---

## Context

The approved superpowers adoption roadmap introduces six new skills that use a **Reference** archetype -- a fourth archetype alongside the existing Coordinator, Pipeline, and Scan patterns. Reference skills are behavioral discipline documents (Iron Laws, gates, principles) rather than executable workflows. They lack numbered steps, tool declarations, verdict gates, and inputs sections.

The current validator (`validate_skill.py`) treats these as hard errors, meaning every Reference skill would fail validation. Phase 0 unblocks all subsequent phases by:

1. Teaching the validator to recognize `type: reference` in frontmatter and apply appropriate checks
2. Adding the `reference` archetype definition to `configs/skill-patterns.json`
3. Adding `--undeploy` to `deploy.sh` for rollback capability

This is a prerequisite for Phases 1-6. No Reference skill can be created or validated until this work lands.

## Context Alignment

- **CLAUDE.md patterns followed:** v2.0.0 skill patterns, conventional commits, validate-before-commit workflow
- **Existing archetypes:** Coordinator, Pipeline, Scan (this adds Reference as fourth)
- **Validator structure:** `validate_skill.py` runs five validation functions in sequence: `validate_frontmatter`, `validate_workflow_header`, `validate_inputs_section`, `validate_steps`, `validate_patterns`. Reference archetype needs conditional gating on these calls.
- **Test suite:** 26 existing tests in `generators/test_skill_generator.sh`. New tests will be appended before the cleanup test (currently Test 26).
- **Deploy script:** Bash with `set -euo pipefail`, case-based argument parsing. `--undeploy` adds a new case branch.
- **Recent migration pattern:** The audit/sync MCP removal plans established the pattern of modifying existing scripts with backward-compatible additions and extending the test suite.
- **Tool permissions:** CLAUDE.md documents that `rm -rf` is not in the global allowlist and requires interactive prompting. The `--undeploy` feature uses `rm -rf` and will trigger this prompt -- this is documented as expected behavior.

---

## Goals

1. `validate_skill.py` accepts `type: reference` in YAML frontmatter and exits 0 for valid Reference skills
2. `validate_skill.py` still rejects invalid Reference skills (missing frontmatter fields, empty body, no core principle heading)
3. All existing Pipeline/Coordinator/Scan skills continue to validate without changes (zero regressions)
4. `configs/skill-patterns.json` contains a `reference` archetype definition consumed by the validator
5. `deploy.sh --undeploy <name>` removes a deployed skill; `deploy.sh --undeploy --contrib <name>` removes a contrib skill
6. Test suite extended with Reference archetype test cases

## Non-Goals

- Creating any actual Reference skills (that is Phases 1-6)
- Modifying CLAUDE.md skill registry (done per-phase when skills are created)
- Modifying the skill generator (`generate_skill.py`) to support a Reference archetype template
- Adding `type` field support for existing archetypes (Coordinator/Pipeline/Scan remain inferred)

## Assumptions

1. The `type` frontmatter field is optional. Skills without `type` continue to be validated as today (inferred archetype).
2. Only `type: reference` triggers the new code path. Unknown type values are treated as warnings.
3. The `attribution` field is required only for Reference skills (not for Pipeline/Coordinator/Scan).
4. The validator's simple YAML parser (line-by-line `key: value`) is sufficient for the new fields.
5. `--undeploy` does not need to modify CLAUDE.md -- that is a manual step documented in the rollback procedure.

---

## Proposed Design

### 1. Validator Changes (`generators/validate_skill.py`)

**Architecture:** Add a Reference archetype detection branch early in `main()`. When `type: reference` is detected in frontmatter, route to a dedicated validation path that skips inapplicable checks and applies Reference-specific checks.

**Changes to `main()` (line 330-396):**

After parsing frontmatter (line 370), add archetype detection:

```python
# Detect archetype from frontmatter
skill_type = frontmatter.get("type", None)
is_reference = (skill_type == "reference")
```

Then gate the existing validation calls:

```python
# Run all validations
issues = []
issues.extend(validate_frontmatter(frontmatter, patterns_config, is_reference=is_reference))

if is_reference:
    # Reference-specific validation
    # NOTE: Do not call validate_workflow_header, validate_inputs_section,
    # validate_steps, or validate_patterns for Reference skills. These check
    # for numbered steps, tool declarations, verdict gates, and other
    # executable-workflow patterns that Reference skills intentionally lack.
    issues.extend(validate_reference_skill(frontmatter, body, patterns_config))
else:
    # Standard skill validation (existing behavior, unchanged)
    if frontmatter.get("name"):
        issues.extend(validate_workflow_header(content, frontmatter["name"]))
    issues.extend(validate_inputs_section(content))
    issues.extend(validate_steps(content, patterns_config))
    issues.extend(validate_patterns(content, patterns_config))
```

**New function: `validate_reference_skill(frontmatter, body, patterns_config)`**

This function performs three checks:

1. **Required frontmatter fields:** `name`, `description`, `version`, `type`, `attribution` must all be present and non-empty. (Note: `name` and `description` are already checked by `validate_frontmatter`; this adds `version`, `type`, `attribution`. The `model` field is intentionally not required -- see Design Decision below.)

2. **Non-empty body:** The body content (everything after the closing `---`) must contain at least one non-whitespace character.

3. **Core principle heading:** At least one markdown heading (any level: `#`, `##`, `###`) must contain one of the words: "Law", "Principle", "Rule", or "Gate". This confirms the skill documents a behavioral constraint. The patterns are loaded from `configs/skill-patterns.json` under `archetypes.reference.core_principle_patterns`.

**Design Decision: `model` field is optional for Reference skills.**

Reference skills are non-executable behavioral documents (Iron Laws, principles, gates). They are never dispatched to a model for execution. Requiring a `model` field would be semantically meaningless and mislead readers into thinking model selection matters for these documents. Therefore, `validate_frontmatter()` skips the `model` requirement when `is_reference=True`. The `archetypes.reference.required_frontmatter` config reflects this by omitting `model`. If a Reference skill includes a `model` field, it is accepted but not required.

**Modified function: `validate_frontmatter(frontmatter, patterns_config, is_reference=False)`**

Add the `is_reference` parameter (default `False` for backward compatibility). Gate the `model` requirement:

```python
def validate_frontmatter(frontmatter, patterns_config, is_reference=False):
    issues = []
    # ... existing name/description checks ...

    if not is_reference:
        # model is required for executable skills only
        if "model" not in frontmatter or not frontmatter["model"]:
            issues.append({
                "severity": "error",
                "pattern": "Model Selection",
                "message": "Missing required frontmatter field: model"
            })
        # ... existing model value validation ...

    if "type" in frontmatter:
        valid_types = ["pipeline", "coordinator", "scan", "reference"]
        if frontmatter["type"] not in valid_types:
            issues.append({
                "severity": "warning",
                "pattern": "Archetype Type",
                "message": f"Unknown type '{frontmatter['type']}'. Valid values: {', '.join(valid_types)}"
            })

    return issues
```

**Modified function: `load_patterns()`**

Load and return the `archetypes` section from `skill-patterns.json` (currently only `patterns` and `structural_requirements` are used). The function already returns the full JSON dict, so no change is needed to the function itself -- the new `validate_reference_skill` function accesses `patterns_config.get("archetypes", {}).get("reference", {})`.

### 2. Pattern Config Changes (`configs/skill-patterns.json`)

Add a top-level `archetypes` key:

```json
{
  "patterns": [ ... existing ... ],
  "structural_requirements": [ ... existing ... ],
  "archetypes": {
    "reference": {
      "description": "Behavioral discipline documents (Iron Laws, principles, gates). Not executable workflows.",
      "required_frontmatter": ["name", "description", "version", "type", "attribution"],
      "required_sections": ["core_principle"],
      "core_principle_patterns": ["Iron Law", "Core Principle", "Fundamental Rule", "The Gate"],
      "requires_numbered_steps": false,
      "requires_tool_declarations": false,
      "requires_verdict_gates": false,
      "requires_artifacts": false,
      "requires_inputs_section": false,
      "requires_workflow_header": false,
      "requires_model": false
    }
  }
}
```

Note: `requires_model: false` explicitly documents that Reference skills do not require the `model` frontmatter field. The `required_frontmatter` list omits `model` accordingly.

### 3. Deploy Script Changes (`scripts/deploy.sh`)

Add `--undeploy` case to the argument parser (before the catch-all `*)`):

```bash
--undeploy)
    if [ $# -lt 2 ]; then
        echo "ERROR: --undeploy requires a skill name" >&2
        echo "Usage: deploy.sh --undeploy <skill-name>" >&2
        echo "       deploy.sh --undeploy --contrib <skill-name>" >&2
        exit 1
    fi
    if [[ "$2" == "--contrib" ]]; then
        if [ $# -lt 3 ]; then
            echo "ERROR: --undeploy --contrib requires a skill name" >&2
            exit 1
        fi
        undeploy_skill "$3"
    else
        undeploy_skill "$2"
    fi
    ;;
```

Add `undeploy_skill()` function with input sanitization:

```bash
undeploy_skill() {
    local skill="$1"

    # Input sanitization: reject path traversal and flag-like names
    if [[ "$skill" == */* ]] || [[ "$skill" == *..* ]] || [[ "$skill" == -* ]]; then
        echo "ERROR: Invalid skill name: '$skill' (must not contain '/', '..', or start with '-')" >&2
        return 1
    fi

    local target="$DEPLOY_DIR/$skill"

    if [ ! -d "$target" ]; then
        echo "WARN: Skill '$skill' not found at $target (already undeployed?)" >&2
        return 0
    fi

    # NOTE: rm -rf is not in the Claude Code global allowlist (~/.claude/settings.json)
    # and will trigger an interactive permission prompt. This is expected behavior.
    rm -rf "$target"
    echo "Undeployed: $skill (removed $target)"
}
```

Update `show_help()` to document the new flag, including a note about the permission prompt:

```
  --undeploy <name>           Remove ~/.claude/skills/<name>/ (triggers permission prompt)
  --undeploy --contrib <name> Remove ~/.claude/skills/<name>/ (same target, contrib context)
```

### 4. Test Suite Changes (`generators/test_skill_generator.sh`)

Add 6 new tests before the cleanup test (currently Test 26). Renumber cleanup to Test 33. New test count: 33 tests.

| Test # | Name | Description | Expected Exit |
|--------|------|-------------|---------------|
| 27 | Validate Reference skill (valid) | Create fixture with valid Reference frontmatter + Iron Law heading, validate | 0 |
| 28 | Validate Reference skill (missing attribution) | Reference skill without `attribution` field | non-zero |
| 29 | Validate Reference skill (empty body) | Reference skill with frontmatter only, no body content | non-zero |
| 30 | Validate Reference skill (no principle heading) | Reference skill with valid frontmatter but no Law/Principle/Rule/Gate heading | non-zero |
| 31 | Undeploy skill | Deploy a test skill, undeploy it, verify directory removed | 0 |
| 32 | Undeploy nonexistent skill (idempotent) | Undeploy a skill that does not exist, verify no error | 0 |

Note: Test 27 (valid Reference skill) fixture must omit the `model` field to verify that Reference skills validate without it. A second variant within Test 27 (or a separate assertion) should confirm that a Reference skill with `model` also validates successfully.

---

## Interfaces / Schema Changes

### YAML Frontmatter Schema (extended)

**New optional field for all skills:**
```yaml
type: reference|pipeline|coordinator|scan  # Optional. Default: inferred from structure
```

**New required field for Reference skills only:**
```yaml
attribution: "Adapted from superpowers plugin (v4.3.1) by Jesse Vincent, MIT License"
```

**`model` field behavior by archetype:**
- Pipeline, Coordinator, Scan: `model` is required (existing behavior, unchanged)
- Reference: `model` is optional (Reference skills are not executed against a model)

### CLI Interface Changes

**`deploy.sh` new flags:**
```
--undeploy <name>           Remove ~/.claude/skills/<name>/ (triggers permission prompt)
--undeploy --contrib <name> Remove ~/.claude/skills/<name>/ (contrib context, same target)
```

**Input validation:** Skill names passed to `--undeploy` are rejected if they contain `/`, `..`, or start with `-`. This prevents path traversal attacks.

### `skill-patterns.json` Schema Addition

New top-level key `archetypes` alongside existing `patterns` and `structural_requirements`. See Proposed Design section 2 for full schema.

---

## Data Migration

None. This is purely additive. No existing files are renamed, moved, or reformatted. All existing skills continue to work without modification.

---

## Rollout Plan

1. Implement all changes in a single branch
2. Run the extended test suite (33 tests, must all pass)
3. Run existing skill validation against all 5 production skills (dream, ship, audit, sync, test-idempotent) to verify zero regressions
4. Commit with conventional commit: `feat(generators): add Reference archetype validator support and --undeploy flag`
5. Deploy skills: `./scripts/deploy.sh` (no new skills to deploy yet -- this just verifies deploy.sh still works)
6. Merge to main
7. To revert these changes if needed: `git revert <commit-sha>` and redeploy

This phase has no runtime impact until Phase 1+ creates actual Reference skills.

---

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Reference validation path introduces regression in existing skill validation | Low | High | Existing skills never set `type: reference`, so they always take the else branch. All 5 production skills validated in test plan. |
| `validate_frontmatter()` change introduces side effects | Low | Medium | The changes are: (1) add `is_reference` parameter with default `False` (backward compatible), (2) add warning for unknown `type` values. Existing skills have no `type` field and pass `is_reference=False`, so the new code does not alter their validation path. |
| `--undeploy` path traversal attack | Low | High | Input sanitization rejects skill names containing `/`, `..`, or starting with `-`. Guard added directly in `undeploy_skill()` before any path construction. |
| `--undeploy` triggers unexpected permission prompt | Low | Low | Documented in `show_help()` output and plan. `rm -rf` is not in the Claude Code global allowlist per CLAUDE.md. Users will see a prompt; this is expected and by design. |
| `core_principle_patterns` list is too narrow, rejecting valid Reference skills | Low | Low | The pattern list is loaded from config, not hardcoded. Adding new patterns is a config-only change. The four initial patterns cover all six planned superpowers skills. |
| Simple YAML parser cannot handle multi-line `attribution` values | Low | Low | Attribution is a single-line string. The parser splits on first `:` and strips quotes. If multi-line is needed in the future, upgrade to a proper YAML parser. |

---

## Test Plan

### Automated Tests

Run from repo root:

```bash
cd ~/projects/claude-devkit

# 1. Run extended test suite (33 tests, all must pass)
bash generators/test_skill_generator.sh

# 2. Validate all production skills (regression check)
python generators/validate_skill.py skills/dream/SKILL.md
python generators/validate_skill.py skills/ship/SKILL.md
python generators/validate_skill.py skills/audit/SKILL.md
python generators/validate_skill.py skills/sync/SKILL.md
python generators/validate_skill.py skills/test-idempotent/SKILL.md

# 3. Manual Reference fixture test -- without model field (standalone, outside test suite)
mkdir -p /tmp/test-reference-skill
cat > /tmp/test-reference-skill/SKILL.md << 'FIXTURE'
---
name: test-reference
description: Test fixture for Reference archetype validation
version: 1.0.0
type: reference
attribution: "Test fixture"
---

# Test Reference Skill

## The Iron Law

Test principle content.

## When to Use

Test trigger conditions.
FIXTURE

python generators/validate_skill.py /tmp/test-reference-skill/SKILL.md
echo "Exit code: $?"  # Must be 0

# 4. JSON output for Reference skill
python generators/validate_skill.py /tmp/test-reference-skill/SKILL.md --json | python -m json.tool

# 5. Test undeploy flow
./scripts/deploy.sh --help  # Verify --undeploy is documented
mkdir -p ~/.claude/skills/test-reference
cp /tmp/test-reference-skill/SKILL.md ~/.claude/skills/test-reference/SKILL.md
./scripts/deploy.sh --undeploy test-reference
test ! -d ~/.claude/skills/test-reference && echo "PASS: undeployed" || echo "FAIL: still exists"

# 6. Test undeploy path traversal rejection
./scripts/deploy.sh --undeploy "../../../tmp" 2>&1 | grep -q "ERROR: Invalid skill name" && echo "PASS: path traversal rejected" || echo "FAIL: path traversal not caught"
./scripts/deploy.sh --undeploy "--flag-name" 2>&1 | grep -q "ERROR: Invalid skill name" && echo "PASS: flag-like name rejected" || echo "FAIL: flag-like name not caught"

# 7. Cleanup
rm -rf /tmp/test-reference-skill
```

### Test Command (single line for CI)

```bash
cd ~/projects/claude-devkit && bash generators/test_skill_generator.sh && python generators/validate_skill.py skills/dream/SKILL.md && python generators/validate_skill.py skills/ship/SKILL.md && python generators/validate_skill.py skills/audit/SKILL.md && python generators/validate_skill.py skills/sync/SKILL.md && python generators/validate_skill.py skills/test-idempotent/SKILL.md
```

---

## Acceptance Criteria

- [ ] `validate_skill.py` accepts `type: reference` in frontmatter and skips inapplicable checks (numbered steps, verdict gates, inputs section, workflow header, minimum steps)
- [ ] `validate_skill.py` exits 0 for a valid Reference skill without a `model` field
- [ ] `validate_skill.py` exits 0 for a valid Reference skill with a `model` field (optional but accepted)
- [ ] `validate_skill.py` exits non-zero for Reference skills missing required frontmatter fields (`attribution`, `version`, `type`)
- [ ] `validate_skill.py` exits non-zero for Reference skills with empty body
- [ ] `validate_skill.py` exits non-zero for Reference skills without a core principle heading (Law/Principle/Rule/Gate)
- [ ] Existing Pipeline/Coordinator/Scan skills (dream, ship, audit, sync, test-idempotent) continue to validate without changes
- [ ] `configs/skill-patterns.json` contains `archetypes.reference` definition with all required fields including `requires_model: false`
- [ ] `deploy.sh --undeploy <name>` removes the skill directory from `~/.claude/skills/`
- [ ] `deploy.sh --undeploy` rejects skill names containing `/`, `..`, or starting with `-`
- [ ] `deploy.sh --undeploy --contrib <name>` removes contrib skill directory
- [ ] `deploy.sh --undeploy` on a nonexistent skill exits cleanly (idempotent)
- [ ] `deploy.sh --help` documents the `--undeploy` flag and notes the permission prompt
- [ ] Test suite extended to 33 tests and all pass

---

## Task Breakdown

### Phase 1: Update `configs/skill-patterns.json`

1. [ ] Read `configs/skill-patterns.json` (already done in analysis)
2. [ ] Add `archetypes.reference` object with all fields specified in Proposed Design section 2, including `requires_model: false`
3. [ ] Validate JSON syntax: `python -m json.tool configs/skill-patterns.json`
4. [ ] Commit: do not commit yet (batch with other changes)

**File:** `/Users/imurphy/projects/claude-devkit/configs/skill-patterns.json`

### Phase 2: Update `generators/validate_skill.py`

1. [ ] Add `validate_reference_skill()` function (after `validate_inputs_section`, ~line 258)
   - Check required frontmatter fields: `version`, `type`, `attribution` (name/description already checked; model intentionally not required)
   - Check body is non-empty (strip whitespace, check length > 0)
   - Load `core_principle_patterns` from `patterns_config["archetypes"]["reference"]`
   - Search all headings (`^#{1,6} .+`) for any pattern match (case-insensitive substring)
   - Return list of issues

2. [ ] Modify `validate_frontmatter()` function (~line 78)
   - Add `is_reference=False` parameter (backward compatible default)
   - Gate the `model` requirement: skip `model` check when `is_reference=True`
   - After model validation block (line 108), add type validation warning for unknown values

3. [ ] Modify `main()` function (~line 370)
   - After `frontmatter, body = parse_frontmatter(content)`, detect `is_reference`
   - Pass `is_reference` to `validate_frontmatter()` call
   - Branch: if `is_reference`, call `validate_reference_skill(frontmatter, body, patterns_config)` instead of the four standard checks
   - Add comment explaining why `validate_patterns` must not run for Reference skills

4. [ ] Test: `python generators/validate_skill.py skills/dream/SKILL.md` (must still pass)
5. [ ] Test with Reference fixture without `model` field (see Test Plan section 3)

**File:** `/Users/imurphy/projects/claude-devkit/generators/validate_skill.py`

### Phase 3: Update `scripts/deploy.sh`

1. [ ] Add `undeploy_skill()` function (after `deploy_contrib_skill`, ~line 47)
   - Validate skill name: reject if contains `/`, `..`, or starts with `-`
   - Constructs target path: `$DEPLOY_DIR/$skill`
   - If directory does not exist, print warning and return 0
   - If directory exists, `rm -rf "$target"` and print confirmation

2. [ ] Add `--undeploy)` case to argument parser (before `-*)` catch-all, ~line 142)
   - Parse `$2` for `--contrib` (shifts to `$3` for skill name) or direct skill name
   - Validate argument count

3. [ ] Update `show_help()` function
   - Add `--undeploy <name>` and `--undeploy --contrib <name>` to options list and examples
   - Note that `--undeploy` triggers a permission prompt (rm -rf not in allowlist)

4. [ ] Test: `./scripts/deploy.sh --help` (verify new flag documented)
5. [ ] Test: deploy then undeploy flow (see Test Plan section 5)
6. [ ] Test: path traversal rejection (see Test Plan section 6)

**File:** `/Users/imurphy/projects/claude-devkit/scripts/deploy.sh`

### Phase 4: Extend Test Suite (`generators/test_skill_generator.sh`)

1. [ ] Add Test 27: Valid Reference skill validation (without `model` field)
   - Create fixture at `$TEST_DIR/test-ref-valid.md` with valid frontmatter (no `model`) + Iron Law heading
   - Run validator, expect exit 0

2. [ ] Add Test 28: Reference skill missing attribution
   - Create fixture without `attribution` field
   - Run validator, expect non-zero

3. [ ] Add Test 29: Reference skill with empty body
   - Create fixture with frontmatter only (body is just whitespace)
   - Run validator, expect non-zero

4. [ ] Add Test 30: Reference skill without principle heading
   - Create fixture with valid frontmatter but headings like "## Overview", "## Details" (none match Law/Principle/Rule/Gate)
   - Run validator, expect non-zero

5. [ ] Add Test 31: Undeploy skill
   - Create a test skill directory at `$DEPLOY_DIR/test-undeploy-skill`
   - Run `deploy.sh --undeploy test-undeploy-skill`
   - Verify directory is removed

6. [ ] Add Test 32: Undeploy nonexistent skill (idempotent)
   - Run `deploy.sh --undeploy nonexistent-skill-xyz`
   - Expect exit 0 (warning printed, no error)

7. [ ] Renumber existing Test 26 (Cleanup) to Test 33
8. [ ] Update header comment from "26 test cases" to "33 test cases"

**File:** `/Users/imurphy/projects/claude-devkit/generators/test_skill_generator.sh`

### Phase 5: Validation and Commit

1. [ ] Run full test suite: `bash generators/test_skill_generator.sh` (33 tests, all must pass)
2. [ ] Validate all 5 production skills (regression check):
   ```bash
   for skill in dream ship audit sync test-idempotent; do
     python generators/validate_skill.py skills/$skill/SKILL.md || echo "REGRESSION: $skill"
   done
   ```
3. [ ] Run manual Reference fixture test (Test Plan section 3)
4. [ ] Verify `deploy.sh --help` output includes `--undeploy`
5. [ ] Test path traversal rejection (Test Plan section 6)
6. [ ] Commit:
   ```
   feat(generators): add Reference archetype validator support and --undeploy flag

   - validate_skill.py recognizes type: reference in frontmatter
   - Skips numbered steps, verdict gates, inputs, workflow header for Reference skills
   - Adds Reference-specific checks: attribution, non-empty body, core principle heading
   - model field is optional for Reference skills (non-executable documents)
   - skill-patterns.json adds archetypes.reference definition
   - deploy.sh --undeploy removes deployed skills for rollback
   - undeploy_skill() rejects path traversal (/, ..) and flag-like (-) names
   - Test suite extended from 26 to 33 tests
   ```

---

## Verification

- [success] `validate_skill.py` exits 0 for valid Reference skill fixture (with and without `model`)
- [success] `validate_skill.py` exits 1 for invalid Reference skill fixtures (3 negative cases)
- [success] All 5 production skills validate without changes
- [success] `deploy.sh --undeploy` removes skill directory
- [success] `deploy.sh --undeploy` rejects path traversal attempts
- [success] `deploy.sh --undeploy` on nonexistent skill exits cleanly
- [success] Test suite runs 33 tests, all pass
- [success] `configs/skill-patterns.json` parses as valid JSON

---

## Next Steps

1. **Execute this plan** using `/ship plans/phase0-reference-validator.md`
2. After merge, proceed to **Phase 4** (receiving-code-review) as canary deployment per rollout plan
3. Then **Phase 2** (verification-before-completion), **Phase 1** (systematic-debugging), etc.

---

## Plan Metadata

- **Plan File:** `./plans/phase0-reference-validator.md`
- **Affected Components:** `generators/validate_skill.py`, `configs/skill-patterns.json`, `scripts/deploy.sh`, `generators/test_skill_generator.sh`
- **Validation:** `bash generators/test_skill_generator.sh && python generators/validate_skill.py skills/dream/SKILL.md`
- **Parent Plan:** `plans/superpowers-adoption-roadmap.md` (Phase 0)
- **Estimated Effort:** Small (4 files modified, ~150-170 lines added across all files)

## Status: APPROVED

<!-- Context Metadata
discovered_at: 2026-03-05T15:30:00Z
claude_md_exists: true
recent_plans_consulted: superpowers-adoption-roadmap.md, audit-remove-mcp-deps.md, sync-remove-mcp-deps.md
archived_plans_consulted: dream-remove-mcp-deps, ship-always-worktree
revision_1_reviews: phase0-reference-validator.redteam.md, phase0-reference-validator.review.md, phase0-reference-validator.feasibility.md
-->
