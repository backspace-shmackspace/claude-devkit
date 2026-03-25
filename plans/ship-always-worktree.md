# Plan: Ship Skill — Always Use Worktree Isolation

## Context

The `/ship` skill (v3.2.0) currently has two implementation paths in Step 3:

1. **Single Work Group Path (No Worktrees)** — coders work directly in the main working directory
2. **Multiple Work Groups Path (With Worktrees)** — coders work in isolated git worktrees

The single work group path is the common case. It provides no isolation, meaning concurrent sessions (another `/ship` run, manual edits in another terminal, or IDE auto-saves) can collide with the implementation. Both paths diverge again in Step 5 (revision loop), creating duplicated logic.

This plan eliminates the non-isolated path entirely, making worktree isolation the default for ALL `/ship` runs.

## Goals

1. Remove the "Single Work Group Path (No Worktrees)" section from Step 3
2. Generalize the "Multiple Work Groups Path" to handle 1+ work groups (including the single-group case)
3. Remove the dual-path logic from Step 5 (revision loop) — always use worktrees for revisions
4. Bump the skill version from 3.2.0 to 3.3.0
5. Preserve all existing worktree mechanics (boundary validation, merge, cleanup)
6. Harden worktree path creation, run isolation, and merge validation (addressing review findings)

## Non-Goals

- Modifying Steps 0, 1, 2, 4, or 6 beyond what is required by the path unification and review findings
- Adding new features (e.g., worktree caching, persistent worktrees)
- Changing the coder agent prompt beyond removing non-worktree references
- Changing the model or tool selections
- Overhauling `git status` parsing (documented as known limitation; follow-up work)

## Assumptions

1. Git worktree operations are fast enough for single-file plans (the overhead of create/merge/cleanup is acceptable for the isolation benefit)
2. The `git worktree add` command succeeds reliably on all target platforms (macOS, Linux)
3. The `/tmp/` directory has sufficient space for worktree copies
4. Plans without a `## Work Groups` section will continue to be treated as a single work group containing all files from the Task Breakdown — this behavior is documented in Step 1 and explicitly specified in this plan (see Proposed Design, Step 1)
5. The pre-flight cleanup in Step 0 already handles orphaned worktrees from aborted runs

## Architectural Analysis

### Current Structure (v3.2.0)

```
Step 3 — Implementation
  ├── IF single work group → dispatch coder in main dir (no isolation)
  └── IF multiple work groups →
        3a: Shared deps (conditional)
        3b: Create worktrees
        3c: Dispatch coders to worktrees
        3d: File boundary validation
        3e: Merge worktrees
        3f: Cleanup worktrees

Step 5 — Revision loop
  ├── 5a: IF work groups → re-create worktrees, dispatch, validate, merge, cleanup
  │       IF single group → dispatch coder in main dir
  └── 5b: Re-verify
```

**Problems:**
- Two code paths = two maintenance surfaces
- Single-group path has zero isolation guarantees
- Revision loop duplicates the branching logic
- Inconsistent safety properties depending on plan structure

### Proposed Structure (v3.3.0)

```
Step 3 — Implementation (always with worktree isolation)
  3a: Shared deps (conditional — only if plan has Shared Dependencies section)
  3b: Create worktrees (1 per work group, minimum 1) — using mktemp -d
  3c: Dispatch coders to worktrees (parallel if multiple, single if one)
  3d: File boundary validation
  3e: Merge worktrees + post-merge file existence validation
  3f: Cleanup worktrees

Step 5 — Revision loop
  5a: WIP commit of current state, re-create worktrees, dispatch, validate, merge, cleanup (always)
  5b: Re-verify
```

**Benefits:**
- Single code path = single maintenance surface
- Every implementation gets structural isolation guarantees
- Revision loop has one path
- Consistent safety properties regardless of plan structure
- Secure worktree paths via `mktemp -d` (no symlink/TOCTOU risk)
- Run-scoped tracking files prevent concurrent run interference

### Trade-offs

