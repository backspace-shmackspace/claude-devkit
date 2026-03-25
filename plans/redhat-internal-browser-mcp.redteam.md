# Red Team Security Analysis: Red Hat Internal Browser MCP Server (Second Pass)

**Verdict: PASS**

**Analyst:** Security Analyst (claude-devkit)
**Date:** 2026-02-24
**Review Type:** Second-pass review of revised plan
**Plan Under Review:** `./plans/redhat-internal-browser-mcp.md`
**Previous Review:** 2026-02-24 (first pass, verdict FAIL)

## Executive Summary

The revised plan comprehensively addresses all three Critical and all four Major findings from the first review. The most significant architectural change is the switch from persistent `userDataDir` to Playwright's `storageState` API, which eliminates the world-readable Chromium profile directory (CRITICAL-3) and sidesteps a known macOS corruption bug. A full URL validation pipeline with SSRF filtering, DNS resolution checks, and HTTPS-only enforcement closes the SSRF vector (CRITICAL-2). The data exfiltration risk (CRITICAL-1) is now explicitly documented with a prominent Data Classification section, user obligations, and appropriate responsibility framing -- this was the correct resolution since the risk is inherent to MCP architecture. Audit logging, error sanitization, exact dependency pins, and `pip-audit` integration address all Major findings.

Five new Minor/Info-level issues were identified in the revisions. None are blocking.

---

## Previous Finding Disposition

### CRITICAL-1: Data Exfiltration to Anthropic (I1)

**Previous Rating:** Critical
**Current Rating:** Info (Accepted Risk, Documented)
**Status:** RESOLVED

The revised plan adds a prominent "Data Classification and Acceptable Use" section (lines 18-29) as the first substantive section after Context. This section:

- Opens with a bold warning that all fetched content is sent to Anthropic's API
- Enumerates four explicit user obligations including data classification review and enterprise agreement confirmation
- States clearly: "The tool does not make data classification decisions for the user"
- Adds Assumption #8: user has reviewed their organization's data classification policy
- The Risk Assessment table (line 807) acknowledges "Certain" probability and "High" impact with documented mitigations
- The README (Phase 5, line 708) lists "Data classification warning (prominent, first section)" as the first content item

This is the correct resolution. The data flow to Anthropic is inherent to how MCP tools work -- any MCP tool that returns content feeds it to the LLM. The plan cannot eliminate this risk without eliminating the tool's purpose. What it can do, and now does, is make the risk impossible to miss and place responsibility with the user.

**Residual risk:** A user who ignores the warning and fetches Restricted/Confidential content. This is a human process risk, not an engineering deficiency.

### CRITICAL-2: Server-Side Request Forgery (E1)

**Previous Rating:** Critical
**Current Rating:** Resolved
**Status:** RESOLVED

The revised plan adds a complete URL validation pipeline (lines 130-165) with nine ordered steps:

1. **Scheme validation** -- HTTPS only; explicitly blocks `file://`, `javascript:`, `data:`, `ftp://`, `http://`
2. **Domain allowlist** -- `*.redhat.com` default, configurable via `config.json`
3. **SSRF filter** -- Blocks RFC 1918 (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), loopback (`127.0.0.0/8`, `::1/128`), link-local (`169.254.0.0/16`), IPv6 private (`fc00::/7`), IPv6 link-local (`fe80::/10`)
4. **DNS resolution check** -- Resolves hostname and verifies resolved IP is not in blocked ranges (DNS rebinding defense)
5. **Max response size** -- 5MB per page load
6. **XXE prevention** -- `resolve_entities=False` on lxml parser
7. **Size truncation** -- 50,000 char limit
8. **Error sanitization** -- Strip internal hostnames/IPs
9. **Audit log entry** -- URL, timestamp, status, size (never content)

The `url_validator.py` module (lines 167-198) provides the implementation skeleton with `validate_url()` returning `(is_valid, error_message)` where error details are for local logging only, never returned via MCP. The `fetch_page` tool specification (lines 336-340) confirms validation happens before any browser interaction, and rejection returns a generic `URL_REJECTED` message that does not reveal which check failed.

Test coverage is specified for all filter categories including DNS rebinding (line 542).

**Residual risk:** See NEW-2 (DNS TOCTOU) below -- Minor severity.

### CRITICAL-3: Unprotected Browser Profile (S1)

**Previous Rating:** Critical
**Current Rating:** Resolved
**Status:** RESOLVED

The revised plan makes a significant architectural change: switching from persistent `userDataDir` to Playwright's `storageState` API (lines 227-257). This change:

- **Eliminates the full Chromium profile directory** -- No more `chromium-profile/` with cookies database, IndexedDB, cache, extensions, etc. The attack surface shrinks from an entire browser profile to a single JSON file (`auth-state.json`)
- **Avoids the macOS headed/headless corruption bug** (Playwright Issue #35466)
- **Sets explicit permissions:** Directory `0700` (line 243), `auth-state.json` at `0600` (line 244)
- **Startup verification:** Checks directory ownership matches current user and permissions are not more permissive than `0700`; refuses to start if wrong (line 245)
- **Secure deletion:** `--wipe-profile` CLI command (line 669)

The `storageState` approach only captures cookies and localStorage (not IndexedDB or service workers), but the plan correctly notes that Red Hat SSO relies on cookies and localStorage, which are captured (line 257).

**Residual risk:** See NEW-3 (SSD wipe limitations) and NEW-5 (storageState scope) below -- both Minor.

### MAJOR-1: No Audit Logging (R1, R2)

**Previous Rating:** Major
**Current Rating:** Resolved
**Status:** RESOLVED

The revised plan adds a dedicated `audit.py` module (lines 288-304) with:

- JSON-lines format at `~/.redhat-browser-mcp/audit.log` (permissions `0600`)
- Fields: timestamp, tool, url, status, content_size, duration_ms
- Explicit rule: never log content
- User-agent string `RedHatBrowserMCP/1.0` for corporate security identification
- Configurable rate limiter: 30 requests/minute default, returns error if exceeded
- `--audit-log` CLI mode to view recent entries (line 670)
- Logs all invocations including failures and validation rejections (line 299)

This fully addresses the original finding. The audit trail enables corporate security investigation and the user-agent allows distinguishing tool traffic from suspicious activity.

### MAJOR-2: Error Message Information Leakage (I2)

**Previous Rating:** Major
**Current Rating:** Resolved
**Status:** RESOLVED

The revised plan adds an Error Sanitizer component (lines 306-319) that:

- Strips internal hostnames (replaces with `[internal-host]`)
- Strips internal IP addresses (replaces with `[internal-ip]`)
- Strips HTTP response headers
- Strips partial page content from timeout errors
- Returns five generic error codes: `AUTH_EXPIRED`, `URL_REJECTED`, `FETCH_FAILED`, `TIMEOUT`, `BROWSER_BUSY`
- Detailed errors are logged locally via audit logger but never returned via MCP

The `fetch_page` specification (line 340) confirms: "If validation fails, return sanitized URL_REJECTED error (do not reveal which specific check failed)."

Test coverage for error sanitization is specified in `test_server.py` (line 654): "Test error sanitization (verify no internal hostnames in MCP responses)."

### MAJOR-3: Profile Directory Tampering (T1)

**Previous Rating:** Major
**Current Rating:** Minor (Downgraded)
**Status:** PARTIALLY RESOLVED

The switch to `storageState` significantly reduces this risk. Instead of a full Chromium profile with extensions, caches, and databases, the attack surface is now a single JSON file (`auth-state.json`). The `0700`/`0600` permissions and startup ownership verification address the access control gap.

However, there is no integrity verification of `auth-state.json` itself. See NEW-1 below.

### MAJOR-4: Loose Dependency Version Pins

**Previous Rating:** Major
**Current Rating:** Resolved
**Status:** RESOLVED

The revised plan pins exact versions (lines 510-515):

| Dependency | Pin |
|-----------|-----|
| `mcp` | `==1.25.0` |
| `playwright` | `==1.49.1` |
| `markdownify` | `==0.14.1` |
| `readability-lxml` | `==0.8.1` |
| `lxml` | `==5.3.0` |
| `pytest` | `==8.3.4` |
| `pytest-asyncio` | `==0.24.0` |
| `pip-audit` | `==2.7.3` |

Additionally, `pip-audit` is integrated into the install script (line 693) and acceptance criteria #15 requires it to report no known vulnerabilities.

---

## New Findings (Introduced by Revisions)

### NEW-1: No Integrity Verification on auth-state.json (Minor)

**Rating:** Minor
**DREAD Score:** Damage=5, Reproducibility=4, Exploitability=4, Affected Users=10, Discoverability=3 = **5.2**

The `auth-state.json` file contains exported cookies and localStorage. While file permissions (`0600`) prevent unauthorized access, there is no integrity check to detect tampering by a process running as the same user (malware, rogue npm script, compromised VS Code extension).

An attacker with same-user write access could modify `auth-state.json` to:
- Inject cookies that redirect requests to attacker-controlled domains
- Add localStorage entries containing prompt injection payloads that get loaded into page context

**Why Minor (not Major):** The permissions check on startup and the `0600` file mode mean only same-user processes can modify the file. If an attacker has same-user code execution, the threat model is already significantly degraded (they could read the file, run their own browser, etc.). Integrity checking adds defense-in-depth but does not change the fundamental trust boundary.

**Recommendation:**
1. Compute and store a SHA-256 hash of `auth-state.json` at write time (in a separate `.hash` file with `0600` permissions)
2. Verify the hash on startup before loading the state
3. If hash mismatch, log a warning and require `--login` to re-authenticate

### NEW-2: DNS Resolution TOCTOU (Minor)

**Rating:** Minor
**DREAD Score:** Damage=6, Reproducibility=2, Exploitability=3, Affected Users=10, Discoverability=2 = **4.6**

The URL validation pipeline resolves the hostname to an IP address and checks it against blocked ranges (Step 4, line 146). Then Playwright fetches the URL (Step 5, line 149). Between resolution and fetch, the DNS record could change (time-of-check, time-of-use). This enables a DNS rebinding attack: an attacker-controlled domain resolves to a public IP during validation, then resolves to `127.0.0.1` or `169.254.169.254` when Playwright fetches.

**Why Minor (not Major):** The domain allowlist (`*.redhat.com`) is the primary defense here. An attacker would need to control a `*.redhat.com` DNS record to exploit this, which implies they have already compromised Red Hat's DNS infrastructure. The DNS check is a secondary defense layer against a threat that the allowlist already mitigates.

**Recommendation:**
1. If the implementation language allows it, pass the resolved IP directly to Playwright rather than the hostname (connect to the IP with the `Host` header set to the original hostname). This eliminates the TOCTOU entirely.
2. Alternatively, document this as an accepted residual risk given the domain allowlist mitigation.

### NEW-3: Secure Deletion Limitations on SSDs (Info)

**Rating:** Info
**DREAD Score:** N/A (informational)

The `--wipe-profile` command performs "overwrite then delete" (line 669). On SSDs with wear leveling, overwriting a file does not guarantee the original data is erased from flash storage -- the SSD controller may write to a new physical location, leaving the original data recoverable via forensic analysis of the raw flash.

**Why Info (not Minor):** This is a hardware-level limitation that affects all software-based secure deletion on modern storage. It is not specific to this tool, and the threat requires physical access to the storage device plus forensic tools. The `0600` permissions and OS-level access controls are the primary defense; `--wipe-profile` is a convenience feature for session cleanup, not a forensic countermeasure.

**Recommendation:** Document in the README that `--wipe-profile` provides best-effort deletion and is not a substitute for full-disk encryption (FileVault on macOS) for protecting sensitive session data at rest.

### NEW-4: Per-Process Rate Limiter (Info)

**Rating:** Info
**DREAD Score:** N/A (informational)

The rate limiter (30 req/min, line 304) is implemented as an `asyncio` token bucket within the server process. Restarting the server resets the rate limit. A determined user (or automated script) could bypass the rate limit by cycling server restarts.

**Why Info (not Minor):** The rate limiter's purpose is to prevent accidental triggering of corporate intrusion detection, not to enforce a security boundary. A user who deliberately circumvents the rate limit is acting intentionally. The audit log (which persists across restarts) still records all requests, preserving accountability.

**Recommendation:** No change needed. The current design is appropriate for its purpose.

### NEW-5: storageState Does Not Capture All Auth Mechanisms (Info)

**Rating:** Info
**DREAD Score:** N/A (informational)

The plan correctly notes (line 257) that `storageState` captures cookies and localStorage but not IndexedDB or service workers. If any Red Hat internal service uses IndexedDB-stored tokens or service worker-mediated authentication, the `--serve` mode may not be authenticated for those services despite a successful `--login`.

**Why Info:** The plan explicitly acknowledges this tradeoff and states Red Hat SSO relies on cookies and localStorage. This is a functional limitation, not a security issue. If it causes auth failures, the user gets an `AUTH_EXPIRED` error and re-authenticates -- no security boundary is violated.

**Recommendation:** No change needed. The plan already documents this tradeoff.

---

## Updated Risk Assessment

| ID | Threat | Previous | Current | Status |
|----|--------|----------|---------|--------|
| CRITICAL-1 | Internal content sent to Anthropic cloud | Critical | Info (Accepted, Documented) | RESOLVED |
| CRITICAL-2 | SSRF via fetch_page | Critical | Resolved | RESOLVED |
| CRITICAL-3 | Unprotected browser profile | Critical | Resolved | RESOLVED |
| MAJOR-1 | No audit trail | Major | Resolved | RESOLVED |
| MAJOR-2 | Error message leakage | Major | Resolved | RESOLVED |
| MAJOR-3 | Profile tampering | Major | Minor | PARTIALLY RESOLVED (see NEW-1) |
| MAJOR-4 | Loose dependency pins | Major | Resolved | RESOLVED |
| NEW-1 | No integrity check on auth-state.json | -- | Minor | NEW |
| NEW-2 | DNS resolution TOCTOU | -- | Minor | NEW |
| NEW-3 | SSD secure deletion limitations | -- | Info | NEW |
| NEW-4 | Per-process rate limiter reset | -- | Info | NEW |
| NEW-5 | storageState auth scope limitations | -- | Info | NEW |

---

## Updated Compliance Checklist

- [x] **OWASP A01 (Broken Access Control):** PASS -- URL allowlist, SSRF filter, DNS resolution check, HTTPS-only
- [x] **OWASP A02 (Cryptographic Failures):** PASS -- File permissions `0600`/`0700`, storageState reduces sensitive data surface
- [x] **OWASP A03 (Injection):** PASS -- URL scheme validation, regex length limit on `list_links`
- [x] **OWASP A04 (Insecure Design):** PASS -- Data flow risk documented with user obligations; inherent to MCP architecture
- [x] **OWASP A05 (Security Misconfiguration):** PASS -- Explicit permissions, startup verification, XXE disabled
- [x] **OWASP A06 (Vulnerable Components):** PASS -- Exact version pins, `pip-audit` in install script
- [x] **OWASP A07 (Auth Failures):** PASS -- SSO delegation, session expiry detection, re-auth guidance
- [x] **OWASP A08 (Data Integrity):** PARTIAL -- File permissions protect integrity from other users; same-user integrity not verified (NEW-1)
- [x] **OWASP A09 (Logging Failures):** PASS -- Audit logging with timestamps, URL, status; rate limiting; user-agent identification
- [x] **OWASP A10 (SSRF):** PASS -- Multi-layer defense: scheme validation, domain allowlist, IP range blocking, DNS resolution check

**Corporate Compliance:**
- [x] Data classification obligations documented with explicit user responsibility
- [x] Audit logging enables investigation of internal access patterns
- [x] User-agent identification allows corporate security to classify traffic
- [ ] Red Hat InfoSec approval for data flow (user obligation, not tool responsibility)
- [ ] Enterprise agreement review (user obligation)

---

## Verdict Rationale

**PASS** -- The revised plan addresses all three Critical and all four Major findings from the first review:

1. **CRITICAL-1 (Data Exfiltration)** is now explicitly documented as an accepted, inherent risk of MCP architecture with prominent warnings and user obligations. This is the correct resolution -- the plan cannot eliminate a risk that is fundamental to its purpose.

2. **CRITICAL-2 (SSRF)** is fully mitigated with a nine-step validation pipeline including scheme validation, domain allowlist, SSRF IP filtering, and DNS rebinding defense. Test coverage is specified for all filter categories.

3. **CRITICAL-3 (Unprotected Profile)** is resolved through an architectural improvement: switching from a persistent Chromium profile directory to a single `storageState` JSON file with `0600` permissions and startup ownership verification.

All four Major findings (audit logging, error sanitization, profile integrity, dependency pins) are resolved or downgraded to Minor.

Five new issues were identified, none exceeding Minor severity. The two Minor findings (auth-state integrity, DNS TOCTOU) represent defense-in-depth opportunities that do not block implementation. The three Info findings are inherent limitations that are already adequately documented or appropriate for the use case.

The plan is ready for implementation.

---

## Recommended Improvements (Non-Blocking)

These are optional enhancements the implementer may consider during or after implementation:

1. **auth-state.json integrity hash** (NEW-1) -- Low effort, adds a defense-in-depth layer
2. **Direct IP connection in Playwright** (NEW-2) -- Eliminates DNS TOCTOU if Playwright's API supports it; otherwise document as accepted risk
3. **FileVault note in README** (NEW-3) -- One sentence documenting that full-disk encryption is recommended

---

## Artifact Location

**Plan File:** `./plans/redhat-internal-browser-mcp.md`
**Red Team Review:** `./plans/redhat-internal-browser-mcp.redteam.md`
