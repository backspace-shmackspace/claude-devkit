# Red Team Security Analysis: Re-architect Red Hat Browser MCP to helper-mcps (Round 1)

**Verdict: PASS**

**Analyst:** Security Analyst (claude-devkit)
**Date:** 2026-02-24
**Revision Round:** 1 (previous review: round 0, verdict PASS)
**Plan Under Review:** `./plans/redhat-browser-mcp-v2.md`
**Prior Reviews:**
- `./plans/redhat-browser-mcp-v2.redteam.md` (round 0, PASS)
- `./plans/redhat-internal-browser-mcp.redteam.md` (v1 FastMCP plan, PASS)
**Scope:** Verify all prior Major findings are addressed; threat modeling, attack surface analysis, rollout gap analysis, failure mode stress testing on the revised plan.

---

## Executive Summary

The revised v2 plan addresses all seven findings from the round 0 red team review (2 Major, 5 Minor) and all three rollout gaps. The two prior Major findings -- loss of persistent audit trail (MAJOR-1) and container running as root (MAJOR-2) -- are both fully resolved. The plan now includes a non-root `mcpuser` in the Dockerfile, a persistent audit log file at `/audit/access.log` with a dedicated volume mount, the `_is_retryable()` httpx import wrapped in try/except, `get_headers()` returning empty dict instead of raising, concrete typing for `BrowserClient`'s auth parameter, explicit content size defaults, and a permission warning in `validate()`.

This review identifies four new findings. One is Major: the `--no-sandbox` flag for Chromium creates a meaningful risk reduction in browser exploit containment when combined with the non-root user, but the plan does not document that `--no-sandbox` disables Chromium's own multi-process sandbox, which is a distinct and important security layer separate from Docker's container sandbox. Three findings are Minor, relating to audit log integrity, Playwright Chromium auto-update risk, and the permission check being a warning instead of a hard block. No Critical findings.

---

## Previous Finding Disposition (Round 0)

### MAJOR-1: Loss of Persistent Audit Trail
**Previous Rating:** Major
**Status:** RESOLVED

The revised plan restores persistent audit logging as a `BrowserClient` concern (Phase 4, line 364). Each tool invocation appends a JSON-lines record to `/audit/access.log`, configurable via `REDHAT_BROWSER_AUDIT_LOG` env var. The Dockerfile (Phase 8, lines 467-468) creates `/audit` owned by `mcpuser`. The `docker-compose.yml` (Phase 10, lines 579-580) maps `${REDHAT_BROWSER_AUDIT_DIR:-~/.redhat-browser-mcp/audit}:/audit` as read-write. The Deviations section (line 783) explicitly confirms "both structured stderr and persistent file" are used.

This fully resolves the finding. The audit trail now survives container removal because it is stored on the host filesystem.

### MAJOR-2: Container Runs Playwright as Root
**Previous Rating:** Major
**Status:** RESOLVED

The Dockerfile (Phase 8, lines 466-469) now includes:
```dockerfile
RUN useradd -m -s /bin/bash mcpuser \
    && mkdir -p /audit \
    && chown mcpuser:mcpuser /audit
USER mcpuser
```

Goal #7 (line 21) explicitly states "running as a non-root user." The `__main__.py` (Phase 7, line 430) detects non-root via `os.getuid() != 0` and adds `--no-sandbox` to Chromium launch arguments. The plan documents (line 481) that `--no-sandbox` is acceptable inside Docker because Docker provides the outer sandbox.

This resolves the root-container finding. See NEW-1 below for a nuance about the `--no-sandbox` tradeoff documentation.

### MINOR-1: _is_retryable() ImportError
**Previous Rating:** Minor
**Status:** RESOLVED

Phase 1 step 1 (lines 240-257) explicitly wraps `import httpx` in `try/except ImportError`. Assumption #5 (line 41) is updated to acknowledge the problem and state that the plan includes a fix. The code snippet shows the corrected implementation.

### MINOR-2: get_headers() Contract Violation
**Previous Rating:** Minor
**Status:** RESOLVED

