# Feasibility Review: `/fix` Skill for Targeted Finding Remediation

**Plan:** `plans/fix-skill.md` (Rev 2)
**Reviewer:** Code reviewer (technical feasibility), Round 2
**Date:** 2026-05-23

## Verdict: PASS

Both Major findings from Round 1 are resolved. The revision introduced two new Minor concerns
related to scope validation interacting with a dirty working directory (Assumption 7). Neither
blocks implementation. No new Critical or Major issues.

---

## Round 1 Resolution Status

### Major Findings

**M-01: Multi-line YAML description (RESOLVED)**

The plan now specifies a single-line `description:` in the frontmatter (lines 142-143):

```yaml
description: Apply targeted fixes for specific findings from code reviews, security reviews, QA reports, or audit scans.
```

This will parse correctly with `validate_skill.py`'s line-by-line `key: value` parser. Confirmed
by tracing through `parse_frontmatter()` -- the line splits on the first `:`, producing
key=`description` and value=`Apply targeted fixes...`. No junk entries.

**M-02: Step header format (RESOLVED)**

The revision log (line 9) explicitly states: "Change all step headers to em-dashes (feasibility
M-02)." The plan's step headers in the body use em-dashes (`#### Step 0 — Parse and locate
finding`). The Context Alignment table (line 852) specifies `## Step N — [Action]` with
em-dashes. Acceptance Criterion 8 (line 808) requires em-dashes. The implementer has
unambiguous direction.

Verified against the validator regex `^## Step (\d+)( —|--) (.+)$` -- the em-dash variant
matches the first alternative ` —` (space + em-dash). All 5 steps will be detected.

### Minor Findings (Round 1 status)

| ID | Status | Notes |
|----|--------|-------|
| m-01 (Role section) | Not addressed | Optional. Plan does not include a `## Role` section. Still recommended for runtime LLM adherence. |
| m-02 (Coder agent requirement) | Not addressed | Hard requirement retained. Consistent with `/ship`. Acceptable. |
| m-03 (Test insertion points) | Addressed | Revision log (line 9) confirms "Clarify test insertion points before cleanup blocks." Task Breakdown (lines 827-830) specifies "Insert before Test 50 (Cleanup) block" and "Insert before Test 9 (Cleanup) block" with header count updates. |
| m-04 (Bounded iteration wording) | Addressed | Plan now uses "Max 1 revision round" (lines 428, 432, 855). Matches validator regex `([Mm]ax \d+ (revision|round|iteration))`. |
| m-05 (Timestamped artifacts) | Addressed | Artifacts now include `[timestamp]` suffix (e.g., `fix-[finding-id]-[timestamp]-reverify.secure-review.md`). Pattern 5 validator regex `\[timestamp\]` will match. This finding is correctly listed in the Deviations table (line 877) with justification. |
| m-06 (Flat archive path) | Not addressed | Acceptable. Cosmetic concern, acknowledged as future improvement. |
| m-07 (Learnings section insertion) | Not addressed | Plan describes the "create if not exists" case (lines 527-528) but the "section heading does not exist in existing file" case is still implicit. Low risk -- append-to-end is the natural fallback for the Edit tool. |

---

## New Concerns (Introduced by Revision)

### Critical

None.

### Major

None.

### Minor

**m-08: Scope validation with dirty working directory may produce false positives**

The scope validation added in Rev 2 (F-03, lines 295-304) uses `git diff --name-only` to check
which files the coder modified. Assumption 7 (line 57) explicitly allows a dirty working
directory: "Git working directory may or may not be clean when `/fix` is invoked."

If the user has pre-existing uncommitted changes to files outside `$SCOPED_FILES`, those files
will appear in `git diff --name-only` and be flagged as out-of-scope modifications by the coder.
The plan then reverts them with `git checkout -- <out-of-scope-files>` (line 312), which would
**destroy the user's pre-existing uncommitted work** on those files.

**Example scenario:** User has uncommitted edits to `README.md`. User runs `/fix` on a finding
in `build.yaml`. The coder only modifies `build.yaml`, but `git diff --name-only` shows both
`build.yaml` and `README.md`. The scope check flags `README.md` as out-of-scope and runs
`git checkout -- README.md`, destroying the user's README edits.

