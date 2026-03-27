---
name: audit
description: Deep security and performance scan with structured reporting.
version: 3.1.0
model: claude-opus-4-6
---
# /audit Workflow

## Inputs
- Scope: $ARGUMENTS (optional: "plan", "code", "full")
  - `plan`: Audit a plan file before implementation
  - `code`: Audit recent uncommitted changes (default)
  - `full`: Full codebase scan

## Role
You are the **audit coordinator**. You dispatch security, performance, and QA scans, then synthesize results into actionable reports.
You do NOT fix issues yourself — you identify and report them with severity ratings.

## Step 1 — Determine scope

Tool: `Bash` (direct — coordinator does this)

Run: `git status --porcelain`

**Scope resolution:**
- If `$ARGUMENTS` is empty:
  - If git status shows uncommitted changes: scope = "code"
  - Else: scope = "full"
- Else: scope = `$ARGUMENTS`

Validate scope is one of: `plan`, `code`, `full`. If not, stop with:
"Invalid scope. Use: /audit [plan|code|full]"

Derive timestamp: `[timestamp]` = current ISO datetime (e.g., `2026-02-07T12-30-00`)

## Step 2 — Security scan

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

**Pre-check:** Glob for `.claude/agents/security-analyst*.md`

Tool: `Glob` (direct — coordinator does this)

Pattern: `.claude/agents/security-analyst*.md`

**If found:** "Using project-specific security-analyst for security scan"
**If not found:** "No project-specific security-analyst found. Using generic Task subagent for security scan. For project-tailored scanning, generate one: gen-agent . --type security-analyst"

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-opus-4-6`

**If scope is "plan":**

- **If security-analyst agent found:** Prompt: "Read `.claude/agents/security-analyst*.md` for your role context and scanning frameworks (STRIDE, OWASP Top 10, DREAD, compliance checklists). Then read the plan file at `$ARGUMENTS` (after 'plan' keyword). Analyze for security risks:
  - Authentication/authorization gaps
  - Data exposure risks
  - Input validation requirements
  - Cryptographic requirements
  - Secrets management

  Rate findings: Critical / High / Medium / Low.
  Write to `./plans/audit-[timestamp].security.md`"

- **If security-analyst agent not found:** Prompt: "Read the plan file at `$ARGUMENTS` (after 'plan' keyword). Analyze for security risks:
  - Authentication/authorization gaps
  - Data exposure risks
  - Input validation requirements
  - Cryptographic requirements
  - Secrets management

  Rate findings: Critical / High / Medium / Low.
  Write to `./plans/audit-[timestamp].security.md`"

**If scope is "code":**

- **If security-analyst agent found:** Prompt: "Read `.claude/agents/security-analyst*.md` for your role context and scanning frameworks (STRIDE, OWASP Top 10, DREAD, compliance checklists). Then scan uncommitted changes for:
  - SQL injection vulnerabilities
  - XSS vulnerabilities
  - Exposed secrets (API keys, passwords, tokens)
  - Authentication bypasses
  - Authorization gaps
  - OWASP Top 10 vulnerabilities
  - Dependency vulnerabilities

  Rate findings: Critical / High / Medium / Low.
  Write to `./plans/audit-[timestamp].security.md`"

- **If security-analyst agent not found:** Prompt: "Scan uncommitted changes for:
  - SQL injection vulnerabilities
  - XSS vulnerabilities
  - Exposed secrets (API keys, passwords, tokens)
  - Authentication bypasses
  - Authorization gaps
  - OWASP Top 10 vulnerabilities
  - Dependency vulnerabilities

  Rate findings: Critical / High / Medium / Low.
  Write to `./plans/audit-[timestamp].security.md`"

**If scope is "full":**

- **If security-analyst agent found:** Prompt: "Read `.claude/agents/security-analyst*.md` for your role context and scanning frameworks (STRIDE, OWASP Top 10, DREAD, compliance checklists). Then perform a full codebase security audit:
  - SQL injection, XSS, CSRF vulnerabilities
  - Exposed secrets in code and config files
  - Authentication and authorization implementation
  - Dependency vulnerabilities (check package manifests)
  - Insecure cryptography
  - OWASP Top 10 compliance

  Rate findings: Critical / High / Medium / Low.
  Write to `./plans/audit-[timestamp].security.md`"

- **If security-analyst agent not found:** Prompt: "Full codebase security audit:
  - SQL injection, XSS, CSRF vulnerabilities
  - Exposed secrets in code and config files
  - Authentication and authorization implementation
  - Dependency vulnerabilities (check package manifests)
  - Insecure cryptography
  - OWASP Top 10 compliance

  Rate findings: Critical / High / Medium / Low.
  Write to `./plans/audit-[timestamp].security.md`"

## Step 3 — Performance scan

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

**If scope is "plan":**
Prompt: "Read the plan file at `$ARGUMENTS` (after 'plan' keyword).
Analyze for performance risks:
- Algorithm complexity concerns
- Database query patterns
- Caching strategy
- Scalability bottlenecks

Rate findings: Critical / High / Medium / Low.
Write to `./plans/audit-[timestamp].performance.md`"

**If scope is "code":**
Prompt: "Analyze uncommitted changes for:
- O(n²) or worse algorithms
- N+1 query patterns
- Missing database indexes
- Memory leaks
- Inefficient data structures
- Unnecessary I/O operations

Rate findings: Critical / High / Medium / Low.
Write to `./plans/audit-[timestamp].performance.md`"

**If scope is "full":**
Prompt: "Full codebase performance audit:
- Algorithm complexity analysis
- Database query optimization opportunities
- Missing indexes
- Memory leak patterns
- Inefficient data structures
- I/O bottlenecks

Rate findings: Critical / High / Medium / Low.
Write to `./plans/audit-[timestamp].performance.md`"

## Step 4 — QA regression (conditional)

**Trigger:** Only run if scope is "code" or "full" (skip for "plan")

**Pre-check:** Verify qa-engineer agent exists

Tool: `Glob` (direct — coordinator does this)

Pattern: `.claude/agents/qa-engineer*.md` or `.claude/agents/qa*.md`

**If no files match:**
- Write note to `./plans/audit-[timestamp].qa.md`:
  ```markdown
  # QA Regression — Skipped

  **Status:** QA agent not found

  No qa-engineer agent found in `.claude/agents/`. Skipping regression tests.

  To enable QA regression tests, generate a QA agent:
  ```bash
  python3 ~/workspaces/claude-devkit/generators/generate_agents.py . --type qa-engineer
  ```
  ```
- Continue to Step 5 (do not block workflow).

**If QA agent exists:**

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

Prompt: "You are running QA regression validation.
Read the `.claude/agents/` directory to find the qa-engineer agent.
Follow that agent's testing standards.

Run the full test suite and analyze results.

Write `./plans/audit-[timestamp].qa.md` with:
- **Test results** (passed/failed/skipped counts)
- **Coverage delta** (if measurable)
- **Flaky tests** (tests that fail intermittently)
- **Missing test coverage** (critical paths without tests)
- **Test performance** (slow tests > 1s)

If no test command is found or tests cannot run, document this limitation."

## Step 5 — Synthesis

Tool: `Read` (direct — coordinator does this)

Read all audit reports:
- `./plans/audit-[timestamp].security.md`
- `./plans/audit-[timestamp].performance.md`
- `./plans/audit-[timestamp].qa.md` (if exists)

Generate `./plans/audit-[timestamp].summary.md` with this structure:

```markdown
# Audit Summary — [scope] — [timestamp]

