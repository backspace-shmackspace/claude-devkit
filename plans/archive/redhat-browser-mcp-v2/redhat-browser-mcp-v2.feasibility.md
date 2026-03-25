# Feasibility Review: Re-architect Red Hat Internal Browser MCP to helper-mcps (Revision 1)

**Plan:** `./plans/redhat-browser-mcp-v2.md`
**Reviewer:** Code Reviewer Specialist Agent
**Date:** 2026-02-24
**Revision Round:** 1 (previous review: same file, pre-revision)
**Verdict:** PASS

---

## Previous Major Concerns -- Resolution Status

### M1. `_is_retryable()` will crash on `import httpx` if httpx is not installed -- RESOLVED

The revised plan explicitly addresses this in Assumption 5 (line 41), Phase 1 step 1 (lines 240-257), and the Risk Assessment table (line 638). The plan includes the exact `try/except ImportError` fix in `shared/server_base.py` with the corrected code shown inline. It is correctly sequenced as the first task in Phase 1, before any redhat-browser-mcp code is written. The plan also adds a test case for this (Phase 1, step 4: "Test `_is_retryable()` returns False for arbitrary exceptions when httpx is not installed"). No remaining issues.

### M2. Persistent browser lifecycle gaps (SSO expiry, browser crash recovery) -- RESOLVED

The revised plan addresses both edge cases in Phase 4 (lines 354-358):

- **SSO cookie expiry:** `_recreate_context()` method calls `self._auth.refresh_if_needed()`, re-reads storage state from disk, and creates a new context with fresh cookies. `fetch_page()` detects SSO redirects and calls `_recreate_context()` then retries once.
- **Browser crash:** `_restart_browser()` performs a full `close()` + `start()` cycle. On `TargetClosedError`, `fetch_page()` calls `_restart_browser()` and retries once; if the restart also fails, it raises a non-retryable error.
- **`check_auth_status()`:** Explicitly stated to create a new page within the existing context and acquire the semaphore (line 359), addressing the concurrency concern from minor m2.

The recovery paths are well-defined with bounded retries (once each). No remaining issues.

### M3. `get_headers()` raising `AuthenticationError` violates LSP -- RESOLVED

The revised plan adopts option (a) from the previous review: `get_headers()` returns an empty dict `{}` with a logged warning (lines 68, 163-164, 263). The plan also updates the `CredentialProvider` ABC docstring to document that not all providers support header-based auth (Phase 1, step 2, lines 258-259). The `BrowserClient` is typed against `PlaywrightStorageStateProvider` concretely rather than the ABC, avoiding `hasattr` dispatch (lines 69-70, 350). This is a clean resolution that preserves LSP compliance while being pragmatic about the type system.

---

## Concerns

### Critical

None.

### Major

None.

### Minor

**m1. The `response.body` bug from v1 is still silently ported**

The previous review (m5) identified that in `/Users/imurphy/projects/claude-devkit/mcp-servers/redhat-browser/src/redhat_browser/browser.py` lines 177-186, the `except Exception: pass` block swallows the `ContentExtractionError` raised when a response exceeds `max_response_size`. The `if response.body:` check also evaluates the bound method (always truthy) rather than calling it.

The revised plan (Phase 3-4) does not mention fixing this bug. Phase 3 says "Keep all extraction logic unchanged" and Phase 4's `fetch_page()` description does not reference a size check at all. During implementation, this should be fixed rather than carried forward. The corrected pattern would be:

```python
if response:
    try:
        body = await response.body()
    except Exception:
        body = None
    if body is not None and len(body) > self.max_response_size:
        raise ContentExtractionError(
            f"Response too large: {len(body)} bytes (max: {self.max_response_size})"
        )
```

This separates the body-fetch error handling from the size validation, ensuring the size check actually blocks oversized responses.

---

**m2. Login CLI migration path is underspecified**

The revised plan's Non-Goals (line 31) state the three tools retain the same semantics, and Assumption 3 (line 39) says "Interactive login remains a host-side CLI operation." However, the existing FastMCP version has a full CLI module at `/Users/imurphy/projects/claude-devkit/mcp-servers/redhat-browser/src/redhat_browser/cli.py` with `--login`, `--check`, `--wipe-profile`, and `--audit-log` commands. None of these appear in the Phase 2-12 file manifests.

Without a login script, new users or users whose cookies expire will have no documented way to create `auth-state.json`. The plan's Task Breakdown (lines 700-745) lists 16 files to create but no login utility.

