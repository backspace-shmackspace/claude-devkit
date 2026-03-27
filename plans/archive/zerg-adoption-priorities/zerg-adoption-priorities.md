# Plan: Zerg Adoption Priorities for Claude-Devkit

**Date:** 2026-02-23 (revised)
**Author:** Senior Architect
**Status:** APPROVED
**Affects:** skills/ship, skills/dream, generators, templates, configs, scripts

---

## Revision Log

| Rev | Date | Trigger | Summary |
|-----|------|---------|---------|
| 1 | 2026-02-23 | Initial draft | Full zerg adoption plan |
| 2 | 2026-02-23 | 3 reviews (librarian FAIL, red team FAIL, feasibility PASS w/ 2 critical unknowns) | Restructured: fix worktree bugs first (C3), evaluate zerg before integration (C1), redesign around CLI invocation (C1), acknowledge vendor risk (C4), fix all naming conventions (C5) |

**Findings addressed in this revision:**
- **C1** -- Zerg Python API does not exist. Integration redesigned around CLI/subprocess invocation.
- **C2** -- Task-graph schema was invented. Schema is now explicitly a claude-devkit-defined contract with a zerg adapter layer.
- **C3** -- Worktree code deletion reversed. Strategy is now: fix bugs, deprecate, replace after zerg is proven.
- **C4** -- Vendor risk upgraded. Anthropic Swarms evaluation added. Integration is opt-in and loosely coupled.
- **C5** -- All librarian naming/convention conflicts resolved.

---

## Context

Claude-devkit (v1.0.0) is a unified development toolkit for Claude Code with 5 production skills, 5 generators, 11 templates, and 7 tech-stack configs. It handles single-instance structured workflows with coordination, validation, and quality gates.

Zerg (zerg-ai v0.2.0) is a parallel Claude Code orchestration framework that runs 5-10 Claude Code instances simultaneously, using exclusive file ownership per task, spec-driven stateless workers, and git worktree isolation to prevent merge conflicts.

Both systems solve the same structural conflict prevention problem for parallel agent work, but at different scales. Claude-devkit's `/ship` v3.1.0 has a hand-rolled worktree isolation mechanism with **6 critical bash scripting bugs** (per the code review at `plans/archive/ship-v3.1/ship-v3.1.code-review.md`). The code review rates the implementation as `REVISION_NEEDED` (not `FAIL`), noting that "the worktree isolation design is architecturally sound" and estimating 2-3 hours to fix the critical issues. The bugs are: unsafe variable expansion, false-positive file boundary validation, missing error handling in worktree creation, undefined scoped files array, fragile modified-file detection, and silent cleanup failures.

Zerg has a purpose-built worktree and file ownership system that solves the same problem at a larger scale. However, zerg is a pre-1.0 project (25 GitHub stars, single maintainer, 16 days old) and Anthropic's native Swarms feature may provide a first-party alternative.

The question is: "How do we get immediate value from fixing what we have, while positioning for zerg adoption if it proves stable, without creating hard dependencies on a pre-1.0 single-maintainer project?"

---

## Goals

1. **Fix /ship's worktree isolation bugs** -- the 6 critical bash bugs are straightforward fixes (variable expansion, error handling, path normalization). This gives immediate value with zero external risk.
2. **Evaluate zerg's actual interface** -- install zerg, document what it actually provides (CLI commands, output formats, actual API surface), and determine the viable integration path. No integration work until this evaluation is complete.
3. **Enable opt-in parallel execution via zerg** -- for users who install zerg, `/ship` can delegate parallel execution to zerg via CLI subprocess invocation. This is additive and never required.
4. **Preserve full functionality without zerg** -- `/dream`, `/audit`, `/sync` remain unchanged. `/ship` works identically whether or not zerg is installed. The worktree isolation code remains the default parallel path.
5. **Design for swappability** -- the integration layer must be thin enough that switching from zerg to Anthropic's native Swarms (or another orchestrator) requires changing one adapter, not the skill definitions.
6. **Add a generator for zerg integration** so projects can bootstrap zerg config from claude-devkit in one command.

## Non-Goals

1. **Replace claude-devkit's skill system with zerg commands** -- zerg's `/z:*` commands are complementary, not competitive. Skills handle quality gates, verdict logic, and artifact management. Zerg handles parallelization.
2. **Make zerg a hard dependency** -- it must remain optional. Users who never install zerg should see zero behavioral changes.
3. **Replicate zerg's container mode** -- docker isolation is zerg's domain. Claude-devkit should not build container support.
4. **Migrate /dream, /audit, or /sync to use zerg** -- these skills are single-instance coordinators. They do not benefit from multi-instance parallelization.
5. **Rewrite zerg** -- we consume it as a dependency, not fork it.
6. **Delete working code before the replacement is proven** -- the worktree isolation code stays until zerg integration is tested end-to-end.

## Assumptions

1. Zerg v0.2.0+ can be invoked via CLI commands or subprocess calls (verified in P0.0 evaluation).
2. Users have Claude Code CLI installed (prerequisite for both systems).
3. The task-graph format is a **claude-devkit-defined contract** that the zerg adapter translates to zerg's native format at execution time. This is explicitly NOT zerg's native schema.
4. **[REVISED]** The integration point is CLI/subprocess invocation (`zerg rush`, `zerg status`, etc.), NOT a Python import. If a Python API is discovered during evaluation, it may be used, but the design does not depend on it.
5. The primary user persona is a solo developer or small team using Claude Code with 1-10 parallel instances on a local machine (not CI/CD at scale).
6. Users who adopt zerg will run `/zerg:init` once per project before using the integrated workflow.
7. **[NEW]** Anthropic may ship native parallel orchestration (Swarms) that supersedes zerg. The integration must be loosely coupled enough to swap orchestrators.

---

## Strategic Assessment

### Current State

| Capability | Claude-Devkit | Zerg | Overlap |
|---|---|---|---|
| Planning with quality gates | `/dream` v2.1.0 | `/z:plan`, `/z:design` | **Partial** -- both produce plans, different formats |
| Parallel execution | `/ship` v3.1.0 (6 fixable bugs) | `/z:rush` (working) | **Direct** -- both use git worktrees, file scoping |
| File conflict prevention | Worktree isolation (architecturally sound, needs bug fixes) | Exclusive file ownership + task graph | **Direct** -- zerg has more features (crash recovery, levels) |
| Code review | `/ship` Step 3a | `/z:review` | **Partial** -- both dispatch reviewers |
| Security scanning | `/audit` v2.0.0 | `/z:security` | **Partial** -- different scope |
| Documentation sync | `/sync` v2.0.0 | `/z:document` | **Minimal** -- different purpose |
| Agent generation | `generate_agents.py` | None | **None** -- claude-devkit unique |
| Skill generation | `generate_skill.py` | None | **None** -- claude-devkit unique |
| Crash recovery | None | Built-in (stateless workers) | **None** -- zerg unique |
| Context engineering | None | Command splitting, scoped budgets | **None** -- zerg unique |

### Desired State

```
/dream  --- produces plan (optionally with task-graph.json) ---+
                                                                |
                                                                v
                        +---------------------------------------+
                        |         /ship v3.2.0                  |
                        |                                       |
                        |  [zerg installed AND task-graph?]      |
                        |     YES: zerg parallel path (opt-in)   |
                        |       - Invoke zerg CLI via subprocess |
                        |       - Adapter translates formats     |
                        |       - Quality gates post-completion  |
                        |     NO: built-in worktree isolation    |
                        |       - Fixed v3.2.0 worktree code     |
                        |       - Same quality gates             |
                        |       - Single-coder fallback for      |
                        |         plans without work groups      |
                        +---------------------------------------+
                                      |
                                      v
                        /audit, /sync (unchanged)
```

### The Worktree Decision: Fix, Deprecate, Then Replace

**Decision: Fix the 6 critical bash bugs in /ship's worktree isolation. Mark the code as deprecated. Replace only after zerg integration is proven end-to-end.**

Rationale:
1. The code review rates the worktree isolation as `REVISION_NEEDED`, not `FAIL`. The design is architecturally sound. The 6 critical bugs are bash scripting errors (unquoted variables, missing error handling, fragile path matching), not architectural flaws.
2. Fixing the bugs is estimated at 2-3 hours -- far less than building and validating a zerg integration from scratch.
3. Deleting working code before the replacement exists creates a capabilities gap. If the zerg integration encounters unexpected issues (API does not exist as expected, schema incompatibility, abandonment), parallel execution would be unavailable for an indefinite period.
4. The worktree code has a test suite (`test_ship_worktree.sh`, 847 lines, 6 test scenarios) that validates the isolation logic. The tests themselves use simulation rather than live execution, but they verify the structural correctness of the worktree lifecycle.
5. Once zerg integration passes end-to-end testing, the worktree code can be removed in a clean v4.0.0 release with zero risk.

