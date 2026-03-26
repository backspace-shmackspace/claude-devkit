---
name: secrets-scan
description: Pre-commit secrets detection with pattern-based scanning for API keys, tokens, passwords, private keys, and connection strings. Self-contained — no external tools required.
model: claude-sonnet-4-5
version: 1.0.0
---
# /secrets-scan Workflow

## Role

This skill is a **pipeline coordinator**. It orchestrates a sequential secrets detection workflow using pattern-based scanning. It delegates grep/regex scanning to Bash and synthesis to analysis tasks. It does NOT require external tools like trufflehog or gitleaks — all scanning uses built-in grep patterns, making it self-contained and deployable anywhere Claude Code runs.

**Zero tolerance policy:** Any confirmed secret detected results in a BLOCKED verdict. There is no passing threshold — secrets in code are a critical finding.

**Report redaction rule:** This skill NEVER includes actual secret values in reports. Reports show secret type, file path, and line number only. Pattern matches are redacted to show type and location: e.g., "AWS Access Key at `src/config.js:42`".

## Inputs

- Scan scope: $ARGUMENTS
  - `staged` (default) — scan git staged files only (pre-commit gate)
  - `all` — scan entire working directory
  - `history` — scan git commit history (use for post-incident review)

## Step 0 — Pre-flight checks

Tool: `Bash` (direct — coordinator does this)

```bash
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
echo "Secrets scan run: $TIMESTAMP"

# Verify we are in a git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: Not inside a git repository. /secrets-scan requires git."
  exit 1
fi

# Determine scope from arguments
SCOPE="${1:-staged}"
if [ "$SCOPE" != "staged" ] && [ "$SCOPE" != "all" ] && [ "$SCOPE" != "history" ]; then
  echo "ERROR: Invalid scope '$SCOPE'. Valid options: staged, all, history"
  echo "Usage: /secrets-scan [staged|all|history]"
  exit 1
fi

# For staged scope: check that there are staged files
if [ "$SCOPE" = "staged" ]; then
  STAGED_FILES=$(git diff --cached --name-only)
  if [ -z "$STAGED_FILES" ]; then
    echo "No staged files found. Stage files with 'git add' before running /secrets-scan staged."
    echo "VERDICT: PASS (no staged files to scan)"
    exit 0
  fi
  echo "Staged files: $(echo "$STAGED_FILES" | wc -l | tr -d ' ') file(s)"
fi

echo "SCOPE=$SCOPE"
echo "TIMESTAMP=$TIMESTAMP"
```

**Pre-flight failures:**
- Not a git repo: Stop with error message.
- Invalid scope argument: Stop with usage message.
- No staged files (staged scope): Output PASS with explanation and stop.

## Step 1 — Determine scan scope and collect target content

Tool: `Bash` (direct — coordinator does this)

Based on the scope from Step 0, collect the content to scan:

```bash
SCAN_TARGET_FILE="./plans/secrets-scan-${TIMESTAMP}.scan-target.txt"

case "$SCOPE" in
  staged)
    # Scan staged content (what would be committed)
    # git diff --cached shows the actual content being staged
    git diff --cached -U0 2>/dev/null > "$SCAN_TARGET_FILE"
    echo "Collected staged diff for scanning ($(wc -l < "$SCAN_TARGET_FILE") lines)"
    ;;
  all)
    # Scan all tracked and untracked files in working directory
    # Exclude common binary and generated directories
    git ls-files 2>/dev/null > /tmp/secrets-scan-filelist.tmp
    git ls-files --others --exclude-standard 2>/dev/null >> /tmp/secrets-scan-filelist.tmp
    # Filter out binary-likely extensions and large generated files
    grep -v -E '\.(png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|pdf|zip|tar|gz|bin|exe|dll|so|dylib|pyc|class)$' \
         /tmp/secrets-scan-filelist.tmp | \
    grep -v -E '(node_modules/|\.git/|vendor/|dist/|build/|__pycache__/)' > /tmp/secrets-scan-filelist-filtered.tmp
    # Read all filtered files into scan target
    while IFS= read -r f; do
      [ -f "$f" ] && echo "=== FILE: $f ===" >> "$SCAN_TARGET_FILE" && cat "$f" >> "$SCAN_TARGET_FILE"
    done < /tmp/secrets-scan-filelist-filtered.tmp
    rm -f /tmp/secrets-scan-filelist.tmp /tmp/secrets-scan-filelist-filtered.tmp
    echo "Collected working directory content for scanning"
    ;;
  history)
    # Scan git log content (recent commits — last 50 commits or since last tag)
    git log --oneline -50 --format="%H" 2>/dev/null | while read -r commit; do
      git show "$commit" 2>/dev/null >> "$SCAN_TARGET_FILE"
    done
    echo "Collected git history (last 50 commits) for scanning"
    ;;
esac
```

