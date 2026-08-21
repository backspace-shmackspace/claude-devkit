# Cross-Repo Plan Support for devkit CLI

## Status: APPROVED

**Type:** CLI Enhancement + Skill Extension
**Archetype:** N/A (infrastructure, not a skill)
**Complexity:** High
**Estimated Time:** 18-22 hours
**Author:** devkit-architect
**Date:** 2026-08-21

---

## Goals

1. **Multi-target plan declarations.** Plans can declare they touch multiple devkit-initialized
   projects via a `targets:` field in YAML frontmatter. Each target is identified by project path
   or project-id. All targets must be devkit-initialized; validation fails otherwise.

2. **Multi-target `devkit shell`.** A new `devkit shell --targets <t1> <t2>` mode opens an
   interactive Claude session with environment variables exposing all target project artifact
   directories. CWD is set to the first target (primary). Each additional target's artifact
   directory is accessible via indexed env vars (`DEVKIT_TARGET_1_DIR`, `DEVKIT_TARGET_1_PATH`,
   etc.).

3. **Cross-project plan indexing.** When `/architect` (or `devkit architect`) produces a plan
   with multiple targets, the plan file lives in the primary target's central storage. A
   lightweight index entry (symlink-free JSON reference) is written to each secondary target's
   central storage so that `devkit status` on any involved project shows the cross-repo plan.

4. **Cross-project plan references.** Plans that reference work in another project can use
   `devkit:// <project-id>/plans/<file>` URIs that resolve via `devkit path` lookups. The
   `/architect` agent is taught to emit these URIs. `/ship` resolves them when reading plans.

5. **`devkit plan` command.** New subcommand for plan lifecycle management: list plans for a
   project, show plan details (including cross-repo targets), validate plan frontmatter, sync
   plan refs, resolve URIs, and archive completed cross-repo plans.

## Non-Goals

- **Cross-repo git operations.** No branching, committing, or merging across repositories.
  Skills still operate on one git working tree at a time. Coordination is at the planning
  level, not the execution level.
- **Workspace/monorepo support.** Monorepos are a single git repo; cross-repo support targets
  distinct repositories with distinct git histories.
- **Changing how skills execute at runtime.** `/ship` still runs against a single target
  project. A cross-repo plan with multiple work groups is shipped one project at a time (the
  plan documents the sequencing; the human or the harness invokes `/ship` per project).
- **Automatic plan splitting.** The architect produces one plan that covers multiple repos.
  Splitting it into per-repo sub-plans is a future enhancement.
- **Shared worktrees or cross-repo file access.** Each coder agent works in its target project's
  worktree. No agent reads/writes files across repos during execution.
- **Registry schema migration.** The registry is informational-only; adding optional fields to
  entries is backward-compatible and does not require a schema version bump.

## Assumptions

1. All target projects are devkit-initialized (`devkit init` has been run). The CLI validates
   this before any cross-repo operation.
2. Project IDs are stable (they are SHA-256 based and computed from resolved absolute paths).
   This is established by the zero-project-footprint plan.
3. The `devkit` CLI is the entry point for all cross-repo operations. Skills invoked directly
   within a Claude Code session operate single-project only (consistent with existing behavior).
4. Python 3.8+, stdlib only -- no external dependencies (consistent with existing requirement).
5. Plan frontmatter parsing requires a new YAML-subset parser (`parse_plan_frontmatter()`).
   The existing `parse_frontmatter()` in `validate_skill.py` (lines 43-75) is a flat key-value
   parser that splits every line on the first `:` -- it cannot handle the `targets:` field,
   which is a list of dictionaries (nested YAML). A bespoke parser is needed that handles
   the following YAML subset:

   **Supported YAML subset:**
   - `---` delimiters (opening and closing)
   - Top-level flat `key: value` pairs (string values only)
   - Top-level keys introducing lists: `key:` with no value on the same line, followed by
     indented `- subkey: value` entries that form a list of flat dictionaries
   - List items: lines starting with `  - ` (two-space indent + dash + space)
   - Sub-keys within a list item: lines starting with `    ` (four-space indent, no dash)
   - Blank lines and `#` comment lines within frontmatter are ignored

   **NOT supported (and rejected with an error):**
   - Nested lists (lists within lists)
   - Multi-line values (`|`, `>` block scalars)
   - Anchors and aliases (`&`, `*`)
   - Flow syntax (`{}`, `[]`)
   - YAML tags (`!!`)
   - Quoted keys
   - Type coercion (everything is a string)

   **Parser specification (`parse_plan_frontmatter()`):**

   ```python
   def parse_plan_frontmatter(content: str) -> Tuple[Dict, str]:
       """Parse plan YAML frontmatter supporting flat keys and one-deep list-of-dicts.

       Returns (frontmatter_dict, error_message).
       On success: ({"status": "DRAFT", "targets": [{"path": "...", "role": "..."}]}, "")
       On failure: ({}, "error description")

       Failure is atomic: if any line cannot be parsed, the entire parse fails.
       No partial results are ever returned.
       """
       # 1. Extract frontmatter block between --- delimiters.
       #    If no opening --- on line 1, return ({}, "").
       #    If no closing ---, return ({}, "unclosed frontmatter").

       # 2. Parse line by line, tracking state:
       #    state = "top" | "in_list"
       #    current_list_key = None
       #    current_item = None
       #
       #    For each line (stripped of trailing whitespace):
       #      Skip blank lines and lines starting with #.
       #
       #      If state == "top":
       #        Match /^([a-zA-Z_][\w_-]*)\s*:\s*(.+)$/ -> flat key-value
       #          result[key] = value.strip().strip('"').strip("'")
       #        Match /^([a-zA-Z_][\w_-]*)\s*:\s*$/ -> begin list
       #          current_list_key = key
       #          result[key] = []
       #          state = "in_list"
       #        Else -> return ({}, f"unparseable line: {line}")
       #
       #      If state == "in_list":
       #        Match /^\s+-\s+([a-zA-Z_][\w_-]*)\s*:\s*(.+)$/ -> new list item
       #          If current_item is not None:
       #            result[current_list_key].append(current_item)
       #          current_item = {key: value.strip().strip('"').strip("'")}
       #        Match /^\s+([a-zA-Z_][\w_-]*)\s*:\s*(.+)$/ -> sub-key in current item
       #          If current_item is None:
       #            return ({}, "sub-key without list item")
       #          current_item[key] = value.strip().strip('"').strip("'")
       #        Match /^([a-zA-Z_][\w_-]*)\s*:/ -> new top-level key (end of list)
       #          If current_item is not None:
       #            result[current_list_key].append(current_item)
       #            current_item = None
       #          state = "top"
       #          Re-process this line in "top" state
       #        Else -> return ({}, f"unparseable line in list: {line}")
       #
       #    After all lines: flush current_item if in_list state.

       # 3. Return (result, "")
   ```

   This parser is approximately 50-80 lines of Python. It is new code, not a reuse of the
   existing `validate_skill.py` parser.

   **Failure mode:** Atomic. If any line within the frontmatter block cannot be parsed by the
   grammar above, `parse_plan_frontmatter()` returns `({}, "error description")` with the
   offending line quoted. No partial target lists are ever returned. This prevents a
   cross-repo plan from being silently treated as single-project due to a formatting error
   in the second target entry.

6. At most 10 targets per cross-repo plan. This is a practical limit that avoids env var
   explosion and keeps CLI ergonomics manageable. The limit is read from config via
   `config.get("max_cross_repo_targets", 10)` (consistent with existing `max_state_file_bytes`
   pattern). Enforced in `validate_plan_targets()`.

## Proposed Design

### Architecture Overview

