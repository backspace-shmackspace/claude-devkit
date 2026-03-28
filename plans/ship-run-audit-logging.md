# Plan: Ship Run Audit Logging -- Structured Event Trail for Agent Accountability

## Revision Log

| Rev | Date | Trigger | Summary |
|-----|------|---------|---------|
| 2 | 2026-03-27 | Red team FAIL + feasibility critical findings + librarian required edits | (1) Replace inline bash function with standalone `scripts/emit-audit-event.sh` helper script to fix shell state persistence across Bash tool calls (RT-F4, FS-C1). (2) Replace `_audit_escape` with `python3 json.dumps()` for RFC 8259 compliance (RT-F3, FS-C2). (3) Persist L3 HMAC key to disk with restricted permissions for post-run chain verification (RT-F1, FS-M1). (4) Drop `duration_ms` from per-event schema; compute in query utility from timestamp pairs (FS-M2). (5) Derive sequence counter from log file line count (FS-M3). (6) Add `security_decision` event verification in Step 6 (RT-F2). (7) Honest OTel migration assessment -- adapter requires span hierarchy reconstruction, not trivial field rename (RT-F5). (8) Librarian fixes: add `agentic-sdlc-next-phase.md` and `agentic-sdlc-security-skills.md` to context references, fix hardcoded `skill_version` to 3.6.0, add `ship-always-worktree.md` to prior plans. |
| 1 | 2026-03-27 | Initial draft | File-based JSONL audit logging for /ship with OTel-forward design and security maturity level awareness |

## Context

Red Hat's corporate mandate for AI-first SDLC requires proving what agents did what and when in the codebase. As AI-assisted development scales beyond individual contributors — via the Josh Boyer/Kevin Myers governance proposal (CNCF model: Sandbox → Incubating → Graduated) and Marek Baluch's "Agentic Operating System" workstreams — engineering leads need visibility into agent actions. This is a development process accountability requirement, not a product compliance requirement (CRA applies to products with digital elements, not build tooling).

Today, `/ship` generates markdown artifacts (code reviews, QA reports, test logs) and commits them, but there is no structured, machine-parseable record of the run itself: which steps executed, what verdicts were reached, what files were modified, whether security overrides were used. This gap means:

1. **No provenance chain** -- Cannot prove which agent modified which file or when.
2. **No override accountability** -- `--security-override` reasons appear only in commit messages, not queryable.
3. **No step-level visibility** -- Cannot determine which steps completed or failed.
4. **No governance readiness** -- When corporate AI tooling controls land (Kagenti, MCP Gateway), there is no structured event stream to integrate with.

**Platform trajectory:** Red Hat's Kagenti platform (OpenShift operator with SPIFFE/SPIRE identity injection, OTel tracing, and MCP Gateway tool governance) is in development. When available, audit events should emit as OTel spans rather than (or in addition to) files. The design must make this transition straightforward, while being honest that a format adapter alone is insufficient -- the migration requires span hierarchy reconstruction (see OTel Migration section).

**Proven pattern:** The `risk-orchestrator` project already uses HMAC-SHA256 event-sourced audit trails. This plan borrows the integrity verification approach for L3 maturity, with the key persisted to disk for post-run verification.

**Current skill versions:**
- `skills/ship/SKILL.md` -- v3.5.0
- `skills/architect/SKILL.md` -- v3.1.0
- `skills/audit/SKILL.md` -- v3.1.0

**Parent plans:**
- `plans/security-guardrails-phase-b.md` (Status: APPROVED) -- established security maturity levels L1/L2/L3 and `--security-override` in `/ship`
- `plans/agentic-sdlc-security-skills.md` (Status: APPROVED) -- standalone security skills
- `plans/devkit-hygiene-improvements.md` (Status: APPROVED) -- test infrastructure
- `plans/agentic-sdlc-next-phase.md` (Status: APPROVED) -- validate-all.sh, expanded test suite, quality infrastructure patterns
- `plans/ship-always-worktree.md` (Status: APPROVED) -- unified worktree isolation model; Step 3 sub-steps (3a-3f) depend on this plan's worktree structure

## Architectural Analysis

### Key Drivers

1. **AI governance readiness** -- Corporate AI tooling controls are coming (Kagenti, MCP Gateway, governance proposal). File-based logs provide the immediate accountability trail; OTel emission provides the future integration path when platform infrastructure arrives.
2. **Zero infrastructure dependency** -- Must work today with nothing more than `bash`, `python3`, and the filesystem. No databases, no message queues, no external services.
3. **LLM-executable** -- The "runtime" is a Claude Code LLM reading a SKILL.md prompt and executing bash blocks. Each `Tool: Bash` invocation spawns a fresh shell process -- functions and variables do not persist between calls. Audit logging must use a standalone helper script invoked as a one-liner in each step.
4. **OTel-forward field design** -- JSONL fields must map to OTel span attributes. The migration to OTel spans requires a format adapter with span hierarchy reconstruction (not a trivial field rename).
5. **Maturity-aware retention** -- L1 logs are informational (gitignored), L2 logs are retained (committed), L3 logs are tamper-evident (HMAC chain with persisted key).
6. **Machine parseability** -- JSONL format enables `jq`, `grep`, and future ingestion tooling without custom parsers.

### Trade-offs

| Decision | Option A | Option B | Choice | Rationale |
|----------|----------|----------|--------|-----------|
| Log format | Structured markdown (consistent with existing artifacts) | JSONL (machine-parseable, OTel-mappable) | **Option B** | Markdown artifacts already exist for human review. The audit log serves a different purpose: machine consumption, compliance queries, and future OTel emission. JSONL is the standard for structured log streams. |
| Log location | `plans/archive/[name]/` (alongside other artifacts) | `plans/audit-logs/` (dedicated directory) | **Option B** | Audit logs have different lifecycle than review artifacts. They should be queryable across runs (`jq` over `plans/audit-logs/*.jsonl`), not buried inside per-feature archive directories. |
| Event emission mechanism | Inline bash function defined at Step 0 | Standalone helper script (`scripts/emit-audit-event.sh`) | **Option B** | Shell state (functions, variables) does not persist between Bash tool calls in Claude Code. An inline function defined in Step 0 is undefined in Steps 1-7. A standalone script reads state from files on disk and is invocable as a one-liner from any step. |
| Integrity verification (L3) | GPG signatures per event | HMAC-SHA256 chain with key persisted to disk | **Option B** | GPG requires key management infrastructure that contradicts the "zero infrastructure" requirement. HMAC-SHA256 chain is proven in risk-orchestrator, requires only `openssl` (available on all target platforms). The key is persisted to a restricted-permission file alongside the log for post-run verification. |
| L3 key management | Ephemeral key (lost with shell session) | Key persisted to disk (mode 0600) | **Option B** | An ephemeral key makes the HMAC chain unverifiable after the run ends, which defeats the purpose of L3 tamper evidence. Persisting the key to a restricted-permission file allows post-run verification. This is not tamper-proof against root, but is sufficient for developer-level non-repudiation. Kagenti/OTel will provide proper signing for adversarial environments. |
| JSON escaping | Bash string substitution (`_audit_escape`) | `python3 -c "import json; json.dumps(...)"` | **Option B** | Bash string substitution misses carriage returns, form feeds, and RFC 8259 control characters (0x00-0x1F). `python3 json.dumps()` handles all escaping requirements correctly. `python3` is already a dependency (used in Step 0 security maturity check). |
| Duration tracking | `duration_ms` field on `step_end` events | Compute duration in query utility from timestamp pairs | **Option B** | Computing duration requires persisting a start timestamp across Bash tool calls. Since shell state does not persist, this is unreliable. The query utility can compute duration from `step_start` and `step_end` timestamp pairs using `jq`. |
| Sequence counter | Shell variable incremented in memory | Derived from `wc -l` of the log file | **Option B** | Shell variables do not persist across Bash tool calls. Deriving the sequence from the log file line count is stateless and self-consistent. |
| L1 log retention | Committed to git | Gitignored (untracked) | **Gitignored** | L1 is advisory. Committing informational logs to every project's git history adds noise. L1 logs exist during the run for debugging. Teams that want retention upgrade to L2. |
| When to create the log file | Lazily on first event | Eagerly at run start (Step 0) | **Eagerly** | An empty or missing log file after a run indicates a crash or bug. Creating it at Step 0 with a `run_start` event provides a reliable anchor. |

### Requirements

