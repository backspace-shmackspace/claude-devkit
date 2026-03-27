# Plan: Security Guardrails Phase B -- Embed Security in /ship, /architect, and /audit

## Revision Log

| Rev | Date | Trigger | Summary |
|-----|------|---------|---------|
| 1 | 2026-03-26 | Initial draft | Phase B implementation plan for embedding security guardrails into core workflow skills |
| 2 | 2026-03-26 | Red team FAIL + librarian + feasibility review | Resolve C1 (L1 non-blocking semantics), M1 (override governance documentation), M2 (secrets scan scope fix), M3 (dependency audit diff-based trigger), M4 (keyword list expansion), M5+R2+F-M2 (audit output filename consistency), M6 (BLOCKED enters revision loop), F-M1 (override parsing pinned to Step 0 first action), F-M3 (python3 justification note). See detailed changes below. |

**Rev 2 Detailed Changes:**

| # | Source Finding | Change Made |
|---|---------------|-------------|
| 1 | C1 (Red Team) + R1 (Librarian) | Made result evaluation matrix maturity-level-aware. At L1: secure-review and dependency-audit BLOCKED auto-downgrade to PASS_WITH_NOTES with prominent warning. At L2/L3: BLOCKED is a hard stop (unless overridden). Exception: secrets-scan BLOCKED blocks at ALL levels (Deviation 4 added). |
| 2 | M2 (Red Team) | Changed secrets scan scope from `staged` to `all` (working directory). Step 0 requires a clean working directory so there are no staged files; scanning "all" catches secrets in the codebase. |
| 3 | M5 (Red Team) + R2 (Librarian) + F-M2 (Feasibility) | Resolved audit output filename contradiction. Standardized on `audit-[timestamp].security.md` throughout -- Proposed Design, Interfaces, Implementation Plan, and Task Breakdown all use the same convention. Step 5 (Synthesis) requires no changes. |
| 4 | M1 (Red Team) | Added "Known limitation (v1.0)" paragraph to section 1d documenting that `--security-override` is a blanket override (no per-finding scoping, no approver field, no structured audit record). Explicitly noted as insufficient for full L3 compliance. Per-finding granularity deferred. |
| 5 | M3 (Red Team) | Changed dependency audit trigger from plan-text heuristic to actual `git diff HEAD` on manifest files. Catches both planned and unplanned dependency additions. |
| 6 | M4 (Red Team) | Expanded security-sensitive keyword list with OWASP/CWE categories: file operations (upload, download, path, exec, eval), network (cors, proxy, redirect, webhook, dns, url), data (database, query, sql, export, import, backup), payment (payment, stripe, billing, credit card, bank). Updated in both Proposed Design and Implementation Plan. |
| 7 | M6 (Red Team) | Added `REVISION_NEEDED + BLOCKED` row to L2/L3 result evaluation matrix. When code review returns REVISION_NEEDED and secure review returns BLOCKED, the workflow enters the revision loop (not a dead-end). Coders fix both code review and security findings. BLOCKED only stops the workflow after the revision loop is exhausted. |
| 8 | F-M1 (Feasibility) | Pinned `--security-override` parsing as the very first action in Step 0, before run ID generation or any other use of `$ARGUMENTS`. Added explicit language: "After extraction, `$ARGUMENTS` contains ONLY the plan path for all subsequent steps." |
| 9 | F-M3 (Feasibility) | Added justification note for python3 usage in config read: Python 3 available on all target platforms, `json` module handles edge cases, silent failure defaults to L1 (safe default). |

## Context

Phase A of the agentic-sdlc-security-skills plan is complete. Five standalone security skills are deployed and working:

1. `/secrets-scan` (v1.0.0) -- Pipeline archetype, pre-commit secrets detection
2. `/secure-review` (v1.0.0) -- Scan archetype, deep semantic security review
3. `/dependency-audit` (v1.0.0) -- Pipeline archetype, CLI scanner coordinator
4. `/compliance-check` (v1.0.0) -- Scan archetype, code-level compliance signals
5. `threat-model-gate` (v1.0.0) -- Reference archetype, threat modeling discipline

These skills currently operate standalone. Phase B embeds them as automated gates within the existing `/ship`, `/architect`, and `/audit` workflows. This is the key integration step that transforms security from "opt-in if you remember" to "embedded by default."

**Current skill versions (confirmed via source):**
- `skills/ship/SKILL.md` -- v3.4.0 (bumped during secure-review-remediation)
- `skills/architect/SKILL.md` -- v3.0.0 (renamed from `/dream` in commit b0ecec9)
- `skills/audit/SKILL.md` -- v3.0.0

**Parent plan:** `plans/agentic-sdlc-security-skills.md` (Status: APPROVED, Rev 3)

**Key constraint:** The parent plan references `/dream` but the skill has been renamed to `/architect`. All modifications target `skills/architect/SKILL.md`, not `skills/dream/SKILL.md`.

## Architectural Analysis

### Key Drivers

1. **Shift-left integration** -- Security gates must run at the same speed as the workflow, not as a separate manual step.
2. **Backward compatibility** -- All changes are conditional on security skill deployment. A project without security skills deployed sees zero behavioral change in `/ship`, `/architect`, or `/audit`.
3. **Configurable enforcement** -- Security Maturity Levels (L1/L2/L3) allow teams to graduate from advisory to enforced at their own pace.
4. **Composition over duplication** -- `/ship` delegates to `/secrets-scan` via Task subagent. `/audit` delegates to `/secure-review`. No security logic is duplicated across skills.
5. **Escape valve** -- `--security-override` prevents false positives from permanently blocking developer flow.

### Trade-offs

| Decision | Option A | Option B | Choice | Rationale |
|----------|----------|----------|--------|-----------|
| Security gate placement in /ship | Add as new numbered steps (Step 0.5, Step 4.5) | Embed within existing steps (Step 0, Step 4, Step 6) | **Option B** | Adding new steps would change the step numbering that existing plans and documentation reference. Embedding within existing steps preserves the step contract. |
| Maturity level storage | Dedicated `security.json` config | Field in `.claude/settings.json` | **Option B** | Parent plan specifies `.claude/settings.json` or `.claude/settings.local.json`. This aligns with existing Claude Code settings pattern and avoids creating a new config file. |
| /ship --security-override parsing | Dedicated flag parser | Extract from $ARGUMENTS string | **Option B** | /ship already parses $ARGUMENTS for the plan path. Adding `--security-override "reason"` to the same argument string keeps the invocation pattern consistent. No new input mechanism required. |
| /architect threat-model injection | Inject into all plans | Inject only for security-sensitive plans | **Option B** | Injecting threat model requirements into every plan (e.g., "add CSS gradient to hero section") would add noise and slow down non-security work. The skill should heuristically detect security-sensitive topics. |
| /audit composability binding | Hard dependency on /secure-review | Conditional delegation with fallback | **Option B** | Hard dependency would break /audit for anyone who hasn't deployed /secure-review. Conditional delegation preserves backward compatibility. |

### Requirements

- All modified skills pass `validate-skill` with zero errors
- No breaking changes to existing invocation patterns
- All security gates are conditional on skill deployment (graceful degradation)
- Security Maturity Levels default to L1 (advisory) -- zero friction for existing users
- `--security-override` requires a reason string and is logged in reports
- Version bumps follow semver: ship 3.4.0 -> 3.5.0, architect 3.0.0 -> 3.1.0, audit 3.0.0 -> 3.1.0

