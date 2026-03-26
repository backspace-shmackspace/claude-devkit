# Code Review: Agentic SDLC Security Skills — Phase A

**Date:** 2026-03-26
**Reviewer:** code-reviewer agent (standalone)
**Scope:** Phase A — 5 new skill files
**Plan revision reviewed:** Rev 3 (OSS migration, all Red Hat content removed)

## Code Review Summary

All 5 Phase A skills pass `validate-skill` and correctly implement their respective archetypes. The implementations are thorough, security-conscious, and faithful to the plan's requirements. Two minor correctness issues exist in `compliance-check` (wrong tool declaration in Step 0) and `secrets-scan` (typo in a recommended URL). One moderate design concern exists in `dependency-audit` and `secrets-scan` around bash variable state not persisting between tool calls — addressed in the Major Improvements section with an explanation of why it is nonetheless workable in practice.

---

## Verdict: PASS

No Critical findings. Major findings are design clarifications that do not block correctness in practice. Minor findings are low-stakes and can be addressed in a follow-up.

---

## Critical Findings (Must Fix)

None.

All plan requirements with critical safety implications are correctly implemented:

- `dependency-audit` correctly reports `INCOMPLETE` (not `PASS`) when no scanner is available. The INCOMPLETE verdict is wired in Step 0, Step 2, Step 7, and all output messages — zero chance of a silent false pass.
- `secrets-scan` never includes actual secret values in reports. The grep patterns apply `sed` redaction inline before writing to the findings file. The false-positive filter subagent receives an already-redacted file and is explicitly told "never include actual secret values" in its prompt.
- `secure-review` includes prompt injection countermeasures in all three scan prompts, both with and without a security-analyst agent. The countermeasures are explicit, repeated, and cover the specific annotation syntax (`#nosec`, `@SuppressWarnings`, `// NOSONAR`, `# type: ignore`).
- `compliance-check` includes the mandatory Limitations section verbatim from the plan, including the CMVP certification caveat, in both the report template and the verdict output messages.
- `threat-model-gate` has `type: reference` and `attribution: Original work, claude-devkit project` in frontmatter, matching the pattern established by `receiving-code-review`. Validator confirms PASS with zero warnings.
- No Red Hat or platform-specific content found in any of the 5 skills. CMVP appears in `compliance-check` appropriately as a generic FIPS 140-3 term, not a platform reference.

---

## Major Findings (Should Fix)

### M1 — `compliance-check` Step 0: Wrong tool declaration

**File:** `/Users/imurphy/projects/claude-devkit/skills/compliance-check/SKILL.md`, line 27

**Finding:** Step 0 declares `Tool: \`Read\`` but the actual operation is parsing `$ARGUMENTS` — no file is read. `Read` requires a file path argument; there is no file to read at this step. The correct declaration is `Tool: (none — coordinator parses $ARGUMENTS directly)` or, for consistency with `secure-review` which does similar argument validation via `Bash`, `Tool: \`Bash\`` if a timestamp derivation command is added.

**Why it matters:** Tool declarations in skill files are both documentation and an instruction to the executing LLM about which tool to invoke. Declaring `Read` for a step that has no file to read may cause the coordinator to pause and look for a file, or generate a confused invocation. The `secure-review` Step 0 correctly uses `Bash` and `Glob` because it actually runs `git diff HEAD` and globs for an agent file. Compliance-check Step 0 does neither.

**Recommendation:** Change the tool declaration to reflect what actually happens. The step derives a timestamp (common to add `date` command via Bash) and parses string arguments. Either:
- Add a `Bash` invocation: `TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%S")` and declare `Tool: \`Bash\``
- Or declare `Tool: (coordinator does this — no tool invocation needed)` to match the intent

The latter is simpler and honest. The other scan-archetype skills always invoke at least `Bash` in Step 0 for timestamp derivation; compliance-check should be consistent.

### M2 — `dependency-audit` Step 2: Bash variables from Step 0 do not persist

**File:** `/Users/imurphy/projects/claude-devkit/skills/dependency-audit/SKILL.md`, lines 120, 146

**Finding:** Step 2's bash block references `${TIMESTAMP}` and `${SCANNER}` which were set in Step 0's separate bash invocation. In Claude Code, each `Bash` tool call runs in a fresh shell — environment variables set in one call do not persist to the next. The Step 0 block does echo these values (`echo "SCANNER=$SCANNER"`, `echo "TIMESTAMP=$TIMESTAMP"`), so the LLM coordinator sees them in its context and is expected to interpolate them when constructing the Step 2 bash block.

**Why this is workable but fragile:** The pattern is consistent with how other skills work (e.g., `/ship` uses `RUN_ID` from Step 0 in later steps). The LLM coordinator retains tool output in its context window and substitutes values when writing subsequent bash blocks. However, the skill text says "If no scanner is available (SCANNER='' from Step 0)" — this relies on the coordinator making this connection correctly. In practice Claude Code coordinators do this reliably, but the skill does not document this dependency explicitly. A reader of the skill may assume the shell variable persists.

