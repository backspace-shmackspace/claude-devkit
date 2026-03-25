# Red Team Review (Revision 2): Zerg Adoption Priorities for Claude-Devkit

**Reviewed:** 2026-02-23
**Reviewer:** Security Analyst (Red Team)
**Scope:** Revised plan at `./plans/zerg-adoption-priorities.md` (Revision 2)
**Method:** Finding-by-finding resolution verification, new risk identification, STRIDE re-assessment
**Previous Verdict:** FAIL (2 Critical, 6 Major, 3 Minor, 1 Info)

---

## Verdict: PASS

The revision substantively addresses both Critical findings and all six Major findings. The plan has been restructured around a defensible strategy: fix what is broken first, evaluate zerg before integrating, use a thin adapter for loose coupling, and preserve the fallback path until the replacement is proven. The remaining concerns are Minor-level design choices, not blocking issues.

---

## Resolved Findings

### F1: Python API Does Not Exist -- RESOLVED

**Original:** The plan's integration architecture was built around `from zerg import ZERGOrchestrator, TaskGraph, WorkerPool` -- classes that do not exist in zerg's codebase.

**Resolution:** The revised plan completely abandons the Python API assumption. Key changes:

1. Assumption 4 is rewritten: "The integration point is CLI/subprocess invocation (`zerg rush`, `zerg status`, etc.), NOT a Python import."
2. The integration is now a shell script adapter (`scripts/zerg-adapter.sh`) with four commands: `detect`, `validate`, `execute`, `status`.
3. P0.0 (Evaluate zerg capabilities) is added as a new prerequisite task that must complete before any integration work begins. This task explicitly checks what zerg actually provides (CLI commands, output formats, whether a Python API exists).
4. All P1 tasks are gated on P0.0 results. The plan states: "If P0.0 reveals that zerg cannot be invoked via CLI or subprocess, P1 must be redesigned."

This is a strong resolution. The plan no longer assumes an interface; it discovers the interface first and builds around it.

### F2: Task-Graph Schema Is Invented, Not Verified -- RESOLVED

**Original:** The plan defined a task-graph.json schema and presented it as "the contract" without verifying it matches zerg's native format.

**Resolution:** The revised plan takes a fundamentally different approach:

1. The schema is now explicitly declared as a "claude-devkit-defined contract" -- not an attempt to match zerg's native format.
2. The `$schema` field was renamed from `task-graph-v1` to `claude-devkit-task-graph-v1` to make ownership unambiguous.
3. The zerg adapter is responsible for translating this format to whatever zerg expects at execution time.
4. P0.0 includes inspecting zerg's actual output formats, which will inform the adapter's translation logic.

This is a clean architectural decision. By owning the schema and using an adapter for translation, the plan eliminates the schema drift risk. If zerg's format changes, only the adapter changes.

### F3: Capabilities Gap Between Deletion and Replacement -- RESOLVED

**Original:** P0.1 deleted worktree code before the zerg replacement existed, creating a gap where parallel execution was unavailable.

**Resolution:** The strategy is reversed entirely:

1. P0.1 is now "Fix 6 critical bash bugs" instead of "Delete worktree code."
2. The plan adds a "Worktree Decision" section with the explicit policy: "Fix the 6 critical bash bugs. Mark the code as deprecated. Replace only after zerg integration is proven end-to-end."
3. Removal is deferred to P3.1, conditional on zerg passing end-to-end tests AND at least 2 weeks of stable operation.
4. The Non-Goals section explicitly states: "Delete working code before the replacement is proven."

This eliminates the capabilities gap entirely.

### F4: No Security Analysis of Parallel Instances -- RESOLVED

**Original:** The plan proposed running 5-10 parallel Claude Code instances with zero security analysis.

**Resolution:** A "Security Considerations" section has been added (lines 1209-1231) covering:

1. **Credential sharing:** Documents that all instances share the same API key and a prompt injection in any worker compromises the credential scope.
2. **Non-file side effects:** Lists specific risks (concurrent package installations, database migrations, shared config modification, arbitrary shell commands).
3. **Resource exhaustion:** Acknowledges the resource cost of 5-10 instances.
4. **Mitigations:** Container mode for untrusted codebases, API spending limits, confirmation prompt for large task graphs (>5 workers), prohibition on recursive `/ship` invocation.
5. Risk R8 is added to the risk table covering multi-instance security.

The analysis is adequate for a plan-level document. One note: the mitigation of "recommend container mode for untrusted codebases" relies on a zerg feature that has not been verified in P0.0. This is a minor gap -- the plan correctly frames it as a recommendation, not a guarantee.

### F5: No Rollback Plan -- RESOLVED

**Original:** No strategy existed for reverting if zerg integration failed.

**Resolution:** A dedicated "Rollback Plan" section (lines 563-579) covers four distinct scenarios:

1. P0.0 reveals zerg is not viable -- stop, zero impact.
2. P1.2 fails during implementation -- revert P1.2, keep task-graph generation and generator.
3. Zerg is deployed then later abandoned -- remove adapter, promote worktree code from deprecated to primary.
4. Anthropic ships native Swarms -- create new adapter, deprecate zerg adapter.

