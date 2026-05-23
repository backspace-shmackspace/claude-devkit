# Plan: `/fix` Skill for Targeted Finding Remediation

## Status: APPROVED

## Revision Log

| Rev | Date | Trigger | Summary |
|-----|------|---------|---------|
| 0 | 2026-05-23 | Stub | Design intent, workflow, inputs, comparison table |
| 1 | 2026-05-23 | Full plan draft | Expanded into self-contained Technical Implementation Plan with security requirements, context alignment, design decisions, task breakdown, and test plan |
| 2 | 2026-05-23 | Review findings | Address Major/required-edit findings from red team (F-01, F-02, F-03), librarian (required edits 1-2), and feasibility (M-01, M-02). Changes: (1) Add lightweight secret-pattern grep after Step 2 (F-01). (2) Clarify test insertion points before cleanup blocks; numbers 57 and 28-29 confirmed correct (F-02). (3) Add `git diff --name-only` scope validation after Step 2 (F-03). (4) Move Pattern 5 from Followed to Deviations table (librarian req 1). (5) Add timestamp suffix to artifact names to prevent collision (librarian req 2). (6) Change frontmatter to single-line description (feasibility M-01). (7) Change all step headers to em-dashes (feasibility M-02). |

## Context

The `/ship` workflow produces review artifacts (code review, QA report, secure review) with
rated findings. When a finding needs remediation -- especially security findings like H-01
(command injection) from past runs -- the current options are:

1. **Full /architect -> /ship** -- writes a plan, creates worktrees, runs full parallel
   verification. Overkill for a one-line fix.
2. **Manual fix + commit** -- no code review, no security re-scan, no traceability.

`/fix` fills the gap: a lightweight, rigorous workflow that takes a specific finding,
applies a targeted fix, runs focused verification, and commits with traceability back
to the original finding.

The `/audit` skill also produces artifacts with severity-rated findings
(`./plans/audit-[timestamp].security.md`, `./plans/audit-[timestamp].performance.md`).
`/fix` supports remediation of findings from both `/ship` and `/audit` artifacts.

## Goals

1. Create a new `/fix` skill at `skills/fix/SKILL.md` following the Pipeline archetype
2. Support artifact-driven invocation (parsed finding ID from review artifacts) and free-text fallback
3. Support findings from `/ship` artifacts (`.code-review.md`, `.secure-review.md`, `.qa-report.md`) AND `/audit` artifacts (`.security.md`, `.performance.md`)
4. Include targeted verification appropriate to finding type (security re-scan, test execution, or code review)
5. Produce traceable commits linking back to source finding and artifact
6. Update `.claude/learnings.md` when security findings are resolved
7. Integrate into existing test, deployment, and CLAUDE.md infrastructure

## Non-Goals

1. **Plan file generation** -- `/fix` does not create or require a plan file. The finding IS the specification.
2. **Worktree isolation** -- Fixes are small (typically 1-2 files). Direct edit is appropriate.
3. **Full QA report generation** -- Overkill for targeted fixes. A focused code review of the diff is sufficient.
4. **Dependency audit** -- Fixes do not add dependencies.
5. **Full secrets scan** -- A full `/secrets-scan` invocation is not warranted for targeted fixes. A lightweight grep-based pattern check on modified files is included instead (see Step 2, post-coder validation).
6. **Pattern validation against CLAUDE.md** -- Not applicable for small fixes.
7. **JSONL audit logging** -- See Design Decisions section below for rationale.
8. **Retro capture** -- The finding itself is the learning. The learnings update in Step 4 provides traceability.
9. **Batch fix mode** -- v1 fixes one finding per invocation. A future `/fix --all` mode could iterate, but that is not v1 scope.
10. **`--security-override` flag** -- Not applicable. See Design Decisions.

## Assumptions

1. Review artifacts follow the established naming conventions: `*.code-review.md`, `*.secure-review.md`, `*.qa-report.md` (from `/ship`), or `audit-[timestamp].security.md`, `audit-[timestamp].performance.md` (from `/audit`)
2. Findings in review artifacts use severity-rated IDs (e.g., H-01, M-1, CR-3, C-01, L-2)
3. The `/secure-review` skill is deployed at `~/.claude/skills/secure-review/SKILL.md` when security finding re-verification is needed (graceful degradation if not deployed)
4. Project has a test command discoverable from CLAUDE.md, plan files, or package.json/pyproject.toml
5. `.claude/agents/coder*.md` exists for coder dispatch (skill checks and fails fast if not found)
6. `python3` is available (same dependency as existing audit infrastructure)
7. Git working directory may or may not be clean when `/fix` is invoked -- the skill does not require a clean tree (unlike `/ship`)

## Design Principles

- **Finding-driven, not plan-driven** -- the finding IS the specification
- **No worktree isolation** -- fixes are small; direct edit is fine
- **Targeted verification** -- re-run only the relevant check, not the full suite
- **Code review still happens** -- but scoped to just the fix diff
- **Traceable** -- commit message links to the source finding and artifact
- **Composable** -- works with artifacts from both `/ship` and `/audit`

## Design Decisions

### D1: No JSONL audit logging

**Decision:** `/fix` does NOT emit JSONL audit events.