**Recommendation:** Add a comment in Step 2 making the dependency explicit: "Note: TIMESTAMP and SCANNER values come from the coordinator's memory of Step 0 output — they must be substituted when constructing this command." Alternatively, have Step 2 re-derive the timestamp by looking for the scanner-raw file created in Step 0, or embed a `TIMESTAMP` re-derivation command at the start of the Step 2 bash block (though this risks generating a different timestamp).

The simpler fix: add a prose note before the bash block stating "The coordinator substitutes TIMESTAMP and SCANNER from Step 0 output." This is sufficient for an LLM coordinator.

### M3 — `secrets-scan` BLOCKED path leaves artifacts un-archived

**File:** `/Users/imurphy/projects/claude-devkit/skills/secrets-scan/SKILL.md`, lines 260-280

**Finding:** When the verdict is BLOCKED, the skill outputs the finding list and stops — it does not archive the scan artifacts. The `scan-target.txt` and `raw-findings.txt` files remain in `./plans/`. Only the PASS path reaches Step 5 which archives intermediates.

**Why it matters:** A BLOCKED run leaves debris in `./plans/`. The next run will create new timestamped files, but the old blocked-run files accumulate. This is also inconsistent with the archive-on-success pattern required by CLAUDE.md Pattern 10, which states "all outputs include ISO timestamps" and archives are done on completion. BLOCKED is a completion state.

**Recommendation:** Add an archive step that runs on both PASS and BLOCKED paths. One approach: move the archive bash block into Step 4 before the final output, regardless of verdict. The BLOCKED output message can still stop the coordinator from proceeding further, but the archive should happen first.

---

## Minor Findings (Consider)

### m1 — `secrets-scan`: Typo in recommended gitleaks URL

**File:** `/Users/imurphy/projects/claude-devkit/skills/secrets-scan/SKILL.md`, line 331

**Finding:** The gitleaks URL reads `https://github.com/zricethezax/gitleaks` — the username `zricethezax` is a typo. The correct GitHub organization is `gitleaks` and the URL is `https://github.com/gitleaks/gitleaks`.

**Recommendation:** Fix the URL. This is in the recommendations section only (users who click this link will get a 404).

### m2 — `secure-review` Step 1: Data flow scan (1b) lacks security-analyst conditional branch

**File:** `/Users/imurphy/projects/claude-devkit/skills/secure-review/SKILL.md`, lines 111-131

**Finding:** Scans 1a and 1c have a conditional branch (security-analyst found / not found) that adds the agent's threat modeling frameworks to the prompt when available. Scan 1b (data flow) has no such conditional — it runs the same prompt regardless of agent availability. This is likely intentional since data flow analysis doesn't directly use STRIDE frameworks, but the inconsistency may cause confusion when reading the skill.

**Recommendation:** Either add a note explaining why 1b doesn't use the security-analyst conditional (e.g., "Data flow analysis does not benefit from STRIDE framing"), or add the conditional for consistency. The current behavior is correct; the missing explanation is the issue.

### m3 — `dependency-audit`: `govulncheck` flag difference between Step 0 and Step 2

**File:** `/Users/imurphy/projects/claude-devkit/skills/dependency-audit/SKILL.md`, lines 67 and 159

**Finding:** Step 0 sets `SCANNER_CMD="govulncheck ./..."` (no `-json` flag). Step 2's bash block runs `govulncheck -json ./...`. These produce different output formats. Step 3's synthesis subagent expects JSON format. The Step 2 version is correct; Step 0's `SCANNER_CMD` variable is never actually used (Step 2 hard-codes the commands in a `case` block), but the discrepancy is confusing documentation.

