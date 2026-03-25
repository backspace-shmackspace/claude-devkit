# Technical Implementation Plan: Journal Review Skill (`/journal-review`)

**Author:** Claude Opus 4.6
**Date:** 2026-02-24
**Status:** APPROVED
**Version:** 1.1.0
**Scope:** New contrib skill for periodic journal review — surfaces unlogged decisions, learnings, action items, and recurring themes from daily entries

---

## Goals

1. Create a `/journal-review` skill that scans daily and meeting entries over a configurable review period and extracts candidates for formal journal entries.
2. Surface **unlogged decisions** — decision-signal language in dailies without a corresponding `decisions/` ADR.
3. Surface **unlogged learnings** — learning-signal language in dailies without a corresponding `learnings/` entry.
4. Surface **untracked action items** — checkboxes, TODOs, and follow-ups that were never completed or formally tracked.
5. Surface **recurring themes** — topics, projects, or patterns that appear across multiple daily entries in the review period.
6. Present candidates grouped by category for user approval or dismissal via `AskUserQuestion`.
7. For approved items, create formal entries using the same templates and conventions as `/journal`.
8. Integrate into the contrib skill ecosystem alongside `/journal` and `/journal-recall`.

## Non-Goals

- Modifying existing journal entries (read-only scan; new entries only).
- Replacing `/journal-recall` weekly review functionality (that skill summarizes; this skill promotes).
- Building a dashboard or persistent tracking system for action items.
- Implementing NLP or ML-based semantic analysis — pattern matching uses signal-word heuristics, not embeddings.
- Automated scheduling (cron, hooks) — the user invokes the skill manually.
- Cross-referencing against external systems (JIRA, GitLab issues, etc.).

## Assumptions

1. The journal vault at `~/journal/` is the canonical location (matches `/journal` and `/journal-recall`).
2. Daily entries follow the template format with `## Work Sessions`, `## Decisions Made`, `## Learnings`, `## Tomorrow's Priorities` sections.
3. Meeting entries follow the template format with `## Action Items`, `## Decisions Made`, `## Follow-up` sections.
4. Existing `decisions/` entries use filenames of the form `YYYY-MM-DD-{topic}.md` and contain a `# ADR: {Decision Name}` heading.
5. Existing `learnings/` entries use filenames of the form `{topic}.md` and contain a `# Learning: {Topic Name}` heading.
6. The user runs this skill periodically (end of week, end of sprint) — it is not automated.
7. `validate_skill.py` at `~/projects/claude-devkit/generators/validate_skill.py` is functional and will be used for validation.
8. The `/journal` skill's embedded templates (daily, meeting, project, learning, decision) are the authoritative format for any new entries created by this skill.
9. Semantic similarity for cross-referencing is handled by the LLM at runtime (Claude reads both the candidate text and existing entry titles/content to determine if a match exists), not by string matching alone.

---

## Context Alignment

### Which CLAUDE.md patterns this plan follows

- **Pipeline archetype** (claude-devkit/CLAUDE.md v1.0.0): Sequential execution with checkpoints. The review workflow is: configure period, scan entries, extract candidates, cross-reference existing entries, present to user, create approved entries. Each step has a clear checkpoint.
- **Numbered steps** (Pattern 2): `## Step N -- [Action]` headers throughout.
- **Tool declarations** (Pattern 3): Every step declares which tools it uses.
- **Verdict gates** (Pattern 4): Final step reports `PASS: N entries created` or `PASS: no candidates found (reviewed N entries)`.
- **Scope parameters** (Pattern 9): Configurable review period via user input.
- **Model selection** (Pattern 8): `claude-opus-4-6` in frontmatter (skill runs in session context, no subagent delegation).
- **Contrib directory** (CLAUDE.md): Personal/opinionated skill in `contrib/` with opt-in deployment.

### Which prior plans this relates to or builds upon

- **`journal-skill-blueprint.md`** (APPROVED, 2026-02-24): Established the contrib/ directory, the two-skill journal system (`/journal` for write, `/journal-recall` for read), embedded templates, path sanitization, and deploy.sh --contrib support. This plan adds a third journal skill that builds on the same vault structure and template conventions.
- **`portfolio-review-next-steps.md`** (referenced in blueprint): The portfolio review identified "review" as a future capability beyond the initial journal/journal-recall split.