| Factor | Benefit | Cost |
|--------|---------|------|
| **Isolation** | Every run is protected from concurrent modifications | None |
| **Consistency** | One code path to maintain and reason about | None |
| **Overhead** | N/A | ~2-5 seconds for worktree create/merge/cleanup on single-group plans (potentially 10-30 seconds for large monorepos) |
| **Complexity** | Simpler skill definition (fewer conditionals) | Slightly more git operations for simple plans |
| **Disk space** | N/A | Temporary worktree copy in /tmp (cleaned up in Step 3f) |

The overhead cost is negligible — `/ship` runs take minutes for implementation and verification. Adding 2-5 seconds of git operations is immaterial for typical repos.

## Proposed Design

### Frontmatter Change

```yaml
---
name: ship
description: Execute an approved plan using unattended implementation and validation with worktree isolation.
version: 3.3.0
model: claude-opus-4-6
---
```

### Run ID and Scoped Tracking Files

Each `/ship` invocation generates a unique `RUN_ID` at the start of the run (in Step 0) using:

```bash
RUN_ID=$(date +%Y%m%d-%H%M%S)-$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 6)
```

All temporary tracking files include the `RUN_ID` to prevent concurrent runs from interfering with each other:

| Before (v3.2.0) | After (v3.3.0) |
|------------------|-----------------|
| `.ship-worktrees.tmp` | `.ship-worktrees-${RUN_ID}.tmp` |
| `.ship-violations.tmp` | `.ship-violations-${RUN_ID}.tmp` |

**Step 0 cleanup change:** The pre-flight cleanup in Step 0 must be updated to clean up only **orphaned** tracking files, not all `.ship-worktrees-*.tmp` files indiscriminately. Specifically:
- Read each `.ship-worktrees-*.tmp` file
- For each worktree path listed, check if the worktree still exists (`git worktree list`)
- If no listed worktrees exist, the tracking file is orphaned — delete it
- If listed worktrees exist, leave the tracking file alone (another run is active)

### Step 1 — Plan Parsing (scoped_files derivation for single-group plans)

Add explicit instructions for constructing `scoped_files` when no `## Work Groups` section exists:

> **When no `## Work Groups` section exists in the plan**, treat the entire plan as a single work group. Derive the `scoped_files` list by extracting ALL files from the Task Breakdown section:
> - All files listed in the `### Files to Modify` table
> - All files listed in the `### Files to Create` table
>
> Store these as the `scoped_files` for the single implicit work group. This list is used in Step 3d (boundary validation) and Step 3e (merge).

This makes the contract between Step 1 and Steps 3b-3f unambiguous for the single-group case.

### Step 3 — Implementation (always with worktree isolation)

The entire step becomes the current "Multiple Work Groups Path" with the following modifications:

1. The conditional gate `**If plan has multiple work groups:**` is removed — the path always executes
2. Step 3c dispatches coders in parallel if multiple work groups exist, or dispatches a single coder if one work group — this is already how Task parallelism works (multiple Task calls = parallel, single Task call = sequential)
3. Worktree paths use `mktemp -d` instead of deterministic paths (Finding 1)
4. Tracking file uses run-scoped name (Finding 6)
5. Post-merge validation checks for missing scoped files (Finding 3)

**New Step 3 structure:**

```markdown
## Step 3 — Implementation (with worktree isolation)

Every implementation runs in isolated git worktrees, regardless of how many work groups
the plan defines. This ensures concurrent sessions cannot interfere with the implementation.

#### Step 3a — Shared Dependencies (conditional)

**Trigger:** Plan contains `### Shared Dependencies` section. If no Shared Dependencies
section exists, skip directly to Step 3b.

[... existing 3a content unchanged ...]

#### Step 3b — Create Worktrees

For each work group, create an isolated worktree using `mktemp -d`:

```bash
# Create worktree with secure, unique path
WORKTREE_PATH=$(mktemp -d /tmp/ship-XXXXXXXXXX)
git worktree add "$WORKTREE_PATH" -b "ship-wg${WG_NUM}-${RUN_ID}" HEAD

# Record the worktree path and its scoped files in the run-scoped tracking file
echo "${WORKTREE_PATH}|${scoped_files}" >> .ship-worktrees-${RUN_ID}.tmp
```

