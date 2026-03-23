# Feasibility Re-Review: Agentic SDLC Security Skills (Rev 2)

**Plan:** `plans/agentic-sdlc-security-skills.md`
**Reviewer:** Code Reviewer (feasibility mode)
**Date:** 2026-03-23
**Round:** 2 (re-review after Rev 2 revision)

---

## Verdict: PASS

The Rev 2 revision adequately addresses all five Major concerns from Round 1. The plan is technically feasible, well-structured, and the phased approach (A/B/C) reduces risk compared to the original monolithic plan. Two new Minor concerns are noted below but neither blocks implementation.

---

## Prior Concerns Resolution (M1-M5)

### M1: `/secure-review` overlap with `/audit` security scan -- RESOLVED

**Original concern:** Thin differentiation between `/secure-review` and `/audit` Step 2; user confusion about which to invoke.

**How Rev 2 addressed it:**
- Added a composability model: `/secure-review` is now explicitly a "building block" that `/audit` invokes as its security scan when deployed.
- Added a "Skill Relationship Model: When to Use Which" table (plan lines 117-131) with clear delineation: `/audit` = broad surface scan, `/secure-review` = deep security analysis, and when both are deployed, `/audit` delegates to `/secure-review` for the security portion.
- `/audit` v3.1.0 modification specifies a Glob check at Step 2 -- if `/secure-review` is deployed, dispatch it; if not, use existing built-in scan (backward compatible).

**Assessment:** This is a clean composability pattern. The delegation mechanism (Glob for skill deployment, then Task dispatch) is the same pattern used by `/dream` Step 0 for agent detection, and by `/audit` Step 2 for security-analyst detection. The `/audit` modification is minimal (add a Glob + conditional dispatch in Step 2) and fully backward-compatible. The relationship table eliminates user confusion.

### M2: `/dependency-audit` CVE database check is under-specified -- RESOLVED

**Original concern:** Claude Code has no access to CVE databases; LLM-based CVE lookup is unreliable due to training cutoff; the skill would give false assurance.

**How Rev 2 addressed it:**
- Completely reframed `/dependency-audit` as a "coordinator/wrapper around real CLI scanners" (plan lines 152-177).
- Added a supported scanners table with auto-detection logic: `npm audit`, `pip-audit`/`safety`, `govulncheck`, `cargo audit`, `mvn dependency:analyze`, `bundle audit`.
- Step 0 now checks scanner availability via `which <scanner>` (Bash tool).
- Step 2 invokes the real scanner via Bash and captures output.
- Step 3 uses LLM synthesis to parse, correlate, and assess scanner output.
- When no scanner is available, the skill reports `INCOMPLETE - no scanner available` -- explicitly cannot report PASS and must not fall back to LLM guessing.
- LLM analysis is reserved for license compliance (Step 4) and supply chain risk heuristics (Step 5), where it is appropriate.

**Assessment:** This is technically sound. The pattern of detecting and invoking CLI tools via Bash is well-established in Claude Code. The `which <scanner>` check at Step 0 is a reliable availability test. The INCOMPLETE verdict for missing scanners is the correct design -- it forces teams to install the right tool rather than silently accepting unreliable results. The separation of concerns (real scanner for CVEs, LLM for license/risk analysis) is honest about capability boundaries. The model choice of `claude-sonnet-4-5` is appropriate since the LLM work is synthesis/formatting, not deep reasoning.

### M3: `/secrets-scan` entropy analysis reliability -- RESOLVED

**Original concern:** Shannon entropy computation in Claude Code is unreliable without calibration; high false-positive risk from minified JS, Base64, UUIDs.

**How Rev 2 addressed it:**
- Deferred entropy analysis to v1.1.0 (plan lines 198-199).
- v1.0.0 uses pattern-based detection only (AWS keys, GitHub tokens, private keys, connection strings, JWT tokens).
- Explicit rationale: "Entropy analysis requires file-type-specific calibration... will be added after gathering false-positive data from real codebases."

**Assessment:** Correct approach. Pattern-based detection is well-understood, deterministic, and produces few false positives. Deferring entropy analysis to a future version after collecting real-world data is a responsible engineering decision. The model downgrade to `claude-sonnet-4-5` (from the original `opus-4-6`) is also appropriate since pattern matching does not require Opus-level reasoning.

### M4: `threat-model-gate` Reference archetype requires `attribution` field -- RESOLVED

**Original concern:** Validator (`validate_skill.py` line 292) requires `attribution` in Reference skill frontmatter; plan did not specify one.

**How Rev 2 addressed it:**
- Added `attribution: Original work, claude-devkit project` to the `threat-model-gate` frontmatter specification (plan line 205).
- Added `attribution` as a required field in both the Frontmatter section (line 500) and Step A3 implementation instructions (line 828).