**What to fix now:**
- Critical #1: Variable expansion in Step 2b (use proper template instructions)
- Critical #2: File boundary validation false positives (use exact path matching with normalization)
- Critical #3: Missing error handling in worktree creation (add failure checks)
- Critical #4: Scoped files array undefined (define explicit format and population)
- Critical #5: Modified file detection logic (use `git status --porcelain`)
- Critical #6: Silent cleanup failures (track and report cleanup failures)

**What to add:**
- Deprecation warning when worktree path is invoked: "Note: Built-in worktree isolation is deprecated and will be removed in a future release. For improved parallel execution, install zerg-ai."

**What to remove later (after zerg proven):**
- Steps 2a-2f (worktree code) -- removed in /ship v4.0.0 only after zerg path passes end-to-end tests
- `.ship-worktrees.tmp`, `.ship-violations.tmp` tracking files
- `generators/test_ship_worktree.sh` -- replaced by zerg integration tests

### Vendor Risk Assessment: Zerg

| Factor | Value | Risk Level |
|--------|-------|------------|
| GitHub stars | 25 | High (extremely low adoption) |
| Forks | 8 | High (minimal community) |
| Maintainers | 1 (rocklambros) | High (bus factor = 1) |
| Version | 0.2.0 (pre-1.0) | High (no API stability guarantee) |
| Age | 16 days (as of 2026-02-23) | High (unproven in production) |
| License | MIT | Low (permissive) |
| Python API | Unverified (CLI-first tool) | High (integration path uncertain) |
| Competing solutions | Conductor, Gas Town, Vibe Kanban, Anthropic Swarms | Medium (market may consolidate) |

**Overall vendor risk: HIGH.** This assessment drives three design decisions:
1. **Zerg is never required.** All functionality works without it.
2. **Integration is a thin adapter layer.** If zerg is abandoned, we swap the adapter, not the skill.
3. **Worktree code stays as fallback.** If zerg disappears, we have working parallel execution.

### Anthropic Swarms Evaluation

As of early 2026, Anthropic has built a multi-agent orchestration feature called "Swarms" that has been observed behind feature flags in Claude Code. If Anthropic ships native parallel orchestration:

- Zerg becomes redundant for claude-devkit users.
- The native solution will have first-party support, API stability, and zero dependency risk.
- Claude-devkit should prefer native orchestration over any third-party tool.

**Design implication:** The adapter layer must define a generic `ParallelExecutor` interface that today calls zerg CLI and tomorrow could call `claude swarm` or equivalent. The skill definitions (`/ship`, `/dream`) should reference abstract concepts ("dispatch to parallel executor") not zerg-specific commands.

**Monitoring plan:** Track Anthropic's changelog and Claude Code release notes. If Swarms ships to GA before zerg integration reaches P2, pivot to native integration and skip zerg entirely.

---

## Priority Tiers

### P0 -- Must Do First (Week 1)

These are prerequisites for everything else. P0.0 can run in parallel with P0.1.

| # | Task | Why First | Dependencies |
|---|------|-----------|--------------|
| P0.0 | Evaluate zerg capabilities | Cannot design integration without knowing actual interface | None |
| P0.1 | Fix 6 critical bash bugs in `/ship` worktree isolation | Immediate value: working parallel execution without external dependencies | None |
| P0.2 | Add zerg detection to `/ship` pre-flight (informational only) | Feature gate for future zerg path; non-blocking, informational | P0.0 (need to know detection method) |
| P0.3 | Reconcile CLAUDE.md version discrepancies and add deprecation note | Documentation accuracy is a prerequisite for further changes | P0.1 |

### P1 -- Do Next (Week 2-3)

These build on P0 and deliver the core zerg integration. **Gated on P0.0 results.**

| # | Task | Why Next | Gate |
|---|------|----------|------|
| P1.1 | Extend `/dream` plan output with task-graph.json | Zerg cannot execute without a task graph. This is the interface contract. | P0.0 confirms viable integration path |
| P1.2 | Implement `/ship` zerg execution path via CLI adapter | The actual parallel execution: parse task graph, invoke zerg CLI, wait for completion | P0.0, P0.2, P1.1 |
| P1.3 | Create `generate_zerg_config.py` generator | One-command zerg bootstrapping for projects | P0.0 |
| P1.4 | Update test suites | Test both paths: zerg-present, zerg-absent, worktree fallback | P1.2 |

### P2 -- Can Wait (Week 4-5)

These improve the integration but are not blocking.

| # | Task | Why Later |
|---|------|-----------|
| P2.1 | Add `--parallel` flag to `/ship` | Explicit opt-in for zerg path even when zerg is installed (user control) |
| P2.2 | Create zerg tech-stack config | `configs/tech-stack-definitions/zerg.json` for agent generation awareness |
| P2.3 | Update CLAUDE.md with zerg integration docs | Document the new workflow, patterns, troubleshooting, new artifact types |
| P2.4 | Update `install.sh` with optional zerg setup | Add `pip install zerg-ai` suggestion and alias for `gen-zerg-config` |
| P2.5 | Add CHANGELOG.md | Document the v3.2.0 changes (worktree bug fixes, deprecation, zerg integration) |

### P3 -- Future/Conditional (v1.2+ or post-Swarms evaluation)

These depend on zerg proving stable in production AND Anthropic not shipping native Swarms.

| # | Task | Why Conditional |
|---|------|-----------------|
| P3.1 | Remove deprecated worktree code from `/ship` (v4.0.0) | Only after zerg integration is proven end-to-end |
| P3.2 | Add `/status-zerg` skill | Wrapper around zerg status commands with claude-devkit artifact formatting |
| P3.3 | Integrate zerg's `/z:security` with `/audit` | Combine security scanning backends |
| P3.4 | Add zerg worker count to `/dream` plan estimation | Help users understand parallelism before execution |
| P3.5 | Complete `/test-idempotent` skill implementation | Useful for testing zerg determinism |
| P3.6 | Evaluate Anthropic Swarms integration | If Swarms ships to GA, build native adapter and deprecate zerg adapter |

---

## Proposed Design

### Architecture

```
claude-devkit/
+-- skills/
|   +-- dream/SKILL.md          # MODIFIED (P1.1): Add task-graph.json generation
|   +-- ship/SKILL.md           # MODIFIED (P0.1): Fix bugs, add deprecation warning
|                                # MODIFIED (P0.2): Add zerg detection
|                                # MODIFIED (P1.2): Add zerg CLI execution path
|   +-- audit/SKILL.md          # UNCHANGED
|   +-- sync/SKILL.md           # UNCHANGED
|   +-- test-idempotent/SKILL.md # UNCHANGED (P3)
|
+-- generators/
|   +-- generate_zerg_config.py  # NEW (P1.3): Bootstrap zerg config for projects
|   +-- generate_agents.py       # UNCHANGED
|   +-- generate_skill.py        # UNCHANGED
|   +-- validate_skill.py        # UNCHANGED
|   +-- validate_agent.py        # UNCHANGED
|
+-- configs/
|   +-- zerg-integration.json    # NEW (P1.2): Zerg integration defaults
|   +-- tech-stack-definitions/
|       +-- (existing files)     # UNCHANGED
|
+-- templates/
|   +-- (existing files)         # UNCHANGED
|
+-- scripts/
    +-- deploy.sh                # UNCHANGED
    +-- install.sh               # MODIFIED (P2.4): Add zerg suggestion
```

### /ship v3.2.0 Execution Flow