- All events are appended to a single JSONL file per run
- The JSONL file path is deterministic from the run ID: `plans/audit-logs/ship-${RUN_ID}.jsonl`
- Every event includes: `run_id`, `timestamp`, `event_type`, `skill`, `skill_version`, `security_maturity`, `sequence`
- Step events include: `step`, `step_name`, `verdict` (where applicable)
- File modification events include: `files_modified` array
- Security events include: `security_maturity`, `override_reason` (where applicable)
- L3 events include: `hmac` field (HMAC-SHA256 of event + previous HMAC, forming a hash chain)
- The `emit-audit-event.sh` helper script is invoked as a one-liner in each step
- Per-run state (run_id, HMAC key, log path) is stored in a state file on disk
- Sequence counter is derived from `wc -l` of the log file (stateless)
- All field names map to OTel conventions documented in the schema section

## Goals

1. **Define the JSONL audit event schema** with OTel-forward field naming
2. **Implement `scripts/emit-audit-event.sh`** standalone helper script for event emission
3. **Instrument every `/ship` step** with event emission (step_start, step_end, verdict, security decisions)
4. **Implement maturity-aware retention**: L1 gitignored, L2 committed, L3 HMAC chain with persisted key
5. **Add audit log finalization** in Step 6 (commit gate) with security_decision event verification
6. **Provide a `scripts/audit-log-query.sh`** utility for querying logs with `jq`
7. **Instrument `/architect` and `/audit`** with the same pattern (lighter touch -- fewer steps, same schema)
8. **Document the OTel migration path** including span hierarchy reconstruction requirements

## Non-Goals

- OTel span emission (requires Kagenti -- future work)
- SPIFFE/SPIRE identity injection (requires Kagenti -- future work)
- MCP Gateway integration (requires platform -- future work)
- Splunk or SIEM integration (corporate infra team scope, contingent on Kagenti)
- Real-time log streaming or monitoring dashboards
- Modifying security skills themselves (they are invoked by /ship, not instrumented independently)
- Agent behavioral testing of the logging (cannot test LLM prompt compliance in CI)
- Log rotation or retention policies beyond git (operational concern)

## Assumptions

1. `openssl` is available on all target platforms (macOS ships with LibreSSL, Linux with OpenSSL) -- needed for L3 HMAC
2. `python3` is available on all target platforms -- already a dependency for security maturity checks in Step 0 and for generators
3. `jq` is available for log querying (not required for emission, only for the query utility)
4. `date` supports `+%s%N` for nanosecond timestamps on Linux; macOS `date` does not, so we fall back to `+%s000000000` (second precision with zero-padded nanos). ISO 8601 timestamps in events use second precision on all platforms.
5. The LLM executing `/ship` will faithfully execute the bash blocks including `emit-audit-event.sh` calls
6. `/ship` v3.5.0 is the current version and the base for modifications (confirmed from source)
7. The `plans/audit-logs/` directory does not currently exist and must be created
8. `plans/audit-logs/*.jsonl` is added to `.gitignore`; L2/L3 use `git add --force` to override

## Security Requirements

### Assets at Risk

| Asset | Classification | Description |
|-------|---------------|-------------|
| Audit log files | **Internal** | Contain step progression, verdicts, file paths, timing data. No secrets or code content. |
| HMAC keys (L3) | **Confidential** | Per-run keys used for hash chain integrity. Derived from `/dev/urandom`, persisted to a restricted-permission file (`mode 0600`) alongside the log. Committed to git at L3 (accepted trade-off: tamper detection, not prevention). |
| Security override reasons | **Internal** | Free-text justifications for `--security-override`. May contain context about why a security finding was dismissed. |
| File modification lists | **Internal** | Paths of files created/modified during a run. Reveal codebase structure but not content. |
| Audit state files | **Internal** | Per-run state (run_id, log path, skill version, maturity level, HMAC key at L3). Deleted after run completion. |

### Trust Boundaries

```
+-----------------------------------+
|  Claude Code LLM (executor)       |  <-- Trust boundary 1: LLM faithfully
|  Reads SKILL.md, executes bash    |      executes the prompt. Cannot be
|  blocks including helper script   |      cryptographically verified today.
+-----------------------------------+
         |
         v (invokes helper script, writes to filesystem)
+-----------------------------------+
|  Local filesystem                 |  <-- Trust boundary 2: File integrity.
|  plans/audit-logs/*.jsonl         |      L1/L2: no integrity guarantee.
|  State files (ephemeral)          |      L3: HMAC chain with persisted key
|  Committed to git (L2/L3)         |      provides tamper detection (not
+-----------------------------------+      prevention) post-run.
         |
         v (future: emit to OTel)
+-----------------------------------+
|  Kagenti / OTel Collector         |  <-- Trust boundary 3: Platform-managed.
|  SPIFFE identity, signed spans    |      Outside scope of this plan.
+-----------------------------------+
```

### STRIDE Analysis

| Threat | Category | Risk | Mitigation |
|--------|----------|------|------------|
| LLM omits audit events (prompt injection, hallucination) | **Spoofing / Repudiation** | High (residual) | Detective control only -- cannot prevent in LLM-executed prompts. Mitigation: (1) Step 6 verifies log file exists, (2) Step 6 validates minimum event count against expected step count, (3) Step 6 verifies `security_decision` events exist when security gates ran, (4) future Kagenti OTel sidecars provide independent observation. Residual risk is High because this is a detective, not preventive, control. |
| Attacker modifies JSONL after write | **Tampering** | Medium (L1/L2), Medium (L3) | L3: HMAC-SHA256 hash chain with persisted key makes tampering detectable post-run. Key file has mode 0600. An attacker with filesystem access could modify both the log and the key file simultaneously -- L3 provides tamper *detection* for uncoordinated modifications, not tamper *prevention*. L1/L2: git commit history provides some protection (L2 commits logs). L1: no protection (ephemeral). |
| No record of agent actions | **Repudiation** | High (current), Medium (with this plan) | This plan provides structured event trails. L3 HMAC chain provides tamper detection for post-run modifications. Residual risk is Medium (not Low) because the LLM self-reports -- there is no independent observer until Kagenti. |
| Audit logs leak file paths or override reasons | **Information Disclosure** | Low | Audit logs contain paths and override text, classified as Internal. No secrets or code content. Logs committed to the project repo inherit the repo's access controls. |
| Excessive logging slows /ship execution | **Denial of Service** | Low | Each `emit-audit-event.sh` invocation is a short bash script execution (sub-second). Even 50 events per run adds negligible I/O. |
| Attacker escalates by modifying SKILL.md to skip logging | **Elevation of Privilege** | Low | SKILL.md is version-controlled. Tampering requires repo write access, which already grants full code modification. Audit logs are a detection control, not a prevention control. |
| Symlink attack on predictable audit log path | **Tampering** | Low | An attacker with repo write access could pre-create a symlink at the log path pointing to a sensitive file. Mitigation: the helper script checks that `$AUDIT_LOG` is not a symlink before writing. |

### Failure Modes

| Condition | Behavior | Detection |
|-----------|----------|-----------|
| `openssl` not available | L3 HMAC fields are empty strings; log is otherwise intact | Step 6 verification warns if L3 events lack non-empty `hmac` |
| `python3` not available | JSON escaping falls back to raw string (risk of invalid JSON) | Step 6 verification catches lines that are not valid JSON |
| `/dev/urandom` not readable | L3 HMAC key generation fails; `AUDIT_HMAC_KEY` is empty | Step 6 verification warns if L3 events lack non-empty `hmac` |
| Audit log directory not writable | `emit-audit-event.sh` fails silently (exit 0 regardless) | Step 6 reports "Audit log not found" |
| Disk full during run | Partial log file; later events silently dropped | Step 6 reports missing `run_end` or low event count |
| Concurrent /ship runs | Each writes to separate file (by RUN_ID); `mkdir -p` is race-safe | No issue unless concurrent L2/L3 `git add` causes commit conflicts (git-level concern, not logging-level) |

### Mitigations Summary

1. **Step 6 log verification**: Before committing, verify the audit log exists, contains `run_start` and `run_end` events, has a minimum event count, and (when security gates ran) contains `security_decision` events. Emit a warning if missing (do not block -- logging failure should not prevent shipping code).
2. **L3 HMAC chain with persisted key**: Each event's `hmac` field is `HMAC-SHA256(event_json + previous_hmac, run_key)`. The key is persisted to `.ship-audit-key-${RUN_ID}` (mode 0600) and committed alongside the log at L3. Verification replays the chain using the persisted key.
3. **Git history**: L2/L3 logs are committed to git. Git's content-addressed storage provides an additional tamper evidence layer.
4. **Symlink check**: The helper script verifies the log path is not a symlink before writing.
5. **Future OTel migration**: When Kagenti is available, OTel sidecars provide independent observation of agent actions, eliminating the "LLM must self-report" trust gap.

## Proposed Design