**Assessment:** Straightforward fix. I verified the validator code at `generators/validate_skill.py` line 292: `ref_required = ["version", "type", "attribution"]`. The specified attribution value will pass validation. Matches the pattern established by `receiving-code-review` (which has `attribution: Adapted from superpowers plugin (v4.3.1) by Jesse Vincent, MIT License`).

### M5: `/ship` inline secrets scan creates dual-maintenance burden -- RESOLVED

**Original concern:** Duplicating secret detection patterns in both `/secrets-scan` and `/ship` Step 0 creates maintenance drift.

**How Rev 2 addressed it:**
- Completely eliminated inline patterns from `/ship` (plan lines 278-307).
- `/ship` Step 0 now delegates to `/secrets-scan` via Task subagent: Glob for `~/.claude/skills/secrets-scan/SKILL.md`, if found dispatch Task subagent to execute the skill, if not found skip with log note.
- Deviation #3 (plan lines 958-960) explicitly documents: "Pattern definitions live in exactly one place (`/secrets-scan`). The trade-off is that secrets checking requires `/secrets-scan` to be deployed, which is enforced at L2+ maturity."

**Assessment:** This is the cleanest solution. The delegation mechanism is technically feasible -- see detailed analysis in the "Skill Delegation Feasibility" section below.

---

## New Feasibility Analysis

### Phased Approach (A/B/C) Dependency Analysis

The plan splits into three independent phases:

| Phase | Scope | Depends On | Risk |
|-------|-------|------------|------|
| A | 5 new skills + 1 config | Nothing | Medium |
| B | 3 modified skills (`ship`, `dream`, `audit`) | Phase A complete | Medium-High |
| C | 2 templates + 1 new template + CLAUDE.md + config | Phase A + B | Low |

**Dependency correctness:** The phase ordering is correct. Phase B references skill names from Phase A by using Glob checks for deployed skill files -- the references are by file path, not by import. If Phase A skills are deployed, Phase B will find them. If Phase A has not been deployed, Phase B's conditional gates will gracefully skip (at L1 maturity) or abort (at L2+ maturity).

**Cross-phase coupling risks:** None identified. Each phase has a clean boundary:
- Phase A creates new files only (no modifications to existing files)
- Phase B modifies existing files only (no new skill files)
- Phase C modifies templates and documentation only (no skill logic changes)

The one potential issue is that Phase B's implementation of `/ship` v3.4.0 must be validated against both Phase A deployed and not-deployed scenarios. The plan's test plan (manual tests 8-11) covers both cases, so this is addressed.

### `/dependency-audit` CLI Scanner Coordinator Feasibility

The proposed design has `/dependency-audit` detect and invoke real CLI scanners. This is feasible because:

1. **Scanner detection:** `which npm` / `which pip-audit` / `which govulncheck` etc. are standard Bash commands that return exit 0 if found, non-zero if not. This is reliable.

2. **Scanner invocation:** All listed scanners support JSON output (`npm audit --json`, `pip-audit --format json`, `cargo audit --json`, `safety check --json`). JSON output is parseable by the LLM in the synthesis step.

3. **Tool permissions:** The `~/.claude/settings.json` allowlist (per CLAUDE.md) includes `npm *`, `python3*`, and general Bash commands. However, `pip-audit`, `govulncheck`, `cargo audit`, `mvn`, and `bundle` are not explicitly allowlisted. These will trigger permission prompts on first invocation.

4. **Error handling:** The INCOMPLETE verdict for missing scanners is correct. The plan should also handle scanner errors (e.g., `npm audit` returning non-zero due to vulnerabilities -- this is expected behavior, not an error).

**One clarification needed:** `npm audit` returns exit code 1 when vulnerabilities are found (expected) vs. when it encounters an error. The skill should treat non-zero exit from `npm audit` as "findings present" not "scanner failed." This is a minor implementation detail, not a feasibility concern. The plan does not explicitly address this but the LLM synthesis step (Step 3) is flexible enough to handle it.

### `/ship` Delegation to `/secrets-scan` Feasibility

This is the most architecturally novel aspect of the plan. The proposed mechanism:

1. `/ship` Step 0 uses Glob to check if `~/.claude/skills/secrets-scan/SKILL.md` is deployed
2. If found, `/ship` dispatches a Task subagent with instructions to read and execute the `/secrets-scan` skill definition
3. The Task subagent reads the skill file, interprets its instructions, and runs the scan

**Feasibility assessment:** This is feasible but requires careful prompt engineering. The mechanism is essentially "Task subagent reads a skill file and follows its instructions" -- this is analogous to how Task subagents already read `.claude/agents/*.md` files and follow their role definitions. The difference is that a skill file contains a multi-step workflow rather than a role definition.

