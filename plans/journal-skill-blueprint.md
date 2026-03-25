# Technical Implementation Plan: Journal Skill System & Distribution Architecture

**Author:** Claude Opus 4.6 (blueprint analysis)
**Date:** 2026-02-24
**Status:** APPROVED
**Version:** 1.1.0
**Scope:** Journal skills (`/journal`, `/journal-recall`) and claude-devkit distribution model

---

## Goals

1. Fix critical path mismatch bug (`~/projects/work-journal/` vs `~/journal/`) in both journal skills.
2. Migrate existing entries from `~/projects/work-journal/` to `~/journal/`, reconciling format differences.
3. Rewrite journal skill templates to match the Obsidian vault structure (YAML frontmatter, wikilinks, 5 entry types).
4. Add missing entry types (`learning`, `decision`) that have Obsidian templates but no skill coverage.
5. Consolidate skill structure: determine whether to keep 2 skills, split into 3+, or restructure.
6. Establish a distribution model that separates personal/opinionated skills from universal devkit skills.
7. Modify `deploy.sh` to support selective skill deployment for external distribution.

## Non-Goals

- Building a full Obsidian plugin or sync system.
- Implementing interactive risk analysis sessions (Phase 2 of JOURNAL_SYSTEM_SPEC.md).
- Creating a code snippet library, reading notes, or idea backlog (Phase 2 features).
- Rewriting the devkit core skills (dream, ship, audit, sync).
- Building a skill marketplace or registry (devkit v1.2 roadmap item).

## Assumptions

1. The journal vault at `~/journal/` is the canonical location and will not move.
2. The 5 Obsidian templates at `~/journal/templates/` are the authoritative format for all entry types.
3. The journal project uses git with auto-commit via Obsidian Git plugin (commit message format: `Journal update: YYYY-MM-DD HH:MM`).
4. Other developers who receive claude-devkit will NOT have `~/journal/` with Obsidian templates.
5. The existing `/journal-recall` skill's query/search/review functionality is correct in design, only the path and template awareness need fixing.
6. `validate_skill.py` at `~/projects/claude-devkit/generators/validate_skill.py` is functional and enforces v2.0.0 patterns, including required `model` field, `# /skill-name Workflow` header, `## Inputs` section, and verdict keywords.
7. The pipeline archetype (not coordinator) is correct for journal skills, as confirmed by the portfolio review plan.
8. `~/projects/work-journal/` contains real entries (3 daily files, ideas.md, todos.md, project-fugue.md) that must be migrated or reconciled before the old path is abandoned.
9. The claude-devkit repository is located at `~/projects/claude-devkit/` (not `~/workspaces/claude-devkit/`, which does not exist; CLAUDE.md references to the latter path are stale and must be corrected).

---

## Context Alignment

### Which CLAUDE.md patterns this plan follows

- **claude-devkit/CLAUDE.md v1.0.0**: Pipeline archetype pattern. Journal operations are sequential file I/O (read template, check existing file, write/append entry, cross-link). No agent delegation required. This matches the pipeline archetype's "sequential execution with checkpoints" model.
- **claude-devkit/CLAUDE.md v1.0.0**: Numbered steps (`## Step N -- [Action]`), tool declarations, scope parameters, bounded iterations. The rewritten skills will include all 10+1 architectural patterns, using stub sections with justification for patterns that are not applicable to direct file-I/O (see Deviation 1 below).
- **claude-devkit/CLAUDE.md v1.0.0**: Source of truth is `skills/*/SKILL.md` (or `contrib/*/SKILL.md` for optional skills) in the devkit repo, deployed via `deploy.sh` to `~/.claude/skills/`.
- **JOURNAL_SYSTEM_SPEC.md v1.0**: Template structures, directory layout, Claude Code integration patterns (daily log, capture learning, record decision, query journal, weekly review).

### Which prior plans this relates to or builds upon

- **`~/plans/portfolio-review-next-steps.md`** (APPROVED, 2026-02-23): This plan implements Move 5 ("Formalize the Journal System as Skills"), which was explicitly deferred to a separate plan. The portfolio review recommended:
  - Pipeline archetype (adopted)
  - Consider splitting into 2-3 simpler skills (adopted: 2-skill split)
  - Implement only `log` and `decide` in v1, defer `query` and `review` to v2 (modified: keep journal-recall as the query/review skill)
  - Validate using `validate_skill.py` (adopted)

### Any deviations from established patterns, with justification

1. **Simplified pipeline with stub sections**: Journal skills will use the full numbered-step pipeline structure but include stub sections for patterns that are not applicable to direct file-I/O operations. Specifically, verdict gates (Pattern 4) will use a minimal "PASS: entry written" / "FAIL: write error" output rather than full PASS/FAIL/BLOCKED gating. Timestamped artifacts (Pattern 5), bounded iterations (Pattern 7), and archive-on-success (Pattern 10) will appear as stub sections with the note "Not applicable: journal entries are permanent records, not workflow artifacts." This satisfies `validate_skill.py` while keeping the skill focused. Justification: the pipeline archetype documentation says "sequential execution with checkpoints," but for journal entries, the only meaningful checkpoint is "did the file write succeed."

2. **Model field set to session default**: Journal skills do not delegate to subagents via Task tool, so no model selection is meaningful. However, `validate_skill.py` requires the `model` field in frontmatter. The field will be set to `claude-opus-4-6` (the session model). This satisfies the validator without implying delegation.

3. **No timestamped artifacts or archive-on-success (stub only)**: Journal entries are the output, not intermediate artifacts. There is nothing to archive to `./plans/archive/`. Stub sections explain this.