**Rationale:** The audit logging infrastructure exists for skills with complex multi-step workflows where timeline reconstruction, security decision tracing, and quantitative scoring provide value (`/ship` has 8 steps, `/architect` has 6 steps, `/audit` has 6 steps). `/fix` is a 5-step linear pipeline with no parallel execution, no worktree isolation, no security maturity level awareness, and no revision loop deeper than 1 retry. The overhead of `emit-audit-event.sh` state file management and event emission would add complexity disproportionate to the value. The commit message provides full traceability (finding ID, artifact path). If quantitative scoring is later extended to `/fix`, audit logging can be added in a version bump.

### D2: No `--security-override` flag

**Decision:** `/fix` does NOT support `--security-override`.

**Rationale:** The `--security-override` flag exists in `/ship` to allow teams to proceed past security gate BLOCKED verdicts at L2/L3 maturity levels with documented override reasons. `/fix` has a simpler contract: Step 3 re-runs targeted verification, and if the original finding persists or a new Critical is introduced, the workflow stops. Unlike `/ship`, which has complex multi-gate evaluation with maturity-level-aware downgrade logic, `/fix` has a binary outcome: the fix resolved the finding (PASS) or it did not (FAIL). If the re-scan finds new unrelated issues, those are separate findings -- the user should run `/fix` on them individually. There is no scenario where overriding is appropriate because the entire purpose of `/fix` is to resolve a specific finding.

### D3: `--dry-run` mode

**Decision:** `/fix` supports `--dry-run` mode.

**Rationale:** For security findings especially, users may want to see the proposed fix before committing. `--dry-run` runs Steps 0-3 (parse, scope, implement, verify) but stops before Step 4 (commit). The changes remain in the working directory for manual review. This is low-cost to implement (skip the commit step) and provides meaningful value for security-conscious workflows.

### D4: Learnings update format

**Decision:** When a security finding is resolved, `/fix` appends to the relevant entry in `.claude/learnings.md` using the existing format.

**Format:**
- If an entry for the finding already exists: append `Fixed in: <commit-sha>` to the entry
- If no entry exists: append a new entry under `## Security Patterns > ### Resolved findings`:
  ```
  - **[YYYY-MM-DD] [Finding ID]: [Title]** -- [Description]. Source: [artifact-path]. Fixed in: [commit-sha]. #security #resolved
  ```

### D5: `/audit` artifact support

**Decision:** `/fix` accepts findings from `/audit` artifacts in addition to `/ship` artifacts.

**Rationale:** `/audit` produces severity-rated findings in the same format as `/ship` security scan artifacts. The only difference is the artifact naming convention (`audit-[timestamp].security.md` vs `[name].secure-review.md`). The finding parsing logic can handle both by detecting the artifact type from the filename. Verification routing: `/audit` security findings route to `/secure-review` re-scan (same as `/ship` security findings). `/audit` performance findings route to test execution (closest available verification).

### D6: New issues found during re-verification

**Decision:** If the targeted re-verification in Step 3 finds new issues unrelated to the original finding, they are reported but do not block the commit. Only the original finding persistence or new Critical findings block.

**Rationale:** `/fix` has a single objective: resolve the specified finding. Blocking on unrelated Medium findings would make the skill unusable for incremental remediation. The commit message includes the re-verification artifact path, so new findings are discoverable. Users can run `/fix` on new findings individually.

## Proposed Design

### Inputs

```
/fix <artifact-path> [finding-id] [--dry-run]
```

Examples:
```
/fix plans/archive/maven-build-support/maven-build-support.secure-review.md H-01
/fix plans/archive/maven-build-support/maven-build-support.code-review.md M-1
/fix plans/audit-20260523T143000.security.md C-01
/fix plans/archive/audit/audit-20260523/audit-20260523.security.md H-02
/fix "command injection in find -exec in pipeline build step"  # free-text fallback
/fix plans/archive/maven-build-support/maven-build-support.secure-review.md H-01 --dry-run
```

- `artifact-path`: Path to a review artifact (`.code-review.md`, `.secure-review.md`,
  `.qa-report.md`, `.security.md`, `.performance.md`) OR a free-text description of the fix
- `finding-id`: Optional finding ID within the artifact (e.g., H-01, M-1, CR-3, C-01)
- `--dry-run`: Optional flag. If present, run Steps 0-3 but skip Step 4 (commit). Changes remain in working directory.

### Skill Frontmatter

```yaml
---
name: fix
description: Apply targeted fixes for specific findings from code reviews, security reviews, QA reports, or audit scans.
model: claude-opus-4-6
version: 1.0.0
---
```

### Workflow (5 Steps — Pipeline Archetype)

#### Step 0 — Parse and locate finding

Tool: `Read`, `Bash`

**Parse `--dry-run` flag (MUST be first action in Step 0):**

If `$ARGUMENTS` contains `--dry-run`:
- Set `$DRY_RUN` to `true`
- Remove the flag from `$ARGUMENTS` before using it as the artifact path / finding ID
- Output: "Dry-run mode: will show proposed fix and verification but will NOT commit."

If `$ARGUMENTS` does not contain `--dry-run`:
- Set `$DRY_RUN` to `false`

**Pre-flight: Verify coder agent exists:**

Tool: `Glob`

Pattern: `.claude/agents/coder*.md`

