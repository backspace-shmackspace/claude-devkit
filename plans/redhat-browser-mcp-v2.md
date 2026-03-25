# Plan: Re-architect Red Hat Internal Browser MCP to helper-mcps Shared Library

## Context

The Red Hat Internal Browser MCP server currently lives at `claude-devkit/mcp-servers/redhat-browser/` and is built on FastMCP -- a convenience wrapper that does not match the architecture of the `helper-mcps` monorepo where all other MCP servers reside. The existing implementation uses global singletons, FastMCP decorators, and has no lifecycle state machine, no structured logging, no `BaseMCPServer` inheritance, and no Docker containerization following the monorepo conventions.

This plan re-architects the server as `redhat-browser-mcp/` inside the `helper-mcps` monorepo, following every pattern established by the existing jira-mcp, gmail-mcp, and google-workspace-mcp servers. The existing business logic (Playwright browser automation, URL validation with SSRF protection, content extraction pipeline, audit logging, rate limiting) is preserved and refactored into the shared library patterns.

**Current state:** A working FastMCP implementation at `claude-devkit/mcp-servers/redhat-browser/` with 6 source modules (`server.py`, `browser.py`, `auth.py`, `url_validator.py`, `content.py`, `audit.py`, `config.py`). The `helper-mcps` monorepo has 3 servers and a mature shared library.

**Target state:** A new `redhat-browser-mcp/` package inside `helper-mcps/` that inherits from `BaseMCPServer`, uses the lifecycle state machine, structured logging, and a new `PlaywrightStorageStateProvider` credential provider. The `claude-devkit/mcp-servers/` directory is deleted entirely.

## Goals

1. **Move the server** to `helper-mcps/redhat-browser-mcp/` following the exact package structure of `jira-mcp/`.
2. **Replace FastMCP** with `BaseMCPServer` inheritance and raw `mcp` SDK `Server` class.
3. **Add a new `PlaywrightStorageStateProvider`** to `shared/auth.py` that implements the `CredentialProvider` ABC for Playwright `storageState` cookie files.
4. **Implement the lifecycle state machine** (INITIALIZING -> SERVICE_VALIDATED -> STDIO_VALIDATED -> READY) in `__main__.py`.
5. **Use structured JSON logging** via `configure_logging()` everywhere instead of `print()` statements.
6. **Return `ToolError`** on failures with `retryable` flag instead of emoji-prefixed error strings.
7. **Add a Dockerfile** with Playwright browser installation for containerized deployment, running as a non-root user.
8. **Write unit tests** with mocked Playwright to meet the 90% coverage threshold.
9. **Delete `claude-devkit/mcp-servers/`** and revert any CLAUDE.md changes that referenced it.
10. **Update `helper-mcps` configuration** (pyproject.toml, Makefile, docker-compose.yml, CLAUDE.md).
11. **Maintain read-only invariant.** The server is strictly read-only -- it fetches and returns page content but never creates, updates, or deletes external resources, conforming to the `helper-mcps` read-only invariant documented in `CLAUDE.md`.

## Non-Goals

1. **Changing the tool semantics.** The three tools (`fetch_page`, `list_links`, `check_auth`) retain the same names, input schemas, and output contracts.
2. **Adding new tools.** No new functionality beyond what the FastMCP version provides.
3. **Implementing PAT or OAuth auth.** The server uses Playwright storageState exclusively. The new `CredentialProvider` subclass handles this.
4. **Modifying other servers.** jira-mcp, gmail-mcp, google-workspace-mcp are untouched.
5. **Running Playwright inside Docker without Chromium.** The Dockerfile will install Chromium via `playwright install --with-deps chromium`.

## Assumptions

1. The `helper-mcps` monorepo is the canonical location for all MCP servers. The `claude-devkit/mcp-servers/` directory was a temporary staging area.
2. The Playwright storageState file lives at `~/.redhat-browser-mcp/auth-state.json` on the host and is volume-mounted into the container at `/secrets/auth-state.json`.
3. Interactive login (`--login` flow) remains a host-side CLI operation, not a containerized operation (Playwright needs a visible browser window for SSO).
4. Python 3.12 is the target runtime, consistent with the monorepo.
5. The `_is_retryable()` function in `server_base.py` currently does `import httpx` unconditionally at the top of the function body (line 107). Since `redhat-browser-mcp` does not install `httpx`, this will raise `ImportError` on every tool error, preventing `ToolError` wrapping from working. **This plan includes a fix:** wrap the `import httpx` in `try/except ImportError` in `server_base.py` as part of Phase 1, so that non-httpx servers fall through to the `isinstance(exc, ConnectionError)` check. This is a 3-line change that benefits all future non-httpx servers.

## Proposed Design

### Architectural Analysis

**Problem:** The current FastMCP implementation violates every convention in the helper-mcps monorepo:
- No `BaseMCPServer` inheritance
- No lifecycle state machine
- No structured logging
- No `CredentialProvider` interface
- No `ToolError` return type
- No Docker container
- Lives in the wrong repository

**Key Architectural Drivers:**
1. **Consistency** -- All MCP servers must follow the same patterns for maintainability.
2. **Observability** -- Structured JSON logging to stderr enables log aggregation.
3. **Reliability** -- Lifecycle state machine prevents serving requests before validation.
4. **Security** -- storageState files contain session cookies and must be handled with the same rigor as PAT tokens.

**Auth Pattern Decision:**

The existing `CredentialProvider` ABC has three methods: `get_headers()`, `validate()`, `refresh_if_needed()`. The Playwright storageState pattern is fundamentally different from PAT/OAuth because it does not produce HTTP headers -- it produces a Playwright `storageState` dict that is passed to `browser.new_context(storage_state=...)`. However, implementing the ABC is still correct because:

- `validate()` checks that the storageState file exists, is valid JSON, and contains cookies.
- `refresh_if_needed()` re-reads the file from disk (same as PATCredentialProvider).
- `get_headers()` returns an empty dict `{}` with a logged warning. This is a pragmatic choice: returning empty headers is semantically accurate (there are no HTTP headers for this auth type) and avoids violating the Liskov Substitution Principle. Any shared library code that calls `get_headers()` generically will receive an empty dict rather than an unexpected exception. The `BrowserClient` never calls `get_headers()` -- it calls `get_storage_state()` directly.

We add one new method to the subclass: `get_storage_state() -> dict` which returns the parsed storageState JSON. To avoid fragile `hasattr` dispatch, `BrowserClient` types its constructor parameter as `PlaywrightStorageStateProvider` directly (not the `CredentialProvider` ABC), since it has no use for other credential types. The ABC docstring in `shared/auth.py` will be updated with a note that not all providers support header-based auth, and that callers requiring storage-state auth should type-check against `PlaywrightStorageStateProvider`.

### Component Boundaries

```
helper-mcps/
  shared/
    auth.py                    # + PlaywrightStorageStateProvider (new subclass)
    server_base.py             # modified: _is_retryable() httpx import wrapped in try/except
    types.py                   # unchanged
    logging_config.py          # unchanged
    lifecycle.py               # unchanged
  redhat-browser-mcp/
    __init__.py                # Module docstring
    __main__.py                # Entry point with lifecycle state machine
    server.py                  # RedHatBrowserMCPServer(BaseMCPServer)
    browser_client.py          # BrowserClient (replaces BrowserSession)
    url_validator.py           # Preserved from FastMCP (minor cleanup)
    content.py                 # Preserved from FastMCP (minor cleanup)
    auth_adapter.py            # Factory: create_auth_provider()
    config.py                  # Preserved from FastMCP (minor cleanup)
    requirements.txt           # playwright, mcp, pydantic, readability-lxml, etc.
    Dockerfile                 # Multi-stage build with Playwright + Chromium
    tests/
      __init__.py
      test_server.py           # Tool registration and handler dispatch
      test_browser_client.py   # Browser client with mocked Playwright
      test_url_validator.py    # URL validation and SSRF protection
      test_content.py          # Content extraction pipeline
      test_auth_adapter.py     # Auth adapter factory
  tests/
    test_auth.py               # + tests for PlaywrightStorageStateProvider
```

### Data Flow

```
Claude Code  --stdio-->  __main__.py (lifecycle)  -->  RedHatBrowserMCPServer
                                                           |
                                                     _register_tools()
                                                           |
                                           fetch_page / list_links / check_auth
                                                           |
                                                     BrowserClient
                                                           |
                                          PlaywrightStorageStateProvider.get_storage_state()
                                                           |
                                          Playwright browser.new_context(storage_state=...)
                                                           |
                                                     page.goto(url)
                                                           |
                                              url_validator.validate_url()
                                              content.extract_main_content()
                                                           |
                                                  TextContent (JSON)  --stdio-->  Claude Code
```

### Technology Stack

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| MCP Protocol | `mcp` SDK (raw Server) | Matches monorepo pattern; no FastMCP dependency |
| Browser | Playwright (async) | Required for SSO-protected pages with JS rendering |
| Content extraction | readability-lxml, beautifulsoup4, markdownify | Preserved from working FastMCP implementation |
| URL validation | stdlib (ipaddress, socket, urllib, fnmatch) | Zero-dependency SSRF protection |
| Models | Pydantic v2 | Monorepo standard |
| Logging | shared/logging_config.py | Structured JSON to stderr |
| Testing | pytest, pytest-asyncio, unittest.mock | Monorepo standard |

## Interfaces / Schema Changes

### New: PlaywrightStorageStateProvider (shared/auth.py)

```python
class PlaywrightStorageStateProvider(CredentialProvider):
    """Playwright storageState authentication for browser-based MCP servers.

    Reads a Playwright storageState JSON file containing cookies and
    localStorage from a prior interactive browser login session.

    Storage state file path resolution:
    1. Explicit path passed to constructor
    2. Environment variable (state_env_var)
    3. Default path (/secrets/auth-state.json)
    """

    def __init__(
        self,
        state_path: str | Path | None = None,
        state_env_var: str = "MCP_STORAGE_STATE_PATH",
        default_path: str = "/secrets/auth-state.json",
    ) -> None: ...

    def get_headers(self) -> dict[str, str]:
        """Returns empty dict with logged warning. Use get_storage_state() instead."""

    def validate(self) -> bool:
        """Validate storage state file exists and contains cookies."""

    def refresh_if_needed(self) -> None:
        """Re-read storage state from disk (file may have been updated)."""

    def get_storage_state(self) -> dict:
        """Return parsed storageState dict for Playwright context creation."""
```

### Modified: Tool Return Types

**Before (FastMCP):** Tools return `str` with emoji-prefixed error messages.

**After (BaseMCPServer):** Tools return `list[TextContent]` with JSON. Errors are wrapped in `ToolError(tool=name, error=msg, retryable=bool)` by the `BaseMCPServer.call_tool` dispatcher.

Tool schemas (unchanged semantics):

```python
# fetch_page
{
    "type": "object",
    "properties": {
        "url": {"type": "string", "description": "URL to fetch (must be *.redhat.com)"},
    },
    "required": ["url"],
}

# list_links
{
    "type": "object",
    "properties": {
        "url": {"type": "string", "description": "URL to extract links from"},
    },
    "required": ["url"],
}

# check_auth
{
    "type": "object",
    "properties": {},
}
```

### Modified: pyproject.toml

Add `redhat-browser-mcp` to testpaths and coverage source:

```toml
[tool.pytest.ini_options]
testpaths = ["tests", "jira-mcp/tests", "google-workspace-mcp/tests", "gmail-mcp/tests", "redhat-browser-mcp/tests"]

[tool.coverage.run]
source = ["shared", "jira-mcp", "google-workspace-mcp", "gmail-mcp", "redhat-browser-mcp"]
```