```
Step 0: Pre-flight checks
  +-- Existing checks (git clean, agents present)
  +-- Stale worktree cleanup (existing, fixed)
  +-- NEW: Detect zerg installation (informational)
       +-- Found: Log "Zerg v{version} detected. Parallel execution available."
       +-- Not found: Log "Zerg not installed. Using built-in worktree isolation."

Step 1: Read plan (unchanged)
  +-- Parse plan file
  +-- Extract files, test command, acceptance criteria
  +-- Parse work groups (if present)
  +-- NEW: Check for task-graph.json alongside plan
       +-- Found: Set HAS_TASK_GRAPH=true
       +-- Not found: Set HAS_TASK_GRAPH=false

Step 2: Implementation
  +-- IF ZERG_AVAILABLE=true AND HAS_TASK_GRAPH=true:
  |     Zerg Parallel Path (opt-in, via CLI adapter)
  |     +-- Validate task-graph.json (schema check + cycle detection)
  |     +-- Invoke zerg CLI via subprocess
  |     +-- Parse structured output
  |     +-- Verify all tasks completed successfully
  |     +-- (On failure: log error, DO NOT fall back automatically)
  |
  +-- ELSE IF plan has multiple work groups:
  |     Built-in Worktree Path (deprecated, fixed)
  |     +-- Log deprecation warning
  |     +-- Steps 2a-2f (existing, with bug fixes from P0.1)
  |
  +-- ELSE:
        Single-Coder Path (current Step 2, no worktrees)
        +-- Dispatch single coder agent
        +-- Check for BLOCKED.md
        +-- Continue to Step 3

Step 3: Parallel verification (unchanged -- code review + tests + QA)
Step 4: Revision loop (unchanged, always single-coder for fixes)
Step 5: Commit gate (unchanged)
```

### /dream v2.2.0 Plan Output Extension

When `/dream` produces a plan, it now also generates a `task-graph.json` file alongside the plan markdown if the plan contains work groups.

**Plan file:** `./plans/[feature-name].md` (existing format, unchanged)
**Task graph:** `./plans/[feature-name].task-graph.json` (new, generated from Work Groups)

The task graph is a **claude-devkit-defined contract**. It is NOT zerg's native schema. The zerg adapter (in `/ship`) translates this format to whatever zerg expects at execution time.

The task graph is derived from the plan's Task Breakdown section:

```
Plan Markdown (Work Groups)     ->     task-graph.json
-----------------------------         --------------------
### Shared Dependencies              level: 0 (sequential)
- src/types.ts                        task: "shared-deps"
                                      files: { creates: ["src/types.ts"] }
### Work Group 1: Components
- src/Button.tsx                      level: 1 (parallel)
- src/Card.tsx                        task: "wg-1-components"
                                      files: { modifies: ["src/Button.tsx", "src/Card.tsx"] }
### Work Group 2: Utilities
- src/helpers.ts                      level: 1 (parallel)
                                      task: "wg-2-utilities"
                                      files: { modifies: ["src/helpers.ts"] }
```

### Generator: generate_zerg_config.py

A new generator that bootstraps zerg configuration for a project.

```bash
gen-zerg-config .                    # Auto-detect, create .zerg/ and .gsd/
gen-zerg-config . --workers 5        # Set default worker count
gen-zerg-config . --mode subprocess  # Set execution mode
```

What it creates:
- `.zerg/config.yaml` -- worker settings, quality gates linked to claude-devkit agents
- `.gsd/` directory structure -- specs directory for zerg planning
- Suggests running `/zerg:init` for full security rule setup

What it does NOT do:
- Run `/zerg:init` (that requires Claude Code session context)
- Install zerg (user responsibility)
- Modify existing `.zerg/` config (use `--force` to overwrite)

**Generator rules compliance (per CLAUDE.md "Development Rules > For Generators"):**
- **Atomic writes:** Write to temp file, rename on success. If generation fails partway, no partial `.zerg/` or `.gsd/` is left behind.
- **Input validation:** Validate target-dir exists and is writable. Validate `--workers` is a positive integer. Validate `--mode` is a valid enum (`subprocess`, `container`).
- **Rollback on failure:** If any file write fails, clean up all generated files (`.zerg/`, `.gsd/`). Use try/finally or atexit handler.
- **Target directory:** Accepts any writable directory (unlike skill generator which restricts to `~/workspaces/`). Rationale: zerg config lives in project directories, not in claude-devkit.

### Zerg CLI Adapter Design

The adapter encapsulates all zerg interaction. If zerg's interface changes, only the adapter changes. If Anthropic ships native Swarms, a new adapter replaces this one.

**Location:** `scripts/zerg-adapter.sh` (shell script, invoked by `/ship` via Bash tool)

**Interface:**

```bash
# Validate task graph
scripts/zerg-adapter.sh validate ./plans/[name].task-graph.json

# Execute task graph via zerg
scripts/zerg-adapter.sh execute ./plans/[name].task-graph.json [--workers N]

# Check zerg status
scripts/zerg-adapter.sh status

# Check zerg availability
scripts/zerg-adapter.sh detect
```

**Why a shell script, not inline Python in SKILL.md:**
- Avoids fragile quoting of multi-line Python inside Bash tool invocations (per librarian optional suggestion 2)
- Can be tested independently of the skill
- Easier to swap for a Swarms adapter later
- Follows the existing `scripts/` pattern

**What the adapter does:**
1. `detect`: Checks for zerg CLI binary (`command -v zerg`). If not found, checks for Python package (`python3 -c "import zerg"`). Outputs version or "not-found".
2. `validate`: Reads the claude-devkit task-graph.json, validates schema (structure, exclusive file ownership, cycle detection in dependency graph), outputs PASS/FAIL.
3. `execute`: Translates claude-devkit task-graph.json to zerg's native format (determined in P0.0), invokes `zerg rush` (or equivalent CLI command), monitors output, writes results to `./plans/[name].zerg-results.json`.
4. `status`: Wraps `zerg status` (or equivalent) with structured output.