If no coder agent found, stop with:
"No coder agent found. Generate one using:
  `python3 ~/projects/claude-devkit/generators/generate_agents.py . --type coder`"

**If artifact path provided:**

Tool: `Read`

- Read the artifact file at the resolved path
- Determine finding type from artifact filename:
  - `.secure-review.md` -> security finding -> re-verify with /secure-review
  - `.code-review.md` -> correctness finding -> re-verify with code review only
  - `.qa-report.md` -> coverage finding -> re-verify with tests
  - `.security.md` (audit artifact) -> security finding -> re-verify with /secure-review
  - `.performance.md` (audit artifact) -> performance finding -> re-verify with tests
- If finding-id provided: extract that specific finding (severity, description,
  file, line, recommendation)
- If no finding-id: list all findings with IDs and severity, ask user to pick one.
  Output:
  ```
  Findings in [artifact-path]:
    H-01 (High) -- Command injection via MODULE_NAME in find -exec
    M-01 (Medium) -- Unquoted variable in tar command
    L-01 (Low) -- Shellcheck SC2086: double-quote variable
  
  Which finding to fix? [H-01/M-01/L-01]
  ```

**If free-text description:**

- Use description as the finding specification
- Ask user which verification is appropriate:
  ```
  Verification type for this fix:
    1. Security re-scan (/secure-review)
    2. Run tests
    3. Code review only
  
  Select [1/2/3]:
  ```

**Output:** Finding spec (what is wrong, where, severity, recommended fix), finding type, verification method.

**Record `$SCOPED_FILES`:** Extract the list of file paths referenced in the finding. This list is used for scope enforcement after Step 2.

#### Step 1 — Scope the fix

Tool: `Read` (direct -- coordinator does this)

Coordinator reads the finding spec and the target file(s) identified in Step 0. Determines:
- **Files to modify** (usually 1-2 files, extracted from finding location) -- store as `$SCOPED_FILES`
- **Verification command** (derived from finding type in Step 0):
  - Security finding -> invoke /secure-review on the changed files
  - Correctness finding -> run code review of the diff only
  - Coverage/performance finding -> run the project's test command
- **Acceptance criterion** (the finding should no longer appear in re-verification)

Read the target file(s) to confirm they exist and understand the context around the finding.

Output the scope to the user for confirmation:

```
Fix scope:
  Finding: H-01 (High) -- Command injection via MODULE_NAME in find -exec
  File(s): konflux/build-and-distribute-pipeline.yaml
  Verification: /secure-review (security finding)
  Criterion: H-01 no longer appears in re-scan

Proceed? [Y/n]
```

Wait for user confirmation. If user declines, stop with: "Fix cancelled."

#### Step 2 — Dispatch coder

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-6`

Dispatch a single coder agent with a tightly scoped prompt:

"You are fixing a specific finding from a security/code review.

Read the coder agent definition at `.claude/agents/coder*.md` and follow its standards.

**Finding:**
[finding ID, severity, description, file, line, recommendation -- extracted in Step 0]

**Source artifact:**
[path to the review artifact]

**Scope:** Fix ONLY this finding. Do not refactor, do not expand scope, do not
fix other findings in the same file.

Read the target file at [file path] and apply the fix.

Hard rules:
- Only modify the file(s) listed in the scope. Do not touch other files.
- Follow the plan exactly. The finding description and recommendation are your specification.
- If the fix requires modifying more than 3 files, write `BLOCKED.md` in the project root explaining why and stop.
- If blocked on something you cannot resolve, write `BLOCKED.md` in the project root and stop.

Report what you changed and why."

No worktree -- coder edits the file directly.

**After coder finishes:**

Tool: `Bash`

Check for BLOCKED.md:

```bash
if [ -f "BLOCKED.md" ]; then
    echo "Implementation blocked. See BLOCKED.md for details."
    cat BLOCKED.md
    rm -f BLOCKED.md
    exit 1
fi
```

If BLOCKED.md exists, stop workflow and output: "Fix blocked. See output above."

**Post-coder scope validation (structural enforcement):**

Tool: `Bash`

Run a `git diff --name-only` check to validate the coder only modified scoped files:

```bash
MODIFIED_FILES=$(git diff --name-only)
for f in $MODIFIED_FILES; do
    if ! echo "$SCOPED_FILES" | grep -qF "$f"; then
        echo "OUT-OF-SCOPE file modified: $f"
        OUT_OF_SCOPE=true
    fi
done
```

If any out-of-scope files were modified:

```bash
echo "WARNING: Coder modified files outside the declared scope."
echo "Reverting out-of-scope changes:"
git checkout -- <out-of-scope-files>
echo "Out-of-scope files reverted. Scoped changes preserved."
```

If ALL modified files were out-of-scope (no scoped files modified at all), stop with:
"Fix did not modify any scoped files. Stopping."

**Post-coder lightweight secret pattern check:**

Tool: `Bash`

Run a quick pattern check on the modified files for common secret patterns. This is not a full `/secrets-scan` invocation -- it is a targeted grep on the diff:

```bash
git diff -U0 | grep -inE \
  '(api[_-]?key|api[_-]?secret|password|passwd|token|secret[_-]?key|access[_-]?key|private[_-]?key)\s*[:=]\s*["\x27][^\s]{8,}' \
  && echo "WARNING: Possible hardcoded secret detected in diff. Review before proceeding." \
  || true