### 1. JSONL Event Schema

Every event is a single JSON object on one line, appended to `plans/audit-logs/<skill>-<run_id>.jsonl`.

#### Common Fields (all events)

```json
{
  "run_id": "20260327-143052-a1b2c3",
  "timestamp": "2026-03-27T14:30:52.000Z",
  "event_type": "step_start|step_end|verdict|security_decision|file_modification|run_start|run_end|error",
  "skill": "ship",
  "skill_version": "3.6.0",
  "security_maturity": "advisory|enforced|audited",
  "sequence": 1
}
```

**Note:** `duration_ms` is not emitted per-event. Duration is computed by the query utility from `step_start`/`step_end` timestamp pairs. This avoids the cross-call state dependency that shell session non-persistence creates.

#### OTel Field Mapping

| JSONL Field | OTel Mapping | Migration Notes |
|-------------|-------------|-------|
| `run_id` | `baggage.run_id` | `run_id` format (`20260327-143052-a1b2c3`) is not a valid OTel `trace_id` (which requires 128-bit / 32-char hex). The adapter must generate a proper `trace_id` and carry `run_id` as baggage for correlation. |
| `timestamp` | `start_time` / `end_time` | ISO 8601 with timezone. OTel uses nanosecond Unix timestamps; adapter converts. |
| `event_type` | Determines span vs event | `step_start`/`step_end` map to span boundaries. `verdict`, `security_decision` map to span events (annotations). |
| `skill` | `service.name` | `ship`, `architect`, `audit` |
| `skill_version` | `service.version` | Semver string |
| `step` | `span.name` | e.g., `step_0_preflight`, `step_3c_dispatch_coders` |
| `step_name` | span attribute `devkit.ship.step_name` | Human-readable, e.g., "Pre-flight checks" |
| `parent_step` | Reconstructed in adapter | The flat event sequence does not encode parent-child span hierarchy. The adapter must reconstruct hierarchy from step naming conventions (e.g., `step_3c` is a child of the `step_3` span). This is span hierarchy reconstruction, not a trivial field rename. See OTel Migration section. |
| `verdict` | span attribute `devkit.ship.verdict` | `PASS`, `FAIL`, `BLOCKED`, `PASS_WITH_NOTES`, `REVISION_NEEDED` |
| `files_modified` | span attribute `devkit.ship.files` | JSON array of relative paths |
| `security_maturity` | span attribute `devkit.ship.security_maturity` | `advisory`, `enforced`, `audited` |
| `override_reason` | span attribute `devkit.ship.security_override_reason` | Free text |
| `agent_type` | span attribute `devkit.ship.agent_type` | `coordinator`, `coder`, `code-reviewer`, `qa-engineer`, `secrets-scan`, `secure-review`, `dependency-audit` |
| `sequence` | span attribute `devkit.ship.sequence` | Monotonic counter for total ordering within a run. Preserved in OTel as an attribute (OTel timestamps do not guarantee ordering for concurrent spans). |
| `hmac` | span attribute `devkit.ship.hmac` (L3 only) | HMAC-SHA256 chain value |
| `plan_file` | span attribute `devkit.ship.plan_file` | Relative path to the plan being shipped |
| `work_groups` | span attribute `devkit.ship.work_groups` | Count of work groups |
| `error` | span status `ERROR` + `exception.message` | Error description when event_type is `error` |

#### Event Type Catalog

**`run_start`** -- Emitted once at the beginning of Step 0.
```json
{
  "run_id": "20260327-143052-a1b2c3",
  "timestamp": "2026-03-27T14:30:52.000Z",
  "event_type": "run_start",
  "skill": "ship",
  "skill_version": "3.6.0",
  "security_maturity": "advisory",
  "sequence": 1,
  "plan_file": "./plans/add-user-auth.md",
  "security_override_active": false
}
```

**`step_start`** -- Emitted at the beginning of each step/substep.
```json
{
  "run_id": "20260327-143052-a1b2c3",
  "timestamp": "2026-03-27T14:31:05.000Z",
  "event_type": "step_start",
  "skill": "ship",
  "skill_version": "3.6.0",
  "security_maturity": "advisory",
  "sequence": 5,
  "step": "step_3c_dispatch_coders",
  "step_name": "Dispatch coders to worktrees",
  "agent_type": "coder",
  "work_groups": 2
}
```

**`step_end`** -- Emitted at the end of each step/substep.
```json
{
  "run_id": "20260327-143052-a1b2c3",
  "timestamp": "2026-03-27T14:35:22.000Z",
  "event_type": "step_end",
  "skill": "ship",
  "skill_version": "3.6.0",
  "security_maturity": "advisory",
  "sequence": 6,
  "step": "step_3c_dispatch_coders",
  "step_name": "Dispatch coders to worktrees",
  "agent_type": "coder"
}
```

**`verdict`** -- Emitted when a verdict gate is evaluated.
```json
{
  "run_id": "20260327-143052-a1b2c3",
  "timestamp": "2026-03-27T14:36:00.000Z",
  "event_type": "verdict",
  "skill": "ship",
  "skill_version": "3.6.0",
  "security_maturity": "advisory",
  "sequence": 10,
  "step": "step_4_verification",
  "verdict": "PASS",
  "verdict_source": "code_review",
  "agent_type": "code-reviewer",
  "artifact": "./plans/feature-x.code-review.md"
}
```

**`security_decision`** -- Emitted for security gate outcomes and overrides.
```json
{
  "run_id": "20260327-143052-a1b2c3",
  "timestamp": "2026-03-27T14:30:58.000Z",
  "event_type": "security_decision",
  "skill": "ship",
  "skill_version": "3.6.0",
  "security_maturity": "enforced",
  "sequence": 3,
  "step": "step_0_preflight",
  "gate": "secrets_scan",
  "gate_verdict": "BLOCKED",
  "action": "override",
  "override_reason": "False positive: test fixture API key",
  "effective_verdict": "PASS_WITH_NOTES"
}
```

**`file_modification`** -- Emitted during merge (Step 3e) to record which files were modified.
```json
{
  "run_id": "20260327-143052-a1b2c3",
  "timestamp": "2026-03-27T14:35:30.000Z",
  "event_type": "file_modification",
  "skill": "ship",
  "skill_version": "3.6.0",
  "security_maturity": "advisory",
  "sequence": 8,
  "step": "step_3e_merge",
  "files_modified": ["src/auth.ts", "src/auth.test.ts", "src/middleware.ts"],
  "work_group": 1,
  "work_group_name": "Authentication"
}
```

**`run_end`** -- Emitted once at the end of the run (Step 6 or on workflow stop).
```json
{
  "run_id": "20260327-143052-a1b2c3",
  "timestamp": "2026-03-27T14:40:00.000Z",
  "event_type": "run_end",
  "skill": "ship",
  "skill_version": "3.6.0",
  "security_maturity": "advisory",
  "sequence": 15,
  "outcome": "success|failure|blocked",
  "steps_completed": 8,
  "revision_rounds": 0,
  "commit_sha": "abc1234",
  "plan_file": "./plans/add-user-auth.md"
}
```

**Known limitation:** `run_end` is emitted before the final `git commit`. If the commit fails (hook rejection, disk full), the log will contain `"outcome":"success"` for a run whose commit did not land. The `commit_sha` is captured from `HEAD` before the new commit, so it points to the previous commit. This is a genuine chicken-and-egg problem with no clean solution in the file-based approach. The `commit_sha` should be treated as "last known HEAD at run completion" rather than "the commit containing this run's changes."

**`error`** -- Emitted when a step fails unexpectedly (not a verdict FAIL, but an execution error).
```json
{
  "run_id": "20260327-143052-a1b2c3",
  "timestamp": "2026-03-27T14:33:00.000Z",
  "event_type": "error",
  "skill": "ship",
  "skill_version": "3.6.0",
  "security_maturity": "advisory",
  "sequence": 7,
  "step": "step_3b_create_worktrees",
  "error": "Failed to create worktree: disk full",
  "fatal": true
}
```

### 2. The `scripts/emit-audit-event.sh` Helper Script

This is a standalone bash script that handles all audit event emission. It is invoked as a one-liner from each `/ship` step, solving the shell state persistence problem (each Bash tool call in Claude Code spawns a fresh shell, so inline functions and variables do not persist between calls).

**Architecture:**

```
Step 0 (Bash call 1):         Step 1 (Bash call 2):         Step N (Bash call N+1):
  Create state file              Invoke helper script           Invoke helper script
  Create log file                  -> reads state file            -> reads state file
  Invoke helper script             -> derives sequence             -> derives sequence
    -> writes run_start              from wc -l of log              from wc -l of log
                                   -> appends event               -> appends event
                                   -> updates HMAC state           -> updates HMAC state
```

