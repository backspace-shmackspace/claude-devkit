---
name: journal
version: 1.0.0
model: claude-opus-4-6
description: Write entries to the Obsidian work journal. Creates daily logs, meeting notes, project updates, learnings, and decision records. Use when the user says "journal", "log", "daily entry", "meeting notes", "learning", "decision", "ADR", "capture this", "write down", "record this", or wants to document work for future reference.
---

# /journal Workflow

## Inputs

**User provides:**
- Natural language description of what to journal (content, context, topic)
- Optional: explicit entry type (daily, meeting, project, learning, decision)
- Optional: project name, topic name, or meeting title

**Scope parameters:**
- `JOURNAL_BASE`: `~/journal/` (hardcoded, user can modify in skill file if needed)
- `TEMPLATES_DIR`: `~/journal/templates/` (on-disk templates override embedded defaults)
- Supported entry types: daily, meeting, project, learning, decision, biweekly-update

## Step 0 — Determine Entry Type

**Action:** Classify user input to determine which journal entry type to create.

**Classification rules:**
1. **daily**: User mentions "daily", "today", "log", "work session", or provides general work update without specific meeting/learning/decision context
2. **meeting**: User mentions "meeting", "standup", "sync", "call", or references attendees/agenda
3. **project**: User mentions "project update", references a specific project name, or provides progress on a named initiative
4. **learning**: User mentions "learned", "discovered", "figured out", "TIL", "gotcha", or describes technical insight
5. **decision**: User mentions "decision", "ADR", "decided to", "chose", "picked", describes options/tradeoffs
6. **biweekly-update**: User mentions "biweekly", "bi-weekly", "leadership update", "14-day update", "fortnightly", or "status update for leadership"

**Disambiguation heuristic:**
- If input matches multiple types, default to broader type: daily > project, meeting > decision
- A decision made in a meeting goes in the meeting entry unless user explicitly wants separate ADR
- If still ambiguous after heuristic, ask user to clarify

**Deprecated types:**
- If user says "idea" or "todo", explain these are now captured in daily notes (`## Learnings` for ideas, `## Tomorrow's Priorities` for todos) and offer to add content there
- Do not silently fail or ignore deprecated types

**Tool declarations:** Read (to check existing files), Bash (for date operations)

**Output:** Entry type classification (daily/meeting/project/learning/decision) and extracted topic/title

## Step 1 — Validate Path and Load Template

**Action:** Sanitize user-supplied names, validate paths, and load the appropriate template.