## Step 2 — Pattern-based secret detection

Tool: `Bash` (direct — coordinator does this)

Run pattern-based detection across the collected scan target. Each pattern targets a distinct secret type.

**Note:** No entropy analysis in v1.0.0. Pattern-based detection only. Entropy analysis deferred to v1.1.0 after false-positive calibration against real codebases.

```bash
FINDINGS_FILE="./plans/secrets-scan-${TIMESTAMP}.raw-findings.txt"
touch "$FINDINGS_FILE"

SCAN_INPUT="./plans/secrets-scan-${TIMESTAMP}.scan-target.txt"

echo "=== PATTERN SCAN RESULTS ===" >> "$FINDINGS_FILE"
echo "Timestamp: $TIMESTAMP" >> "$FINDINGS_FILE"
echo "Scope: $SCOPE" >> "$FINDINGS_FILE"
echo "" >> "$FINDINGS_FILE"

# Pattern 1: AWS Access Keys (AKIA... format — 20 char alphanumeric after AKIA)
echo "--- AWS Access Keys (AKIA...) ---" >> "$FINDINGS_FILE"
grep -n -E 'AKIA[0-9A-Z]{16}' "$SCAN_INPUT" | \
  sed 's/\(AKIA[0-9A-Z]\{4\}\)[0-9A-Z]*/\1****REDACTED/' >> "$FINDINGS_FILE" || true

# Pattern 2: AWS Secret Access Keys (40-char base64-like strings after known label)
echo "--- AWS Secret Access Keys ---" >> "$FINDINGS_FILE"
grep -n -E -i '(aws_secret_access_key|aws_secret_key)\s*[=:]\s*[A-Za-z0-9/+=]{40}' "$SCAN_INPUT" | \
  sed 's/\([A-Za-z0-9\/+=]\{4\}\)[A-Za-z0-9\/+=]\{32\}\([A-Za-z0-9\/+=]\{4\}\)/\1****REDACTED****\2/' >> "$FINDINGS_FILE" || true

# Pattern 3: GitHub Personal Access Tokens (ghp_, gho_, ghu_, ghs_, ghr_ prefixes)
echo "--- GitHub Tokens (ghp_/gho_/ghu_/ghs_/ghr_) ---" >> "$FINDINGS_FILE"
grep -n -E '(ghp_|gho_|ghu_|ghs_|ghr_)[A-Za-z0-9_]{36}' "$SCAN_INPUT" | \
  sed 's/\(gh[a-z]_[A-Za-z0-9_]\{4\}\)[A-Za-z0-9_]*/\1****REDACTED/' >> "$FINDINGS_FILE" || true

# Pattern 4: Private key headers (RSA, EC, OpenSSH, DSA)
echo "--- Private Key Material ---" >> "$FINDINGS_FILE"
grep -n -E '-----BEGIN (RSA |EC |DSA |OPENSSH |PRIVATE )PRIVATE KEY-----' "$SCAN_INPUT" >> "$FINDINGS_FILE" || true

# Pattern 5: Generic high-confidence password patterns (labeled assignments)
echo "--- Generic Passwords (labeled) ---" >> "$FINDINGS_FILE"
grep -n -E -i '(password|passwd|pwd|secret|api_key|apikey|api_secret|client_secret|auth_token|access_token)\s*[=:]\s*['\''"][^'\''"]{8,}['\''"]' "$SCAN_INPUT" | \
  sed "s/\(=\s*['\"][^'\"]\{4\}\)[^'\"]*\([^'\"]\{4\}['\"]\)/\1****REDACTED****\2/" >> "$FINDINGS_FILE" || true

# Pattern 6: Database connection strings with embedded credentials
echo "--- Database Connection Strings ---" >> "$FINDINGS_FILE"
grep -n -E '(mysql|postgresql|postgres|mongodb|redis|amqp|jdbc)://[^@\s]+:[^@\s]+@' "$SCAN_INPUT" | \
  sed 's|://\([^:]*\):[^@]*@|://\1:****REDACTED****@|' >> "$FINDINGS_FILE" || true

# Pattern 7: JWT tokens (3-part base64 separated by dots, starting with eyJ)
echo "--- JWT Tokens ---" >> "$FINDINGS_FILE"
grep -n -E 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' "$SCAN_INPUT" | \
  sed 's/\(eyJ[A-Za-z0-9_-]\{6\}\)[A-Za-z0-9_-]*\(\.[A-Za-z0-9_-]\{4\}\).*/\1****REDACTED***\2.../' >> "$FINDINGS_FILE" || true

# Pattern 8: Slack tokens (xox[bpaso]-...)
echo "--- Slack Tokens ---" >> "$FINDINGS_FILE"
grep -n -E 'xox[bpaso]-[A-Za-z0-9-]{10,}' "$SCAN_INPUT" | \
  sed 's/\(xox[bpaso]-[A-Za-z0-9-]\{6\}\)[A-Za-z0-9-]*/\1****REDACTED/' >> "$FINDINGS_FILE" || true

# Pattern 9: Google API keys (AIza...)
echo "--- Google API Keys ---" >> "$FINDINGS_FILE"
grep -n -E 'AIza[0-9A-Za-z_-]{35}' "$SCAN_INPUT" | \
  sed 's/\(AIza[0-9A-Za-z_-]\{4\}\)[0-9A-Za-z_-]*/\1****REDACTED/' >> "$FINDINGS_FILE" || true

# Pattern 10: Stripe API keys (sk_live_, pk_live_, sk_test_, rk_live_)
echo "--- Stripe API Keys ---" >> "$FINDINGS_FILE"
grep -n -E '(sk_live_|pk_live_|rk_live_|sk_test_)[0-9a-zA-Z]{24,}' "$SCAN_INPUT" | \
  sed 's/\(\(sk\|pk\|rk\)_\(live\|test\)_[0-9a-zA-Z]\{6\}\)[0-9a-zA-Z]*/\1****REDACTED/' >> "$FINDINGS_FILE" || true

echo "" >> "$FINDINGS_FILE"
echo "=== RAW SCAN COMPLETE ===" >> "$FINDINGS_FILE"

# Count non-empty finding lines (excluding headers/separators)
FINDING_LINES=$(grep -v -E '^(---|===|Timestamp|Scope|$)' "$FINDINGS_FILE" | grep -c '[0-9]' || true)
echo "Raw matches found: $FINDING_LINES"
```