```

If patterns are detected: output a warning with the matched lines (redacted to first 4 / last 4 characters of the value). **Do not block** -- the code review in Step 3b provides a second check. Log: "Secret pattern detected in diff. Flagged for review."

#### Step 3 — Targeted verification

Tool: `Task`, `Bash`, `Glob`

Run ONLY the verification relevant to the finding type determined in Step 0.

**3a -- Type-specific verification:**

**Security finding:**

Tool: `Glob`

Glob for `~/.claude/skills/secure-review/SKILL.md`

If found:

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`

"You are running a focused security re-scan to verify that a specific finding has been resolved.

Read the secure-review skill definition at `~/.claude/skills/secure-review/SKILL.md`.
Execute its scanning workflow scoped to `changes` (uncommitted diff only).

**Original finding to verify resolution:**
[finding ID, severity, description -- from Step 0]

Write your findings to `./plans/fix-[finding-id]-[timestamp]-reverify.secure-review.md`.

In your report, explicitly state whether finding [finding-id] is RESOLVED or PERSISTS.
If the finding PERSISTS, explain why the fix did not address it.

Verdict:
- PASS: Original finding is resolved AND no new Critical findings introduced
- FAIL: Original finding persists OR a new Critical finding was introduced
- PASS_WITH_NOTES: Original finding is resolved but new non-Critical findings were found (these do NOT block the fix)

CRITICAL: Never include actual secret values in your report. Redact to first 4 / last 4 characters."

If /secure-review is not found:

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-6`

"You are reviewing the uncommitted diff (`git diff`) for security implications.
The original finding was: [finding ID, severity, description].
Check whether the fix addresses the finding without introducing new security issues.

Verdict: PASS (finding addressed) / FAIL (finding persists or new Critical issue)

Write your review to `./plans/fix-[finding-id]-[timestamp]-reverify.security-review.md`."

**Correctness finding:**

Tool: `Bash` (direct -- coordinator does this)

Run the project test command. Derive test command from (in priority order):
1. `CLAUDE.md` test command section
2. `package.json` scripts.test
3. `pyproject.toml` or `Makefile` test target

If test command is not discoverable: log "No test command found. Skipping test execution. Relying on code review."

**Coverage/performance finding:**

Same as correctness finding -- run the project test command.

**3b -- Focused code review (all finding types):**

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-6`

"You are reviewing a targeted code fix. The fix addresses a specific finding from a review artifact.

**Original finding:**
[finding ID, severity, description]

**Changed files:**
Review the uncommitted diff (`git diff`).

Check:
1. Does the fix actually address the finding?
2. Does the fix introduce new issues?
3. Is the fix minimal (no scope creep)?

Verdict:
- PASS: Fix addresses the finding, is minimal, and introduces no new issues
- REVISION_NEEDED: Fix needs adjustment (explain what)
- FAIL: Fix does not address the finding or introduces a Critical issue

Write your review to `./plans/fix-[finding-id]-[timestamp].code-review.md`."

**3c -- Result evaluation:**

| Type Verification | Code Review | Action |
|---|---|---|
| PASS or PASS_WITH_NOTES | PASS | Proceed to Step 4 (commit) |
| PASS or PASS_WITH_NOTES | REVISION_NEEDED | Re-dispatch coder with review feedback (Max 1 revision round, then stop) |
| FAIL | Any | Stop. Output: "Fix did not resolve the finding. See verification artifact." |
| Any | FAIL | Stop. Output: "Code review FAIL. See `./plans/fix-[finding-id]-[timestamp].code-review.md`." |

**Revision retry (Max 1 revision round):**

If code review returns REVISION_NEEDED:

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-6`

"You are revising a fix based on code review feedback.

Read the code review at `./plans/fix-[finding-id]-[timestamp].code-review.md`.
Address the REVISION_NEEDED findings.

Read the coder agent definition at `.claude/agents/coder*.md`.

Do not change anything beyond what the code review asks for."

Then re-run Step 3b (code review only). If still REVISION_NEEDED or FAIL after retry:
Stop. Output: "Fix did not converge after 1 revision. See `./plans/fix-[finding-id]-[timestamp].code-review.md`."

#### Step 4 — Commit and archive

Tool: `Bash`

**If `$DRY_RUN` is `true`:**

Output:
```
Dry-run complete. Fix applied and verified but NOT committed.

Changes in working directory:
[git diff --stat output]

To commit manually:
  git add <fixed-files>
  git commit -m "fix(<scope>): <description>"

To re-run and commit:
  /fix <same-arguments-without-dry-run>
```

Stop workflow. Do not proceed to commit.

**If `$DRY_RUN` is `false`:**

**4a -- Commit:**

Tool: `Bash`

```bash
git add <fixed-files>
git commit -m "$(cat <<'EOF'
fix(<scope>): <what was fixed>

Resolves <finding-id> from <artifact-path>.
<one-line description of the finding>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

Where:
- `<scope>` is derived from the file path (e.g., `security`, `pipeline`, module name)
- `<what was fixed>` is a concise imperative description
- `<finding-id>` is the finding ID from Step 0
- `<artifact-path>` is the path to the source review artifact

**4b -- Archive verification artifacts:**

Tool: `Bash`