```
~/.claude-devkit/
├── registry.json                           # Existing: gains optional cross_repo_plans index
├── projects/
│   ├── lightwell-intake-automation-c627b.../
│   │   ├── state.json                      # Existing
│   │   ├── plans/
│   │   │   ├── integrate-cve-api.md        # Primary plan (lives here)
│   │   │   └── ...
│   │   └── plan-refs/                      # NEW: cross-repo plan references
│   │       └── integrate-cve-api.ref.json  # Reference to plan in another project
│   └── cve-api-f25db5e61a87/
│       ├── state.json
│       ├── plans/
│       │   └── ...
│       └── plan-refs/                      # NEW: reference back to primary plan
│           └── integrate-cve-api.ref.json
```

### Component 1: Plan Frontmatter Extension

Plans that span multiple projects include a `targets:` field in YAML frontmatter:

```yaml
---
status: DRAFT
targets:
  - path: ~/projects/lightwell-intake-automation
    role: primary
  - path: ~/projects/cve-api
    role: secondary
---
```

**Semantics:**

- `role: primary` -- the project where the plan file is stored. Exactly one target must
  have this role.
- `role: secondary` -- projects referenced by the plan. Work groups in the plan's Task
  Breakdown indicate which target each group operates on.
- Both `path` and `project_id` are accepted as target identifiers. When `path` is given,
  the CLI resolves and validates it, then computes the project-id. When `project_id` is
  given, the CLI looks it up in the registry.
- Backward compatibility: plans without a `targets:` field are treated as single-project
  plans scoped to whichever project they reside in (existing behavior, unchanged).

**Frontmatter parsing:** Uses `parse_plan_frontmatter()` as specified in Assumption 5.
The parser handles the `targets:` list-of-dicts structure and returns an atomic result
(all-or-nothing, no partial parses).

### Component 2: Plan Reference Index (`plan-refs/`)

When a cross-repo plan is created, a lightweight JSON reference file is written to each
involved project's central storage under `plan-refs/`:

```json
{
  "schema_version": "1.0.0",
  "plan_name": "integrate-cve-api",
  "plan_file": "integrate-cve-api.md",
  "primary_project_id": "lightwell-intake-automation-c627b987f6da",
  "primary_project_path": "/Users/imurphy/projects/lightwell-intake-automation",
  "primary_plan_path": "/Users/imurphy/.claude-devkit/projects/lightwell-intake-automation-c627b987f6da/plans/integrate-cve-api.md",
  "role": "secondary",
  "all_targets": [
    {
      "project_id": "lightwell-intake-automation-c627b987f6da",
      "project_path": "/Users/imurphy/projects/lightwell-intake-automation",
      "role": "primary"
    },
    {
      "project_id": "cve-api-f25db5e61a87",
      "project_path": "/Users/imurphy/projects/cve-api",
      "role": "secondary"
    }
  ],
  "created_at": "2026-08-21T16:00:00Z",
  "created_by": "devkit-architect"
}
```

**Key invariants:**

- The primary project gets a ref file too (with `"role": "primary"`), providing a single
  place to list all involved projects without re-parsing the plan's YAML frontmatter.
- Ref files are named `<plan-basename>.ref.json` (matching the plan file basename without
  extension).
- Ref files are informational only (like the registry). Losing or corrupting them does not
  break any workflow -- at worst, `devkit status` stops showing cross-repo relationships
  until `devkit plan sync` rebuilds them.
- No symlinks. The ref file contains an absolute path to the primary plan file. Tools read
  the plan via the path, not via a symlink dereference. This preserves the no-symlink
  invariant established in `validate_target()`.
- **All paths in ref files are absolute (no tildes).** Paths are expanded via
  `Path.expanduser().resolve()` before writing, matching the pattern used in `state.json`
  where `project_path` is always an absolute path. This avoids the need for tilde expansion
  on read and prevents breakage if ref files are processed by tools that do not expand `~`.

### Component 3: `devkit plan` Subcommand

New CLI subcommand for plan lifecycle management:

```bash
# List plans for a project (including cross-repo refs)
devkit plan list <target>

# Show plan details (targets, status, work groups)
devkit plan show <target> <plan-name>

# Validate plan frontmatter (targets exist, are initialized, roles valid)
devkit plan validate <target> <plan-file>

# Sync plan-refs/ from plan frontmatter (rebuild after manual edits)
devkit plan sync <target>

# Resolve a devkit:// URI to an absolute path
devkit plan resolve <uri>

# Archive a cross-repo plan (remove refs from all involved projects)
devkit plan archive <target> <plan-name>
```

**`devkit plan list` output:**

```
PLAN                       STATUS    TARGETS  ROLE       CREATED
integrate-cve-api          DRAFT     2        primary    2026-08-21
add-intake-webhooks        APPROVED  1        -          2026-08-20
fix-db-migration           DRAFT     1        -          2026-08-19
cve-api-v2-redesign        DRAFT     2        secondary  2026-08-18
```

The `TARGETS` column shows how many projects are involved. The `ROLE` column shows this
project's role in cross-repo plans (`-` for single-project plans).

**`devkit plan sync` algorithm:**

1. Validate the target, resolve its project directory.
2. Scan all `*.md` files in the target's `plans/` directory (not `archive/`).
3. For each plan file, call `parse_plan_frontmatter()`. Skip files that have no `targets:`
   field (single-project plans).
4. For each cross-repo plan, validate each target path:
   - Call `validate_target()` on each `path` from the frontmatter.
   - If a secondary target fails validation (not initialized, path missing, etc.), log a
     warning and skip that target. Do not fail the entire sync.
   - If the primary target fails validation, log an error and skip the entire plan.
5. Call `write_plan_refs()` for each valid cross-repo plan, writing ref files to all
   reachable targets' `plan-refs/` directories.
6. Scan existing `*.ref.json` files in the target's `plan-refs/` directory. For each ref
   file, check if the referenced plan still exists at its `primary_plan_path`. If not,
   delete the stale ref file and log a notice.
7. Report results: plans synced, refs created, stale refs removed, unreachable targets.

**`devkit plan archive` algorithm:**

1. Validate the target, resolve its project directory.
2. Read the ref file at `plan-refs/<plan-name>.ref.json` to find all involved projects.
   If no ref file exists, check if the plan exists as a local-only plan and report
   "no cross-repo refs to clean up."
3. For each project in `all_targets`:
   a. Validate the project path (skip unreachable projects with a warning).
   b. Delete `plan-refs/<plan-name>.ref.json` from that project's central storage.
4. Move the plan file to `plans/archive/<plan-name>/` (existing archive pattern).
5. Report results.

This command is also called by `/ship` when archiving a cross-repo plan (see Component 8).

### Component 4: Multi-Target `devkit shell`

Extended syntax for multi-target interactive sessions:

```bash
# Single target (existing, unchanged)
devkit shell ~/projects/lightwell-intake-automation

# Multi-target (new)
devkit shell ~/projects/lightwell-intake-automation --with ~/projects/cve-api
```

**`--with` flag extraction algorithm:**

The `--with` flag is materially more complex than `--detach` (which is a boolean flag).
`--with` takes a required value (a target path), can appear multiple times, and must be
extracted before `split_skill_args()` runs. The extraction algorithm:

```python
def extract_with_targets(args: list) -> Tuple[list, list]:
    """Extract --with <path> pairs from an argument list.

    Returns (remaining_args, with_targets).
    with_targets is a list of raw path strings (not yet validated).

    Extraction runs BEFORE --detach extraction and split_skill_args().
    --with and its following argument are consumed as a pair; they do
    not reach split_skill_args() or validate_args().

    Errors:
      --with at end of args with no following path -> exit 2.
      --with followed by another flag (--xyz) -> exit 2 (path expected).
    """
    remaining = []
    targets = []
    i = 0
    while i < len(args):
        if args[i] == "--with":
            if i + 1 >= len(args):
                print("Error: --with requires a target path", file=sys.stderr)
                sys.exit(2)
            next_arg = args[i + 1]
            if next_arg.startswith("--"):
                print(f"Error: --with requires a path, got flag: {next_arg}",
                      file=sys.stderr)
                sys.exit(2)
            targets.append(next_arg)
            i += 2  # consume both --with and the path
        else:
            remaining.append(args[i])
            i += 1
    return remaining, targets
```