Using `mktemp -d` ensures:
- The directory is created with 0700 permissions (not world-readable)
- The path contains a random suffix, eliminating symlink/TOCTOU attacks
- Kernel-guaranteed uniqueness, no PID or timestamp collisions

[... remaining 3b content (error handling, recovery steps) unchanged ...]

#### Step 3c — Dispatch Coders to Worktrees

Tool: `Task`, `subagent_type=general-purpose`, `model=claude-sonnet-4-5` — **dispatch
one coder per work group (parallel if multiple, single Task call if one group)**

[... existing 3c content unchanged, already works for 1+ groups ...]

#### Step 3d — File Boundary Validation

[... existing 3d content unchanged, except update references from
`.ship-worktrees.tmp` to `.ship-worktrees-${RUN_ID}.tmp` ...]

**Known limitation:** The `awk '{print $2}'` parsing of `git status --porcelain` output
does not correctly handle renamed files (`R old -> new` captures only `old`) or file
paths containing spaces. These are pre-existing limitations carried forward from v3.2.0.
The merge step (Step 3e) serves as the primary safety boundary — it copies only scoped
files, so out-of-scope modifications in the worktree are never merged regardless of
whether boundary validation detects them. Improving the parsing is deferred to a
follow-up change.

#### Step 3e — Merge Worktrees

[... existing 3e merge logic unchanged (read tracking file, cp scoped files) ...
update references from `.ship-worktrees.tmp` to `.ship-worktrees-${RUN_ID}.tmp` ...]

**Post-merge validation (new):** After the merge loop completes, validate that all
scoped files exist in the main working directory:

```bash
# Validate that all scoped files were produced
for file in $scoped_files; do
  if [ ! -f "$MAIN_DIR/$file" ]; then
    echo "WARNING: Scoped file $file was not created by coder in worktree"
  fi
done
```

This validation emits warnings but does not block the workflow. A file may legitimately
not need creation if it already existed in the main directory before the worktree was
created (e.g., a file listed under "Files to Modify" that the coder chose not to change).
The code review in Step 4 serves as the catch for genuinely missing files.

#### Step 3f — Cleanup Worktrees

[... existing 3f content unchanged, except update references from
`.ship-worktrees.tmp` to `.ship-worktrees-${RUN_ID}.tmp` ...
delete `.ship-worktrees-${RUN_ID}.tmp` after all worktrees are removed ...]
```

**Key observation:** Steps 3b through 3f already work correctly for a single work group. The bash loops iterate over `.ship-worktrees-${RUN_ID}.tmp` which will have exactly one line for a single-group plan. The only bash script changes are:
- `mktemp -d` replaces the deterministic path format in Step 3b
- Run-scoped tracking filename replaces `.ship-worktrees.tmp` in Steps 3b-3f
- Post-merge file existence validation added to Step 3e

### Step 5 — Revision Loop

The dual-path conditional is removed. The revision loop always uses worktrees:

```markdown
## Step 5 — Revision loop (conditional)

**Trigger:** Step 4 code review verdict is `REVISION_NEEDED` (and no FAIL verdicts
from any check).

**If Step 4 all checks PASS:** skip to Step 6.

### 5a — Coder fixes (with worktree isolation)

Before re-creating worktrees, commit the current working directory state so that
worktrees created from HEAD contain the first-pass implementation code:

```bash
git add -A
git commit -m "WIP: ship v3.3.0 first-pass implementation (pre-revision)"
```

This ensures revision-loop worktrees are based on the first-pass code, not the
pre-implementation state. The coder can then read the code review feedback and
apply targeted fixes to the existing implementation rather than re-implementing
from scratch.

Then proceed with the standard worktree workflow:

- Re-create worktrees (Step 3b) — these now branch from the WIP commit containing first-pass code
- Dispatch coders to worktrees (Step 3c) with modified prompt:
  [... existing worktree revision prompt, unchanged ...]
- Validate file boundaries (Step 3d)
- Merge worktrees (Step 3e) — including post-merge validation
- Cleanup worktrees (Step 3f)