**Recommendation:** Add a `redhat-browser-mcp/login.py` (or a section in the plan's Phase 11 documenting a one-liner alternative such as `playwright codegen --save-storage=~/.redhat-browser-mcp/auth-state.json https://source.redhat.com`). This does not need to replicate the full CLI -- just the `--login` flow.

---

**m3. Audit log file write is not atomic and has no rotation**

The plan (Phase 4, line 364) preserves the v1 audit pattern: append a JSON-lines record to `/audit/access.log` on each tool invocation. The existing implementation at `/Users/imurphy/projects/claude-devkit/mcp-servers/redhat-browser/src/redhat_browser/audit.py` opens the file, appends, and closes per write (lines 68-69). In the containerized deployment:

1. Concurrent tool calls (up to `max_concurrent=3`) could interleave writes within a single line if the JSON string exceeds the OS pipe buffer size (typically 4KB on Linux). JSON audit records are small enough that this is unlikely, but the plan does not address it.
2. There is no log rotation. In a long-running container, the audit log will grow unbounded. For a personal tool this is acceptable, but the plan should acknowledge it.

**Recommendation:** Use `fcntl.flock()` or write to a `logging.FileHandler` (which handles buffering) rather than raw `open()/write()`. Alternatively, acknowledge the limitation and note that log rotation is out of scope for v1.

---

**m4. Dockerfile installs Playwright browsers as root, then switches to non-root user**

The Dockerfile in Phase 8 (lines 443-478) runs `playwright install chromium` before the `USER mcpuser` directive. This means Chromium is installed into root-owned directories. When `mcpuser` runs `chromium.launch()`, Playwright resolves the browser binary from `~/.cache/ms-playwright/` or the system-wide path. Since `playwright install` ran as root, the binaries are in `/root/.cache/ms-playwright/` which `mcpuser` cannot read.

**Recommendation:** Either run `playwright install chromium` after `USER mcpuser` (requires the directory to be writable), or set `PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers` before installation and ensure the directory is world-readable:

```dockerfile
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers
RUN mkdir -p /opt/pw-browsers && playwright install chromium && chmod -R o+rX /opt/pw-browsers
```

This is a common pitfall with Playwright + non-root Docker containers.

---

**m5. `networkidle` wait strategy preserved without comment**

Carried forward from the previous review (m3). The plan ports `wait_until="networkidle"` from v1. Many Red Hat internal pages (Jira, Confluence, internal dashboards) have persistent WebSocket connections that prevent `networkidle` from resolving, causing every request to hit the 30-second timeout before content extraction begins. The plan should either switch to `domcontentloaded` as the default or document this as a known limitation with a future improvement note.

---

**m6. Effort estimate removed but Phase 4 and Phase 9 remain the highest-risk phases**

The previous review (m7) noted that "2-3 engineering sessions" was optimistic. The revised plan removes the effort estimate entirely, which is fine. For planning purposes: Phase 4 (browser client with recovery logic) and Phase 9 (tests with mocked Playwright async context managers) will each likely require a full session. The total is likely 4 sessions.

---

## Verdict Rationale

**PASS.** All three Major concerns from the previous review have been substantively addressed in the revised plan:

1. The `_is_retryable()` httpx import crash is fixed with a `try/except ImportError` wrapper in Phase 1, correctly sequenced before any redhat-browser-mcp code.
2. The persistent browser lifecycle now includes explicit `_recreate_context()` (SSO recovery) and `_restart_browser()` (crash recovery) methods with bounded retry logic.
3. The `get_headers()` LSP violation is resolved by returning empty `{}` with a logged warning, and the ABC docstring is updated.

The remaining concerns are all Minor. The most actionable are m2 (login script) and m4 (Playwright browser path for non-root user), both of which are implementation details that can be resolved during coding without changing the plan's architecture.

---

## Recommended Adjustments

1. **Fix the `response.body` bug during Phase 4** rather than porting it from v1. Separate the body-fetch `try/except` from the size validation `raise`. (Carried forward from previous review m5.)

2. **Add a login utility or documented procedure** for creating the initial `auth-state.json` file. Either create `redhat-browser-mcp/login.py` or add a documented `playwright codegen` one-liner to the plan. (Carried forward from previous review m6.)

3. **Set `PLAYWRIGHT_BROWSERS_PATH`** in the Dockerfile to a world-readable location so the non-root `mcpuser` can access the Chromium binary installed by `playwright install`.

4. **Acknowledge audit log rotation is out of scope** or add a `logging.handlers.RotatingFileHandler` for the audit trail.

5. **Consider `domcontentloaded`** as the default wait strategy with `networkidle` as an opt-in parameter, to avoid 30-second timeouts on pages with persistent connections.

---

## Plan Metadata

- **Reviewed Plan:** `./plans/redhat-browser-mcp-v2.md`
- **Previous Review:** `./plans/redhat-browser-mcp-v2.feasibility.md` (pre-revision, verdict: PASS_WITH_NOTES)
- **Date:** 2026-02-24
- **Reviewer:** Code Reviewer Specialist Agent
- **Files Examined:**
  - `/Users/imurphy/projects/claude-devkit/plans/redhat-browser-mcp-v2.md` (revised plan)
  - `/Users/imurphy/projects/claude-devkit/plans/redhat-browser-mcp-v2.feasibility.md` (previous feasibility review)
  - `/Users/imurphy/projects/workspaces/helper-mcps/CLAUDE.md` (monorepo conventions)
  - `/Users/imurphy/projects/workspaces/helper-mcps/shared/server_base.py` (confirmed `_is_retryable()` still has bare `import httpx` at line 107)
  - `/Users/imurphy/projects/workspaces/helper-mcps/shared/auth.py` (confirmed `CredentialProvider` ABC, `PATCredentialProvider`, `OAuthCredentialProvider`)
  - `/Users/imurphy/projects/claude-devkit/mcp-servers/redhat-browser/src/redhat_browser/browser.py` (confirmed `response.body` bug at lines 177-186)
  - `/Users/imurphy/projects/claude-devkit/mcp-servers/redhat-browser/src/redhat_browser/cli.py` (confirmed full CLI with `--login`, `--check`, `--wipe-profile`, `--audit-log`)
  - `/Users/imurphy/projects/claude-devkit/mcp-servers/redhat-browser/src/redhat_browser/audit.py` (confirmed audit log append pattern)