**Extraction order in `main()` dynamic skill dispatch:**

```
Input: devkit architect ~/foo "args" --with ~/bar --detach -- --fast

1. extract_with_targets(skill_args)
   -> remaining = ["args", "--detach", "--", "--fast"]
   -> with_targets = ["~/bar"]

2. Extract --detach from remaining
   -> remaining = ["args", "--", "--fast"]
   -> detach = True

3. split_skill_args(remaining)
   -> pre_sep = ["args"]
   -> post_sep = ["--fast"]

4. validate_args(pre_sep)
   -> passes (no --prefix in pre_sep args)

5. Validate each with_target via validate_target()
   -> all must pass same checks as primary target
```

**`cmd_shell` routing in `main()`:** Currently `main()` calls `cmd_shell(rest[0], config)`,
discarding `rest[1:]` which would contain `--with` arguments. Updated routing passes the
full `rest` list: `cmd_shell(rest, config)`. The `cmd_shell()` function extracts the
primary target from `rest[0]` and calls `extract_with_targets(rest[1:])` for secondary
targets.

**Environment variables set for multi-target sessions:**

| Variable | Value | Notes |
|----------|-------|-------|
| `DEVKIT_PROJECT_DIR` | Primary project's artifact dir | Existing, unchanged |
| `DEVKIT_SCRIPTS` | `~/.claude-devkit/scripts` | Existing, unchanged |
| `CLAUDE_DEVKIT` | Devkit source repo path | Existing, unchanged |
| `DEVKIT_TARGET_COUNT` | `N` (number of targets) | **Always set, even for single-target (value: 1)** |
| `DEVKIT_TARGET_0_DIR` | Primary project's artifact dir | Same as DEVKIT_PROJECT_DIR |
| `DEVKIT_TARGET_0_PATH` | Primary project's repo path | Source code location |
| `DEVKIT_TARGET_0_ID` | Primary project's project-id | For reference in plans |
| `DEVKIT_TARGET_0_NAME` | Primary project's basename | Human-readable name |
| `DEVKIT_TARGET_1_DIR` | Secondary project's artifact dir | Only when --with is used |
| `DEVKIT_TARGET_1_PATH` | Secondary project's repo path | Only when --with is used |
| `DEVKIT_TARGET_1_ID` | Secondary project's project-id | Only when --with is used |
| `DEVKIT_TARGET_1_NAME` | Secondary project's basename | Only when --with is used |

**Single-target consistency:** `DEVKIT_TARGET_COUNT=1` and `DEVKIT_TARGET_0_*` vars are
always set, even for single-target invocations (both `devkit shell` and `devkit <skill>`).
This provides a consistent interface for skills: they can always read `DEVKIT_TARGET_0_PATH`
instead of conditionally checking whether indexed vars exist. `DEVKIT_TARGET_COUNT > 1`
indicates a multi-target session.

**CWD:** Set to the first (primary) target's repo path, same as single-target `devkit shell`.

**State tracking:** Each target's `state.json` is updated with the shell invocation
(same as existing behavior for single-target shell, applied to all targets).

### Component 5: Multi-Target `devkit architect`

Extended syntax for cross-repo planning:

```bash
# Single target (existing, unchanged)
devkit architect ~/projects/lightwell-intake-automation "integrate with cve-api"

# Multi-target (new)
devkit architect ~/projects/lightwell-intake-automation "integrate with cve-api" \
  --with ~/projects/cve-api
```

**Behavior:**

1. Validate all targets (each must pass `validate_target()` and be devkit-initialized).
2. Set multi-target env vars (same as `devkit shell --with`, using
   `extract_with_targets()` as specified in Component 4).
3. Invoke `claude --print` with CWD set to the primary target.
4. The `/architect` skill detects `DEVKIT_TARGET_COUNT > 1` in Step 0 (context discovery)
   and:
   a. Reads CLAUDE.md from all targets (using `DEVKIT_TARGET_N_PATH`).
   b. Runs codebase-scanner on all targets.
   c. Instructs the architect agent to produce a plan with `targets:` frontmatter
      listing all targets.
   d. Work groups in the Task Breakdown must specify which target repo each group
      operates on.
5. After the plan is approved (Step 4 PASS path), the skill writes plan refs by calling
   `devkit plan sync "$DEVKIT_TARGET_0_PATH"` via Bash (see Component 7 for details).

**Plan storage:** The plan lives in the primary target's central storage only. Secondary
targets get ref files. This is a firm invariant -- plans are never duplicated.

### Component 6: `devkit://` URI Scheme

Plans can reference artifacts in other projects using a URI scheme:

```
devkit://<project-id>/plans/<filename>
devkit://<project-id>/plans/archive/<feature>/<filename>
```

**Resolution:** The CLI resolves `devkit://` URIs to absolute paths by looking up the
project-id in the registry and constructing the full path:

```
devkit://cve-api-f25db5e61a87/plans/add-v2-endpoint.md
  -> ~/.claude-devkit/projects/cve-api-f25db5e61a87/plans/add-v2-endpoint.md
```

**Usage in plans:**

```markdown
## Dependencies

This plan depends on the API changes described in:
- [cve-api v2 endpoint plan](devkit://cve-api-f25db5e61a87/plans/add-v2-endpoint.md)
```

**Implementation:** `devkit plan resolve <uri>` prints the absolute path. Skills that need
to follow cross-repo references invoke this command via Bash:

```bash
# In a skill (SKILL.md), via Bash tool:
resolved_path=$(devkit plan resolve "devkit://cve-api-f25db5e61a87/plans/add-v2-endpoint.md")
```

Skills cannot call `resolve_devkit_uri()` as a Python function -- they execute inside
Claude Code sessions, not as subprocesses of `devkit_cli.py`. The `devkit plan resolve`
CLI command is the only interface available to skills.

### Component 7: `/architect` Skill Changes (Minimal)

The `/architect` skill receives minimal changes to support cross-repo context:

**Step 0 (Context Discovery) addition:**

```markdown
**Cross-repo context (when DEVKIT_TARGET_COUNT > 1):**
For each target N (0 to DEVKIT_TARGET_COUNT-1):
1. Read CLAUDE.md from $DEVKIT_TARGET_N_PATH/CLAUDE.md
2. Run codebase-scanner on $DEVKIT_TARGET_N_PATH (if scanner is available)
3. Note the project name ($DEVKIT_TARGET_N_NAME) and ID ($DEVKIT_TARGET_N_ID)

Pass all discovered context to the architect agent. Instruct the agent to:
- Include a `targets:` frontmatter field listing all targets with roles
- Annotate each Work Group with `target: <project-name>` to indicate which
  repo it operates on
- Use `devkit://` URIs when referencing artifacts in other targets
```

**Step 1 (Architect Agent) context injection:**

The prompt to the architect agent includes a preamble like:

```
This plan spans multiple repositories:
- PRIMARY: lightwell-intake-automation (Python, ~/projects/lightwell-intake-automation)
  Project ID: lightwell-intake-automation-c627b987f6da
- SECONDARY: cve-api (Go, ~/projects/cve-api)
  Project ID: cve-api-f25db5e61a87