## Goals

1. Embed `/secrets-scan` as a pre-flight gate in `/ship` Step 0 (delegate, not duplicate)
2. Embed `/secure-review` as a parallel verification step in `/ship` Step 4 (alongside code review, tests, QA)
3. Embed `/dependency-audit` as a pre-commit check in `/ship` Step 6 (when new deps added)
4. Add Security Maturity Level configuration reading to `/ship` Step 0
5. Add `--security-override` flag support to `/ship` for false-positive escape
6. Add `threat-model-gate` awareness to `/architect` Step 0, Step 2, and Step 3
7. Add `/secure-review` composability to `/audit` Step 2

## Non-Goals

- Modifying agent templates (Phase C scope)
- Updating CLAUDE.md registry (Phase C scope)
- Creating new template files (Phase C scope)
- Modifying the Phase A security skills themselves
- Implementing L3 audit trail auto-commit for security artifacts (future enhancement -- L3 is defined but auto-commit of security scan results is deferred)
- Implementing entropy-based scanning in `/secrets-scan` (v1.1.0 scope)

## Assumptions

1. Phase A skills are deployed and stable (confirmed: all 5 skills exist in `skills/` directory)
2. `/ship` is currently at v3.4.0 (confirmed from source)
3. `/architect` is the renamed `/dream` skill at v3.0.0 (confirmed: `skills/architect/SKILL.md` exists, `skills/dream/` does not)
4. `/audit` is at v3.0.0 (confirmed from source)
5. `.claude/settings.json` is the standard location for Claude Code project settings (per CLAUDE.md)
6. The `validate-skill` validator supports all v2.0.0 patterns including numbered steps, tool declarations, verdict gates, etc.
7. The test suite (`generators/test_skill_generator.sh`) validates all production skills including ship, architect (was dream), and audit

## Proposed Design

### 1. `/ship` v3.5.0 Modifications

Four additive changes to the existing `/ship` workflow:

#### 1a. Step 0 -- Security Pre-flight (secrets scan + maturity level)

After the existing pre-flight checks (git status, agent glob checks), add two new blocks:

**Block 1: Security Maturity Level Detection**

Read `.claude/settings.json` and `.claude/settings.local.json` (local overrides project). Extract `security_maturity` field. Default to `"advisory"` (L1) if not found.

At L2/L3 (enforced/audited): Glob for all three security skills (`secrets-scan`, `secure-review`, `dependency-audit`). If any are missing, abort with a message listing which skills need deployment and the exact `deploy.sh` command to run.

**Block 2: Secrets Scan Gate**

Glob for `~/.claude/skills/secrets-scan/SKILL.md`. If found, dispatch a Task subagent that reads and executes the secrets-scan skill against the working directory (scope: `all`). If the subagent reports BLOCKED (secrets detected): at ALL maturity levels, halt `/ship` (secrets are a special case -- see Deviation 4 below). Exception: `--security-override` downgrades to PASS_WITH_NOTES. If not found, log a note at L1 or abort at L2/L3.

**Why Task subagent delegation, not inline patterns:** The parent plan explicitly requires delegation to avoid dual-maintenance burden. Pattern definitions live in exactly one place (`/secrets-scan`). The trade-off is a round-trip to spawn a subagent, but secrets scanning is fast (grep-based) and runs once at Step 0.

#### 1b. Step 4 -- Add 4d Secure Review (parallel with 4a, 4b, 4c)

Add a fourth parallel verification track:

**4d -- Secure review**

Glob for `~/.claude/skills/secure-review/SKILL.md`. If found, dispatch a Task subagent for semantic security review of the files modified in the implementation. Scope is `changes` (uncommitted files). If not found, log a note.

The secure-review verdict feeds into the existing result evaluation matrix. The matrix is expanded and is **maturity-level-aware**:

**At L1 (advisory) -- security BLOCKED is non-blocking (reported as warning, auto-downgraded to PASS_WITH_NOTES):**

| Code Review | Tests | QA | Secure Review | Action |
|---|---|---|---|---|
| PASS | Pass | PASS/PASS_WITH_NOTES | PASS/PASS_WITH_NOTES/BLOCKED/not-run | Proceed to Step 6. If BLOCKED: log prominent warning with findings summary, auto-downgrade to PASS_WITH_NOTES. |
| REVISION_NEEDED | Any | Any | Any | Enter Step 5 (revision loop) |
| FAIL | Any | Any | Any | Stop workflow |
| Any | Fail | Any | Any | Stop workflow |
| PASS | Pass | FAIL | Any | Stop workflow |

At L1, secure-review BLOCKED produces a visible warning ("Security review found critical issues -- review `./plans/[name].secure-review.md`") but does NOT stop the workflow. This aligns with the parent plan's L1 definition: "BLOCKED verdicts are reported but do not prevent commit."

**At L2/L3 (enforced/audited) -- security BLOCKED is a hard stop (unless overridden):**

| Code Review | Tests | QA | Secure Review | Action |
|---|---|---|---|---|
| PASS | Pass | PASS/PASS_WITH_NOTES | PASS/PASS_WITH_NOTES/not-run | Proceed to Step 6 |
| PASS | Pass | PASS/PASS_WITH_NOTES | BLOCKED | If --security-override: Proceed (PASS_WITH_NOTES, log override). Else: Stop workflow. |
| REVISION_NEEDED | Any | Any | Any (not BLOCKED without override) | Enter Step 5 (revision loop) |
| REVISION_NEEDED | Any | Any | BLOCKED | Enter Step 5 (revision loop). Coders fix security AND code review findings. Re-run Step 4 after revision. |
| FAIL | Any | Any | Any | Stop workflow |
| Any | Fail | Any | Any | Stop workflow |
| PASS | Pass | FAIL | Any | Stop workflow |
| Any | Any | Any | BLOCKED (no override, after revision loop exhausted) | Stop workflow |

"not-run" means the security skill was not deployed -- treated as pass at L1, treated as abort at L2/L3 (caught earlier in Step 0).

**Exception:** Secrets-scan BLOCKED at Step 0 blocks at ALL maturity levels (including L1). Committed secrets require rotation -- a costly remediation that justifies blocking even at advisory maturity. See Deviation 4 in Context Alignment.

#### 1c. Step 6 -- Dependency Audit Gate (before commit)

Before the commit gate logic, add a dependency audit check:

Glob for `~/.claude/skills/dependency-audit/SKILL.md`. If found, detect actual dependency changes by diffing manifest files against HEAD. For each known manifest file (package.json, requirements.txt, pyproject.toml, Pipfile, go.mod, Cargo.toml, pom.xml, Gemfile), run `git diff HEAD -- <file>`. If any manifest file shows additions in dependency sections, dispatch a Task subagent for dependency audit. This catches both planned and unplanned dependency additions.

BLOCKED verdict from dependency-audit: at L1, log a prominent warning and auto-downgrade to PASS_WITH_NOTES (consistent with L1 advisory semantics). At L2/L3, block the commit (unless `--security-override`). INCOMPLETE verdict is logged as a warning but does not block at any level.