Each scenario has a clear action, estimated effort, and impact assessment. The rollback paths are credible because the worktree code is preserved.

### F6: Vendor Risk Understated -- RESOLVED

**Original:** R1 (breaking API changes) was rated Medium probability for a pre-1.0 project with 25 stars and a single maintainer.

**Resolution:**

1. A dedicated "Vendor Risk Assessment" table (lines 139-151) rates all key factors, with 6 of 8 factors rated High risk.
2. Overall vendor risk is explicitly stated as "HIGH."
3. R1 probability is upgraded to High.
4. R2 (project abandoned) is added with High probability.
5. Three design decisions are driven by this assessment: zerg is never required, integration is a thin adapter, worktree code stays as fallback.
6. Competing solutions are listed (Conductor, Gas Town, Vibe Kanban, Anthropic Swarms).

The risk assessment is now appropriately calibrated for the dependency's maturity level.

### F7: Anthropic Swarms Not Evaluated -- RESOLVED

**Original:** The plan ignored Anthropic's native multi-agent orchestration feature entirely.

**Resolution:** An "Anthropic Swarms Evaluation" section (lines 157-168) addresses this:

1. Acknowledges Swarms has been observed behind feature flags.
2. States the design implication: the adapter layer must define a generic `ParallelExecutor` interface that is swappable.
3. Defines a monitoring plan: track Anthropic's changelog and release notes.
4. Adds a pivot trigger: "If Swarms ships to GA before zerg integration reaches P2, pivot to native integration and skip zerg entirely."
5. P3.6 explicitly covers Swarms adapter creation if Swarms ships.

The plan now has a credible strategy for the most likely competitive scenario.

### F8: No Cycle Detection, Deadlock Handling, or Partial Failure Recovery -- RESOLVED

**Original:** The task graph had no validation for circular dependencies, no per-task timeouts, and no recovery from partial failures.

**Resolution:**

1. **Cycle detection:** The adapter's `validate` command includes cycle detection in the dependency graph (lines 383, 475, 551).
2. **Per-task timeouts:** `timeout_seconds` field added to the task-graph schema (lines 425, 433, 449, 475).
3. **Partial failure recovery:** The `/ship` zerg path includes explicit recovery instructions (lines 868-873): which tasks completed, which failed, how to retry, and how to fall back to worktrees.
4. R4 in the risk table now lists "schema check, exclusive file ownership, and cycle detection" as mitigations.

The automated cycle detection test (lines 607-633) is a good addition -- it creates a task graph with circular dependencies and verifies the adapter rejects it.

---

## Remaining Findings

### F9 (Minor): pip Detection Fragile -- RESOLVED

The adapter now uses multi-method detection: `command -v zerg` first, then `python3 -c "import zerg"` as fallback (line 383, Risk R9). This handles virtualenvs, pip/pip3 confusion, and CLI-first vs. library-first installations.

### F10 (Minor): Critical Tests Manual-Only -- PARTIALLY RESOLVED

The revision adds automated adapter tests (detect, validate, cycle detection) and a proper test matrix. End-to-end tests (scenarios 5 and 7 in the test matrix) remain manual, which is acceptable given they require a live Claude Code session and zerg installation. The automated coverage is now adequate for the adapter layer, which is where regressions are most likely.

### F11 (Minor): git reset --soft HEAD~1 Removal Buried -- RESOLVED (No Longer Applicable)

Since the worktree code is being fixed rather than removed, the `git reset` stays as part of the worktree flow. The finding is moot.

### F12 (Minor): No Data Classification for Task Graphs -- PARTIALLY RESOLVED

The security considerations section notes that task graphs should be "treated same as plan files" (line 1300). This is adequate -- plan files already have an established handling pattern in the artifact locations and `.gitignore` recommendations.

### F13 (Info): No Cost Controls -- RESOLVED

Confirmation prompt added for large task graphs (>5 tasks), cost documentation planned for P2.3 (lines 861-863, 1229).

---

## New Findings

### N1: Adapter Shell Script Has No Input Sanitization Specification

**Severity: Minor**

The `zerg-adapter.sh` design (lines 357-390) accepts file paths as arguments (`scripts/zerg-adapter.sh validate ./plans/[name].task-graph.json`). The plan does not specify input sanitization for these paths. A task-graph filename containing shell metacharacters (spaces, semicolons, backticks) could cause unexpected behavior in a shell script.

This is unlikely in practice because `/dream` controls the filename generation, but the adapter should validate that its arguments are well-formed paths before processing them.

**Recommendation:** Add a note to P1.2 that the adapter must quote all file path arguments and reject paths containing shell metacharacters.

### N2: No Specification for Adapter Exit Codes

**Severity: Minor**

The adapter defines four commands (detect, validate, execute, status) but does not specify exit codes. `/ship` needs to branch on the adapter's result, so the contract between the skill and the adapter must include:

- `detect`: exit 0 with version string on stdout, or exit 1 with "not-found" on stdout
- `validate`: exit 0 for PASS, exit 1 for FAIL with reason on stderr
- `execute`: exit 0 for success, exit 1 for failure with details on stderr
- `status`: exit 0 for running/complete, exit 1 for error

Without this specification, the `/ship` skill cannot reliably interpret adapter results.

**Recommendation:** Add exit code specifications to the adapter interface design in the plan.

### N3: P0.1 Bug Verification May Be Optimistic

**Severity: Minor**

P0.1 (lines 699-740) states that "Review of the actual v3.1.0 SKILL.md shows that many of the code review's critical bugs were already addressed." The task then reduces to "verify all 6 fixes are correctly implemented."

There is a risk that the verification is superficial -- reading the SKILL.md and confirming the text looks correct is not the same as running the worktree isolation and confirming the bash commands execute correctly. The plan's test commands (line 737, `bash generators/test_ship_worktree.sh`) mitigate this, but only if the test suite covers the specific bugs. The plan notes the tests "use simulation rather than live execution" (line 120), which means they may not catch all bash scripting errors.

**Recommendation:** After P0.1, manually run `/ship` with a multi-work-group plan on a test repository to verify the worktree flow works end-to-end, in addition to the automated tests.

### N4: Zerg Adapter as Shell Script May Limit Validation Capabilities

**Severity: Info**

The plan places cycle detection and schema validation in a shell script (`scripts/zerg-adapter.sh`). Implementing topological sort and JSON schema validation in pure bash is non-trivial and error-prone. The plan's test for cycle detection (lines 607-633) creates the test fixture with Python but expects bash to detect the cycle.

In practice, the adapter will likely need to call `python3` or `jq` internally for JSON parsing and graph validation. This is fine, but it means the "shell script" is really a shell script that delegates to Python -- which is slightly at odds with the stated rationale of avoiding "fragile quoting of multi-line Python inside Bash tool invocations."

**Recommendation:** Consider whether `scripts/zerg-adapter.py` would be more natural, given the JSON parsing and graph validation requirements. If the shell script wraps Python anyway, the indirection adds complexity without benefit. This is a design preference, not a blocking issue.

---

## Overall Assessment

The revision is thorough and well-structured. Every Critical and Major finding from the original review has been addressed with substantive changes, not superficial acknowledgments. The key improvements are:

1. **Evaluate before integrating** (P0.0 as a gate for P1) -- this was the single most important change and it is well-executed.
2. **Fix before replacing** (P0.1 fixes bugs instead of deleting code) -- eliminates the capabilities gap risk entirely.
3. **Own the schema, adapt at the boundary** (claude-devkit-defined task-graph with adapter translation) -- clean architectural decision that avoids schema coupling.
4. **Honest vendor risk assessment** (HIGH rating with three design mitigations) -- appropriately calibrated for a 16-day-old pre-1.0 project.
5. **Swappable adapter design** (zerg today, Swarms tomorrow) -- the most strategically important decision in the plan.
6. **Explicit rollback paths** for four distinct failure scenarios -- no ambiguity about what happens if things go wrong.

The remaining new findings (N1-N4) are Minor/Info-level design details that can be addressed during implementation without plan revision.

---

## Findings Summary

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| F1 | Python API does not exist | Critical | RESOLVED -- redesigned around CLI adapter |
| F2 | Task-graph schema invented | Critical | RESOLVED -- owned schema with adapter translation |
| F3 | Capabilities gap | Major | RESOLVED -- fix first, deprecate, replace when proven |
| F4 | No security analysis | Major | RESOLVED -- Security Considerations section added |
| F5 | No rollback plan | Major | RESOLVED -- four-scenario rollback plan added |
| F6 | Vendor risk understated | Major | RESOLVED -- HIGH rating, three design mitigations |
| F7 | Swarms not evaluated | Major | RESOLVED -- evaluation section, swappable adapter, P3.6 |
| F8 | No cycle detection / deadlock handling | Major | RESOLVED -- cycle detection, timeouts, partial recovery |
| F9 | pip detection fragile | Minor | RESOLVED -- multi-method detection |
| F10 | Critical tests manual-only | Minor | PARTIALLY RESOLVED -- acceptable for E2E scope |
| F11 | git reset buried | Minor | RESOLVED -- no longer applicable |
| F12 | No data classification | Minor | PARTIALLY RESOLVED -- adequate for plan level |
| F13 | No cost controls | Info | RESOLVED -- confirmation prompt, documentation |
| N1 | Adapter input sanitization unspecified | Minor | NEW |
| N2 | Adapter exit codes unspecified | Minor | NEW |
| N3 | P0.1 bug verification may be optimistic | Minor | NEW |
| N4 | Shell script may be suboptimal for JSON/graph validation | Info | NEW |

---

**Reviewed by:** Security Analyst (Red Team)
**Review timestamp:** 2026-02-23T16:00:00Z
**Plan reviewed:** `./plans/zerg-adoption-priorities.md` (Revision 2)
**Previous review:** `./plans/zerg-adoption-priorities.redteam.md` (Revision 1, 2026-02-23T14:30:00Z)