```bash
mkdir -p ./plans/archive/fix/
# Move all fix verification artifacts (timestamped names prevent collisions)
mv ./plans/fix-*.md ./plans/archive/fix/ 2>/dev/null || true
```

**4c -- Update learnings (conditional, security findings only):**

If the fix resolved a security finding (finding type from Step 0 is security):

Tool: `Read`, `Edit`

Read `.claude/learnings.md` (if exists).

Search for an existing entry matching the finding ID or finding description.

If found: append `Fixed in: <commit-sha>` to the existing entry using Edit tool.

If not found: append a new entry under `## Security Patterns > ### Resolved findings`
(create the section if it does not exist):

```
- **[YYYY-MM-DD] [Finding-ID]: [Finding Title]** -- [Description]. Source: [artifact-path]. Fixed in: [commit-sha]. #security #resolved
```

If `.claude/learnings.md` does not exist: create it with standard header and the new entry.

Auto-commit the learnings update:

Tool: `Bash`

```bash
if git diff --name-only -- .claude/learnings.md | grep -q .; then
    git add .claude/learnings.md
    git commit -m "chore: mark finding [finding-id] as resolved in learnings"
elif git ls-files --others --exclude-standard -- .claude/learnings.md | grep -q .; then
    git add .claude/learnings.md
    git commit -m "chore: add resolved finding [finding-id] to learnings"
fi
```

If the commit fails, log the error but do not fail the step.

**4d -- Output success message:**

```
Fix complete and committed.
  Finding: [finding-id] ([severity]) -- [title]
  Commit: [commit-sha]
  Artifact: [artifact-path]
  Verification: [artifact-path in archive]
  
Next steps:
  - Run /audit to verify overall codebase health
  - Run /sync to update documentation if the fix changed behavior
```

## What `/fix` Does NOT Do

- No plan file required or generated
- No worktree isolation (fixes are small)
- No QA report (overkill for targeted fixes)
- No pattern validation against CLAUDE.md
- No dependency audit (fixes do not add dependencies)
- No full secrets scan (lightweight grep-based pattern check is included; see Step 2)
- No retro capture (the finding itself is the learning)
- No JSONL audit logging (see D1)
- No security maturity level awareness (see D2)

## Comparison

| Dimension | Manual fix | /fix | /architect -> /ship |
|-----------|-----------|------|-------------------|
| Plan file | No | No | Yes (required) |
| Worktree isolation | No | No | Yes |
| Code review | No | Yes (diff-scoped) | Yes (full) |
| Security re-scan | No | Yes (if security finding) | Yes (full) |
| QA report | No | No | Yes |
| Tests | Manual | Targeted | Full suite |
| Commit traceability | Manual | Automatic (finding ref) | Automatic (plan ref) |
| Learnings update | No | Yes (mark resolved) | Yes (retro capture) |
| Audit artifacts support | No | Yes (/ship + /audit) | No (/ship only) |
| Dry-run mode | N/A | Yes (`--dry-run`) | No |
| Typical time | 2 min | 5-10 min | 30-60 min |

## Interfaces / Schema Changes

### New Skill File

| File | Purpose |
|------|---------|
| `skills/fix/SKILL.md` | Skill definition (source of truth) |

### Deployed Location

After `./scripts/deploy.sh`: `~/.claude/skills/fix/SKILL.md`

### Artifact Naming Convention

Artifacts include a `[timestamp]` suffix (ISO 8601 compact, e.g., `20260523T170000`) to prevent naming collisions when `/fix` is invoked multiple times for the same finding.

| Artifact | Location | Lifecycle |
|----------|----------|-----------|
| `./plans/fix-[finding-id]-[timestamp]-reverify.secure-review.md` | Working directory during run | Archived to `./plans/archive/fix/` |
| `./plans/fix-[finding-id]-[timestamp]-reverify.security-review.md` | Working directory during run | Archived to `./plans/archive/fix/` |
| `./plans/fix-[finding-id]-[timestamp].code-review.md` | Working directory during run | Archived to `./plans/archive/fix/` |

### Trigger Phrases (system-reminder registration)

```
Use when the user wants to fix a specific finding from a review artifact,
apply a targeted code fix with verification, or remediate a security finding.
Triggers: "fix finding", "fix H-01", "apply the fix", "remediate",
"fix the command injection", "address the review finding".
```

### No Schema Changes

- No changes to `configs/audit-event-schema.json` (no new event types)
- No changes to `configs/score-dimensions.json` (no scoring for `/fix`)
- No changes to `scripts/emit-audit-event.sh` (not used by `/fix`)

## Data Migration

None. `/fix` is a new skill with no existing data to migrate.

## Security Requirements

### Assets

- **Source code under fix:** Confidentiality: internal | Integrity: high | Availability: medium
  - The code being modified may contain security-sensitive logic (authentication, authorization, input validation)
- **Review artifacts (input):** Confidentiality: internal | Integrity: high | Availability: low
  - Artifacts contain security finding descriptions with file paths and line numbers. May reference vulnerabilities by CWE/OWASP category.
- **Verification artifacts (output):** Confidentiality: internal | Integrity: high | Availability: low
  - Re-scan reports may contain security finding details. Same sensitivity as input artifacts.
- **Learnings file:** Confidentiality: internal | Integrity: medium | Availability: low
  - Contains finding metadata (IDs, titles, commit SHAs). No secret values.