**State file:** `.ship-audit-state-${RUN_ID}.json` -- created in Step 0, read by the helper script on every invocation. Contains:

```json
{
  "run_id": "20260327-143052-a1b2c3",
  "audit_log": "./plans/audit-logs/ship-20260327-143052-a1b2c3.jsonl",
  "skill": "ship",
  "skill_version": "3.6.0",
  "security_maturity": "advisory",
  "hmac_key": ""
}
```

At L3, `hmac_key` contains the 64-character key. The state file is deleted in Step 6 cleanup.

**HMAC key persistence (L3):** The HMAC key is also written to a separate key file (`.ship-audit-key-${RUN_ID}`, mode 0600) so that the chain can be verified post-run even after the state file is deleted. At L3, this key file is committed alongside the log. The key file is a simple text file containing only the hex key.

**Sequence counter:** Derived from `wc -l` of the log file plus 1. This is stateless -- no shell variable needs to persist. Each invocation counts the lines in the log file to determine the next sequence number.

**JSON escaping:** Uses `python3 -c "import json,sys; print(json.dumps(sys.argv[1])[1:-1])"` for all string value escaping. This handles all RFC 8259 control characters (0x00-0x1F), including carriage returns, form feeds, and null bytes. Falls back to raw string if `python3` is unavailable, with a warning to stderr.

**HMAC chain:** For L3, the helper script reads the previous HMAC from the last line of the log file (extracting the `hmac` field). For the first event, it uses `"genesis"` as the previous HMAC. The HMAC is computed as `HMAC-SHA256(event_json + previous_hmac, key)` using `openssl dgst -sha256 -hmac`.

**Symlink check:** Before writing, the script verifies that `$AUDIT_LOG` is not a symlink (`[ -L "$AUDIT_LOG" ]`). If it is, the script warns and exits without writing.

**Helper script pseudocode:**

```bash
#!/usr/bin/env bash
# scripts/emit-audit-event.sh
# Usage: bash scripts/emit-audit-event.sh <state-file> <partial-event-json>
# Example: bash scripts/emit-audit-event.sh .ship-audit-state-abc123.json \
#            '{"event_type":"step_start","step":"step_1","step_name":"Read plan"}'

set -euo pipefail

STATE_FILE="$1"
EVENT_JSON="$2"

# Read state
# ... parse state file with python3 for reliability ...

# Derive sequence from log file line count
SEQUENCE=$(( $(wc -l < "$AUDIT_LOG" 2>/dev/null || echo 0) + 1 ))

# Generate timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Escape string values using python3 json.dumps
_escape() {
  python3 -c "import json,sys; print(json.dumps(sys.argv[1])[1:-1])" "$1" 2>/dev/null || printf '%s' "$1"
}

# Build complete event JSON (common fields + caller's partial event)
# ... merge common fields with event_json ...

# L3: compute HMAC chain
if [ -n "$HMAC_KEY" ]; then
  PREV_HMAC=$(tail -1 "$AUDIT_LOG" 2>/dev/null | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('hmac','genesis'))" 2>/dev/null || echo "genesis")
  HMAC=$(printf '%s' "${FULL_EVENT}${PREV_HMAC}" | openssl dgst -sha256 -hmac "$HMAC_KEY" 2>/dev/null | awk '{print $NF}')
  # Insert hmac into event
fi

# Symlink check
if [ -L "$AUDIT_LOG" ]; then
  echo "Warning: audit log path is a symlink, refusing to write" >&2
  exit 0
fi

# Append event
printf '%s\n' "$FULL_EVENT" >> "$AUDIT_LOG" 2>/dev/null || true
```

**Design decisions:**

1. **Standalone script over inline function** -- Solves the shell state persistence problem (RT-F4, FS-C1). The script reads all state from files on disk, requires no persistent shell variables, and is invocable as a one-liner from any step.
2. **`python3 json.dumps()` for escaping** -- Handles all RFC 8259 control characters (RT-F3, FS-C2). The `|| printf '%s'` fallback preserves the "never block /ship" principle if python3 is unavailable.
3. **Sequence from `wc -l`** -- Stateless derivation eliminates cross-call state dependency (FS-M3).
4. **Previous HMAC from last log line** -- Reads the `hmac` field from the last line of the log file, eliminating the need to persist `AUDIT_PREV_HMAC` in a shell variable.
5. **`exit 0` on all error paths** -- Audit log write failure must never block `/ship` execution. The script exits successfully even when writing fails.
6. **Symlink check** -- Prevents symlink attacks on the predictable log path (RT-F6, STRIDE supplemental).

### 3. Maturity-Aware Retention

| Level | Directory | Git Status | HMAC | Post-Run Behavior |
|-------|-----------|------------|------|-------------------|
| **L1** (advisory) | `plans/audit-logs/` | Gitignored (`plans/audit-logs/*.jsonl` in `.gitignore`) | No HMAC | Log exists during run. Untracked by git. Developer can inspect or delete. |
| **L2** (enforced) | `plans/audit-logs/` | Committed via `git add --force` in Step 6 | No HMAC | Log force-added past gitignore and committed to git. Provides queryable history. |
| **L3** (audited) | `plans/audit-logs/` | Committed via `git add --force` in Step 6 | HMAC-SHA256 chain | Log and key file force-added and committed. Chain provides post-run tamper detection. |

**Implementation approach for gitignore:**

- `plans/audit-logs/*.jsonl` is added to `.gitignore`
- `.ship-audit-key-*` is added to `.gitignore`
- `.ship-audit-state-*` is added to `.gitignore`
- At L2/L3, `git add --force` overrides the gitignore for the specific audit log file
- At L3, `git add --force` also adds the key file
- This keeps L1 logs cleanly untracked without cluttering `git status`

### 4. Instrumentation Points in /ship

Each step in `/ship` gets `emit-audit-event.sh` calls. The coordinator (the LLM executing `/ship`) is responsible for calling the helper script at the documented points. The SKILL.md prompt specifies the exact one-liner for each emission point.

**Invocation pattern in SKILL.md:**

```bash
bash "$CLAUDE_DEVKIT/scripts/emit-audit-event.sh" ".ship-audit-state-${RUN_ID}.json" '{"event_type":"step_start","step":"step_1_read_plan","step_name":"Coordinator reads plan"}'
```

If `$CLAUDE_DEVKIT` is not set, fall back to the repo-relative path:

```bash
bash "scripts/emit-audit-event.sh" ".ship-audit-state-${RUN_ID}.json" '{"event_type":"step_start","step":"step_1_read_plan","step_name":"Coordinator reads plan"}'
```

| Step | Events Emitted |
|------|---------------|
| Step 0 (pre-flight) | `run_start`, `step_start(step_0)`, `security_decision(secrets_scan)`, `step_end(step_0)` |
| Step 1 (read plan) | `step_start(step_1)`, `step_end(step_1)` |
| Step 2 (pattern validation) | `step_start(step_2)`, `step_end(step_2)` |
| Step 3a (shared deps) | `step_start(step_3a)`, `step_end(step_3a)` |
| Step 3b (create worktrees) | `step_start(step_3b)`, `step_end(step_3b)` |
| Step 3c (dispatch coders) | `step_start(step_3c)`, `step_end(step_3c)` |
| Step 3d (boundary validation) | `step_start(step_3d)`, `verdict(boundary_check)`, `step_end(step_3d)` |
| Step 3e (merge) | `step_start(step_3e)`, `file_modification(per work group)`, `step_end(step_3e)` |
| Step 3f (cleanup) | `step_start(step_3f)`, `step_end(step_3f)` |
| Step 4a (code review) | `step_start(step_4a)`, `verdict(code_review)`, `step_end(step_4a)` |
| Step 4b (tests) | `step_start(step_4b)`, `verdict(tests)`, `step_end(step_4b)` |
| Step 4c (QA) | `step_start(step_4c)`, `verdict(qa)`, `step_end(step_4c)` |
| Step 4d (secure review) | `step_start(step_4d)`, `security_decision(secure_review)`, `step_end(step_4d)` |
| Step 5 (revision loop) | `step_start(step_5)`, events for re-run of Steps 3-4, `step_end(step_5)` |
| Step 6 (commit gate) | `step_start(step_6)`, `security_decision(dependency_audit)`, `verdict(commit_gate)`, audit log verification, `run_end`, `step_end(step_6)` |
| Step 7 (retro) | `step_start(step_7)`, `step_end(step_7)` |

### 5. Step 6 Audit Log Verification (Enhanced)

Step 6 performs non-blocking verification of the audit log before the commit gate. This addresses RT-F2 (security_decision events not verified) by checking for security gate events, not just `run_start` existence.

