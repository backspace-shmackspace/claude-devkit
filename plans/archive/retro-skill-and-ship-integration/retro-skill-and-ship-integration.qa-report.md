# QA Report: /retro Skill and /ship Integration

**Plan:** `plans/retro-skill-and-ship-integration.md`
**QA Agent:** qa-engineer (qa-engineer-base.md v1.8.0)
**Date:** 2026-03-12
**Validation command:** `python3 generators/validate_skill.py skills/retro/SKILL.md && python3 generators/validate_skill.py skills/ship/SKILL.md`

---

## Verdict: FAIL

The implementation contains one blocking defect: `skills/retro/SKILL.md` fails `validate_skill.py` with exit code 1. Acceptance criterion 1 (validator exits 0) is not met. The root cause is a step-header format mismatch between what the retro skill uses and what the validator regex accepts.

All other acceptance criteria (2-31) are met.

---

## Acceptance Criteria Coverage

| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | `skills/retro/SKILL.md` exists and passes `validate_skill.py` with exit 0 | NOT MET | Validator exits 1 with 2 errors (see Finding F-1) |
| 2 | Retro skill follows Scan archetype (parallel scans, synthesis, verdict gate, archive) | MET | Steps 1-3 are parallel Task subagents; Step 4 synthesizes; Step 5 has verdict gate and archive |
| 3 | Retro skill has 6 numbered steps matching `## Step N -- [Action]` format | PARTIAL | 6 steps exist and use `## Step N -- [Action]` format, but this exact format is rejected by the validator regex (see F-1). The plan's criterion text describes the format used; the validator does not accept it. |
| 4 | Retro skill has frontmatter: name=retro, model=claude-opus-4-6, version=1.0.0 | MET | Frontmatter confirmed: `name: retro`, `model: claude-opus-4-6`, `version: 1.0.0` |
| 5 | Retro skill supports 3 scope modes: recent, full, feature-name | MET | All 3 modes implemented in Step 0 with validation and fail-fast |
| 6 | Retro skill uses git log for "recent" scope ordering (not filesystem mtime) | MET | `git log --diff-filter=A --name-only` used in Step 0 bash block |
| 7 | Retro skill uses glob-based artifact discovery (not constructed paths) | MET | Step 0 instructs glob discovery for `*.code-review.md`, `*.qa-report.md`, `*.test-failure.log` per feature directory |
| 8 | Retro scan subagent prompts include severity ratings (Critical/High/Medium/Low) | MET | All 3 subagent prompts (Steps 1, 2, 3) include explicit severity rating instructions |
| 9 | Retro scan subagent prompts are format-resilient (no assumed section headers) | MET | Each prompt includes "Extract findings regardless of the specific section header format used" |
| 10 | Retro skill writes to `.claude/learnings.md` with the defined schema | MET | Step 5 creates/edits `.claude/learnings.md` with date prefix, sections, `Seen in:`, hash tags |
| 11 | Retro skill creates timestamped scan artifacts in `./plans/` | MET | Steps 1-3 write `retro-[timestamp].coder-scan.md`, `.reviewer-scan.md`, `.test-scan.md`; Step 4 writes `retro-[timestamp].summary.md` |
| 12 | Retro skill archives scan artifacts to `./plans/archive/retro/[timestamp]/` | MET | Step 5 bash block: `mkdir -p ./plans/archive/retro/[timestamp]` and `mv ./plans/retro-[timestamp].*` |
| 13 | Retro skill has 3 verdict outcomes: LEARNINGS_FOUND, NO_NEW_LEARNINGS, INSUFFICIENT_DATA | MET | All three defined in Step 4 and handled in Step 5 |
| 14 | Single-feature mode can cross-reference against existing learnings (not always INSUFFICIENT_DATA) | MET | Step 4 verdict rules explicitly state: single-feature mode returns INSUFFICIENT_DATA only when no existing `.claude/learnings.md` exists to cross-reference |
| 15 | Ship skill version is 3.4.0 in frontmatter | MET | `version: 3.4.0` confirmed in `skills/ship/SKILL.md` frontmatter |
| 16 | Ship Step 6 archives `.test-failure.log` when it exists | MET | Step 6 contains conditional bash block: `if [ -f "./plans/[name].test-failure.log" ]; then mv ...` |
| 17 | Ship skill has Step 7 (Retro capture) after Step 6 | MET | `## Step 7 -- Retro capture (post-commit, non-blocking)` present at line 625 |
| 18 | Ship Step 7 is non-blocking (failure does not affect commit) | MET | Step 7 explicitly states "This step is non-blocking" and failure path outputs error without stopping workflow |
| 19 | Ship Step 7 trigger condition: Step 6 committed successfully | MET | "Trigger: Step 6 committed successfully (PASS or PASS_WITH_NOTES verdict). If Step 6 did not commit (FAIL), skip Step 7 entirely." |
| 20 | Ship Step 7 auto-commits `.claude/learnings.md` after writing | MET | Post-Task bash block uses `git diff`/`git ls-files` to detect changes and commits with appropriate message |
| 21 | Ship Step 7 subagent prompts are format-resilient and include severity ratings | MET | Prompt includes "Extract findings regardless of the specific section header format used" and severity rating instructions |
| 22 | Ship Step 3c prompt references `.claude/learnings.md` Coder Patterns section | MET | "If the file `.claude/learnings.md` exists, read the `## Coder Patterns` section before starting implementation." |
| 23 | Ship Step 4a prompt references `.claude/learnings.md` for reviewer calibration | MET | Prompt references `## Coder Patterns > ### Missed by coders, caught by reviewers` and `## Reviewer Patterns > ### Overcorrected` |
| 24 | Ship Step 4c prompt references `.claude/learnings.md` for QA patterns | MET | "read the `## QA Patterns` and `## Test Patterns` sections" |
| 25 | Ship skill passes `validate_skill.py` with exit 0 | MET | Validator exits with PASS (with warnings). Warning is non-blocking (timestamped artifacts advisory for ship). |
| 26 | CLAUDE.md Skill Registry includes retro entry (v1.0.0, Scan, 6 steps) | MET | Row present: `\| **retro** \| 1.0.0 \| ... \| opus-4-6 \| 6 \|` |
| 27 | CLAUDE.md Skill Registry shows ship v3.4.0 with 8 steps | MET | Row present: `\| **ship** \| 3.4.0 \| ... \| opus-4-6 \| 8 \|` |
| 28 | CLAUDE.md Artifact Locations section includes retro artifacts and `.claude/learnings.md` | MET | `retro-[timestamp].coder-scan.md`, `.reviewer-scan.md`, `.test-scan.md`, `.summary.md`, `archive/retro/retro-[timestamp]/`, and `.claude/learnings.md` note all present |
| 29 | Learnings schema includes date prefix, Seen in list, and hash tags | MET | Date prefix `[YYYY-MM-DD]`, `Seen in:`, and `#category #tags` all present in both retro Step 5 and ship Step 7 subagent prompt |
| 30 | Deduplication uses semantic guidance (not numeric token overlap threshold) | MET | Deduplication language: "same underlying issue (same root cause, same actor, same category)" — no numeric threshold |
| 31 | Generator test suite (`test_skill_generator.sh`) still passes (26 tests) | MET | Suite passes with 33 tests (test count grew from plan's stated 26 — this is acceptable; all pass with 0 failures) |

---

## Findings

### F-1 (BLOCKING): retro SKILL.md step headers fail validator — wrong separator format

**Severity:** Critical

**Evidence:**
```
Skill Validation Report
File: skills/retro/SKILL.md
Skill: retro (v1.0.0)

✗ Errors (2):
  • Minimum Steps: Skill must have at least 2 numbered workflow steps. Found: 0
  • Numbered Steps: Pattern 2 (Numbered Steps): All workflow steps must use format
    '## Step N -- [Action]' or '## Step N — [Action]'.
```

**Root cause:** The validator regex is:
```python
step_pattern = r'^## Step (\d+)( —|--) (.+)$'
```
This regex accepts either:
- `## Step N — ` (space + em dash `\u2014`)
- `## Step N-- ` (no space before double-hyphen)

The retro SKILL.md uses `## Step N -- ` (space before double-hyphen). The space preceding `--` causes the regex not to match because `\d+` captures the digit, and the alternation `( —|--)` expects to start immediately after the digit — matching ` —` (space + em dash) or `--` (no leading space). With a space before `--`, neither branch matches.

All six step headers in `skills/retro/SKILL.md` are affected:
- Line 19: `## Step 0 -- Determine scope and discover artifacts`
- Line 81: `## Step 1 -- Scan: Coder calibration (parallel with Steps 2, 3)`
- Line 138: `## Step 2 -- Scan: Reviewer calibration (parallel with Steps 1, 3)`
- Line 193: `## Step 3 -- Scan: Test pattern analysis (parallel with Steps 1, 2)`
- Line 257: `## Step 4 -- Synthesis and deduplication`
- Line 339: `## Step 5 -- Write learnings and verdict gate`

**Note:** Ship's Step 7 (line 625) has the same format (`## Step 7 -- Retro capture`), but ship passes validation because its other 7 steps (0-6) use em dash and are found by the validator.

**Required fix:** Change all six step headers in `skills/retro/SKILL.md` from `## Step N -- ` to `## Step N — ` (em dash). Alternatively, change to `## Step N-- ` (no space before `--`). The em dash form is preferred (matches Steps 0-6 of ship skill and all other skills in this repo).

Also fix ship Step 7 at line 625 from `## Step 7 -- ` to `## Step 7 — ` for consistency, though this is non-blocking since ship still passes validation.

---

### F-2 (NON-BLOCKING): Plan states "26 tests" but test suite has 33

**Severity:** Low / Informational

The plan's acceptance criterion 31 references "26 tests" and the Test Plan section says "This ensures the existing 26 tests still pass." The test suite currently has 33 tests and all pass. The test count grew after the plan was written. This is not a defect in the implementation — acceptance criterion 31 is met. The plan description is stale.

---

### F-3 (NON-BLOCKING): Ship skill validator warning on timestamped artifacts

**Severity:** Low / Informational

`validate_skill.py` on `skills/ship/SKILL.md` exits with PASS but emits:
```
⚠ Warnings (1):
  • Timestamped Artifacts: Pattern 5 (Timestamped Artifacts): Consider using timestamped
    filenames (e.g., [timestamp] placeholder or ISO format) for artifact outputs.
```
This is pre-existing (not introduced by this change) and non-blocking. Ship's primary artifacts (`[name].code-review.md`, `[name].qa-report.md`) use plan-name-based naming, not timestamps. The validator pattern is advisory for this skill type.

---

## Missing Tests or Edge Cases

The following test scenarios from the plan's Manual Validation Tests table have not been executed (they require a live Claude Code session):

1. **Retro no-archives error path** — `/retro` in project with no `plans/archive/`: plan says it should stop with a clear error. The fail-fast logic exists in the skill (exits if `$FEATURE_COUNT` is 0) but has not been smoke-tested.

2. **Ship Step 7 non-blocking under archive-empty condition** — Simulating an empty archive to confirm Step 6 success is still reported after Step 7 failure. The non-blocking language is correct in the skill but untested end-to-end.

3. **Deduplication idempotency** — Running `/retro` twice on the same archives to confirm no duplicate entries appear. Semantic guidance is in place but not validated against actual model behavior.

4. **Staleness flagging** — The summary schema includes a `## Stale Learnings (>90 days)` section but there is no automated check that populates it in Step 4. The Step 4 synthesis instructions describe reading existing learnings and categorizing, but do not explicitly instruct the coordinator to flag stale entries (entries older than 90 days). This is a gap in the Step 4 prose relative to the summary schema output.

---

## Notes (Non-Blocking Observations)

- **Step header inconsistency within ship skill:** Steps 0-6 use em dash (`—`), Step 7 uses double-hyphen with leading space (`--`). This is inconsistent but does not affect ship validation (7 steps still found). Cleaning it up alongside the retro fix would make both files uniform.

- **Learnings consumption is optional, not enforced:** Steps 3c, 4a, and 4c in ship all use "If the file `.claude/learnings.md` exists" language. This is correct per the plan's design (learnings are opt-in). However, there is no mechanism to verify that agents actually read and apply the learnings vs. silently ignoring the conditional. This is an acknowledged risk in the plan's Risk Assessment section.

- **Step 7 Reviewer Patterns gap:** The Step 7 subagent prompt (ship) maps code review findings to `## Coder Patterns` and QA findings to `## QA Patterns`, but does not populate `## Reviewer Patterns` (high-value checks, overcorrections). The standalone `/retro` skill does populate Reviewer Patterns via the dedicated Step 2 reviewer calibration scan. This asymmetry is by design (Step 7 is lightweight; `/retro` is the full-featured path) but is not explicitly documented as a known limitation.

- **`.claude/` directory creation:** The retro skill Step 5 says "If `.claude/learnings.md` does not exist, create it with the full schema." The `Write` tool creates parent directories, but the skill does not include an explicit `mkdir -p .claude/` call. This is fine in practice but is a minor documentation gap relative to the plan's Risk Assessment entry about the `.claude/` directory.

---

## Summary

One blocking defect prevents the implementation from meeting its stated acceptance criteria. The retro skill exists and is functionally complete, but its step headers use a separator format (`-- ` with a leading space) that the validator regex does not recognize. The fix is a mechanical find-and-replace of all six step header separators in `skills/retro/SKILL.md`. No logic changes are required.

| Category | Count |
|----------|-------|
| Blocking findings | 1 (F-1) |
| Non-blocking findings | 2 (F-2, F-3) |
| Acceptance criteria met | 30 / 31 |
| Acceptance criteria not met | 1 / 31 (criterion 1; criterion 3 partially met) |
| Generator tests | 33 / 33 pass |