The Auth Pattern Decision section (lines 63-70) now specifies that `get_headers()` returns an empty dict `{}` with a logged warning, not an exception. This preserves Liskov Substitution Principle compliance. The interface definition (lines 163-164) confirms: "Returns empty dict with logged warning."

### MINOR-3: File Permission Check Not Implemented
**Previous Rating:** Minor
**Status:** PARTIALLY RESOLVED (see NEW-3 below)

Phase 1 step 3 (line 264) adds a permission check in `validate()` that logs a warning if permissions are more permissive than `0o600`, but only on non-container environments (`os.getuid() != 0`). This is a pragmatic approach that avoids blocking startup on macOS dev environments with `umask 022`. However, it downgrades from the v1 plan's hard block to a warning. See NEW-3 for analysis.

### MINOR-4: No Content Size Limit Defaults
**Previous Rating:** Minor
**Status:** RESOLVED

Phase 4 (line 351) now specifies explicit defaults: `max_response_size (default: 5MB), content_truncation_limit (default: 50,000 chars), browser_launch_timeout (default: 30s)`.

### MINOR-5: hasattr Check Fragile
**Previous Rating:** Minor
**Status:** RESOLVED

Phase 4 (line 350) states: "typed concretely, not as `CredentialProvider` ABC...No `hasattr` dispatch." The Auth Pattern Decision (lines 68-70) confirms `BrowserClient` uses `PlaywrightStorageStateProvider` as its concrete type. The ABC docstring update (Phase 1 step 2, lines 258-259) documents this pattern for future maintainers.

### GAP-1: No Docker Integration Test for Playwright
**Previous Rating:** Minor
**Status:** NOT EXPLICITLY ADDRESSED

The plan still describes integration tests as "manual, requires VPN" (Phase 12, line 615). There is no Docker smoke test step that validates Playwright launches Chromium inside the container without requiring VPN or valid auth. The `make build-redhat-browser` target (Phase 10, line 556) only builds the image.

Downgraded to Info for this round: the risk is operational (delayed detection of broken Docker builds), not a security concern.

### GAP-2: Phase 11 Deletion Not Gated on Phase 12
**Previous Rating:** Info
**Status:** NOT EXPLICITLY ADDRESSED

The rollout plan (lines 622-630) still lists Phase 11 and Phase 12 as separate steps without an explicit ordering constraint. However, the plan is structured so that Phase 11 is a separate commit in a separate repository (claude-devkit), which naturally gates it behind Phase 12 validation (helper-mcps). The risk is mitigated by the two-repository structure even without explicit documentation.

Retained as Info.

### GAP-3: Claude Code Config Snippet Missing
**Previous Rating:** Info
**Status:** NOT EXPLICITLY ADDRESSED

The rollout plan (line 628) still says "Update Claude Code MCP configuration" without the exact settings.json snippet. This remains an operational gap, not a security concern.

Retained as Info.

---

## STRIDE Analysis (Round 1)

### Spoofing

| ID | Threat | Severity | Analysis |
|----|--------|----------|----------|
| S1 | StorageState file substitution | Minor | Carried from v1 (NEW-1 in original review). No integrity hash. File permissions (0600) remain the primary control. The v2 plan does not change this risk. |

### Tampering

| ID | Threat | Severity | Analysis |
|----|--------|----------|----------|
| T1 | Audit log tampering via volume mount | Minor | See NEW-2 below. The `/audit` volume is read-write, and the `mcpuser` inside the container has write access. A compromised container process could modify or truncate the audit log. |

### Repudiation

| ID | Threat | Severity | Analysis |
|----|--------|----------|----------|
| R1 | Audit trail persistence | Resolved | See disposition of MAJOR-1 above. Persistent file-based audit logging is restored with host-mounted volume. |

### Information Disclosure

| ID | Threat | Severity | Analysis |
|----|--------|----------|----------|
| I1 | Error sanitization integration | Info | The plan preserves `sanitize_error_message()` in `content.py` (Phase 3, line 330). The `BaseMCPServer.call_tool` exception handler wraps all exceptions as `ToolError`. Playwright timeout messages containing internal URLs will pass through `ToolError` before reaching `sanitize_error_message()`. The plan does not specify where in the call chain sanitization occurs, but this is an implementation detail that can be resolved during coding. Downgraded from the previous Minor to Info because the sanitization function exists and the plan references it. |