### Any deviations from established patterns, with justification

1. **Interactive approval via AskUserQuestion**: Unlike `/journal` (which writes immediately) and `/journal-recall` (which reads only), this skill has an interactive approval loop where the user reviews candidates before entries are created. This is a deliberate design choice — the skill surfaces suggestions, not certainties, so human judgment is required. The loop is bounded (one pass per category, no revision loops).

2. **No timestamped artifacts or archive-on-success (stub only)**: Like the other journal skills, the output is journal entries themselves, not intermediate artifacts. Stub sections explain this.

3. **Semantic cross-referencing by LLM judgment**: Rather than exact string matching or embedding-based similarity, the skill relies on the LLM (Claude, running the skill) to read candidate text alongside existing entry titles and determine whether a match exists. This is pragmatic — the journal vault is small enough to read relevant entries, and Claude's judgment is more accurate than keyword overlap for this domain.

4. **Bounded but user-controlled iteration**: The skill presents candidates per category and the user approves/dismisses each. This is bounded by the number of categories (4) and candidates (finite, extracted from a finite set of daily entries). There is no unbounded revision loop.

---

## Proposed Design

### Skill Architecture

| Property | Value |
|----------|-------|
| Name | `journal-review` |
| Version | 1.0.0 |
| Model | claude-opus-4-6 |
| Archetype | Pipeline |
| Steps | 6 (Step 0 through Step 5) |
| Location | `contrib/journal-review/SKILL.md` |
| Deployment | `./scripts/deploy.sh --contrib journal-review` |
| Prerequisites | `~/journal/` vault with `daily/`, `decisions/`, `learnings/`, `meetings/` directories |

### Full SKILL.md Content

The following is the complete, deployable SKILL.md file:

```markdown
---
name: journal-review
description: Periodic journal review — scans daily entries to surface unlogged decisions, unlogged learnings, untracked action items, and recurring themes. Use when the user says "journal audit", "review my entries for promotion", "extract decisions", "unlogged items", "what should I formalize", "untracked items", or wants to promote daily notes into formal entries. NOT for weekly summaries — use /journal-recall for "weekly review" or "review my journal".
model: claude-opus-4-6
version: 1.0.0
---

# /journal-review Workflow

## Inputs

**User provides:**
- Review period: "this week", "last week", "last N days", "this sprint", a date range (YYYY-MM-DD to YYYY-MM-DD), or omitted (defaults to "this week")
- Optional: category filter (decisions, learnings, actions, themes, or all)

**Scope parameters:**
- `JOURNAL_BASE`: `~/journal/` (hardcoded, matches /journal and /journal-recall skills)
- `REVIEW_CATEGORIES`: decisions, learnings, actions, themes
- `DECISION_SIGNALS`: "decided", "chose", "went with", "opted for", "tradeoff", "picked", "selected", "decision:"
- `LEARNING_SIGNALS`: "learned", "discovered", "figured out", "TIL", "gotcha", "insight", "realization", "aha"
- `ACTION_SIGNALS`: "- [ ]", "TODO", "follow up", "need to", "action item", "next step"
- Default review period: "this week" (Monday of current week through today)

## Step 0 — Configure Review Period

**Action:** Parse user input to determine the date range for the review.

**Date resolution rules:**
1. **"this week"** (or omitted): Monday of current week through today (inclusive)
2. **"last week"**: Monday through Sunday of previous week
3. **"last N days"**: Today minus N through today (inclusive)
4. **"this sprint"**: Last 14 days (2-week sprint default)
5. **Date range** (YYYY-MM-DD to YYYY-MM-DD): Exact range specified
6. **Single date**: That date only

**Validation:**
- Start date must not be in the future
- End date must be >= start date
- Range must not exceed 90 days (safety limit)
- If validation fails, report error and FAIL

**Category filter:**
- If user specifies a category, only scan for that category
- Default: all categories (decisions, learnings, actions, themes)

**Tool declarations:** Bash (date calculations)

**Checkpoint:** Review period resolved to concrete start/end dates, categories determined

## Step 1 — Scan Daily and Meeting Entries

**Action:** Read all daily and meeting entries within the review period.

**File discovery:**
1. Use Glob to find daily entries: `$JOURNAL_BASE/daily/*.md`
2. Filter by date range: parse `YYYY-MM-DD` from filename, include if within [start, end]
3. Use Glob to find meeting entries: `$JOURNAL_BASE/meetings/*.md`
4. Filter meetings by date: parse `YYYY-MM-DD` prefix from filename
5. Read all matching files

**If no entries found:**
- Report: "No daily or meeting entries found for {date range}. Nothing to review."
- Verdict: `PASS: no entries found for review period (searched daily/ and meetings/)`
- STOP (do not proceed to Step 2)

**Content extraction per file:**
- Store full content indexed by file path and date
- Extract section content for targeted scanning in Step 2

**Tool declarations:** Glob (find files), Read (file content), Bash (date filtering)

**Checkpoint:** All entries for review period loaded into working memory

## Step 2 — Extract Candidates

**Action:** Scan loaded entries for each active category using signal-word matching and contextual analysis.

**Resilience note:** Scan the full file content for signal words using grep-style matching across the entire entry text, not only named sections. Section-scoped matches (e.g., content found under `## Decisions Made`) are treated as higher-confidence candidates, but signal matches anywhere in the file are included. If an entry is missing expected sections (e.g., no `## Learnings` heading), log a warning but still scan the full content.

### 2a — Unlogged Decisions

**Scan strategy:**
1. Search the full entry content for decision-signal language: "decided", "chose", "went with", "opted for", "tradeoff", "picked", "selected", and variations (case-insensitive)
2. Also scan `## Decisions Made` sections in daily entries for inline decisions not linked to `decisions/` files (matches here are higher-confidence)
3. For each match, extract:
   - **Source file** and date
   - **Decision text**: the sentence or bullet containing the signal word, plus 1-2 lines of surrounding context
   - **Inferred topic**: a short descriptive name for the decision (e.g., "Use contrib/ directory for personal skills")
4. Exclude matches that are:
   - Inside wikilinks to existing decision files (e.g., `[[decisions/2026-02-23-worktree-isolation]]`)
   - Clearly referencing past decisions already recorded (e.g., "as we decided in the ADR...")

### 2b — Unlogged Learnings

**Scan strategy:**
1. Search entry content for learning-signal language: "learned", "discovered", "figured out", "TIL", "gotcha", "insight", "realization", and variations
2. Also scan `## Learnings` sections and `**Learning:**` fields in work session blocks
3. For each match, extract:
   - **Source file** and date
   - **Learning text**: the sentence or bullet containing the signal word, plus context
   - **Inferred topic**: a short descriptive name (e.g., "Git worktrees are lightweight")
4. Exclude matches that:
   - Link to existing learning files (e.g., `[[learnings/project-recovery-strategy]]`)
   - Are trivial observations (single words, vague statements)

### 2c — Untracked Action Items

**Scan strategy:**
1. Search for unchecked checkboxes: `- [ ]` (not `- [x]`)
2. Search for TODO markers: "TODO", "FIXME", "HACK" (case-insensitive)
3. Search for follow-up language: "follow up", "need to", "action item", "next step"
4. Also scan `## Tomorrow's Priorities`, `## Action Items`, `## Follow-up`, `## Next Steps` sections
5. For each match, extract:
   - **Source file** and date
   - **Action text**: the specific action item or TODO
   - **Assignee**: if present (e.g., `@person` in meeting notes)
   - **Due date**: if mentioned
6. Cross-reference: check if the same action item text appears as `- [x]` (completed) in a later daily entry within the vault. If so, mark as "completed" and exclude from candidates.

### 2d — Recurring Themes

**Scan strategy:**
1. Analyze all loaded entries for recurring topics:
   - **Project names**: Extract from YAML frontmatter `projects:` field and `**Project:**` lines
   - **Technologies/tools**: Mentioned multiple times across entries
   - **Problem patterns**: Similar blockers, challenges, or concerns appearing in multiple entries
   - **People/teams**: Recurring collaborators or stakeholders
2. A theme is "recurring" if it appears in 2+ entries within the review period
3. For each theme, extract:
   - **Theme name**: descriptive label
   - **Frequency**: number of entries mentioning it
   - **Dates**: which entries
   - **Context snippets**: representative excerpts from each mention

**Tool declarations:** Grep (signal-word search), Read (section extraction — files already loaded from Step 1)

**Checkpoint:** All candidates extracted and categorized

## Step 3 — Cross-Reference Existing Entries

**Action:** For decision and learning candidates, check whether a formal entry already exists that covers the same topic.

### Decisions cross-reference:

1. Use Glob to list all files in `$JOURNAL_BASE/decisions/`
2. Read the title (from `# ADR:` heading or YAML `title:` field) of each existing decision file
3. For each decision candidate from Step 2a, compare the candidate's inferred topic against existing decision titles and content summaries
4. **Semantic matching**: The candidate topic and existing entry title/context describe the same decision, even if worded differently. For example, candidate "chose contrib/ over skills/ for journal" matches existing ADR titled "Journal Distribution Model" if the content discusses the same choice.
5. If a confident semantic match is found, move the candidate to the **Filtered candidates** list (not silently dropped — reported in Step 4). Record the matched existing entry and the reason for filtering.
6. If uncertain whether a candidate matches an existing entry, keep the candidate but annotate it: "Possible duplicate of: {existing entry title}."
7. If no match, keep the candidate

### Learnings cross-reference:

1. Use Glob to list all files in `$JOURNAL_BASE/learnings/`
2. Read the title (from `# Learning:` heading or YAML `title:` field) of each existing learning file
3. For each learning candidate from Step 2b, compare against existing learning titles and content summaries
4. Apply the same semantic matching as for decisions
5. If a confident semantic match is found, move to Filtered candidates list with matched entry and reason
6. If uncertain, keep the candidate with a "Possible duplicate of:" annotation
7. If no match, keep the candidate

### Confidence and audit:

- Every filtered candidate is preserved in a **Filtered candidates** list with: the candidate text, the matched existing entry, and a one-line reason explaining why it was considered a match.
- This list is presented to the user in Step 4 so they can audit cross-reference decisions and override any incorrect matches.

**Tool declarations:** Glob (list existing entries), Read (entry titles/content)

**Checkpoint:** Candidates filtered — only genuinely unlogged items remain; filtered candidates preserved for user audit

## Step 4 — Present Candidates and Get Approval

**Action:** Present remaining candidates to the user, grouped by category, and collect approval/dismissal decisions.

**Pagination:** If any category contains more than 10 candidates, present the top 10 (ranked by signal confidence: section-scoped matches first, then recency) and note: "{N} additional candidates found. Say 'show more {category}' to see them."

**Presentation format:**

For each active category that has candidates, present a summary block:

```
## Unlogged Decisions (N candidates)

### 1. {Inferred Topic}
**Source:** daily/{date}.md, line ~{N}
**Signal:** "{signal phrase in context}"
**Context:** {1-3 sentences of surrounding context}
**Recommendation:** Create ADR? [approve / dismiss]

### 2. {Inferred Topic}
...

## Unlogged Learnings (N candidates)

### 1. {Inferred Topic}
**Source:** daily/{date}.md
**Signal:** "{signal phrase in context}"
**Context:** {1-3 sentences of surrounding context}
**Recommendation:** Create learning entry? [approve / dismiss]

...

## Untracked Action Items (N candidates)

### 1. {Action Text}
**Source:** daily/{date}.md
**Status:** Open (not found as completed in later entries)
**Age:** {N days since entry date}

...

## Recurring Themes (N themes)

### 1. {Theme Name}
**Frequency:** Mentioned in {N} entries
**Dates:** {date1}, {date2}, ...
**Snippets:** {representative excerpts}
**Note:** This is informational — no entry created for themes.

...

## Filtered by Cross-Reference (N items)

The following candidates were excluded because they appear to match existing entries.
If any were filtered incorrectly, say "restore {category} {number}" to promote them.

### 1. {Candidate Topic}
**Source:** daily/{date}.md
**Signal:** "{signal phrase in context}"
**Matched to:** {existing entry filename and title}
**Reason:** {one-line explanation of why it was considered a match}

...
```

**If no candidates in any category:**
- Report: "No unlogged items found for {date range}. Your journal entries are well-formalized!"
- Verdict: `PASS: no candidates found (reviewed N entries across N days)`
- STOP (do not proceed to Step 5)

**Interaction:**
1. Present candidates grouped by category (top 10 per category if more than 10 exist)
2. Present the Filtered by Cross-Reference section so the user can audit what was excluded
3. Use AskUserQuestion to ask: "Which items would you like to promote to formal entries? You can specify by number (e.g., 'Decisions: 1, 3; Learnings: 2') or say 'all', 'none', 'all decisions' / 'all learnings', 'show more {category}', or 'restore {category} {number}' to recover a filtered item."
4. Parse user response to determine which candidates are approved
5. If user says "show more {category}", present the next batch of candidates for that category
6. If user says "restore {category} {number}", move the filtered candidate back to the active list for approval
7. Recurring themes are informational only — no entries are created for them

**Tool declarations:** AskUserQuestion (user approval)

**Checkpoint:** Approval list finalized

## Step 5 — Create Approved Entries

**Action:** For each approved candidate, create a formal journal entry using the same templates and conventions as the /journal skill.

### For approved decisions:

1. **Filename:** `$JOURNAL_BASE/decisions/YYYY-MM-DD-{sanitized-topic}.md`
   - YYYY-MM-DD = date of the source daily entry where the decision was found
   - sanitized-topic: strip path separators, remove `..`, remove chars outside `[a-zA-Z0-9_-]`, lowercase, limit 100 chars
2. **Template:** Use embedded decision template (see Embedded Templates below)
3. **Fill template:**
   - `{Decision Name}` = inferred topic from Step 2a
   - `date` = source entry date
   - `## Context` = extracted context from the daily entry
   - `## Decision` = the decision text from the signal match
   - `## Rationale` = any surrounding reasoning from the daily entry, or `<!-- Fill in rationale -->`
   - `**Project:**` = project from source entry's YAML frontmatter or session block
   - Cross-link to source daily entry: `[[daily/YYYY-MM-DD]]`
4. **Verify path** starts with `$JOURNAL_BASE/` (traversal protection)
5. **Check for existing file** at target path — if exists, warn user and skip (do not overwrite)
6. **Write file**

### For approved learnings:

1. **Filename:** `$JOURNAL_BASE/learnings/{sanitized-topic}.md`
   - sanitized-topic: same sanitization as decisions
2. **Template:** Use embedded learning template (see Embedded Templates below)
3. **Fill template:**
   - `{Topic Name}` = inferred topic from Step 2b
   - `date` = source entry date
   - `## Context` / `**Why I learned this:**` = extracted context
   - `### What I Discovered` = the learning text
   - `**Project:**` = project from source entry
   - Cross-link to source daily entry: `[[daily/YYYY-MM-DD]]`
4. **Verify path**, check existing, write file

### For approved action items:

Action items are NOT created as new journal entries. Instead, they are reported as a summary list for the user to track manually. The skill does not create a tracking system.

**Output for action items:**
```markdown
## Open Action Items Summary

| # | Action | Source | Date | Age |
|---|--------|--------|------|-----|
| 1 | {action text} | daily/{date}.md | {date} | {N} days |
| 2 | ... | ... | ... | ... |

These items were found as open (unchecked) in your daily entries.
Consider adding them to your current daily entry's Tomorrow's Priorities
or closing them with `- [x]` in the source file.
```

### Post-creation:

1. Report all created files with absolute paths
2. Report dismissed candidates (for reference)
3. Report action items summary (if any)
4. Report recurring themes (informational)

**Verdict:**
- If entries were created: `PASS: created N entries (M decisions, K learnings) from review of {date range}`
- If user dismissed all: `PASS: all candidates dismissed, no entries created (reviewed N daily entries)`
- If error writing any file: `FAIL: {reason} (N of M entries written successfully)`

**Tool declarations:** Write (new files), Bash (date operations, path sanitization), Glob (check existing files)

**Checkpoint:** All approved entries created, results reported

## Embedded Templates

The following templates are used for entries created by this skill. They are identical to the /journal skill's embedded templates to ensure consistency across the journal vault. On-disk templates at `~/journal/templates/{type}.md` override these if present.

**IMPORTANT — template duplication policy:** At implementation time, templates MUST be copied character-for-character from `/journal` SKILL.md (the authoritative source). Do NOT copy from this plan document, as plan-level templates may drift from the implementation. Each embedded template in the SKILL.md must include a version tracking comment: `<!-- Template source: /journal SKILL.md v1.0.0 — re-sync if /journal templates change -->`.

### decision.md

```markdown
---
title: {Decision Name}
date: YYYY-MM-DD
status: accepted
tags: [decision]
projects: []
---

# ADR: {Decision Name}

## Status
**Status:** Accepted
**Date:** YYYY-MM-DD
**Deciders:** Ian Murphy
**Project:** [[project-name]]

## Context
<!-- What is the issue that we're seeing that is motivating this decision? -->

## Decision
<!-- What is the change that we're proposing? -->

## Rationale
<!-- Why are we making this decision? -->

### Options Considered
1. **Option A:**
   - Pros:
   - Cons:

### Why We Chose This


## Consequences
### Positive
-

### Negative
-

### Neutral
-

## Implementation
**Implemented in:** [[project-name]]
**Date implemented:** YYYY-MM-DD
**Commits:**

## Related Decisions
- [[decisions/other-decision]]

## References
-
```

### learning.md

```markdown
---
title: {Topic Name}
date: YYYY-MM-DD
tags: [learning]
category: technical | pattern | tool
confidence: beginner | intermediate | advanced
---

# Learning: {Topic Name}

## Context
**When:** [[daily/YYYY-MM-DD]]
**Project:** [[project-name]]
**Why I learned this:**

## The Learning

### What I Discovered


### How It Works


### Why It Matters


## Code Example
```
# Example code
```

## Gotchas / Pitfalls
-

## Related Concepts
- [[other-learning]]

## References
-

## Application
**Used in:** [[project-name]]
**Date applied:** YYYY-MM-DD
**Outcome:**
```

## Timestamped Artifacts

**Not applicable:** Journal review creates permanent journal entries, not workflow artifacts. The review results are communicated directly to the user during the session.

## Bounded Iterations

**Not applicable:** The approval loop is bounded by the number of candidates (finite, extracted from a finite set of entries). There is no revision loop — the user approves or dismisses each candidate once.

## Archive on Success

**Not applicable:** Journal entries are the final output, not intermediate artifacts requiring archival.
```

---

## Interfaces / Schema Changes

### New Files

| File | Purpose |
|------|---------|
| `contrib/journal-review/SKILL.md` | The skill definition (content above) |

### Modified Files

| File | Change |
|------|--------|
| `contrib/README.md` | Add journal-review to the available contrib skills list |
| `CLAUDE.md` | Add journal-review to the Contrib Skills registry table |

### No Schema Changes

- No changes to the journal vault directory structure
- No changes to existing templates
- No new template files in `~/journal/templates/` (the skill uses embedded templates identical to `/journal`)
- No changes to `deploy.sh` (it already supports `--contrib [name]` syntax)
- No changes to `validate_skill.py`

---

## Data Migration

**None required.** This skill is purely additive — it reads existing entries and creates new ones. It does not modify, move, or delete any existing files.

---

## Rollout Plan

### Phase 1: Implementation (this plan)

1. Create `contrib/journal-review/SKILL.md` with the full content specified in the Proposed Design section
2. Update `contrib/README.md` to list journal-review
3. Update `CLAUDE.md` to add journal-review to the Contrib Skills registry
4. Validate with `validate_skill.py`
5. Deploy with `./scripts/deploy.sh --contrib journal-review`

### Phase 2: Manual Testing

1. Run `/journal-review` with "this week" against actual journal vault
2. Verify each category produces reasonable candidates from known daily entries
3. Approve some candidates, dismiss others
4. Verify created entries match template format and contain correct content
5. Verify cross-referencing correctly filters out already-logged items

### Phase 3: Steady State

- Use weekly or bi-weekly as part of journal maintenance routine
- No automated scheduling — user invokes manually

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **False positives**: Signal words trigger on non-decision/learning text (e.g., "I chose to get coffee") | Medium | Low | User approval gate (Step 4) filters false positives before any entries are created. Signal words are contextually analyzed by the LLM, not just pattern-matched. |
| **False negatives**: Decisions/learnings expressed without signal words are missed | Medium | Low | Not a correctness issue — missed items can still be manually created with `/journal`. The signal word list covers common phrasing. |
| **Semantic cross-reference inaccuracy**: LLM misjudges whether a candidate matches an existing entry | Low | Medium | Filtered candidates are shown to the user in a "Filtered by Cross-Reference" section so incorrect matches can be restored. Uncertain matches are kept with a "Possible duplicate" annotation. The journal vault is small enough for accurate LLM judgment. |
| **Large review periods**: 90-day review could load many files | Low | Low | 90-day safety limit. Even at daily entries for 90 days, that is ~90 files — well within Claude's context window. |
| **Template drift**: If `/journal` skill templates change, `/journal-review` embedded templates become stale | Low | Medium | Templates MUST be copied character-for-character from `/journal` SKILL.md at implementation time. Each embedded template includes a version tracking comment (`<!-- Template source: /journal SKILL.md v1.0.0 -->`). Future work could extract shared templates, but for v1.0.0 duplication with version tracking is acceptable. |

---

## Test Plan

### Pre-deployment validation

```bash
# Validate skill definition against v2.0.0 patterns
cd ~/projects/claude-devkit
python3 generators/validate_skill.py contrib/journal-review/SKILL.md
# Expected: exit code 0 (warnings acceptable, errors not)
```

### Functional tests (manual, in Claude Code session)

**Test 1: Default review period ("this week")**
```
/journal-review
```
- Expected: Resolves to Monday of current week through today
- Expected: Scans daily entries in range, presents candidates

**Test 2: Explicit date range**
```
/journal-review 2026-02-22 to 2026-02-24
```
- Expected: Scans exactly 3 daily entries (Feb 22, 23, 24)
- Expected: Finds decision candidates (e.g., "Tool permissions go in global settings", "Runbooks get their own repo", "Journal skills go in contrib/")
- Expected: Finds learning candidates (e.g., "Claude Code permissions use prefix matching", "Runbooks buried in project plans are easy to lose")
- Expected: Finds action item candidates (e.g., unchecked `- [ ]` items in Tomorrow's Priorities)
- Expected: Finds recurring themes (e.g., "claude-devkit" appears in all 3 entries, "prodsecrm" appears in 2)

**Test 3: Cross-referencing filters existing entries**
```
/journal-review 2026-02-22 to 2026-02-22
```
- Expected: The learning about "project recovery strategy" in Feb 22's daily entry should be filtered out because `learnings/project-recovery-strategy.md` already exists
- Expected: The learning is NOT presented as a candidate

**Test 4: Category filter**
```
/journal-review last week --decisions-only
```
- Expected: Only decision candidates are presented, not learnings/actions/themes

**Test 5: No candidates found**
- Create a test scenario where all decisions and learnings from daily entries already have formal entries
- Expected: "No unlogged items found" message with PASS verdict

**Test 6: Approve and create entries**
- From Test 2 results, approve 1 decision and 1 learning
- Expected: Decision ADR created at `~/journal/decisions/YYYY-MM-DD-{topic}.md`
- Expected: Learning entry created at `~/journal/learnings/{topic}.md`
- Expected: Both files follow template format with YAML frontmatter, wikilinks, correct dates
- Expected: Verdict reports "PASS: created 2 entries (1 decision, 1 learning)"

**Test 7: Dismiss all candidates**
- Present candidates, user says "none"
- Expected: No files created
- Expected: Verdict: "PASS: all candidates dismissed, no entries created"

**Test 8: Path safety**
- Verify no created file has a path outside `~/journal/`
- Verify sanitized filenames strip special characters

**Test 9: Empty vault period**
```
/journal-review 2026-01-01 to 2026-01-07
```
- Expected: "No daily or meeting entries found for 2026-01-01 to 2026-01-07"
- Expected: PASS verdict, workflow stops at Step 1

**Test 10: Deploy and redeploy**
```bash
cd ~/projects/claude-devkit
./scripts/deploy.sh --contrib journal-review
ls ~/.claude/skills/journal-review/SKILL.md
# Expected: file exists
```

---

## Acceptance Criteria

1. `contrib/journal-review/SKILL.md` exists and passes `validate_skill.py` (exit code 0)
2. Skill is deployable via `./scripts/deploy.sh --contrib journal-review`
3. `/journal-review` is recognized as a valid skill in Claude Code after deployment
4. Scanning daily entries correctly identifies decision-signal and learning-signal language
5. Cross-referencing against `decisions/` and `learnings/` directories correctly filters already-logged items
6. User can approve or dismiss candidates via AskUserQuestion interaction
7. Approved decision entries are created with correct ADR template, YAML frontmatter, and wikilinks
8. Approved learning entries are created with correct learning template, YAML frontmatter, and wikilinks
9. Action items are reported as a summary table (not created as files)
10. Recurring themes are reported informationally (not created as files)
11. No existing files are modified by the skill
12. All created files have paths within `~/journal/` (path traversal protection)
13. Created entries are consistent with `/journal` skill template format
14. `contrib/README.md` lists journal-review
15. `CLAUDE.md` Contrib Skills registry includes journal-review

---

## Task Breakdown

### Task 1: Create SKILL.md

**File:** `~/projects/claude-devkit/contrib/journal-review/SKILL.md`
**Action:** Create new file
**Content:** The full SKILL.md content specified in the Proposed Design section above
**Effort:** Primary implementation task

### Task 2: Update contrib/README.md

**File:** `~/projects/claude-devkit/contrib/README.md`
**Action:** Edit existing file
**Change:** Add journal-review entry to the available skills list with description, prerequisites, and usage example:
```markdown
### journal-review

**Purpose:** Periodic journal review — scans daily entries to surface unlogged decisions, learnings, action items, and recurring themes for promotion to formal entries.

**Prerequisites:** Same as journal and journal-recall — `~/journal/` vault with Obsidian structure.

**Usage:**
```
/journal-review              # Review this week
/journal-review last week    # Review last week
/journal-review last 14 days # Review last 2 weeks
```

**Deployment:**
```bash
./scripts/deploy.sh --contrib journal-review
```
```

### Task 3: Update CLAUDE.md Registry

**File:** `~/projects/claude-devkit/CLAUDE.md`
**Action:** Edit existing file
**Change:** Add row to the Contrib Skills registry table:

```markdown
| **journal-review** | 1.0.0 | Periodic review of daily entries — surfaces unlogged decisions, learnings, untracked action items, and recurring themes for promotion to formal entries. Pipeline archetype with interactive approval. | Same `~/journal/` vault as journal skill | 6 |
```

### Task 4: Validate

**Command:**
```bash
cd ~/projects/claude-devkit
python3 generators/validate_skill.py contrib/journal-review/SKILL.md
```
**Expected:** Exit code 0

### Task 5: Deploy and Smoke Test

**Commands:**
```bash
cd ~/projects/claude-devkit
./scripts/deploy.sh --contrib journal-review
ls ~/.claude/skills/journal-review/SKILL.md
```
**Then in Claude Code session:**
```
/journal-review 2026-02-22 to 2026-02-24
```
**Expected:** Candidates presented from the 3 existing daily entries

### Task 6: Commit

**Commands:**
```bash
cd ~/projects/claude-devkit
git add contrib/journal-review/SKILL.md contrib/README.md CLAUDE.md
git commit -m "feat(contrib): add journal-review skill for periodic journal auditing"
```

---

<!-- Context Metadata
discovered_at: 2026-02-24T14:00:00Z
claude_md_exists: true
recent_plans_consulted: journal-skill-blueprint.md
archived_plans_consulted: none
-->