- **Git commits:** Confidentiality: public (committed to repo) | Integrity: high | Availability: high

### Trust Boundaries

- **Boundary 1: Review artifact -> Skill coordinator (reading)**
  - Trust level: High. Artifacts are generated by trusted skills (/ship, /audit, /secure-review) and stored in the local filesystem.
  - Authentication: Not applicable (local file read).
  - Authorization: Filesystem permissions. Skill runs as the user.

- **Boundary 2: Skill coordinator -> Coder agent (delegation)**
  - Trust level: Medium. The coder agent receives a prompt with finding details and a file path. The coder can modify files.
  - Authentication: Not applicable (Task subagent invocation).
  - Authorization: Scoped by prompt instructions, BLOCKED.md escape hatch, and post-coder `git diff --name-only` scope validation. Coder is instructed to modify only listed files; out-of-scope modifications are reverted.

- **Boundary 3: Skill coordinator -> /secure-review (re-verification)**
  - Trust level: High. Secure-review is a trusted skill in the same deployment.
  - Authentication: Not applicable (skill invocation).
  - Authorization: Secure-review operates on uncommitted diff only.

- **Boundary 4: Coder output -> Git commit (persistence)**
  - Trust level: Medium. Coder output is reviewed by the code review substep before commit.
  - Authentication: Git user identity.
  - Authorization: User must approve the commit (or dry-run mode prevents it).

### STRIDE Analysis

| Threat | Vector | Mitigation | Residual Risk |
|--------|--------|-----------|---------------|
| **Spoofing** | Attacker crafts a malicious review artifact with a fake finding that tricks the coder into introducing a vulnerability | Artifacts are read from local filesystem paths specified by the user. User must provide the artifact path explicitly. Coder prompt is scoped to the finding and target file only. | Low -- requires attacker to write files to user's filesystem |
| **Tampering** | Attacker modifies a review artifact after creation to change the finding recommendation to a malicious fix | Artifacts are stored in `./plans/` or `./plans/archive/` under git version control. Tampering is detectable via `git diff`. Code review substep (Step 3b) validates the fix independently. | Low -- git provides tamper detection |
| **Repudiation** | User claims a fix was not applied or was applied incorrectly | Commit message includes finding-id, artifact-path, and Co-Authored-By. Verification artifacts are archived. | Low -- full audit trail in git |
| **Information Disclosure** | Security finding details in verification artifacts expose vulnerability information | Same exposure level as existing /secure-review and /audit artifacts. Artifacts are stored locally, not transmitted. Secure-review redaction rules apply (first 4 / last 4 chars for secrets). | Low -- same as existing skills |
| **Denial of Service** | Malformed artifact causes parsing loop or resource exhaustion | Skill reads artifact once (Step 0) and extracts finding. If parsing fails, skill stops with error. No retry loops on parse failure. | Low -- fail-fast on bad input |
| **Elevation of Privilege** | Coder agent expands scope beyond the target finding, modifying unrelated files | Coder prompt explicitly constrains scope to listed files. BLOCKED.md escape for >3 files. Post-coder `git diff --name-only` check validates modified files against scope list and reverts out-of-scope changes (structural enforcement). Code review (Step 3b) validates minimality. User confirmation at Step 1 shows scope. | Low -- defense in depth (prompt scoping + structural validation + review + user confirmation) |

### Security Controls

- **Input Validation:** Artifact path is validated by attempting to read it (file existence check). Finding ID is extracted via pattern matching. Free-text input is used as-is (no injection risk -- it becomes a prompt, not code).
- **Scope Enforcement:** Coder prompt constrains file modification scope. Post-coder `git diff --name-only` structurally validates modified files against scope list and reverts out-of-scope changes. Code review validates minimality. User confirmation at Step 1.
- **Secret Detection:** Post-coder lightweight grep-based pattern check on the diff flags common secret patterns (API keys, tokens, passwords). Warning-only (does not block). Code review provides a second check.
- **Secret Redaction:** Re-verification via /secure-review inherits its redaction rules (first 4 / last 4 characters). Code review prompt does not ask for secret values.
- **Audit Trail:** Git commit with finding-id and artifact-path. Verification artifacts archived to `./plans/archive/fix/`.

### Failure Modes

- **If artifact cannot be read:** Stop with error message. No files modified.
- **If finding ID not found in artifact:** List available findings and prompt user. No files modified.
- **If coder is blocked:** BLOCKED.md created, workflow stops. No commit.
- **If coder modifies out-of-scope files:** Out-of-scope changes reverted via `git checkout`. Scoped changes preserved. Workflow continues with warning.
- **If verification fails:** Workflow stops. Changes remain uncommitted in working directory. User can inspect and decide.
- **If commit fails:** Log error. Changes remain uncommitted. No data loss.
- **If learnings update fails:** Log error, do not fail the step. Fix commit is already done.

## Rollout Plan

### Phase 1: Implementation (this plan)

1. Create `skills/fix/SKILL.md`
2. Validate with `validate_skill.py`
3. Deploy with `./scripts/deploy.sh fix`
4. Run `validate-all.sh` to confirm no regression

### Phase 2: Integration (same implementation)

