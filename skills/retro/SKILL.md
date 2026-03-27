---
name: retro
description: Mine review artifacts for recurring patterns and write project learnings.
version: 1.0.0
model: claude-opus-4-6
---
# /retro Workflow

## Inputs
- Scope: $ARGUMENTS (optional: "recent", "full", or a feature name)
  - `recent`: Last 3 archived features (default)
  - `full`: All archived features
  - `<name>`: Single feature archive (e.g., "add-user-auth")

## Role
You are the **retro coordinator**. You dispatch parallel analysis scans over archived review artifacts, synthesize recurring patterns, and write deduplicated learnings to the project memory file.
You do NOT fix code or modify agents — you extract and record patterns.

## Step 0 — Determine scope and discover artifacts

Tool: `Bash`, `Glob` (direct — coordinator does this)

**Determine scope:**
- If `$ARGUMENTS` is empty: scope = "recent"
- Else: scope = `$ARGUMENTS`

Validate scope:
- If scope is "recent", "full", or matches an existing directory in `plans/archive/`: proceed
- Else: stop with "Invalid scope. Use: /retro [recent|full|<feature-name>]"

Derive timestamp: `[timestamp]` = current ISO datetime (e.g., `2026-03-12T10-00-00`)

**Discover artifacts:**

Tool: `Bash`

```bash
ARCHIVE_DIR="./plans/archive"

if [ "$SCOPE" = "recent" ]; then
  # Get 3 most recently added feature directories (by git commit date, excluding sync/ and audit/)
  FEATURES=$(git log --diff-filter=A --name-only --format='' -- "$ARCHIVE_DIR"/*/ \
    | grep -E '^plans/archive/[^/]+/$' \
    | grep -v '/sync/' | grep -v '/audit/' \
    | sed 's|plans/archive/||;s|/||' \
    | awk '!seen[$0]++' \
    | head -3)
elif [ "$SCOPE" = "full" ]; then
  FEATURES=$(ls -d "$ARCHIVE_DIR"/*/ 2>/dev/null | grep -v '/sync/$' | grep -v '/audit/$' | xargs -I{} basename {})
else
  # Single feature
  if [ -d "$ARCHIVE_DIR/$SCOPE" ]; then
    FEATURES="$SCOPE"
  else
    echo "No archive found for feature: $SCOPE"
    exit 1
  fi
fi

echo "Features to analyze: $FEATURES"
FEATURE_COUNT=$(echo "$FEATURES" | wc -w | tr -d ' ')
echo "Total features: $FEATURE_COUNT"
```

**Fail fast if no artifacts:**
- If `$FEATURE_COUNT` is 0: stop with "No archived features found in plans/archive/. Run /ship on at least one feature first."

**Collect artifact paths (glob-based discovery):**

For each feature in `$FEATURES`, use glob to discover artifacts:
- `plans/archive/<feature>/*.code-review.md` (all code review files in the directory)
- `plans/archive/<feature>/*.qa-report.md` (all QA report files in the directory)
- `plans/archive/<feature>/*.test-failure.log` (all test failure logs in the directory)

Log any feature directories that contain no code-review or QA artifacts: "Skipping <feature>: no review artifacts found."

Remove features with zero artifacts from the scan set. Re-check `$FEATURE_COUNT` after filtering.

Store the feature list and discovered artifact paths for use in Steps 1-3.

## Step 1 — Scan: Coder calibration (parallel with Steps 2, 3)

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-6`

Prompt:
"You are analyzing code review artifacts to identify coder behavior patterns.

Read the following code review files:
[list all discovered *.code-review.md paths from Step 0]

Read each code review file in its entirety. Extract findings regardless of the specific section header format used. Look for issues categorized by severity (critical, major, minor) or described as problems, concerns, or areas for improvement. Also look for positive feedback or things done well, regardless of what section header they appear under.

For each code review, extract:
1. **Critical/Major findings** — These represent things the coder missed. Rate each: Critical / High / Medium / Low.
2. **Positives** — These represent things the coder did well
3. **Feature name** — The feature being reviewed (use the archive directory name)

Then analyze across all reviews to identify:

### Recurring coder mistakes (caught by reviewers)
Patterns that appear in 2+ reviews. For each:
- Pattern name (concise, descriptive)
- Severity: Critical / High / Medium / Low
- Description (what the coder keeps missing)
- Features where this occurred (Seen in: list)
- Category tags (#coder #<topic>)

### Coder strengths (consistently done well)
Patterns that appear as Positives in 2+ reviews.

### One-off issues (appeared only once)
List but mark as non-recurring. Include severity rating.

Write to `./plans/retro-[timestamp].coder-scan.md` with this structure:

```markdown
# Coder Calibration Scan — [timestamp]