```bash
# Audit log verification (non-blocking)
if [ -f "$AUDIT_LOG" ]; then
  EVENT_COUNT=$(wc -l < "$AUDIT_LOG")
  RUN_START_COUNT=$(grep -c '"event_type":"run_start"' "$AUDIT_LOG" 2>/dev/null || echo "0")

  # Check 1: run_start exists
  if [ "$RUN_START_COUNT" -eq 0 ]; then
    echo "Warning: Audit log exists but missing run_start event."
  fi

  # Check 2: minimum event count (at least 2 per step that executed + run_start)
  EXPECTED_MIN=5  # run_start + at least 2 step pairs
  if [ "$EVENT_COUNT" -lt "$EXPECTED_MIN" ]; then
    echo "Warning: Audit log has only $EVENT_COUNT events (expected at least $EXPECTED_MIN)."
  fi

  # Check 3: security_decision events when security gates ran
  SECRETS_SCAN_DEPLOYED=$(ls ~/.claude/skills/secrets-scan/SKILL.md 2>/dev/null && echo "yes" || echo "no")
  SECURE_REVIEW_DEPLOYED=$(ls ~/.claude/skills/secure-review/SKILL.md 2>/dev/null && echo "yes" || echo "no")
  DEP_AUDIT_DEPLOYED=$(ls ~/.claude/skills/dependency-audit/SKILL.md 2>/dev/null && echo "yes" || echo "no")

  SECURITY_EVENTS=$(grep -c '"event_type":"security_decision"' "$AUDIT_LOG" 2>/dev/null || echo "0")

  if [ "$SECRETS_SCAN_DEPLOYED" = "yes" ] || [ "$SECURE_REVIEW_DEPLOYED" = "yes" ] || [ "$DEP_AUDIT_DEPLOYED" = "yes" ]; then
    if [ "$SECURITY_EVENTS" -eq 0 ]; then
      echo "Warning: Security skills are deployed but no security_decision events found in audit log."
    fi
  fi

  # Emit run_end
  COMMIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
    "{\"event_type\":\"run_end\",\"outcome\":\"success\",\"commit_sha\":\"${COMMIT_SHA}\",\"plan_file\":\"${PLAN_PATH}\"}"

  # Stage audit log for commit at L2/L3
  if [ "$SECURITY_MATURITY" = "enforced" ] || [ "$SECURITY_MATURITY" = "audited" ]; then
    git add --force "$AUDIT_LOG"
    echo "Audit log staged for commit (${SECURITY_MATURITY} maturity)."

    # L3: also stage key file
    if [ "$SECURITY_MATURITY" = "audited" ]; then
      KEY_FILE=".ship-audit-key-${RUN_ID}"
      if [ -f "$KEY_FILE" ]; then
        git add --force "$KEY_FILE"
        echo "HMAC key file staged for commit (audited maturity)."
      fi
    fi
  else
    echo "Audit log available at $AUDIT_LOG (advisory maturity -- not committed)."
  fi

  # Cleanup state file (not needed after run)
  rm -f ".ship-audit-state-${RUN_ID}.json"
else
  echo "Warning: Audit log not found at $AUDIT_LOG. Logging may have failed."
fi
```

### 6. Query Utility

`scripts/audit-log-query.sh` provides common queries over the JSONL audit logs.

```bash
#!/usr/bin/env bash
# Query audit logs from /ship, /architect, /audit runs
# Requires: jq
# Usage: ./scripts/audit-log-query.sh <command> [options]
#
# Commands:
#   summary <run_id>         Show run summary (outcome, steps, timestamps)
#   verdicts <run_id>        Show all verdict events for a run
#   security <run_id>        Show security decisions for a run
#   files <run_id>           Show all file modifications for a run
#   overrides [--all]        Show all security overrides across runs
#   timeline <run_id>        Show step-by-step timeline (duration computed from timestamp pairs)
#   verify-chain <run_id>    Verify L3 HMAC chain integrity (reads key from .ship-audit-key-<run_id>)
#   recent [N]               Show N most recent runs (default 10)
```

**`timeline` command:** Computes per-step duration from `step_start`/`step_end` timestamp pairs using `jq`. This replaces the dropped `duration_ms` field with a computed equivalent at query time.

**`verify-chain` command:** Reads the HMAC key from `.ship-audit-key-${RUN_ID}` (or accepts a `--key` argument). Replays all events in sequence, recomputing the HMAC chain, and reports any mismatches. If the key file is not found (key was ephemeral or file was deleted), reports that verification is not possible.

### 7. Instrumentation of /architect and /audit

The same `scripts/emit-audit-event.sh` helper is used by `/architect` and `/audit`, with skill-specific state files and event types.

**`/architect`** events:
- State file: `.architect-audit-state-${RUN_ID}.json`
- Log file: `plans/audit-logs/architect-${RUN_ID}.jsonl`
- `run_start`, `step_start/end` for Steps 0-5
- `verdict` events for red team, librarian, feasibility reviews
- `run_end` with approval status

**`/audit`** events:
- State file: `.audit-audit-state-${RUN_ID}.json`
- Log file: `plans/audit-logs/audit-${RUN_ID}.jsonl`
- `run_start` with scope
- `step_start/end` for Steps 1-6
- `verdict` events for security, performance, QA scans
- `run_end` with final verdict and risk score

**Benefit of shared helper script:** All three skills invoke the same `scripts/emit-audit-event.sh`. Changes to emit logic (e.g., adding a new common field, fixing a bug) require modifying one file, not three SKILL.md files. This addresses feasibility concern m6 (three copies of inline function would diverge).

### 8. OTel Migration Assessment

**Honest assessment:** The migration from JSONL to OTel spans is not a trivial field rename. It requires a format adapter that performs span hierarchy reconstruction.

**What the adapter must do:**

1. **Generate proper trace IDs.** The `run_id` format (`20260327-143052-a1b2c3`) is not a valid OTel `trace_id` (128-bit hex). The adapter must generate a conformant `trace_id` and carry `run_id` as baggage.

2. **Reconstruct span hierarchy.** The flat JSONL event sequence has no parent-child encoding. The adapter must infer hierarchy from step naming conventions:
   - `step_3c` is a child of `step_3` (by naming prefix)
   - `verdict` and `security_decision` events within a step are span events (annotations) on that step's span
   - `run_start`/`run_end` define the root span
   - This inference is fragile and convention-dependent. A step naming change in SKILL.md could break the hierarchy reconstruction.

3. **Handle concurrent spans.** Steps 4a/4b/4c run in parallel. The adapter must create sibling spans with overlapping time ranges, not sequential spans.

4. **Preserve sequence ordering.** OTel does not guarantee timestamp ordering for concurrent spans. The `sequence` field is preserved as a span attribute (`devkit.ship.sequence`) to maintain total ordering.

**Migration effort estimate:** Medium. The adapter is a standalone script/service (50-100 lines of Python) that reads JSONL and emits OTLP to a collector. It is not trivial but is a bounded, well-defined task. The JSONL schema is designed to make this possible, even though it requires reconstruction rather than direct mapping.

**When to build the adapter:** When Kagenti provides an OTel collector endpoint. Building the adapter before the collector exists provides no value.

## Interfaces / Schema Changes

### New Files

| File | Purpose |
|------|---------|
| `plans/audit-logs/` (directory) | Audit log storage. Created by Step 0. |
| `plans/audit-logs/.gitkeep` | Ensure the directory exists in git. |
| `plans/audit-logs/ship-*.jsonl` | Per-run JSONL audit logs from `/ship`. |
| `plans/audit-logs/architect-*.jsonl` | Per-run JSONL audit logs from `/architect`. |
| `plans/audit-logs/audit-*.jsonl` | Per-run JSONL audit logs from `/audit`. |
| `scripts/emit-audit-event.sh` | Standalone helper script for audit event emission. |
| `scripts/audit-log-query.sh` | Query utility for audit logs. |
| `configs/audit-event-schema.json` | JSON Schema for audit events (validation reference). |
| `.ship-audit-state-*.json` (ephemeral) | Per-run state files. Created at Step 0, deleted at Step 6. |
| `.ship-audit-key-*` (L3 only) | Per-run HMAC key files. Committed at L3, deleted at L1/L2. |

### Modified Files