#### 1d. --security-override Flag

Parse `--security-override "reason"` from `$ARGUMENTS`. When present:

- Any BLOCKED verdict from security scans (secrets-scan, secure-review, dependency-audit) is downgraded to PASS_WITH_NOTES
- The override reason is logged in the commit message footer: `Security-Override: [reason]`
- At L3 (audited), the override is flagged in the archived security report
- The override applies to security scans only, not to code review, tests, or QA verdicts

**Parsing:** Extract `--security-override` as the very first action in Step 0, before `$ARGUMENTS` is used for any other purpose (run ID generation, plan path extraction, or subagent prompts). After extraction, `$ARGUMENTS` contains only the plan path for all subsequent steps. Example: `/ship plans/feature.md --security-override "False positive: test fixture"`. The plan path is the first argument; `--security-override` and its quoted value are the second and third.

**Known limitation (v1.0):** The `--security-override` flag applies to ALL security gates in a single invocation (secrets-scan, secure-review, dependency-audit). There is no per-finding granularity (`--finding=SEC-2026-XXXX`), no approver field (`--approver=...`), and no structured audit record beyond the commit message footer. This blanket override is acceptable for L1 (advisory) and L2 (enforced) but is insufficient for full L3 compliance audit requirements. Per-finding override scoping, approver tracking, and structured audit records are deferred to a future enhancement.

### 2. `/architect` v3.1.0 Modifications

Three additive changes:

#### 2a. Step 0 -- Threat Model Gate Detection

Add a fourth Glob to the existing parallel agent pre-check:

- Pattern 4: `~/.claude/skills/threat-model-gate/SKILL.md`

If found: "Threat model gate active. Security-related plans will include threat modeling requirements."
If not found: No note (unlike missing architect/reviewer agents, threat-model-gate is optional at all maturity levels).

#### 2b. Step 2 -- Inject Threat Modeling for Security-Sensitive Plans

When threat-model-gate was found in Step 0 AND the plan subject ($ARGUMENTS) appears to involve security-sensitive functionality, append to the architect prompt:

"This plan involves security-sensitive functionality. Include a `## Security Requirements` section addressing: assets at risk, trust boundaries, STRIDE analysis (Spoofing, Tampering, Repudiation, Information Disclosure, DoS, Elevation of Privilege), and proposed mitigations. Refer to the threat-model-gate skill at `~/.claude/skills/threat-model-gate/SKILL.md` for the checklist and template."

**Security-sensitive heuristic:** The plan subject is security-sensitive if $ARGUMENTS contains any of these keywords (case-insensitive):

- **Identity/Auth:** auth, authentication, authorization, login, password, token, session, oauth, oidc, saml, api key, secret, credential, identity, mfa, 2fa, rbac, acl, permission, role, privilege, security
- **Cryptography/Network:** encrypt, decrypt, certificate, tls, ssl, firewall, cors, proxy, redirect, webhook, dns, url
- **Data/Compliance:** pii, gdpr, hipaa, compliance, fips, fedramp, export, import, backup, database, query, sql
- **File/Process:** upload, download, file, path, exec, shell, command, subprocess, eval
- **Payment:** payment, stripe, billing, credit card, bank

This heuristic is intentionally broad, covering OWASP Top 10 and CWE Top 25 threat categories. It is better to include threat modeling in a plan that doesn't need it (minor overhead) than to skip it in a plan that does (security gap).

#### 2c. Step 3a -- Strengthen Security-Analyst Recommendation

Change the security-analyst invocation language from:

> "Optional (security-specific plans only): If `.claude/agents/security-analyst.md` was found in Step 0 AND the plan subject is security-related..."

To:

> "Recommended (when threat-model-gate is deployed and plan subject is security-related): If `.claude/agents/security-analyst.md` was found in Step 0 AND `threat-model-gate` was found in Step 0 AND the plan subject is security-related..."

This changes the language from "Optional" to "Recommended" without making it mandatory. The red team review still runs; the security-analyst supplement is now a stronger recommendation.

### 3. `/audit` v3.1.0 Modifications

One focused change:

#### 3a. Step 2 -- Secure Review Composability

Before the existing security scan dispatch, add a Glob check:

Glob for `~/.claude/skills/secure-review/SKILL.md`.

**If found:** Replace the existing built-in security scan with a dispatch to `/secure-review`. The Task subagent reads and executes the secure-review skill with the same scope as the audit (plan/code/full mapped to changes/full). The subagent writes its output to `./plans/audit-[timestamp].security.md` (the standard audit naming convention), so Step 5 (Synthesis) requires no filename changes.

**If not found:** Use the existing built-in security scan unchanged. This preserves exact backward compatibility.

**Scope mapping (audit scope to secure-review scope):**
- audit `plan` -> secure-review not applicable (plans are not code). Use existing built-in scan.
- audit `code` -> secure-review `changes`
- audit `full` -> secure-review `full`

Note: When scope is `plan`, always use the built-in scan regardless of `/secure-review` deployment, because `/secure-review` scans code, not plan documents.

### 4. Security Maturity Level Schema

The maturity level is a single string field in `.claude/settings.json` or `.claude/settings.local.json`:

```json
{
  "security_maturity": "advisory"
}
```

Valid values: `"advisory"` (L1, default), `"enforced"` (L2), `"audited"` (L3).

Invalid or missing values default to `"advisory"`. This ensures zero friction for existing projects that have no `security_maturity` setting.

**Read precedence:** `.claude/settings.local.json` overrides `.claude/settings.json`. If neither exists or neither contains the field, default to `"advisory"`.

**No schema file is created.** The maturity level is a simple string with three valid values. It is documented inline in the `/ship` skill and in CLAUDE.md (Phase C). No JSON schema validator is needed for a single-field enum.

## Interfaces / Schema Changes

### Skill Frontmatter Changes

| Skill | Field | From | To |
|-------|-------|------|-----|
| `skills/ship/SKILL.md` | `version` | `3.4.0` | `3.5.0` |
| `skills/architect/SKILL.md` | `version` | `3.0.0` | `3.1.0` |
| `skills/audit/SKILL.md` | `version` | `3.0.0` | `3.1.0` |

### /ship Input Changes

| Change | Type | Detail |
|--------|------|--------|
| `--security-override "reason"` | New optional flag | Downgrades security BLOCKED to PASS_WITH_NOTES. Requires quoted reason string. |

Existing `/ship $ARGUMENTS` interface is unchanged. The plan path remains the primary argument.

### /ship Result Evaluation Matrix Changes

Column added: **Secure Review** (4d). Values: PASS, PASS_WITH_NOTES, BLOCKED, not-run. "not-run" is treated as PASS at L1.

### /architect Step 0 Output Changes

New line added when threat-model-gate is detected. No input changes. No output format changes.

### /audit Step 2 Behavioral Change

When `/secure-review` is deployed, Step 2 delegates to it. The output is written to the standard `audit-[timestamp].security.md` filename (audit naming convention). Step 5 (Synthesis) requires no changes -- it reads the same filename regardless of whether the scan was built-in or delegated to `/secure-review`.

## Data Migration

No data migration required. All changes are additive. Existing plan artifacts, reports, and archives are unaffected.

## Rollout Plan

### Pre-conditions