5. Update CLAUDE.md skill registry table
6. Add validation test to `generators/test_skill_generator.sh`
7. Add structural integration test to `scripts/test-integration.sh`

### Phase 3: Verification

8. Run full test suites: `bash generators/test_skill_generator.sh` and `bash scripts/test-integration.sh`
9. Manual smoke test: invoke `/fix` on a known finding in an active project

### Rollback

- Delete `skills/fix/SKILL.md` and redeploy: `rm -rf ~/.claude/skills/fix/`
- Revert CLAUDE.md and test file changes
- No data migration to reverse

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Coder agent expands scope beyond the target finding | Medium | Medium | Prompt scoping, post-coder `git diff --name-only` scope validation with revert, code review validation, user confirmation, 3-file limit with BLOCKED.md escape |
| /secure-review re-scan produces false positives unrelated to the fix | Medium | Low | Decision D6: new non-Critical findings do not block. Only original finding persistence or new Criticals block. |
| Finding ID format varies across artifact types | Low | Medium | Flexible pattern matching (H-01, M-1, CR-3, C-01 formats). Free-text fallback for unparseable findings. |
| Learnings update creates merge conflicts with concurrent /ship runs | Low | Low | Learnings commit is a separate, post-fix commit. If it fails, the fix commit is unaffected. |
| Skill does not validate with `validate_skill.py` | Low | High | Pre-test: run validator during implementation. Follow existing skill patterns exactly. Use em-dashes in step headers, single-line description in frontmatter. |
| Coder introduces hardcoded secret in fix | Low | High | Post-coder lightweight grep-based secret pattern check on diff (warning). Code review (Step 3b) provides second check. |

## Test Plan

### Exact test commands

```bash
# Unit test: validate the new skill definition
python3 generators/validate_skill.py skills/fix/SKILL.md

# Full unit test suite (includes new test for fix skill)
bash generators/test_skill_generator.sh

# Full integration test suite (includes new structural test for fix skill)
bash scripts/test-integration.sh

# Validate all skills (regression check)
bash scripts/validate-all.sh

# Deploy and verify deployment
./scripts/deploy.sh fix
ls ~/.claude/skills/fix/SKILL.md
```

### Test cases added

**In `generators/test_skill_generator.sh`:**

| Test # | Name | Command | Expected | Insertion Point |
|--------|------|---------|----------|-----------------|
| 57 | Validate fix skill | `python3 validate_skill.py skills/fix/SKILL.md` | Exit 0 | Before Test 50 (Cleanup) block. Update header from "up to 56 tests" to "up to 57 tests". |

**In `scripts/test-integration.sh`:**

| Test # | Name | Command | Expected | Insertion Point |
|--------|------|---------|----------|-----------------|
| 28 | fix SKILL.md version is 1.0.0 | `grep -q 'version: 1.0.0' skills/fix/SKILL.md` | Exit 0 | Before Test 9 (Cleanup) block. Update header from "26 tests" to "28 tests". |
| 29 | fix SKILL.md contains Pipeline archetype steps | `grep -q 'Step 0 .* Parse' skills/fix/SKILL.md && grep -q 'Step 4 .* Commit' skills/fix/SKILL.md` | Exit 0 | Immediately after Test 28, before Test 9 (Cleanup) block. |

### Manual smoke tests (post-deployment, not automated)

1. **Smoke test with a security finding:**
   ```
   /fix plans/archive/maven-build-support/maven-build-support.secure-review.md H-01
   ```
   Expected: coder fixes the finding, secure-review re-scan shows H-01 resolved, commit references the finding.

2. **Smoke test with a code-review finding:**
   ```
   /fix plans/archive/maven-build-support/maven-build-support.code-review.md M-1
   ```
   Expected: coder fixes the finding, tests pass, commit references the finding.

3. **Smoke test with free-text:**
   ```
   /fix "unquoted LOCKFILE_ENTRIES variable in upload-cache tar command"
   ```
   Expected: asks which verification type, applies fix, verifies, commits.

4. **Smoke test with dry-run:**
   ```
   /fix plans/archive/maven-build-support/maven-build-support.secure-review.md H-01 --dry-run
   ```
   Expected: fix applied and verified but NOT committed. Changes remain in working directory.

5. **Smoke test with audit artifact:**
   ```
   /fix plans/audit-20260523T143000.security.md C-01
   ```
   Expected: parses audit artifact, applies fix, runs security re-scan, commits.

## Acceptance Criteria

1. `skills/fix/SKILL.md` exists and passes `python3 generators/validate_skill.py skills/fix/SKILL.md`
2. `bash scripts/validate-all.sh` passes (no regression from new skill)
3. `bash generators/test_skill_generator.sh` passes with new test 57
4. `bash scripts/test-integration.sh` passes with new tests 28-29
5. CLAUDE.md skill registry table includes `/fix` entry with correct metadata
6. `./scripts/deploy.sh fix` deploys successfully to `~/.claude/skills/fix/SKILL.md`
7. Skill frontmatter has `model: claude-opus-4-6`, `version: 1.0.0`, single-line `description:`
8. Skill follows Pipeline archetype with Steps 0-4, using em-dashes (`—`) in step headers
9. Skill supports `--dry-run` flag
10. Skill supports both `/ship` artifacts and `/audit` artifacts as input

## Task Breakdown

### Files to Create