| File | Change |
|------|--------|
| `skills/ship/SKILL.md` | Add state file creation and `emit-audit-event.sh` invocation in Step 0, add helper script calls in all steps, add enhanced audit log verification in Step 6, bump version to 3.6.0. |
| `skills/architect/SKILL.md` | Add state file creation and helper script calls. Bump version to 3.2.0. |
| `skills/audit/SKILL.md` | Add state file creation and helper script calls. Bump version to 3.2.0. |
| `CLAUDE.md` | Update skill registry versions, add audit logging section, update artifact locations. |
| `generators/test_skill_generator.sh` | Add tests for audit log emission validation. |
| `.gitignore` | Add `plans/audit-logs/*.jsonl`, `.ship-audit-key-*`, `.ship-audit-state-*`, `.architect-audit-state-*`, `.audit-audit-state-*`. |

### No Schema Changes

- No changes to `configs/skill-patterns.json` (audit logging is additive, not a new required pattern)
- No changes to `configs/base-definitions/` or `configs/tech-stack-definitions/`
- No changes to templates (templates generate new skills; audit logging is retrofitted to existing skills)

## Data Migration

None. This is a new feature with no existing data to migrate. The `plans/audit-logs/` directory will be created on first use.

## Rollout Plan

### Phase 1: Foundation (ship only)

1. Create `scripts/emit-audit-event.sh` helper script
2. Define JSONL event schema in `configs/audit-event-schema.json`
3. Create `plans/audit-logs/.gitkeep` to establish the directory
4. Update `.gitignore` with audit log patterns
5. Modify `skills/ship/SKILL.md`:
   - Bump version to 3.6.0
   - Add state file creation and `run_start` emission in Step 0
   - Add helper script calls at every step start/end, verdict gate, security decision, file modification
   - Add enhanced audit log verification in Step 6 (event count, security_decision verification)
   - Add `run_end` emission, conditional `git add --force`, and state file cleanup in Step 6
6. Deploy and test with a real `/ship` run

### Phase 2: Tooling

7. Create `scripts/audit-log-query.sh` query utility (including `timeline` for computed durations and `verify-chain` for L3)
8. Add tests to `generators/test_skill_generator.sh`
9. Update CLAUDE.md with audit logging documentation

### Phase 3: Expansion

10. Instrument `/architect` with audit logging (same helper script, architect-specific state file and events)
11. Instrument `/audit` with audit logging (same helper script, audit-specific state file and events)
12. Update CLAUDE.md with architect and audit version bumps

### Phase 4: Hardening (deferred -- requires Kagenti)

13. Build OTel format adapter (span hierarchy reconstruction from JSONL)
14. Integrate SPIFFE identity into events
15. Move L3 HMAC keys to sealed secrets or HSM

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| LLM does not faithfully execute `emit-audit-event.sh` calls | Medium | High -- silent logging failure | Step 6 verifies audit log exists, checks minimum event count, and verifies security_decision events when security gates ran. Missing events trigger a warning (not a block). Future: Kagenti OTel sidecars provide independent observation. Residual risk: High (detective, not preventive). |
| `python3 json.dumps()` is unavailable | Low | Medium -- fallback to raw string escaping may produce invalid JSON | Helper script falls back to `printf '%s'` with a warning to stderr. Step 6 verification can detect invalid JSON lines. `python3` is a pre-existing dependency (security maturity check in Step 0). |
| L3 HMAC key persisted to disk -- attacker with filesystem access reads key and forges chain | Medium | Medium -- L3 tamper detection is defeated | Key file has mode 0600. At L3, key is committed to git (same access as the log itself). L3 provides tamper detection for uncoordinated modifications (e.g., accidental edits, partial log corruption), not tamper prevention against an adversary with full filesystem access. Kagenti migration provides proper signing. |
| Audit log files accumulate over time | Low | Low -- disk space, git history bloat (L2/L3) | L1 logs are gitignored. L2/L3: each log is small (< 50KB). `scripts/audit-log-query.sh recent` helps identify old logs. Guidance for periodic cleanup in documentation. |
| macOS `date` lacks nanosecond precision | Certain | Low -- timestamps have second granularity on macOS | Document this. Second-level timestamps are sufficient for audit purposes. OTel migration will use platform-provided high-res timestamps. |
| SKILL.md becomes longer due to helper script calls | Medium | Low -- more prompt tokens consumed | Each helper script call is a one-liner (~100 chars). ~30 calls adds ~30 lines. Step 0 state file creation adds ~20 lines. Total addition: ~50 lines. Acceptable for a 935-line SKILL.md (~5% increase). |
| Concurrent /ship runs on same branch at L2/L3 | Low | Low -- potential git commit conflicts | Each run writes to a separate JSONL file. Concurrent `git add --force` + `git commit` may conflict. This is a git concurrency issue, not a logging issue. |
| `_audit_ts` timestamp lacks `-u` flag on non-standard systems | Very Low | Low -- timestamps in local time instead of UTC | The helper script uses `date -u` with a fallback to `date` (without `-u`) for systems where `-u` is unsupported. |

## Test Plan

### Unit-Level Tests (in `generators/test_skill_generator.sh`)

**Test A: Ship skill validates with audit logging additions**
```bash
run_test NN "Validate ship skill (with audit logging)" \
    "python3 '$VALIDATE_PY' '$REPO_DIR/skills/ship/SKILL.md'" \
    0
```

**Test B: Architect skill validates with audit logging additions**
```bash
run_test NN "Validate architect skill (with audit logging)" \
    "python3 '$VALIDATE_PY' '$REPO_DIR/skills/architect/SKILL.md'" \
    0
```

**Test C: Audit skill validates with audit logging additions**
```bash
run_test NN "Validate audit skill (with audit logging)" \
    "python3 '$VALIDATE_PY' '$REPO_DIR/skills/audit/SKILL.md'" \
    0
```

**Test D: Audit event schema is valid JSON**
```bash
run_test NN "Audit event schema is valid JSON" \
    "python3 -c \"import json; json.load(open('$REPO_DIR/configs/audit-event-schema.json'))\"" \
    0
```

**Test E: Query utility has executable permissions and shows help**
```bash
run_test NN "Audit log query utility help" \
    "bash '$REPO_DIR/scripts/audit-log-query.sh' --help" \
    0
```

**Test F: Helper script has executable permissions and shows help**
```bash
run_test NN "Audit event helper script help" \
    "bash '$REPO_DIR/scripts/emit-audit-event.sh' --help" \
    0
```

### Integration Tests (in `scripts/test-integration.sh`)

**Test G: emit-audit-event.sh produces valid JSONL across multiple calls**
```bash
# Simulates the actual runtime: multiple separate script invocations
RUN_ID="test-$(date +%s)-$(head -c 3 /dev/urandom | od -A n -t x1 | tr -d ' ')"
STATE_FILE=".ship-audit-state-${RUN_ID}.json"
AUDIT_LOG="./plans/audit-logs/ship-${RUN_ID}.jsonl"
mkdir -p ./plans/audit-logs

# Create state file (as Step 0 would)
cat > "$STATE_FILE" << EOF
{"run_id":"${RUN_ID}","audit_log":"${AUDIT_LOG}","skill":"ship","skill_version":"3.6.0","security_maturity":"advisory","hmac_key":""}
EOF

# Call 1: run_start
bash scripts/emit-audit-event.sh "$STATE_FILE" '{"event_type":"run_start","plan_file":"./plans/test.md"}'

# Call 2: step_start (separate process, simulating separate Bash tool call)
bash scripts/emit-audit-event.sh "$STATE_FILE" '{"event_type":"step_start","step":"step_0","step_name":"Pre-flight"}'

# Call 3: step_end
bash scripts/emit-audit-event.sh "$STATE_FILE" '{"event_type":"step_end","step":"step_0","step_name":"Pre-flight"}'

# Verify each line is valid JSON with correct sequence numbers
python3 -c "
import json
with open('$AUDIT_LOG') as f:
    lines = f.readlines()
    assert len(lines) == 3, f'Expected 3 events, got {len(lines)}'
    for i, line in enumerate(lines):
        event = json.loads(line)
        assert event['sequence'] == i + 1, f'Expected sequence {i+1}, got {event[\"sequence\"]}'
        assert event['run_id'] == '$RUN_ID', f'Wrong run_id'
        assert event['skill'] == 'ship', f'Wrong skill'
        assert event['skill_version'] == '3.6.0', f'Wrong version'
print('PASS: Multi-call event emission produces valid, sequenced JSONL')
"

# Cleanup
rm -f "$STATE_FILE" "$AUDIT_LOG"
```

**Test H: L3 HMAC chain produces verifiable chain across calls**
```bash
# Similar to Test G but with security_maturity=audited and hmac_key set
# Verify each event has a non-empty hmac field
# Verify hmac values are all different (chain, not static)
# Verify chain is replayable using the key
```

**Test I: validate-all.sh passes after modifications**
```bash
cd ~/projects/claude-devkit && ./scripts/validate-all.sh
```