### 5b — Re-verify in parallel

[... existing 5b content unchanged ...]
```

**Removed:** The entire `**If single work group (no worktrees):**` block in Step 5a.

**Added:** WIP commit before worktree re-creation in Step 5a, mirroring the Step 3a pattern for shared dependencies. This ensures the revision worktrees contain the first-pass code.

### Step 6 — Commit Gate

One minor change: the conditional `**If shared deps were committed in Step 3a:**` for the soft reset remains as-is. This is orthogonal to worktree isolation — it only triggers when Shared Dependencies exist and were committed, which is still conditional.

The Step 5a WIP commit (if it occurred) must also be included in the soft reset. Update the squash logic to handle the case where both a Step 3a shared deps commit AND a Step 5a pre-revision commit exist:

```bash
# Soft reset to the commit before any WIP commits (shared deps and/or pre-revision)
# The number of WIP commits to squash depends on which steps executed
```

No other changes needed to Step 6.

## Interfaces/Schema Changes

### Frontmatter

| Field | Before (v3.2.0) | After (v3.3.0) |
|-------|-----------------|-----------------|
| `version` | `3.2.0` | `3.3.0` |

No other frontmatter changes.

### Inputs

No changes. `$ARGUMENTS` (plan file path) remains the sole input.

### Outputs/Artifacts

No changes. Same artifact structure:
- `./plans/[name].code-review.md`
- `./plans/[name].qa-report.md`
- `./plans/[name].test-failure.log` (on test failure)
- `./plans/archive/[name]/` (on success)

### Temporary Files

| File | Before (v3.2.0) | After (v3.3.0) |
|------|------------------|-----------------|
| Worktree tracking | `.ship-worktrees.tmp` (shared across runs) | `.ship-worktrees-${RUN_ID}.tmp` (run-scoped) |
| Boundary violations | `.ship-violations.tmp` | `.ship-violations-${RUN_ID}.tmp` (run-scoped) |

## Data Migration

N/A — This is a markdown skill definition change. No data, schema, or database changes.

## Rollout Plan

### Phase 1: Edit Source

1. [ ] Edit `/Users/imurphy/projects/claude-devkit/skills/ship/SKILL.md`
   - Bump version in frontmatter from `3.2.0` to `3.3.0`
   - Add `RUN_ID` generation in Step 0 (unique per invocation)
   - Update Step 0 pre-flight cleanup to use orphan-aware logic for `.ship-worktrees-*.tmp` files
   - Add explicit `scoped_files` derivation instructions in Step 1 for plans without `## Work Groups` section (extract ALL files from Task Breakdown: Files to Modify + Files to Create)
   - Remove the "Single Work Group Path (No Worktrees)" section from Step 3
   - Remove the `### Single Work Group Path (No Worktrees)` and `### Multiple Work Groups Path (With Worktrees)` headers — the entire Step 3 body becomes the worktree path
   - Add introductory text clarifying that all implementations use worktree isolation
   - Replace deterministic `/tmp/ship-${name}-wg${num}-${TIMESTAMP}` paths with `mktemp -d /tmp/ship-XXXXXXXXXX` in Step 3b
   - Replace `.ship-worktrees.tmp` with `.ship-worktrees-${RUN_ID}.tmp` in Steps 3b, 3c, 3d, 3e, 3f
   - Replace `.ship-violations.tmp` with `.ship-violations-${RUN_ID}.tmp` in Step 3d
   - Add known-limitation comment to Step 3d about `awk '{print $2}'` parsing for renames and spaces
   - Add post-merge file existence validation in Step 3e (warning-level, non-blocking)
   - Update Step 3c tool line to note `parallel if multiple, single Task call if one group`
   - Remove the dual-path conditional in Step 5a
   - Remove the `**If single work group (no worktrees):**` block from Step 5a
   - Remove the `**If work groups were used in Step 3:**` conditional — make the worktree path unconditional
   - Add WIP commit of current state before worktree re-creation in Step 5a
   - Update Step 5a to reference `.ship-worktrees-${RUN_ID}.tmp`
   - Update Step 6 squash logic to account for possible Step 5a WIP commit
   - Update the WIP commit message in Step 3a from `v3.2.0` to `v3.3.0`

