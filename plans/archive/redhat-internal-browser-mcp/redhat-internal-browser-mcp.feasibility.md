# Feasibility Review: Red Hat Internal Browser MCP Server (Second Pass)

**Plan:** `./plans/redhat-internal-browser-mcp.md`
**Reviewed:** 2026-02-24
**Reviewer:** code-reviewer agent (claude-opus-4-6)
**Previous Review:** 2026-02-24 (verdict: REVISE)

---

## Verdict: PASS

The revised plan addresses all Critical and Major concerns from the first review. The storageState authentication model is correct, the event loop integration is specified, and the content extraction pipeline now includes the necessary fallback and custom converter logic. The plan is ready for implementation. Two new minor concerns are noted below but are non-blocking.

---

## Previous Critical Concerns -- Resolution Status

### C1. Playwright headed/headless profile corruption (was: CRITICAL)

**Status: RESOLVED.**

The revised plan replaces the persistent `userDataDir` approach entirely with Playwright's `storageState` API. The authentication flow is now:

1. `--login` mode launches a headed browser with a **temporary** persistent context (line 249)
2. After user authentication, exports state via `context.storage_state(path=AUTH_STATE_PATH)` (line 251)
3. `--serve` mode launches a **fresh headless browser** and creates a new context with `browser.new_context(storage_state=AUTH_STATE_PATH)` (line 253)