**Test J: Multi-call integration test for state persistence**
```bash
# Exercises the exact pattern used at runtime: state file created in one
# process, read by separate processes in subsequent calls.
# Verifies that sequence, HMAC chain, and common fields are consistent
# across 10+ separate invocations.
```

### Exact Test Command

```bash
# Run full test suite (includes new audit logging tests)
cd ~/projects/claude-devkit && bash generators/test_skill_generator.sh

# Run validate-all to confirm no regressions
cd ~/projects/claude-devkit && ./scripts/validate-all.sh

# Run integration tests
cd ~/projects/claude-devkit && bash scripts/test-integration.sh
```

## Acceptance Criteria

1. `/ship` emits a JSONL audit log to `plans/audit-logs/ship-${RUN_ID}.jsonl` on every run
2. Every event contains the required common fields: `run_id`, `timestamp`, `event_type`, `skill`, `skill_version`, `security_maturity`, `sequence`
3. `run_start` and `run_end` events bracket every run
4. Verdict events capture the verdict value and source (code review, QA, tests, security)
5. Security decision events capture gate name, verdict, action (pass/block/override), and override reason
6. File modification events capture the list of files modified per work group
7. At L1, the audit log is NOT git-added in Step 6 (gitignored)
8. At L2, the audit log IS force-added and committed in Step 6
9. At L3, every event contains a non-empty `hmac` field and the chain is verifiable post-run using the persisted key file
10. Step 6 verification checks: (a) `run_start` exists, (b) minimum event count, (c) `security_decision` events exist when security gates ran
11. `scripts/emit-audit-event.sh` works correctly across multiple separate invocations (multi-call test)
12. `scripts/audit-log-query.sh` can parse and query the JSONL files, including computed duration via `timeline`
13. All three modified skills (`ship`, `architect`, `audit`) pass `validate-skill`
14. `generators/test_skill_generator.sh` passes with new tests
15. `scripts/validate-all.sh` passes with no regressions
16. CLAUDE.md is updated with audit logging documentation, version bumps, and artifact location
17. `configs/audit-event-schema.json` exists and is valid JSON Schema

## Task Breakdown

### Phase 1: Foundation (ship only)

#### Files to Create

| File | Purpose |
|------|---------|
| `scripts/emit-audit-event.sh` | Standalone helper script for audit event emission. Handles JSON construction (via `python3 json.dumps`), timestamp generation, sequence derivation (from `wc -l`), L3 HMAC chain computation, and append to JSONL file. |
| `configs/audit-event-schema.json` | JSON Schema defining all event types, required fields, and OTel mapping annotations |
| `plans/audit-logs/.gitkeep` | Ensure the directory exists in git (empty directory placeholder) |

#### Files to Modify

| File | Change Summary |
|------|---------------|
| `skills/ship/SKILL.md` | (1) Bump version 3.5.0 -> 3.6.0. (2) Add state file creation, HMAC key generation (L3), and `run_start` emission via helper script in Step 0. (3) Add one-liner helper script calls at every step start/end, verdict gate, security decision, file modification event. (4) Add enhanced audit log verification in Step 6 (run_start check, event count check, security_decision check). (5) Add `run_end` emission, conditional `git add --force`, L3 key file staging, and state file cleanup in Step 6. |
| `.gitignore` | Add `plans/audit-logs/*.jsonl`, `.ship-audit-key-*`, `.ship-audit-state-*`, `.architect-audit-state-*`, `.audit-audit-state-*` |

#### Detailed Step 0 Modifications (skills/ship/SKILL.md)

After the existing `RUN_ID` generation block, insert:

```markdown
**Then: Initialize audit logging**

Tool: `Bash`

```bash
# --- Audit Logging Setup ---
AUDIT_LOG_DIR="./plans/audit-logs"
mkdir -p "$AUDIT_LOG_DIR"
AUDIT_LOG="$AUDIT_LOG_DIR/ship-${RUN_ID}.jsonl"
STATE_FILE=".ship-audit-state-${RUN_ID}.json"

# L3: generate HMAC key and persist to disk
HMAC_KEY=""
if [ "$SECURITY_MATURITY" = "audited" ]; then
  HMAC_KEY=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | head -c 64)
  KEY_FILE=".ship-audit-key-${RUN_ID}"
  printf '%s' "$HMAC_KEY" > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
fi

# Create state file for helper script
python3 -c "
import json
state = {
    'run_id': '${RUN_ID}',
    'audit_log': '${AUDIT_LOG}',
    'skill': 'ship',
    'skill_version': '3.6.0',
    'security_maturity': '${SECURITY_MATURITY}',
    'hmac_key': '${HMAC_KEY}'
}
with open('${STATE_FILE}', 'w') as f:
    json.dump(state, f)
"

# Emit run_start
OVERRIDE_ACTIVE="false"
[ -n "$SECURITY_OVERRIDE_REASON" ] && OVERRIDE_ACTIVE="true"
bash scripts/emit-audit-event.sh "$STATE_FILE" \
  "{\"event_type\":\"run_start\",\"plan_file\":\"${PLAN_PATH}\",\"security_override_active\":${OVERRIDE_ACTIVE}}"
echo "Audit log: $AUDIT_LOG"
```
```

After each existing step in the SKILL.md, the coordinator emits `step_start` before executing the step's work and `step_end` after. For example, before the Step 1 content:

```bash
bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_start","step":"step_1_read_plan","step_name":"Coordinator reads plan"}'
```

And after Step 1 content:

```bash
bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_end","step":"step_1_read_plan","step_name":"Coordinator reads plan"}'
```

### Phase 2: Tooling

#### Files to Create

| File | Purpose |
|------|---------|
| `scripts/audit-log-query.sh` | Query utility with `jq`-based commands. Includes `timeline` (computes duration from timestamp pairs) and `verify-chain` (reads key from `.ship-audit-key-*` or `--key` argument). |

#### Files to Modify

| File | Change Summary |
|------|---------------|
| `generators/test_skill_generator.sh` | Add 4 new tests: (A) ship validates with logging, (D) schema is valid JSON, (E) query utility help works, (F) helper script help works. Adjust cleanup test number. |
| `CLAUDE.md` | Update skill registry: ship 3.5.0 -> 3.6.0. Add "Audit Logging" section documenting the JSONL format, helper script, maturity-aware retention, and query utility. Update artifact locations to include `plans/audit-logs/`. |

### Phase 3: Expansion

#### Files to Modify

| File | Change Summary |
|------|---------------|
| `skills/architect/SKILL.md` | Bump version 3.1.0 -> 3.2.0. Add state file creation (`.architect-audit-state-${RUN_ID}.json`) and helper script calls. Log file: `architect-${RUN_ID}.jsonl`. Lighter instrumentation than /ship (fewer steps, no worktree/security events). |
| `skills/audit/SKILL.md` | Bump version 3.1.0 -> 3.2.0. Add state file creation (`.audit-audit-state-${RUN_ID}.json`) and helper script calls. Log file: `audit-${RUN_ID}.jsonl`. |
| `CLAUDE.md` | Update architect 3.1.0 -> 3.2.0, audit 3.1.0 -> 3.2.0 in registry. |

## Implementation Plan

### Phase 1: Foundation

1. [ ] Create `scripts/emit-audit-event.sh` with:
   - [ ] State file parsing (reads `run_id`, `audit_log`, `skill`, `skill_version`, `security_maturity`, `hmac_key`)
   - [ ] Sequence derivation from `wc -l` of log file
   - [ ] Timestamp generation (`date -u` with fallback)
   - [ ] JSON escaping via `python3 -c "import json; json.dumps(...)"` with raw-string fallback
   - [ ] HMAC chain computation (reads previous HMAC from last log line)
   - [ ] Symlink check before writing
   - [ ] `--help` flag for test discoverability
   - [ ] Exit 0 on all paths (never block /ship)
2. [ ] Create `configs/audit-event-schema.json` with JSON Schema for all event types
3. [ ] Create `plans/audit-logs/.gitkeep` to establish the directory
4. [ ] Update `.gitignore` with audit log patterns (`plans/audit-logs/*.jsonl`, `.ship-audit-key-*`, `.ship-audit-state-*`, `.architect-audit-state-*`, `.audit-audit-state-*`)
5. [ ] Modify `skills/ship/SKILL.md`:
   - [ ] Bump version to 3.6.0
   - [ ] Add state file creation (including L3 HMAC key generation and persistence) in Step 0
   - [ ] Add `run_start` event emission via helper script at end of Step 0 setup
   - [ ] Add `step_start` one-liner at beginning of each step (Steps 0-7)
   - [ ] Add `step_end` one-liner at end of each step (Steps 0-7)
   - [ ] Add `verdict` events at each verdict gate (Steps 3d, 4a, 4b, 4c)
   - [ ] Add `security_decision` events at each security gate (Step 0 secrets scan, Step 4d secure review, Step 6 dependency audit)
   - [ ] Add `file_modification` event in Step 3e (merge) per work group
   - [ ] Add `error` event emission where `/ship` stops due to errors
   - [ ] Add enhanced audit log verification in Step 6 (run_start check, event count check, security_decision check)
   - [ ] Add `run_end` event emission in Step 6
   - [ ] Add conditional `git add --force` of audit log at L2/L3 in Step 6
   - [ ] Add L3 key file staging in Step 6
   - [ ] Add state file cleanup in Step 6