### Denial of Service

| ID | Threat | Severity | Analysis |
|----|--------|----------|----------|
| D1 | Concurrency semaphore default specified | Resolved | Phase 4 (line 351) specifies `max_concurrent (default: 3)`. This limits browser context memory consumption to approximately 150-300MB. |

### Elevation of Privilege

| ID | Threat | Severity | Analysis |
|----|--------|----------|----------|
| E1 | Non-root user with --no-sandbox Chromium | **Major** | See NEW-1 below. The container now runs as `mcpuser` (MAJOR-2 resolved), but Chromium's own sandbox is disabled. |

---

## Detailed Findings

### NEW-1: Chromium --no-sandbox Disables Browser Multi-Process Sandbox

**Rating:** Major
**STRIDE Category:** Elevation of Privilege (E1)
**DREAD Score:** Damage=6, Reproducibility=3, Exploitability=3, Affected Users=10, Discoverability=4 = **5.2**

**Finding:** The plan states (line 430, 481) that Chromium is launched with `args=["--no-sandbox"]` when running as non-root, and that "the `--no-sandbox` flag is acceptable inside a Docker container because Docker provides the outer sandbox via seccomp profiles and Linux namespaces."

This statement is partially correct but omits a critical nuance. Chromium's multi-process sandbox is a defense-in-depth mechanism that isolates the renderer process from the browser process. When `--no-sandbox` is used:

1. **Renderer process runs with the same privileges as the browser process.** A malicious page exploiting a renderer vulnerability gains access to all files readable by `mcpuser`, including the storage state cookies mounted at `/secrets/auth-state.json` (read-only, but readable).
2. **The Docker seccomp profile is a coarser-grained sandbox** than Chromium's. Chromium's sandbox uses seccomp-bpf filters tuned specifically for renderer processes, blocking syscalls like `open()`, `socket()`, and `exec()` that a renderer should never need. Docker's default seccomp profile allows many more syscalls because it must support general-purpose container workloads.
3. **The plan does not document this tradeoff.** Line 481 presents Docker's sandbox as equivalent to Chromium's, but they operate at different layers with different granularity.

The non-root user (resolving MAJOR-2) significantly reduces the blast radius -- a compromised renderer cannot escalate to root. Combined with the `:ro` mount on `/secrets`, the attacker cannot modify the auth state. The remaining risk is information disclosure of the storage state cookies and any files in the container filesystem readable by `mcpuser`.

**Why Major (not Critical):** The attack requires exploiting a Chromium renderer vulnerability, which is a zero-day or n-day exploit scenario. The threat actor must also be able to serve malicious content from a `*.redhat.com` domain (due to the URL allowlist), which implies compromising Red Hat infrastructure. The non-root user and `:ro` volume mount provide meaningful containment. However, the plan should not claim Docker's sandbox is a full substitute for Chromium's sandbox without acknowledging the differences.

**Recommendation:**
1. Update the `--no-sandbox` documentation (line 481 and Phase 7 line 430) to state: "Docker provides a container-level sandbox via seccomp/namespaces, but this is coarser-grained than Chromium's multi-process sandbox. The `--no-sandbox` flag is a pragmatic tradeoff: Chromium's sandbox requires root or `CLONE_NEWUSER` capability, which the non-root container user does not have. Mitigations: non-root user limits blast radius, `:ro` volume mount prevents credential modification, and the URL allowlist limits exposure to trusted domains."
2. Consider adding `--cap-drop=ALL` to the docker-compose service definition to further restrict container capabilities.
3. Consider adding a custom seccomp profile that restricts syscalls beyond Docker's default (optional, defense-in-depth).

### NEW-2: Audit Log Integrity in Writable Volume

**Rating:** Minor
**STRIDE Category:** Tampering (T1)
**DREAD Score:** Damage=4, Reproducibility=5, Exploitability=3, Affected Users=10, Discoverability=3 = **5.0**