**Risk:** Medium likelihood (Assumption 7 allows it), High impact (data loss).

**Recommendation:** The scope check should compare against a baseline snapshot taken **before**
the coder runs, not against a clean tree. Capture `git diff --name-only` before Step 2 coder
dispatch and diff the two lists:

```bash
# Before coder dispatch (Step 2, before Task):
PRE_FIX_FILES=$(git diff --name-only)

# After coder dispatch (scope validation):
POST_FIX_FILES=$(git diff --name-only)
CODER_MODIFIED=$(comm -13 <(echo "$PRE_FIX_FILES" | sort) <(echo "$POST_FIX_FILES" | sort))
```

This isolates only the files the coder actually changed. Files with pre-existing modifications
are excluded from scope enforcement.

**m-09: Secret pattern grep false positive rate may generate noise**

The lightweight secret pattern check (lines 326-329) runs against `git diff -U0`. Like m-08,
this operates on the full diff including pre-existing changes. However, the more practical
concern is false positive rate: the regex
`(api[_-]?key|...|private[_-]?key)\s*[:=]\s*["\x27][^\s]{8,}` will match legitimate patterns
like environment variable documentation, config file templates with placeholder values, and
test fixtures.

Since this is warning-only and non-blocking, the impact is low -- it adds noise. The plan
correctly specifies "Do not block" (line 332). No change required, but the SKILL.md implementer
should ensure the warning message is clear that this is a heuristic check, not a definitive
detection.

**Risk:** Low (warning only, non-blocking).

**Recommendation:** No change required. Implementer should ensure the warning clearly labels
matches as "possible" and recommends manual review rather than implying certainty.

---

## Validator Compliance Assessment (Updated)

With M-01 and M-02 resolved, re-checked the proposed SKILL.md against every validation rule:

| Check | Will Pass? | Notes |
|-------|-----------|-------|
| Valid YAML frontmatter | Yes | Single-line description, clean parsing |
| Required fields: name, description, model | Yes | All present |
| Model value in valid list | Yes | `claude-opus-4-6` is in `valid_models` |
| Workflow header | Yes | Plan specifies `# /fix Workflow` |
| `## Inputs` section | Yes | Plan describes inputs |
| Minimum 2 numbered steps | Yes | Steps 0-4 (5 steps) with em-dashes |
| Sequential step numbering | Yes | 0, 1, 2, 3, 4 |
| Non-empty steps | Yes | All steps have substantial content |
| Pattern 1 (Coordinator) | Yes | "dispatch", "coordinator" present |
| Pattern 2 (Numbered steps) | Yes | Em-dashes match regex |
| Pattern 3 (Tool declarations) | Yes | Each step specifies `Tool:` |
| Pattern 4 (Verdict gates) | Yes | PASS/FAIL/BLOCKED in Step 3 |
| Pattern 5 (Timestamped artifacts) | Yes | `[timestamp]` in artifact names now matches regex |
| Pattern 6 (Structured reporting) | Yes | References `./plans/` |
| Pattern 7 (Bounded iterations) | Yes | "Max 1 revision round" matches regex |
| Pattern 8 (Model selection) | Yes | Handled by frontmatter check |
| Pattern 9 (Scope parameters) | Yes | `## Inputs` section present |
| Pattern 10 (Archive on success) | Yes | References `./plans/archive/fix/` |

**Expected result:** PASS (no warnings). Improvement from Round 1 expected result (PASS with
1-2 warnings) due to timestamp and bounded iteration wording fixes.

---

## Recommended Adjustments

1. **(m-08, recommended)** Add a pre-coder baseline snapshot of `git diff --name-only` and diff
   against post-coder state, so scope validation only evaluates files the coder actually changed.
   Prevents data loss when the working directory is dirty (Assumption 7).

2. **(m-01, carried from Round 1, optional)** Include a `## Role` section in the SKILL.md.
   Improves runtime coordinator behavior. Not required for validation.
