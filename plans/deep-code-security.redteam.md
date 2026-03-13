# Red Team Review: deep-code-security (Round 2)

## Verdict: PASS

All Critical and Major findings from Round 1 have been adequately addressed. No new Critical findings were introduced. The revised plan demonstrates thorough engagement with the security concerns raised and makes substantive architectural changes rather than superficial acknowledgments.

---

## Round 1 Finding Resolution

### F-01 -- Docker Socket Mount Enables Full Host Compromise [was Critical]

**Status:** Addressed -- Yes
**Resolution:** Adequate

The plan has been fundamentally redesigned. The MCP server now runs as a native stdio process on the host, not inside a container. Docker/Podman is invoked via subprocess CLI only for sandbox containers. This eliminates the Docker socket mount attack vector entirely. The change is reflected consistently throughout the plan:

- Trade-offs table explicitly calls out "Native stdio" as the choice with rationale referencing F-01
- Sandbox Architecture section opens with "The MCP server runs as a native stdio process on the host"
- Architecture diagram shows native Python process invoking Docker CLI
- MCP configuration uses `python -m deep_code_security.mcp` directly
- `sandbox.py` uses subprocess (not Docker SDK)
- Deviations table explains the native deployment rationale
- Podman rootless is now the preferred container runtime (`DCS_CONTAINER_RUNTIME` defaults to auto-detect, prefer podman)

This is the correct fix. No residual risk from the original finding.

---

### F-02 -- Arbitrary Path Read via `deep_scan_hunt` and `deep_scan_remediate` [was Major]

**Status:** Addressed -- Yes
**Resolution:** Adequate

The plan adds a comprehensive path validation system:

- Dedicated `path_validator.py` module with `validate_path()` function
- `DCS_ALLOWED_PATHS` configuration (comma-separated, defaults to cwd)
- Symlink resolution via `os.path.realpath()` before validation
- Path traversal prevention (reject `..` after normalization)
- Special file rejection (`/proc`, `/sys`, `/dev`, block devices, named pipes)
- Symlink cycle detection in file discovery
- `DCS_MAX_FILES` limit (default 10,000)
- Path validation listed as P0 requirement
- Test scenarios include path validation rejection (test scenario 8)
- `deep_scan_status` tool exposes `allowed_paths` for transparency

The implementation is specified at the right level of detail. The `DCS_ALLOWED_PATHS` default of cwd is sensible -- it scopes to the project directory without requiring manual configuration.

---

### F-03 -- Exploit Script Generation is an Arbitrary Code Execution Pipeline [was Major]

**Status:** Addressed -- Yes
**Resolution:** Adequate

Multiple layers of defense have been added:

1. **Input validation:** Dedicated `input_validator.py` with strict regex patterns for function names (`^[a-zA-Z_][a-zA-Z0-9_.]*$`), variable names, and file paths. Validation happens before any template interpolation.
2. **Safe templating:** Jinja2 `SandboxedEnvironment` replaces string formatting. This is the correct choice -- Jinja2's sandbox restricts attribute access and prevents arbitrary Python execution within templates.
3. **Finding provenance:** `deep_scan_verify` now accepts finding IDs referencing a server-side session store, not raw `RawFinding` JSON from external callers. This eliminates the confused deputy vector where an attacker could inject crafted findings.
4. **Seccomp profile:** Custom seccomp profile added to sandbox containers.
5. **PID limits:** `--pids-limit=64` added to sandbox containers.
6. **Test coverage:** Test scenario 9 validates rejection of malicious function names; test scenario 10 validates rejection of fabricated finding IDs.

The `deep_scan_verify` schema change from accepting raw `findings` to accepting `finding_ids` is a significant improvement that closes the most dangerous attack path.

---

### F-04 -- No Authentication or Authorization on MCP Tools [was Major]

**Status:** Addressed -- Yes
**Resolution:** Adequate

A dedicated "Trust Model" section has been added covering all six points:

1. Trust boundary defined (spawning process is trusted)
2. Primary access control via input validation (path allowlists, schema validation, field sanitization)
3. Defense in depth via sandbox security policy
4. Explicit acknowledgment that stdio MCP servers have no authentication (correct -- this is architectural, not a bug)
5. Rate limiting via concurrency semaphore (`DCS_MAX_CONCURRENT_SANDBOXES`)
6. Audit trail with full parameter logging