4. **Personal skills in `contrib/` instead of `skills/`**: Journal skills will live in the devkit repo under `contrib/journal/` and `contrib/journal-recall/` rather than `skills/`. This deviates from the portfolio review's assumed location of `skills/journal/SKILL.md` (portfolio-review-next-steps.md, Phase 5 task breakdown). Justification: `skills/` contains universal skills deployed to all users; `contrib/` contains optional/personal skills that require user-specific configuration (e.g., `~/journal/` vault). External developers without an Obsidian journal vault would get a broken skill if it were in `skills/`. The `contrib/` convention isolates personal skills without polluting the core distribution. This requires updating CLAUDE.md's architecture sections (see Phase 4).

5. **Repository path correction**: CLAUDE.md references `~/workspaces/claude-devkit` in Quick Start, installation, and deployment examples. The actual path is `~/projects/claude-devkit/`. This plan uses the correct path throughout and includes a task to correct CLAUDE.md.

---

## Proposed Design

### Part 1: Skill Architecture (2 Skills, Not 3+)

**Decision: Keep 2 skills, rewrite both.**

| Skill | Purpose | Entry Types | Archetype |
|-------|---------|-------------|-----------|
| `/journal` | Create and update journal entries | daily, meeting, project, learning, decision | Pipeline (simplified) |
| `/journal-recall` | Search, retrieve, and summarize past entries | query, review, weekly summary | Pipeline (simplified) |

**Rationale for 2 skills instead of 3-5:**

The portfolio review suggested splitting into `/journal-log`, `/journal-decide`, `/journal-review`. However:

1. The existing 2-skill split (`/journal` for writes, `/journal-recall` for reads) is a clean separation of concerns.
2. Splitting write operations into 3 skills (`/journal-log`, `/journal-learn`, `/journal-decide`) adds invocation overhead -- users must remember which command to use for which entry type. The current `/journal` skill auto-detects entry type from natural language, which is the correct UX.
3. The portfolio review's concern about "one skill with 5 sub-commands" is addressed by the skill's entry-type detection step, not by splitting commands. Each entry type is a template application, not a separate workflow.

**What changes from the current skills:**

| Aspect | Current | Proposed |
|--------|---------|----------|
| Base path | `~/projects/work-journal/` | `~/journal/` |
| Entry types | daily, meeting, project, idea, todo | daily, meeting, project, learning, decision |
| Templates | Simple markdown (no frontmatter) | Obsidian templates (YAML frontmatter, wikilinks), embedded in SKILL.md with on-disk override |
| ideas/todos | Separate accumulating files | Removed (not in JOURNAL_SYSTEM_SPEC.md; use project notes or daily notes instead) |
| learning | Not supported | Full template with context, examples, gotchas |
| decision | Not supported | Full ADR template with options, consequences |
| Cross-linking | None | Wikilinks (`[[daily/YYYY-MM-DD]]`, `[[project-name]]`) |
| Path validation | None | Sanitize user-supplied names; reject `..` segments and non-alphanumeric-hyphen-underscore characters |

**Removed entry types -- justification:**

- **idea**: The JOURNAL_SYSTEM_SPEC.md lists ideas as a Phase 2 feature ("Idea Backlog"). The current skill's `ideas.md` accumulating file is a simpler pattern than the spec envisions. Defer to Phase 2.
- **todo**: Todos are captured within daily notes (`## Tomorrow's Priorities`) and project notes (`## Open Questions`). A separate todo file conflicts with the Obsidian task management approach (Tasks plugin + Dataview queries across all notes).

**Deprecated entry type handling**: If the user says "idea" or "todo", the skill must not fail silently. Instead, it must explain that these are now captured within daily notes (ideas under `## Learnings`, todos under `## Tomorrow's Priorities`) and offer to add the content there.

### Part 2: Rewritten `/journal` Skill

The rewritten `/journal` skill will:

1. **Step 0 -- Determine entry type**: Parse user input to classify as daily, meeting, project, learning, or decision. **Disambiguation rule**: if the user's input could match multiple entry types, default to the broader type (daily > project, meeting > decision) and incorporate the specific content. A decision made in a meeting goes in the meeting entry, with a cross-link to a standalone decision record only if the user explicitly wants a separate ADR. Ask if still ambiguous after applying this heuristic.
2. **Step 1 -- Validate path and load template**: Sanitize the user-supplied topic/title name: strip any path separators (`/`, `\`), `..` sequences, and characters outside `[a-zA-Z0-9_-]`. Verify the resolved absolute path starts with `~/journal/`. If `~/journal/templates/{type}.md` exists on disk, read it (on-disk override). Otherwise, use the embedded default template from within the SKILL.md file. If neither is available, report an error listing the expected template path and abort.
3. **Step 2 -- Check existing file**: For daily and project entries, check if the file already exists (append vs create logic -- see Append Semantics below).
4. **Step 3 -- Write entry**: Create or update the file using the template format with YAML frontmatter and wikilinks. Fill in user-provided content, leave template placeholders for unprovided fields.
5. **Step 4 -- Cross-link**: Add wikilinks to the current entry pointing to related entries. Cross-linking is one-directional (current entry links out; the linked-to file is not modified). Specifically: daily entries link to mentioned projects (`[[projects/name]]`) and to previous day (`[[daily/YYYY-MM-DD]]`, determined by globbing `daily/*.md` for the most recent prior file). Meeting entries link to the day's daily entry. Learning and decision entries link to the day's daily entry and any mentioned project. Project entries link to the day's daily entry.
6. **Step 5 -- Confirm**: Report what was written and where. Include the verdict keyword: "PASS: entry written to {path}" on success, or "FAIL: {reason}" on error.

**Append Semantics (daily entries):**

When a daily entry file already exists:
- New content is appended as a new `### Session N` block under the `## Work Sessions` section, where N is incremented from the highest existing session number.
- YAML frontmatter is NOT modified on append (frontmatter reflects the day's initial state; updates to `focus_time`, `projects`, etc. are manual or deferred to a future automation).
- The `## Tomorrow's Priorities` section is NOT moved or duplicated; it remains at its current position and can be manually updated.

**Append Semantics (project entries):**

When a project entry file already exists:
- New content is appended as a new dated entry under the `## Recent Activity` section, formatted as `### YYYY-MM-DD` followed by the update content.
- YAML frontmatter is NOT modified on append.

### Part 3: Rewritten `/journal-recall` Skill

The rewritten `/journal-recall` skill will:

1. **Step 0 -- Classify intent**: Determine if the user wants: specific date lookup, date range, keyword search, topic/project, meeting lookup, weekly review, or project status.
2. **Step 1 -- Retrieve entries**: Use Glob/Grep/Read to find and read matching entries from `~/journal/`.
3. **Step 2 -- Present results**: Format output based on intent (full entry, search excerpts, weekly summary).
4. **Step 3 -- Handle missing data**: Report clearly if no entries found, suggest alternatives. Include verdict keyword: "PASS: found N entries" or "PASS: no entries found for criteria X".

### Part 4: Distribution Architecture

**Decision: Introduce `contrib/` directory in claude-devkit for optional/personal skills.**

```
claude-devkit/
  skills/              # Core skills (deployed to all users)
    dream/SKILL.md
    ship/SKILL.md
    audit/SKILL.md
    sync/SKILL.md
    test-idempotent/SKILL.md
  contrib/             # Optional skills (user opts-in)
    journal/SKILL.md
    journal-recall/SKILL.md
    README.md          # Documents available contrib skills and how to deploy
```

**deploy.sh changes:**

```bash
# Current behavior (unchanged):
./scripts/deploy.sh              # Deploy all CORE skills from skills/
./scripts/deploy.sh dream        # Deploy one core skill

# New behavior:
./scripts/deploy.sh --contrib journal        # Deploy one contrib skill
./scripts/deploy.sh --contrib                # Deploy ALL contrib skills
./scripts/deploy.sh --all                    # Deploy core + all contrib skills
./scripts/deploy.sh --help                   # Show usage
```

**Argument parsing specification** (replaces ambiguous pseudocode):

The argument parser must use a `case` statement on `${1:-}` with the following rules:
- Flags (`--contrib`, `--all`, `--help`) are identified by the `--` prefix.
- Any argument starting with `-` that is not a recognized flag produces an error: `"ERROR: Unknown flag: $1"` and exits with code 1.
- `--contrib` takes an optional second positional argument (the skill name). If `$2` exists and does not start with `-`, it is treated as the skill name. If `$2` starts with `-`, emit an error: `"ERROR: Invalid skill name: $2"`.
- `--contrib` with no second argument deploys all contrib skills.
- Bare arguments (no `--` prefix) are treated as core skill names (existing behavior).

**Rationale for `contrib/` over alternatives:**

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Bundle in `skills/` | Simple, single deploy | All users get personal/opinionated skills. Other devs won't have `~/journal/`. | Rejected |
| Separate repo | Clean separation | Extra repo to maintain. Breaks single-source-of-truth. Can't use `validate_skill.py` without clone. | Rejected |
| `contrib/` directory | Opt-in. Lives in same repo. Uses same validation. Single `deploy.sh` with flags. | Slightly more complex `deploy.sh`. | **Adopted** |
| `.optional/` or `extras/` | Same as contrib | Less conventional naming. | Rejected |

**User experience for external developers:**

1. Clone claude-devkit
2. Run `./scripts/deploy.sh` -- deploys core skills only (dream, ship, audit, sync, test-idempotent)
3. Optionally browse `contrib/README.md` to see available optional skills
4. Run `./scripts/deploy.sh --contrib journal` to deploy journal skill
5. The journal skill uses embedded default templates. If the user has their own Obsidian vault at `~/journal/` with templates, the skill will prefer on-disk templates over embedded defaults.

**Configuration question: How do contrib skills handle user-specific paths?**

The journal skill hardcodes `~/journal/` as the base path. For external developers, this path may differ. Options:

1. **Hardcode and document**: Keep `~/journal/` in the skill. Document that users should change this path if their journal is elsewhere. This is the simplest approach and matches how the existing core skills work (e.g., `/dream` references `./plans/` which is relative to the project).
2. **Environment variable**: Use `$JOURNAL_PATH` with a fallback to `~/journal/`. More flexible but adds setup complexity.

**Recommendation: Hardcode `~/journal/` and document.** The journal skill is inherently personal/opinionated. Users who opt in to deploy it will need to customize templates anyway. Changing one path is trivial.

---

## Interfaces / Schema Changes

### Skill Frontmatter (journal)

```yaml
---
name: journal
version: 1.0.0
model: claude-opus-4-6
description: Write entries to the Obsidian work journal. Creates daily logs, meeting notes, project updates, learnings, and decision records. Use when the user says "journal", "log", "daily entry", "meeting notes", "learning", "decision", "ADR", "capture this", "write down", "record this", or wants to document work for future reference.
---
```

### Skill Frontmatter (journal-recall)

```yaml
---
name: journal-recall
version: 1.0.0
model: claude-opus-4-6
description: Search, retrieve, and summarize past journal entries. Use when the user says "what did I", "recall", "look up", "find in journal", "journal search", "last week", "weekly review", "what happened on", "summarize my week", "what have I been working on", "review my journal", or asks about past work, decisions, meetings, or notes.
---
```

### Skill Body Structure (both skills)

Both SKILL.md files must include these structural elements for `validate_skill.py` compliance:

- `# /journal Workflow` (or `# /journal-recall Workflow`) as the top-level header
- `## Inputs` section listing expected user input and parameters
- Numbered steps as `## Step N -- [Action]`
- Verdict keywords (`PASS` / `FAIL`) in the final step's output instructions
- Stub sections for non-applicable patterns:
  - `## Timestamped Artifacts` -- "Not applicable: journal entries are permanent records, not workflow artifacts."
  - `## Bounded Iterations` -- "Not applicable: journal entry creation is a single-pass operation."
  - `## Archive on Success` -- "Not applicable: journal entries are the final output."

### deploy.sh Interface Change

**New flags:**

| Flag | Behavior |
|------|----------|
| (no args) | Deploy all skills from `skills/` (existing behavior, unchanged) |
| `<name>` | Deploy one skill from `skills/` (existing behavior, unchanged) |
| `--contrib` | Deploy all skills from `contrib/` |
| `--contrib <name>` | Deploy one skill from `contrib/` |
| `--all` | Deploy all skills from both `skills/` and `contrib/` |
| `--help` | Print usage summary and exit |
| `-*` (unknown) | Print error and exit with code 1 |

### Directory Structure (journal vault -- no changes)

The journal vault at `~/journal/` requires no structural changes. The skill will use the existing directories:

```
~/journal/
  daily/           YYYY-MM-DD.md
  meetings/        YYYY-MM-DD-meeting-topic.md
  projects/        {project-name}.md
  learnings/       {topic-name}.md
  decisions/       YYYY-MM-DD-decision-name.md
  templates/       daily.md, meeting.md, project.md, learning.md, decision.md
```

---

## Data Migration

### Existing Entries at `~/projects/work-journal/` (Migration Required)

The currently deployed `/journal` skill targets `~/projects/work-journal/`, which exists and contains real entries:

**Files found:**
- `daily/2026-02-22.md` (178 bytes)
- `daily/2026-02-23.md` (5.2 KB)
- `daily/2026-02-24.md` (6.1 KB)
- `daily/_template.md` (template, skip)
- `projects/project-fugue.md` (3.4 KB)
- `projects/_template.md` (template, skip)
- `ideas/ideas.md` (428 bytes)
- `todos/todos.md` (1.4 KB)

**Migration procedure (Phase 1, Step 1.2):**

1. **Daily entries**: For each `daily/*.md` file (excluding `_template.md`):
   - Check if a file with the same date already exists at `~/journal/daily/YYYY-MM-DD.md`.
   - If the target file does NOT exist: copy the old entry to `~/journal/daily/`, adding YAML frontmatter (`date`, `tags: [migrated]`) at the top if missing.
   - If the target file DOES exist: append the old entry's content as a `### Migrated Session (from work-journal)` block under `## Work Sessions`. Do not overwrite existing content.
2. **Project entries**: For `projects/project-fugue.md`:
   - Check if `~/journal/projects/project-fugue.md` exists.
   - If not, copy it over, adding YAML frontmatter if missing.
   - If yes, append the old content under `## Recent Activity` with a `### Migrated (from work-journal)` heading.
3. **Ideas and todos**: For `ideas/ideas.md` and `todos/todos.md`:
   - These entry types are being deprecated. Content will be appended to the daily entry for the migration date (today) under `## Migrated Content` as a one-time consolidation.
   - This preserves the content without creating files in directories that the new skill does not manage.
4. **After migration**: Rename `~/projects/work-journal/` to `~/projects/work-journal.migrated/` (do not delete; keep as backup until manual verification confirms all content is accounted for).

### Existing Skills (Replace in Place)

The existing deployed skills at `~/.claude/skills/journal/SKILL.md` and `~/.claude/skills/journal-recall/SKILL.md` will be overwritten by `deploy.sh`. No migration logic needed -- the deploy is a file copy.

---

## Rollout Plan

### Phase 1: Migrate Data and Rewrite Skills (Day 1, ~4 hours)

**Entry criteria:** None. First phase.

1. **Verify journal filesystem.** Confirm `~/journal/` structure, templates, and existing entries.
2. **Migrate entries from `~/projects/work-journal/`** to `~/journal/` following the migration procedure above. Rename old directory to `~/projects/work-journal.migrated/`.
3. **Create `contrib/` directory** in claude-devkit repo.
4. **Write `/journal` skill** at `~/projects/claude-devkit/contrib/journal/SKILL.md`, including:
   - Frontmatter with `name`, `version`, `model`, and `description` fields.
   - `# /journal Workflow` top-level header.
   - `## Inputs` section.
   - Path sanitization logic in Step 1.
   - Embedded default templates for all 5 entry types (with on-disk override note).
   - Template validation pre-flight: verify template file exists and starts with `---` (YAML frontmatter); if missing or malformed, fall back to embedded template; if embedded template also unavailable, report error and abort.
   - Explicit append semantics for daily and project entries.
   - Disambiguation heuristic for entry type detection.
   - Deprecated entry type handling (idea, todo redirection).
   - Verdict keywords in Step 5.
   - Stub sections for non-applicable patterns.
5. **Write `/journal-recall` skill** at `~/projects/claude-devkit/contrib/journal-recall/SKILL.md`, with same structural compliance.
6. **Write `contrib/README.md`** documenting available contrib skills, prerequisites (journal vault structure), and deployment instructions.
7. **Validate both skills** with `validate_skill.py`.
8. **If validation fails on missing patterns**, review error output and add/adjust stub sections. Re-validate until both skills pass (exit code 0).

**Acceptance criteria:**
- Both skills pass `validate_skill.py` (exit code 0).
- `/journal` skill references `~/journal/` (not `~/projects/work-journal/`).
- `/journal` skill supports all 5 entry types: daily, meeting, project, learning, decision.
- `/journal` skill includes embedded default templates and on-disk override logic.
- `/journal` skill includes path sanitization step.
- `/journal` skill defines explicit append semantics for daily and project entries.
- `/journal-recall` skill references `~/journal/` (not `~/projects/work-journal/`).
- `contrib/` directory exists with both skills and a README.
- All entries from `~/projects/work-journal/` are accounted for in `~/journal/`.
- `~/projects/work-journal/` has been renamed to `~/projects/work-journal.migrated/`.

### Phase 2: Update deploy.sh (Day 1, ~1.5 hours)

**Entry criteria:** Phase 1 complete.

1. **Modify `deploy.sh`** to support `--contrib`, `--contrib <name>`, `--all`, and `--help` flags, using the argument parsing specification from Part 4.
2. **Add unknown-flag rejection**: any argument starting with `-` that is not a recognized flag produces an error and exits with code 1.
3. **Add `--help` handler** printing usage summary.
4. **Test deploy.sh** with all flag combinations (see Test Plan).
5. **Deploy both journal skills** using `./scripts/deploy.sh --contrib`.

**Acceptance criteria:**
- `./scripts/deploy.sh` deploys only core skills (existing behavior preserved).
- `./scripts/deploy.sh --contrib journal` deploys journal skill to `~/.claude/skills/journal/SKILL.md`.
- `./scripts/deploy.sh --contrib` deploys both contrib skills.
- `./scripts/deploy.sh --all` deploys all core and contrib skills.
- `./scripts/deploy.sh --help` prints usage.
- `./scripts/deploy.sh --unknown` exits with error.
- `./scripts/deploy.sh --contrib --verbose` exits with error (not treated as skill name).
- Deployed skill files match source files exactly.

### Phase 3: Manual Testing (Day 1-2, ~1.5 hours)

**Entry criteria:** Phase 2 complete. Skills deployed.

1. **Test `/journal` daily entry**: Say "journal: worked on journal skill rewrite today, 3 hours focused" and verify output.
2. **Test `/journal` learning entry**: Say "I learned that contrib directories solve the distribution problem for opinionated skills" and verify output.
3. **Test `/journal` decision entry**: Say "We decided to use a contrib directory instead of bundling journal in core devkit skills" and verify output.
4. **Test `/journal` meeting entry**: Say "Log my standup with the team, discussed sprint priorities" and verify output.
5. **Test `/journal` project update**: Say "Update claude-devkit project: implemented contrib directory and journal skill rewrite" and verify output.
6. **Test `/journal-recall` search**: Say "What did I work on yesterday?" and verify output.
7. **Test `/journal-recall` weekly review**: Say "Summarize this week" and verify output.
8. **Test `/journal-recall` keyword search**: Say "When did I work on worktree isolation?" and verify output.
9. **Test error: missing template**: Temporarily rename `~/journal/templates/learning.md` and attempt a learning entry. Verify the skill falls back to the embedded template and does not crash. Restore the template file.
10. **Test error: path traversal**: Say "log a learning about ../../.ssh/something" and verify the skill rejects the path or sanitizes it to a safe filename.
11. **Test deprecated type**: Say "journal an idea about skill distribution" and verify the skill redirects to a daily note or learning entry with an explanation.

**Acceptance criteria:**
- All 11 test scenarios produce correct output.
- Created entries match Obsidian template format (YAML frontmatter, wikilinks).
- Existing entries are appended to (not overwritten) for daily and project types, with new content placed in the correct section.
- Search and retrieval correctly find entries across all directories.
- Error cases produce clear messages without crashes or data corruption.

### Phase 4: Commit and Document (Day 2, ~1 hour)

**Entry criteria:** Phase 3 complete. All tests pass.

1. **Commit changes** to claude-devkit repo.
2. **Update claude-devkit CLAUDE.md**:
   - Skill registry: add journal and journal-recall as contrib skills.
   - Architecture section: add `contrib/` to the directory structure (four-tier: `skills/`, `contrib/`, `generators/`, `templates/`).
   - Data flow diagram: update to show `contrib/` path.
   - Directory reference: add `contrib/` entry.
   - Development Rules: add note that `contrib/` skills follow the same `<name>/SKILL.md` structure as `skills/` but are deployed opt-in via `--contrib` flag.
   - Fix stale path references: replace `~/workspaces/claude-devkit` with `~/projects/claude-devkit` throughout.
3. **Create journal entry** documenting this work (using the newly working skill).

**Acceptance criteria:**
- Changes committed to claude-devkit with descriptive commit message.
- CLAUDE.md architecture, directory reference, data flow, and skill registry all updated to include `contrib/`.
- CLAUDE.md path references corrected to `~/projects/claude-devkit`.
- Journal entry created for today documenting the implementation.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `validate_skill.py` rejects skills despite stub sections | Low | Low | Phase 1 includes an explicit iterate-until-pass step (1.8). Test early, adjust stub wording to include required keywords. |
| Template drift: Obsidian templates change but embedded defaults in SKILL.md are stale | Low | Medium | Skill prefers on-disk templates at `~/journal/templates/` when available. Embedded defaults are a fallback, not the primary source. Document that embedded templates should be updated when on-disk templates change significantly. |
| `deploy.sh` changes break existing deployment | Low | High | Phase 2 explicitly preserves existing behavior (no-arg deploys core only). Test regression before committing. Rollback: `git checkout scripts/deploy.sh`. |
| External developers confused by `contrib/` | Low | Low | `contrib/README.md` documents purpose and usage. `deploy.sh --help` lists available flags. |
| Migration loses or corrupts entries from `~/projects/work-journal/` | Low | High | Migration renames (not deletes) old directory. Backup exists at `~/projects/work-journal.migrated/` until manual verification. |
| Path traversal in user-supplied topic names | Low | Medium | Step 1 sanitizes filenames: strips path separators, `..` sequences, and non-alphanumeric characters. Verifies resolved path starts with `~/journal/`. |

---

## Test Plan

### Validation Tests

```bash
# Validate journal skill against devkit patterns
cd ~/projects/claude-devkit
python generators/validate_skill.py contrib/journal/SKILL.md

# Validate journal-recall skill against devkit patterns
python generators/validate_skill.py contrib/journal-recall/SKILL.md

# Expected: both exit code 0
```

### deploy.sh Tests

```bash
cd ~/projects/claude-devkit

# Clean up from any prior test runs
rm -rf ~/.claude/skills/journal ~/.claude/skills/journal-recall

# Test 1: Default deploy (core only) -- should NOT deploy contrib
./scripts/deploy.sh
test -f ~/.claude/skills/dream/SKILL.md && echo "PASS: core deployed" || echo "FAIL"
test -f ~/.claude/skills/journal/SKILL.md && echo "FAIL: contrib deployed by default" || echo "PASS: contrib not deployed"

# Clean up
rm -rf ~/.claude/skills/journal ~/.claude/skills/journal-recall

# Test 2: Deploy single contrib skill
./scripts/deploy.sh --contrib journal
test -f ~/.claude/skills/journal/SKILL.md && echo "PASS: journal deployed" || echo "FAIL"

# Clean up
rm -rf ~/.claude/skills/journal ~/.claude/skills/journal-recall

# Test 3: Deploy all contrib skills
./scripts/deploy.sh --contrib
test -f ~/.claude/skills/journal/SKILL.md && echo "PASS: journal deployed" || echo "FAIL"
test -f ~/.claude/skills/journal-recall/SKILL.md && echo "PASS: recall deployed" || echo "FAIL"

# Test 4: Deploy all (core + contrib)
./scripts/deploy.sh --all
test -f ~/.claude/skills/dream/SKILL.md && echo "PASS: core deployed" || echo "FAIL"
test -f ~/.claude/skills/journal/SKILL.md && echo "PASS: contrib deployed" || echo "FAIL"

# Test 5: Invalid contrib skill name
./scripts/deploy.sh --contrib nonexistent 2>&1 | grep -q "ERROR" && echo "PASS: error on invalid" || echo "FAIL"

# Test 6: Unknown flag rejection
./scripts/deploy.sh --unknown 2>&1 | grep -q "ERROR" && echo "PASS: unknown flag rejected" || echo "FAIL"

# Test 7: Flag-as-skill-name rejection
./scripts/deploy.sh --contrib --verbose 2>&1 | grep -q "ERROR" && echo "PASS: flag-as-name rejected" || echo "FAIL"

# Test 8: Help flag
./scripts/deploy.sh --help 2>&1 | grep -q "Usage" && echo "PASS: help works" || echo "FAIL"
```

### Content Tests (Manual)

These are executed manually in a Claude Code session after deployment:

1. **Daily entry creation**: `/journal log today's work on journal skill blueprint` -- verify file at `~/journal/daily/2026-02-24.md` is updated (not overwritten) with correct session format under `## Work Sessions`.
2. **Learning entry creation**: `/journal save learning: contrib directories solve distribution` -- verify file created at `~/journal/learnings/contrib-directory-distribution.md` with YAML frontmatter.
3. **Decision entry creation**: `/journal record decision: use contrib not core for journal skills` -- verify file at `~/journal/decisions/2026-02-24-contrib-over-core.md` with ADR format.
4. **Recall search**: `/journal-recall search worktree isolation` -- verify returns results from `~/journal/daily/2026-02-23.md`.
5. **Recall weekly**: `/journal-recall summarize this week` -- verify reads all daily entries from past 7 days.
6. **Missing template fallback**: Rename `~/journal/templates/learning.md` temporarily, create a learning entry, verify embedded template is used, restore file.
7. **Path traversal rejection**: Attempt `../../.ssh/something` as a topic name, verify sanitization.
8. **Deprecated type redirection**: Say "journal an idea", verify redirection to daily/learning.

### Exact Test Command

```bash
# Full automated test suite (run from claude-devkit root):
cd ~/projects/claude-devkit && \
  python generators/validate_skill.py contrib/journal/SKILL.md && \
  python generators/validate_skill.py contrib/journal-recall/SKILL.md && \
  echo "=== deploy.sh tests ===" && \
  rm -rf ~/.claude/skills/journal ~/.claude/skills/journal-recall && \
  ./scripts/deploy.sh && \
  test ! -f ~/.claude/skills/journal/SKILL.md && \
  ./scripts/deploy.sh --contrib journal && \
  test -f ~/.claude/skills/journal/SKILL.md && \
  rm -rf ~/.claude/skills/journal ~/.claude/skills/journal-recall && \
  echo "ALL AUTOMATED TESTS PASSED"
```

---

## Acceptance Criteria

1. `/journal` skill correctly writes entries to `~/journal/` (not `~/projects/work-journal/`).
2. `/journal` skill supports 5 entry types: daily, meeting, project, learning, decision.
3. All generated entries include YAML frontmatter matching the Obsidian templates at `~/journal/templates/`.
4. All generated entries use wikilinks for cross-referencing (e.g., `[[daily/2026-02-24]]`, `[[project-name]]`).
5. `/journal` skill embeds default templates in SKILL.md and prefers on-disk templates at `~/journal/templates/` when available.
6. `/journal` skill includes path sanitization that rejects `..` segments, path separators, and non-alphanumeric characters in user-supplied names.
7. `/journal` skill defines explicit append semantics: daily entries append under `## Work Sessions` as `### Session N`; project entries append under `## Recent Activity` as `### YYYY-MM-DD`.
8. `/journal-recall` skill correctly searches `~/journal/` (not `~/projects/work-journal/`).
9. `/journal-recall` supports: specific date lookup, date range, keyword search, project status, weekly review.
10. Both skills pass `validate_skill.py` validation (exit code 0), including `model` field, `# /skill-name Workflow` header, `## Inputs` section, and verdict keywords.
11. `deploy.sh` default behavior (no args) is unchanged -- deploys only core skills.
12. `deploy.sh --contrib journal` deploys the journal skill to `~/.claude/skills/journal/`.
13. `deploy.sh --all` deploys both core and contrib skills.
14. `deploy.sh` rejects unknown flags and flag-like strings as skill names.
15. `deploy.sh --help` prints usage.
16. `contrib/README.md` exists and documents available optional skills and prerequisites.
17. claude-devkit `CLAUDE.md` updated: skill registry (contrib section), architecture diagram (four-tier with `contrib/`), directory reference, data flow, development rules, and path correction (`~/projects/` not `~/workspaces/`).
18. Existing daily entries at `~/journal/daily/` are not corrupted by the new skills.
19. Entries from `~/projects/work-journal/` have been migrated to `~/journal/`, with the old directory renamed to `~/projects/work-journal.migrated/`.

---

## Task Breakdown

### Phase 1: Migrate Data and Rewrite Skills (~4 hours)

| # | Task | File | Action |
|---|------|------|--------|
| 1.1 | Verify journal filesystem | `~/journal/` | Run `ls`, confirm structure matches spec |
| 1.2 | Migrate entries from old path | `~/projects/work-journal/` -> `~/journal/` | Follow migration procedure; rename old dir to `.migrated` |
| 1.3 | Create contrib directory | `~/projects/claude-devkit/contrib/` | `mkdir -p` |
| 1.4 | Create contrib journal directory | `~/projects/claude-devkit/contrib/journal/` | `mkdir -p` |
| 1.5 | Create contrib journal-recall directory | `~/projects/claude-devkit/contrib/journal-recall/` | `mkdir -p` |
| 1.6 | Write journal SKILL.md | `~/projects/claude-devkit/contrib/journal/SKILL.md` | Create (full rewrite with embedded templates, on-disk override, path sanitization, append semantics, validator compliance) |
| 1.7 | Write journal-recall SKILL.md | `~/projects/claude-devkit/contrib/journal-recall/SKILL.md` | Create (rewrite with correct path, Obsidian-aware search, validator compliance) |
| 1.8 | Write contrib README.md | `~/projects/claude-devkit/contrib/README.md` | Create (document available contrib skills, prerequisites, deployment instructions) |
| 1.9 | Validate journal skill | N/A | Run `validate_skill.py contrib/journal/SKILL.md` |
| 1.10 | Validate journal-recall skill | N/A | Run `validate_skill.py contrib/journal-recall/SKILL.md` |
| 1.11 | Fix validation issues (iterate until pass) | `contrib/journal/SKILL.md`, `contrib/journal-recall/SKILL.md` | Adjust stub sections, keywords, headers as needed until exit code 0 |

### Phase 2: Update deploy.sh (~1.5 hours)

| # | Task | File | Action |
|---|------|------|--------|
| 2.1 | Add contrib deployment to deploy.sh | `~/projects/claude-devkit/scripts/deploy.sh` | Modify (add `--contrib`, `--all`, `--help` flags, unknown-flag rejection, `CONTRIB_DIR` variable) |
| 2.2 | Test default deployment | N/A | Run `./scripts/deploy.sh`, verify core-only |
| 2.3 | Test contrib deployment | N/A | Run `./scripts/deploy.sh --contrib journal` |
| 2.4 | Test all deployment | N/A | Run `./scripts/deploy.sh --all` |
| 2.5 | Test error handling | N/A | Run `./scripts/deploy.sh --contrib nonexistent`, `--unknown`, `--contrib --verbose` |
| 2.6 | Test help output | N/A | Run `./scripts/deploy.sh --help` |
| 2.7 | Deploy journal skills | `~/.claude/skills/journal/SKILL.md`, `~/.claude/skills/journal-recall/SKILL.md` | Run `./scripts/deploy.sh --contrib` |

### Phase 3: Manual Testing (~1.5 hours)

| # | Task | File | Action |
|---|------|------|--------|
| 3.1 | Test daily entry (new file) | `~/journal/daily/YYYY-MM-DD.md` | Create via `/journal` |
| 3.2 | Test daily entry (append) | `~/journal/daily/2026-02-24.md` | Update via `/journal`, verify content under `## Work Sessions > ### Session N` |
| 3.3 | Test meeting entry | `~/journal/meetings/YYYY-MM-DD-*.md` | Create via `/journal` |
| 3.4 | Test project update | `~/journal/projects/*.md` | Update via `/journal`, verify content under `## Recent Activity > ### YYYY-MM-DD` |
| 3.5 | Test learning entry | `~/journal/learnings/*.md` | Create via `/journal` |
| 3.6 | Test decision entry | `~/journal/decisions/*.md` | Create via `/journal` |
| 3.7 | Test date lookup | N/A | Query via `/journal-recall` |
| 3.8 | Test keyword search | N/A | Query via `/journal-recall` |
| 3.9 | Test weekly review | N/A | Query via `/journal-recall` |
| 3.10 | Test missing template fallback | `~/journal/templates/learning.md` | Temporarily rename, create learning entry, verify embedded fallback, restore |
| 3.11 | Test path traversal rejection | N/A | Attempt `../../.ssh/something` as topic, verify sanitization |
| 3.12 | Test deprecated type redirection | N/A | Say "journal an idea", verify redirection |
| 3.13 | Verify YAML frontmatter in all created entries | All created files | Read and verify format |
| 3.14 | Verify wikilinks in all created entries | All created files | Read and verify format |

### Phase 4: Commit and Document (~1 hour)

| # | Task | File | Action |
|---|------|------|--------|
| 4.1 | Remove old deployed skills | `~/.claude/skills/journal/SKILL.md`, `~/.claude/skills/journal-recall/SKILL.md` | Delete (will be replaced by deploy.sh) |
| 4.2 | Update CLAUDE.md | `~/projects/claude-devkit/CLAUDE.md` | Update skill registry (contrib section), architecture (four-tier), directory reference, data flow, development rules, fix path references |
| 4.3 | Commit all changes | N/A | `git add contrib/ scripts/deploy.sh CLAUDE.md && git commit` |
| 4.4 | Create journal entry for this work | `~/journal/daily/2026-02-24.md` | Update via `/journal` (test the new skill) |

---

## Appendix A: Template Mapping Reference

This table maps each entry type to its Obsidian template, file path pattern, and key fields.

| Entry Type | Template | File Path | YAML Frontmatter Keys | Wikilink Targets |
|------------|----------|-----------|----------------------|------------------|
| daily | `templates/daily.md` | `daily/YYYY-MM-DD.md` | date, day_of_week, tags, projects, mood, energy, focus_time | `[[project-name]]`, `[[YYYY-MM-DD]]` (prev only; determined by globbing `daily/*.md`) |
| meeting | `templates/meeting.md` | `meetings/YYYY-MM-DD-topic.md` | title, date, time, attendees, tags | `[[daily/YYYY-MM-DD]]`, `[[project-name]]` |
| project | `templates/project.md` | `projects/{name}.md` | title, repo, status, started, tags, tech_stack | `[[daily/YYYY-MM-DD]]`, `[[decisions/YYYY-MM-DD-name]]`, `[[learnings/topic]]` |
| learning | `templates/learning.md` | `learnings/{topic}.md` | title, date, tags, category, confidence | `[[daily/YYYY-MM-DD]]`, `[[project-name]]` |
| decision | `templates/decision.md` | `decisions/YYYY-MM-DD-name.md` | title, date, status, tags, projects | `[[daily/YYYY-MM-DD]]`, `[[project-name]]` |

## Appendix B: deploy.sh Argument Parsing (Pseudocode)

```bash
# New variables
CONTRIB_DIR="$REPO_DIR/contrib"

# New function
deploy_contrib_skill() {
    local skill="$1"
    local src="$CONTRIB_DIR/$skill"
    local dst="$DEPLOY_DIR/$skill"
    if [ ! -d "$src" ]; then
        echo "ERROR: Contrib skill '$skill' not found in $src" >&2
        return 1
    fi
    mkdir -p "$dst"
    cp "$src/SKILL.md" "$dst/SKILL.md"
    echo "Deployed (contrib): $skill"
}

deploy_all_contrib() {
    for skill_dir in "$CONTRIB_DIR"/*/; do
        if [ -d "$skill_dir" ]; then
            deploy_contrib_skill "$(basename "$skill_dir")"
        fi
    done
}