- Phase A skills deployed: `ls ~/.claude/skills/{secrets-scan,secure-review,dependency-audit,compliance-check,threat-model-gate}/SKILL.md`
- All Phase A skills pass validation: `python3 generators/validate_skill.py skills/<name>/SKILL.md` for each
- Test suite passes: `bash generators/test_skill_generator.sh`

### Deployment

1. Modify three skill files (see Task Breakdown)
2. Validate all three
3. Run test suite
4. Deploy: `./scripts/deploy.sh`
5. Manual testing (see Test Plan)
6. Commit

### Rollback

Revert the three modified skill files to their previous versions via git:

```bash
git checkout HEAD~1 -- skills/ship/SKILL.md skills/architect/SKILL.md skills/audit/SKILL.md
./scripts/deploy.sh
```

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| `/ship` modification breaks existing workflows | Medium | High | All security gates are conditional on skill deployment AND maturity level. At L1 (default), `/ship` behavior is unchanged if security skills are missing. Step 0 fail-fast logic is additive -- existing checks are not modified. |
| Secrets scan Task subagent adds latency to Step 0 | Medium | Low | Secrets scan is grep-based and fast. It runs after agent checks, so if agent checks fail fast, the scan never runs. The one-time latency at Step 0 is acceptable for the security benefit. |
| Secure review in Step 4 adds wall-clock time | Low | Low | It runs in parallel with code review, tests, and QA. No additional wall-clock time unless secure-review is slower than the slowest existing check. |
| Dependency audit in Step 6 slows commit gate | Medium | Medium | Only runs if new deps were added (plan mentions package manifest changes). Most `/ship` runs will skip this check entirely. |
| `--security-override` parsing fails on edge cases | Medium | Medium | Parsing extracts everything after `--security-override ` as the reason string. Edge case: reason contains quotes. Mitigation: use single-quoted HEREDOC for the argument extraction, as done in existing Step 6 commit messages. |
| /architect threat-model heuristic false positives | Low | Low | Heuristic is keyword-based and intentionally broad. A false positive adds a `## Security Requirements` prompt to a non-security plan -- this is low-cost (architect can skip the section) and high-safety (security plans always get the prompt). |
| /audit secure-review scope mapping for "plan" | Low | Medium | When scope is `plan`, always use built-in scan regardless of `/secure-review` deployment. `/secure-review` scans code, not plans. This is documented explicitly in the skill. |
| Maturity level config read fails (malformed JSON) | Low | Low | Parse with error handling. If `.claude/settings.json` is malformed, default to L1 with a warning. Never block `/ship` on a config parse error. |
| Test suite may need updates for renamed skill references | Medium | Medium | Test suite references "dream" in some tests. The suite already passes at 33 tests. Verify no tests break from the architect version bump. |

## Test Plan

### Validation Commands

```bash
# Validate all modified skills
python3 /Users/imurphy/projects/claude-devkit/generators/validate_skill.py /Users/imurphy/projects/claude-devkit/skills/ship/SKILL.md
python3 /Users/imurphy/projects/claude-devkit/generators/validate_skill.py /Users/imurphy/projects/claude-devkit/skills/architect/SKILL.md
python3 /Users/imurphy/projects/claude-devkit/generators/validate_skill.py /Users/imurphy/projects/claude-devkit/skills/audit/SKILL.md

# Run full test suite
cd /Users/imurphy/projects/claude-devkit && bash generators/test_skill_generator.sh

# Deploy and verify
cd /Users/imurphy/projects/claude-devkit && ./scripts/deploy.sh
ls -la ~/.claude/skills/ship/SKILL.md
ls -la ~/.claude/skills/architect/SKILL.md
ls -la ~/.claude/skills/audit/SKILL.md
```

### Manual Testing

1. **`/ship` with security gates (L1, skills deployed):** Run `/ship plans/<test-plan>.md` with security skills deployed and no `security_maturity` setting. Verify: secrets scan runs at Step 0 (blocks on BLOCKED -- special case), secure-review runs parallel in Step 4, secure-review/dependency-audit BLOCKED verdicts produce prominent warnings but are auto-downgraded to PASS_WITH_NOTES (L1 advisory -- non-blocking for non-secrets gates).

2. **`/ship` with security gates (L2, skills deployed):** Set `"security_maturity": "enforced"` in `.claude/settings.json`. Run `/ship`. Verify: BLOCKED verdicts from security scans prevent commit.

3. **`/ship` with `--security-override`:** Run `/ship plans/<plan>.md --security-override "False positive: test fixture"`. Verify: BLOCKED from security scan is downgraded to PASS_WITH_NOTES. Override reason appears in commit message.

4. **`/ship` without security skills (L1):** Undeploy security skills (`rm -rf ~/.claude/skills/{secrets-scan,secure-review,dependency-audit}`). Run `/ship`. Verify: completes normally with "security skill not deployed" log notes. No errors, no blocks.

5. **`/ship` without security skills (L2):** Set enforced maturity level. Undeploy security skills. Run `/ship`. Verify: aborts at Step 0 with message listing which skills need deployment and the exact deploy command.

6. **`/architect` with threat-model-gate:** Run `/architect add user authentication`. Verify: threat-model-gate detection in Step 0. Architect prompt includes threat modeling requirements (Step 2). Security-analyst invocation recommended (Step 3a).

7. **`/architect` without threat-model-gate:** Undeploy threat-model-gate. Run `/architect add CSS animation`. Verify: no threat model prompt injection. Standard planning workflow.

8. **`/architect` with non-security topic:** With threat-model-gate deployed, run `/architect add loading spinner`. Verify: threat-model-gate detected in Step 0 but heuristic does NOT inject threat model requirements (no security keywords in arguments).

9. **`/audit` with `/secure-review` deployed:** Run `/audit code`. Verify: security scan delegates to `/secure-review` (deeper analysis). Output written to `audit-[timestamp].security.md` (standard audit naming convention).

10. **`/audit` without `/secure-review`:** Undeploy `/secure-review`. Run `/audit code`. Verify: uses built-in security scan (backward compatible). Output references `audit-[timestamp].security.md`.

11. **`/audit` with scope "plan":** With `/secure-review` deployed, run `/audit plan plans/<plan>.md`. Verify: uses built-in plan security scan, NOT `/secure-review` (plans are not code).

### Exact Test Command

```bash
cd /Users/imurphy/projects/claude-devkit && bash generators/test_skill_generator.sh
```

## Acceptance Criteria