## Recurring Mistakes (caught by reviewers)
- **[Pattern Name]** [Severity] — [Description]. Seen in: [feature1, feature2]. #coder #tag
...

## Coder Strengths
- **[Pattern Name]** — [Description]. Seen in: [feature1, feature2]. #coder #tag
...

## One-Off Issues
- **[Issue]** [Severity] — [Description]. Seen in: [feature]. #coder #tag
...

## Statistics
- Features analyzed: N
- Code reviews found: N
- Recurring patterns: N
- One-off issues: N
```"

## Step 2 — Scan: Reviewer calibration (parallel with Steps 1, 3)

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-6`

Prompt:
"You are analyzing code review artifacts to identify reviewer behavior patterns.

Read the following code review files:
[list all discovered *.code-review.md paths from Step 0]

Also read the QA reports for cross-reference:
[list all discovered *.qa-report.md paths from Step 0]

Read each file in its entirety. Extract findings regardless of the specific section header format used. Look for verdicts, issues by severity, and any observations about code quality, regardless of how the review is structured.

For each code review, extract:
1. **Verdict** — Was the review correct? (Compare review verdict with QA verdict if available)
2. **Critical/Major findings** — What the reviewer flagged. Rate each: Critical / High / Medium / Low.
3. **Minor findings** — Were these valuable or noise?

Then analyze across all reviews to identify:

### High-value reviewer checks (consistently valid findings)
Findings that appear across 2+ reviews and are confirmed by QA. Include severity rating.

### Reviewer overcorrections (false positives or low-value flags)
Findings that the reviewer flagged but QA did not confirm, or that appear repeatedly as Minor without being actionable. Rate severity of impact.

### Missed by reviewers, caught by QA
Issues in QA reports that the code reviewer did not flag. Rate severity.

Write to `./plans/retro-[timestamp].reviewer-scan.md` with this structure:

```markdown
# Reviewer Calibration Scan — [timestamp]

## High-Value Checks (consistently valid)
- **[Pattern Name]** [Severity] — [Description]. Seen in: [feature1, feature2]. #reviewer #tag
...

## Overcorrections (false positives)
- **[Pattern Name]** [Severity] — [Description]. Seen in: [feature1, feature2]. #reviewer #tag
...

## Missed by Reviewer, Caught by QA
- **[Pattern Name]** [Severity] — [Description]. Seen in: [feature1, feature2]. #reviewer #qa #tag
...

## Statistics
- Features analyzed: N
- Reviews with PASS verdict: N
- Reviews with REVISION_NEEDED verdict: N
- Overcorrection patterns: N
```"

## Step 3 — Scan: Test pattern analysis (parallel with Steps 1, 2)

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-6`

Prompt:
"You are analyzing QA reports and test failure logs to identify testing patterns.

Read the following QA reports:
[list all discovered *.qa-report.md paths from Step 0]

Read the following test failure logs (if any exist):
[list all discovered *.test-failure.log paths from Step 0]

Note: Test failure logs may not exist for all (or any) archives. If no test failure logs are found, base your analysis on QA reports only and note this in your statistics.

Read each file in its entirety. Extract findings regardless of the specific section header format used. Look for test failures, missing coverage, edge cases, and infrastructure issues regardless of how the report is structured.

For each QA report, extract:
1. **Missing tests or edge cases** — Gaps the QA found
2. **Coverage observations** — What was well-tested vs. under-tested
3. **Acceptance criteria that were NOT met** — Systemic gaps

For each test failure log, extract:
1. **Failure patterns** — What types of tests failed
2. **Root cause categories** — Configuration, logic, async, fixture, etc.

Rate each finding: Critical / High / Medium / Low.

Then analyze across all artifacts to identify:

### Recurring test failures
Error patterns that appear in 2+ features. Include severity rating.

### Recurring coverage gaps
QA findings that appear in 2+ features. Include severity rating.

### Test infrastructure issues
Problems with test setup, fixtures, or environment. Include severity rating.

Write to `./plans/retro-[timestamp].test-scan.md` with this structure:

```markdown
# Test Pattern Scan — [timestamp]

## Recurring Test Failures
- **[Pattern Name]** [Severity] — [Description]. Seen in: [feature1, feature2]. #test #tag
...

## Recurring Coverage Gaps
- **[Pattern Name]** [Severity] — [Description]. Seen in: [feature1, feature2]. #qa #coverage #tag
...

## Test Infrastructure Issues
- **[Issue]** [Severity] — [Description]. Seen in: [feature1, feature2]. #test #infra #tag
...