**Recommendation:** Either remove `SCANNER_CMD` from Step 0 entirely (since Step 2 doesn't use it — the `case` block uses `$SCANNER` not `$SCANNER_CMD`), or align the `govulncheck` command to include `-json`. Removing `SCANNER_CMD` is simpler and reduces confusion.

### m4 — `compliance-check` Step 0: No timestamp format example in this skill

**File:** `/Users/imurphy/projects/claude-devkit/skills/compliance-check/SKILL.md`, line 46

**Finding:** The timestamp derivation is described as "current ISO datetime (e.g., `2026-03-25T14-30-00`)" but there is no `Bash` call to actually generate it. Other skills use `TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")`. Since Step 0 doesn't invoke Bash (see M1), there is no concrete mechanism for generating the timestamp — the LLM coordinator is expected to do so conceptually.

**Recommendation:** Resolves naturally with M1: add a Bash invocation at Step 0 to generate the timestamp concretely.

### m5 — Validator warnings: "Bounded Iterations" on all 4 active skills

**Files:** All 4 active skills (secure-review, compliance-check, dependency-audit, secrets-scan)

**Finding:** All four skills receive a "Bounded Iterations" validator warning: `Pattern 7 (Bounded Iterations): If skill includes a revision loop, specify maximum iterations`. None of these skills have revision loops — the warning is a false positive from the pattern check looking for "Max N revision" language.

**Assessment:** This is a validator limitation, not a skill defect. The validator cannot distinguish between "has a revision loop without bounds" and "has no revision loop." The skills are correct as written. No action required on the skills.

**Recommendation:** Consider filing this as a validator improvement: the pattern check should look for a revision loop construct first, then require bounds. Out of scope for this review.

---

## What Went Well

**1. `dependency-audit` INCOMPLETE verdict is thorough and non-bypassable.** The no-scanner path is handled in Step 0 (pre-flight outcomes), Step 2 (explicit output template), Step 3 (synthesis subagent told to write "CVE scan skipped"), Step 6 (consolidated report marks scanner as 'none — INCOMPLETE'), and Step 7 (verdict rules explicitly state INCOMPLETE takes priority over PASS, with bold note "MUST NOT report PASS"). The plan's critical requirement is addressed at every decision point.

**2. `secure-review` prompt injection countermeasures are applied at the right level.** The countermeasures appear in two places: once as a global note at the Step 1 header (for the coordinator), and repeated verbatim inside each individual subagent prompt. This belt-and-suspenders approach ensures the subagents receive the instructions even if the coordinator's prompt injection interacts with the step boundary. Countermeasures also cover the specific annotation formats the plan required (`#nosec`, `@SuppressWarnings`, `// NOSONAR`, `# type: ignore`).

**3. `secrets-scan` pattern redaction happens at the grep layer.** The `sed` redaction is applied inline in the grep pipeline, meaning the raw findings file never contains actual secret values. The false-positive filter subagent (Step 3) therefore cannot accidentally leak secrets in its output even if it misunderstands the redaction rules. Defense-in-depth: the subagent prompt also explicitly forbids including actual values.

**4. `compliance-check` FIPS scan is technically accurate.** The FIPS 140-3 algorithm table is correct: SHA-1 correctly flagged as non-approved, HMAC-SHA1 correctly noted as borderline, ECB mode correctly flagged, GCM/CCM correctly shown as preferred alternatives. The asymmetric key minimums (RSA >=2048, ECDH NIST curves) are accurate. This level of technical correctness in the scan criteria is commendable.

**5. `threat-model-gate` reference skill is well-structured and complete.** The STRIDE quick-reference table is accurate and actionable. The Security Requirements Template is specific enough to be immediately useful (not just a checklist of vague categories). The Anti-Patterns section uses concrete "WRONG/RIGHT" examples following the same style as `receiving-code-review`. The "Relationship to Other Skills" section correctly documents how this skill interacts with `/dream`, `/ship`, `/secure-review`, and `receiving-code-review`.

**6. No Red Hat or platform-specific content anywhere.** Rev 3 migration was executed cleanly. CMVP appears appropriately as a generic FIPS term.

**7. All 5 skills validate cleanly** (`validate-skill` PASS or PASS with warnings). `threat-model-gate` achieves a clean PASS with zero warnings, as expected for a Reference archetype with no active workflow steps.

**8. Model selection is correct throughout.** `secure-review` and `compliance-check` use `claude-opus-4-6` (deep analysis tasks), while `dependency-audit`, `secrets-scan`, and `threat-model-gate` use `claude-sonnet-4-5` (appropriate for pipeline coordination and reference material). Subagent models within skills are also appropriately scoped.

---

## Recommendations (Prioritized)

1. **Fix M1** (`compliance-check` Step 0 tool declaration): Change `Tool: \`Read\`` to `Tool: \`Bash\`` and add a timestamp-generation command. This is a two-line change.

2. **Fix m1** (gitleaks URL typo in `secrets-scan`): Change `zricethezax` to `gitleaks`. One-word fix.

3. **Address M3** (`secrets-scan` BLOCKED path archive): Add a `Bash` archive block that runs before the BLOCKED output. This ensures no artifacts are left in `./plans/` after a blocked scan.

4. **Address M2** (`dependency-audit` bash variable documentation): Add a prose note in Step 2 clarifying that `TIMESTAMP` and `SCANNER` are substituted from Step 0 output by the coordinator. No code change needed — this is a documentation clarification.

5. **Consider m3** (`govulncheck` flag consistency): Remove `SCANNER_CMD` from Step 0 or align it with Step 2's `-json` flag. Low priority since `SCANNER_CMD` is never actually executed.

Items 1 and 2 are trivial and should be fixed before deployment. Items 3 and 4 are behavioral improvements. Items 5, m2, m4, m5 can be deferred to a follow-up.