6. [ ] Run validation: `python3 generators/validate_skill.py skills/ship/SKILL.md`
7. [ ] Run full test suite: `bash generators/test_skill_generator.sh`
8. [ ] Deploy and test with a real `/ship` run: `./scripts/deploy.sh ship`

### Phase 2: Tooling

9. [ ] Create `scripts/audit-log-query.sh` with commands: summary, verdicts, security, files, overrides, timeline (computed duration), verify-chain (reads persisted key), recent
10. [ ] Add executable permissions: `chmod +x scripts/audit-log-query.sh scripts/emit-audit-event.sh`
11. [ ] Add tests to `generators/test_skill_generator.sh`:
    - [ ] Test: audit event schema is valid JSON
    - [ ] Test: query utility shows help text
    - [ ] Test: helper script shows help text
    - [ ] Adjust cleanup test number
12. [ ] Update `CLAUDE.md`:
    - [ ] Update ship version in skill registry (3.5.0 -> 3.6.0)
    - [ ] Add `## Audit Logging` section after `## Security Maturity Levels`
    - [ ] Update `## Artifact Locations` to include `plans/audit-logs/`
    - [ ] Document `scripts/emit-audit-event.sh` in scripts section
13. [ ] Run validation: `./scripts/validate-all.sh`
14. [ ] Run test suite: `bash generators/test_skill_generator.sh`

### Phase 3: Expansion

15. [ ] Modify `skills/architect/SKILL.md`:
    - [ ] Bump version to 3.2.0
    - [ ] Add state file creation (`.architect-audit-state-${RUN_ID}.json`) in Step 0
    - [ ] Add helper script calls at Steps 0-5
    - [ ] Add `run_end` with approval status in Step 5
16. [ ] Modify `skills/audit/SKILL.md`:
    - [ ] Bump version to 3.2.0
    - [ ] Add state file creation (`.audit-audit-state-${RUN_ID}.json`) in Step 1
    - [ ] Add helper script calls at Steps 1-6
    - [ ] Add `run_end` with verdict and risk score in Step 6
17. [ ] Update `CLAUDE.md` with architect and audit version bumps
18. [ ] Update `.gitignore` with architect and audit state file patterns (if not already covered by wildcards)
19. [ ] Run validation: `./scripts/validate-all.sh`
20. [ ] Run full test suite: `bash generators/test_skill_generator.sh`
21. [ ] Commit changes

## Context Alignment

### CLAUDE.md Patterns Followed

| Pattern | How This Plan Follows It |
|---------|-------------------------|
| **Numbered steps** | Audit events map 1:1 to existing step numbers. No new steps are added to skills. |
| **Tool declarations** | All new bash blocks specify `Tool: Bash`. |
| **Verdict gates** | Audit events capture verdict values at existing gates. No new verdicts are introduced. |
| **Timestamped artifacts** | Audit log filenames include run ID (which embeds a timestamp). |
| **Structured reporting** | JSONL format with documented schema. |
| **Archive on success** | L2/L3 logs are committed. L1 logs are ephemeral (consistent with advisory maturity semantics). |
| **Worktree isolation** | No changes to worktree pattern. File modification events are emitted during merge, not inside worktrees. |
| **Security maturity levels** | Retention behavior varies by L1/L2/L3, extending the existing maturity model. |

### Prior Plans Referenced

| Plan | Relationship |
|------|-------------|
| `security-guardrails-phase-b.md` | Builds on: security maturity levels (L1/L2/L3) and `--security-override` flag. This plan extends those with structured logging of security decisions. |
| `agentic-sdlc-security-skills.md` | Builds on: standalone security skills. Audit logging captures their verdicts when invoked by /ship. |
| `devkit-hygiene-improvements.md` | Follows pattern: test-first, validate-all, CLAUDE.md update. |
| `agentic-sdlc-next-phase.md` | Follows pattern: quality infrastructure additions with test coverage. Established `validate-all.sh` and expanded test suite that this plan extends. |
| `ship-always-worktree.md` | Depends on: unified worktree isolation model. Step 3 sub-steps (3a-3f) in the instrumentation table exist because of this plan's worktree structure. |

### Deviations from Established Patterns

| Deviation | Justification |
|-----------|---------------|
| **JSONL format (new to codebase)** | All existing artifacts are markdown. JSONL serves a fundamentally different purpose (machine consumption, OTel compatibility) that markdown cannot serve. The audit log complements, not replaces, existing markdown artifacts. |
| **Standalone helper script for event emission** | Existing SKILL.md bash blocks are self-contained. The helper script is necessary because shell state (functions, variables) does not persist between Bash tool calls. The script is a `.sh` file in `scripts/`, consistent with existing utilities (`deploy.sh`, `validate-all.sh`). |
| **`plans/audit-logs/` directory** | New subdirectory under `plans/`. Existing subdirectory is `plans/archive/`. Audit logs have different lifecycle (queryable across runs, maturity-aware retention) that justifies separation from the archive pattern. |
| **L1 logs gitignored** | All existing artifacts are committed or archived. L1 advisory logs are informational and committing them would add noise to every project's git history. Teams wanting retention upgrade to L2. |
| **Persisting L3 HMAC key to disk** | The key file is committed to git at L3, meaning anyone with repo access can read the key and forge the chain. This is accepted because L3 provides tamper *detection* (detecting uncoordinated modifications), not tamper *prevention* (stopping a determined adversary). Kagenti/OTel will provide proper signing for adversarial environments. |

## Verification

- [ ] `/ship` produces a JSONL file at `plans/audit-logs/ship-${RUN_ID}.jsonl`
- [ ] Every line in the JSONL file is valid JSON (verifiable with `jq . plans/audit-logs/ship-*.jsonl`)
- [ ] `run_start` event is the first event, `run_end` is the last
- [ ] Verdict events contain the correct verdict values
- [ ] Security decision events contain gate name and outcome
- [ ] Step 6 verification checks event count and security_decision presence
- [ ] At L1, the audit log does not appear in `git status` (gitignored)
- [ ] At L2, the audit log appears in the git commit
- [ ] At L3, every event has a non-empty `hmac` field and chain is verifiable using `.ship-audit-key-*`
- [ ] `scripts/emit-audit-event.sh` works across multiple separate invocations (Test G / Test J)
- [ ] `./scripts/validate-all.sh` passes with zero failures
- [ ] `bash generators/test_skill_generator.sh` passes with all tests
- [ ] `scripts/audit-log-query.sh timeline <run_id>` computes step durations from timestamp pairs
- [ ] `scripts/audit-log-query.sh verify-chain <run_id>` verifies L3 HMAC chain using persisted key

## Next Steps

1. **Execute Phase 1** -- Create `scripts/emit-audit-event.sh`, instrument `/ship`, test with a real run
2. **Execute Phase 2** -- Create query utility, add tests, update CLAUDE.md
3. **Execute Phase 3** -- Instrument `/architect` and `/audit`
4. **When Kagenti is available** -- Build OTel format adapter with span hierarchy reconstruction (not trivial field rename; see OTel Migration section)
5. **For corporate AI governance** -- When the Josh Boyer/Kevin Myers governance proposal is ratified (CNCF model: Sandbox → Incubating → Graduated), audit logs provide the evidence trail for tooling maturity assessment. Structured event data from devkit skills can feed into whatever reporting/dashboard the governance framework requires.

---

<!-- Context Metadata
discovered_at: 2026-03-27T22:00:00Z
revised_at: 2026-03-27T23:30:00Z
claude_md_exists: true
recent_plans_consulted: devkit-hygiene-improvements.md, security-guardrails-phase-b.md, agentic-sdlc-next-phase.md, agentic-sdlc-security-skills.md, ship-always-worktree.md
archived_plans_consulted: none
revision_trigger: red team FAIL (F1,F2,F3,F4,F5), feasibility critical (C1,C2), feasibility major (M1,M2,M3), librarian required edits (4)
-->

## Status: APPROVED