**Finding:** The `/audit` volume is mounted read-write (Phase 10, line 588: "not `:ro`") so the server can append audit records. This means:

1. A compromised container process running as `mcpuser` can truncate or modify the audit log to cover its tracks.
2. The audit log is on the host filesystem, so host-side processes with write access can also tamper with it.
3. There is no log integrity mechanism (append-only filesystem, chattr +a, cryptographic chaining, or log forwarding to a remote SIEM).

For a security audit trail that is intended to support incident investigation (the stated purpose from the v1 red team review), a tamper-evident log is desirable.

**Why Minor (not Major):** The audit log is a secondary control. The primary security boundary is the URL allowlist and SSRF protection. The audit log is for post-incident investigation, not real-time prevention. Additionally, if the container process is compromised to the point of modifying audit logs, the attacker has already bypassed Chromium's renderer (even without sandbox) and has code execution in the container -- the audit log modification is a symptom, not the root cause.

**Recommendation:**
1. On Linux hosts, consider using `chattr +a` on the audit log file to make it append-only at the filesystem level. This prevents truncation even by `mcpuser`.
2. Alternatively, forward audit records to a remote syslog or SIEM endpoint in addition to the local file (future enhancement, not blocking).
3. At minimum, document in `CLAUDE.md` that the audit log is not tamper-proof and that organizations requiring tamper-evident logging should configure a remote log aggregator.

### NEW-3: Permission Check Downgraded from Hard Block to Warning

**Rating:** Minor
**STRIDE Category:** Information Disclosure
**DREAD Score:** Damage=5, Reproducibility=6, Exploitability=2, Affected Users=10, Discoverability=4 = **5.4**

**Finding:** The v1 plan specified that the server "refuses to start" if file permissions are more permissive than `0700`/`0600` (line 245 of the v1 plan, marked RESOLVED by the original red team). The v2 plan (Phase 1 step 3, line 264) downgrades this to "Log a warning (not hard failure) if file permissions are more permissive than 0o600 on non-container environments."

The justification is pragmatic: macOS dev environments with `umask 022` would create files as `0644` by default, and a hard block would force users to manually `chmod` every time they re-authenticate. This is a reasonable developer experience tradeoff.

However, the change means the security control that was specifically validated as RESOLVED by the v1 red team review is now weaker. On a shared macOS system (e.g., a managed corporate laptop with multiple admin-level users), the storage state file containing SSO cookies could be readable by other users.

**Why Minor (not Major):** On macOS, multiple admin users sharing the same machine is uncommon in corporate environments (each user has their own account with home directory permissions managed by MDM). The `~/` prefix means the file is in the user's home directory, which is typically not world-readable on macOS. The warning log ensures the user is informed. Additionally, the Docker deployment path (the production path) does not have this issue because the file is volume-mounted with explicit permissions.

**Recommendation:**
1. Consider a middle ground: warn on first startup, but provide a `--strict-permissions` flag (or `REDHAT_BROWSER_STRICT_PERMISSIONS=1` env var) that enables the hard block for security-conscious environments.
2. Ensure the warning is prominent (not buried in debug-level logging). Use `logger.warning()` with a message that includes the current permissions and the recommended command (`chmod 600`).
3. In the `--login` flow that creates the auth-state file, explicitly set `0600` permissions at write time regardless of umask.

### NEW-4: Playwright Chromium Version Drift in Docker Image

**Rating:** Minor
**STRIDE Category:** Vulnerable Components (A06)
**DREAD Score:** Damage=5, Reproducibility=8, Exploitability=2, Affected Users=10, Discoverability=5 = **6.0**

**Finding:** The Dockerfile (Phase 8, line 459) runs `playwright install chromium` during the build. Playwright pins Chromium to a specific revision per Playwright release (e.g., Playwright 1.40.0 ships with Chromium 121). However, `requirements.txt` (Phase 2, line 300) pins `playwright>=1.40.0` (minimum, not exact). This means:

1. Rebuilding the Docker image at different times may pull different Playwright versions (1.40.0 vs 1.45.0), each shipping a different Chromium revision.
2. The Chromium version in the running container is not tracked or pinned -- it depends on when the image was last built.
3. Known Chromium vulnerabilities (CVEs) may be present in older builds, and there is no mechanism to detect or force upgrades.

The v1 red team review (MAJOR-4) validated that dependency pins were exact. The v2 plan uses `>=` pins for Playwright, which partially undoes this resolution.

**Why Minor (not Major):** The Chromium version is tied to the Playwright version, so pinning Playwright pins Chromium indirectly. Rebuilding the image triggers a new Chromium download. The risk is that stale images continue running with known-vulnerable Chromium versions, which is an operational concern (image hygiene) rather than a plan design flaw. Additionally, the URL allowlist limits exposure to `*.redhat.com` domains, reducing the attack surface for browser exploits.

**Recommendation:**
1. Pin `playwright` to an exact version in `requirements.txt` (e.g., `playwright==1.49.1`) to match the v1 pattern and ensure reproducible builds.
2. Document an image rebuild cadence (e.g., monthly or when Playwright releases a security update) in the operational runbook.
3. Consider adding a Playwright/Chromium version check to the `check_auth` tool output so operators can verify the running version.

---

## Rollout Plan Gap Analysis (Round 1)

### GAP-1 (Carried): No Docker Smoke Test

**Rating:** Info (downgraded from Minor)

The plan still lacks a Docker smoke test that validates Playwright launches Chromium inside the container. This is an operational quality gap, not a security concern. The `make build-redhat-browser` target validates the build, and the lifecycle state machine will surface launch failures at runtime (INITIALIZING will never reach SERVICE_VALIDATED if Chromium fails to launch).

**Recommendation:** Add a CI step that runs the container with a dummy storageState and verifies the lifecycle reaches INITIALIZING. This is a nice-to-have, not blocking.

### GAP-2 (Carried): Phase 11 Deletion Ordering

**Rating:** Info

The two-repository structure (helper-mcps for the new server, claude-devkit for the deletion) naturally gates Phase 11 behind Phase 12. No change needed.

### GAP-3 (Carried): Claude Code Config Snippet

**Rating:** Info

The exact `mcpServers` configuration for `~/.claude/settings.json` is still not specified. This is an operational gap that will be resolved during implementation.

**Recommendation:** Include the exact settings.json snippet for Docker mode in the plan or in a post-merge checklist.

---

## Compliance Checklist (Round 1)

- [x] **OWASP A01 (Broken Access Control):** PASS -- URL allowlist, SSRF filter, DNS resolution (carried from v1)
- [x] **OWASP A02 (Cryptographic Failures):** PASS -- storageState file handling, permission checks (carried from v1)
- [x] **OWASP A03 (Injection):** PASS -- URL scheme validation (carried from v1)
- [x] **OWASP A04 (Insecure Design):** PASS -- Data flow risk documented (carried from v1)
- [x] **OWASP A05 (Security Misconfiguration):** PASS -- Non-root container user (MAJOR-2 resolved); permission warning on dev environments (NEW-3 is Minor)
- [x] **OWASP A06 (Vulnerable Components):** PARTIAL -- Playwright uses `>=` pin instead of exact pin (NEW-4)
- [x] **OWASP A07 (Auth Failures):** PASS -- SSO session validation, expiry detection
- [x] **OWASP A08 (Data Integrity):** PASS -- Audit log on host volume; same-user integrity not verified (carried from v1 NEW-1)
- [x] **OWASP A09 (Logging Failures):** PASS -- Persistent audit trail restored (MAJOR-1 resolved); tamper-evidence is a Minor gap (NEW-2)
- [x] **OWASP A10 (SSRF):** PASS -- Multi-layer defense preserved from v1

---

## Risk Assessment Summary