### Phase 2: Validate

2. [ ] Run skill validator:
   ```bash
   python3 /Users/imurphy/projects/claude-devkit/generators/validate_skill.py \
     /Users/imurphy/projects/claude-devkit/skills/ship/SKILL.md
   ```
3. [ ] Verify the skill passes validation (exit code 0)

### Phase 3: Update Registry

4. [ ] Update `/Users/imurphy/projects/claude-devkit/CLAUDE.md`
   - Update Ship skill version from `3.2.0` to `3.3.0` in the Skill Registry table
   - Update Ship skill description in the registry. Replace the current description with: `Pre-flight check -> Read plan -> Pattern validation (warnings) -> Worktree isolation -> Parallel coders -> File boundary validation -> Merge -> Code review + tests + QA (parallel) -> Revision loop -> Commit gate. Structural conflict prevention.` (removes the "(for work groups)" parenthetical since worktrees are now unconditional)
   - Update the "When NOT to use" guidance in the Worktree Isolation Pattern section. Remove or revise "Single-file changes (no parallelism needed)" since `/ship` now uses worktrees for all changes regardless of file count. The remaining items ("Read-only operations", "Tightly coupled files") remain valid guidance for the abstract pattern.

### Phase 4: Deploy and Test

5. [ ] Deploy the updated skill:
   ```bash
   cd /Users/imurphy/projects/claude-devkit && ./scripts/deploy.sh ship
   ```
6. [ ] Manual smoke test: Run `/ship` against a single-work-group plan and verify worktree creation
7. [ ] Manual smoke test: Run `/ship` against a multi-work-group plan and verify behavior unchanged

### Phase 5: Commit

8. [ ] Commit changes:
   ```bash
   git add skills/ship/SKILL.md CLAUDE.md
   git commit -m "feat(skills): ship v3.3.0 — always use worktree isolation

   Eliminates the non-isolated single work group path. Every /ship
   implementation now runs in a git worktree regardless of work group count,
   providing consistent isolation guarantees against concurrent modifications.

   Also hardens worktree mechanics: mktemp -d for secure paths, run-scoped
   tracking files for concurrent run safety, post-merge file validation,
   and WIP commit before revision loop worktree creation."
   ```

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Worktree creation fails on edge-case git states (detached HEAD, shallow clone) | Low | High — blocks all /ship runs | Step 0 pre-flight already checks git status; add explicit error message in Step 3b pointing to recovery steps |
| Disk space exhaustion in /tmp for large repos | Low | Medium — worktree creation fails | Worktrees are cleaned up in Step 3f; Step 0 prunes orphans; /tmp is typically large |
| Performance regression on very large repos (worktree copy time) | Low | Low — adds seconds to a minutes-long process | Git worktrees use hardlinks for objects; only working tree files are copied. May take 10-30s on large monorepos. |
| Single-group plans that previously succeeded now fail due to boundary validation being more strict | Very Low | Medium — false positives block implementation | Boundary validation logic is unchanged; single-group plans populate scoped_files from Task Breakdown (explicitly specified in Step 1) |
| Existing documentation/tutorials reference the non-worktree path | Low | Low — confusion, not breakage | CLAUDE.md is the single source of truth; update it in Phase 3 |
| Concurrent `/ship` runs interfere with each other | Low | High — corrupted tracking state | Mitigated by run-scoped tracking filenames (`.ship-worktrees-${RUN_ID}.tmp`) |
| Revision loop worktrees lack first-pass code | Low | Medium — coder re-implements instead of fixing | Mitigated by WIP commit before worktree re-creation in Step 5a |

## Test Plan

### Automated Validation

```bash
# Validate skill definition against v2.0.0 patterns
python3 /Users/imurphy/projects/claude-devkit/generators/validate_skill.py \
  /Users/imurphy/projects/claude-devkit/skills/ship/SKILL.md
```

Expected: Exit code 0, all checks pass.

### Manual Smoke Tests