## Step 3 — False positive filtering

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

Prompt:
"You are a security analyst reviewing raw pattern-match output for false positive elimination.

Read the raw findings file at `./plans/secrets-scan-[TIMESTAMP].raw-findings.txt`.

**Your task:**

Review each finding and classify as CONFIRMED or FALSE_POSITIVE.

**False positive indicators — classify as FALSE_POSITIVE if:**
- The match is in a test fixture file (e.g., path contains: `test/`, `tests/`, `spec/`, `fixtures/`, `__tests__/`, `testdata/`)
- The match is in a documentation file (`.md`, `.rst`, `.txt`, `.adoc`) showing an example format
- The match is in a comment explaining what a secret LOOKS LIKE (e.g., `# example: AKIA...`)
- The match is an obvious placeholder (e.g., `AKIAIOSFODNN7EXAMPLE`, `your-secret-here`, `<YOUR_API_KEY>`, `xxx...xxx`)
- The match is in a `.env.example`, `.env.sample`, or `.env.template` file
- The match is in a README or CONTRIBUTING file describing configuration
- The value is clearly a test/dummy value (e.g., `password: 'test'`, `password: 'secret'` in test files)
- The match is in a mock or stub (file path contains `mock`, `stub`, `fake`)

**Confirmed secret indicators — classify as CONFIRMED if:**
- The match appears in a source code file that would be executed
- The match appears in a configuration file that is NOT an example/template
- The match appears in a script file
- The match appears in a Dockerfile or docker-compose file
- The value appears to be a real credential format (not a placeholder)
- The match appears in a git diff as an added line (lines starting with '+' in staged scope)

**CRITICAL REDACTION RULE:** Your output must NEVER include actual secret values. The raw findings file already has patterns redacted. Do NOT attempt to reconstruct or show the original value. Report type, file path, and line number only.

Write your analysis to `./plans/secrets-scan-[TIMESTAMP].filtered-findings.md`:

```
## Secrets Scan Filtered Findings

**Scope:** [staged/all/history]
**Timestamp:** [TIMESTAMP]

### Confirmed Secrets

| # | Type | File | Line | Severity | Notes |
|---|------|------|------|----------|-------|
[rows for each confirmed finding]

[Or: 'No confirmed secrets detected.']

### False Positives Excluded

| Type | File | Reason |
|------|------|--------|
[rows for each excluded finding]

[Or: 'No false positives to exclude.']

### Summary
- Total pattern matches: [N]
- Confirmed secrets: [N]
- False positives excluded: [N]
```"

## Step 4 — Verdict gate

Tool: `Read` (direct — coordinator does this)

Read `./plans/secrets-scan-[TIMESTAMP].filtered-findings.md` and count confirmed secrets.

**Verdict rules — zero tolerance:**

- **BLOCKED:** Any confirmed secret detected (count > 0). No exceptions. No thresholds.
- **PASS:** Zero confirmed secrets detected.

There is no PASS_WITH_NOTES for secrets — a secret is either present or it is not.

**If BLOCKED:**

Output immediately:
```
BLOCKED — Secrets detected in [scope] scan.

Confirmed secrets found: [count]

[List each: type + file:line — NO actual secret values]

Remove all confirmed secrets before committing or shipping.
Options:
1. Remove the secret and rotate the credential (strongly recommended)
2. Add the file to .gitignore if it must not be committed
3. Use environment variables or a secrets manager instead
4. If this is a test fixture or example, rename the file to include 'example' or 'fixture' and use obviously fake values

Run /secrets-scan again after remediation to verify.
```

Stop workflow. Do not proceed to Step 5 if BLOCKED.

**If PASS:**

Proceed to Step 5.

## Step 5 — Report generation and archive

Tool: `Task` (report) + `Bash` (archive)

**Generate final report:**

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5`

Prompt:
"Generate a final secrets scan report.

Read `./plans/secrets-scan-[TIMESTAMP].filtered-findings.md`.

Write the final report to `./plans/secrets-scan-[TIMESTAMP].report.md`:

```
# Secrets Scan Report

**Date:** [TIMESTAMP]
**Scope:** [staged/all/history]
**Verdict:** PASS

## Summary

No secrets detected in [scope] scan.

Pattern categories checked:
- AWS Access Keys (AKIA... format)
- AWS Secret Access Keys (labeled assignments)
- GitHub Personal Access Tokens (ghp_, gho_, ghu_, ghs_, ghr_)
- Private Key Material (RSA, EC, DSA, OpenSSH)
- Generic Passwords (labeled high-confidence patterns)
- Database Connection Strings (with embedded credentials)
- JWT Tokens
- Slack Tokens (xox[bpaso]-)
- Google API Keys (AIza...)
- Stripe API Keys (sk_live_, pk_live_, rk_live_)

## False Positives Excluded
[List from filtered findings, or 'None']

## Recommendations

For production use, consider also deploying:
- `trufflehog` (https://github.com/trufflesecurity/trufflehog) — entropy-based scanning
- `gitleaks` (https://github.com/zricethezax/gitleaks) — pre-commit hook integration
- A secrets manager (AWS Secrets Manager, HashiCorp Vault, etc.) to eliminate secrets from code entirely

Note: v1.0.0 uses pattern-based detection. Entropy-based detection (for unstructured secrets) is planned for v1.1.0.
```"

**Archive artifacts:**

Tool: `Bash`

```bash
mkdir -p ./plans/archive/secrets-scan/${TIMESTAMP}
mv ./plans/secrets-scan-${TIMESTAMP}.scan-target.txt \
   ./plans/secrets-scan-${TIMESTAMP}.raw-findings.txt \
   ./plans/secrets-scan-${TIMESTAMP}.filtered-findings.md \
   ./plans/archive/secrets-scan/${TIMESTAMP}/ 2>/dev/null || true
echo "Archived intermediate artifacts to ./plans/archive/secrets-scan/${TIMESTAMP}/"
echo "Final report: ./plans/secrets-scan-${TIMESTAMP}.report.md"
```

**Final output:**

"Secrets scan PASS. No secrets detected in [scope] scan.
Report: `./plans/secrets-scan-[TIMESTAMP].report.md`
Archived artifacts: `./plans/archive/secrets-scan/[TIMESTAMP]/`"