The trust model is appropriate for a local stdio MCP server. The combination of input validation + sandboxing + audit logging provides adequate controls given the threat profile.

---

### F-05 -- YAML Registry Poisoning via Malicious tree-sitter Queries [was Major]

**Status:** Addressed -- Yes
**Resolution:** Adequate

The plan now specifies:

- Tree-sitter queries compiled and validated at load time (registry.py)
- Query execution timeout (default 5s per query)
- Query result size cap (default 1000 matches per query)
- Registry path restricted to `DCS_REGISTRY_PATH` only (no user override to arbitrary directories)
- Registry version hash included in scan output metadata for reproducibility
- Test coverage for malformed query rejection and query timeout enforcement

The restriction of `DCS_REGISTRY_PATH` to a single configured directory (rather than allowing project-level overrides) is the right call. It prevents the attack vector where a malicious project `.claude/settings.json` could redirect to a poisoned registry.

One item from Round 1 was not addressed: registry signing/checksumming. This is acceptable for v1 given that the registry path is now restricted and the registries ship with the project.

---

### F-06 -- Intraprocedural-Only Taint Tracking Will Miss Most Real Vulnerabilities [was Major]

**Status:** Addressed -- Yes
**Resolution:** Adequate

This finding received the most substantive revision. The plan now:

1. **Known Limitations section** at the top of the plan explicitly states "Expected detection rate on real-world injection vulnerabilities: **10-25%**" and positions v1 as proving the architecture, not competing with commercial SAST.
2. **Trade-offs table** explicitly notes "v1 catches ~10-25% of real injection vulns."
3. **Requirements table** elevates interprocedural taint tracking to P1 (v1.1).
4. **`call_graph.py` stub** created in Phase 1 as an explicit placeholder for v1.1 work.
5. **Risk assessment** lists "Intraprocedural-only taint tracking misses most real bugs" as High probability / Medium impact with clear mitigation.
6. **Rollout plan** Stage 2 includes "Document actual v1 detection rate vs the estimated 10-25%."
7. **Acceptance criteria** item 20 requires README to document known limitations.
8. **Remediation guidance instead of apply-ready patches** -- the Architect phase was descoped to avoid trust erosion from incorrect auto-patches, which is a smart response to the limited analysis scope.

The honesty about detection rates is the correct approach. Users and agents consuming the output will have calibrated expectations.

---

### F-07 -- No Input Size Limits on `deep_scan_hunt` [was Major]

**Status:** Addressed -- Yes
**Resolution:** Adequate

The plan adds:

- `DCS_MAX_FILES` limit (default 10,000) enforced during file discovery
- `max_results` parameter with default 100 and pagination (`offset`, `total_count`, `has_more`)
- `max_verifications` parameter with default 50 for the Auditor phase
- Sequential file processing with AST release after each file (bounds memory)
- `DCS_MAX_CONCURRENT_SANDBOXES` semaphore (default 2)
- Input size limits listed as P0 requirement

These limits are reasonable defaults. The pagination design is clean and matches standard MCP patterns.

---

### F-08 -- Vendored shared/ Library Creates Maintenance Debt [was Minor]

**Status:** Addressed -- Partially
**Resolution:** Acceptable for v1

The plan adds a `check-vendor` Makefile target that compares the vendored commit hash against upstream HEAD. This is better than the original (no mechanism at all) but does not adopt the git subtree or private package recommendations. The `VENDORED_FROM.md` with source commit hash provides traceability.

This is acceptable for v1. The Makefile target provides a manual drift-detection mechanism. If the vendored library diverges significantly, the git subtree approach should be reconsidered for v1.1.

---

### F-09 -- Confidence Scoring Model is Not Validated [was Minor]

**Status:** Addressed -- Yes
**Resolution:** Adequate

The scoring model has been redesigned:

- Exploit verification weight reduced from 40% to 10% (bonus-only, no penalty for failed PoCs)
- Taint path weight increased to 45% (reflecting its primacy)
- Sanitizer absence weight at 25%
- CWE severity baseline at 20%
- Formula clearly documented with bonus-only semantics
- Thresholds adjusted (75/45/20 instead of 80/50/20)
- Test coverage explicitly requires "Test that failed exploit does not reduce base confidence"

