---
name: journal-recall
version: 1.0.0
model: claude-opus-4-6
description: Search, retrieve, and summarize past journal entries. Use when the user says "what did I", "recall", "look up", "find in journal", "journal search", "last week", "weekly review", "what happened on", "summarize my week", "what have I been working on", "review my journal", or asks about past work, decisions, meetings, or notes.
---

# /journal-recall Workflow

## Inputs

**User provides:**
- Natural language query describing what to find (date, keyword, topic, project, etc.)
- Optional: date range, entry type filter, project name

**Scope parameters:**
- `JOURNAL_BASE`: `~/journal/` (hardcoded, matches /journal skill)
- Entry types: daily, meetings, projects, learnings, decisions
- Search modes: date lookup, date range, keyword search, topic search, project filter, weekly review

## Step 0 — Classify Intent

**Action:** Determine what type of retrieval the user wants.

**Intent classification:**
1. **Specific date lookup**: User mentions a date ("yesterday", "Feb 23", "2026-02-22", "last Tuesday")
2. **Date range**: User mentions a span ("this week", "last month", "between X and Y")
3. **Keyword search**: User provides search terms ("worktree isolation", "Docker socket")
4. **Topic/project**: User asks about a specific topic or project ("what did I do on claude-devkit?")
5. **Meeting lookup**: User asks about meetings ("what meetings did I have?", "standup notes")
6. **Weekly review**: User asks for a summary ("summarize this week", "weekly review", "what happened this week")
7. **Project status**: User asks about a project's current state ("what's the status of X?", "where am I on X?")

**Disambiguation:**
- If intent unclear, default to keyword search across all entries
- For time-based queries, resolve relative dates ("yesterday" = YYYY-MM-DD, "this week" = past 7 days)

**Tool declarations:** Bash (date calculations for relative dates)

**Output:** Search intent classification and search parameters

## Step 1 — Retrieve Entries

**Action:** Use appropriate tools to find and read matching journal entries.

**Retrieval strategies by intent:**

**Specific date lookup:**
- Read `daily/YYYY-MM-DD.md` directly
- If date is in past and daily entry doesn't exist, report "No daily entry for YYYY-MM-DD"
- Also check for meetings/decisions on that date using Glob: `meetings/YYYY-MM-DD-*.md`, `decisions/YYYY-MM-DD-*.md`

**Date range:**
- Use Glob to find all daily entries in range: `daily/*.md`
- Filter by date range (parse YYYY-MM-DD from filename)
- Use Glob for meetings/decisions in range
- Read all matching files

**Keyword search:**
- Use Grep with content output mode to search across all journal directories
- Pattern: user's search terms (case-insensitive)
- Glob pattern: `*.md` (search all markdown files)
- Context: 3 lines before/after match for readability
- Return: file paths and matching excerpts

**Topic/project search:**
- Use Grep to find mentions of topic/project name
- Search in YAML frontmatter (`projects: [name]`) and wikilinks (`[[projects/name]]`)
- Also directly read `projects/{name}.md` if it exists

**Meeting lookup:**
- Use Glob to find all meetings: `meetings/*.md`
- Optionally filter by date range or keyword
- Read matching files

**Weekly review:**
- Calculate date range for "this week" or "last week" (Mon-Sun or last 7 days)
- Use Glob to find all daily entries in range
- Read all daily files
- Summarize: projects worked on, key wins, decisions made, learnings captured

**Project status:**
- Read `projects/{name}.md` directly
- Extract: current status (YAML frontmatter), recent activity (Work Log section), open questions
- Also search daily entries for recent mentions

**Tool declarations:** Read (specific files), Glob (find files by pattern), Grep (keyword search), Bash (date calculations)

**Checkpoint:** Retrieved all matching entries

## Step 2 — Present Results

**Action:** Format and present the retrieved information based on intent.

**Presentation formats:**

**Specific date lookup:**
- Show full daily entry for that date
- List any meetings or decisions from that date
- Format: markdown with clear sections

**Date range:**
- Show abbreviated daily entries (date + Morning Intention + key wins)
- List meetings and decisions in chronological order
- Format: bulleted timeline

**Keyword search:**
- Show file path, date (extracted from filename), and matching excerpt for each result
- Highlight search term context (3 lines before/after)
- Format: search result blocks with file references
- Example:
  ```
  Found in: daily/2026-02-23.md
  Date: 2026-02-23
  Context:
  ...
  - **Project work:** Refactored authentication module — extracted shared validation logic into middleware, added rate limiting, updated all 8 endpoint handlers to use the new pattern.
  ...
  ```

**Topic/project search:**
- Show project overview (from `projects/{name}.md`)
- List recent daily entries mentioning the project (past 30 days)
- List related learnings and decisions
- Format: structured summary with links

**Meeting lookup:**
- List all meetings in chronological order
- For each meeting: date, title, attendees, key decisions, action items
- Format: bulleted list with meeting metadata

**Weekly review:**
- Summary sections:
  - **Date range:** (Mon-Sun or last 7 days)
  - **Projects worked on:** (unique list from all daily entries)
  - **Key wins:** (aggregated from daily Wins sections)
  - **Decisions made:** (list all decisions from the week)
  - **Learnings:** (list all learnings from the week)
  - **Carry-overs:** (open items from last daily entry)
- Format: structured markdown summary

**Project status:**
- **Overview:** (from project file)
- **Current status:** (YAML frontmatter `status` field)
- **Recent activity:** (last 3 entries from Work Log)
- **Open questions:** (from project file)
- **Recent daily mentions:** (grep daily/ for project name, last 7 days)
- Format: structured report

**Tool declarations:** None (output formatting only)

**Checkpoint:** Results formatted and ready to present

## Step 3 — Handle Missing Data

**Action:** Report clearly if no entries found, suggest alternatives.

**No results handling:**
- If specific date has no entry: "No daily entry found for YYYY-MM-DD. Nearest entries: [list files within ±3 days]"
- If keyword search returns no results: "No matches found for '{keyword}' in journal. Try broader terms or check spelling."
- If project doesn't exist: "No project file found for '{name}'. Available projects: [list all projects/*.md]"
- If date range is empty: "No entries found for {date range}. First entry: YYYY-MM-DD, last entry: YYYY-MM-DD"

**Always include verdict:**
- Success (results found): `PASS: found N entries matching '{query}'`
- Success (no results): `PASS: no entries found for '{query}' (searched N files)`
- Never use FAIL for legitimate "no results" scenarios (that's a successful search with zero matches)

**Tool declarations:** Glob (to find nearest entries or list available projects)

**Checkpoint:** Missing data handled, verdict reported

## Timestamped Artifacts

**Not applicable:** Journal recall is a read-only search operation, not a workflow that produces artifacts.

## Bounded Iterations

**Not applicable:** Journal search is a single-pass retrieval operation.

## Archive on Success

**Not applicable:** Journal recall produces output directly to the user, not intermediate artifacts requiring archival.