## Verdict
[PASS / PASS_WITH_NOTES / BLOCKED]

## Critical Findings
[Count: N]
- [Finding 1 from any report]
- [Finding 2 from any report]

## High Findings
[Count: N]
- [Finding 1 from any report]
- [Finding 2 from any report]

## Medium Findings
[Count: N]
(Summarize or list)

## Low Findings
[Count: N]
(Summarize or list)

## Risk Score
[1-10 scale]
- 1-3: Low risk (PASS)
- 4-6: Medium risk (PASS_WITH_NOTES)
- 7-10: High risk (BLOCKED)

## Action Items
(Prioritized list of what must be fixed)

1. [Critical item 1]
2. [Critical item 2]
3. [High item 1]
...

## Reports
- Security: ./plans/audit-[timestamp].security.md
- Performance: ./plans/audit-[timestamp].performance.md
- QA: ./plans/audit-[timestamp].qa.md (if run)
```

**Verdict rules:**
- **BLOCKED**: Any Critical findings OR 3+ High findings
- **PASS_WITH_NOTES**: 1-2 High findings OR 3+ Medium findings
- **PASS**: Only Medium/Low findings

## Step 6 — Gate

Read `./plans/audit-[timestamp].summary.md` and check verdict.

**If BLOCKED:**
Output:
"🚫 Audit BLOCKED — Critical security or performance issues found.

Summary: ./plans/audit-[timestamp].summary.md
Action items must be resolved before proceeding.

Critical findings: [count]
High findings: [count]"

**If PASS_WITH_NOTES:**
Output:
"⚠️ Audit PASS with notes — Review recommended but not blocking.

Summary: ./plans/audit-[timestamp].summary.md
Consider addressing high-priority findings.

High findings: [count]
Medium findings: [count]"

**If PASS:**
Output:
"✅ Audit PASS — No blocking issues found.

Summary: ./plans/audit-[timestamp].summary.md
Only minor findings to consider.

Medium findings: [count]
Low findings: [count]"