- [ ] `skills/ship/SKILL.md` updated to v3.5.0 with all security gates
- [ ] `skills/architect/SKILL.md` updated to v3.1.0 with threat-model-gate awareness
- [ ] `skills/audit/SKILL.md` updated to v3.1.0 with secure-review composability
- [ ] All three modified skills pass `validate-skill` with zero errors
- [ ] Full test suite passes (`bash generators/test_skill_generator.sh`)
- [ ] `/ship` runs normally when security skills are NOT deployed (backward compatibility at L1)
- [ ] `/ship` runs security gates when security skills ARE deployed (L1: advisory, L2: enforced)
- [ ] `/ship` aborts at Step 0 when L2/L3 maturity is set and security skills are missing
- [ ] `/ship` secrets scan gate delegates to `/secrets-scan` via Task subagent (no inline patterns)
- [ ] `/ship` secure-review runs parallel with code review, tests, and QA in Step 4
- [ ] `/ship` dependency-audit runs before commit in Step 6 (only when new deps added)
- [ ] `/ship --security-override "reason"` downgrades security BLOCKED to PASS_WITH_NOTES
- [ ] Override reason logged in commit message footer
- [ ] `/architect` detects threat-model-gate deployment in Step 0
- [ ] `/architect` injects threat modeling requirements for security-sensitive plans
- [ ] `/architect` does NOT inject threat modeling for non-security plans
- [ ] `/architect` recommends (not requires) security-analyst invocation at Step 3a
- [ ] `/audit` delegates security scan to `/secure-review` when deployed (code/full scope)
- [ ] `/audit` uses built-in security scan when `/secure-review` not deployed (backward compatible)
- [ ] `/audit` uses built-in scan for "plan" scope regardless of `/secure-review` deployment
- [ ] All skills deploy successfully via `./scripts/deploy.sh`

## Task Breakdown

### Files to Modify

| # | File | Change | Version |
|---|------|--------|---------|
| 1 | `skills/ship/SKILL.md` | Add security pre-flight (Step 0), secure-review parallel verification (Step 4), dependency audit (Step 6), --security-override flag, maturity level config. Bump version. | 3.4.0 -> 3.5.0 |
| 2 | `skills/architect/SKILL.md` | Add threat-model-gate detection (Step 0), threat model injection (Step 2), strengthen security-analyst recommendation (Step 3a). Bump version. | 3.0.0 -> 3.1.0 |
| 3 | `skills/audit/SKILL.md` | Add /secure-review composability (Step 2). Delegated scan writes to `audit-[timestamp].security.md` (standard naming) so Step 5 requires no changes. Bump version. | 3.0.0 -> 3.1.0 |

### Files NOT Modified

No new files are created. No other existing files are modified. Agent templates and CLAUDE.md updates are Phase C scope.

## Work Groups

### Work Group B1: /ship Security Integration
- `skills/ship/SKILL.md`

### Work Group B2: /architect Threat-Model Integration
- `skills/architect/SKILL.md`

### Work Group B3: /audit Secure-Review Composability
- `skills/audit/SKILL.md`

All three work groups modify non-overlapping files and can execute in parallel.

## Implementation Plan

### Phase B: Guardrails and Integration

#### Step B1: Modify /ship (Work Group B1)

1. [ ] Read `skills/ship/SKILL.md` (current v3.4.0)
2. [ ] Bump version in frontmatter from `3.4.0` to `3.5.0`
3. [ ] **Step 0 additions** -- After the existing "Run validation checks in parallel" block and before "Fail fast if any check fails", add two new blocks:

    **Block: Security Maturity Level Detection**

    Add after the existing agent glob checks and before the fail-fast block:

    ```markdown
    **Security maturity level check:**

    Tool: `Bash`, `Read`

    Read `.claude/settings.local.json` (if exists), then `.claude/settings.json` (if exists). Extract the `security_maturity` field. Local settings override project settings.

    **Note:** This block uses `python3 -c` for JSON parsing. Python 3 is available on all target platforms (macOS, Linux dev environments) and the `json` module handles edge cases (nested objects, whitespace, escaping) more reliably than regex-based alternatives. If `python3` is not available, the command silently fails and the maturity level defaults to `"advisory"` (L1) -- the safe default. This is analogous to existing `/ship` pre-flight checks that use `git` and other CLI tools.

    ```bash
    SECURITY_MATURITY="advisory"  # Default: L1

    # Read local settings first (takes precedence)
    if [ -f ".claude/settings.local.json" ]; then
      LOCAL_MATURITY=$(python3 -c "import json; d=json.load(open('.claude/settings.local.json')); print(d.get('security_maturity',''))" 2>/dev/null || echo "")
      [ -n "$LOCAL_MATURITY" ] && SECURITY_MATURITY="$LOCAL_MATURITY"
    fi

    # Fall back to project settings
    if [ "$SECURITY_MATURITY" = "advisory" ] && [ -f ".claude/settings.json" ]; then
      PROJECT_MATURITY=$(python3 -c "import json; d=json.load(open('.claude/settings.json')); print(d.get('security_maturity',''))" 2>/dev/null || echo "")
      [ -n "$PROJECT_MATURITY" ] && SECURITY_MATURITY="$PROJECT_MATURITY"
    fi

    # Validate value
    case "$SECURITY_MATURITY" in
      advisory|enforced|audited) ;;
      *) echo "Warning: Invalid security_maturity value '$SECURITY_MATURITY'. Defaulting to 'advisory'."
         SECURITY_MATURITY="advisory" ;;
    esac

    echo "Security maturity level: $SECURITY_MATURITY"
    ```

    If `$SECURITY_MATURITY` is `enforced` or `audited`:

    Tool: `Glob`

    Check for required security skills:
    - Glob `~/.claude/skills/secrets-scan/SKILL.md`
    - Glob `~/.claude/skills/secure-review/SKILL.md`
    - Glob `~/.claude/skills/dependency-audit/SKILL.md`

    If ANY are missing, stop immediately:
    "Security maturity level '$SECURITY_MATURITY' requires all security skills to be deployed.
    Missing skills:
    - [list missing skills]

    Deploy with:
      cd ~/projects/claude-devkit && ./scripts/deploy.sh secrets-scan secure-review dependency-audit"
    ```

    **Block: Secrets Scan Gate**

    Add after the maturity level check:

    ```markdown
    **Secrets scan gate (pre-flight):**

    Tool: `Glob`

    Glob for `~/.claude/skills/secrets-scan/SKILL.md`

    **If found:**

    Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

    Prompt:
    "You are running a pre-commit secrets scan as part of the /ship pre-flight check.

    Read the secrets-scan skill definition at `~/.claude/skills/secrets-scan/SKILL.md`.
    Execute it with scope `all` against the current repository working directory.

    Report your verdict: PASS or BLOCKED.
    If BLOCKED, list the confirmed secret types and file locations (NO actual secret values).
    If PASS, report 'No secrets detected in working directory.'"

    **If secrets scan returns BLOCKED:**
    Secrets-scan BLOCKED blocks at ALL maturity levels (including L1). Committed secrets cannot be un-committed and require rotation.
    - If `--security-override` flag is set: Log override reason. Downgrade to PASS_WITH_NOTES. Continue.
      Output: "Secrets scan BLOCKED — overridden: [reason]. Logged for audit trail."
    - If `--security-override` flag is NOT set: Stop workflow.
      Output: "Secrets detected in working directory. Remove before shipping.
      If this is a false positive, re-run with: /ship $ARGUMENTS --security-override \"reason\""

    **If not found:**
    - If L1 (advisory): Log: "Security note: secrets-scan skill not deployed. Consider deploying for pre-commit secret detection."
    - If L2/L3: Already caught by maturity level check above (will not reach here).
    ```