**Key considerations:**

- **Context window:** The Task subagent will need to read `~/.claude/skills/secrets-scan/SKILL.md` (a multi-step pipeline definition) and execute its steps. This is within the context window capacity of `claude-sonnet-4-5`.
- **Step execution fidelity:** The subagent must interpret the skill's step structure and execute it faithfully. This is similar to how coder subagents read plan files and follow task breakdowns -- an established pattern in `/ship`.
- **Tool access:** The Task subagent has access to Bash, Grep, Read, and Write -- the same tools `/secrets-scan` needs.
- **Prompt design:** The `/ship` prompt should instruct the subagent to "Read the skill definition at [path] and execute its pipeline steps. Report findings in the specified output format." This is more effective than asking it to "run /secrets-scan" which implies a skill invocation mechanism that does not exist.
- **Verdict propagation:** The subagent must write its verdict to a predictable file path that `/ship`'s coordinator can read. The plan specifies this (BLOCK workflow if secrets found).

**Comparison to existing patterns:** This pattern is not entirely novel. `/audit` Step 2 already dispatches a Task subagent with detailed instructions about what to scan and how to report. The difference is that `/audit` embeds the scan instructions in its own prompt, while `/ship` would point the subagent to an external skill file. The external file approach is cleaner (single source of truth) but adds one Read step for the subagent.

**Verdict:** Feasible. The existing Task subagent pattern supports this use case. The `/ship` prompt for the secrets-scan subagent should be explicit about reading the skill file and executing its pipeline rather than relying on implicit skill invocation.

### `/audit` v3.1.0 Composability Modification Feasibility

The proposed change adds a Glob check at `/audit` Step 2:

```
Step 2 -- Security scan
  Glob for ~/.claude/skills/secure-review/SKILL.md
  If found: dispatch /secure-review as security scan
  If not found: use existing built-in security scan
```

**Feasibility:** Fully feasible. This follows the exact same pattern as `/audit` Step 2's existing Glob for `.claude/agents/security-analyst*.md` (line 38-45 of current audit SKILL.md). The addition is:

1. One additional Glob check (parallel with existing Glob -- negligible latency)
2. Conditional dispatch: if `/secure-review` deployed, the Task subagent prompt includes "Read the /secure-review skill definition and use it as your scanning methodology" instead of the built-in scan checklist

The modification is additive (2-3 lines of conditional logic in Step 2) and preserves the existing behavior when `/secure-review` is not deployed.

### Security Maturity Levels Configuration Feasibility

The plan proposes reading `security_maturity` from `.claude/settings.json` or `.claude/settings.local.json`:

**Feasibility:** Feasible with one note. Claude Code's settings files (`settings.json`, `settings.local.json`) are standard JSON files readable via the Read tool. `/ship` Step 0 can read these files and parse the `security_maturity` field. However:

- This introduces a custom field into Claude Code's settings schema. The field is not recognized by Claude Code itself -- it is a convention used only by the skill definition. This is acceptable (the settings files are JSON and can contain arbitrary fields), but should be documented as a skill-level convention, not a Claude Code feature.
- The plan correctly specifies fallback behavior: if the field is not set, default to L1 (advisory).

---

## New Concerns

### N1: Scanner Exit Code Handling in `/dependency-audit` [Minor]

Several CLI scanners (notably `npm audit`, `pip-audit`) return non-zero exit codes when vulnerabilities are found. This is expected behavior, not an error. The plan's pipeline Step 2 invokes scanners via Bash, and Bash tool will report non-zero exit as a failure. The skill definition must instruct the coordinator that non-zero exit from vulnerability scanners is expected and the output should still be parsed.

**Recommended adjustment:** Add a note to Step 2 of `/dependency-audit`: "Non-zero exit codes from vulnerability scanners indicate findings (not errors). Capture stdout/stderr regardless of exit code. Use `|| true` after scanner invocation to prevent Bash tool from reporting failure."

### N2: `/ship` Task Subagent for `/secrets-scan` -- Prompt Specificity [Minor]

The plan says `/ship` Step 0 "dispatches a Task subagent that reads and executes the secrets-scan skill definition" but does not draft the actual subagent prompt. The prompt design is critical for execution fidelity. A vague prompt ("run the secrets scan") will produce inconsistent results; a specific prompt ("read the skill file at [path], execute Steps 0-5, write findings to [output path], report verdict as PASS or BLOCKED") will be reliable.

**Recommended adjustment:** Draft the Task subagent prompt for `/ship` Step 0 secrets-scan delegation in the implementation plan (Phase B), similar to how `/ship` Step 4a-4c have fully drafted prompts. This ensures the implementation matches the design intent.