1. **Single work group, no Work Groups section:**
   - Create a minimal plan with Task Breakdown listing 1-2 files, no `## Work Groups` section
   - Run `/ship plans/test-single.md`
   - Verify: worktree created via `mktemp -d` at `/tmp/ship-*`, coder dispatched to worktree, files merged back, worktree cleaned up
   - Verify: tracking file uses run-scoped name (`.ship-worktrees-*.tmp`)

2. **Single work group, explicit Work Groups section with one group:**
   - Create a plan with `## Work Groups` containing one `### Work Group 1:` section
   - Run `/ship plans/test-explicit-single.md`
   - Verify: same worktree behavior as test 1

3. **Multiple work groups (regression):**
   - Use an existing multi-group plan
   - Run `/ship`
   - Verify: behavior identical to v3.2.0 multi-group path (with mktemp paths and run-scoped tracking)

4. **Shared dependencies + single group:**
   - Create a plan with `### Shared Dependencies` and one work group
   - Run `/ship`
   - Verify: shared deps committed first, worktree created from that commit, merge includes both

5. **Revision loop with single group:**
   - Create a plan likely to trigger REVISION_NEEDED (e.g., intentionally incomplete implementation)
   - Verify: WIP commit created before revision, revision loop re-creates worktree from WIP commit, dispatches coder, validates boundaries, merges, cleans up

### Negative Tests

6. **Aborted run cleanup:**
   - Kill a `/ship` run mid-execution
   - Start a new `/ship` run
   - Verify: Step 0 pre-flight cleans up orphaned worktrees and their tracking files

7. **Concurrent runs (manual verification):**
   - Start two `/ship` runs in separate terminals against the same project
   - Verify: each run uses its own `.ship-worktrees-${RUN_ID}.tmp` file
   - Verify: Step 0 of the second run does NOT delete the first run's tracking file

## Acceptance Criteria

- [ ] The string "Single Work Group Path (No Worktrees)" does not appear in `skills/ship/SKILL.md`
- [ ] The string "If single work group (no worktrees)" does not appear in `skills/ship/SKILL.md`
- [ ] The string "If work groups were used in Step 3" does not appear in `skills/ship/SKILL.md`
- [ ] Frontmatter version is `3.3.0`
- [ ] Steps 3b-3f are present and unconditional (no branching based on work group count)
- [ ] Step 3a remains conditional on `### Shared Dependencies` section existence
- [ ] Step 3b uses `mktemp -d` instead of deterministic paths
- [ ] All references to `.ship-worktrees.tmp` use run-scoped format `.ship-worktrees-${RUN_ID}.tmp`
- [ ] Step 3d includes a known-limitation comment about `awk '{print $2}'` parsing
- [ ] Step 3e includes post-merge file existence validation (warning-level)
- [ ] Step 1 includes explicit `scoped_files` derivation for plans without `## Work Groups`
- [ ] Step 5a includes a WIP commit before worktree re-creation
- [ ] Step 5a has exactly one path — always uses worktrees
- [ ] Skill passes `validate_skill.py` with exit code 0
- [ ] CLAUDE.md Skill Registry shows ship version `3.3.0`
- [ ] CLAUDE.md Skill Registry description removes "(for work groups)" parenthetical
- [ ] CLAUDE.md "When NOT to use" section is updated to remove single-file guidance
- [ ] The Step 3a WIP commit message references `v3.3.0`

## Task Breakdown

### Files to Modify

| File | Action | Description |
|------|--------|-------------|
| `/Users/imurphy/projects/claude-devkit/skills/ship/SKILL.md` | Modify | Remove dual-path logic, make worktrees unconditional, mktemp paths, run-scoped tracking, post-merge validation, revision WIP commit, bump version |
| `/Users/imurphy/projects/claude-devkit/CLAUDE.md` | Modify | Update Ship version and description in Skill Registry; update "When NOT to use" worktree guidance |

### Files to Create

None.

### Files to Delete

None.

### Detailed Edits for `skills/ship/SKILL.md`

1. **Frontmatter:** Change `version: 3.2.0` to `version: 3.3.0`