4. [ ] **Step 4 additions** -- Add 4d secure review as a parallel verification track. Insert after the existing 4c QA validation section and before the "Result evaluation" section:

    ```markdown
    ### 4d — Secure review (conditional)

    Tool: `Glob`

    Glob for `~/.claude/skills/secure-review/SKILL.md`

    **If found:**

    Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`

    Prompt:
    "You are running a semantic security review as part of the /ship verification step.

    Read the secure-review skill definition at `~/.claude/skills/secure-review/SKILL.md`.
    Execute its scanning workflow (vulnerability, data flow, auth/authz scans) against the
    files modified in this implementation.

    Scope: `changes` (uncommitted modifications in the working directory).

    Write your security review summary to `./plans/[name].secure-review.md` with the
    standard secure-review output format including verdict (PASS / PASS_WITH_NOTES / BLOCKED),
    severity-rated findings, and redacted secrets (if any).

    CRITICAL: Never include actual secret values in your report. Redact to first 4 / last 4 characters."

    **If not found:**
    - Log: "Security note: secure-review skill not deployed. Security code review skipped."
    - Set secure review verdict to "not-run"
    ```

5. [ ] **Step 4 result evaluation** -- Replace the existing result evaluation matrix with the expanded version that includes secure review:

    ```markdown
    ### Result evaluation

    Coordinator reads all outputs (three or four, depending on secure-review deployment) and evaluates.

    **The result evaluation matrix is maturity-level-aware:**

    **At L1 (advisory):**

    | Code Review | Tests | QA | Secure Review | Action |
    |---|---|---|---|---|
    | PASS | Pass (exit 0) | PASS or PASS_WITH_NOTES | PASS / PASS_WITH_NOTES / BLOCKED / not-run | Proceed to Step 6. If BLOCKED: log prominent warning ("Security review found critical issues"), auto-downgrade to PASS_WITH_NOTES. |
    | REVISION_NEEDED | Any | Any | Any | Enter Step 5 (revision loop) |
    | FAIL | Any | Any | Any | Stop workflow |
    | Any | Fail (non-zero) | Any | Any | Stop workflow |
    | PASS | Pass | FAIL | Any | Stop workflow |

    At L1, secure-review BLOCKED is reported but does not stop the workflow (parent plan L1 definition).

    **At L2/L3 (enforced/audited):**

    | Code Review | Tests | QA | Secure Review | Action |
    |---|---|---|---|---|
    | PASS | Pass (exit 0) | PASS or PASS_WITH_NOTES | PASS or PASS_WITH_NOTES or not-run | Proceed to Step 6 (commit) |
    | PASS | Pass (exit 0) | PASS or PASS_WITH_NOTES | BLOCKED | If --security-override: Proceed to Step 6 (log override). Else: Stop workflow. |
    | REVISION_NEEDED | Any | Any | Any (not BLOCKED) | Enter Step 5 (revision loop) |
    | REVISION_NEEDED | Any | Any | BLOCKED | Enter Step 5 (revision loop). Include security findings in coder instructions. Coders fix both code review and security issues. Re-run Step 4 after revision. |
    | FAIL | Any | Any | Any | Stop workflow |
    | Any | Fail (non-zero) | Any | Any | Stop workflow |
    | PASS | Pass | FAIL | Any | Stop workflow |
    | Any | Any | Any | BLOCKED (no override, revision loop exhausted) | Stop workflow |

    If stopping due to secure review BLOCKED (L2/L3, post-revision):
    - "Secure review BLOCKED after revision loop. See `./plans/[name].secure-review.md`. Fix security findings or re-run with --security-override."

    If proceeding with security override (L2/L3):
    - Log: "Secure review BLOCKED — overridden: [reason]. Proceeding with PASS_WITH_NOTES."

    If auto-downgrading at L1:
    - Log: "Secure review BLOCKED (L1 advisory — non-blocking). Review findings: `./plans/[name].secure-review.md`."
    ```

6. [ ] **Step 4 parallel dispatch note** -- Update the Step 4 header to mention 4d:

    Change: "Run these verification tasks in parallel:"
    To: "Run these verification tasks in parallel (3 or 4 tasks depending on security skill deployment):"

7. [ ] **Parse --security-override from $ARGUMENTS** -- Insert as the **very first action** in Step 0, BEFORE run ID generation, BEFORE any other use of `$ARGUMENTS`. This must precede all existing Step 0 logic to prevent the flag from leaking into plan path parsing or subagent prompts.

    ```markdown
    **Parse --security-override flag (MUST be first action in Step 0):**

    If `$ARGUMENTS` contains `--security-override`:
    - Extract the reason string (quoted text after `--security-override`)
    - Store as `$SECURITY_OVERRIDE_REASON`
    - Remove the flag and reason from `$ARGUMENTS` before using it as the plan path
    - After extraction, `$ARGUMENTS` contains ONLY the plan path for all subsequent steps
    - Log: "Security override active. Reason: $SECURITY_OVERRIDE_REASON"

    If `$ARGUMENTS` does not contain `--security-override`:
    - Set `$SECURITY_OVERRIDE_REASON` to empty
    ```

8. [ ] **Step 6 additions** -- Before the existing commit logic (item 1: "If WIP commits exist..."), add:

    ```markdown
    **Dependency audit gate (conditional):**

    Tool: `Glob`

    Glob for `~/.claude/skills/dependency-audit/SKILL.md`

    **If found:**

    Detect actual dependency changes by diffing manifest files against HEAD:

    Tool: `Bash`

    ```bash
    # Check each known manifest file for dependency-section changes
    for manifest in package.json requirements.txt pyproject.toml Pipfile go.mod Cargo.toml pom.xml Gemfile; do
      if [ -f "$manifest" ]; then
        git diff HEAD -- "$manifest" 2>/dev/null
      fi
    done
    ```

    If any manifest file diff shows additions in dependency sections (new packages, version changes):

    **If dependency changes detected:**

    Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

    Prompt:
    "You are running a dependency audit as part of the /ship commit gate.

    Read the dependency-audit skill definition at `~/.claude/skills/dependency-audit/SKILL.md`.
    Execute it against the current project.

    Report your verdict: PASS, PASS_WITH_NOTES, INCOMPLETE, or BLOCKED.
    If BLOCKED, list the Critical CVE findings.
    Write your report to `./plans/[name].dependency-audit.md`."

    **If dependency audit returns BLOCKED:**
    - At L1 (advisory): Log prominent warning. Auto-downgrade to PASS_WITH_NOTES. Continue.
      Output: "Dependency audit BLOCKED (L1 advisory — non-blocking). Review findings: `./plans/[name].dependency-audit.md`."
    - At L2/L3: If `--security-override`: Downgrade to PASS_WITH_NOTES. Log override reason. Else: Stop workflow.
      Output: "Dependency audit BLOCKED. Critical vulnerabilities found. See `./plans/[name].dependency-audit.md`."

    **If dependency audit returns INCOMPLETE:**
    - Log: "Dependency audit INCOMPLETE — no scanner available for this ecosystem. Install the appropriate scanner for full CVE scanning."
    - Continue (INCOMPLETE does not block at any level).

    **If no dependency changes detected:** Skip dependency audit.
    - Log: "No dependency changes detected (manifest files unchanged vs HEAD). Skipping dependency audit."

    **If not found:**
    - Log: "Security note: dependency-audit skill not deployed. Dependency audit skipped."
    ```

9. [ ] **Step 6 commit message** -- Update the commit message template to include security override information when applicable:

    ```markdown
    If `--security-override` was used, append to commit message:
    ```
    Security-Override: $SECURITY_OVERRIDE_REASON
    ```
    ```

10. [ ] **Step 6 archive** -- Update the archive command to also move security review and dependency audit artifacts:

    ```markdown
    Then, archive security review and dependency audit artifacts if they exist:
    ```bash
    if [ -f "./plans/[name].secure-review.md" ]; then
      mv "./plans/[name].secure-review.md" "./plans/archive/[name]/"
    fi
    if [ -f "./plans/[name].dependency-audit.md" ]; then
      mv "./plans/[name].dependency-audit.md" "./plans/archive/[name]/"
    fi
    ```
    ```

11. [ ] Validate: `python3 /Users/imurphy/projects/claude-devkit/generators/validate_skill.py /Users/imurphy/projects/claude-devkit/skills/ship/SKILL.md`

#### Step B2: Modify /architect (Work Group B2)

12. [ ] Read `skills/architect/SKILL.md` (current v3.0.0)
13. [ ] Bump version in frontmatter from `3.0.0` to `3.1.0`
14. [ ] **Step 0 additions** -- Add a fourth Glob to the existing parallel agent pre-check. After the existing three globs (senior-architect, code-reviewer, security-analyst), add:

    ```markdown
    - Pattern 4: `~/.claude/skills/threat-model-gate/SKILL.md`

    **If threat-model-gate found:**
    - Output: "Threat model gate active. Security-related plans will include threat modeling requirements."

    **If threat-model-gate not found:**
    - No output (threat-model-gate is optional at all maturity levels).
    ```

15. [ ] **Step 2 modification** -- After the existing architect prompt block ("Analyze the codebase and draft a Technical Implementation Plan for: $ARGUMENTS..."), add a conditional injection:

    ```markdown
    **If threat-model-gate was found in Step 0 AND $ARGUMENTS appears to involve security-sensitive functionality:**

    Security-sensitive heuristic: $ARGUMENTS (case-insensitive) contains any of:
    - Identity/Auth: auth, authentication, authorization, login, password, token, session, oauth, oidc, saml, api key, secret, credential, identity, mfa, 2fa, rbac, acl, permission, role, privilege, security
    - Cryptography/Network: encrypt, decrypt, certificate, tls, ssl, firewall, cors, proxy, redirect, webhook, dns, url
    - Data/Compliance: pii, gdpr, hipaa, compliance, fips, fedramp, export, import, backup, database, query, sql
    - File/Process: upload, download, file, path, exec, shell, command, subprocess, eval
    - Payment: payment, stripe, billing, credit card, bank

    **If security-sensitive:** Append to the architect Task prompt:

    "SECURITY CONTEXT: This plan involves security-sensitive functionality. You MUST include a `## Security Requirements` section addressing:
    - Assets at risk (data classification: public/internal/confidential/restricted)
    - Trust boundaries (where does trust change?)
    - STRIDE analysis (Spoofing, Tampering, Repudiation, Information Disclosure, DoS, Elevation of Privilege)
    - Proposed mitigations for each identified threat

    Refer to the threat-model-gate skill at `~/.claude/skills/threat-model-gate/SKILL.md` for the full checklist and security requirements template."

    **If not security-sensitive:** Do not append. Standard planning prompt only.
    ```

16. [ ] **Step 3a modification** -- Change the security-analyst invocation paragraph. Replace the existing text:

    From:
    ```
    **Optional (security-specific plans only):** If `.claude/agents/security-analyst.md` was found in Step 0 AND the plan subject is security-related (e.g., authentication, authorization, cryptography, network), additionally invoke the security-analyst agent via `Task` and append its STRIDE analysis to the redteam artifact as a supplemental section. The Verdict from the primary Task subagent governs the pass/fail decision.
    ```

    To:
    ```
    **Recommended (when threat-model-gate is deployed and plan subject is security-related):** If `.claude/agents/security-analyst.md` was found in Step 0 AND `~/.claude/skills/threat-model-gate/SKILL.md` was found in Step 0 AND the plan subject is security-related (e.g., authentication, authorization, cryptography, network, data handling), additionally invoke the security-analyst agent via `Task` and append its STRIDE analysis to the redteam artifact as a supplemental section. When threat-model-gate is deployed, this invocation is recommended to ensure plans with a `## Security Requirements` section receive expert validation. The Verdict from the primary Task subagent governs the pass/fail decision.
    ```

17. [ ] Validate: `python3 /Users/imurphy/projects/claude-devkit/generators/validate_skill.py /Users/imurphy/projects/claude-devkit/skills/architect/SKILL.md`

#### Step B3: Modify /audit (Work Group B3)

18. [ ] Read `skills/audit/SKILL.md` (current v3.0.0)
19. [ ] Bump version in frontmatter from `3.0.0` to `3.1.0`
20. [ ] **Step 2 modification** -- Add secure-review composability check at the top of Step 2, before the existing "Pre-check" for security-analyst agent:

    ```markdown
    **Secure-review composability check:**

    Tool: `Glob`

    Glob for `~/.claude/skills/secure-review/SKILL.md`

    **If found AND scope is NOT "plan":**
    - Output: "Using /secure-review for deep security analysis (composability mode)."
    - Dispatch `/secure-review` instead of the built-in security scan.

    Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`

    Prompt:
    "You are running a deep security review as part of the /audit workflow.

    Read the secure-review skill definition at `~/.claude/skills/secure-review/SKILL.md`.
    Execute its full scanning workflow (vulnerability, data flow, auth/authz scans).

    Scope: [map audit scope to secure-review scope: 'code' -> 'changes', 'full' -> 'full']

    Write your findings to `./plans/audit-[timestamp].security.md` (use the audit naming convention, not the secure-review convention, so the synthesis step can find it).

    Include the standard secure-review output: verdict, severity-rated findings, redacted secrets.

    CRITICAL: Never include actual secret values. Redact to first 4 / last 4 characters."

    Skip the existing built-in security scan below. Proceed to Step 3 (Performance scan).

    **If not found OR scope is "plan":**
    - If not found: Output: "secure-review skill not deployed. Using built-in security scan."
    - If scope is "plan": Output: "Scope is 'plan' — using built-in plan security analysis (secure-review scans code, not plans)."
    - Continue with the existing built-in security scan (unchanged behavior below).
    ```