The bonus-only model is a meaningful improvement. It correctly reflects that template-based PoCs fail for structural reasons (missing execution context), not because the vulnerability is false. The weights are still arbitrary, but the plan acknowledges this implicitly by making them constants that can be tuned during rollout.

---

### F-10 -- Rollout Plan Has Placeholder CVE References [was Minor]

**Status:** Addressed -- Yes
**Resolution:** Adequate

The rollout plan Stage 2 no longer contains `CVE-2024-xxxxx` placeholders. Instead, it describes categories of test targets ("Django or Flask projects with publicly disclosed injection CVEs", "popular Go web frameworks with known vulnerabilities") and adds a note: "Specific CVE targets should be identified during Stage 1 based on available test data." This is pragmatic -- it acknowledges the work needs to be done without pretending it has been.

---

### F-11 -- Effort Estimates Are Optimistic [was Minor]

**Status:** Addressed -- Yes
**Resolution:** Adequate

- Total estimate revised from 21-30 days (4-5 weeks) to 6-8 weeks
- Language scope reduced from 5 to 2-3 (Python + Go + C stretch)
- Phase 3 (taint tracking) increased from 4-5 days to 6-8 days
- Phase 4 (sandbox) increased from 2-3 days to 3-4 days
- Phase 5 (exploit verification) increased from 3-5 days to 5-7 days
- Total files reduced from ~90 to ~75

The 6-8 week estimate with reduced scope is more realistic. The taint tracking engine estimate (6-8 days) now accounts for per-language AST node type differences, which was previously unacknowledged.

---

### F-12 -- No Consideration of Symbolic Links in Target Codebase [was Minor]

**Status:** Addressed -- Yes
**Resolution:** Adequate

Symlink handling is now specified in the path validation section:

- `os.path.realpath()` called before validation
- Resolved path must still be within the allowlist
- File discovery does not follow symlinks outside the target root
- Symlink cycle detection mentioned in the path validation section

---

### F-13 -- ExploitResult Stores Full Exploit Scripts in Output [was Info]

**Status:** Addressed -- Yes
**Resolution:** Adequate

`ExploitResult` model now uses `exploit_script_hash: str` (SHA-256 hash) instead of `exploit_script: str`. The plan states "Store exploit scripts only in ephemeral sandbox logs, not in the structured response." Stdout and stderr are truncated to 2KB. This prevents exploit code from flowing through MCP responses into plan files.

---

### F-14 -- No Concurrent Sandbox Execution Limit [was Info]

**Status:** Addressed -- Yes
**Resolution:** Adequate

`DCS_MAX_CONCURRENT_SANDBOXES` environment variable (default: 2) with a server-side semaphore is now specified. This is referenced in the sandbox manager, the trust model section, and the risk assessment table.

---

## New Findings (Round 2)

### R2-F01 -- Session Store Lacks Expiry and Size Bounds [Minor]

**Location:** MCP Server; Finding Provenance; Phase 7

The server-side session store (in-memory dict keyed by scan ID) that holds findings between `deep_scan_hunt` and `deep_scan_verify`/`deep_scan_remediate` calls has no specified expiry or size limit. If a user runs many scans without restarting the MCP server, the session store will grow unbounded. Since the MCP server is a long-lived stdio process, this is a slow memory leak.

**Recommendation:**
1. Add a `DCS_SESSION_TTL` configuration (default: 1 hour) that evicts stale scan results.
2. Add a `DCS_MAX_SESSIONS` limit (default: 10) that evicts the oldest session when exceeded.
3. Document that restarting the MCP server clears all session state.

---

### R2-F02 -- tmpfs noexec Claim May Conflict with PoC Execution Model [Minor]

**Location:** Sandbox Architecture; Security Policy item 3 and 7

The sandbox security policy specifies `--tmpfs /tmp:rw,noexec,nosuid,size=64m` and notes "PoC executes via interpreter, not direct binary execution." For Python and Go interpreters, this is correct -- the interpreter binary is on the read-only root filesystem, and noexec on tmpfs only prevents direct execution of binaries placed in /tmp.

