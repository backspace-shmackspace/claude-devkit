# Integrate 10 Curated Prodsec-Skills into Claude Devkit

**Type:** Skill Integration (new skills + existing skill enhancements)
**Complexity:** High
**Estimated Time:** 8-12 hours
**Plan Version:** 1.1.0
**Date:** 2026-07-15

---

## Goals

1. Copy 7 prodsec-skills as new knowledge-base reference skills into `skills/`
2. Enhance 4 existing devkit security skills with prodsec domain content
3. Extend the validator and deploy infrastructure to support the new `knowledge-base` archetype
4. Maintain full backward compatibility with all existing skills and workflows
5. All 20+ existing skills continue to pass validation after changes

## Non-Goals

- Redesigning devkit's workflow orchestration (/ship, /architect, /audit)
- Converting prodsec-skills into executable v2.0.0 workflows (they are reference knowledge, not workflows)
- Modifying prodsec-skills upstream (this is a one-directional integration)
- Adding new security gates to /ship (the existing 3 gates remain unchanged)
- Changing security maturity levels (L1/L2/L3)

## Assumptions

1. Prodsec skill content is stable -- this is a point-in-time copy, not a live sync. The source commit SHA from the prodsec-skills repository should be recorded at implementation time in the commit message for traceability.
2. The `knowledge-base` archetype is the correct classification for tool-agnostic reference materials
3. Existing skill consumers (humans invoking /secrets-scan, /secure-review, etc.) benefit from richer detection guidance without workflow changes
4. The `threat-model` skill coexists with `threat-model-gate` -- they serve different purposes (full methodology vs. planning gate)
5. `validate_skill.py` changes are additive (new archetype, no changes to existing validation paths)
6. `deploy.sh` changes are backward compatible (existing skills without `reference/` dirs are unaffected)

---

## Proposed Design

### Architecture Decision: Knowledge-Base Archetype

Prodsec skills are **tool-agnostic reference materials** -- they lack Claude-specific `model:`, `Tool:` declarations, `## Step N --` headers, `## Inputs`, and `# /skill-name Workflow` patterns. They intentionally do not match the executable skill format or the existing `reference` archetype (behavioral discipline documents with Iron Law/Core Principle headings).

**Decision:** Create a new `type: knowledge-base` archetype that validates prodsec-style content with minimal structural requirements.

| Property | `reference` (existing) | `knowledge-base` (new) |
|----------|----------------------|----------------------|
| Purpose | Behavioral discipline (Iron Laws, gates) | Domain knowledge and checklists |
| Frontmatter required | name, description, version, type, attribution | name, description, version, type, attribution |
| Core principle heading | Required (Iron Law / Core Principle / etc.) | Not required |
| Model field | Optional | Optional |
| Numbered steps | No | No |
| Tool declarations | No | No |
| Verdict gates | No | No |
| Inputs section | No | No |
| Workflow header | No | No |

**Why not reuse `reference`:** The `reference` archetype requires a heading matching "Iron Law", "Core Principle", "Fundamental Rule", or "The Gate". Prodsec skills don't have these headings and shouldn't be forced to. The semantic difference matters: `reference` skills define behavioral constraints; `knowledge-base` skills provide domain expertise.

### Frontmatter Adaptation Strategy

Each copied prodsec skill gets adapted frontmatter:

**Remove:** `category`, `subcategory` (devkit doesn't use these)
**Add:**
- `type: knowledge-base`
- `version: 1.0.0`
- `attribution: "Red Hat Product Security, prodsec-skills repository"`

**Keep:** `name`, `description` (unchanged from prodsec -- the descriptions are written as invocation conditions, which is exactly what devkit expects)

No `model:` field -- knowledge-base skills are loaded as context, not executed as workflows. The model that loads them is determined by the invoking skill or session.

### Deploy.sh Enhancement: Reference Directory Support

Current `deploy.sh` copies only `SKILL.md`. The prodsec `threat-model` skill has a `reference/` subdirectory with 2 files (`otm-schema.md`, `report-template.md`). Update `deploy_skill()` and `deploy_contrib_skill()` to also copy `reference/` when present.

### Integration Strategy for Enhanced Skills

For each of the 4 existing skills, the prodsec content is integrated as **additional detection guidance within the existing workflow structure** -- no new steps, no architectural changes. Version bumps reflect the content additions.

#### 1. secrets-scan v1.0.0 -> v1.1.0 (+ insecure-defaults)

**What changes:** Step 2 (pattern scanning) gains 6 new detection categories beyond the current 10 secret patterns. Step 3 (false positive filtering) gains guidance for distinguishing fail-open defaults from intentional test fixtures.

**New detection categories (from insecure-defaults SKILL.md):**
- Fallback secrets in env var handling (`os.environ.get(KEY, "default-secret")` patterns)
- Hardcoded default credentials (`admin/admin`, `password`, `changeme`)
- Fail-open security toggles (`AUTH_REQUIRED = os.environ.get(..., False)`)
- Weak cryptographic defaults (MD5, SHA1, DES, RC4, ECB in security contexts)
- Permissive access defaults (CORS `*`, chmod 0777, `0.0.0.0` binding)
- Debug/development flags left enabled (`DEBUG = True`, `FLASK_DEBUG=1`)

**Integration approach:** Add new grep patterns to the existing Step 2 pattern list. Add a new subsection `### Insecure Default Patterns` after the existing `### Secret Patterns` section. The existing verdict gate (Step 4) applies unchanged -- confirmed insecure defaults get the same BLOCKED treatment as confirmed secrets.

**What does NOT change:** Steps 0, 1, 3 (classification logic adapts naturally), 4, 5 structure. The skill remains a pipeline coordinator with the same tools.

#### 2. secure-review v1.1.0 -> v1.2.0 (+ differential-review)

**What changes:** Step 0 (scope determination) gains codebase size classification (SMALL/MEDIUM/LARGE) that controls analysis depth. Step 1's three parallel scans gain enhanced methodology from differential-review's phases.

**New capabilities (from differential-review SKILL.md):**
- **Codebase size classification** in Step 0: SMALL (<500 changed lines), MEDIUM (500-2000), LARGE (>2000). Controls depth of analysis.
- **Blast radius calculation** in Scan 1a: Count callers of modified functions using grep to assess impact scope. Report caller count per modified function.
- **Git blame regression detection** in Scan 1a: Use `git log --follow` on modified files to check if previously-fixed vulnerabilities are being reintroduced.
- **Per-file risk scoring** in synthesis (Step 2): Each file gets a risk score (0-10) based on: trust boundary proximity, input handling, auth logic, crypto usage, data sensitivity.
- **Common vulnerability pattern checklist** added to scan prompts: Double accounting bugs, TOCTOU races, integer overflow/type coercion, unchecked errors, DoS via unbounded operations.

**Integration approach:** Add codebase size detection (line count of diff) to Step 0. Enhance the three scan task prompts in Step 1 with additional detection instructions. Add per-file risk scoring to the synthesis step. The existing verdict thresholds and report format remain unchanged.

**What does NOT change:** Step structure (0-4), verdict gate logic, archive behavior, threat model coverage section (v1.1.0 addition), composability with /audit.

#### 3. dependency-audit v1.0.0 -> v1.1.0 (+ supply-chain-risk-auditor)

**What changes:** Step 5 (supply chain risk assessment) gains structured risk criteria and GitHub API queries via `gh` CLI for dependency health assessment.

**New capabilities (from supply-chain-risk-auditor SKILL.md):**
- **Single/anonymous maintainer detection:** Use `gh api repos/{owner}/{repo}` to check contributor count. Flag dependencies with <=2 maintainers.
- **Maintenance health indicators:** Check last commit date, open issue count, whether repo is archived. Flag repos with no commits in 12+ months.
- **Past CVE history:** Check if dependency has had previous CVEs (from scanner output in Step 2). Repeat offenders get elevated risk.
- **High-risk feature flagging:** Flag dependencies that use FFI/native code, deserialization, code execution (`eval`), or network listeners.
- **Alternative package suggestions:** When a high-risk dependency is found, suggest well-maintained alternatives if known.

**Integration approach:** Expand the existing Step 5 instructions with the structured risk criteria. Add `gh` CLI usage for GitHub metadata queries (graceful degradation if `gh` is not available or not authenticated). The risk assessment becomes a structured table in the report rather than free-form text.

**What does NOT change:** Steps 0-4, 6-7 structure. Scanner invocation (Step 2) is unchanged. Verdict gate logic is unchanged. License analysis (Step 4) is unchanged.

#### 4. threat-model-gate v1.0.0 -> v1.1.0 (enhanced with threat-model reference)

**What changes:** The existing STRIDE Quick Reference table and Security Requirements Template are enhanced with content from the prodsec `threat-model` skill. The skill gains a pointer to the new standalone `threat-model` knowledge-base skill for full methodology.

**New content (from threat-model SKILL.md):**
- **DREAD scoring reference:** Add DREAD scoring dimensions and severity bands alongside the existing STRIDE reference
- **Structured threat record format:** Replace the simple checklist with the structured per-threat format (STRIDE category, DREAD scores, attack scenario, mitigations)
- **Cross-reference to /threat-model:** Add explicit pointer: "For full threat modeling methodology with STRIDE+DREAD+OTM output, use the `threat-model` knowledge-base skill"
- **Expanded anti-patterns:** Add prodsec patterns for incomplete trust boundary analysis, missing data flow mapping, skipped DREAD calibration

**Integration approach:** The skill remains a `type: reference` behavioral discipline document. The STRIDE Quick Reference table gains DREAD columns. The Security Requirements Template gains structured threat record format. A new `## Full Threat Modeling` section points to the standalone skill.

**What does NOT change:** The skill's role as a planning gate. Its integration with /architect (Stage 2 security detection) and /ship (Step 1 plan validation). The core behavioral discipline (threat model before implementation).

---

## Interfaces / Schema Changes

### skill-patterns.json

Add `knowledge-base` archetype definition alongside existing `reference`:

```json
{
  "archetypes": {
    "reference": { ... },
    "knowledge-base": {
      "description": "Domain-specific knowledge, checklists, and reference materials. Tool-agnostic content imported from external skill repositories.",
      "required_frontmatter": ["name", "description", "version", "type", "attribution"],
      "requires_numbered_steps": false,
      "requires_tool_declarations": false,
      "requires_verdict_gates": false,
      "requires_artifacts": false,
      "requires_inputs_section": false,
      "requires_workflow_header": false,
      "requires_model": false,
      "requires_core_principle_heading": false
    }
  }
}
```

### validate_skill.py

Add `knowledge-base` to the `valid_types` list. Add a `validate_knowledge_base_skill()` function parallel to `validate_reference_skill()`. The knowledge-base validation checks:
1. Required frontmatter fields (name, description, version, type, attribution)
2. Non-empty body
3. No core principle heading requirement (unlike reference)

Update the `validate_frontmatter()` call to pass `is_reference=(is_reference or is_knowledge_base)` so that knowledge-base skills are not required to have a `model:` field. Without this fix, all 7 knowledge-base skills would fail validation because `validate_frontmatter()` requires `model:` when `is_reference` is `False`.

Also update the `valid_models` list to include `claude-sonnet-4-6` (stale allowlist fix -- existing skills already use this model).

### deploy.sh

Update `deploy_skill()` and `deploy_contrib_skill()` to copy `reference/` subdirectories. Remove stale `reference/` on redeploy before copying (ensures deleted source files do not persist at the destination):

```bash
# After copying SKILL.md:
if [ -d "$src/reference" ]; then
    rm -rf "$dst/reference"
    cp -r "$src/reference" "$dst/reference"
fi
```

### CLAUDE.md Skill Registry

Add 7 new rows to the Core Skills table for knowledge-base skills. Update 4 existing rows with new versions.

---

## Data Migration

None. This is purely additive -- new skill directories and content additions to existing skills. No data formats, audit logs, or configurations change.

---

## Rollout Plan

### Phase 1: Infrastructure (Shared Dependencies)
1. Update `configs/skill-patterns.json` with knowledge-base archetype
2. Update `generators/validate_skill.py` with knowledge-base support + model allowlist fix
3. Update `scripts/deploy.sh` with reference/ directory copying
4. Verify: all 13 existing core skills + 3 contrib skills still pass validation

### Phase 2: New Skills (Work Group 1)
5. Create 7 new skill directories with adapted frontmatter
6. Copy prodsec SKILL.md content with frontmatter adaptation
7. Copy `threat-model/reference/` directory (2 files)
8. Verify: all 7 new skills pass `validate_skill.py`

### Phase 3: Enhanced Skills (Work Group 2)
9. Update secrets-scan v1.0.0 -> v1.1.0 (+ insecure-defaults content)
10. Update secure-review v1.1.0 -> v1.2.0 (+ differential-review content)
11. Update dependency-audit v1.0.0 -> v1.1.0 (+ supply-chain-risk-auditor content)
12. Update threat-model-gate v1.0.0 -> v1.1.0 (+ threat-model references)
13. Verify: all 4 enhanced skills still pass `validate_skill.py`

### Phase 4: Tests and Documentation (Work Group 3)
14. Add validation tests for all 7 new skills to `test_skill_generator.sh`
15. Add knowledge-base archetype positive/negative tests
16. Update CLAUDE.md skill registry table
17. Run full test suite: `bash generators/test_skill_generator.sh`
18. Run integration tests: `bash scripts/test-integration.sh`

### Phase 5: Deploy and Verify
19. Deploy all skills: `./scripts/deploy.sh`
20. Verify deployment: `ls ~/.claude/skills/` shows all 20 core skills
21. Verify threat-model reference files: `ls ~/.claude/skills/threat-model/reference/`

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Prodsec skill content too large for context window | Low | Medium | Skills are loaded on-demand, not all at once. Largest skill (differential-review, 1761 lines) is integrated as methodology enhancements, not copied wholesale. |
| Validator changes break existing skill validation | Low | High | Knowledge-base is a new code path -- existing `reference` and standard validation paths are untouched. Run all 16 existing skills through validator before and after. |
| deploy.sh reference/ copy breaks on skills without reference/ | Low | High | Guard with `if [ -d "$src/reference" ]`. Only threat-model has a reference/ dir. |
| Enhanced skills become too long for effective use | Medium | Medium | Keep enhancements targeted: add detection patterns and methodology, don't duplicate entire prodsec skill content. Prodsec skills remain available as standalone references. |
| Frontmatter adaptation misses prodsec-specific fields | Low | Low | Only 2 fields to remove (category, subcategory) and 3 to add (type, version, attribution). The adaptation is mechanical and verified by validator. |
| `gh` CLI not available for dependency-audit enhancements | Medium | Low | All `gh` usage is wrapped in availability checks with graceful degradation. Step 5 works without `gh` -- it just skips GitHub metadata queries. |
| test_skill_generator.sh test numbering collisions | Low | Low | Existing tests end at 57. New tests start at 58. Verify no gaps or collisions. |

---

## Test Plan

### Automated Tests

**Command to run all tests:**
```bash
cd /Users/imurphy/projects/claude-devkit
bash generators/test_skill_generator.sh && bash scripts/test-integration.sh
```

**New tests in `test_skill_generator.sh` (12 tests, numbers 58-69):**

| Test # | Description | Command | Expected |
|--------|-------------|---------|----------|
| 58 | Validate input-validation-injection skill | `validate_skill.py skills/input-validation-injection/SKILL.md` | Exit 0 |
| 59 | Validate client-side-security skill | `validate_skill.py skills/client-side-security/SKILL.md` | Exit 0 |
| 60 | Validate ai-code-review skill | `validate_skill.py skills/ai-code-review/SKILL.md` | Exit 0 |
| 61 | Validate semgrep skill | `validate_skill.py skills/semgrep/SKILL.md` | Exit 0 |
| 62 | Validate build-yaml-misconfiguration skill | `validate_skill.py skills/build-yaml-misconfiguration/SKILL.md` | Exit 0 |
| 63 | Validate container-hardening skill | `validate_skill.py skills/container-hardening/SKILL.md` | Exit 0 |
| 64 | Validate threat-model skill | `validate_skill.py skills/threat-model/SKILL.md` | Exit 0 |
| 65 | Knowledge-base archetype validates with minimal frontmatter | Create fixture, validate | Exit 0 |
| 66 | Knowledge-base rejects empty body | Create fixture with empty body, validate | Exit 1 |
| 67 | Knowledge-base rejects missing attribution | Create fixture without attribution field, validate | Exit 1 |
| 68 | deploy.sh copies reference/ directory | Create skill with reference/, deploy, verify copy | Exit 0 |
| 69 | secrets-scan grep patterns are valid syntax | Run grep -E pattern against /dev/null, check exit != 2 | Exit 0 |

**Existing tests that must continue passing (regression):**

| Test # | Skill | Notes |
|--------|-------|-------|
| 38 | secure-review | Modified to v1.2.0 |
| 39 | dependency-audit | Modified to v1.1.0 |
| 40 | secrets-scan | Modified to v1.1.0 |
| 41 | threat-model-gate | Modified to v1.1.0 |
| 42 | compliance-check | Unchanged |
| 57 | fix | Unchanged |
| All 1-37 | Core skill + generator tests | Unchanged |

### Manual Verification

1. **Deploy and list:** `./scripts/deploy.sh && ls ~/.claude/skills/` -- verify 20 skill directories
2. **Reference directory:** `ls ~/.claude/skills/threat-model/reference/` -- verify `otm-schema.md` and `report-template.md` present
3. **Validate-all:** `./scripts/validate-all.sh` -- all 20 core skills pass
4. **Deploy with validation:** `./scripts/deploy.sh --validate` -- all skills pass and deploy

---

## Acceptance Criteria

1. [ ] 7 new skill directories exist under `skills/` with adapted frontmatter
2. [ ] All 7 new skills pass `validate_skill.py` (exit 0)
3. [ ] `threat-model` skill includes `reference/` directory with `otm-schema.md` and `report-template.md`
4. [ ] `secrets-scan` v1.1.0 includes insecure-defaults detection patterns
5. [ ] `secure-review` v1.2.0 includes blast radius, codebase sizing, and regression detection
6. [ ] `dependency-audit` v1.1.0 includes supply chain risk criteria with `gh` CLI usage
7. [ ] `threat-model-gate` v1.1.0 includes DREAD reference and cross-reference to `threat-model` skill
8. [ ] All 13 pre-existing core skills still pass `validate_skill.py` (no regressions)
9. [ ] `deploy.sh` copies `reference/` directories when present
10. [ ] `validate_skill.py` recognizes `type: knowledge-base` and validates accordingly
11. [ ] `valid_models` list includes `claude-sonnet-4-6`
12. [ ] `test_skill_generator.sh` passes all tests (existing 57 + 12 new = 69 total)
13. [ ] `test-integration.sh` passes all 42 existing tests
14. [ ] CLAUDE.md skill registry reflects all new and modified skills
15. [ ] `./scripts/deploy.sh` successfully deploys all 20 core skills
16. [ ] `./scripts/deploy.sh --validate` succeeds for all skills

---

## Context Alignment

### CLAUDE.md Patterns Followed

| Pattern | How This Plan Follows It |
|---------|-------------------------|
| Three-tier structure | New skills go in `skills/` (Tier 1), infrastructure in `generators/` + `scripts/` (Tier 2) |
| Skills follow v2.0.0 patterns | New archetype (`knowledge-base`) extends v2.0.0 pattern system; enhanced skills retain all 10/11 patterns |
| Each skill is a directory with SKILL.md | All 7 new skills follow `skills/<name>/SKILL.md` convention |
| Validate before committing | Plan requires all skills pass `validate_skill.py` |
| Core vs Contrib | All 10 skills go in `skills/` (core) -- they're universal security knowledge, not user-specific |
| Version bumps on modification | secrets-scan 1.1.0, secure-review 1.2.0, dependency-audit 1.1.0, threat-model-gate 1.1.0 |
| Deploy via deploy.sh | deploy.sh enhanced to handle reference/ directories |
| Test coverage | 12 new tests added to test_skill_generator.sh |

### Prior Plans Referenced

| Plan | Relationship |
|------|-------------|
| `agentic-sdlc-security-skills.md` (Rev 3, 2026-03-25) | Established the 5 security skills being enhanced here. This plan extends that architecture with prodsec content. |
| `phase0-reference-validator.md` | Established the `reference` archetype and `validate_reference_skill()` function. This plan's `knowledge-base` archetype follows the same validation dispatch pattern. |

### Learnings Applied

| Learning | Application |
|----------|-------------|
| `project_threat_model_gap.md` | The new `threat-model` standalone skill with STRIDE+DREAD+OTM provides the structured methodology that was missing. The `threat-model-gate` enhancement includes a cross-reference to it. |
| `feedback_decisiveness.md` | Clear keep/replace recommendations for each skill (e.g., threat-model-gate is kept and enhanced, not replaced). |

---

## Task Breakdown

### Shared Dependencies

These files are needed by multiple work groups and must be committed to HEAD before worktrees are created.

1. **`configs/skill-patterns.json`** (modify)
   - Add `knowledge-base` archetype to the `archetypes` object
   - Fields: description, required_frontmatter, all `requires_*` set to false

2. **`generators/validate_skill.py`** (modify)
   - Add `"knowledge-base"` to `valid_types` list (line 121)
   - Add `"claude-sonnet-4-6"` to `valid_models` list (line 111)
   - Add `validate_knowledge_base_skill()` function:
     - Check required frontmatter: name, description, version, type, attribution
     - Check non-empty body
     - No core principle heading requirement
   - Update main validation dispatch: add `is_knowledge_base = (skill_type == "knowledge-base")` branch that calls `validate_knowledge_base_skill()` instead of standard or reference validation
   - Update the `validate_frontmatter()` call to pass `is_reference=(is_reference or is_knowledge_base)` so that knowledge-base skills are not required to have a `model:` field (same exemption as `reference` skills)

3. **`scripts/deploy.sh`** (modify)
   - In `deploy_skill()`: after `cp "$src/SKILL.md" "$dst/SKILL.md"`, add reference/ directory copy with stale cleanup:
     ```bash
     if [ -d "$src/reference" ]; then
         rm -rf "$dst/reference"
         cp -r "$src/reference" "$dst/reference"
     fi
     ```
   - Same change in `deploy_contrib_skill()`

### Work Group 1: New Prodsec Knowledge-Base Skills

7 new skill directories. Each gets a SKILL.md with adapted frontmatter wrapping the prodsec content body. All files are new creations with no overlap with other work groups.

1. **`skills/input-validation-injection/SKILL.md`** (create)
   - Source: `/Users/imurphy/projects/prodsec-skills/.claude/skills/input-validation-injection/SKILL.md`
   - Frontmatter adaptation: replace `category`/`subcategory` with `type: knowledge-base`, add `version: 1.0.0`, `attribution`
   - Body: copy unchanged from prodsec source
   - Size: ~100 lines

2. **`skills/client-side-security/SKILL.md`** (create)
   - Source: `/Users/imurphy/projects/prodsec-skills/.claude/skills/client-side-security/SKILL.md`
   - Same frontmatter adaptation pattern
   - Body: copy unchanged
   - Size: ~123 lines

3. **`skills/ai-code-review/SKILL.md`** (create)
   - Source: `/Users/imurphy/projects/prodsec-skills/module/skills/ai-code-review/SKILL.md`
   - Same frontmatter adaptation pattern
   - Body: copy unchanged
   - Size: ~231 lines

4. **`skills/semgrep/SKILL.md`** (create)
   - Source: `/Users/imurphy/projects/prodsec-skills/.claude/skills/semgrep/SKILL.md`
   - Same frontmatter adaptation pattern
   - Body: copy unchanged
   - Size: ~564 lines

5. **`skills/build-yaml-misconfiguration/SKILL.md`** (create)
   - Source: `/Users/imurphy/projects/prodsec-skills/.claude/skills/build-yaml-misconfiguration/SKILL.md`
   - Same frontmatter adaptation pattern
   - Body: copy unchanged
   - Size: ~403 lines

6. **`skills/container-hardening/SKILL.md`** (create)
   - Source: `/Users/imurphy/projects/prodsec-skills/.claude/skills/container-hardening/SKILL.md`
   - Same frontmatter adaptation pattern
   - Body: copy unchanged
   - Size: ~108 lines

7. **`skills/threat-model/SKILL.md`** (create) + **`skills/threat-model/reference/`** (create directory)
   - Source: `/Users/imurphy/projects/prodsec-skills/module/skills/threat-model/SKILL.md`
   - Same frontmatter adaptation pattern
   - Body: copy unchanged
   - Size: ~1315 lines
   - Also copy `reference/otm-schema.md` and `reference/report-template.md` from prodsec source
   - Reference files: copy unchanged (they have their own internal YAML frontmatter which is prodsec-convention, not validated by devkit)

### Work Group 2: Existing Skill Enhancements

4 existing SKILL.md files modified with prodsec content integration. No overlap with Work Group 1 or 3 files.

1. **`skills/secrets-scan/SKILL.md`** (modify -- v1.0.0 -> v1.1.0)

   Changes:
   - Update frontmatter `version: 1.1.0`
   - In `## Step 2`, after the existing 10 secret grep patterns, add a new subsection:

   ```markdown
   ### Insecure Default Patterns

   In addition to secret patterns above, scan for fail-open insecure defaults
   that allow the application to run with weak security in production.

   **Patterns to detect:**

   11. **Fallback secrets in env var handling:**
       ```
       grep -rnE "(environ\.get|getenv|ENV\[|process\.env)\s*\(?\s*['\"][^'\"]+['\"]\s*,\s*['\"][^'\"]{4,}['\"]" --include="*.py" --include="*.rb" --include="*.js" --include="*.ts"
       ```
       Matches: `os.environ.get("SECRET_KEY", "my-default-secret")`
       Excludes: Empty strings, `None`, short placeholder values

   12. **Hardcoded default credentials:**
       ```
       grep -rnEi "(admin[:/]admin|password\s*[:=]\s*['\"]?(password|changeme|default|admin|root|test123)['\"]?)" --include="*.py" --include="*.js" --include="*.ts" --include="*.yaml" --include="*.yml" --include="*.json" --include="*.rb" --include="*.go" --include="*.java"
       ```

   13. **Fail-open security toggles:**
       ```
       grep -rnEi "(AUTH_REQUIRED|VERIFY_SSL|CSRF_ENABLED|SECURE_COOKIES|REQUIRE_AUTH|ENABLE_AUTH)\s*[:=]\s*\b(False|false|0|no|off)\b" --include="*.py" --include="*.js" --include="*.ts" --include="*.yaml" --include="*.yml" --include="*.env" --include="*.rb" --include="*.go"
       ```

   14. **Weak cryptographic defaults:**
       ```
       grep -rnEi "\b(md5|sha1(?!_)|des[^cir]|rc4|ecb|blowfish)\b" --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" --include="*.rb" --include="*.cs"
       ```
       Only flag when used in security contexts (hashing passwords, encrypting data, signing tokens). Do NOT flag when used in checksums, cache keys, or non-security file hashing.

   15. **Permissive access defaults:**
       ```
       grep -rnE "(Access-Control-Allow-Origin.*\*|cors.*origin.*\*|0\.0\.0\.0|chmod\s+0?777|ALLOW_ALL|allow_any)" --include="*.py" --include="*.js" --include="*.ts" --include="*.yaml" --include="*.yml" --include="*.go" --include="*.java" --include="*.rb"
       ```

   16. **Debug/development mode flags:**
       ```
       grep -rnEi "(DEBUG\s*[:=]\s*(True|true|1|yes|on)|FLASK_DEBUG|DJANGO_DEBUG|NODE_ENV.*development)" --include="*.py" --include="*.js" --include="*.ts" --include="*.yaml" --include="*.yml" --include="*.env"
       ```
       Only flag in production configuration files and application defaults. Do NOT flag in test fixtures, development-only configs, or CI configurations.
   ```

   - In `## Step 3` (false positive filtering), add guidance:

   ```markdown
   **Insecure default classification rules:**
   - **CONFIRMED** if the fallback/default value would be used in production
     (no environment variable override required for the app to start)
   - **FALSE_POSITIVE** if the pattern is in a test file, example/sample config,
     documentation, or has a comment indicating it is intentionally a placeholder
   - **FALSE_POSITIVE** if the "weak crypto" match is for non-security use
     (cache keys, file checksums, ETag generation)
   ```

2. **`skills/secure-review/SKILL.md`** (modify -- v1.1.0 -> v1.2.0)

   Changes:
   - Update frontmatter `version: 1.2.0`
   - In `## Step 0`, add codebase size classification after scope determination:

   ```markdown
   **Codebase size classification (controls analysis depth):**

   After determining the diff, classify the change size:
   - **SMALL** (<500 changed lines): Full line-by-line analysis of every change.
     Trace every data flow end-to-end. Check git blame for regression patterns.
   - **MEDIUM** (500-2000 changed lines): Focus on security-relevant files first
     (auth, crypto, input handling, config). Sample non-security files at 50%.
     Git blame on modified security-critical files only.
   - **LARGE** (>2000 changed lines): Prioritize files by risk score (see below).
     Analyze top-risk files in full, remainder by function signature and
     data flow entry/exit points only. Skip git blame (too noisy at this scale).

   Determine size by running:
   ```
   git diff --stat HEAD | tail -1
   ```
   Parse the "N insertions, M deletions" line. Changed lines = insertions + deletions.
   ```

   - In `## Step 1`, enhance Scan 1a (Vulnerability scan) prompt with:

   ```markdown
   **Blast radius assessment (for each modified function/method):**

   For every function/method that has security-relevant changes, estimate blast radius:
   1. Count direct callers: `grep -rn "function_name" --include="*.{ext}" | wc -l`
   2. Check if function is exported/public (broader blast radius)
   3. Check if function handles external input (trust boundary crossing)
   Report format: `function_name: N callers, exported={yes/no}, handles_input={yes/no}`

   **Git blame regression detection:**

   For SMALL and MEDIUM codebases, check if modifications reintroduce patterns
   that were previously fixed:
   1. Run `git log --oneline --all -20 -- <modified-file>` to see recent history
   2. Look for commit messages containing "fix", "vuln", "CVE", "security", "patch"
   3. If a security fix commit exists, compare the current change against that fix
      to detect regression (re-opening a previously closed vulnerability)

   **Common vulnerability pattern checklist (check each modified file for):**

   - Double accounting: two code paths that both modify the same state (e.g., balance)
   - TOCTOU race: check-then-use with no lock between check and use
   - Integer overflow / type coercion: arithmetic on user-controlled values without bounds
   - Unchecked error returns: function returns error but caller ignores it
   - DoS via unbounded operations: loops, allocations, or queries controlled by user input
   - Sensitive data in logs: PII, tokens, or secrets passed to log/print functions
   ```

   - In `## Step 2` (synthesis), add per-file risk scoring:

   ```markdown
   **Per-file risk score (0-10):**

   Score each modified file on a 0-10 risk scale based on:
   - +3 if file handles external/untrusted input (request handlers, parsers, API endpoints)
   - +2 if file implements authentication or authorization logic
   - +2 if file uses cryptographic operations
   - +1 if file accesses databases or external services
   - +1 if file handles file I/O or process execution
   - +1 if file sits on a trust boundary (crosses zones in the architecture)
   - +0 for test files, documentation, static assets

   Include the per-file risk table in the synthesis report:
   | File | Risk Score | Risk Factors |
   |------|-----------|-------------|
   ```

3. **`skills/dependency-audit/SKILL.md`** (modify -- v1.0.0 -> v1.1.0)

   Changes:
   - Update frontmatter `version: 1.1.0`
   - In `## Step 5` (supply chain risk assessment), replace the existing free-form
     instructions with structured risk criteria:

   ```markdown
   ### Supply Chain Risk Assessment

   Evaluate each direct dependency against these structured risk criteria.
   Use `gh` CLI for GitHub metadata when available (graceful degradation if
   `gh` is not installed or not authenticated).

   **Risk Criteria (check each dependency):**

   1. **Single/low maintainer count** (HIGH risk indicator)
      If `gh` is available:
      ```bash
      gh api repos/{owner}/{repo}/contributors --jq 'length'
      ```
      Flag if contributor count <= 2. This is the left-pad/event-stream risk:
      a single compromised or burned-out maintainer can affect all consumers.

   2. **Unmaintained/archived** (HIGH risk indicator)
      If `gh` is available:
      ```bash
      gh api repos/{owner}/{repo} --jq '{archived: .archived, pushed_at: .pushed_at, open_issues: .open_issues_count}'
      ```
      Flag if: repo is archived, OR last push > 12 months ago, OR open issues > 100
      with no recent activity.

   3. **Past CVE history** (MEDIUM risk indicator)
      Cross-reference with scanner output from Step 2. If the dependency has had
      previous CVEs (even if currently fixed), flag as elevated risk -- repeat
      offenders indicate structural security issues in the codebase.

   4. **High-risk features** (MEDIUM risk indicator)
      Check if the dependency uses:
      - FFI / native code bindings (C extensions, node-gyp, cgo)
      - Deserialization of untrusted data (pickle, yaml.load, JSON.parse with reviver)
      - Code execution capabilities (eval, exec, Function constructor)
      - Network listeners or servers (opens ports, accepts connections)
      Flag each high-risk feature found.

   5. **Low popularity** (LOW risk indicator)
      If `gh` is available:
      ```bash
      gh api repos/{owner}/{repo} --jq '.stargazers_count'
      ```
      Flag if stars < 100 for a non-internal package. Low popularity means fewer
      eyes reviewing the code for security issues.

   6. **Missing security contact** (LOW risk indicator)
      If `gh` is available, check for SECURITY.md:
      ```bash
      gh api repos/{owner}/{repo}/contents/SECURITY.md --jq '.name' 2>/dev/null
      ```
      Missing SECURITY.md means no coordinated disclosure process.

   **Graceful degradation:** If `gh` is not available or returns errors,
   skip GitHub metadata queries and note in the report:
   "GitHub metadata unavailable -- supply chain risk assessment is based on
   manifest data and scanner output only. Install and authenticate `gh` CLI
   for full assessment."

   **Report format for supply chain risks:**

   | Dependency | Version | Risk Level | Risk Factors | Suggested Alternative |
   |-----------|---------|-----------|-------------|---------------------|
   | left-pad | 1.1.3 | HIGH | 1 maintainer, archived | String.prototype.padStart (built-in) |

   For HIGH-risk dependencies, suggest well-maintained alternatives where known.
   Do not fabricate alternatives -- only suggest packages you can verify exist.
   ```

4. **`skills/threat-model-gate/SKILL.md`** (modify -- v1.0.0 -> v1.1.0)

   Changes:
   - Update frontmatter `version: 1.1.0`
   - Expand the existing `## STRIDE Quick Reference` table to include DREAD dimensions:

   ```markdown
   ## STRIDE Quick Reference

   | Category | Threat Target | Standard Mitigation | DREAD Focus |
   |----------|--------------|--------------------|----|
   | **S**poofing | Identity, authentication | MFA, strong auth, certificate pinning | Reproducibility: how reliably can credentials be forged? |
   | **T**ampering | Data integrity, code | Input validation, signing, checksums | Damage Potential: what is the blast radius of tampered data? |
   | **R**epudiation | Audit trails, logging | Comprehensive audit logs, timestamps | Discoverability: how visible is the logging gap? |
   | **I**nfo Disclosure | Confidentiality | Encryption at rest/transit, access controls | Affected Users: how many users' data is exposed? |
   | **D**enial of Service | Availability | Rate limiting, auto-scaling, circuit breakers | Exploitability: how easily can the DoS be triggered? |
   | **E**levation of Privilege | Authorization | Least privilege, RBAC, input validation | Damage Potential: what can the attacker do with elevated access? |
   ```

   - Add new section after STRIDE Quick Reference:

   ```markdown
   ## DREAD Risk Rating Reference

   When threat modeling identifies specific threats, score each using DREAD
   (5 dimensions, each 0-10). The average determines severity classification.

   | Dimension | Question | 0 (Low) | 5 (Medium) | 10 (High) |
   |-----------|---------|---------|-----------|----------|
   | Damage Potential | How bad if exploited? | Minor inconvenience | Single user data loss | Full system compromise |
   | Reproducibility | How reliably exploitable? | Race condition, rare | Requires specific config | Every time, automated |
   | Exploitability | How much skill needed? | Nation-state capability | Security professional | Script kiddie, public exploit |
   | Affected Users | How many impacted? | Single user, edge case | Subset of users | All users / tenants |
   | Discoverability | How easy to find? | Requires source code access | Findable by scanning | Obvious from public interface |

   **Severity bands:**
   - **CRITICAL:** DREAD average >= 8.0
   - **HIGH:** DREAD average >= 6.0 and < 8.0
   - **MEDIUM:** DREAD average >= 4.0 and < 6.0
   - **LOW:** DREAD average < 4.0

   **Calibration rule:** When a score falls within 0.5 of a boundary (e.g., 5.5-6.4),
   check Damage Potential. If DP >= 7, round UP. If DP <= 3, round DOWN.
   ```

   - Add new section before `## The Bottom Line`:

   ```markdown
   ## Full Threat Modeling Methodology

   This skill provides a **planning gate** -- it ensures threat modeling happens
   before implementation. For the **full threat modeling methodology** with
   three-phase STRIDE+DREAD analysis and OTM JSON output, load the standalone
   `threat-model` knowledge-base skill:

   ```
   Using skills/threat-model/SKILL.md: perform a threat model for this system.
   ```

   The `threat-model` skill provides:
   - Three-phase workflow: System Decomposition, Per-Subsystem Threat Analysis, Cross-Cutting Synthesis
   - DREAD scoring with calibration and consistency checks
   - MITRE ATT&CK technique mapping
   - OTM v0.2.0 JSON output (machine-readable)
   - Structured markdown report (human-readable)
   - Reference materials in `reference/otm-schema.md` and `reference/report-template.md`
   ```

   - Add to `## Anti-Patterns`:

   ```markdown
   9. **Incomplete trust boundary analysis**
      - WRONG: "The API talks to the database" (no trust boundary identified)
      - RIGHT: "Data flow DF-003 crosses from TZ-DMZ to TZ-Internal at the API-to-DB boundary, carrying user credentials over PostgreSQL wire protocol"

   10. **Skipping DREAD calibration**
       - WRONG: DREAD average 5.8, classified as MEDIUM
       - RIGHT: DREAD average 5.8 with Damage Potential 8 -> calibrate UP to HIGH (DP >= 7 near boundary)
   ```

### Work Group 3: Documentation and Tests

Modifications to documentation and test files. No overlap with Work Group 1 (new skill content) or Work Group 2 (existing skill modifications).

1. **`CLAUDE.md`** (modify)

   Update the **Skill Registry** table in the `## Skill Registry` section.

   Add 7 new rows to the **Core Skills** table after the existing `fix` row:

   ```markdown
   | **input-validation-injection** | 1.0.0 | Injection prevention reference: SQL, LDAP, OS command, prototype pollution, ReDoS. Knowledge-base from prodsec-skills. | N/A | Knowledge-base |
   | **client-side-security** | 1.0.0 | Browser security reference: XSS (5 contexts), CSP, CSRF, XS-Leaks, Trusted Types, security headers. Knowledge-base from prodsec-skills. | N/A | Knowledge-base |
   | **ai-code-review** | 1.0.0 | AI-generated code review: hallucinated APIs, plausible-but-wrong logic, pattern drift, stale dependencies. Knowledge-base from prodsec-skills. | N/A | Knowledge-base |
   | **semgrep** | 1.0.0 | Semgrep static analysis orchestration: auto-language detection, 30+ rulesets, SARIF output, Semgrep Pro support. Knowledge-base from prodsec-skills. | N/A | Knowledge-base |
   | **build-yaml-misconfiguration** | 1.0.0 | CI/CD pipeline security: GitLab CI, Tekton, Containerfile hardening across 18+ misconfiguration categories. Knowledge-base from prodsec-skills. | N/A | Knowledge-base |
   | **container-hardening** | 1.0.0 | Container image and runtime security: non-root, read-only filesystem, capability restrictions, UBI base images. Knowledge-base from prodsec-skills. | N/A | Knowledge-base |
   | **threat-model** | 1.0.0 | Full STRIDE+DREAD threat modeling with OTM v0.2.0 JSON output, MITRE ATT&CK mapping, three-phase methodology. Knowledge-base from prodsec-skills. Includes reference/ subdirectory. | N/A | Knowledge-base |
   ```

   Update 4 existing rows with new versions:
   - `secrets-scan`: version 1.0.0 -> 1.1.0, description add "insecure defaults detection"
   - `secure-review`: version 1.1.0 -> 1.2.0, description add "blast radius, codebase sizing, regression detection"
   - `dependency-audit`: version 1.0.0 -> 1.1.0, description add "structured supply chain risk criteria with GitHub metadata"
   - `threat-model-gate`: version 1.0.0 -> 1.1.0, description add "DREAD reference, cross-reference to threat-model skill"

   Update the skill count references:
   - "13 core reusable Claude Code workflows" -> "20 core skills (13 workflows + 7 knowledge bases)"
   - Update the `/skills` directory structure listing to include all 20 skills
   - Update `test_skill_generator.sh` test count references

   Add a clarification note in the Knowledge-Base Pattern section (or near the registry table) explaining the distinction between `threat-model-gate` and `threat-model`:

   ```markdown
   **`threat-model-gate` vs `threat-model`:** These serve different purposes and have different invocation patterns.
   `threat-model-gate` is a **planning gate** (behavioral discipline, `type: reference`) -- it is invoked automatically by `/architect` Stage 2 and checked by `/ship` Step 1 to ensure threat modeling happens before implementation. Users do not invoke it directly.
   `threat-model` is a **standalone methodology** (domain knowledge, `type: knowledge-base`) -- it provides full STRIDE+DREAD+OTM threat modeling methodology for hands-on threat modeling sessions.

   Knowledge-base skills are loaded as context, not invoked as slash commands. Use:
   ```
   Using skills/threat-model/SKILL.md: perform a threat model for this system.
   ```
   Do not attempt `/threat-model` -- knowledge-base skills have no workflow steps to execute.
   ```

   Add a new subsection under `## Skill Architectural Patterns (v2.0.0)`:

   ```markdown
   #### Knowledge-Base Pattern (prodsec-skills integration)

   **Characteristics:**
   - Tool-agnostic reference materials (not executable workflows)
   - Domain-specific security knowledge, checklists, and methodologies
   - Imported from Red Hat Product Security's prodsec-skills repository
   - Loaded as context by other skills or directly by users
   - No model, steps, tools, or verdict gates

   **Use Cases:**
   - Security review context (load alongside /secure-review or /audit)
   - Developer reference during implementation
   - Code review checklists
   - Standalone security analysis methodology

   **Frontmatter:**
   ```yaml
   ---
   name: skill-name
   description: Invocation condition description.
   type: knowledge-base
   version: 1.0.0
   attribution: "Red Hat Product Security, prodsec-skills repository"
   ---
   ```

   **Example usage:**
   ```
   Using skills/input-validation-injection/SKILL.md: review this endpoint for injection risks.
   Using skills/threat-model/SKILL.md: perform a threat model for the authentication subsystem.
   ```
   ```

2. **`generators/test_skill_generator.sh`** (modify)

   Add 12 new tests after Test 57 (before Test 50 Cleanup -- note: Test 50 is the cleanup step, but tests 51-57 were inserted before it in the file; new tests follow the same pattern).

   ```bash
   # ============================================================
   # Prodsec knowledge-base skill validation tests
   # ============================================================

   # Test 58: Validate input-validation-injection skill
   run_test 58 "Validate input-validation-injection skill" \
       "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/input-validation-injection/SKILL.md'" \
       0

   # Test 59: Validate client-side-security skill
   run_test 59 "Validate client-side-security skill" \
       "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/client-side-security/SKILL.md'" \
       0

   # Test 60: Validate ai-code-review skill
   run_test 60 "Validate ai-code-review skill" \
       "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/ai-code-review/SKILL.md'" \
       0

   # Test 61: Validate semgrep skill
   run_test 61 "Validate semgrep skill" \
       "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/semgrep/SKILL.md'" \
       0

   # Test 62: Validate build-yaml-misconfiguration skill
   run_test 62 "Validate build-yaml-misconfiguration skill" \
       "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/build-yaml-misconfiguration/SKILL.md'" \
       0

   # Test 63: Validate container-hardening skill
   run_test 63 "Validate container-hardening skill" \
       "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/container-hardening/SKILL.md'" \
       0

   # Test 64: Validate threat-model skill
   run_test 64 "Validate threat-model skill" \
       "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/threat-model/SKILL.md'" \
       0

   # Test 65: Knowledge-base archetype validates with minimal frontmatter
   mkdir -p "$TEST_DIR/skills/test-kb"
   cat > "$TEST_DIR/skills/test-kb/SKILL.md" << 'KBEOF'
   ---
   name: test-kb
   description: Test fixture for knowledge-base archetype validation
   type: knowledge-base
   version: 1.0.0
   attribution: "Test fixture"
   ---

   # Test Knowledge Base

   This is a test knowledge-base skill with reference content.

   ## Section One

   Some guidance content here.
   KBEOF
   run_test 65 "Knowledge-base archetype validates" \
       "python3 '$VALIDATE_PY' '$TEST_DIR/skills/test-kb/SKILL.md'" \
       0
   rm -rf "$TEST_DIR/skills/test-kb"

   # Test 66: Knowledge-base rejects empty body
   mkdir -p "$TEST_DIR/skills/test-kb-empty"
   cat > "$TEST_DIR/skills/test-kb-empty/SKILL.md" << 'KBEOF2'
   ---
   name: test-kb-empty
   description: Test fixture with empty body
   type: knowledge-base
   version: 1.0.0
   attribution: "Test fixture"
   ---
   KBEOF2
   run_test 66 "Knowledge-base rejects empty body" \
       "python3 '$VALIDATE_PY' '$TEST_DIR/skills/test-kb-empty/SKILL.md'" \
       1
   rm -rf "$TEST_DIR/skills/test-kb-empty"

   # Test 67: Knowledge-base rejects missing attribution field
   mkdir -p "$TEST_DIR/skills/test-kb-no-attr"
   cat > "$TEST_DIR/skills/test-kb-no-attr/SKILL.md" << 'KBEOF3'
   ---
   name: test-kb-no-attr
   description: Test fixture missing attribution field
   type: knowledge-base
   version: 1.0.0
   ---

   # Test Knowledge Base

   Content without attribution field in frontmatter.
   KBEOF3
   run_test 67 "Knowledge-base rejects missing attribution" \
       "python3 '$VALIDATE_PY' '$TEST_DIR/skills/test-kb-no-attr/SKILL.md'" \
       1
   rm -rf "$TEST_DIR/skills/test-kb-no-attr"

   # Test 68: deploy.sh copies reference/ directory
   # Create a temp skill with reference/ dir, deploy it, verify reference/ copied
   mkdir -p "$TEST_DIR/skills/test-ref-deploy/reference"
   cat > "$TEST_DIR/skills/test-ref-deploy/SKILL.md" << 'REFEOF'
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
   echo "# Test reference file" > "$TEST_DIR/skills/test-ref-deploy/reference/test-ref.md"
   run_test 68 "deploy.sh copies reference/ directory" \
       "cd '$SKILLS_DIR' && bash scripts/deploy.sh test-ref-deploy && test -f ~/.claude/skills/test-ref-deploy/reference/test-ref.md" \
       0
   rm -rf "$TEST_DIR/skills/test-ref-deploy"
   rm -rf ~/.claude/skills/test-ref-deploy

   # Test 69: Enhanced skill grep patterns are syntactically valid
   # Smoke-test that the insecure-defaults grep patterns added to secrets-scan
   # are valid grep -E syntax (exit 0 or 1, not exit 2 which indicates syntax error)
   run_test 69 "secrets-scan grep patterns are valid syntax" \
       "grep -rnE '(environ\\.get|getenv|ENV\\[|process\\.env)' --include='*.py' /dev/null; test \$? -ne 2" \
       0
   ```

   Update the test file header comment to reflect the new test count (69 tests).

---

## Appendix A: Prodsec Skill Frontmatter Adaptation Template

For each of the 7 straight-copy skills, replace the prodsec frontmatter:

**Before (prodsec format):**
```yaml
---
name: skill-name
description: Description text.
category: secure_development
subcategory: web-security
---
```

**After (devkit format):**
```yaml
---
name: skill-name
description: "Description text."
type: knowledge-base
version: 1.0.0
attribution: "Red Hat Product Security, prodsec-skills repository"
---
```

**Multi-line description flattening (required):** Prodsec skills use YAML folded block scalars (`>` or `>-`) for descriptions. Devkit's `parse_frontmatter()` is a line-by-line parser that does not handle multi-line YAML. All multi-line descriptions must be flattened to double-quoted single-line strings during adaptation:

```yaml
# Before (prodsec multi-line -- will break devkit parser)
description: >
  Apply when reviewing or writing code that processes untrusted input,
  constructs queries or commands, or handles user-supplied data. Covers SQL,
  LDAP, OS command injection, prototype pollution, and general validation strategy.

# After (devkit single-line -- required format)
description: "Apply when reviewing or writing code that processes untrusted input, constructs queries or commands, or handles user-supplied data. Covers SQL, LDAP, OS command injection, prototype pollution, and general validation strategy."
```

Collapse all whitespace and newlines from the folded block into a single space-separated string. Wrap in double quotes. Preserve the full description text -- do not truncate.

The body content below the frontmatter is copied unchanged.

## Appendix B: File Inventory

### Files Created (9)

| File | Work Group | Size (approx) |
|------|-----------|---------------|
| `skills/input-validation-injection/SKILL.md` | WG1 | 100 lines |
| `skills/client-side-security/SKILL.md` | WG1 | 123 lines |
| `skills/ai-code-review/SKILL.md` | WG1 | 231 lines |
| `skills/semgrep/SKILL.md` | WG1 | 564 lines |
| `skills/build-yaml-misconfiguration/SKILL.md` | WG1 | 403 lines |
| `skills/container-hardening/SKILL.md` | WG1 | 108 lines |
| `skills/threat-model/SKILL.md` | WG1 | 1315 lines |
| `skills/threat-model/reference/otm-schema.md` | WG1 | 905 lines |
| `skills/threat-model/reference/report-template.md` | WG1 | 335 lines |

Note: `skills/threat-model/reference/` directory is also created (not counted as a file).

### Files Modified (9)

| File | Work Group | Change Summary |
|------|-----------|---------------|
| `configs/skill-patterns.json` | Shared | Add knowledge-base archetype |
| `generators/validate_skill.py` | Shared | Add knowledge-base validation, fix model allowlist |
| `scripts/deploy.sh` | Shared | Copy reference/ directories |
| `skills/secrets-scan/SKILL.md` | WG2 | v1.1.0: insecure defaults patterns |
| `skills/secure-review/SKILL.md` | WG2 | v1.2.0: blast radius, sizing, regression detection |
| `skills/dependency-audit/SKILL.md` | WG2 | v1.1.0: supply chain risk criteria |
| `skills/threat-model-gate/SKILL.md` | WG2 | v1.1.0: DREAD reference, threat-model cross-ref |
| `CLAUDE.md` | WG3 | Skill registry update, knowledge-base pattern docs |
| `generators/test_skill_generator.sh` | WG3 | 12 new validation tests |

**Total: 9 files created, 9 files modified, 1 directory created**

## Status: APPROVED

<!-- Context Metadata
discovered_at: 2026-07-15T00:00:00Z
claude_md_exists: true
recent_plans_consulted: agentic-sdlc-security-skills.md, phase0-reference-validator.md
archived_plans_consulted: none
-->