21. [ ] Validate: `python3 /Users/imurphy/projects/claude-devkit/generators/validate_skill.py /Users/imurphy/projects/claude-devkit/skills/audit/SKILL.md`

#### Step B4: Phase B Verification

22. [ ] Run all three validations in parallel:
    ```bash
    python3 /Users/imurphy/projects/claude-devkit/generators/validate_skill.py /Users/imurphy/projects/claude-devkit/skills/ship/SKILL.md
    python3 /Users/imurphy/projects/claude-devkit/generators/validate_skill.py /Users/imurphy/projects/claude-devkit/skills/architect/SKILL.md
    python3 /Users/imurphy/projects/claude-devkit/generators/validate_skill.py /Users/imurphy/projects/claude-devkit/skills/audit/SKILL.md
    ```

23. [ ] Run full test suite:
    ```bash
    cd /Users/imurphy/projects/claude-devkit && bash generators/test_skill_generator.sh
    ```

24. [ ] Deploy updated skills:
    ```bash
    cd /Users/imurphy/projects/claude-devkit && ./scripts/deploy.sh
    ```

25. [ ] Verify deployment:
    ```bash
    ls -la ~/.claude/skills/ship/SKILL.md
    ls -la ~/.claude/skills/architect/SKILL.md
    ls -la ~/.claude/skills/audit/SKILL.md
    ```