Each Work Group in the Task Breakdown must specify which repository it targets.
Use the `target:` annotation in Work Group headers.
```

**Step 4 (Approval Gate, PASS path) -- plan-ref creation mechanism:**

The `/architect` skill calls `devkit plan sync` via Bash to create plan-ref files. This
mechanism was chosen over alternatives because:

- The skill runs inside a Claude Code session (LLM + Bash/Read/Write tools). It cannot call
  Python functions in `devkit_cli.py` directly.
- Having the CLI write refs post-completion (option B) would require the CLI to know which
  plan file was created, which is opaque (the skill writes the file, the CLI never sees the
  filename).
- `devkit plan sync` is idempotent, handles validation and permissions, and does not require
  the skill to know the ref JSON schema.

The Step 4 PASS path adds:

```markdown
**If PASS and DEVKIT_TARGET_COUNT > 1:**
Tool: Bash
```bash
devkit plan sync "$DEVKIT_TARGET_0_PATH"
```
This reads the plan's `targets:` frontmatter and writes ref files to all involved
project directories. If any secondary target is unreachable, the sync logs a warning
but does not alter the verdict.
```

Ref creation failure (e.g., wrong permissions on secondary target's central storage) is
non-blocking. The plan is already committed. Refs can be rebuilt later via
`devkit plan sync`.

**No changes to Steps 2-3, 5.** Red team, librarian, feasibility, revision loop, and
auto-commit operate on the plan content -- they do not need awareness of the multi-target
env vars.

### Component 8: `/ship` Awareness (Minimal, Read-Only)

`/ship` receives minimal changes to support consuming cross-repo plans:

**Step 1 (Read Plan) -- target validation:**

When the plan has `targets:` frontmatter, `/ship` validates that the current `$CWD`
matches one of the listed targets. The matching algorithm:

1. Parse frontmatter via `parse_plan_frontmatter()` (called as a Python one-liner via Bash,
   since `/ship` runs inside Claude Code and cannot call the function directly).
2. For each target in `targets:`, resolve the `path` value: expand `~` and resolve to an
   absolute path.
3. Compare each resolved target path against `$CWD` (also resolved via `realpath`).
4. If CWD matches a target with `role: primary`, proceed normally.
5. If CWD matches a target with `role: secondary`, log a warning:
   "This plan's primary target is <primary-name>. Running against secondary target
   <current-name>. Only work groups targeting this repo will be executed."
6. If CWD does not match any target, log an error and BLOCK:
   "Current directory does not match any target in plan frontmatter."

**Step 2b (Work Group dispatch) -- target filtering:**

When dispatching work groups from a cross-repo plan, `/ship` filters by the `**Target:**`
annotation in work group headers:

**Matching algorithm:**
- The `**Target:** <name>` value is compared against `DEVKIT_TARGET_N_NAME` values
  (the basename of each project directory, e.g., `cve-api`).
- Comparison is **case-insensitive** (e.g., `**Target:** CVE-API` matches
  `DEVKIT_TARGET_0_NAME=cve-api`).
- The current project's name is determined by matching `$CWD` against
  `DEVKIT_TARGET_N_PATH` values (same resolution as Step 1).

**Behavior for edge cases:**
- **Unannotated work group** (no `**Target:**` line) in a multi-target plan: Treated as
  primary-target-only. `/ship` logs a warning: "Work group N has no target annotation;
  treating as primary target only."
- **Mismatched target name** (`**Target:** cve-apii` -- typo): The work group does not
  match any known target. It is skipped with a warning: "Work group N targets unknown
  project 'cve-apii'; skipping."
- **No matching work groups**: If no work groups match the current project, `/ship` logs:
  "No work groups target this project (<name>). Nothing to execute." and exits with
  PASS (no work to do is not an error -- the user may be running `/ship` against
  secondary targets in sequence).

**Cross-repo URI resolution:**

When `/ship` encounters a `devkit://` URI in a plan (e.g., in a Dependencies section),
it resolves it via Bash:

```bash
resolved_path=$(devkit plan resolve "devkit://<project-id>/plans/<file>")
```

This is the only way skills can resolve `devkit://` URIs -- they cannot call the Python
`resolve_devkit_uri()` function directly.

**Archive step -- ref cleanup:**

When `/ship` archives a cross-repo plan (moving it to `plans/archive/`), it also cleans up
plan refs by calling `devkit plan archive` via Bash:

```bash
devkit plan archive "$DEVKIT_TARGET_0_PATH" "<plan-name>"
```

This removes ref files from all involved projects. If ref cleanup fails (e.g., secondary
target unreachable), the archive proceeds with a warning.

**No structural changes to /ship.** The filtering is advisory -- it helps the coder
agents focus on the right files, but does not change the worktree isolation or
validation patterns.

## Interfaces / Schema Changes

### state.json (No Change)

The per-project `state.json` schema is unchanged. Cross-repo metadata lives in
`plan-refs/` JSON files, not in state.

### registry.json (No Change)

The registry schema is unchanged. Plan refs are per-project, not global. The registry
remains a flat list of projects with no relationship modeling.

### New: `plan-refs/*.ref.json` Schema

```json
{
  "schema_version": "1.0.0",
  "plan_name": "<string, max 255>",
  "plan_file": "<string, max 255>",
  "primary_project_id": "<string, max 128>",
  "primary_project_path": "<string, max 4096, absolute, no tildes>",
  "primary_plan_path": "<string, max 4096, absolute, no tildes>",
  "role": "<'primary' | 'secondary'>",
  "all_targets": [
    {
      "project_id": "<string, max 128>",
      "project_path": "<string, max 4096, absolute, no tildes>",
      "role": "<'primary' | 'secondary'>"
    }
  ],
  "created_at": "<ISO 8601 timestamp>",
  "created_by": "<string, max 64>"
}
```

Max array length for `all_targets`: 10 (matching the max-targets-per-plan limit).

### New: devkit-defaults.json Addition

```json
{
  "max_cross_repo_targets": 10
}
```

The Python code reads this via `config.get("max_cross_repo_targets", 10)` -- no separate
`MAX_CROSS_REPO_TARGETS` constant. This is consistent with how `max_state_file_bytes` and
other config values are accessed (config value with hardcoded fallback default).

### New: Plan Frontmatter Fields

```yaml
targets:
  - path: ~/projects/lightwell-intake-automation
    role: primary
  - path: ~/projects/cve-api
    role: secondary
```

### New: Work Group Target Annotation

```markdown
### Work Group 1: CVE API endpoint changes
**Target:** cve-api
- src/api/v2/handler.go (create)
- src/api/v2/handler_test.go (create)

### Work Group 2: Intake automation consumer
**Target:** lightwell-intake-automation
- src/clients/cve_api.py (create)
- tests/test_cve_api_client.py (create)
```

### CLI Interface Changes

```
# New subcommand
devkit plan list <target>
devkit plan show <target> <plan-name>
devkit plan validate <target> <plan-file>
devkit plan sync <target>
devkit plan resolve <devkit-uri>
devkit plan archive <target> <plan-name>

# Extended existing commands
devkit shell <target> --with <target2> [--with <target3> ...]
devkit architect <target> <args> --with <target2> [--with <target3> ...]
devkit status <target>     # Now shows cross-repo plan refs
```

### Environment Variable Additions

| Variable | Set By | Used By | Single-Target |
|----------|--------|---------|---------------|
| `DEVKIT_TARGET_COUNT` | `devkit_cli.py` | `/architect` Step 0, skills checking for multi-target | Always set (value: 1) |
| `DEVKIT_TARGET_N_DIR` | `devkit_cli.py` | Skills needing cross-repo artifact access | `DEVKIT_TARGET_0_DIR` always set |
| `DEVKIT_TARGET_N_PATH` | `devkit_cli.py` | Skills needing cross-repo source access | `DEVKIT_TARGET_0_PATH` always set |
| `DEVKIT_TARGET_N_ID` | `devkit_cli.py` | Skills referencing project IDs | `DEVKIT_TARGET_0_ID` always set |
| `DEVKIT_TARGET_N_NAME` | `devkit_cli.py` | Skills displaying project names | `DEVKIT_TARGET_0_NAME` always set |

## Data Migration

No migration required. This is a purely additive change:

- Existing plans without `targets:` frontmatter continue to work unchanged.
- Existing `state.json` files are not modified.
- Existing registry entries are not modified.
- The new `plan-refs/` directory is created on-demand when the first cross-repo plan
  is created.

## Security Requirements

### Assets

- **Plan files:** Confidentiality: internal | Integrity: high | Availability: medium.
  Plans may contain architecture details, API designs, and security requirements that
  should not leak outside the user's machine.
- **Plan ref files:** Confidentiality: internal | Integrity: medium | Availability: low.
  Informational-only cross-references. Corruption is recoverable via `devkit plan sync`.