2. **Step 0 — Pre-flight:** Add `RUN_ID` generation. Update cleanup logic for `.ship-worktrees-*.tmp` to use orphan-aware deletion (check if listed worktrees still exist before deleting tracking file).

3. **Step 1 — Plan parsing:** Add explicit instruction: "When no `## Work Groups` section exists, derive `scoped_files` by extracting ALL files from the Task Breakdown section (both `### Files to Modify` and `### Files to Create` tables). Store as a single implicit work group."

4. **Step 3 header area:** Remove the entire "Single Work Group Path" section. Remove the "Multiple Work Groups Path" header. Add introductory paragraph explaining that all implementations use worktree isolation.

5. **Step 3a commit message:** Change `v3.2.0` to `v3.3.0`

6. **Step 3b — Create Worktrees:** Replace the deterministic path construction with:
   ```bash
   WORKTREE_PATH=$(mktemp -d /tmp/ship-XXXXXXXXXX)
   ```
   Replace `.ship-worktrees.tmp` with `.ship-worktrees-${RUN_ID}.tmp`.

7. **Step 3c tool line:** Update to clarify single-group behavior: `**dispatch one coder per work group (parallel if multiple, single Task call if one group)**`

8. **Step 3d — File Boundary Validation:** Replace `.ship-worktrees.tmp` with `.ship-worktrees-${RUN_ID}.tmp`. Replace `.ship-violations.tmp` with `.ship-violations-${RUN_ID}.tmp`. Add comment after the `awk '{print $2}'` line:
   ```
   # Known limitation: awk '{print $2}' does not correctly handle renamed files
   # (R old -> new captures only 'old') or file paths containing spaces.
   # The merge step (3e) is the primary safety boundary — it copies only scoped files.
   # Improving this parsing is deferred to a follow-up change.
   ```

9. **Step 3e — Merge Worktrees:** Replace `.ship-worktrees.tmp` with `.ship-worktrees-${RUN_ID}.tmp`. After the existing `cp` loop, add post-merge validation:
   ```bash
   for file in $scoped_files; do
     if [ ! -f "$MAIN_DIR/$file" ]; then
       echo "WARNING: Scoped file $file was not created by coder in worktree"
     fi
   done
   ```

10. **Step 3f — Cleanup Worktrees:** Replace `.ship-worktrees.tmp` with `.ship-worktrees-${RUN_ID}.tmp`. Delete the tracking file after all worktrees are removed.

11. **Step 5a:** Remove the `**If work groups were used in Step 3:**` conditional. Remove the `**If single work group (no worktrees):**` block. Make the worktree revision path unconditional. Update section header to `### 5a — Coder fixes (with worktree isolation)`. Add WIP commit before worktree re-creation:
    ```bash
    git add -A
    git commit -m "WIP: ship v3.3.0 first-pass implementation (pre-revision)"
    ```
    Update all tracking file references to `.ship-worktrees-${RUN_ID}.tmp`.

12. **Step 6 — Commit Gate:** Update squash logic to account for possible Step 5a WIP commit in addition to the existing Step 3a shared deps commit.

## Context Alignment

| Aspect | Alignment |
|--------|-----------|
| **CLAUDE.md Patterns** | Fully aligned — Pattern #11 (Worktree Isolation) is already documented; this change makes it unconditional |
| **Skill v2.0.0 Patterns** | All 11 patterns maintained — numbered steps, tool declarations, verdict gates, bounded iterations, etc. |
| **Artifact Locations** | No change — same `./plans/` and `./plans/archive/` structure |
| **Development Rules** | Follows "Edit source, not deployment" — changes to `skills/ship/SKILL.md` |
| **Deployment Flow** | Standard `./scripts/deploy.sh ship` — no changes to deployment |
| **Version Control** | Conventional commit format: `feat(skills): ship v3.3.0 — ...` |
| **Existing Worktree Pattern** | Steps 2a-2f in CLAUDE.md map directly to Steps 3a-3f — no structural change |

## Status: APPROVED

<!-- Context Metadata
discovered_at: 2026-02-24T00:00:00Z
claude_md_exists: true
recent_plans_consulted: none
archived_plans_consulted: none
-->