This avoids the macOS profile corruption bug (Playwright Issue #35466) entirely because headed and headless modes never share a `userDataDir`. The plan explicitly documents the tradeoff (IndexedDB and service workers are not captured by storageState) and correctly notes that Red Hat SSO relies on cookies and localStorage, which are captured.

The plan also includes a dedicated section (lines 256-257) explaining **why** storageState was chosen over persistent userDataDir, which is good for future maintainers.

No remaining concerns.

### C2. Async event loop integration (was: CRITICAL)

**Status: RESOLVED.**

The revised plan specifies the event loop model in three locations:

1. **server.py design** (lines 214-216): Explicit comment that `mcp.run()` creates the event loop and `browser.launch()` is awaited within tool handlers on that same loop.

2. **server.py detail** (line 219): States that `BrowserManager.launch()` uses `playwright.async_api.async_playwright()` which attaches to the current running loop, and that the browser manager **never creates its own event loop**.

3. **browser.py Phase 2** (line 562): Reiterates that all methods are async coroutines called from MCP tool handlers on the loop created by `mcp.run()`, with a 15-second browser launch timeout separate from page timeouts.

This is the correct architecture. The MCP Python SDK's `mcp.run(transport="stdio")` starts the asyncio event loop, and Playwright's async API cooperates with whatever loop is currently running. No deadlock risk.

No remaining concerns.

---

## Previous Major Concerns -- Resolution Status

### M1. readability-lxml fallback pipeline (was: MAJOR)

**Status: RESOLVED.**

The revised plan adds a fallback pipeline in the content processor design (lines 267-270) and Phase 3 implementation (lines 595-598):

- If `readability-lxml` returns content below 200 characters, fall back to semantic selectors in order: `<main>`, `<article>`, `[role="main"]`, `#content`, `.content`, `#main`
- Final fallback: `<body>` minus `<nav>`, `<header>`, `<footer>`, `<aside>`
- Log which extraction method succeeded

The 200-character threshold is reasonable. The selector order prioritizes semantic HTML elements before ID/class-based selectors, which is correct. The logging of which method succeeded will be valuable for debugging content extraction quality during the Week 2 validation stage.

The plan also adds a Confluence-specific test fixture (`tests/fixtures/confluence_page.html`, line 613) to validate the fallback pipeline, which directly addresses the concern about low text-density Confluence pages.

No remaining concerns.

### M2. markdownify table conversion (was: MAJOR)

**Status: RESOLVED.**

The revised plan specifies a custom `MarkdownConverter` subclass (`RedHatMarkdownConverter`, line 599) with:

- Custom `convert_table` method that degrades `colspan`/`rowspan` to indented plain text (line 600)
- `table_infer_header=True` for tables missing `<thead>` (line 601)
- Handling of nested `<div>` and `<p>` inside `<td>` cells (line 602)

The degradation strategy (indented plain text instead of invalid markdown tables) is the right call. Invalid markdown tables are worse than no tables at all because they corrupt the LLM's context. The test fixture for complex tables (`tests/fixtures/complex_tables.html`, line 614) covers the specific scenarios raised in the first review.

No remaining concerns.

### M3. Line count estimates (was: MAJOR)

**Status: RESOLVED.**

The revised plan updates the total estimate to ~2,000 lines (line 946) and the timeline to 5-7 days (line 947), both within the range recommended in the first review (1,600-1,800 lines, 5-7 days). Individual file estimates have been updated realistically (e.g., server.py at 280 lines, browser.py at 260 lines).

No remaining concerns.

### M4. Concurrency model (was: MAJOR)

**Status: RESOLVED.**

The revised plan specifies the concurrency model explicitly in the browser manager design (line 231):

- `asyncio.Semaphore(3)` controls the page pool
- Each tool call acquires semaphore, creates page, navigates, extracts, closes page, releases
- If all 3 slots are occupied, the caller waits up to 30 seconds
- On timeout, returns `BROWSER_BUSY` error
- **No global navigation lock** -- the semaphore alone is sufficient

This is the correct model. Each tool call gets its own page lifecycle, the semaphore prevents resource exhaustion, and the 30-second wait timeout with a clear error message handles the exhaustion case gracefully. The removal of the global navigation lock from the original plan is important -- it would have serialized all tool calls unnecessarily.

No remaining concerns.

### M5. Zombie process recovery (was: MAJOR)

**Status: RESOLVED.**

The revised plan adds comprehensive zombie process handling (lines 232-237):

- On startup: check PID file, verify liveness with `os.kill(pid, 0)`, SIGTERM if alive
- After launch: write browser PID to PID file
- Signal handlers for SIGTERM/SIGINT call `browser.close()`
- `atexit` handler removes PID file
- Catch `TargetClosedError` in page operations; reset browser reference for auto-relaunch

This covers all three failure modes raised in the first review (SIGKILL orphans, Chromium OOM crashes, stale atexit handlers). The `TargetClosedError` catch-and-relaunch pattern is particularly important -- it means the server self-heals after a Chromium crash without requiring manual intervention.

No remaining concerns.

---

## Previous Minor Concerns -- Resolution Status

| ID | Concern | Status |
|----|---------|--------|
| m1 | `mcp>=1.25,<2` too narrow | **PARTIALLY ADDRESSED.** Plan now pins exact version `mcp==1.25.0` (line 510). Exact pinning is stricter than the range constraint but is appropriate for an MCP server where reproducibility matters more than compatibility breadth. Acceptable. |
| m2 | `search_page` deferred | **RESOLVED.** Removed from v1, deferred to v2 (line 473). Tool count reduced to 3. |
| m3 | `check_auth` session age | **RESOLVED.** Uses `~/.redhat-browser-mcp/last-login` timestamp file (line 403). Documented as approximate. |
| m4 | `claude` CLI PATH check | **RESOLVED.** Install script checks `command -v claude` with helpful error message (lines 682-685). |
| m5 | Missing `.gitignore` | **RESOLVED.** `.gitignore` included in Phase 1 scaffolding (lines 501-508, also line 411). |
| m6 | `filter` shadows builtin | **RESOLVED.** Renamed to `link_filter` (line 365). |

All minor concerns from the first review have been addressed.

---

## New Concerns Introduced by Revisions

### N1. (Minor) PID file race condition on startup

The PID file check (lines 233-234) has a TOCTOU race: the server reads the PID file, checks liveness with `os.kill(pid, 0)`, then sends SIGTERM. Between the liveness check and SIGTERM, the stale process could exit and a new unrelated process could take the same PID. On macOS this is extremely unlikely (PID recycling is slow and the window is microseconds), but it is worth noting in code comments during implementation.

**Recommendation:** Add a code comment acknowledging the race. No code change needed -- the risk is negligible on macOS and a PID-namespace solution would be over-engineering.

### N2. (Minor) DNS resolution check has a TOCTOU gap with Playwright navigation

The URL validation pipeline resolves the hostname and checks the resolved IP against blocked ranges (lines 146-147) **before** passing the URL to Playwright. However, Playwright performs its own DNS resolution when navigating. If the DNS response changes between the validator's resolution and Playwright's resolution (DNS rebinding attack), the SSRF filter is bypassed.

This is a known limitation of application-layer SSRF filters. Mitigations:

- The domain allowlist (`*.redhat.com`) already limits the attack surface to Red Hat-controlled DNS
- An attacker would need to control a `*.redhat.com` DNS record to exploit this
- The combination of allowlist + SSRF filter makes exploitation impractical in this threat model

**Recommendation:** Document this limitation in a code comment in `url_validator.py`. The current mitigation (allowlist constrains DNS to trusted domains) is sufficient for this use case. A more robust fix (intercepting Playwright's DNS resolution via a custom DNS resolver or proxy) would add significant complexity for negligible security benefit given the domain allowlist.

### N3. (Minor) `--wipe-profile` secure deletion is best-effort on APFS

The plan mentions "overwrite then delete" for `--wipe-profile` (line 669). On macOS APFS (which uses copy-on-write), overwriting a file does not guarantee the original data blocks are erased -- the filesystem may write to new blocks and mark old blocks as free without zeroing them. True secure deletion on APFS requires either FileVault (which encrypts at rest, making block-level recovery moot) or the deprecated `rm -P` flag (which Apple removed because it is ineffective on SSDs/APFS).

**Recommendation:** Document in the README that `--wipe-profile` performs best-effort deletion and that FileVault disk encryption is the recommended protection for data at rest. Most Red Hat corporate macOS machines have FileVault enabled by default, so this is likely a non-issue in practice.

---

## What the Revised Plan Gets Right

1. **storageState architecture** -- The authentication model is now technically sound. The separation between "headed temporary context for login" and "fresh headless context with injected state for serving" avoids the Playwright profile corruption bug cleanly. The explicit documentation of the tradeoff (no IndexedDB/service workers) shows the author understands the API surface.

2. **Security depth** -- The addition of URL validation (SSRF filter + DNS resolution check + domain allowlist), error sanitization (no internal hostnames in MCP responses), audit logging (JSON lines, never log content), file permission hardening (0700/0600 with ownership verification), and rate limiting (30 req/min) significantly exceeds what most internal tools implement. The security architecture diagram (lines 131-165) is clear and auditable.

3. **Content extraction resilience** -- The fallback pipeline (readability -> semantic selectors -> body minus chrome) with logging of which method succeeded is a pragmatic approach. The Confluence-specific test fixture shows the author internalized the concern about low-density SPA pages.

4. **Error sanitization as a first-class concern** -- The error sanitizer module (lines 306-319) that strips internal hostnames and IPs before MCP responses is important because MCP tool output goes to Anthropic's API. This was not in the original plan and is a meaningful security improvement.

5. **Honest estimates** -- The revised timeline (5-7 days) and line count (~2,000) reflect the actual complexity. The inclusion of "Week 2: Daily Use Validation" in the rollout plan shows realistic expectations about content extraction iteration.

6. **Removed scope** -- Deferring `search_page` to v2 reduces implementation risk without losing meaningful functionality, since Claude Code can search returned markdown natively.

---

## Recommendations

No blocking recommendations. The plan is ready for implementation.

For the implementer:

1. Add a code comment in `url_validator.py` acknowledging the DNS TOCTOU gap (N2) and noting that the domain allowlist makes it impractical to exploit.
2. Add a code comment in `browser.py` acknowledging the PID file race condition (N1) as negligible on macOS.
3. Document in the README that `--wipe-profile` is best-effort on APFS and recommend FileVault (N3).
4. During Week 2 validation, pay particular attention to content extraction quality on Confluence pages and Angular-based internal dashboards. The fallback pipeline is the right architecture but the selector order and threshold may need tuning based on real page structures.

---

## References

- [Playwright storageState API](https://playwright.dev/docs/auth#reuse-signed-in-state) -- Documents the recommended approach for authentication reuse
- [Playwright Issue #35466](https://github.com/microsoft/playwright/issues/35466) -- macOS headed/headless profile corruption (original motivating bug)
- [APFS Copy-on-Write and Secure Deletion](https://support.apple.com/en-us/102631) -- Apple's documentation on why secure erase is ineffective on SSDs/APFS
- [DNS Rebinding Attacks](https://en.wikipedia.org/wiki/DNS_rebinding) -- Background on the TOCTOU gap in application-layer SSRF filters

<!-- Feasibility Review Metadata
reviewed_at: 2026-02-24T17:00:00Z
plan_file: ./plans/redhat-internal-browser-mcp.md
verdict: PASS
previous_verdict: REVISE
critical_resolved: 2/2
major_resolved: 5/5
minor_resolved: 6/6
new_concerns: 3 (all minor)
-->