### Modified: Makefile

Add `test-redhat-browser` and `build-redhat-browser` targets.

### Modified: docker-compose.yml

Add `redhat-browser-mcp` service with volume mount for storageState.

## Data Migration

No data migration required. The storageState file format (`~/.redhat-browser-mcp/auth-state.json`) is unchanged. Users who previously ran the FastMCP version can use the same auth state file without re-authenticating.

## Implementation Plan

### Phase 1: Shared Library Extension (shared/auth.py, shared/server_base.py)

**Goal:** Add `PlaywrightStorageStateProvider` to the shared library and fix `_is_retryable()` to handle missing httpx, without breaking existing servers.

1. [ ] **Fix `_is_retryable()` in `/Users/imurphy/projects/workspaces/helper-mcps/shared/server_base.py`**
    - Wrap the `import httpx` at line 107 in `try/except ImportError` so non-httpx servers fall through gracefully:
      ```python
      def _is_retryable(exc: Exception) -> bool:
          """Determine if an exception indicates a retryable error."""
          try:
              import httpx
          except ImportError:
              return isinstance(exc, ConnectionError)

          if isinstance(exc, httpx.HTTPStatusError):
              return exc.response.status_code in (429, 500, 502, 503, 504)
          if isinstance(exc, (httpx.ConnectTimeout, httpx.ReadTimeout, httpx.PoolTimeout)):
              return True
          return isinstance(exc, ConnectionError)
      ```
    - This is a prerequisite for Phase 6: without this fix, every Playwright exception will cause an unhandled `ImportError` instead of producing a `ToolError`.
    - Run existing tests to confirm no regressions: `python -m pytest tests/ jira-mcp/tests/ -v`
2. [ ] **Update `CredentialProvider` ABC docstring** in `/Users/imurphy/projects/workspaces/helper-mcps/shared/auth.py`
    - Add a note to the class docstring that not all subclasses support header-based auth. Subclasses that do not produce HTTP headers (e.g., `PlaywrightStorageStateProvider`) return empty dicts from `get_headers()` and expose alternative methods for their auth mechanism.
3. [ ] **Add `PlaywrightStorageStateProvider` class** to `/Users/imurphy/projects/workspaces/helper-mcps/shared/auth.py`
    - Implement `__init__()` with path resolution (explicit -> env var -> default)
    - Implement `_load_state()` with file reading, JSON parsing, cookie validation
    - Implement `get_headers()` that returns `{}` with a logged warning: "PlaywrightStorageStateProvider does not produce HTTP headers. Use get_storage_state() for Playwright context creation."
    - Implement `validate()` that checks file exists, is valid JSON, has `cookies` list. Log a warning (not hard failure) if file permissions are more permissive than 0o600 on non-container environments (check `os.getuid() != 0`). This matches the pragmatic approach: warn on macOS dev environments where umask is 022, but do not block startup.
    - Implement `refresh_if_needed()` that clears cached state and re-reads from disk
    - Implement `get_storage_state() -> dict` that returns the parsed JSON
4. [ ] Add unit tests to `/Users/imurphy/projects/workspaces/helper-mcps/tests/test_auth.py`
    - Test path resolution (explicit, env var, default)
    - Test valid storage state loading
    - Test missing file raises AuthenticationError
    - Test empty file raises AuthenticationError
    - Test invalid JSON raises AuthenticationError
    - Test missing cookies key raises AuthenticationError
    - Test get_headers() returns empty dict (not raises)
    - Test validate() returns True for valid state
    - Test refresh_if_needed() re-reads from disk
    - Test get_storage_state() returns parsed dict
    - Test `_is_retryable()` returns False for arbitrary exceptions when httpx is not installed (mock the import)
5. [ ] Run validation: `cd /Users/imurphy/projects/workspaces/helper-mcps && python -m pytest tests/test_auth.py -v`
6. [ ] Run lint: `cd /Users/imurphy/projects/workspaces/helper-mcps && ruff check shared/auth.py shared/server_base.py`

### Phase 2: Create redhat-browser-mcp Package Structure

**Goal:** Create the package skeleton following the jira-mcp structure exactly.

1. [ ] Create directory: `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/`
2. [ ] Create directory: `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/tests/`
3. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/__init__.py`
    ```python
    """Red Hat Browser MCP Server -- Authenticated access to Red Hat internal documentation."""
    ```
4. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/tests/__init__.py`
    ```python
    """Tests for redhat-browser-mcp."""
    ```
5. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/requirements.txt`
    ```
    mcp>=1.0.0
    pydantic>=2.0.0
    playwright>=1.40.0
    readability-lxml>=0.8.1
    beautifulsoup4>=4.12.0
    lxml>=5.0.0
    markdownify>=0.11.0
    ```
6. [ ] Run validation: `ls -la /Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/`

### Phase 3: Port Business Logic Modules

**Goal:** Port `url_validator.py`, `content.py`, `config.py`, and `audit.py` with minimal changes (structured logging, type annotation cleanup).

1. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/url_validator.py`
    - Copy from `claude-devkit/mcp-servers/redhat-browser/src/redhat_browser/url_validator.py`
    - Replace `Optional[list[str]]` with `list[str] | None` (Python 3.12 style)
    - Add `from __future__ import annotations`
    - Add structured logging via `logging.getLogger("mcp.redhat-browser.url")`
    - Keep all SSRF protection logic unchanged
    - Keep `URLValidationError` class
    - Keep `validate_url()` and `is_redhat_internal_domain()` functions
    - Keep `_check_ip_blocked()` function
    - Keep `DEFAULT_ALLOWED_DOMAINS`

2. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/content.py`
    - Copy from `claude-devkit/mcp-servers/redhat-browser/src/redhat_browser/content.py`
    - Replace `Optional[...]` with `... | None`
    - Add `from __future__ import annotations`
    - Add structured logging via `logging.getLogger("mcp.redhat-browser.content")`
    - Keep all extraction logic unchanged (readability -> article -> main -> body -> fallback)
    - Keep `ContentExtractionError`, `TableAwareMarkdownConverter`
    - Keep `extract_main_content()`, `extract_links()`, `sanitize_error_message()`

3. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/config.py`
    - Copy from `claude-devkit/mcp-servers/redhat-browser/src/redhat_browser/config.py`
    - Replace `Optional[Path]` with `Path | None`
    - Add `from __future__ import annotations`
    - Add environment variable overrides for container deployment:
      - `REDHAT_BROWSER_ALLOWED_DOMAINS` (comma-separated)
      - `REDHAT_BROWSER_RATE_LIMIT` (int)
      - `REDHAT_BROWSER_MAX_RESPONSE_SIZE` (int)
    - Keep `DEFAULT_CONFIG` dict and `load_config()` function

4. [ ] Run lint: `cd /Users/imurphy/projects/workspaces/helper-mcps && ruff check redhat-browser-mcp/`

### Phase 4: Port and Refactor Browser Client

**Goal:** Refactor `BrowserSession` into `BrowserClient` following the `JiraClient` pattern.

1. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/browser_client.py`
    - Class `BrowserClient` (not a context manager like `BrowserSession` was -- lifecycle managed by `__main__.py`)
    - Constructor takes `PlaywrightStorageStateProvider` (typed concretely, not as `CredentialProvider` ABC) and calls `get_storage_state()` directly. No `hasattr` dispatch.
    - Constructor also takes config dict for max_concurrent (default: 3), max_response_size (default: 5MB), content_truncation_limit (default: 50,000 chars), browser_launch_timeout (default: 30s), allowed_domains
    - `async def start()` -- Launch Playwright, create browser, create authenticated context
    - `async def close()` -- Close context, browser, playwright
    - `async def _recreate_context()` -- Close existing context, call `self._auth.refresh_if_needed()`, re-read storage state from disk, create new context with fresh cookies. Used for SSO expiry recovery.
    - `async def _restart_browser()` -- Full `close()` + `start()` cycle. Used for browser crash recovery. Attempts one restart; if restart also fails, raises non-retryable error.
    - `async def validate_connection()` -- Attempt to access source.redhat.com and verify no SSO redirect (analogous to `JiraClient.validate_connection()`)
    - `async def fetch_page(url: str) -> dict` -- URL validation, page fetch, SSO redirect detection (with recovery: on SSO redirect, call `_recreate_context()` and retry once), content extraction. Returns dict with url, final_url, title, content, method. On `TargetClosedError`, call `_restart_browser()` and retry once, then fail with non-retryable `ToolError`.
    - `async def list_page_links(url: str) -> list[dict]` -- URL validation, page fetch, link extraction. Same SSO and crash recovery as `fetch_page`.
    - `async def check_auth_status() -> dict` -- Validate storageState, test access (creates a new page within the existing context, acquires semaphore, closes page afterward), return status dict.
    - Use structured logging throughout (no `print()`)
    - Remove PID file logic (container manages lifecycle)
    - Remove signal handler registration (handled by `__main__.py`)
    - Port `is_sso_redirect()` as a module-level function in this file
    - **Audit logging:** Each tool invocation appends a JSON-lines audit record to a persistent log file (default: `/audit/access.log`, configurable via `REDHAT_BROWSER_AUDIT_LOG` env var). The record includes timestamp, tool name, URL, success/failure, user-agent, and response size. This preserves the security control from the v1 `audit.py` module. Structured stderr logging via `configure_logging()` is used for operational logs; the audit file provides a persistent, tamper-evident trail for compliance. Rate limiting moves to the server handler level.
2. [ ] Run lint: `cd /Users/imurphy/projects/workspaces/helper-mcps && ruff check redhat-browser-mcp/browser_client.py`

### Phase 5: Create Auth Adapter

**Goal:** Create the auth adapter factory following the jira-mcp pattern.

1. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/auth_adapter.py`
    ```python
    """Auth adapter factory for the Red Hat Browser MCP server.

    Reads REDHAT_BROWSER_AUTH_TYPE env var (default: "storage_state").
    """
    from __future__ import annotations

    import os
    from shared.auth import CredentialProvider, PlaywrightStorageStateProvider

    def create_auth_provider() -> CredentialProvider:
        auth_type = os.environ.get("REDHAT_BROWSER_AUTH_TYPE", "storage_state").lower()
        if auth_type == "storage_state":
            return PlaywrightStorageStateProvider(
                state_env_var="REDHAT_BROWSER_STATE_PATH",
                default_path="/secrets/auth-state.json",
            )
        else:
            raise ValueError(
                f"Unsupported REDHAT_BROWSER_AUTH_TYPE: '{auth_type}'. "
                "Supported values: 'storage_state'."
            )
    ```

### Phase 6: Create MCP Server

**Goal:** Implement `RedHatBrowserMCPServer(BaseMCPServer)` with 3 tools.

1. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/server.py`
    - Class `RedHatBrowserMCPServer(BaseMCPServer)`
    - Constructor takes `BrowserClient` instance and config dict
    - `_register_tools()` registers 3 tools: `fetch_page`, `list_links`, `check_auth`
    - Each tool schema matches the FastMCP version but uses explicit JSON Schema dicts
    - `_handle_fetch_page(arguments)` -- calls `self._client.fetch_page(url)`, formats result as JSON TextContent
    - `_handle_list_links(arguments)` -- calls `self._client.list_page_links(url)`, formats as JSON TextContent
    - `_handle_check_auth(arguments)` -- calls `self._client.check_auth_status()`, formats as JSON TextContent
    - Rate limiting: check before each operation using an in-memory sliding window (ported from audit.py `check_rate_limit()`)
    - All exceptions caught by `BaseMCPServer.call_tool` and wrapped in `ToolError`
2. [ ] Run lint: `cd /Users/imurphy/projects/workspaces/helper-mcps && ruff check redhat-browser-mcp/server.py`

### Phase 7: Create Entry Point

**Goal:** Implement `__main__.py` with the lifecycle state machine, following jira-mcp exactly.

1. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/__main__.py`
    - Follows the exact structure of `jira-mcp/__main__.py`
    - sys.path manipulation for hyphenated package name
    - Import `create_auth_provider`, `BrowserClient`, `RedHatBrowserMCPServer`
    - Import lifecycle utilities from `shared.lifecycle`
    - Import `configure_logging` from `shared.logging_config`
    - `SERVER_NAME = "redhat-browser-mcp"`
    - Global `LifecycleMetrics` instance
    - `_shutdown_handler()` for SIGTERM/SIGINT
    - `_atexit_cleanup()` for process exit
    - `async def main()`:
      1. Start ready timeout watchdog
      2. Create auth provider
      3. Create BrowserClient with auth provider and config
      4. Start browser (`await browser_client.start()`) -- launches Chromium with `args=["--no-sandbox"]` when running as non-root (detected via `os.getuid() != 0`)
      5. Validate connection (`await browser_client.validate_connection()`) -> SERVICE_VALIDATED
      6. Validate stdio -> STDIO_VALIDATED
      7. Transition to READY
      8. Create `RedHatBrowserMCPServer(browser_client, config)`
      9. Run stdio server loop
    - `if __name__ == "__main__": asyncio.run(main())`
    - `finally` block closes browser client

### Phase 8: Create Dockerfile

**Goal:** Multi-stage Docker build with Playwright and Chromium, running as non-root user.

1. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/Dockerfile`
    ```dockerfile
    FROM python:3.12-slim AS base
    WORKDIR /app

    # Install Playwright system dependencies
    RUN apt-get update && apt-get install -y --no-install-recommends \
        libnss3 libnspr4 libdbus-1-3 libatk1.0-0 libatk-bridge2.0-0 \
        libcups2 libdrm2 libxkbcommon0 libatspi2.0-0 libxcomposite1 \
        libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 \
        libcairo2 libasound2 libwayland-client0 \
        && rm -rf /var/lib/apt/lists/*

    COPY shared/ ./shared/
    COPY redhat-browser-mcp/requirements.txt .
    RUN pip install --no-cache-dir -r requirements.txt
    RUN playwright install chromium

    COPY redhat-browser-mcp/ ./redhat-browser-mcp/

    # Create non-root user for running the server (Chromium requires --no-sandbox
    # when running as non-root inside a container; this is acceptable because
    # Docker provides the outer sandbox via seccomp/namespaces)
    RUN useradd -m -s /bin/bash mcpuser \
        && mkdir -p /audit \
        && chown mcpuser:mcpuser /audit
    USER mcpuser

    ENV PYTHONUNBUFFERED=1
    ENV REDHAT_BROWSER_AUTH_TYPE=storage_state
    STOPSIGNAL SIGTERM

    HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=3 \
      CMD test -f /tmp/mcp_healthy || exit 1

    CMD ["python", "-m", "redhat-browser-mcp"]
    ```
    - Note: `start-period` is 60s instead of 30s because Playwright browser launch is slower.
    - Note: Playwright's Chromium must be launched with `args=["--no-sandbox"]` when running as non-root. This is configured in `BrowserClient.start()`. The `--no-sandbox` flag is acceptable inside a Docker container because Docker provides the outer sandbox via seccomp profiles and Linux namespaces.
    - Note: The `/audit` directory is created and owned by `mcpuser` for persistent audit log writes. It is volume-mounted from the host (see docker-compose.yml).

### Phase 9: Write Tests

**Goal:** Unit tests with mocked Playwright meeting 90% coverage.

1. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/tests/test_server.py`
    - Mirror structure of `jira-mcp/tests/test_jira_server.py`
    - `EXPECTED_TOOLS = ["fetch_page", "list_links", "check_auth"]`
    - `mock_client` fixture with AsyncMock for `fetch_page`, `list_page_links`, `check_auth_status`
    - `TestToolRegistration`: all tools registered, each has handler, schemas have required fields, server name, version
    - `TestHandlerDispatch`: each handler calls correct client method, passes arguments
    - `TestErrorWrapping`: unknown tool, handler exception propagation

2. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/tests/test_browser_client.py`
    - Mock `async_playwright()` context manager
    - Mock browser, context, page objects
    - Test `start()` launches browser and creates context with storage state
    - Test `close()` closes all resources
    - Test `validate_connection()` succeeds on non-SSO page
    - Test `validate_connection()` fails on SSO redirect
    - Test `fetch_page()` returns content dict
    - Test `fetch_page()` raises on invalid URL
    - Test `fetch_page()` raises on SSO redirect
    - Test `fetch_page()` raises on timeout
    - Test `list_page_links()` returns link list
    - Test `check_auth_status()` returns status dict
    - Test `is_sso_redirect()` detection patterns
    - Test concurrency semaphore (max_concurrent)

3. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/tests/test_url_validator.py`
    - Test valid URLs pass
    - Test empty URL raises
    - Test invalid scheme raises
    - Test missing hostname raises
    - Test domain allowlist enforcement
    - Test SSRF: loopback, link-local, private IP, cloud metadata
    - Test DNS resolution check
    - Test raw IP address handling
    - Test `is_redhat_internal_domain()`

4. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/tests/test_content.py`
    - Test readability extraction path
    - Test article fallback path
    - Test main/body fallback paths
    - Test empty HTML raises ContentExtractionError
    - Test table-aware markdown conversion
    - Test link extraction
    - Test `sanitize_error_message()` (IP, hostname, path redaction)

5. [ ] Create `/Users/imurphy/projects/workspaces/helper-mcps/redhat-browser-mcp/tests/test_auth_adapter.py`
    - Test default auth type creates PlaywrightStorageStateProvider
    - Test explicit "storage_state" env var
    - Test unsupported auth type raises ValueError

6. [ ] Run tests: `cd /Users/imurphy/projects/workspaces/helper-mcps && python -m pytest redhat-browser-mcp/tests/ tests/ -v --cov=shared --cov=redhat-browser-mcp`
7. [ ] Run lint: `cd /Users/imurphy/projects/workspaces/helper-mcps && ruff check .`

### Phase 10: Update Monorepo Configuration

**Goal:** Integrate redhat-browser-mcp into the monorepo build/test/deploy configuration.

1. [ ] Update `/Users/imurphy/projects/workspaces/helper-mcps/pyproject.toml`
    - Add `"redhat-browser-mcp/tests"` to `testpaths`
    - Add `"redhat-browser-mcp"` to `[tool.coverage.run] source`
    - Update project description to include "Red Hat Browser"

2. [ ] Update `/Users/imurphy/projects/workspaces/helper-mcps/Makefile`
    - Add `test-redhat-browser` target:
      ```makefile
      test-redhat-browser:
      	python -m pytest redhat-browser-mcp/tests/ tests/ -v --cov=shared --cov=redhat-browser-mcp
      ```
    - Add `build-redhat-browser` target:
      ```makefile
      build-redhat-browser:
      	docker build -f redhat-browser-mcp/Dockerfile -t redhat-browser-mcp:latest .
      ```
    - Add `build-redhat-browser` to `build-all` prerequisites
    - Update `.PHONY` line
    - Update `help` text

3. [ ] Update `/Users/imurphy/projects/workspaces/helper-mcps/docker-compose.yml`
    - Add `redhat-browser-mcp` service:
      ```yaml
      redhat-browser-mcp:
        build:
          context: .
          dockerfile: redhat-browser-mcp/Dockerfile
        stdin_open: true
        environment:
          - REDHAT_BROWSER_AUTH_TYPE=storage_state
          - MCP_STORAGE_STATE_PATH=/secrets/auth-state.json
          - REDHAT_BROWSER_AUDIT_LOG=/audit/access.log
          - MCP_READY_TIMEOUT=90
          - LOG_LEVEL=INFO
        volumes:
          - ${REDHAT_BROWSER_SECRETS_DIR:-~/.redhat-browser-mcp}:/secrets:ro
          - ${REDHAT_BROWSER_AUDIT_DIR:-~/.redhat-browser-mcp/audit}:/audit
        healthcheck:
          test: ["CMD", "test", "-f", "/tmp/mcp_healthy"]
          interval: 10s
          timeout: 5s
          start_period: 60s
          retries: 3
      ```
    - Note: The `/audit` volume is read-write (not `:ro`) to allow the server to persist audit records. The audit log file survives container restarts and removals because it is stored on the host filesystem.

4. [ ] Update `/Users/imurphy/projects/workspaces/helper-mcps/CLAUDE.md`
    - Add `redhat-browser-mcp/` to architecture overview
    - Add to server list with Playwright auth type
    - Update the opening description line from "Read-only MCP servers for Jira, Google Workspace, and Gmail" to include "Red Hat Browser"
    - Confirm the read-only invariant statement applies to the new server

### Phase 11: Cleanup claude-devkit

**Goal:** Remove the FastMCP implementation and revert CLAUDE.md references.

1. [ ] Delete directory: `/Users/imurphy/projects/claude-devkit/mcp-servers/` (entire directory tree)
2. [ ] Update `/Users/imurphy/projects/claude-devkit/CLAUDE.md`
    - Remove any references to `mcp-servers/` directory
    - Remove any MCP server documentation that was added for the FastMCP version
    - Keep the reference to the prior plan in `./plans/` for historical record
3. [ ] Verify: `ls /Users/imurphy/projects/claude-devkit/mcp-servers/` should return "No such file or directory"

### Phase 12: Final Validation

**Goal:** End-to-end verification that everything works.

1. [ ] Run full test suite: `cd /Users/imurphy/projects/workspaces/helper-mcps && make test`
2. [ ] Run lint: `cd /Users/imurphy/projects/workspaces/helper-mcps && make lint`
3. [ ] Build Docker image: `cd /Users/imurphy/projects/workspaces/helper-mcps && make build-redhat-browser`
4. [ ] Verify coverage meets 90% threshold
5. [ ] Manual smoke test (requires VPN + valid auth state):
    ```bash
    cd /Users/imurphy/projects/workspaces/helper-mcps
    python -m redhat-browser-mcp
    # In another terminal, send MCP messages via stdio
    ```

## Rollout Plan

1. **Phase 1-9:** Implemented in a feature branch on `helper-mcps` repository. No impact to existing servers.
2. **Phase 10:** Configuration changes are additive only. Existing `make test`, `make lint`, `make build-all` continue to work for existing servers.
3. **Phase 11:** Executed in a separate commit on `claude-devkit` repository. This is a cleanup-only change.
4. **Phase 12:** Final validation before merging.
5. **Post-merge:** Update Claude Code MCP configuration (`~/.claude/settings.json` or project-level) to point to the new server location.

**Rollback:** If the new server has issues, the old FastMCP code is preserved in git history and can be restored. The `helper-mcps` changes are in a separate branch and can be reverted independently.

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Playwright in Docker fails (missing system deps) | Medium | High | Use official Playwright Docker base image or tested apt dependency list. Test build early in Phase 8. |
| Storage state format differs between Playwright versions | Low | Medium | Pin Playwright version in requirements.txt. Validate JSON schema in `PlaywrightStorageStateProvider.validate()`. |
| `_is_retryable()` imports httpx but redhat-browser-mcp does not install it | ~~Low~~ Certain | ~~Low~~ Medium | **Resolved in Phase 1:** The `import httpx` executes unconditionally in the function body, not inside an exception handler. This plan wraps it in `try/except ImportError` in `server_base.py` so non-httpx servers fall through to the `ConnectionError` check. |
| Cookie expiry or browser crash mid-session | Medium | Medium | `BrowserClient` implements `_recreate_context()` for SSO cookie expiry (refresh storage state, retry once) and `_restart_browser()` for `TargetClosedError` (full restart, retry once, then non-retryable error). |
| Test coverage below 90% due to Playwright mocking complexity | Medium | Medium | Extensive mocking fixtures. Use `unittest.mock.patch` for `async_playwright()`. Focus tests on handler dispatch and business logic, not Playwright internals. |
| Browser launch timeout in container is too short | Medium | Low | Set `start_period: 60s` in Docker healthcheck and `BROWSER_LAUNCH_TIMEOUT: 30` default. |
| Interactive login flow breaks (requires host-side browser) | Low | Low | Document that `--login` must run on the host, not in the container. Provide a CLI script outside the MCP server for login. |
| Breaking `shared/auth.py` for existing servers | Low | High | `PlaywrightStorageStateProvider` is purely additive. No changes to `CredentialProvider` ABC, `PATCredentialProvider`, or `OAuthCredentialProvider`. Run full test suite to verify. |

## Test Plan

### Test Commands

```bash
# Run all tests (must pass before merge)
cd /Users/imurphy/projects/workspaces/helper-mcps && python -m pytest -v --cov

# Run only redhat-browser-mcp tests
cd /Users/imurphy/projects/workspaces/helper-mcps && python -m pytest redhat-browser-mcp/tests/ -v --cov=redhat-browser-mcp

# Run shared library tests (verify no regressions)
cd /Users/imurphy/projects/workspaces/helper-mcps && python -m pytest tests/ -v --cov=shared

# Run linter
cd /Users/imurphy/projects/workspaces/helper-mcps && ruff check .

# Build Docker image
cd /Users/imurphy/projects/workspaces/helper-mcps && docker build -f redhat-browser-mcp/Dockerfile -t redhat-browser-mcp:latest .
```

### Test Coverage Requirements

- `shared/auth.py` -- `PlaywrightStorageStateProvider`: 100% (path resolution, loading, validation, error cases)
- `redhat-browser-mcp/server.py` -- Tool registration and dispatch: 100%
- `redhat-browser-mcp/browser_client.py` -- Core logic: 90%+ (Playwright internals mocked)
- `redhat-browser-mcp/url_validator.py` -- URL validation and SSRF: 100%
- `redhat-browser-mcp/content.py` -- Content extraction: 95%+
- `redhat-browser-mcp/auth_adapter.py` -- Factory: 100%
- **Overall monorepo coverage:** >=90% (enforced by pyproject.toml `fail_under = 90`)

### Test Categories

1. **Unit tests** (automated, run in CI): All tests in `redhat-browser-mcp/tests/` and `tests/test_auth.py`
2. **Integration tests** (manual, requires VPN): Marked with `@pytest.mark.integration`, skipped by default
3. **Docker build test** (automated): `make build-redhat-browser` succeeds

## Acceptance Criteria

- [ ] `PlaywrightStorageStateProvider` exists in `shared/auth.py` and passes all unit tests
- [ ] `redhat-browser-mcp/` follows the exact package structure of `jira-mcp/`
- [ ] `RedHatBrowserMCPServer` inherits from `BaseMCPServer` and registers 3 tools
- [ ] `__main__.py` implements the full lifecycle state machine (INITIALIZING -> SERVICE_VALIDATED -> STDIO_VALIDATED -> READY)
- [ ] All logging uses `configure_logging()` structured JSON to stderr (no `print()` statements)
- [ ] Errors are returned as `ToolError` via `BaseMCPServer.call_tool` (no emoji strings)
- [ ] URL validation with SSRF protection is preserved
- [ ] Content extraction pipeline (readability -> article -> main -> body -> fallback) is preserved
- [ ] Rate limiting is preserved (sliding window, configurable limit)
- [ ] `ruff check .` passes with zero violations
- [ ] `python -m pytest -v --cov` passes with >=90% coverage
- [ ] `docker build -f redhat-browser-mcp/Dockerfile -t redhat-browser-mcp:latest .` succeeds
- [ ] `pyproject.toml`, `Makefile`, `docker-compose.yml` include the new server
- [ ] `claude-devkit/mcp-servers/` directory is deleted
- [ ] No changes to jira-mcp, gmail-mcp, or google-workspace-mcp

## Task Breakdown (File Manifest)

### Files to CREATE in helper-mcps

| File | Description |
|------|-------------|
| `redhat-browser-mcp/__init__.py` | Module docstring |
| `redhat-browser-mcp/__main__.py` | Entry point with lifecycle state machine |
| `redhat-browser-mcp/server.py` | `RedHatBrowserMCPServer(BaseMCPServer)` |
| `redhat-browser-mcp/browser_client.py` | Playwright browser client |
| `redhat-browser-mcp/url_validator.py` | URL validation with SSRF protection |
| `redhat-browser-mcp/content.py` | HTML-to-markdown extraction pipeline |
| `redhat-browser-mcp/config.py` | Configuration management |
| `redhat-browser-mcp/auth_adapter.py` | Auth provider factory |
| `redhat-browser-mcp/requirements.txt` | Python dependencies |
| `redhat-browser-mcp/Dockerfile` | Multi-stage Docker build |
| `redhat-browser-mcp/tests/__init__.py` | Test package init |
| `redhat-browser-mcp/tests/test_server.py` | Server tool registration tests |
| `redhat-browser-mcp/tests/test_browser_client.py` | Browser client tests |
| `redhat-browser-mcp/tests/test_url_validator.py` | URL validation tests |
| `redhat-browser-mcp/tests/test_content.py` | Content extraction tests |
| `redhat-browser-mcp/tests/test_auth_adapter.py` | Auth adapter tests |

### Files to MODIFY in helper-mcps

| File | Change |
|------|--------|
| `shared/auth.py` | Add `PlaywrightStorageStateProvider` class; update `CredentialProvider` ABC docstring |
| `shared/server_base.py` | Wrap `import httpx` in `_is_retryable()` with `try/except ImportError` |
| `tests/test_auth.py` | Add tests for `PlaywrightStorageStateProvider` and `_is_retryable()` without httpx |
| `pyproject.toml` | Add testpaths and coverage source |
| `Makefile` | Add test/build targets |
| `docker-compose.yml` | Add service definition |
| `CLAUDE.md` | Add server documentation |

### Files to DELETE in claude-devkit

| File/Directory | Reason |
|----------------|--------|
| `mcp-servers/` (entire tree) | FastMCP implementation superseded by helper-mcps version |

### Files to MODIFY in claude-devkit

| File | Change |
|------|--------|
| `CLAUDE.md` | Remove mcp-servers/ references |

## Context Alignment

### Patterns Followed

| Pattern | Source | How Applied |
|---------|--------|-------------|
| `BaseMCPServer` inheritance | `helper-mcps/shared/server_base.py` | `RedHatBrowserMCPServer(BaseMCPServer)` |
| `CredentialProvider` ABC | `helper-mcps/shared/auth.py` | New `PlaywrightStorageStateProvider` subclass; ABC docstring updated for non-header providers |
| Lifecycle state machine | `helper-mcps/shared/lifecycle.py` | `__main__.py` follows jira-mcp pattern exactly |
| Structured logging | `helper-mcps/shared/logging_config.py` | All modules use `configure_logging()` |
| `ToolError` returns | `helper-mcps/shared/types.py` | Errors wrapped by `BaseMCPServer.call_tool` |
| Auth adapter factory | `helper-mcps/jira-mcp/auth_adapter.py` | `create_auth_provider()` pattern |
| Docker healthcheck | `helper-mcps/docker-compose.yml` | `/tmp/mcp_healthy` marker file |
| Package structure | `helper-mcps/jira-mcp/` | Identical directory layout |
| Test structure | `helper-mcps/jira-mcp/tests/` | Mirror test organization |
| Coverage threshold | `helper-mcps/pyproject.toml` | 90% minimum enforced |

### Prior Plans

| Plan | Relationship |
|------|-------------|
| `plans/redhat-internal-browser-mcp.md` | **Superseded.** This was the original FastMCP design. The business logic (URL validation, content extraction, auth management) is preserved but the architecture is replaced. |
| `plans/redhat-internal-browser-mcp.feasibility.md` | **Still valid.** Feasibility assessment of browser automation approach applies regardless of framework. |
| `plans/redhat-internal-browser-mcp.review.md` | **Partially superseded.** Review findings about the FastMCP design are addressed by adopting helper-mcps patterns. |
| `plans/redhat-internal-browser-mcp.redteam.md` | **Still valid.** Security concerns (SSRF, credential handling, data classification) are preserved in the new implementation. |

### Deviations from helper-mcps Patterns

| Deviation | Justification |
|-----------|---------------|
| `get_headers()` returns empty dict instead of auth headers | Playwright storageState is not header-based auth. The `BrowserClient` calls `get_storage_state()` directly and is typed against `PlaywrightStorageStateProvider` concretely. `get_headers()` returns `{}` with a logged warning to preserve Liskov Substitution Principle compliance. |
| `validate_connection()` uses Playwright instead of httpx | The server does not make HTTP requests -- it uses Playwright browser automation. Validation requires launching a browser and navigating to a test page. |
| `_is_retryable()` does not cover Playwright exceptions | Playwright errors (TargetClosedError, TimeoutError) are not httpx errors. The `import httpx` in `_is_retryable()` is now wrapped in `try/except ImportError` (Phase 1), so these exceptions fall through to the `ConnectionError` check and return `False` (non-retryable). This is correct: browser state corruption requires a restart, not a retry. |
| Docker image is larger (Chromium included) | Unavoidable -- Playwright requires a browser binary. Image size is ~500MB vs ~100MB for other servers. |
| `start_period` is 60s instead of 30s | Playwright browser launch is slower than HTTP client initialization. |
| No `httpx` dependency | The server uses Playwright for all network access, not httpx. |
| Audit logging uses both structured stderr and persistent file | The FastMCP `AuditLogger` class wrote JSON-lines to a file. The new implementation retains a persistent file-based audit trail (`/audit/access.log`, volume-mounted from host) for compliance and incident investigation, alongside structured stderr logging via `configure_logging()` for operational observability. This preserves the security control from the v1 red team review (MAJOR-1, marked RESOLVED). |

---

## Plan Metadata

- **Plan File:** `./plans/redhat-browser-mcp-v2.md`
- **Date:** 2026-02-24
- **Author:** Senior Architect Agent
- **Affected Components:**
  - `helper-mcps/shared/auth.py` (modified -- new provider + ABC docstring)
  - `helper-mcps/shared/server_base.py` (modified -- `_is_retryable()` httpx fix)
  - `helper-mcps/redhat-browser-mcp/` (new package, 16 files)
  - `helper-mcps/pyproject.toml` (modified)
  - `helper-mcps/Makefile` (modified)
  - `helper-mcps/docker-compose.yml` (modified)
  - `helper-mcps/CLAUDE.md` (modified)
  - `claude-devkit/mcp-servers/` (deleted)
  - `claude-devkit/CLAUDE.md` (modified)
- **Validation:**
  - `cd /Users/imurphy/projects/workspaces/helper-mcps && python -m pytest -v --cov` (must pass, >=90% coverage)
  - `cd /Users/imurphy/projects/workspaces/helper-mcps && ruff check .` (zero violations)
  - `cd /Users/imurphy/projects/workspaces/helper-mcps && make build-redhat-browser` (Docker build succeeds)
  - `ls /Users/imurphy/projects/claude-devkit/mcp-servers/` (should not exist)
- **Estimated Effort:** 2-3 engineering sessions
- **Dependencies:** None (all shared library primitives exist; only `PlaywrightStorageStateProvider` is new)

## Status: APPROVED
