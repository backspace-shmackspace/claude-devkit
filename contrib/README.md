# Contrib Skills

This directory contains **optional** and **personal** skills that are not deployed by default. These skills require user-specific configuration or are opinionated for specific workflows.

## Available Skills

### journal

**Purpose:** Write entries to an Obsidian work journal.

**Entry types:**
- Daily logs (work sessions, priorities, wins)
- Meeting notes (agenda, decisions, action items)
- Project updates (progress, blockers, work log)
- Learnings (technical insights, gotchas, examples)
- Decision records (ADRs with options, rationale, consequences)

**Prerequisites:**
- Journal vault at `~/journal/` (or modify `JOURNAL_BASE` in skill file)
- Directory structure:
  ```
  ~/journal/
    daily/
    meetings/
    projects/
    learnings/
    decisions/
    templates/     # Optional: on-disk templates override embedded defaults
  ```
- Templates (optional): The skill includes embedded default templates for all entry types.
  - On-disk templates at `~/journal/templates/{type}.md` override embedded defaults if present
  - If no on-disk templates exist, the skill uses its embedded defaults (works out-of-the-box)
  - Supported types: `daily.md`, `meeting.md`, `project.md`, `learning.md`, `decision.md`

**Deployment:**
```bash
cd ~/projects/claude-devkit
./scripts/deploy.sh --contrib journal
```

**Usage:**
- "journal today's work on X"
- "log meeting with team about Y"
- "I learned that Z"
- "record decision to use A instead of B"
- "update project-name with progress"

---

### journal-recall

**Purpose:** Search, retrieve, and summarize past journal entries.

**Search modes:**
- Specific date lookup ("what did I do yesterday?")
- Date range ("summarize this week")
- Keyword search ("find worktree isolation")
- Project filter ("what did I do on claude-devkit?")
- Weekly review ("review this week")
- Meeting lookup ("what meetings did I have?")

**Prerequisites:**
- Same journal vault as `/journal` skill
- Journal entries must exist at `~/journal/`

**Deployment:**
```bash
cd ~/projects/claude-devkit
./scripts/deploy.sh --contrib journal-recall
```

**Usage:**
- "what did I work on last week?"
- "summarize this week"
- "find entries about Docker"
- "what's the status of my-project?"
- "what meetings did I have yesterday?"

---

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

---

## Deploying Contrib Skills

**Deploy one skill:**
```bash
./scripts/deploy.sh --contrib <skill-name>
```

**Deploy all contrib skills:**
```bash
./scripts/deploy.sh --contrib
```

**Deploy core + contrib skills:**
```bash
./scripts/deploy.sh --all
```

**See all options:**
```bash
./scripts/deploy.sh --help
```

---

## Creating Your Own Contrib Skills

Contrib skills follow the same structure as core skills:

1. Create directory: `contrib/<skill-name>/`
2. Create skill file: `contrib/<skill-name>/SKILL.md`
3. Follow skill validator requirements:
   - YAML frontmatter with `name`, `version`, `model`, `description`
   - `# /<skill-name> Workflow` header
   - `## Inputs` section
   - Numbered steps: `## Step N -- [Action]`
   - Verdict keywords (`PASS` / `FAIL`) in final step
4. Validate: `python generators/validate_skill.py contrib/<skill-name>/SKILL.md`
5. Deploy: `./scripts/deploy.sh --contrib <skill-name>`

---

## Why Contrib vs Core?

**Core skills** (`skills/`) are universal and deploy to all users:
- `/dream`, `/ship`, `/audit`, `/sync`
- No user-specific paths or configuration
- Work out-of-the-box after install

**Contrib skills** (`contrib/`) are optional and require setup:
- User-specific paths (e.g., `~/journal/`)
- Opinionated workflows (e.g., Obsidian journal format)
- Personal tools that don't generalize to all developers

**External developers** who clone claude-devkit run `./scripts/deploy.sh` and get only core skills. They can browse `contrib/README.md` to see what's available and opt in to individual skills.

---

## Path Customization

If your journal vault is not at `~/journal/`, edit the skill files directly:

1. Open `contrib/journal/SKILL.md` and `contrib/journal-recall/SKILL.md`
2. Find `JOURNAL_BASE`: `~/journal/` in the `## Inputs` section
3. Change to your journal path (e.g., `~/Documents/journal/`)
4. Redeploy: `./scripts/deploy.sh --contrib journal journal-recall`

This approach keeps path configuration explicit and avoids environment variable complexity.