26. [ ] Run manual tests 1-11 from Test Plan

27. [ ] Commit Phase B:
    ```bash
    git add skills/ship/SKILL.md skills/architect/SKILL.md skills/audit/SKILL.md
    git commit -m "feat(skills): embed security guardrails in /ship, /architect, /audit (Phase B)

    Ship v3.5.0: secrets scan gate (Step 0), secure-review parallel verification (Step 4d),
    dependency audit pre-commit (Step 6), security maturity levels (L1/L2/L3),
    --security-override flag. All gates conditional on skill deployment.

    Architect v3.1.0: threat-model-gate detection (Step 0), security requirements injection
    for security-sensitive plans (Step 2), security-analyst recommendation upgrade (Step 3a).

    Audit v3.1.0: /secure-review composability (Step 2) -- delegates security scan to
    /secure-review when deployed, falls back to built-in scan otherwise.

    Phase B of agentic-sdlc-security-skills plan.
    Implements: ./plans/security-guardrails-phase-b.md

    Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
    ```

## Context Alignment

### CLAUDE.md Patterns Followed

- **Three-tier structure:** All modifications are in `skills/` (Tier 1 core). No new files created.
- **Skill archetypes:** Each modified skill retains its archetype (ship: Pipeline, architect: Coordinator, audit: Scan). No archetype changes.
- **v2.0.0 patterns (all 11):** Numbered steps preserved. Tool declarations added for new blocks. Verdict gates extended (not replaced). Timestamped artifacts maintained. Bounded iterations unchanged. Model selection preserved. Scope parameters extended (--security-override). Archive on success extended for security artifacts.
- **Deploy pattern:** Edit `skills/*/SKILL.md` -> validate -> deploy via `deploy.sh`
- **Composition over duplication:** /ship delegates to /secrets-scan (no inline patterns). /audit delegates to /secure-review (composable building block). This follows the anti-pattern guidance from the embedding-security-in-agentic-sdlc standard.
- **Coordinator pattern:** /ship remains a coordinator -- it dispatches security work to Task subagents, checks verdicts, and gates progression. It does not execute security scans directly.
- **Backward compatibility:** All changes are conditional. Default maturity level is L1 (advisory). Missing security skills produce log notes, not errors (at L1).

### Prior Plans Referenced

- **agentic-sdlc-security-skills.md (Rev 3)** -- Parent plan. Phase B specification defines the exact modifications to /ship, /architect (was /dream), and /audit. This plan is the detailed implementation blueprint for that specification.
- **embedding-security-in-agentic-sdlc.md** -- Proposed standard for security controls. Maturity levels, severity taxonomy, five intervention points, and anti-patterns (especially "do not duplicate security logic across tools") directly inform this plan's design decisions.
- **secure-review-remediation.md** -- Bumped /ship to v3.4.0. This plan bumps to v3.5.0 (correct next increment).
- **ship-always-worktree.md** -- Established universal worktree isolation. Security gates added here are orthogonal to worktree mechanics and do not modify worktree behavior.
- **dream-auto-commit.md** -- Established auto-commit pattern for /architect. This plan does not modify the auto-commit behavior.

### Deviations from Established Patterns

1. **Conditional security gates (vs. hard-required gates):** Existing /ship gates (code review, tests, QA) are hard-required -- /ship will not run without a coder, code-reviewer, and qa-engineer agent. Security gates are soft-required at L1 and hard-required at L2/L3. **Justification:** Security skills are new. Hard-requiring them at the default maturity level would break every existing /ship invocation. The maturity level graduation path provides a controlled ramp to mandatory enforcement.

2. **Security override flag modifies verdict interpretation:** The `--security-override` flag changes how BLOCKED verdicts from security scans are interpreted, which is a novel interaction not present in existing /ship logic. **Justification:** False positives in security scanning are inevitable. Without an escape valve, teams will undeploy security skills entirely, which is worse than having an auditable override. The override requires a documented reason and is logged in the commit message.

3. **Heuristic-based prompt injection (architect Step 2):** The threat model injection uses keyword matching to determine if a plan is security-sensitive. This is a heuristic, not a precise classification. **Justification:** False positives (adding threat model prompt to a non-security plan) have low cost -- the architect can skip the section. False negatives (missing a security plan) have high cost -- no threat model. The heuristic is intentionally broad.

4. **L1 secrets-scan BLOCKED blocks at all levels (narrower than parent plan L1 definition):** The parent plan defines L1 as "BLOCKED verdicts are reported but do not prevent commit." This plan treats secrets detection as an exception: a BLOCKED verdict from `/secrets-scan` at L1 halts `/ship` because committed secrets cannot be easily revoked. For `/secure-review` and `/dependency-audit`, BLOCKED at L1 follows the parent plan definition (reported as PASS_WITH_NOTES, not blocking). **Justification:** Secrets in git history are a permanent exposure. Unlike code vulnerabilities (fixable in the next commit), committed secrets require rotation -- a costly remediation that justifies blocking even at advisory maturity. The `--security-override` escape valve still applies if the detection is a false positive.

## Verification

- The three modified skills pass `validate-skill`
- The full test suite (`test_skill_generator.sh`) passes with all existing tests
- `/ship` backward compatibility confirmed (works without security skills at L1)
- `/ship` security gates confirmed (works with security skills deployed)
- `/ship` maturity level enforcement confirmed (L2 aborts when skills missing)
- `/ship` override confirmed (`--security-override` downgrades BLOCKED)
- `/architect` threat model injection confirmed (security-sensitive topics get the prompt)
- `/audit` composability confirmed (delegates to `/secure-review` when deployed)

## Next Steps

1. **Execute Phase B** -- `/ship plans/security-guardrails-phase-b.md` (this plan)
2. **Validate implementation** -- Run all acceptance criteria checks
3. **Manual testing** -- Run manual tests 1-11 in a real Claude Code session
4. **Phase C planning** -- After Phase B is validated, plan Phase C (documentation and templates):
   - Update CLAUDE.md skill registry with new versions
   - Add security awareness sections to agent templates
   - Create CLAUDE.md security section template
   - Update agent-patterns.json with security variants

## Plan Metadata

- **Plan File:** `./plans/security-guardrails-phase-b.md`
- **Affected Components:** `skills/ship/SKILL.md`, `skills/architect/SKILL.md`, `skills/audit/SKILL.md`
- **Validation:** `python3 generators/validate_skill.py skills/{ship,architect,audit}/SKILL.md && bash generators/test_skill_generator.sh`
- **Parent Plan:** `./plans/agentic-sdlc-security-skills.md` (Phase B)

<!-- Context Metadata
discovered_at: 2026-03-26T20:30:00Z
claude_md_exists: true
recent_plans_consulted: agentic-sdlc-security-skills.md, secure-review-remediation.md, embedding-security-in-agentic-sdlc.md
archived_plans_consulted: agentic-sdlc-security-skills/, secure-review/
-->

## Status: APPROVED