**Path sanitization:**
1. Extract topic/title/name from user input
2. Sanitize filename:
   - Strip all path separators (`/`, `\`)
   - Remove `..` sequences
   - Remove characters outside `[a-zA-Z0-9_-]` (replace with `-`)
   - Convert to lowercase for consistency
   - Limit to 100 characters
3. Construct absolute file path based on entry type:
   - **daily**: `$JOURNAL_BASE/daily/YYYY-MM-DD.md` (date-based, no user input in path)
   - **meeting**: `$JOURNAL_BASE/meetings/YYYY-MM-DD-{sanitized-topic}.md`
   - **project**: `$JOURNAL_BASE/projects/{sanitized-name}.md`
   - **learning**: `$JOURNAL_BASE/learnings/{sanitized-topic}.md`
   - **decision**: `$JOURNAL_BASE/decisions/YYYY-MM-DD-{sanitized-name}.md`
   - **biweekly-update**: `$JOURNAL_BASE/deliverables/YYYY-MM-DD-biweekly-update.md`
4. Verify resolved absolute path starts with `$JOURNAL_BASE/` (prevent traversal attacks)

**Template loading:**
1. Check if on-disk template exists at `$TEMPLATES_DIR/{type}.md`
2. If exists, read it (on-disk override)
3. If not, use embedded default template (see Embedded Templates section below)
4. If neither available, report error listing expected template path and FAIL

**Tool declarations:** Read (template files), Bash (date operations)

**Checkpoint:** Path validated, template loaded, ready to proceed

## Step 2 — Check Existing File

**Action:** For daily and project entries, check if the file already exists to determine append vs create.

**Daily entry append logic:**
- If `daily/YYYY-MM-DD.md` exists, new content will append as `### Session N` under `## Work Sessions`
- Determine N by reading existing file and incrementing highest session number
- YAML frontmatter is NOT modified on append

**Project entry append logic:**
- If `projects/{name}.md` exists, new content will append as `### YYYY-MM-DD` under `## Recent Activity` (or `## Work Log` if that section exists instead)
- YAML frontmatter is NOT modified on append

**Biweekly update entries:**
- Always new files (date-stamped: `YYYY-MM-DD-biweekly-update.md`)
- If file already exists for today's date, warn user and ask if they want to overwrite
- Period defaults to 14 days back from today unless user specifies

**Biweekly update drafting process:**
When creating a biweekly-update entry, automatically gather context to draft content:
1. **Mine journal data**: Read daily entries from the last 14 days (`daily/*.md`) to extract wins, blockers, decisions, and project progress
2. **Mine project entries**: Read `projects/*.md` for recent activity sections
3. **Mine decision records**: Read `decisions/*.md` from the last 14 days for strategic context
4. **Draft all 6 sections** with concrete content from the mined data, leaving `<!-- VERIFY -->` comments on any claims the user should double-check

**Audience context:** Leadership team. They want signal, not noise: specific metrics, clear blockers with named owners, and forward-looking risks.

**Meeting, learning, decision entries:**
- These are always new files (timestamped or uniquely named)
- If file already exists, warn user and ask if they want to overwrite or append

**Tool declarations:** Read (existing file), Glob (to find max session number)

**Checkpoint:** Determined whether this is a create or append operation

## Step 3 — Write Entry

**Action:** Create or update the journal file using the template format.

**For new files:**
1. Fill YAML frontmatter with current date, extracted metadata, and user content
2. Replace template placeholders:
   - `YYYY-MM-DD` → current date
   - `{Project Name}`, `{Topic Name}`, etc. → sanitized user input
   - `HH:MM` → current time
3. Insert user-provided content in appropriate sections
4. Leave unprovided template sections as placeholders (user fills later)

**For daily entry appends:**
1. Read existing file content
2. Find `## Work Sessions` section
3. Determine next session number (e.g., if Session 3 exists, next is Session 4)
4. Append new session block:
   ```markdown
   ### Session N (HH:MM - HH:MM)
   **Project:** [[project-name]]
   **Task:** {user content}
   **Progress:** {user content}
   **Blockers:** {from user or TBD}
   **Learning:** {from user or TBD}
   ```
5. Write updated file

**For project entry appends:**
1. Read existing file content
2. Find `## Recent Activity` or `## Work Log` section
3. Append new dated entry:
   ```markdown
   ### YYYY-MM-DD
   {user content}
   [[daily/YYYY-MM-DD]]
   ```
4. Write updated file

**Tool declarations:** Write (new files), Edit (append operations), Bash (date/time)

**Checkpoint:** File written successfully

## Step 4 — Cross-Link

**Action:** Add wikilinks from the current entry to related entries (one-directional linking).

**Cross-linking rules:**
- **Daily entries**: Link to mentioned projects (`[[projects/name]]`) and previous day (`[[daily/YYYY-MM-DD]]`, determined by globbing `daily/*.md` for most recent prior date)
- **Meeting entries**: Link to today's daily entry (`[[daily/YYYY-MM-DD]]`) and mentioned projects
- **Learning entries**: Link to today's daily entry and mentioned projects
- **Decision entries**: Link to today's daily entry and mentioned projects
- **Project entries**: Link to today's daily entry (`[[daily/YYYY-MM-DD]]`)
- **Biweekly update entries**: Link to today's daily entry, mentioned projects, and previous biweekly update (Glob `deliverables/*-biweekly-update.md`, most recent before today)


**Implementation:**
- Cross-links are inserted in the appropriate section (e.g., `**Links:**` for daily, `## Related Projects` for project)
- Only modify current entry; do NOT modify linked-to files (one-directional)
- Use Glob to find previous daily entry: `daily/*.md`, sort by filename descending, take first that's before today

**Tool declarations:** Glob (find previous daily), Edit (insert links)

**Checkpoint:** Cross-links added

## Step 5 — Confirm and Report

**Action:** Report what was written and where, with verdict keyword.

**Success output:**
- Path to created/updated file
- Entry type and operation (created/appended)
- Brief summary of content
- Verdict: `PASS: entry written to {absolute-path}`

**Failure output:**
- Error message with specific reason
- Expected vs actual state
- Verdict: `FAIL: {reason}`

**Tool declarations:** None (output only)

## Embedded Templates

The following templates are embedded as defaults. On-disk templates at `~/journal/templates/{type}.md` override these if present.

### daily.md

```markdown
---
date: YYYY-MM-DD
day_of_week: Monday
tags: [daily, work]
projects: []
mood: 😐
energy: medium
focus_time: 0h
---

# Daily Log - YYYY-MM-DD

## Morning Intention
<!-- What are you trying to accomplish today? -->

## Work Sessions

### Session 1 (09:00 - 11:00)
**Project:** [[project-name]]
**Task:**
**Progress:**
**Blockers:**
**Learning:**

### Session 2 (11:00 - 13:00)
**Project:**
**Task:**
**Progress:**
**Blockers:**
**Learning:**

## Decisions Made
<!-- Link to decision records if significant -->

## Learnings
<!-- Quick notes, expand in learnings/ if deep -->

## Tomorrow's Priorities
1.
2.
3.

## Gratitude / Wins
<!-- What went well? What are you grateful for? -->

---

**Links:**
- Previous: [[YYYY-MM-DD]]
- Next: [[YYYY-MM-DD]]
- Related:
```

### meeting.md

```markdown
---
title: Meeting Topic
date: YYYY-MM-DD
time: HH:MM
attendees: []
tags: [meeting]
---

# Meeting: {Topic}

**Date:** YYYY-MM-DD HH:MM
**Attendees:** Person 1, Person 2
**Duration:** XXm

## Agenda
1.
2.

## Notes

### Topic 1


## Action Items
- [ ] @person: Task 1 (Due: YYYY-MM-DD)

## Decisions Made
- [[decisions/YYYY-MM-DD-decision-name]]

## Follow-up
- Next meeting: YYYY-MM-DD
- Related: [[project-name]]
```

### project.md

```markdown
---
title: Project Name
repo: github.com/your-org/project-name
status: active
started: YYYY-MM-DD
tags: [project, python]
tech_stack: []
---

# Project: {Project Name}

## Overview
**Purpose:**
**Status:** Active | Paused | Complete
**Repo:** `~/projects/{project-name}`

## Current Focus
<!-- What are you working on right now? -->

## Architecture
<!-- High-level architecture diagram or description -->

## Key Decisions
- [[decisions/YYYY-MM-DD-decision-name]]

## Learnings
- [[learnings/topic-name]]

## Work Log
### YYYY-MM-DD
- Work summary
- [[daily/YYYY-MM-DD]]

## Open Questions
- [ ] Question 1?

## Future Ideas
- Idea 1

## Related Projects
- [[project-name]]
```

### learning.md

```markdown
---
title: Topic Name
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
```python
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

### decision.md

```markdown
---
title: Decision Name
date: YYYY-MM-DD
status: accepted | rejected | superseded | deprecated
tags: [decision, architecture]
projects: []
---

# ADR: {Decision Name}

## Status
**Status:** Accepted
**Date:** YYYY-MM-DD
**Deciders:** {Your Name}
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

### biweekly-update.md

```markdown
---
title: Bi-Weekly Leadership Update
date: YYYY-MM-DD
period_start: YYYY-MM-DD
period_end: YYYY-MM-DD
tags: [deliverable, biweekly, leadership]
projects: []
audience: Leadership Team
---

# Bi-Weekly Update - YYYY-MM-DD

**Period:** YYYY-MM-DD to YYYY-MM-DD
**Author:** {Your Name}

## 1. Key Wins

**Impactful Wins over the last 14 days:**
<!-- Evidence-first: specific metrics, deliverables shipped, risks resolved. No vague "good progress." -->
-

**Recognition:**
<!-- Name 1-2 individuals and briefly explain their contribution. -->
-

## 2. Priority Shifts & Strategic Context

**Primary Goal Alignment:** <!-- Yes/No. If no, what is the new target? -->

**Change:** <!-- Summarize the decision or pivot -->

**Reasoning:** <!-- Why did the direction evolve? e.g., market shift, resource constraint. -->

**Impact:** <!-- Who/what does this affect? What are we deprioritizing? -->

## 3. Roadblocks & Risks

<!-- Use [BLOCKER] for stop-work issues, [RISK] for awareness items -->
<!-- Be direct and specific. Name the person or team you need help from. -->

- **[BLOCKER]:** <!-- Stop-work issue. I need immediate help from: Name -->
- **[RISK]:** <!-- Potential delay. Watching: Factor. (Awareness only) -->

## 4. Leadership Support & Influence

**Decision Support:** <!-- e.g., "I am leaning toward A despite B; do you see a different trade-off?" -->

**Barrier Removal:** <!-- e.g., "Need alignment with Team X; need perspective on their constraints." -->

**The Early Warning:** <!-- What decision is coming up that we need to anticipate now? -->

## 5. External Pulse (Market, Customers & Partners)

**Market Intel:** <!-- Major wins, escalations, or "scary" developments. -->

**Observations:** <!-- Shifts in customer needs, resource availability, or pivots required. -->

## 6. The 14-Day Outlook

**Single Most Important Objective:** <!-- What is the #1 thing that MUST go right in the next 2 weeks? -->

**Next Milestone:** <!-- Specific deliverable due by the next report. -->

---

**Links:**
- Previous: [[deliverables/YYYY-MM-DD-biweekly-update]]
- Related:
```

## Timestamped Artifacts

**Not applicable:** Journal entries are permanent records, not workflow artifacts.

## Bounded Iterations

**Not applicable:** Journal entry creation is a single-pass operation.

## Archive on Success

**Not applicable:** Journal entries are the final output, not intermediate artifacts requiring archival.