---

## Backward Compatibility Assessment (Updated)

### `/ship` v3.3.0 -> v3.4.0

**Backward compatible: Yes.** All security gates are conditional on:
1. Skill deployment (Glob check)
2. Security maturity level (L1 default = advisory, no blocking)

At L1 (default), `/ship` behavior is identical to v3.3.0 when no security skills are deployed. The result evaluation matrix expansion (adding 4d) is additive. The `--security-override` flag is a new optional parameter that does not affect existing invocations.

### `/dream` v3.0.0 -> v3.1.0

**Backward compatible: Yes.** Changes are limited to:
- Step 0: Additional Glob for `threat-model-gate` (parallel, negligible latency)
- Step 2: Conditional prompt augmentation (only when threat-model-gate deployed AND security-related)
- Step 3a: "Optional" -> "Recommended" for security-analyst (behavioral, not structural)

### `/audit` v3.0.0 -> v3.1.0

**Backward compatible: Yes.** The only change is a conditional Glob check at Step 2. If `/secure-review` is not deployed, existing behavior is preserved exactly.

---

## Archetype Pattern Compliance (Updated)

| Skill | Archetype | Valid Frontmatter? | Matches Template? | Validator Will Accept? |
|-------|-----------|-------------------|-------------------|----------------------|
| `/secure-review` | Scan | Yes (name, description, model, version) | Yes | Yes (if 11 patterns present) |
| `/compliance-check` | Scan | Yes | Yes | Yes |
| `/dependency-audit` | Pipeline | Yes (model: claude-sonnet-4-5) | Yes | Yes |
| `/secrets-scan` | Pipeline | Yes (model: claude-sonnet-4-5) | Yes | Yes |
| `threat-model-gate` | Reference | Yes (type: reference, attribution present) | Yes | Yes (validated via validate_reference_skill) |

The validator at `generators/validate_skill.py` handles Reference skills via a dedicated `validate_reference_skill()` function (line 279) that checks for `version`, `type`, and `attribution` in frontmatter, and verifies non-empty body with at least one heading containing core patterns (like "Core Principle"). The `threat-model-gate` specification satisfies all these requirements.

---

## Implementation Complexity Assessment (Updated)

| Component | Complexity | Phase | Realistic? |
|-----------|-----------|-------|------------|
| `/secure-review` | Medium | A | Yes -- follows `/audit` scan pattern |
| `/compliance-check` | Medium-High | A | Yes -- framework content is substantial but well-scoped to code-level signals |
| `/dependency-audit` | Medium | A | Yes -- CLI scanner coordination is straightforward |
| `/secrets-scan` | Low-Medium | A | Yes -- pattern-based only (entropy deferred) |
| `threat-model-gate` | Low | A | Yes -- Reference archetype is content-focused |
| `redhat-security.json` | Low | A | Yes -- static config file |
| `/ship` v3.4.0 | Medium-High | B | Yes -- conditional gates are well-scoped; prompt design for secrets-scan delegation needs care |
| `/dream` v3.1.0 | Low | B | Yes -- minimal changes |
| `/audit` v3.1.0 | Low | B | Yes -- single conditional addition |
| Agent templates | Low | C | Yes -- additive sections |
| CLAUDE.md | Low | C | Yes -- registry updates |

**Overall assessment:** Phase A (2-3 sessions) and Phase B (1-2 sessions) estimates are realistic. The phased approach reduces risk significantly compared to the original monolithic plan.

---

## Recommendations

1. **Address N1 (scanner exit codes)** -- Add `|| true` guidance to `/dependency-audit` Step 2 to prevent false failures from vulnerability findings.
2. **Address N2 (prompt specificity)** -- Draft the Task subagent prompt for `/ship` Step 0 secrets-scan delegation before Phase B implementation.
3. **Proceed with implementation** -- All five Major concerns from Round 1 have been adequately resolved. The phased approach provides natural checkpoints for validation.

<!-- Context Metadata
review_type: feasibility_re-review
review_round: 2
plan_reviewed: plans/agentic-sdlc-security-skills.md
plan_revision: 2
prior_feasibility_verdict: PASS (5 Major, 5 Minor)
current_verdict: PASS (0 Major, 2 Minor)
prior_concerns_resolved: M1 (RESOLVED), M2 (RESOLVED), M3 (RESOLVED), M4 (RESOLVED), M5 (RESOLVED)
skills_reviewed: skills/ship/SKILL.md (v3.3.0), skills/audit/SKILL.md (v3.0.0), skills/dream/SKILL.md (v3.0.0)
validator_reviewed: generators/validate_skill.py (reference skill validation confirmed)
-->