**What the adapter does NOT do:**
- Import zerg as a Python library (unless P0.0 discovers a stable Python API)
- Modify skill definitions
- Handle quality gates (that is the skill's job)

---

## Interfaces / Schema Changes

### New: task-graph.json Schema (claude-devkit-defined)

This is a **claude-devkit-defined contract** between `/dream` output and `/ship` execution. It is NOT zerg's native schema. The zerg adapter translates this format at execution time.

```json
{
  "$schema": "claude-devkit-task-graph-v1",
  "feature": "add-user-authentication",
  "plan_file": "./plans/add-user-authentication.md",
  "generated_by": "dream-v2.2.0",
  "generated_at": "2026-02-23T14:30:00Z",
  "levels": [
    {
      "level": 0,
      "tasks": [
        {
          "id": "shared-deps",
          "name": "Shared Dependencies",
          "description": "Implement shared type definitions and utilities",
          "files": {
            "creates": [],
            "modifies": ["src/types.ts"],
            "reads": ["package.json", "tsconfig.json"]
          },
          "dependencies": [],
          "acceptance_criteria": [
            "TypeScript types compile without errors"
          ],
          "timeout_seconds": 600
        }
      ]
    },
    {
      "level": 1,
      "tasks": [
        {
          "id": "wg-1-components",
          "name": "UI Components",
          "description": "Implement login form and auth guard components",
          "files": {
            "creates": ["src/components/LoginForm.tsx"],
            "modifies": ["src/components/AuthGuard.tsx"],
            "reads": ["src/types.ts"]
          },
          "dependencies": ["shared-deps"],
          "acceptance_criteria": [
            "LoginForm renders without errors",
            "AuthGuard redirects unauthenticated users"
          ],
          "timeout_seconds": 600
        },
        {
          "id": "wg-2-api",
          "name": "API Routes",
          "description": "Implement authentication API endpoints",
          "files": {
            "creates": ["src/api/auth.ts"],
            "modifies": ["src/api/index.ts"],
            "reads": ["src/types.ts"]
          },
          "dependencies": ["shared-deps"],
          "acceptance_criteria": [
            "POST /api/auth/login returns JWT",
            "POST /api/auth/register creates user"
          ],
          "timeout_seconds": 600
        }
      ]
    }
  ],
  "test_command": "npm test",
  "total_tasks": 3,
  "max_parallelism": 2
}
```

**Key changes from Rev 1:**
- `$schema` value changed from `task-graph-v1` to `claude-devkit-task-graph-v1` (clearly signals this is our schema, not zerg's)
- Added `timeout_seconds` per task (addresses red team Finding 8 -- deadlock handling)
- Cycle detection is enforced by the adapter's `validate` command (addresses red team Finding 8)

### Modified: /ship SKILL.md Frontmatter

```yaml
---
name: ship
description: Execute an approved plan using unattended implementation and validation with worktree isolation.
version: 3.2.0
model: claude-opus-4-6
---
```

Version bump from 3.1.0 to 3.2.0 (minor: bug fixes + additive zerg detection). NOT 4.0.0 because this is not a breaking change -- existing worktree behavior is preserved and fixed, not removed.

### Modified: /dream SKILL.md Frontmatter

```yaml
---
name: dream
description: Research and create a technical blueprint with optional task graph for parallel execution.
version: 2.2.0
model: claude-opus-4-6
---
```

Minor version bump for additive task-graph generation. Note: CLAUDE.md Skill Registry currently shows v2.0.0 but actual SKILL.md is v2.1.0. P0.3 reconciles this before the v2.2.0 bump.

### New: configs/zerg-integration.json

```json
{
  "version": "1.0.0",
  "description": "Default configuration for zerg integration with claude-devkit",
  "defaults": {
    "worker_count": 5,
    "max_workers": 10,
    "execution_mode": "subprocess",
    "global_timeout_seconds": 3600,
    "per_task_timeout_seconds": 600,
    "quality_gates": {
      "lint": {
        "enabled": false,
        "command": null
      },
      "test": {
        "enabled": true,
        "command_source": "plan"
      }
    }
  },
  "adapter": {
    "script": "scripts/zerg-adapter.sh",
    "min_zerg_version": "0.2.0",
    "detection_method": "cli_then_python",
    "notes": "min_zerg_version is advisory. Adapter validates at runtime."
  },
  "task_graph_schema_version": "claude-devkit-task-graph-v1",
  "alternatives": {
    "anthropic_swarms": {
      "status": "monitoring",
      "notes": "If Anthropic ships native parallel orchestration, prefer it over zerg. Adapter swap only."
    }
  }
}
```

---

## Risk Assessment

| # | Risk | Probability | Impact | Mitigation |
|---|------|-------------|--------|------------|
| R1 | Zerg v0.2.0 has breaking changes in v0.3+ | **High** (pre-1.0, single maintainer, 16 days old) | High | All zerg interaction is in `scripts/zerg-adapter.sh`. Adapter can be updated without changing skill definitions. Pin documentation to tested version. |
| R2 | Zerg project abandoned | **High** (25 stars, single maintainer) | Medium | Worktree isolation code is preserved as fallback. Zerg is never required. Adapter can be replaced with Swarms adapter. |
| R3 | Anthropic ships native Swarms, making zerg redundant | Medium | Low (positive outcome) | Adapter design supports swapping. If Swarms ships before P1 completes, pivot to native integration. |
| R4 | `/dream` task-graph generation produces invalid graphs | Medium | High | Adapter validates task-graph before execution. Includes schema check, exclusive file ownership, and cycle detection. Dry-run mode available via `zerg-adapter.sh validate`. |
| R5 | Zerg CLI interface differs from documentation/expectations | Medium | Medium | P0.0 evaluation discovers actual interface before any integration code is written. |
| R6 | Worktree bug fixes introduce regressions | Low | Medium | Existing test suite (`test_ship_worktree.sh`) validates after fixes. Skill validator confirms pattern compliance. |
| R7 | Claude-devkit task-graph schema diverges from zerg's native format | Medium | Medium | Adapter handles translation. Schema is explicitly claude-devkit-defined, so divergence is expected and managed. |
| R8 | Multi-instance execution creates security risks (prompt injection, resource exhaustion) | Medium | High | Document container mode for untrusted codebases. Recommend API spending limits. Add confirmation prompt for large task graphs (>5 workers). Zerg workers should not invoke `/ship` recursively. |
| R9 | `pip show zerg-ai` detection is fragile across environments | Medium | Low | Adapter uses multi-method detection: `command -v zerg` first, then `python3 -c "import zerg"`. Handles virtualenvs, pip vs pip3, pyenv. |
| R10 | Cost of parallel execution surprises users | Low | Medium | Document expected cost multiplier. Add confirmation prompt in `/ship` when `total_tasks` exceeds threshold. |

---

## Rollback Plan

If zerg integration fails at any stage, the rollback path is clear:

### If P0.0 reveals zerg is not viable
- **Action:** Stop zerg integration work. The worktree code is already fixed (P0.1). Mark P1+ tasks as "Cancelled -- zerg evaluation negative."
- **Impact:** Zero. All existing functionality works.

### If P1.2 (zerg execution path) fails during implementation
- **Action:** Revert P1.2 changes to `/ship` SKILL.md. Keep P1.1 (task-graph generation in `/dream`) as it has standalone value for future orchestrators. Keep P1.3 (generator) as optional tooling.
- **Impact:** Users lose zerg parallel path but retain fixed worktree isolation.

### If zerg integration is deployed and zerg is later abandoned
- **Action:** Remove `scripts/zerg-adapter.sh`. Remove zerg detection from `/ship` Step 0. Remove zerg execution path from `/ship` Step 2. Promote worktree isolation from deprecated to primary. Total effort: ~1 hour.
- **Impact:** Users lose zerg-based parallelism but retain worktree-based parallelism.

### If Anthropic ships native Swarms
- **Action:** Create `scripts/swarms-adapter.sh` implementing the same interface. Update `configs/zerg-integration.json` to point to new adapter. Deprecate zerg adapter. Total effort: depends on Swarms API surface, estimated 1-2 days.
- **Impact:** Users gain first-party parallel execution with better support.

---

## Test Plan

### Test Commands

```bash
# P0 tests: Run after fixing worktree bugs and adding zerg detection
# 1. Existing skill validation (must still pass)
python3 generators/validate_skill.py skills/ship/SKILL.md
python3 generators/validate_skill.py skills/dream/SKILL.md

# 2. Existing test suites (must still pass)
bash generators/test_skill_generator.sh

# 3. Worktree test suite (must pass AFTER bug fixes)
bash generators/test_ship_worktree.sh

# 4. Zerg detection test (adapter-based)
bash scripts/zerg-adapter.sh detect
# Expected output: version string or "not-found"

# P1 tests: Run after implementing zerg execution path
# 5. Task-graph schema validation via adapter
bash scripts/zerg-adapter.sh validate plans/test-feature.task-graph.json
# Expected output: "PASS: Task graph valid" or "FAIL: [reason]"

# 6. Cycle detection test
# Create a task graph with circular deps, verify adapter rejects it
python3 -c "
import json
graph = {
    '\$schema': 'claude-devkit-task-graph-v1',
    'feature': 'cycle-test',
    'plan_file': './plans/cycle-test.md',
    'generated_by': 'test',
    'generated_at': '2026-02-23T00:00:00Z',
    'levels': [{
        'level': 0,
        'tasks': [
            {'id': 'a', 'name': 'A', 'description': 'A', 'files': {'creates': ['a.ts'], 'modifies': [], 'reads': []}, 'dependencies': ['b'], 'acceptance_criteria': [], 'timeout_seconds': 60},
            {'id': 'b', 'name': 'B', 'description': 'B', 'files': {'creates': ['b.ts'], 'modifies': [], 'reads': []}, 'dependencies': ['a'], 'acceptance_criteria': [], 'timeout_seconds': 60}
        ]
    }],
    'test_command': 'echo ok',
    'total_tasks': 2,
    'max_parallelism': 2
}
with open('/tmp/cycle-test.task-graph.json', 'w') as f:
    json.dump(graph, f)
"
bash scripts/zerg-adapter.sh validate /tmp/cycle-test.task-graph.json
# Expected output: "FAIL: Circular dependency detected: a -> b -> a"

# 7. Generator validation
python3 generators/generate_zerg_config.py /tmp/test-project --workers 3
test -f /tmp/test-project/.zerg/config.yaml && echo "PASS" || echo "FAIL"
rm -rf /tmp/test-project/.zerg /tmp/test-project/.gsd

# 8. End-to-end test: /dream produces task graph
# (Manual -- run in Claude Code session)
# /dream add user authentication
# Verify: ls plans/*.task-graph.json

# 9. End-to-end test: /ship with zerg
# (Manual -- run in Claude Code session with zerg installed)
# /ship plans/add-user-authentication.md
# Verify: zerg executed in parallel, quality gates ran

# 10. End-to-end test: /ship without zerg (worktree fallback)
# (Manual -- run in Claude Code session without zerg)
# /ship plans/multi-work-group-plan.md
# Verify: worktree isolation used, deprecation warning shown
```

### Test Matrix

| Scenario | Zerg Installed | Task Graph Present | Multiple Work Groups | Expected Path | Test Type |
|---|---|---|---|---|---|
| Simple plan, no zerg | No | No | No | Single-coder | Automated |
| Simple plan, zerg installed | Yes | No | No | Single-coder | Automated |
| Complex plan, no zerg, no task graph | No | No | Yes | Built-in worktrees (with deprecation warning) | Automated |
| Complex plan, no zerg, task graph present | No | Yes | Yes | Built-in worktrees (warn: zerg not found) | Automated |
| Complex plan, zerg installed, task graph | Yes | Yes | Yes | Zerg parallel | Manual |
| Invalid task graph, zerg installed | Yes | Yes (invalid) | Yes | Error + instructions (no silent fallback) | Automated |
| Zerg execution fails mid-way | Yes | Yes | Yes | Error with partial recovery instructions | Manual |
| Single work group, zerg installed | Yes | No | No | Single-coder (zerg not needed) | Automated |

---

## Task Breakdown

### P0: Fix Worktree Bugs, Evaluate Zerg, Add Detection (Week 1)

#### P0.0: Evaluate zerg capabilities

**Purpose:** Before any integration work, install zerg, run it, and document what it actually provides. This is a prerequisite for all P1+ tasks.

**Steps:**
1. [ ] Install zerg: `pip install zerg-ai`
2. [ ] Check for Python API: `python3 -c "import zerg; print(dir(zerg))"`
3. [ ] Check for CLI commands: `zerg --help` or `command -v zerg`
4. [ ] If Claude Code session available: run `/z:design` on a test feature and inspect output
5. [ ] Inspect `.gsd/specs/` directory for task-graph format
6. [ ] Document findings in `./plans/zerg-evaluation.md`:
   - Actual CLI commands and their flags
   - Actual output formats (JSON? plaintext? structured?)
   - Whether a Python programmatic API exists
   - The actual `task-graph.json` schema (if any)
   - Version string format
   - Dependency tree (`pip show zerg-ai` output)
7. [ ] Determine integration path: CLI subprocess, slash commands, or Python API
8. [ ] Update this plan's P1 tasks based on findings (if significant changes needed, flag for re-review)

**Acceptance criteria:**
- [ ] `./plans/zerg-evaluation.md` exists with documented CLI surface, output formats, and recommended integration path
- [ ] Decision on adapter implementation approach is documented

#### P0.1: Fix 6 critical bash bugs in /ship worktree isolation

**Files to modify:**
- `skills/ship/SKILL.md` -- Fix bugs in Steps 2a-2f, add deprecation warning, update version to 3.2.0

**Bug fixes (from code review at `plans/archive/ship-v3.1/ship-v3.1.code-review.md`):**

1. **Critical #1 (Variable expansion):** The v3.1.0 code already uses `${name}`, `${wg_num}`, `${wg_name}`, `${scoped_files}` template syntax with explicit coordinator instructions. Verify these instructions are clear and unambiguous. Add a note that the coordinator must substitute these variables from Step 1 plan parsing.

2. **Critical #2 (File boundary validation):** Already fixed in v3.1.0 -- Step 2d uses exact path matching with `sed 's|^\./||'` normalization and a loop over scoped files. Verify the logic is correct.

3. **Critical #3 (Missing error handling in worktree creation):** Already fixed in v3.1.0 -- Step 2b has `if ! git worktree add` with error handling and `.ship-worktrees.tmp` cleanup. Verify.

4. **Critical #4 (Scoped files array):** Already fixed in v3.1.0 -- Step 2b has coordinator instructions to populate `${scoped_files}` as space-separated list and stores in pipe-delimited format in `.ship-worktrees.tmp`. Verify the `.ship-worktrees.tmp` format is documented.

5. **Critical #5 (Modified file detection):** Already fixed in v3.1.0 -- Step 2d uses `git status --porcelain | awk '{print $2}'` as primary detection, with `git diff --name-only HEAD~1 HEAD` as fallback for committed changes. Verify both paths.

6. **Critical #6 (Silent cleanup failures):** Already fixed in v3.1.0 -- Step 2f tracks `CLEANUP_FAILURES` counter and reports failures without blocking workflow. Verify.

**Note:** Review of the actual v3.1.0 SKILL.md shows that many of the code review's critical bugs were already addressed in the v3.1.0 implementation (the code review may have been against an earlier draft). The remaining work is:
- Verify all 6 fixes are correctly implemented
- Add deprecation warning to the Multiple Work Groups Path header
- Update version to 3.2.0

**Additional changes:**
- Add deprecation warning at the top of "### Multiple Work Groups Path (With Worktrees)":
  ```
  **DEPRECATED:** Built-in worktree isolation will be removed in /ship v4.0.0.
  For improved parallel execution with crash recovery and level-based task progression,
  install zerg-ai: `pip install zerg-ai`
  ```
- Update frontmatter version to 3.2.0

**Steps:**
1. [ ] Read `skills/ship/SKILL.md` in full
2. [ ] Verify all 6 critical bug fixes are correctly implemented in v3.1.0
3. [ ] If any bug is NOT fixed, apply the fix from the code review recommendations
4. [ ] Add deprecation warning to Multiple Work Groups Path section header
5. [ ] Update frontmatter version to 3.2.0
6. [ ] Run: `python3 generators/validate_skill.py skills/ship/SKILL.md`
7. [ ] Run: `bash generators/test_ship_worktree.sh` (existing worktree tests must pass)
8. [ ] Run: `bash generators/test_skill_generator.sh` (full test suite must pass)

#### P0.2: Add zerg detection to /ship pre-flight

**Files to modify:**
- `skills/ship/SKILL.md` -- Add zerg detection check to Step 0

**Depends on:** P0.0 (need to know which detection method works)

**Changes:**
Add to Step 0 parallel checks:
```markdown
5. Check for zerg installation (Bash):
   ```bash
   bash scripts/zerg-adapter.sh detect
   ```
   - If output is a version string: Output "Zerg v{version} detected. Parallel execution available."
     Set internal flag: ZERG_AVAILABLE=true
   - If output is "not-found": Output "Zerg not installed. Using built-in parallel execution.
     For improved parallel execution: pip install zerg-ai"
     Set internal flag: ZERG_AVAILABLE=false
   - This check is informational only -- it does NOT block the workflow.
```

Add to Step 1, after parsing plan:
```markdown
6. Check for task-graph.json: `ls ./plans/[name].task-graph.json` (Bash)
   - If found: Set HAS_TASK_GRAPH=true
   - If not found: Set HAS_TASK_GRAPH=false
```

**Steps:**
1. [ ] Add zerg detection to Step 0 parallel checks (uses adapter script)
2. [ ] Add task-graph.json detection to Step 1
3. [ ] Add routing logic at the top of Step 2 (three-way: zerg path, worktree path, single-coder path)
4. [ ] Run: `python3 generators/validate_skill.py skills/ship/SKILL.md`

#### P0.3: Reconcile CLAUDE.md version discrepancies and add deprecation note

**Files to modify:**
- `CLAUDE.md` -- Fix version discrepancies, update pattern documentation

**Changes:**
1. Skill Registry: Update `/dream` version from 2.0.0 to 2.1.0 (matches actual SKILL.md)
2. Skill Registry: Update `/ship` version from 3.1.0 to 3.2.0, update description to note deprecation
3. Pattern section header: Fix "these 10 patterns" to "these 11 patterns" (table has 11 rows)
4. Pattern 11 (Worktree Isolation): Add deprecation note: "Deprecated in /ship v3.2.0. Will be replaced by external orchestrator integration (zerg or Anthropic Swarms) in v4.0.0."
5. Skill Registry Steps column: Update `/ship` from 6 to 6 (unchanged)

**Steps:**
1. [ ] Update Skill Registry `/dream` version to 2.1.0
2. [ ] Update Skill Registry `/ship` version to 3.2.0 and description
3. [ ] Fix pattern section header count to 11
4. [ ] Add deprecation note to Pattern 11
5. [ ] Verify no other stale references

### P1: Zerg Integration (Week 2-3, gated on P0.0 results)

**GATE:** P1 tasks should NOT begin until P0.0 is complete and the zerg evaluation confirms a viable integration path. If P0.0 reveals that zerg cannot be invoked via CLI or subprocess, P1 must be redesigned.

#### P1.1: Extend /dream plan output with task-graph.json

**Files to modify:**
- `skills/dream/SKILL.md` -- Add task-graph generation step after plan approval

**Changes:**
Add new sub-step to Step 1 (architect drafts plan), appended to the existing prompt requirements:
```markdown
Task graph generation (for parallel execution):
- If the plan's Task Breakdown contains a `## Work Groups` section with 2+ groups,
  also generate `./plans/[feature-name].task-graph.json` with the claude-devkit-task-graph-v1 schema:
  [schema from Interfaces section above]
- Derive levels from the plan structure:
  - Shared Dependencies = level 0 (sequential)
  - Work Groups = level 1+ (parallel within each level)
- File ownership MUST be exclusive: no file appears in "creates" or "modifies"
  for more than one task at the same level
- Each task MUST have a `timeout_seconds` field (default: 600)
- Dependencies MUST NOT form cycles
- If the plan has no Work Groups section, do NOT generate a task graph
```

Update frontmatter: version 2.2.0

**Steps:**
1. [ ] Read `skills/dream/SKILL.md` in full
2. [ ] Add task-graph generation instructions to Step 1 prompt
3. [ ] Add task-graph validation language to Step 2 (reviewers should check file ownership exclusivity and cycle-free dependencies)
4. [ ] Update frontmatter version to 2.2.0
5. [ ] Run: `python3 generators/validate_skill.py skills/dream/SKILL.md`

#### P1.2: Implement /ship zerg execution path via CLI adapter

**Files to modify:**
- `skills/ship/SKILL.md` -- Add zerg parallel execution path to Step 2

**Files to create:**
- `scripts/zerg-adapter.sh` -- CLI adapter for zerg interaction

**Changes to /ship Step 2:**
Add new section before the existing worktree path:

```markdown
### Zerg Parallel Path (when ZERG_AVAILABLE=true AND HAS_TASK_GRAPH=true)

Tool: `Bash` (direct -- coordinator does this)

**Pre-validation:**
```bash
bash scripts/zerg-adapter.sh validate ./plans/[name].task-graph.json
```

If validation fails, output error and stop workflow (do NOT fall back silently -- the user chose zerg by providing a task graph with zerg installed).

**Execution:**
```bash
bash scripts/zerg-adapter.sh execute ./plans/[name].task-graph.json --workers ${worker_count:-5}
```

Monitor output. The adapter writes results to `./plans/[name].zerg-results.json`.

**Confirmation prompt (if total_tasks > 5):**
Before execution, output:
"This plan will spawn {N} parallel Claude Code instances. This multiplies API costs by ~{N}x. Continue? [Waiting for user confirmation]"

**After zerg completes:**
- Read `./plans/[name].zerg-results.json`
- If all tasks passed: continue to Step 3 (quality gates)
- If any task failed: output failure details and stop workflow
  Include partial recovery instructions:
  "Some tasks completed successfully. Completed work is in the main directory.
  Failed tasks: [list]. Review output above.
  To retry failed tasks only: [instructions based on P0.0 findings]
  To fall back to built-in worktrees: remove the task-graph.json and re-run /ship."
```

**Steps:**
1. [ ] Create `scripts/zerg-adapter.sh` with detect, validate, execute, status commands
2. [ ] Implement task-graph validation (schema, exclusive ownership, cycle detection)
3. [ ] Implement zerg CLI invocation (based on P0.0 findings)
4. [ ] Implement results parsing and output
5. [ ] Add zerg parallel path to /ship Step 2
6. [ ] Add confirmation prompt for large task graphs
7. [ ] Add error handling and partial recovery instructions
8. [ ] Run: `python3 generators/validate_skill.py skills/ship/SKILL.md`
9. [ ] Manual test: run `/ship` with zerg installed and a task-graph present

#### P1.3: Create generate_zerg_config.py

**Files to create:**
- `generators/generate_zerg_config.py` -- Zerg configuration bootstrapper

**Files to modify:**
- `CLAUDE.md` -- Add to Generator Registry

**Functionality:**
```
Usage:
    python3 generators/generate_zerg_config.py [target-dir] [--workers N] [--mode MODE] [--force]

Creates:
    target-dir/.zerg/config.yaml
    target-dir/.gsd/ (empty directory structure)

Rules:
    - Atomic writes: write to temp file, rename on success
    - Input validation: target-dir exists, --workers is positive int, --mode is valid enum
    - Rollback on failure: clean up .zerg/ and .gsd/ if generation fails partway
    - Target directory: accepts any writable directory (not restricted to ~/workspaces/)
    - Idempotent: does NOT overwrite without --force

Does NOT:
    - Install zerg
    - Run /zerg:init
    - Modify existing config without --force
```

**Steps:**
1. [ ] Create `generators/generate_zerg_config.py` following patterns from `generate_agents.py`
2. [ ] Implement atomic writes (write to temp file, rename on success)
3. [ ] Implement input validation (target-dir exists, --workers positive int, --mode valid enum)
4. [ ] Implement rollback on failure (clean up partial artifacts)
5. [ ] Add auto-detection (reuse `detect_tech_stack()` from `generate_agents.py`)
6. [ ] Generate `.zerg/config.yaml` with worker settings and quality gate references
7. [ ] Create `.gsd/specs/` directory structure
8. [ ] Add `--force` flag for overwrite behavior
9. [ ] Add validation that zerg is installed (`command -v zerg || python3 -c "import zerg"`)
10. [ ] Update CLAUDE.md Generator Registry (add `generate_zerg_config.py` with correct description)
11. [ ] Test: `python3 generators/generate_zerg_config.py /tmp/test-zerg`

#### P1.4: Update test suites

**Files to modify:**
- `generators/test_skill_generator.sh` -- Ensure existing tests pass after /ship and /dream changes

**Files to create:**
- `generators/test_zerg_integration.sh` -- New test suite for zerg integration (standalone, not merged into `test_skill_generator.sh`)

**Test coverage:**
1. /ship SKILL.md validates after changes (strict mode)
2. /dream SKILL.md validates after changes (strict mode)
3. Task-graph.json schema validation via adapter
4. Cycle detection in task graph
5. Exclusive file ownership validation
6. generate_zerg_config.py basic functionality (create, idempotency, --force)
7. Zerg detection logic (both found and not-found paths)
8. Adapter detect command (mock if zerg not installed)

**Steps:**
1. [ ] Verify `test_skill_generator.sh` passes with modified skills
2. [ ] Create `generators/test_zerg_integration.sh` with 8-10 tests
3. [ ] Test task-graph schema validation
4. [ ] Test cycle detection
5. [ ] Test zerg config generation
6. [ ] Test fallback path when zerg is absent

### P2: Polish and Documentation (Week 4-5)

#### P2.1: Add --parallel flag to /ship

**Files to modify:**
- `skills/ship/SKILL.md` -- Add `--parallel` / `--no-parallel` flags to Inputs section

**Routing truth table:**

| `--parallel` flag | ZERG_AVAILABLE | HAS_TASK_GRAPH | Multiple Work Groups | Execution Path |
|---|---|---|---|---|
| `--parallel` | Yes | Yes | Any | Zerg parallel |
| `--parallel` | Yes | No | Any | Error: "task-graph.json required for --parallel" |
| `--parallel` | No | Any | Any | Error: "zerg not installed. Install: pip install zerg-ai" |
| `--no-parallel` | Any | Any | Yes | Built-in worktrees (deprecated) |
| `--no-parallel` | Any | Any | No | Single-coder |
| (not set) | Yes | Yes | Yes | Zerg parallel (auto-detect) |
| (not set) | Yes | No | Yes | Built-in worktrees (deprecated) |
| (not set) | No | Any | Yes | Built-in worktrees (deprecated) |
| (not set) | Any | Any | No | Single-coder |

**Steps:**
1. [ ] Add flag parsing to Inputs section
2. [ ] Update Step 2 routing logic with truth table above
3. [ ] Add clear error messages for invalid flag combinations
4. [ ] Validate skill

#### P2.2: Create zerg tech-stack config

**Files to create:**
- `configs/tech-stack-definitions/zerg.json` -- Zerg-aware agent generation hints

**Steps:**
1. [ ] Create config with zerg-specific quality gates and worker recommendations
2. [ ] Update generate_agents.py to recognize zerg projects (`.zerg/` directory presence)

#### P2.3: Update CLAUDE.md

**Files to modify:**
- `CLAUDE.md` -- Add Zerg Integration section, update registries, update workflows

**Sections to add/update:**
- Skill Registry: Update /ship to v3.2.0, /dream to v2.2.0
- Generator Registry: Add `generate_zerg_config.py` (alias: `gen-zerg-config`)
- Artifact Locations: Add `[feature-name].task-graph.json` and `[feature-name].zerg-results.json`
- Pattern table: Verify header count matches row count (should be 11 after deprecation note)
- New section: "Integration with Zerg" under Integration Patterns
- Update Workflow 1 (Feature Development) to show zerg-enabled path
- Update Troubleshooting with zerg-specific issues
- Update Roadmap: Mark zerg integration as in-progress

**Steps:**
1. [ ] Update Skill Registry table
2. [ ] Update Generator Registry table
3. [ ] Add new artifact types to Artifact Locations section
4. [ ] Add "Integration with Zerg" section
5. [ ] Update Workflow 1 example
6. [ ] Add zerg troubleshooting entries
7. [ ] Update Roadmap

#### P2.4: Update install.sh

**Files to modify:**
- `scripts/install.sh` -- Add optional zerg setup

**Changes:**
- Add `gen-zerg-config` alias for `generate_zerg_config.py` (NOT `gen-zerg` -- follows `gen-<noun>` convention where the noun is what is generated)
- Add post-install message suggesting `pip install zerg-ai` for parallel execution
- Do NOT make zerg a required dependency

**Steps:**
1. [ ] Add alias for `gen-zerg-config`
2. [ ] Add informational message about zerg
3. [ ] Test install.sh on clean shell config

#### P2.5: Add CHANGELOG.md

**Files to create:**
- `CHANGELOG.md` -- Document breaking/notable changes

**Content:**
```markdown
# Changelog

## v1.0.1 (unreleased)

### Skills
- **ship v3.2.0:** Fixed 6 critical bash scripting bugs in worktree isolation.
  Worktree isolation is now deprecated in favor of zerg-ai integration.
- **dream v2.2.0:** Added optional task-graph.json generation for plans with work groups.

### Generators
- **generate_zerg_config.py:** New generator for bootstrapping zerg configuration.

### Scripts
- **zerg-adapter.sh:** New CLI adapter for zerg integration.

### Configs
- **zerg-integration.json:** Default configuration for zerg integration.

### Documentation
- CLAUDE.md: Fixed /dream version discrepancy (was 2.0.0, should be 2.1.0).
- CLAUDE.md: Fixed pattern count header (was "10 patterns", table has 11).
- CLAUDE.md: Added deprecation note to Pattern 11 (Worktree Isolation).
```

**Steps:**
1. [ ] Create `CHANGELOG.md` with the above content
2. [ ] Verify all changes match actual implementation

### P3: Future Work (v1.2+ or post-Swarms evaluation)

#### P3.1: Remove deprecated worktree code (/ship v4.0.0)

**Prerequisites:**
- Zerg integration (P1.2) is deployed and passing end-to-end tests in production
- OR Anthropic Swarms is available as a replacement
- At least 2 weeks of stable operation

**Files to modify:**
- `skills/ship/SKILL.md` -- Remove Steps 2a-2f, remove worktree references from Step 4a, update version to 4.0.0

**Files to delete:**
- `generators/test_ship_worktree.sh` -- Replaced by zerg integration tests

#### P3.2: Add /status-zerg skill

**Note:** Renamed from `/zerg-status` to `/status-zerg` to follow the `[action]-[qualifier]` naming convention (like `test-idempotent`).

#### P3.6: Evaluate Anthropic Swarms integration

**Trigger:** Anthropic ships Swarms to GA

**Steps:**
1. [ ] Evaluate Swarms API surface
2. [ ] Create `scripts/swarms-adapter.sh` implementing same interface as `zerg-adapter.sh`
3. [ ] Test with existing task-graph.json files
4. [ ] If stable: deprecate zerg adapter, promote Swarms adapter
5. [ ] Update `configs/zerg-integration.json` (rename to `parallel-execution.json`)

---

## Acceptance Criteria

### P0 Acceptance

- [ ] `./plans/zerg-evaluation.md` exists with documented zerg capabilities
- [ ] `/ship` SKILL.md worktree isolation code has all 6 critical bugs verified/fixed
- [ ] `/ship` SKILL.md has deprecation warning on worktree path
- [ ] `/ship` SKILL.md version is 3.2.0
- [ ] `/ship` single-coder path works identically to current behavior
- [ ] `/ship` worktree path works correctly (test suite passes)
- [ ] `/ship` pre-flight checks detect zerg installation and log result (informational only)
- [ ] `validate-skill skills/ship/SKILL.md` passes
- [ ] `validate-skill skills/dream/SKILL.md` passes
- [ ] CLAUDE.md `/dream` version corrected to 2.1.0
- [ ] CLAUDE.md `/ship` version updated to 3.2.0
- [ ] CLAUDE.md pattern header count corrected
- [ ] CLAUDE.md Pattern 11 has deprecation note

### P1 Acceptance

- [ ] `scripts/zerg-adapter.sh` exists with detect, validate, execute, status commands
- [ ] Adapter validates task-graph schema, exclusive file ownership, and cycle-free dependencies
- [ ] `/dream` generates `task-graph.json` when plan contains Work Groups
- [ ] `/dream` does NOT generate `task-graph.json` for plans without Work Groups
- [ ] `/ship` executes zerg parallel path when zerg is installed AND task graph exists
- [ ] `/ship` falls back to built-in worktrees when zerg is not installed (with deprecation warning)
- [ ] `/ship` uses single-coder path when no work groups exist
- [ ] `/ship` does NOT silently fall back from zerg to worktrees (explicit error on zerg failure)
- [ ] `generate_zerg_config.py` creates valid `.zerg/config.yaml`
- [ ] `generate_zerg_config.py` uses atomic writes, input validation, and rollback on failure
- [ ] `generate_zerg_config.py` is idempotent (does not overwrite without `--force`)
- [ ] `/ship` zerg path feeds results into existing quality gates (Step 3+)
- [ ] Confirmation prompt shown for task graphs with >5 tasks

### P2 Acceptance

- [ ] `--parallel` / `--no-parallel` flags work per truth table
- [ ] `configs/zerg-integration.json` exists with documented defaults
- [ ] CLAUDE.md updated with zerg integration section, new artifact types, updated registries
- [ ] `install.sh` has `gen-zerg-config` alias (NOT `gen-zerg`)
- [ ] `CHANGELOG.md` exists documenting all changes

---

## Verification

After each phase, run these verification commands:

### After P0:
```bash
# All skill validations pass
python3 generators/validate_skill.py skills/ship/SKILL.md && echo "PASS" || echo "FAIL"
python3 generators/validate_skill.py skills/dream/SKILL.md && echo "PASS" || echo "FAIL"
python3 generators/validate_skill.py skills/audit/SKILL.md && echo "PASS" || echo "FAIL"
python3 generators/validate_skill.py skills/sync/SKILL.md && echo "PASS" || echo "FAIL"

# Existing test suite passes
bash generators/test_skill_generator.sh

# Worktree tests pass (NOT deleted -- still needed)
bash generators/test_ship_worktree.sh

# Zerg evaluation documented
test -f plans/zerg-evaluation.md && echo "PASS" || echo "FAIL"

# CLAUDE.md versions are correct
grep "dream.*2\.1\.0" CLAUDE.md && echo "PASS" || echo "FAIL"
grep "ship.*3\.2\.0" CLAUDE.md && echo "PASS" || echo "FAIL"
```

### After P1:
```bash
# Adapter exists and is executable
test -x scripts/zerg-adapter.sh && echo "PASS" || echo "FAIL"

# Adapter detect works
bash scripts/zerg-adapter.sh detect

# New generator works
python3 generators/generate_zerg_config.py /tmp/test-verify --workers 3
test -f /tmp/test-verify/.zerg/config.yaml && echo "PASS" || echo "FAIL"
rm -rf /tmp/test-verify/.zerg /tmp/test-verify/.gsd

# New test suite passes
bash generators/test_zerg_integration.sh

# Task graph schema validation
bash scripts/zerg-adapter.sh validate plans/test-feature.task-graph.json
```

### After P2:
```bash
# CLAUDE.md mentions zerg integration
grep -c "Integration with Zerg" CLAUDE.md  # Should be > 0

# Install script has gen-zerg-config alias
grep -c "gen-zerg-config" scripts/install.sh  # Should be > 0

# Zerg config exists
test -f configs/zerg-integration.json && echo "PASS" || echo "FAIL"

# CHANGELOG exists
test -f CHANGELOG.md && echo "PASS" || echo "FAIL"

# New artifact types documented
grep "task-graph.json" CLAUDE.md && echo "PASS" || echo "FAIL"
grep "zerg-results.json" CLAUDE.md && echo "PASS" || echo "FAIL"
```

---

## Security Considerations

### Multi-Instance Execution Risks

Running 5-10 parallel Claude Code instances introduces security concerns that must be documented:

**Credential sharing:** All instances authenticate with the same API key/subscription. A prompt injection in any single file read by any worker compromises the credential scope.

**Non-file side effects:** Exclusive file ownership prevents file conflicts but does not prevent:
- Concurrent npm/pip package installations
- Concurrent database migrations
- Modification of shared configuration files (`.env`, `package.json`)
- Arbitrary shell commands affecting shared system state

**Resource exhaustion:** 5-10 Claude Code instances consume significant memory, CPU, and API credits. No built-in guardrails.

**Mitigations (documented in zerg integration docs, P2.3):**
1. Recommend zerg's container mode (`--mode container`) for untrusted codebases.
2. Recommend setting Anthropic API spending limits before enabling parallel execution.
3. Add confirmation prompt in `/ship` when `total_tasks` exceeds 5.
4. Document that zerg workers should NOT invoke `/ship` or other claude-devkit skills recursively.
5. Task-graph `reads` field documents expected file access; workers exceeding this scope should be investigated.

---

## Next Steps

1. **Execute P0.0 and P0.1 in parallel.** P0.0 (evaluate zerg) can run alongside P0.1 (fix worktree bugs). Neither depends on the other.

2. **Execute P0.2 after P0.0 completes.** Zerg detection method depends on evaluation findings.

3. **Execute P0.3 after P0.1 completes.** CLAUDE.md updates reference the new version number.

4. **Gate P1 on P0.0 results.** If P0.0 reveals zerg cannot be invoked via CLI or subprocess, P1 must be redesigned. If P0.0 reveals Anthropic Swarms is imminent, consider deferring P1 entirely.

5. **Execute P1 as a work unit** once P0 is complete and gate is passed. P1.1 and P1.3 can start in parallel. P1.2 depends on P1.1. P1.4 depends on P1.2.

6. **P2 can be done opportunistically** -- documentation and polish tasks that don't block anyone.

7. **P3 items are conditional** -- they depend on zerg proving stable in production AND Anthropic not shipping native Swarms.

**Who executes:**
- P0.0: Manual (developer installs and evaluates zerg)
- P0.1: `/ship` or manual edit (straightforward bug verification/fixes)
- P0.2-P0.3: `/ship` with careful plan review
- P1.1: `/ship` (standard skill modification)
- P1.2: Manual implementation (adapter requires testing against real zerg CLI)
- P1.3: `/ship` (standard generator pattern exists to follow)
- P1.4: Manual (test authoring)
- P2.*: `/ship` or `/sync` as appropriate

---

## Plan Metadata

- **Plan File:** `./plans/zerg-adoption-priorities.md`
- **Revision:** 2
- **Affected Components:** skills/ship, skills/dream, generators/, configs/, scripts/, CLAUDE.md
- **Validation:** `python3 generators/validate_skill.py skills/ship/SKILL.md && python3 generators/validate_skill.py skills/dream/SKILL.md && bash generators/test_skill_generator.sh`
- **New Artifacts:** `./plans/zerg-evaluation.md`, `scripts/zerg-adapter.sh`, `generators/generate_zerg_config.py`, `configs/zerg-integration.json`, `CHANGELOG.md`
- **New Artifact Types (for CLAUDE.md):** `[feature-name].task-graph.json`, `[feature-name].zerg-results.json`

---

## Sources

- [ZERG GitHub Repository](https://github.com/rocklambros/zerg)
- [ZERG Official Website](https://zerg-ai.com/)
- [Behold the Zerg! Parallel Claude Code Orchestration](https://www.rockcybermusings.com/p/behold-zerg-parallel-claude-code-orchestration)

---

## Appendix: Review Findings Resolution Matrix

This appendix maps every Critical and Major finding from all three reviews to its resolution in this revision.

### Red Team Findings

| # | Finding | Severity | Resolution |
|---|---------|----------|------------|
| F1 | Python API does not exist | Critical | Redesigned integration around CLI/subprocess adapter (`scripts/zerg-adapter.sh`). P0.0 evaluates actual interface first. |
| F2 | Task-graph schema is invented | Critical | Schema explicitly declared as claude-devkit-defined contract. Adapter translates to zerg native format. `$schema` renamed to `claude-devkit-task-graph-v1`. |
| F3 | Capabilities gap between deletion and replacement | Major | Reversed: fix bugs first (P0.1), deprecate, replace only after zerg proven (P3.1). |
| F4 | No security analysis of multi-instance execution | Major | Added "Security Considerations" section with STRIDE-aligned mitigations. |
| F5 | No rollback plan | Major | Added "Rollback Plan" section with four scenarios. |
| F6 | Vendor risk understated | Major | Vendor risk assessment added with HIGH rating. R1 probability upgraded to High. R2 (abandonment) added. |
| F7 | Anthropic Swarms not evaluated | Major | Added "Anthropic Swarms Evaluation" section. Adapter designed for swappability. P3.6 added. |
| F8 | No cycle detection or deadlock handling | Major | Cycle detection added to adapter validate command. Per-task `timeout_seconds` added to schema. Partial failure recovery instructions added. |
| F9 | `pip show` detection fragile | Minor | Adapter uses multi-method detection (`command -v zerg`, then `python3 -c "import zerg"`). |
| F10 | Critical tests are manual-only | Minor | Adapter-based tests (validate, detect) are automated. E2E tests remain manual (acceptable). |
| F11 | `git reset --soft HEAD~1` removal buried | Minor | No longer applicable -- worktree code is being fixed, not removed. The `git reset` stays as part of the worktree flow. |
| F12 | No data classification for task graphs | Minor | Noted in security considerations. Task graphs treated same as plan files. |
| F13 | No cost controls | Info | Confirmation prompt added for large task graphs. Cost documentation in P2.3. |

### Librarian Findings

| # | Finding | Resolution |
|---|---------|------------|
| Conflict 1 | `/dream` version mismatch (CLAUDE.md says 2.0.0, SKILL.md says 2.1.0) | P0.3 reconciles CLAUDE.md to 2.1.0 before P1.1 bumps to 2.2.0. |
| Conflict 2 | Pattern 11 removal without pattern version bump | Pattern 11 is now deprecated with a note, not removed. Header count fixed to 11. |
| Conflict 3 | New artifact types not in Artifact Locations | P2.3 scope now explicitly includes `task-graph.json` and `zerg-results.json` in Artifact Locations. |
| Conflict 4 | Generator missing atomic writes/rollback spec | P1.3 task steps now explicitly require atomic writes, input validation, and rollback on failure. |
| Conflict 5 | `gen-zerg` alias naming | Changed to `gen-zerg-config` to follow `gen-<noun>` convention. |
| Conflict 6 | No CHANGELOG for breaking change | P2.5 adds CHANGELOG.md. Also, this is no longer a breaking change (v3.2.0, not v4.0.0). |
| Conflict 7 | `/zerg-status` skill naming | Renamed to `/status-zerg` following `[action]-[qualifier]` pattern. |
| F1 | CLAUDE.md `/dream` at 2.0.0 vs actual 2.1.0 | Fixed in P0.3. |
| F2 | "10 patterns" header with 11 rows | Fixed in P0.3. |
| F3 | `plans/ship-v3.1-code-review.md` location | Corrected reference to `plans/archive/ship-v3.1/ship-v3.1.code-review.md`. |

### Feasibility Findings

| # | Finding | Resolution |
|---|---------|------------|
| C1 | Zerg Python API unverified | P0.0 evaluation task added as prerequisite. P1 gated on results. |
| C2 | Task-graph schema invented | Explicitly declared as claude-devkit contract with adapter translation. |
| M1 | `/dream` version discrepancy | P0.3 reconciles before v2.2.0 bump. |
| M2 | "never passed integration test" claim inaccurate | Revised: acknowledged test suite exists (847 lines, 6 scenarios). |
| M3 | P0.1 step 4 ambiguous about `git reset` removal | No longer applicable -- `git reset` stays as part of worktree flow. |
| M4 | Pattern 11 deletion loses documentation | Pattern 11 deprecated with note, not deleted. |
| M5 | Generator path validation differs from existing generators | Explicitly documented: accepts any writable directory, with rationale. |
| M6 | Test coverage gaps | Adapter-based tests added. Strict mode validation added. |