# New argument handling
case "${1:-}" in
    --contrib)
        if [ $# -ge 2 ]; then
            # Reject flags passed as skill names
            if [[ "$2" == -* ]]; then
                echo "ERROR: Invalid skill name: $2" >&2
                exit 1
            fi
            deploy_contrib_skill "$2"
        else
            deploy_all_contrib
        fi
        ;;
    --all)
        deploy_all_core
        deploy_all_contrib
        ;;
    --help|-h)
        echo "Usage: deploy.sh [OPTIONS] [SKILL_NAME]"
        echo ""
        echo "Options:"
        echo "  (no args)          Deploy all core skills from skills/"
        echo "  <name>             Deploy one core skill from skills/"
        echo "  --contrib          Deploy all contrib skills from contrib/"
        echo "  --contrib <name>   Deploy one contrib skill from contrib/"
        echo "  --all              Deploy all core and contrib skills"
        echo "  --help, -h         Show this help message"
        exit 0
        ;;
    "")
        deploy_all_core
        ;;
    -*)
        echo "ERROR: Unknown flag: $1" >&2
        exit 1
        ;;
    *)
        deploy_skill "$1"
        ;;
esac
```

## Status: APPROVED

---

<!-- Context Metadata
discovered_at: 2026-02-24T09:30:00Z
revised_at: 2026-02-24T11:00:00Z
claude_md_exists: false (journal project), true (claude-devkit)
recent_plans_consulted:
  - portfolio-review-next-steps.md
  - JOURNAL_SYSTEM_SPEC.md
archived_plans_consulted: none
devkit_path_verified: ~/projects/claude-devkit (~/workspaces/claude-devkit does not exist)
work_journal_exists: true (6 content files, 2 templates found at ~/projects/work-journal/)
revision_trigger: red-team FAIL, librarian FAIL, feasibility PASS-with-adjustments
findings_addressed: F01, F02, F03, F04, F05, L1, L2, L3, L4, L5, C1, C2, M1, M2, M3
-->