## Statistics
- Features analyzed: N
- QA reports found: N
- Test failure logs found: N
- Recurring failure patterns: N
- Coverage gap patterns: N
```"

## Step 4 — Synthesis and deduplication

Tool: `Read` (direct — coordinator does this)

Read all three scan reports:
- `./plans/retro-[timestamp].coder-scan.md`
- `./plans/retro-[timestamp].reviewer-scan.md`
- `./plans/retro-[timestamp].test-scan.md`

Read existing learnings (if any):
- `.claude/learnings.md` (may not exist)

**Synthesize:**

For each recurring pattern from the scan reports:
1. Read all existing entries in the target section of `.claude/learnings.md`
2. If an existing learning describes the same underlying issue (same root cause, same actor, same category): mark for update (append new `Seen in:` features, update date)
3. If no existing learning matches the underlying issue: mark for addition under the appropriate section
4. Err on the side of creating new entries -- duplicates are easier to clean up than incorrectly merged patterns

**Categorize into learnings sections:**

| Scan Source | Learning Section |
|-------------|-----------------|
| Coder recurring mistakes | `## Coder Patterns > ### Missed by coders, caught by reviewers` |
| Coder strengths | Not written to learnings (positive reinforcement is implicit) |
| Reviewer high-value checks | `## Reviewer Patterns > ### Consistently caught` |
| Reviewer overcorrections | `## Reviewer Patterns > ### Overcorrected` |
| Missed by reviewer, caught by QA | `## QA Patterns > ### Coverage gaps` |
| Recurring test failures | `## Test Patterns > ### Common failures` |
| Recurring coverage gaps | `## QA Patterns > ### Coverage gaps` |
| Test infrastructure issues | `## Test Patterns > ### Flaky tests` or `### Common failures` |

**Generate summary:**

Write `./plans/retro-[timestamp].summary.md`:

```markdown
# Retro Summary — [scope] — [timestamp]

## Verdict
[LEARNINGS_FOUND / NO_NEW_LEARNINGS / INSUFFICIENT_DATA]

## New Learnings
[Count: N]
- [Learning 1 — brief description]
- [Learning 2 — brief description]
...

## Updated Learnings (existing patterns seen again)
[Count: N]
- [Learning 1 — added features to Seen in list]
...

## Stale Learnings (>90 days since last occurrence)
[Count: N]
- [Learning 1 — last seen YYYY-MM-DD]
...

## Statistics
- Features analyzed: N
- Code reviews mined: N
- QA reports mined: N
- Test failure logs mined: N
- Total recurring patterns found: N
- New learnings added: N
- Existing learnings updated: N
- Stale learnings flagged: N

## Reports
- Coder scan: ./plans/retro-[timestamp].coder-scan.md
- Reviewer scan: ./plans/retro-[timestamp].reviewer-scan.md
- Test scan: ./plans/retro-[timestamp].test-scan.md
```

**Verdict rules:**
- **LEARNINGS_FOUND**: At least 1 new or updated learning
- **NO_NEW_LEARNINGS**: All patterns already exist in learnings.md and no updates needed
- **INSUFFICIENT_DATA**: Fewer than 2 features analyzed AND no existing `.claude/learnings.md` to cross-reference against (cannot identify recurring patterns and cannot update existing ones)

Note: Single-feature mode (`/retro <feature-name>`) can still produce LEARNINGS_FOUND if it finds patterns that match existing learnings in `.claude/learnings.md` (updating `Seen in:` lists counts as an update). It only returns INSUFFICIENT_DATA when there are no existing learnings to cross-reference against.

## Step 5 — Write learnings and verdict gate

Tool: `Read`, `Write` or `Edit` (direct — coordinator does this)

**If verdict is INSUFFICIENT_DATA:**
Output: "Not enough data to identify recurring patterns. Run /ship on more features and try again, or run /retro full after building up a learnings baseline.

Summary: ./plans/retro-[timestamp].summary.md"

Skip writing to `.claude/learnings.md`. Continue to archive step.

**If verdict is NO_NEW_LEARNINGS:**
Output: "No new patterns found. Existing learnings are current.

Summary: ./plans/retro-[timestamp].summary.md"

Skip writing to `.claude/learnings.md`. Continue to archive step.

**If verdict is LEARNINGS_FOUND:**

If `.claude/learnings.md` does not exist, create it with the full schema (header + all sections).

If `.claude/learnings.md` exists, use Edit to:
1. Update the `Last updated:` timestamp in the header
2. For updated learnings: find the existing entry, update the date prefix, and append new feature names to `Seen in:`
3. For new learnings: append under the appropriate section

Output:
"New learnings written to .claude/learnings.md:

[List each new/updated learning with its section]

Summary: ./plans/retro-[timestamp].summary.md

Agents in future /ship runs will reference these learnings."

**Archive scan artifacts:**

Tool: `Bash`

```bash
mkdir -p "./plans/archive/retro/[timestamp]"
mv ./plans/retro-[timestamp].* "./plans/archive/retro/[timestamp]/"
```

Output: "Retro scan complete. Reports archived to ./plans/archive/retro/[timestamp]/"