However, for the C stretch goal, the typical PoC workflow would be: compile the PoC to a binary, then execute it. If compilation output goes to /tmp (the only writable location), noexec will prevent execution. The entrypoint would need to compile to the read-only root filesystem (not possible) or use an alternative approach.

**Recommendation:** For the C sandbox, either:
1. Use a second tmpfs mount specifically for compiled binaries (without noexec), accepting the increased risk.
2. Compile and execute in a single step using `gcc -o /dev/stdout poc.c | /tmp/...` (not viable with noexec).
3. Document that C PoCs must be compiled and run within the gcc invocation (e.g., `gcc -x c - -o /dev/fd/3 3>&1 <<< "$POC_CODE" && ...`), or accept that C exploit verification requires relaxing noexec.

Since C is a stretch goal, this does not block v1.

---

### R2-F03 -- DCS_ALLOWED_PATHS Default of CWD May Be Surprising [Minor]

**Location:** Path Validation; MCP Configuration

The plan states `DCS_ALLOWED_PATHS` defaults to the current working directory. However, the MCP server's cwd is set to `/Users/imurphy/projects/deep-code-security` in the MCP configuration example. This means by default, the tool can only scan the deep-code-security project itself, not other projects. Users must explicitly configure `DCS_ALLOWED_PATHS` to scan their actual project directories.

The example configuration does set `DCS_ALLOWED_PATHS` to `/Users/imurphy/projects`, which is broad (all projects). This is probably correct for a development machine, but the plan does not discuss the tradeoff between convenience (broad allowlist) and security (narrow allowlist).

**Recommendation:**
1. Document that the default (cwd) is intentionally restrictive and must be overridden for normal use.
2. Add a note in the MCP configuration section about scoping `DCS_ALLOWED_PATHS` appropriately -- per-project is safer, but a parent directory is more convenient.
3. Consider making the default `DCS_ALLOWED_PATHS` derive from the project path being scanned rather than the MCP server's cwd, or require explicit configuration with no default.

---

### R2-F04 -- No Integrity Verification of Container Images [Info]

**Location:** Sandbox Infrastructure; Phase 4

The sandbox images are built locally (`make build-sandboxes`). Once built, there is no mechanism to verify that the images have not been tampered with (e.g., by a compromised Docker daemon or by another process on the machine). An attacker who can modify local Docker images could replace the sandbox image with one that exfiltrates data or suppresses exploit results.

For a local development tool, this is a low-priority concern -- the Docker daemon itself is a trust boundary. However, it is worth noting for completeness.

**Recommendation:** Consider adding image digest verification in `sandbox.py` -- after building, record the image digest, and verify it before each container creation. This is a defense-in-depth measure, not a blocking requirement.

---

## Summary

| Category | Count |
|----------|-------|
| Round 1 Critical resolved | 1/1 |
| Round 1 Major resolved | 6/6 |
| Round 1 Minor resolved | 5/5 (1 partially -- F-08, acceptable) |
| Round 1 Info resolved | 2/2 |
| New Round 2 findings | 2 Minor, 1 Minor, 1 Info |
| New Critical findings | 0 |

The revised plan demonstrates strong security architecture. The key improvements are:

1. **Native MCP server** eliminates the Docker socket attack surface entirely (F-01)
2. **Finding provenance via session store** closes the confused deputy attack on exploit generation (F-03)
3. **Honest detection rate expectations** (~10-25%) prevent false confidence in v1 results (F-06)
4. **Bonus-only exploit scoring** prevents penalizing real vulnerabilities when PoCs fail (F-09)
5. **Comprehensive input validation** with dedicated modules and test coverage (F-02, F-03, F-07)

The remaining Minor and Info findings are refinements, not blockers.

---

<!-- Review Metadata
reviewer: security-analyst
review_round: 2
review_date: 2026-03-12
plan_file: ./plans/deep-code-security.md
verdict: PASS
round1_critical_resolved: 1
round1_major_resolved: 6
round1_minor_resolved: 5
round1_info_resolved: 2
new_critical_findings: 0
new_major_findings: 0
new_minor_findings: 3
new_info_findings: 1
-->