| ID | Finding | Severity | Likelihood | Impact | Status |
|----|---------|----------|------------|--------|--------|
| MAJOR-1 (R0) | Loss of persistent audit trail | Major | -- | -- | RESOLVED in revision |
| MAJOR-2 (R0) | Container runs Playwright as root | Major | -- | -- | RESOLVED in revision |
| MINOR-1 (R0) | _is_retryable() ImportError | Minor | -- | -- | RESOLVED in revision |
| MINOR-2 (R0) | get_headers() contract violation | Minor | -- | -- | RESOLVED in revision |
| MINOR-3 (R0) | File permission check missing | Minor | -- | -- | PARTIALLY RESOLVED (see NEW-3) |
| MINOR-4 (R0) | No content size limit defaults | Minor | -- | -- | RESOLVED in revision |
| MINOR-5 (R0) | hasattr fragility | Minor | -- | -- | RESOLVED in revision |
| NEW-1 | --no-sandbox Chromium tradeoff underdocumented | Major | Low | Medium | NEW |
| NEW-2 | Audit log integrity in writable volume | Minor | Low | Low | NEW |
| NEW-3 | Permission check downgraded to warning | Minor | Medium | Medium | NEW |
| NEW-4 | Playwright version pin is >=, not exact | Minor | Medium | Low | NEW |
| GAP-1 | No Docker smoke test | Info | N/A | N/A | CARRIED (downgraded) |
| GAP-2 | Phase 11 deletion ordering | Info | N/A | N/A | CARRIED (mitigated by repo structure) |
| GAP-3 | Claude Code config snippet missing | Info | N/A | N/A | CARRIED |

---

## Verdict Rationale

**PASS** -- The revised plan is approved for implementation with the following rationale:

1. **All prior Major findings are resolved.** MAJOR-1 (audit trail) is restored with persistent file-based logging and a host-mounted volume. MAJOR-2 (root container) is resolved with a non-root `mcpuser` and `USER mcpuser` directive.

2. **All prior Minor findings are resolved or partially resolved.** The five Minor findings from round 0 are addressed: `_is_retryable()` is fixed, `get_headers()` returns empty dict, `BrowserClient` uses concrete typing, content size defaults are specified, and permission validation is implemented (as a warning).

3. **One new Major finding (NEW-1) is actionable but not blocking.** The `--no-sandbox` tradeoff documentation is incomplete but the architectural decision is sound. The non-root user, `:ro` volume mount, and URL allowlist provide meaningful containment. The fix is a documentation update (clarifying the tradeoff), not an architectural change. This can be addressed during implementation by updating the comments in the Dockerfile and `__main__.py`.

4. **Three new Minor findings** represent defense-in-depth opportunities (audit log integrity, exact Playwright pin, permission strictness) that do not block the plan.

5. **No Critical findings.** The security posture from the v1 plan (URL validation, SSRF protection, storageState handling, error sanitization) is fully preserved.

**Condition:** The implementer should:
- Update the `--no-sandbox` documentation per NEW-1 recommendations (clarify that Docker's sandbox is coarser than Chromium's, document mitigations)
- Pin `playwright` to an exact version in `requirements.txt` (NEW-4)
- If either of these remains unaddressed at code review time, the code reviewer should flag them as required changes.

---

## Recommended Improvements (Non-Blocking)

Priority order for implementation:

1. **Document --no-sandbox tradeoff accurately** (NEW-1) -- Update Dockerfile and __main__.py comments; consider `--cap-drop=ALL`
2. **Pin playwright to exact version** (NEW-4) -- Change `>=1.40.0` to `==1.49.1` in requirements.txt
3. **Set 0600 permissions at write time in --login flow** (NEW-3) -- Ensure auth-state.json is created with correct permissions regardless of umask
4. **Document audit log tamper limitations** (NEW-2) -- Note in CLAUDE.md that the audit log is not tamper-proof
5. **Add Docker smoke test** (GAP-1) -- Validate Playwright launches in container
6. **Add settings.json snippet** (GAP-3) -- Include exact mcpServers config

---

## Artifact Location

**Plan File:** `./plans/redhat-browser-mcp-v2.md`
**Red Team Review:** `./plans/redhat-browser-mcp-v2.redteam.md`
**Prior Red Team Review (v1):** `./plans/redhat-internal-browser-mcp.redteam.md`