| File | Description |
|------|-------------|
| `skills/fix/SKILL.md` | Skill definition following Pipeline archetype (source of truth) |

### Files to Modify

| File | Change | Description |
|------|--------|-------------|
| `CLAUDE.md` | Add row to Skill Registry table | Add fix skill entry: name, version, purpose, model, steps |
| `CLAUDE.md` | Update skill count references | Update "12 core skills" to "13 core skills" in Overview, Architecture, and Development Rules sections |
| `CLAUDE.md` | Add `/fix` artifact location | Add fix archive path to Artifact Locations section |
| `generators/test_skill_generator.sh` | Add test 57 | Validate fix skill: `python3 validate_skill.py skills/fix/SKILL.md`. Insert before Test 50 (Cleanup) block. |
| `generators/test_skill_generator.sh` | Update test inventory comment | Update header from "up to 56 tests" to "up to 57 tests" |
| `scripts/test-integration.sh` | Add tests 28-29 | Structural tests: version check, pipeline archetype steps. Insert before Test 9 (Cleanup) block. |
| `scripts/test-integration.sh` | Update test count in header | Update "26 tests" to "28 tests" in header comment |

### Files NOT Modified

| File | Reason |
|------|--------|
| `scripts/deploy.sh` | Auto-discovers skills from `skills/*/` directories. No hardcoded list. New skill is automatically discovered. |
| `scripts/validate-all.sh` | Auto-discovers skills from `skills/*/` directories. No hardcoded list. |
| `configs/audit-event-schema.json` | No new event types (D1: no audit logging) |
| `configs/score-dimensions.json` | No scoring for `/fix` |
| `scripts/emit-audit-event.sh` | Not used by `/fix` |
| `scripts/audit-log-query.sh` | Not used by `/fix` |
| `scripts/compute-run-score.sh` | Not used by `/fix` |

## Context Alignment

### CLAUDE.md Patterns Followed

| Pattern | How Followed |
|---------|-------------|
| 1. Coordinator | Skill coordinates work -- dispatches coder and reviewer agents, does not write code |
| 2. Numbered steps | `## Step N — [Action]` headers (Steps 0-4) with em-dashes |
| 3. Tool declarations | Each step specifies `Tool:` line |
| 4. Verdict gates | Step 3c has PASS/FAIL/REVISION_NEEDED evaluation matrix |
| 6. Structured reporting | Verification artifacts written to `./plans/` |
| 7. Bounded iterations | Max 1 revision round in Step 3c |
| 8. Model selection | `claude-opus-4-6` in frontmatter; `claude-sonnet-4-6` for coder and reviewer subagents |
| 9. Scope parameters | `$ARGUMENTS` with artifact-path, finding-id, --dry-run |
| 10. Archive on success | Step 4b moves artifacts to `./plans/archive/fix/` |

### Prior Plans Referenced

| Plan | Relationship |
|------|-------------|
| `quantitative-eval-scoring.md` | Decided NOT to add scoring for `/fix` (D1). Scoring is for multi-step workflows with complex execution paths. |
| `threat-model-consumption.md` | `/fix` does not consume threat model context. It fixes individual findings, not plan-level security requirements. |
| `ship-audit-logging-gaps.md` | Decided NOT to add audit logging to `/fix` (D1). Logging infrastructure exists but is disproportionate for a 5-step linear pipeline. |

### Deviations with Justification

| Deviation | Justification |
|-----------|---------------|
| No worktree isolation (Pattern 11) | Fixes are small (1-2 files). Worktree overhead is not justified. `/fix` explicitly does not use worktrees -- this is a design principle, not an oversight. |
| No JSONL audit logging | See D1. Cost-benefit analysis: 5-step linear pipeline with no parallel execution, no security maturity awareness. Commit message provides full traceability. |
| No security maturity level awareness | `/fix` is maturity-level-agnostic. It does not have multi-gate evaluation or downgrade logic. The verification is binary (resolved or not). |
| Pipeline archetype (not Coordinator) | Although `/fix` dispatches agents, its primary flow is sequential: parse -> scope -> implement -> verify -> commit. This aligns with the Pipeline archetype more closely than Coordinator (which emphasizes parallel reviews and revision loops). |
| `--dry-run` flag (no precedent) | New capability not present in existing skills. Justified by the security-sensitive nature of the fixes and user request for inspection before commit. Low implementation cost (skip Step 4). |
| Finding-ID-based artifact naming (Pattern 5) | Uses `fix-[finding-id]-[timestamp]` naming instead of pure ISO timestamp naming. Finding-ID provides semantic traceability to the source finding. Timestamp suffix prevents naming collisions across multiple invocations for the same finding. Artifacts are short-lived (archived in Step 4b). |

### Archetype Classification

**Pipeline** -- Sequential execution with checkpoints:
- Step 0: Parse input (pre-flight)
- Step 1: Scope and confirm (user gate)
- Step 2: Implement (dispatch coder)
- Step 3: Verify (targeted re-verification + code review)
- Step 4: Commit (commit gate with optional dry-run skip)

<!-- Context Metadata
discovered_at: 2026-05-23T17:27:15Z
claude_md_exists: true
recent_plans_consulted: quantitative-eval-scoring.md, threat-model-consumption.md, ship-audit-logging-gaps.md
archived_plans_consulted: none
-->