- **Project paths (in env vars and ref files):** Confidentiality: internal | Integrity: high.
  Paths reveal directory structure. Tampered paths could misdirect file operations.
- **devkit:// URIs:** Confidentiality: internal | Integrity: high. A tampered URI
  could resolve to an unintended file path.

### Trust Boundaries

- **TB-1: CLI argument parsing -> file system operations.** User-supplied target paths
  are untrusted until they pass `validate_target()`. The `--with` arguments must pass
  the same validation as the primary target.
- **TB-2: Plan frontmatter -> file operations.** The `targets:` field in plan YAML is
  semi-trusted (written by the architect agent, which is trusted, but the plan file
  itself could be hand-edited or tampered). All paths from frontmatter must be
  re-validated via `validate_target()` before use.
- **TB-3: devkit:// URI -> file path resolution.** URIs are untrusted input. The
  project-id component must match `^[a-zA-Z0-9._-]+-[0-9a-f]{12}$` (existing project
  ID format). The path component must not contain `..` or absolute path prefixes.
- **TB-4: plan-refs/*.ref.json -> display/resolution.** Ref files are written by the
  CLI (trusted at write time) but could be tampered on disk. All fields must be
  validated on read: project-id format, path length limits, role enum values.
- **TB-5: Environment variables -> skill execution.** Skills receive paths via env
  vars. A compromised skill could read files from secondary targets. This is accepted
  risk -- skills already have full filesystem access within their model's tool
  permissions. The env vars do not grant additional access; they provide convenient
  path resolution.

### STRIDE Analysis

| Threat | Vector | Mitigation | Residual Risk |
|--------|--------|------------|---------------|
| **Spoofing** | Attacker crafts a plan ref pointing to a fake project-id, tricking `devkit status` into showing misleading information | Ref files contain `project_path` which is validated against the filesystem on display. Invalid/missing paths shown as `[STALE]` (existing pattern from registry). Project-ids in refs are validated against the ID format regex. | Low -- ref files are informational only; no security decision depends on them. |
| **Tampering** | Attacker modifies plan frontmatter to add a target they control, gaining visibility into the plan | Plans are local files under `~/.claude-devkit/` (0o700 dir, 0o600 files). Tampering requires local filesystem access, which means the attacker already has full access. All paths from frontmatter are re-validated via `validate_target()` before any operation. | Low -- local-only threat model; filesystem permissions are the primary control. |
| **Tampering** | Plan file received from an external source (e.g., colleague shares a plan file via chat). The `targets:` paths would be attacker-controlled. | All paths from frontmatter are re-validated via `validate_target()` before any operation. `validate_target()` checks `allowed_roots`, rejects symlinks, and requires devkit initialization. Externally-sourced paths that point outside `allowed_roots` are rejected. | Low -- `validate_target()` is the same trust boundary used for all user-supplied paths. |
| **Tampering** | `devkit://` URI with path traversal (`devkit://proj-id/../../../etc/passwd`) | URI path component is validated: no `..` segments, no absolute paths, must start with `plans/`. The resolved path is checked to be under `~/.claude-devkit/projects/<id>/`. | Low -- defense-in-depth with both URI validation and resolved-path containment check. |
| **Tampering** | Modified ref file: `primary_plan_path` changed to point to a different plan or arbitrary file | Ref files are informational only -- no security decision depends on them. On read, `primary_plan_path` is validated: must be under `~/.claude-devkit/projects/<valid-id>/`, no `..` segments, file must exist. If validation fails, the ref is shown as `[STALE]` and not followed. | Low -- informational-only defense applies; validation prevents reading arbitrary files. |
| **Repudiation** | User claims they did not create a cross-repo plan | Plan ref files include `created_at` timestamp and `created_by` field. JSONL audit logging (existing) captures the architect invocation. | Low -- audit trail exists via existing mechanisms. |
| **Information Disclosure** | Env vars expose project paths to all skills in the session | Skills already have filesystem access within tool permissions. Env vars expose paths that are discoverable via `ls` or `find`. No new information is disclosed beyond what is already accessible. | Low -- accepted; no escalation beyond existing access model. |
| **Information Disclosure** | Codebase-scanner output from multiple targets combined in architect agent context | When `/architect` runs `codebase-scanner` on multiple targets (Step 0), symbol indexes from all projects are combined in the LLM prompt. If one project is more sensitive than another, the scanner output crosses a sensitivity boundary. | Low -- accepted. The user explicitly initiated the multi-target session via `--with`. The scanner output does not persist beyond the session context window. |
| **Denial of Service** | Attacker creates thousands of plan-refs to slow `devkit status` | Max 10 targets per plan (validated). Max ref file size validated on read (same pattern as state.json max size check). `plan-refs/` directory listing is bounded by plan count. | Low -- practical limits enforced. |
| **Elevation of Privilege** | `--with` target bypasses `allowed_roots` validation | Every `--with` target passes through `validate_target()` with the same checks as the primary target: non-symlink, real git repo, under allowed_roots. No special case, no bypass path. | Low -- same validation as existing targets. |

### Security Controls

- **Input Validation:** All target paths (primary, `--with`, frontmatter `targets:`,
  `devkit://` URIs) pass through `validate_target()` or equivalent format validation
  before any filesystem operation.
- **Path Containment:** `devkit://` URI resolution validates that the resolved path is
  under `~/.claude-devkit/projects/<valid-project-id>/`. No path traversal possible.
  `cmd_path` subpath also validates containment (see Rollout Plan step 8).
- **File Permissions:** `plan-refs/` directory created with 0o700. Ref files written
  with 0o600. Consistent with existing `plans/` permissions.
- **Audit Logging:** Cross-repo plan creation is logged via existing JSONL audit event
  emission in `/architect`. No additional audit logging needed.
- **Rate Limiting:** Max 10 targets per plan. Read from config via
  `config.get("max_cross_repo_targets", 10)`.
- **Secrets Management:** No new secrets introduced. No credentials in plan refs.
- **Atomic Parsing:** `parse_plan_frontmatter()` returns atomic results -- all targets
  or no targets, never a partial list. This prevents a cross-repo plan from being
  silently treated as single-project due to a formatting error.

### Failure Modes

- **If a secondary target path becomes invalid (project moved/deleted):** `devkit status`
  shows the ref with `[STALE]` marker. `devkit plan sync` can rebuild refs from the
  plan's frontmatter. No workflow is blocked.
- **If plan-refs/ directory is corrupted or deleted:** Single-project behavior is
  unaffected. Cross-repo visibility is lost until `devkit plan sync` rebuilds refs.
  Plans themselves are never stored in `plan-refs/`.
- **If DEVKIT_TARGET_COUNT env var is missing:** Skills fall back to single-project
  behavior (existing default). Cross-repo context is not injected. No error, no crash.
- **If devkit:// URI resolution fails (project not found):** The resolution function
  returns an error message. Skills that follow cross-repo references should treat
  unresolvable URIs as informational warnings, not blocking errors.
- **If `parse_plan_frontmatter()` encounters a malformed line:** The entire parse fails
  atomically. The function returns `({}, "error description")` with no partial target
  list. The caller (e.g., `validate_plan_targets()`, `devkit plan list`) handles this
  by reporting the parse error and treating the plan as a single-project plan (no
  `targets:` extracted). This is the safe default -- a plan with unparseable frontmatter
  is never silently treated as cross-repo with a subset of its intended targets.

## Rollout Plan

### Phase 1: Core Infrastructure (devkit_cli.py)

1. Add `parse_plan_frontmatter()` function (new YAML-subset parser, ~50-80 lines,
   specification in Assumption 5).
2. Add `validate_plan_targets()` function.
3. Add `resolve_devkit_uri()` function with path containment check.
4. Add `write_plan_refs()` function.
5. Add `read_plan_refs()` function.
6. Add `extract_with_targets()` function (extraction algorithm in Component 4).
7. Add multi-target env var propagation to `cmd_run_skill()` and `cmd_shell()`.
   Update `main()` routing for `shell` command to pass full `rest` list to
   `cmd_shell()` (currently passes only `rest[0]`, discarding `--with` arguments).
8. Backfill path traversal protection on `cmd_path()`: reject `..` segments in subpath,
   validate resolved path is under project directory. This matches the security
   properties of the new `resolve_devkit_uri()`.
9. Add `cmd_plan()` subcommand with `list`, `show`, `validate`, `sync`, `resolve`,
   `archive` actions.
10. Update `KNOWN_COMMANDS` tuple (add `plan`).
11. Update `print_help()`.
12. Bump `VERSION` to `0.4.0`.

### Phase 2: `/architect` Skill Update

13. Add cross-repo context discovery to Step 0.
14. Add multi-target preamble to Step 1 architect agent prompt.
15. Add plan-ref creation via `devkit plan sync` Bash call in Step 4 (approval gate,
    PASS path). The skill calls `devkit plan sync "$DEVKIT_TARGET_0_PATH"` via Bash.
16. Bump `/architect` version to `3.5.0`.

### Phase 3: `/ship` Awareness

17. Add target validation to Step 1 (read plan): CWD matching against frontmatter targets.
18. Add work group filtering by target to Step 2b with specified matching algorithm
    (case-insensitive basename match against `DEVKIT_TARGET_N_NAME`).
19. Add cross-repo ref cleanup to archive step via `devkit plan archive` Bash call.
20. Bump `/ship` version to `3.9.0`.

### Phase 4: Documentation and Tests

21. Update CLAUDE.md (skill registry versions, new CLI commands, env vars, architecture).
22. Add integration tests (29 new tests, numbered 120-148).
23. Run full test suite to verify no regressions.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Plan frontmatter parsing fails on complex YAML | Medium | Low | Bespoke YAML-subset parser supports only the documented subset (Assumption 5). Parser fails atomically on unsupported syntax. Validate against known schema. |
| Env var explosion for many targets (10 x 4 = 40 vars) | Low | Low | Cap at 10 targets. Env vars are set per-session, not persisted. |
| Users expect `/ship` to execute across repos automatically | Medium | Medium | Document clearly: `/ship` runs against one project at a time. Cross-repo plans document sequencing; execution is per-project. |
| Plan ref files become stale after project moves | Medium | Low | `devkit plan sync` rebuilds refs. `devkit plan archive` cleans up refs. Stale refs shown with `[STALE]` marker, matching existing registry pattern. |
| `/architect` produces plans without `targets:` frontmatter in multi-target mode | Low | Medium | Step 0 explicitly instructs the agent to include `targets:` and validates the output. Fallback: `devkit plan validate` detects missing frontmatter. |
| URI resolution used for file reads outside `~/.claude-devkit/` | Low | High | Path containment check: resolved path must be under `~/.claude-devkit/projects/<valid-id>/`. `..` segments rejected. `cmd_path` also backfilled with traversal protection. |

## Test Plan

**Test command:** `bash scripts/test-integration.sh`

### New Tests (29 tests, numbered 120-148)

Tests follow the existing `run_test()` harness pattern. All tests use the test fixtures
created in the setup section (temporary git repos under `/tmp/`).

**Note on numbering:** The existing test suite has 118 `run_test` calls numbered 1-119
(one number is skipped within the existing range). New tests start at 120, which is
contiguous with the last existing test (119).

#### Plan Frontmatter Parser Tests (120-125)

**Test 120:** `parse_plan_frontmatter extracts targets from valid frontmatter`
- Create a plan file with `targets:` frontmatter (2 targets, primary + secondary).
- Call `parse_plan_frontmatter()` via Python one-liner.
- Assert: returns dict with `targets` list of 2 items, correct `path` and `role` values.

**Test 121:** `parse_plan_frontmatter handles plan without targets (single-project)`
- Create a plan file with status-only frontmatter (no `targets:`).
- Call `parse_plan_frontmatter()`.
- Assert: returns dict with `status` key, no `targets` key, no error.

**Test 122:** `parse_plan_frontmatter rejects more than 10 targets`
- Create a plan file with 11 targets in frontmatter.
- Call `validate_plan_targets()` on the parsed result.
- Assert: returns `(False, "exceeds maximum ...")`, exit code 1.

**Test 123:** `parse_plan_frontmatter handles mixed flat keys and list keys`
- Create a plan file with `status: DRAFT`, `targets:` list, and `author: test` after
  the list (flat key following a list).
- Call `parse_plan_frontmatter()`.
- Assert: returns dict with all three keys correctly parsed. The `author` key is not
  swallowed by the list parser.

**Test 124:** `parse_plan_frontmatter fails atomically on malformed indentation`
- Create a plan file where the second target has wrong indentation (e.g., missing
  indent on `role:`).
- Call `parse_plan_frontmatter()`.
- Assert: returns `({}, "unparseable line...")`. No partial target list.

**Test 125:** `parse_plan_frontmatter fails atomically on partial targets`
- Create a plan file where the first target parses correctly but the second has
  invalid syntax (e.g., `- : bad`).
- Call `parse_plan_frontmatter()`.
- Assert: returns `({}, "error...")`. Does NOT return a list with only the first target.

#### devkit:// URI Tests (126-128)

**Test 126:** `resolve_devkit_uri resolves valid URI to absolute path`
- Call `resolve_devkit_uri("devkit://test-project-abc123456789/plans/test.md")`.
- Assert: returns `~/.claude-devkit/projects/test-project-abc123456789/plans/test.md`
  (expanded to absolute).

**Test 127:** `resolve_devkit_uri rejects path traversal`
- Call `resolve_devkit_uri("devkit://test-project-abc123456789/../../../etc/passwd")`.
- Assert: returns error, "path traversal rejected".

**Test 128:** `resolve_devkit_uri rejects invalid project-id format`
- Call `resolve_devkit_uri("devkit://../../bad/plans/test.md")`.
- Assert: returns error, "invalid project ID".

#### Plan Ref Tests (129-131)

**Test 129:** `write_plan_refs creates ref files in all target project dirs`
- Create two test project dirs under `~/.claude-devkit/projects/`.
- Call `write_plan_refs()` with two targets.
- Assert: ref files exist in both project dirs' `plan-refs/`.

**Test 130:** `plan-refs/ directory has 0o700 permissions`
- After test 129, check permissions on created `plan-refs/` dirs.
- Assert: directory mode is 0o700.

**Test 131:** `ref files have 0o600 permissions and store absolute paths`
- After test 129, check permissions on created ref JSON files.
- Assert: file mode is 0o600.
- Assert: `primary_plan_path` and `project_path` fields contain no `~` character.

#### Multi-Target Shell Tests (132-134)

**Test 132:** `cmd_shell with --with sets DEVKIT_TARGET_COUNT and indexed env vars`
- Create two test git repos under `/tmp/`.
- Run `devkit init` on both.
- Invoke `cmd_shell()` code path with `--with` (functional test via env var inspection,
  using a mock that captures env setup before `execvp`).
- Assert: `DEVKIT_TARGET_COUNT=2`, `DEVKIT_TARGET_0_PATH` and `DEVKIT_TARGET_1_PATH`
  are set correctly.

**Test 133:** `cmd_shell with --with validates secondary targets`
- Call `cmd_shell()` with `--with /tmp/nonexistent`.
- Assert: exits 1 with validation error.

**Test 134:** `cmd_shell with --with rejects symlinked secondary targets`
- Create a symlink to a test git repo.
- Call `cmd_shell()` with `--with <symlink-path>`.
- Assert: exits 1 with "symlink" error.

#### Multi-Target Skill Dispatch Tests (135-137)

**Test 135:** `extract_with_targets extracts --with pairs correctly`
- Call `extract_with_targets(["arg1", "--with", "/tmp/a", "--detach", "--with", "/tmp/b"])`.
- Assert: remaining = `["arg1", "--detach"]`, targets = `["/tmp/a", "/tmp/b"]`.

**Test 136:** `extract_with_targets exits 2 on missing path after --with`
- Call `extract_with_targets(["arg1", "--with"])`.
- Assert: exits 2 with "requires a target path" error.

**Test 137:** `cmd_run_skill with --with and --detach extracts both correctly`
- Invoke the dynamic skill dispatch code path with args containing both `--with ~/bar`
  and `--detach`.
- Assert: `with_targets` contains `~/bar`, `detach` is True, and remaining args are clean.

#### devkit plan Subcommand Tests (138-142)

**Test 138:** `devkit plan list shows cross-repo refs`
- Create a test project with a plan-ref JSON file in `plan-refs/`.
- Run `devkit plan list <test-project>`.
- Assert: output includes the ref'd plan name and target count.

**Test 139:** `devkit plan show displays plan details with target info`
- Create a test project with a cross-repo plan file (has `targets:` frontmatter) and
  corresponding ref file.
- Run `devkit plan show <test-project> <plan-name>`.
- Assert: output includes target paths and roles.

**Test 140:** `devkit plan validate detects missing primary target`
- Create a plan file with `targets:` where no target has `role: primary`.
- Run `devkit plan validate <test-project> <plan-file>`.
- Assert: exits 1 with "no primary target" error.

**Test 141:** `devkit plan validate detects uninitialized secondary target`
- Create a plan file with `targets:` where the secondary path is not devkit-initialized.
- Run `devkit plan validate <test-project> <plan-file>`.
- Assert: exits 1 with "not initialized" error for the secondary target.

**Test 142:** `devkit plan sync rebuilds refs and removes stale refs`
- Create a test project with two plan files: one cross-repo, one deleted (but its ref
  file still exists in `plan-refs/`).
- Run `devkit plan sync <test-project>`.
- Assert: ref files for the existing plan are correct. Stale ref file for the deleted
  plan is removed.

#### read_plan_refs Tests (143-144)

**Test 143:** `read_plan_refs returns empty list for missing plan-refs/ directory`
- Create a test project with no `plan-refs/` directory.
- Call `read_plan_refs()` on the project dir.
- Assert: returns empty list, no error.

**Test 144:** `read_plan_refs rejects oversized ref files`
- Create a ref file larger than the max size limit.
- Call `read_plan_refs()` on the project dir.
- Assert: the oversized ref file is skipped (logged as warning), other valid refs
  are returned.

#### validate_plan_targets Tests (145-146)

**Test 145:** `validate_plan_targets rejects duplicate primaries`
- Create a targets list with two entries both having `role: primary`.
- Call `validate_plan_targets()`.
- Assert: returns `(False, "multiple primary targets")`.

**Test 146:** `validate_plan_targets rejects targets list with no primary`
- Create a targets list with two entries both having `role: secondary`.
- Call `validate_plan_targets()`.
- Assert: returns `(False, "no primary target")`.

#### cmd_path Traversal Protection Test (147)

**Test 147:** `cmd_path rejects path traversal via .. segments`
- Call `cmd_path(<valid-target>, config, subpath="../../etc/passwd")`.
- Assert: exits 1 with "path traversal rejected" error.
- Assert: `cmd_path(<valid-target>, config, subpath="plans/feature.md")` succeeds.

#### devkit plan archive Test (148)

**Test 148:** `devkit plan archive removes ref files from all involved projects`
- Create two test projects with plan-ref files for the same cross-repo plan.
- Run `devkit plan archive <primary-project> <plan-name>`.
- Assert: ref files are removed from both projects' `plan-refs/` directories.
- Assert: plan file is moved to `plans/archive/<plan-name>/`.

### Skill Structural Tests (Run Within Existing Ranges)

- Verify `/architect` SKILL.md contains `DEVKIT_TARGET_COUNT` reference.
- Verify `/architect` SKILL.md version is `3.5.0`.
- Verify `/ship` SKILL.md version is `3.9.0`.
- Verify `/ship` SKILL.md contains `target:` work group annotation language.

## Acceptance Criteria

1. `devkit shell ~/projects/lightwell-intake-automation --with ~/projects/cve-api`
   opens an interactive session with `DEVKIT_TARGET_COUNT=2` and indexed env vars
   for both projects.

2. `devkit architect ~/projects/lightwell-intake-automation "integrate with cve-api" --with ~/projects/cve-api`
   produces a plan with `targets:` frontmatter and work groups annotated with
   `target:` per repo.

3. After a cross-repo plan is created, `devkit status ~/projects/cve-api` shows
   the plan in its cross-repo references section.

4. `devkit plan list ~/projects/lightwell-intake-automation` shows both local plans
   and cross-repo plan refs with target counts.

5. `devkit plan resolve devkit://cve-api-f25db5e61a87/plans/add-v2-endpoint.md`
   prints the absolute path to the plan file.

6. Single-target workflows are completely unaffected. No behavioral change when
   `--with` is not specified, when plans lack `targets:` frontmatter, or when
   `DEVKIT_TARGET_COUNT` is absent. (Note: `DEVKIT_TARGET_COUNT=1` and
   `DEVKIT_TARGET_0_*` vars are now always set for single-target invocations,
   but this is additive -- no existing skill reads these vars.)

7. All `--with` targets pass the same validation as primary targets: non-symlink,
   real git repo, under `allowed_roots`, devkit-initialized.

8. `bash scripts/test-integration.sh` passes with all 147+ tests (118 existing +
   29 new).

9. Path traversal via `devkit://` URIs is rejected. Path traversal via `cmd_path`
   subpath is also rejected (backfilled).

10. Max 10 targets enforced; 11th target produces a clear error.

11. `devkit plan archive` removes ref files from all involved projects.

## Task Breakdown

### Shared Dependencies

- `scripts/devkit_cli.py` lines 46-77 (modify -- add `PLAN_REF_SCHEMA_VERSION = "1.0.0"`,
  `PROJECT_ID_RE` compiled regex constants. Note: `max_cross_repo_targets` is read from
  config via `config.get()`, not as a constant.)
- `configs/devkit-defaults.json` (modify -- add `"max_cross_repo_targets": 10`)

### Work Group 1: Core CLI Infrastructure

All changes to `scripts/devkit_cli.py` core functions and new `devkit plan` subcommand.

- `scripts/devkit_cli.py` (modify -- add `parse_plan_frontmatter()` YAML-subset parser,
  specification in Assumption 5)
- `scripts/devkit_cli.py` (modify -- add `validate_plan_targets()`, `resolve_devkit_uri()`,
  `write_plan_refs()`, `read_plan_refs()`, `extract_with_targets()` functions)
- `scripts/devkit_cli.py` (modify -- add `cmd_plan()` function with list/show/validate/sync/
  resolve/archive actions)
- `scripts/devkit_cli.py` (modify -- add `--with` extraction via `extract_with_targets()` to
  `cmd_shell()` for multi-target env var setup)
- `scripts/devkit_cli.py` (modify -- add `--with` extraction via `extract_with_targets()` to
  dynamic skill dispatch in `main()` for multi-target env var setup)
- `scripts/devkit_cli.py` (modify -- update `main()` to route `plan` to `cmd_plan()`, add
  `plan` to `KNOWN_COMMANDS`, pass full `rest` list to `cmd_shell()`)
- `scripts/devkit_cli.py` (modify -- backfill `cmd_path()` with path traversal protection:
  reject `..` segments in subpath, validate resolved path under project directory)
- `scripts/devkit_cli.py` (modify -- update `print_help()` with new commands, `--with` flag,
  and `plan` subcommand)
- `scripts/devkit_cli.py` (modify -- update `VERSION` to `0.4.0`)

### Work Group 2: Skill Updates

Changes to `/architect` and `/ship` SKILL.md files for cross-repo awareness.

- `skills/architect/SKILL.md` (modify -- Step 0 cross-repo context discovery, Step 1
  multi-target preamble, Step 4 plan-ref creation via `devkit plan sync` Bash call,
  version bump to 3.5.0)
- `skills/ship/SKILL.md` (modify -- Step 1 target validation for cross-repo plans with
  CWD matching, Step 2b work group filtering by target with case-insensitive basename
  matching and unannotated/mismatched behavior, archive step ref cleanup via
  `devkit plan archive` Bash call, version bump to 3.9.0)

### Work Group 3: Tests and Documentation

Integration tests and documentation updates.

- `scripts/test-integration.sh` (modify -- add 29 new tests numbered 120-148, update test
  count in header comment to 147)
- `CLAUDE.md` (modify -- update skill registry versions, add `devkit plan` to CLI reference,
  add `--with` to shell/architect docs, add cross-repo plan section, update env var table
  with `DEVKIT_TARGET_*` and single-target note, add `plan-refs/` to directory structure,
  update test count, add `cmd_path` traversal protection to CLI docs)

## Work Groups

### Shared Dependencies
- `scripts/devkit_cli.py` lines 46-77 (modify -- add constants: `PLAN_REF_SCHEMA_VERSION = "1.0.0"`, `PROJECT_ID_RE` compiled regex)
- `configs/devkit-defaults.json` (modify -- add `"max_cross_repo_targets": 10`)

### Work Group 1: Core CLI Infrastructure
- `scripts/devkit_cli.py` (modify -- add `parse_plan_frontmatter()` YAML-subset parser)
- `scripts/devkit_cli.py` (modify -- add `validate_plan_targets()`, `resolve_devkit_uri()` functions)
- `scripts/devkit_cli.py` (modify -- add `write_plan_refs()`, `read_plan_refs()`, `extract_with_targets()` functions)
- `scripts/devkit_cli.py` (modify -- add `cmd_plan()` with list/show/validate/sync/resolve/archive)
- `scripts/devkit_cli.py` (modify -- extend `cmd_shell()` with `--with` multi-target support)
- `scripts/devkit_cli.py` (modify -- extend dynamic skill dispatch in `main()` with `--with` extraction and multi-target env var setup)
- `scripts/devkit_cli.py` (modify -- update `main()` routing: pass full `rest` to `cmd_shell()`, add `plan` to `KNOWN_COMMANDS`)
- `scripts/devkit_cli.py` (modify -- backfill `cmd_path()` with path traversal protection)
- `scripts/devkit_cli.py` (modify -- update `print_help()`, `VERSION` to `0.4.0`)

### Work Group 2: Skill Updates
- `skills/architect/SKILL.md` (modify -- Step 0 cross-repo context, Step 1 multi-target preamble, Step 4 ref creation via `devkit plan sync` Bash call, version 3.5.0)
- `skills/ship/SKILL.md` (modify -- Step 1 target validation with CWD matching, Step 2b target filtering with case-insensitive basename matching and edge case behavior, archive step ref cleanup via `devkit plan archive`, version 3.9.0)

### Work Group 3: Tests and Documentation
- `scripts/test-integration.sh` (modify -- 29 new tests 120-148, update header count to 147)
- `CLAUDE.md` (modify -- skill versions, CLI docs, env vars, directory structure, test count, cmd_path traversal note)

## Context Alignment

### CLAUDE.md Patterns Followed

- **Python stdlib only:** All changes to `devkit_cli.py` use stdlib only. No external dependencies.
  Plan frontmatter parsing uses a bespoke YAML-subset parser (Assumption 5), not PyYAML.
- **Atomic writes:** `_atomic_write_json()` reused for all plan-ref writes. No new write pattern.
- **Atomic parsing:** `parse_plan_frontmatter()` returns all-or-nothing results. No partial
  target lists on parse failure.
- **Validation tuples:** `(bool, error_msg)` pattern for `validate_plan_targets()`,
  `resolve_devkit_uri()`, and other new validation functions.
- **Zero project footprint:** Plan refs and plan files live under `~/.claude-devkit/projects/`,
  never in target project directories. The `--with` flag does not create any files in secondary
  target repos.
- **Test pattern:** New tests follow the `test-integration.sh` `run_test()` harness pattern.
  All 29 new tests are functional tests (invoke code paths and assert behavior, not code
  structure inspection).
- **Environment variable convention:** New `DEVKIT_TARGET_*` env vars follow the same naming
  convention as existing `DEVKIT_PROJECT_DIR` and `DEVKIT_SCRIPTS`. Single-target invocations
  always set `DEVKIT_TARGET_COUNT=1` and `DEVKIT_TARGET_0_*` for interface consistency.
- **Injection resistance:** `--with` arguments pass through `validate_target()` (same as primary
  targets). `extract_with_targets()` is specified with a precise algorithm (Component 4).
  `devkit://` URIs are parsed with format validation and path containment checks.
  No shell interpolation of user-supplied values.
- **Informational-only indexes:** Plan refs follow the same "informational, not authoritative"
  pattern as the registry. Loss or corruption of ref files does not break any workflow.
- **Defense-in-depth:** URI resolution validates both the URI format AND the resolved path
  location (must be under `~/.claude-devkit/projects/`), same dual-check pattern used in
  `resolve-project-dir.sh`. `cmd_path` subpath is backfilled with the same protection.
- **Config over constants:** `max_cross_repo_targets` is read from config via
  `config.get("max_cross_repo_targets", 10)`, consistent with `max_state_file_bytes` pattern.
  No separate Python constant.

### Prior Plans This Builds Upon

- **zero-project-footprint** (APPROVED) -- Established the centralized artifact storage model
  at `~/.claude-devkit/projects/<project-id>/`. This plan extends that model with `plan-refs/`
  subdirectories and cross-project URI resolution, all under the same central storage.
- **detached-skill-execution** (APPROVED) -- Established the `--detach` flag extraction pattern
  (extract before `split_skill_args()`/`validate_args()`). The `--with` flag uses a related but
  more complex extraction algorithm (`extract_with_targets()`, specified in Component 4) that
  consumes value pairs and supports multiple occurrences.
- **shared-learnings-layer** (APPROVED) -- Addresses cross-project data at the learnings level.
  This plan addresses it at the planning level. Both follow the same principle: central storage
  with project-id-based indexing, informational cross-references, no modification of target
  project directories.

### Deviations From Established Patterns

1. **New `plan-refs/` subdirectory in project artifact dirs.** This adds a new directory to the
   per-project central storage layout. It follows the same permission model (0o700 dir, 0o600
   files) and the same "informational-only" principle as the registry.

2. **`devkit://` URI scheme.** This is a new convention not present in existing plans. It is
   strictly a convenience for human-readable cross-references in plan markdown. No critical
   path depends on URI resolution -- if it fails, the plan still contains the project-id and
   can be located manually via `devkit path`.

3. **`devkit plan` as a sub-subcommand.** Existing commands are flat (`devkit init`, `devkit
   status`, etc.). The `plan` command introduces a two-level structure (`devkit plan list`,
   `devkit plan show`). This is necessary because plan operations have enough actions (6) to
   warrant grouping. The alternative (flat `devkit plan-list`, `devkit plan-show`) was
   rejected for verbosity.

4. **Skill Step 0 reads from multiple CLAUDE.md files.** Currently, `/architect` Step 0 reads
   one CLAUDE.md. With multi-target, it reads from all targets. This increases context size
   but is bounded by the target count limit (max 10). The architect agent's context window
   is already large (opus-4-6 with 1M context).

5. **`--with` extraction is NOT identical to `--detach`.** The `--detach` pattern (boolean
   filter) does not apply to `--with` (valued, repeatable). A separate `extract_with_targets()`
   function with explicit pair-consumption logic is specified in Component 4.

---

<!-- Context Metadata
discovered_at: 2026-08-21T16:15:00Z
revised_at: 2026-08-21T17:30:00Z
revision_notes: Address red team (7 major), librarian (5 required), feasibility (1 critical, 2 major) findings
claude_md_exists: true
recent_plans_consulted: add-anti-pattern-reviewer.md, detached-skill-execution.md, zero-project-footprint.md, shared-learnings-layer.md
archived_plans_consulted: zero-project-footprint, detached-skill-execution
-->
