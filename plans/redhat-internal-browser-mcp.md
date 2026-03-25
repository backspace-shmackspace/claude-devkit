# Plan: Red Hat Internal Browser MCP Server

## Context

Red Hat employees need to access internal documentation portals (source.redhat.com, internal wikis, knowledge bases) from within Claude Code sessions. The built-in `WebFetch` tool cannot access these pages because they sit behind Red Hat SSO (Keycloak/SAML-based authentication), VPN requirements, and other corporate access controls.

This plan designs and implements a local MCP server that leverages the user's existing authenticated browser session to fetch, convert, and return internal page content to Claude Code. The server runs locally on the user's machine, reads from an already-authenticated browser profile, and exposes MCP tools that Claude Code can call directly.

**Current state:** No MCP server infrastructure exists in claude-devkit. This is a new component category.

**Constraints:**
- Must run entirely locally (no cloud services, no proxying through third parties)
- Must not store or transmit Red Hat credentials
- Must work with Red Hat SSO (Keycloak SAML) and potentially Kerberos
- Must handle JavaScript-rendered pages (many internal portals are SPAs)
- Personal/user-specific tool -- belongs in `contrib/` or a new `mcp-servers/` directory

## Data Classification and Acceptable Use

**WARNING: All content fetched by this tool is sent to Anthropic's API as part of the Claude Code conversation context.** This is inherent to how MCP tools work -- the tool returns content to Claude Code, which processes it via Anthropic's cloud-hosted model.

**User obligations before using this tool:**

1. **Accept the data flow risk.** Internal page content will be transmitted to Anthropic's servers for LLM processing. The user must determine whether their organization's data classification policies permit this for the content they intend to access.
2. **Restrict usage to permitted data classifications.** Do not use this tool to fetch pages containing Restricted or Confidential data (e.g., pre-disclosure CVEs, PII, HR/payroll data, security incident reports) unless your organization's Anthropic agreement explicitly covers those classifications.
3. **Use the URL domain allowlist.** The server enforces a configurable domain allowlist (default: `*.redhat.com`). This limits the blast radius but does not eliminate the data flow risk -- permitted domains may still host sensitive content.
4. **Review your enterprise AI agreement.** If Red Hat has an Anthropic enterprise agreement, confirm it covers internal documentation access via developer tooling.

**The tool does not make data classification decisions for the user.** It provides guardrails (domain allowlist, audit logging) but ultimately the user is responsible for compliance with their organization's information security policies.

## Architectural Analysis

### Key Drivers

1. **Authentication transparency** -- The server must use the user's existing session, not manage credentials itself
2. **JavaScript rendering** -- Internal portals often use React/Angular, requiring a real browser engine
3. **Content fidelity** -- Converted markdown must preserve technical content (code blocks, tables, headings)
4. **Session persistence** -- Browser sessions should survive server restarts
5. **Minimal user intervention** -- After initial login, the server should operate hands-free
6. **MCP compliance** -- Must follow the Model Context Protocol specification for stdio transport
7. **Input validation** -- All URLs must be validated against an allowlist before fetching
8. **Audit trail** -- All tool invocations must be logged locally for corporate security compliance

### Authentication Strategy Decision Matrix

| Approach | SSO Support | JS Rendering | Session Persistence | Setup Complexity | Security |
|----------|------------|--------------|---------------------|-----------------|----------|
| **A. Playwright storageState** | Yes (manual first login) | Yes | Yes (exported cookies/localStorage as JSON) | Medium | Good -- no creds stored, no profile corruption |
| B. Cookie extraction (mcp-cookies style) | Partial (cookies only) | No (requests-based) | No (cookies expire) | Low | Medium -- decrypts cookie store |
| C. Chrome DevTools Protocol (CDP) | Yes (attach to running Chrome) | Yes | Yes (existing profile) | Medium | Good -- reads from running browser |
| D. Kerberos tickets (kinit + requests) | Kerberos only, not SAML | No | Until ticket expires | Low | Good |

**Recommendation: Approach A (Playwright with storageState API) as primary, with Approach D (Kerberos) as optional fallback for CLI-friendly endpoints.**

**Rationale:**
- Red Hat SSO uses SAML/Keycloak which requires a full browser flow -- cookies-only extraction (B) breaks when tokens expire or when JavaScript redirects are needed
- CDP attachment to running Chrome (C) is fragile -- users may close Chrome, and port conflicts are common
- Playwright's `storageState` API exports cookies and localStorage as a JSON file after headed login, then injects them into fresh headless contexts for subsequent runs. This avoids the [known macOS bug (Playwright Issue #35466)](https://github.com/microsoft/playwright/issues/35466) where switching between headed and headless modes with the same `userDataDir` corrupts the browser profile
- The user authenticates once manually in a headed Playwright browser, the server exports the auth state to a JSON file, and headless contexts import it on startup
- Kerberos (D) is a useful supplement for API endpoints that accept Negotiate auth, but cannot handle the full SAML flow needed for source.redhat.com

### Technology Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Language | **Python 3.11+** | Consistent with claude-devkit generators; rich ecosystem |
| MCP SDK | **`mcp` (Python SDK v1.x)** | Official Anthropic SDK; FastMCP decorator pattern |
| Browser engine | **Playwright (async, Chromium)** | storageState auth persistence, SSO support, JS rendering |
| HTML-to-Markdown | **`markdownify`** (with custom table converter) | Lightweight; custom `MarkdownConverter` subclass handles colspan/rowspan |
| Content extraction | **`readability-lxml`** (Mozilla Readability port) with fallback pipeline | Strips navigation/chrome, extracts article content; fallback to semantic selectors when heuristics fail |
| Transport | **stdio** | Standard for local MCP servers in Claude Code |

## Goals

1. Claude Code can fetch and read any Red Hat internal page the user has access to (within the domain allowlist)
2. Content is returned as clean markdown suitable for LLM consumption
3. Authentication is handled transparently via Playwright storageState persistence
4. The server integrates with Claude Code via standard MCP stdio transport
5. The solution is documented, testable, and deployable via claude-devkit patterns
6. All fetched URLs are logged locally for audit compliance
7. URL input is validated against a configurable domain allowlist and SSRF filters

## Non-Goals

1. **Credential management** -- The server does not store, manage, or prompt for passwords
2. **Write operations** -- No form submission, commenting, or editing on internal sites
3. **Full browser automation** -- This is a fetch-and-read tool, not a general browser controller
4. **Multi-user support** -- This is a single-user, local-only tool
5. **Caching layer** -- No persistent content cache (Claude Code manages its own context)
6. **Search engine** -- No crawling or indexing; fetch is on-demand by URL
7. **Data classification enforcement** -- The tool provides guardrails but does not classify content sensitivity; the user is responsible

## Assumptions

1. The user has a Red Hat VPN connection active when using the tool (GlobalProtect or similar)
2. The user can authenticate to Red Hat SSO via a browser (standard employee access)
3. Python 3.11+ is available on the user's machine
4. The user runs macOS (darwin) -- Linux support is secondary
5. Internal pages return HTML that can be meaningfully converted to markdown
6. Playwright can install its own Chromium binary (no corporate firewall blocking)
7. Sessions persist for at least 8 hours (typical Red Hat SSO session lifetime)
8. The user has reviewed their organization's data classification policy and accepts that fetched content is transmitted to Anthropic's API

## Proposed Design

### Architecture Overview

```
Claude Code
    |
    | stdio (JSON-RPC over stdin/stdout)
    |
[redhat-browser-mcp]  (Python, FastMCP)
    |
    |--- [URL Validator]         -- Domain allowlist + SSRF filter
    |--- [Audit Logger]          -- Local log of all tool invocations
    |--- [Error Sanitizer]       -- Strip internal hostnames from MCP responses
    |
    | Playwright async API (shared event loop with MCP SDK)
    |
[Chromium -- fresh context per serve, storageState injection]
    |
    | HTTPS only (through VPN)
    |
[*.redhat.com internal sites]
```

### Security Architecture

All URL inputs pass through a validation pipeline before reaching Playwright:

```
[URL Input from tool call]
    |
    v
[1. Scheme Validation]        -- HTTPS only; block file://, javascript:, data:, ftp://, http://
    |
    v
[2. Domain Allowlist]         -- *.redhat.com by default; configurable in config.json
    |
    v
[3. SSRF Filter]              -- Block RFC 1918 (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16),
    |                            loopback (127.0.0.0/8, ::1), link-local (169.254.0.0/16),
    |                            cloud metadata (169.254.169.254)
    v
[4. DNS Resolution Check]     -- Resolve hostname, verify resolved IP is not in blocked ranges
    |                            (prevents DNS rebinding attacks)
    v
[5. Playwright Fetch]         -- Timeout, max response size (5MB)
    |
    v
[6. Content Extraction]       -- readability-lxml (XXE disabled) with fallback pipeline
    |
    v
[7. Size Truncation]          -- 50,000 char limit
    |
    v
[8. Error Sanitization]       -- Strip internal hostnames/IPs from any error messages
    |
    v
[9. Audit Log Entry]          -- URL, timestamp, status, content size (never content)
    |
    v
[MCP Response]
```

### URL Validation Module (`url_validator.py`)

```python
import ipaddress
import socket
from urllib.parse import urlparse

# Default allowlist -- configurable via ~/.redhat-browser-mcp/config.json
DEFAULT_ALLOWED_DOMAINS = ["*.redhat.com"]

BLOCKED_IP_RANGES = [
    ipaddress.ip_network("10.0.0.0/8"),        # RFC 1918
    ipaddress.ip_network("172.16.0.0/12"),      # RFC 1918
    ipaddress.ip_network("192.168.0.0/16"),     # RFC 1918
    ipaddress.ip_network("127.0.0.0/8"),        # Loopback
    ipaddress.ip_network("169.254.0.0/16"),     # Link-local (includes cloud metadata)
    ipaddress.ip_network("::1/128"),            # IPv6 loopback
    ipaddress.ip_network("fc00::/7"),           # IPv6 private
    ipaddress.ip_network("fe80::/10"),          # IPv6 link-local
]

ALLOWED_SCHEMES = {"https"}

def validate_url(url: str, allowed_domains: list[str]) -> tuple[bool, str]:
    """Validate URL against allowlist and SSRF filters.
    Returns (is_valid, error_message).
    """
    # 1. Parse and check scheme
    # 2. Check domain against allowlist (wildcard matching)
    # 3. Resolve DNS and check resolved IP against blocked ranges
    # 4. Return (True, "") or (False, "reason")
```

### Component Design

#### 1. MCP Server (`server.py`)

The main entry point. Uses FastMCP to declare tools and run via stdio transport.

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP(
    "redhat-browser",
    description="Browse Red Hat internal sites using authenticated browser session"
)

# Playwright shares the MCP SDK's asyncio event loop.
# mcp.run() creates the event loop; browser.launch() is awaited
# within tool handlers on that same loop. No separate loop creation.
```

**Event loop integration:** The `BrowserManager.launch()` method is an async coroutine called from within MCP tool handlers. It uses `playwright.async_api.async_playwright()` which attaches to the current running event loop (the one created by `mcp.run(transport="stdio")`). The browser manager never creates its own event loop. The `launch()` call is guarded by a 15-second timeout separate from per-page navigation timeouts.

#### 2. Browser Manager (`browser.py`)

Manages Playwright browser instances using the storageState API for authentication persistence.

**Key behaviors:**
- Lazy initialization -- browser launches on first tool call, not on server start
- **storageState-based authentication** (not persistent userDataDir):
  - `--login` mode: launches a headed persistent context, user authenticates, then exports state via `context.storage_state(path=AUTH_STATE_PATH)`
  - `--serve` mode: launches a fresh headless browser, creates context with `browser.new_context(storage_state=AUTH_STATE_PATH)`
  - Auth state stored at `~/.redhat-browser-mcp/auth-state.json` (permissions 0600)
- **Concurrency model:** `asyncio.Semaphore(3)` controls the page pool. Each tool call acquires the semaphore, creates a new page, navigates, extracts content, closes the page, and releases the semaphore. If all 3 slots are occupied, the caller waits up to 30 seconds; on timeout, returns error "Browser busy, try again shortly." No global navigation lock -- the semaphore is sufficient.
- **Zombie process recovery:**
  - On startup, check for PID file at `~/.redhat-browser-mcp/browser.pid`. If a stale process exists, attempt `os.kill(pid, 0)` to check liveness; if alive, send SIGTERM.
  - Write current browser PID to `~/.redhat-browser-mcp/browser.pid` after launch.
  - Register signal handlers for SIGTERM and SIGINT that call `browser.close()`.
  - `atexit` handler removes PID file and closes browser.
  - Wrap page operations in try/except catching `playwright._impl._errors.TargetClosedError`; on catch, set browser reference to None so next call re-launches.
- Automatic cleanup on server shutdown
- Browser launch timeout: 15 seconds (separate from page navigation timeout)
- Max response size: 5MB per page load (abort larger responses)

**Profile directory permissions:**
- `~/.redhat-browser-mcp/` directory: created with mode `0700` (user-only access)
- `auth-state.json`: written with mode `0600` (user-only read/write)
- On startup, verify directory ownership matches current user and permissions are not more permissive than `0700`. If permissions are wrong, log a warning and refuse to start.

**Authentication flow (revised from v1 -- uses storageState, not persistent userDataDir):**
1. First run: User runs `redhat-browser-mcp --login`
2. Server launches Chromium in headed mode with a temporary persistent context
3. User manually navigates to source.redhat.com and authenticates via SSO
4. After authentication, server calls `context.storage_state(path="~/.redhat-browser-mcp/auth-state.json")` to export cookies and localStorage as JSON
5. Server closes the headed browser and exits
6. Subsequent runs (`--serve` mode): Server launches headless browser, creates a fresh context with `browser.new_context(storage_state="~/.redhat-browser-mcp/auth-state.json")`
7. If a fetch returns a login page (detected by URL redirect to SSO), server logs a warning and instructs user to run `redhat-browser-mcp --login` to re-authenticate

**Why storageState instead of persistent userDataDir:**
Playwright has a [known bug on macOS (Issue #35466)](https://github.com/microsoft/playwright/issues/35466) where switching between headed and headless modes with the same `userDataDir` corrupts the browser profile (cookie read failures, SingletonLock stale files, database corruption). The `storageState` API avoids this entirely by exporting auth state as a portable JSON file and injecting it into fresh contexts. The tradeoff is that `storageState` does not capture IndexedDB or service workers, but Red Hat SSO relies on cookies and localStorage, which are captured.

#### 3. Content Processor (`content.py`)

Converts raw HTML to clean markdown.

**Pipeline:**
1. Receive raw HTML from Playwright `page.content()`
2. Extract main content using `readability-lxml` (strips nav, sidebar, footer, ads)
   - **XXE prevention:** Configure lxml parser with `resolve_entities=False`
3. **Fallback pipeline:** If `readability-lxml` returns content below 200 characters:
   - Attempt extraction via semantic selectors in order: `<main>`, `<article>`, `[role="main"]`, `#content`, `.content`, `#main`
   - If all selectors fail, fall back to `<body>` content (full page minus `<nav>`, `<header>`, `<footer>`, `<aside>`)
   - Log which extraction method succeeded for debugging
4. Convert to markdown using a **custom `MarkdownConverter` subclass** of markdownify:
   - Preserve code blocks and inline code
   - **Custom `convert_table` method**: Handle `colspan`/`rowspan` by degrading to indented plain text rather than producing invalid markdown tables. Set `table_infer_header=True` for tables missing `<thead>`.
   - Strip images (optional, configurable)
   - Collapse excessive whitespace
5. Truncate to configurable max length (default: 50,000 chars) to respect MCP token limits
6. Prepend metadata header (title, URL, fetch timestamp)

#### 4. Login Detector (`auth.py`)

Detects whether a page response is actually a login/SSO redirect.

**Detection signals:**
- Final URL contains `sso.redhat.com`, `auth.redhat.com`, or `login`
- Page title contains "Log In", "Sign In", "Red Hat SSO"
- Page contains Keycloak form elements (`#kc-form-login`)

#### 5. Audit Logger (`audit.py`)

Logs all tool invocations to a local file for corporate security compliance.

**Log format:** JSON lines at `~/.redhat-browser-mcp/audit.log`

```json
{"timestamp": "2026-02-24T15:30:00Z", "tool": "fetch_page", "url": "https://source.redhat.com/...", "status": "success", "content_size": 12450, "duration_ms": 2300}
```

**Rules:**
- Log every tool invocation (including failures and validation rejections)
- **Never log response content** (may contain sensitive data)
- Log URL, timestamp, tool name, status (success/error/auth_expired/url_rejected), content size, duration
- Set log file permissions to `0600`
- Include user-agent string `RedHatBrowserMCP/1.0` in Playwright requests so corporate security can identify the tool's traffic
- Configurable rate limit: max 30 requests per minute (default). Return error if exceeded.

#### 6. Error Sanitizer

All error messages returned via MCP are sanitized before transmission:
- Strip internal hostnames (replace with `[internal-host]`)
- Strip internal IP addresses (replace with `[internal-ip]`)
- Strip HTTP response headers
- Strip partial page content from timeout errors
- Return generic error codes with user-facing descriptions:
  - `AUTH_EXPIRED` -- "Session expired. Run `redhat-browser-mcp --login` to re-authenticate."
  - `URL_REJECTED` -- "URL not permitted by domain allowlist or SSRF filter."
  - `FETCH_FAILED` -- "Page could not be loaded. Check VPN connection."
  - `TIMEOUT` -- "Page load timed out after N seconds."
  - `BROWSER_BUSY` -- "Browser busy, try again shortly."
- Detailed errors are logged locally (audit log) but never returned via MCP

### MCP Tools Specification

#### Tool 1: `fetch_page`

**Purpose:** Fetch an internal page and return its content as markdown.

```
fetch_page(
    url: str,           # Required. Full URL to fetch (must pass domain allowlist + SSRF filter)
    format: str = "markdown",  # "markdown" | "html" | "text"
    wait_for: str = "",        # Optional CSS selector to wait for before extracting
    timeout: int = 30          # Page load timeout in seconds
) -> str
```

**Validation (before fetch):**
1. URL must use HTTPS scheme
2. URL hostname must match domain allowlist (default: `*.redhat.com`)
3. Resolved IP must not be in blocked ranges (RFC 1918, loopback, link-local, cloud metadata)
4. If validation fails, return sanitized `URL_REJECTED` error (do not reveal which specific check failed)

**Returns:** Markdown content with metadata header:
```
# [Page Title]
> Source: https://source.redhat.com/path/to/page
> Fetched: 2026-02-24T15:30:00Z

[Converted page content...]
```

**Error cases:**
- URL rejected by validation: Returns `URL_REJECTED` with generic message
- SSO redirect detected: Returns `AUTH_EXPIRED` with re-authentication instructions
- Timeout: Returns `TIMEOUT` error (no partial content returned)
- Content too large: Returns truncated content with truncation notice
- Browser busy: Returns `BROWSER_BUSY` if semaphore timeout exceeded

#### Tool 2: `list_links`

**Purpose:** Extract and list all links from a page's main content area.

```
list_links(
    url: str,              # Required. Page to extract links from (must pass validation)
    link_filter: str = "", # Optional regex filter on link text or URL (max 200 chars)
    internal_only: bool = True  # Only return links to *.redhat.com domains
) -> str
```

**Returns:** Markdown list of links:
```
## Links from [Page Title]

- [Link Text 1](https://source.redhat.com/path1)
- [Link Text 2](https://source.redhat.com/path2)
...

Found 42 links (showing internal only).
```

#### Tool 3: `check_auth`

**Purpose:** Verify that the browser session is authenticated and can access internal sites.

```
check_auth() -> str
```

**Returns:**
```
Authentication status: ACTIVE
Test URL: https://source.redhat.com
Auth state: ~/.redhat-browser-mcp/auth-state.json
Session age: 2h 15m (approximate, based on last login timestamp)
```

Or if not authenticated:
```
Authentication status: EXPIRED
Action required: Run `redhat-browser-mcp --login` to re-authenticate.
```

**Session age:** Calculated from a `~/.redhat-browser-mcp/last-login` timestamp file written when `--login` completes. This is approximate -- the actual SSO session may expire independently.

### Directory Structure

```
claude-devkit/
└── mcp-servers/
    └── redhat-browser/
        ├── .gitignore             # Exclude .venv/, __pycache__/, .pytest_cache/
        ├── README.md              # Setup, usage, troubleshooting, security model
        ├── pyproject.toml         # Project metadata and pinned dependencies
        ├── server.py              # MCP server entry point (FastMCP)
        ├── browser.py             # Playwright browser manager (storageState)
        ├── content.py             # HTML-to-markdown conversion with fallback pipeline
        ├── auth.py                # Login/SSO detection
        ├── url_validator.py       # Domain allowlist + SSRF filter
        ├── audit.py               # Audit logging
        ├── cli.py                 # CLI entry point (--login, --check, --serve)
        ├── tests/
        │   ├── test_content.py    # Content processor unit tests
        │   ├── test_auth.py       # Auth detection unit tests
        │   ├── test_url_validator.py  # URL validation + SSRF filter tests
        │   ├── test_server.py     # MCP tool integration tests
        │   └── fixtures/
        │       ├── sample_page.html        # Sample internal page HTML
        │       ├── confluence_page.html    # Sample Confluence/Angular page (for fallback testing)
        │       ├── complex_tables.html     # Tables with colspan/rowspan
        │       ├── sso_redirect.html       # Sample SSO login page
        │       └── expected_output.md      # Expected markdown conversion
        └── scripts/
            └── install.sh         # Install dependencies and configure Claude Code
```

**Why `mcp-servers/` instead of `contrib/`:** MCP servers are a fundamentally different component type from skills. Skills are markdown instruction files deployed to `~/.claude/skills/`. MCP servers are Python/Node applications that run as processes. Mixing them in `contrib/` would conflate two different deployment models. A new top-level `mcp-servers/` directory establishes the pattern for future MCP server additions. The `contrib/` directory was established for optional skills (journal-skill-blueprint.md, APPROVED), but MCP servers differ in deployment model (process lifecycle, venv, `claude mcp add`) vs. skill deployment (`deploy.sh` copies SKILL.md).

### Claude Code Integration

The server registers with Claude Code via the `claude mcp add` command:

```bash
claude mcp add --transport stdio --scope user redhat-browser \
  -- python /Users/imurphy/projects/claude-devkit/mcp-servers/redhat-browser/server.py
```

This adds the server at user scope (available across all projects).

**Configuration in `~/.claude.json`:**
```json
{
  "mcpServers": {
    "redhat-browser": {
      "type": "stdio",
      "command": "python",
      "args": ["/Users/imurphy/projects/claude-devkit/mcp-servers/redhat-browser/server.py"],
      "env": {}
    }
  }
}
```

## Interfaces / Schema Changes

### New MCP Tools (exposed to Claude Code)

| Tool | Input Schema | Output |
|------|-------------|--------|
| `fetch_page` | `{url: string, format?: "markdown"\|"html"\|"text", wait_for?: string, timeout?: int}` | Markdown string (or sanitized error) |
| `list_links` | `{url: string, link_filter?: string, internal_only?: bool}` | Markdown list of links |
| `check_auth` | `{}` | Status string |

**Removed from v1:** `search_page` -- deferred to v2. Claude Code can search the returned markdown of `fetch_page` natively without a dedicated tool.

### New Configuration

| File | Purpose | Permissions |
|------|---------|-------------|
| `~/.redhat-browser-mcp/` | Server data directory | `0700` |
| `~/.redhat-browser-mcp/auth-state.json` | Exported cookies/localStorage (storageState) | `0600` |
| `~/.redhat-browser-mcp/config.json` | Optional user config (allowed_domains, max content length, default timeout, rate limit) | `0600` |
| `~/.redhat-browser-mcp/audit.log` | Audit log of all tool invocations | `0600` |
| `~/.redhat-browser-mcp/browser.pid` | PID file for zombie process detection | `0600` |
| `~/.redhat-browser-mcp/last-login` | Timestamp of last successful `--login` | `0600` |

### CLAUDE.md Updates

Add `mcp-servers/` to the Architecture section and reference this server in a new "MCP Servers" section. See Phase 6 for specific sections.

## Data Migration

None. This is a new component with no existing data to migrate.

## Implementation Plan

### Phase 1: Project Scaffolding, Core Dependencies, and Security Foundation

**Goal:** Establish the project structure, dependency management, URL validation, audit logging, and basic server skeleton.

1. [ ] Create directory structure: `mcp-servers/redhat-browser/` with all subdirectories
2. [ ] Create `mcp-servers/redhat-browser/.gitignore`:
   ```
   .venv/
   __pycache__/
   *.pyc
   .pytest_cache/
   *.egg-info/
   ```
3. [ ] Create `mcp-servers/redhat-browser/pyproject.toml` with **pinned** dependencies:
   - `mcp==1.25.0` (Python MCP SDK -- pin exact version)
   - `playwright==1.49.1` (pin exact version)
   - `markdownify==0.14.1` (pin exact version)
   - `readability-lxml==0.8.1` (pin exact version)
   - `lxml==5.3.0` (pin exact version)
   - Dev dependencies: `pytest==8.3.4`, `pytest-asyncio==0.24.0`, `pip-audit==2.7.3`
4. [ ] Create `mcp-servers/redhat-browser/url_validator.py`:
   - HTTPS-only scheme validation
   - Configurable domain allowlist (default: `*.redhat.com`) with wildcard matching
   - SSRF filter: block RFC 1918, loopback, link-local, cloud metadata IP ranges
   - DNS resolution check: resolve hostname, verify resolved IP is not in blocked ranges
   - Return `(is_valid, error_reason)` -- error_reason is for local logging only, never returned to MCP
5. [ ] Create `mcp-servers/redhat-browser/audit.py`:
   - JSON-lines logger at `~/.redhat-browser-mcp/audit.log`
   - Log fields: timestamp, tool, url, status, content_size, duration_ms
   - Never log content
   - File permissions `0600`
   - Rate limiter: `asyncio` token bucket, configurable max requests/minute (default 30)
6. [ ] Create `mcp-servers/redhat-browser/server.py` with minimal FastMCP skeleton:
   - Import FastMCP, declare server name and description
   - Add single placeholder tool `check_auth` that returns "not implemented"
   - Add `if __name__ == "__main__": mcp.run(transport="stdio")`
7. [ ] Create Python virtual environment and install dependencies:
   ```bash
   cd mcp-servers/redhat-browser
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -e ".[dev]"
   pip-audit  # Check for known vulnerabilities
   playwright install chromium
   ```
8. [ ] Write URL validator tests:
   - `tests/test_url_validator.py` -- test allowlist matching, SSRF filter (RFC 1918, loopback, metadata endpoint, non-HTTPS schemes, DNS rebinding with blocked resolved IP)
9. [ ] Verify MCP server starts and responds:
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1"}}}' | python server.py
   ```
10. [ ] Validate: Server responds with `initialize` result containing tool list; URL validator tests pass; `pip-audit` reports no known vulnerabilities

**Parallel work:** None. This phase must complete first.

### Phase 2: Browser Manager

**Goal:** Implement the Playwright browser lifecycle with storageState-based auth and concurrency controls.

1. [ ] Create `mcp-servers/redhat-browser/browser.py`:
   - `BrowserManager` class with async context manager pattern
   - Singleton instance (one browser per server process)
   - **storageState authentication:**
     - `async def login()` -- launch headed browser, wait for user auth, export via `context.storage_state(path=AUTH_STATE_PATH)`, write `last-login` timestamp
     - `async def launch()` -- launch headless browser, create context with `browser.new_context(storage_state=AUTH_STATE_PATH)`
     - Auth state at `~/.redhat-browser-mcp/auth-state.json` (permissions `0600`)
   - **Event loop integration:** Uses `playwright.async_api.async_playwright()` exclusively. Never creates its own event loop. All methods are async coroutines called from MCP tool handlers on the loop created by `mcp.run()`. Browser launch has a 15-second timeout separate from page timeouts.
   - **Concurrency:** `asyncio.Semaphore(3)` for page pool. Each tool call acquires semaphore, creates page, navigates, extracts, closes page, releases. Wait timeout: 30 seconds. On timeout: return `BROWSER_BUSY` error.
   - **Zombie process recovery:**
     - On startup: check `~/.redhat-browser-mcp/browser.pid` for stale process; SIGTERM if alive
     - After launch: write current browser PID to PID file
     - Signal handlers for SIGTERM/SIGINT call `browser.close()`
     - `atexit` handler removes PID file
     - Catch `TargetClosedError` in page operations; reset browser reference for auto-relaunch on next call
   - **Profile directory hardening:**
     - Create `~/.redhat-browser-mcp/` with `os.makedirs(mode=0o700, exist_ok=True)`
     - On startup: verify directory permissions are `0700` and owner is current user. Warn and refuse to start if permissions are more permissive.
   - Max response size: 5MB per page load
   - `HEADED=1` env var for debug mode
2. [ ] Create `mcp-servers/redhat-browser/auth.py`:
   - `def is_sso_redirect(url: str, html: str) -> bool` -- detect SSO login pages
   - Check for: `sso.redhat.com` in URL, `auth.redhat.com` in URL, Keycloak form elements, "Log In" in title
   - Return structured result with redirect URL and detection reason
3. [ ] Write tests for auth detection:
   - `tests/fixtures/sso_redirect.html` -- sample Keycloak login page
   - `tests/test_auth.py` -- test detection logic against fixtures
4. [ ] Validate:
   ```bash
   cd mcp-servers/redhat-browser
   python -m pytest tests/test_auth.py -v
   ```

### Phase 3: Content Processor

**Goal:** Implement HTML-to-markdown conversion pipeline with content extraction and fallback.

1. [ ] Create `mcp-servers/redhat-browser/content.py`:
   - `def extract_content(html: str, url: str) -> str` -- use readability-lxml to extract article content
     - **XXE prevention:** `lxml.etree.XMLParser(resolve_entities=False)` for all lxml parsing
   - **Fallback pipeline:** If readability returns < 200 chars:
     - Try semantic selectors in order: `<main>`, `<article>`, `[role="main"]`, `#content`, `.content`, `#main`
     - Final fallback: `<body>` minus `<nav>`, `<header>`, `<footer>`, `<aside>`
     - Log which extraction method was used
   - `class RedHatMarkdownConverter(MarkdownConverter)` -- custom markdownify subclass:
     - Override `convert_table`: handle `colspan`/`rowspan` by degrading to indented plain text
     - Set `table_infer_header=True` for tables missing `<thead>`
     - Handle nested `<div>` and `<p>` inside `<td>` cells
   - `def html_to_markdown(html: str, options: dict) -> str` -- convert using custom converter
   - `def process_page(html: str, url: str, title: str, format: str, max_length: int) -> str` -- full pipeline
   - Options: strip images (default True), preserve code blocks
   - Metadata header with title, source URL, fetch timestamp
   - Truncation with notice when exceeding max_length
2. [ ] Create `mcp-servers/redhat-browser/content.py` link extraction:
   - `def extract_links(html: str, base_url: str, filter_regex: str, internal_only: bool) -> list[dict]`
   - Regex filter limited to 200 characters max; timeout on regex compilation
3. [ ] Create test fixtures:
   - `tests/fixtures/sample_page.html` -- representative internal page with nav, sidebar, code blocks, tables
   - `tests/fixtures/confluence_page.html` -- Confluence-style page with low text density main content (for fallback testing)
   - `tests/fixtures/complex_tables.html` -- tables with colspan, rowspan, missing thead
   - `tests/fixtures/expected_output.md` -- expected markdown output
4. [ ] Write tests:
   - `tests/test_content.py` -- test extraction, fallback pipeline, custom table conversion, code block preservation, truncation, link extraction, metadata headers
5. [ ] Validate:
   ```bash
   cd mcp-servers/redhat-browser
   python -m pytest tests/test_content.py -v
   ```

**Parallel with Phase 2:** Yes, content processing has no dependency on browser manager.

### Phase 4: MCP Tool Implementation

**Goal:** Wire browser manager, URL validator, content processor, audit logger, and error sanitizer into MCP tools.

1. [ ] Implement `fetch_page` tool in `server.py`:
   - Validate URL via `url_validator.validate_url()` -- reject before any browser interaction
   - Log invocation via audit logger
   - Acquire page semaphore
   - Call browser manager to fetch page
   - Check for SSO redirect; return sanitized `AUTH_EXPIRED` if detected
   - Process content through content pipeline
   - Sanitize any error messages (strip internal hostnames/IPs) before returning
   - Return formatted markdown with metadata header
2. [ ] Implement `list_links` tool in `server.py`:
   - Validate URL via url_validator
   - Fetch page via browser manager
   - Extract links via content processor
   - Apply `link_filter` and internal_only logic
   - Limit `link_filter` regex to 200 chars
   - Return formatted markdown link list
3. [ ] Implement `check_auth` tool in `server.py`:
   - Attempt to fetch `https://source.redhat.com` via browser
   - Report authentication status, auth state file path, session age (from `last-login` timestamp)
   - Sanitize error messages
4. [ ] Write integration tests:
   - `tests/test_server.py` -- test tool invocation via MCP protocol
   - Mock Playwright to avoid requiring real browser in CI
   - Test URL rejection for blocked URLs, SSRF attempts
   - Test error sanitization (verify no internal hostnames in MCP responses)
5. [ ] Validate:
   ```bash
   cd mcp-servers/redhat-browser
   python -m pytest tests/ -v
   ```

### Phase 5: CLI and Installation

**Goal:** Create CLI entry point, install script, and Claude Code registration.

1. [ ] Create `mcp-servers/redhat-browser/cli.py`:
   - `--login` mode: Launch browser in headed mode, navigate to source.redhat.com, wait for user to authenticate, export storageState, write `last-login` timestamp, then exit
   - `--check` mode: Run check_auth and print status
   - `--serve` mode (default): Start MCP server via stdio
   - `--wipe-profile` mode: Securely delete `~/.redhat-browser-mcp/` contents (overwrite then delete)
   - `--audit-log` mode: Print the last N entries from the audit log
   - Uses `argparse` for argument parsing
2. [ ] Create `mcp-servers/redhat-browser/scripts/install.sh`:
   ```bash
   #!/usr/bin/env bash
   # Install redhat-browser MCP server
   set -euo pipefail

   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
   SERVER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

   # Check prerequisites
   if ! command -v claude &>/dev/null; then
       echo "Error: 'claude' CLI not found in PATH."
       echo "Install Claude Code first: https://claude.ai/code"
       exit 1
   fi

   # Create venv and install
   python3 -m venv "$SERVER_DIR/.venv"
   "$SERVER_DIR/.venv/bin/pip" install -e "$SERVER_DIR"

   # Audit dependencies for known vulnerabilities
   "$SERVER_DIR/.venv/bin/pip-audit"

   # Install Chromium
   "$SERVER_DIR/.venv/bin/playwright" install chromium

   # Create data directory with restricted permissions
   mkdir -p -m 0700 ~/.redhat-browser-mcp

   # Register with Claude Code
   claude mcp add --transport stdio --scope user redhat-browser \
     -- "$SERVER_DIR/.venv/bin/python" "$SERVER_DIR/server.py"

   echo "Installed. Run: redhat-browser-mcp --login"
   ```
3. [ ] Create `mcp-servers/redhat-browser/README.md`:
   - **Data classification warning** (prominent, first section)
   - Prerequisites (Python 3.11+, VPN access)
   - Installation steps
   - First-time authentication
   - Usage examples in Claude Code
   - Security model (domain allowlist, SSRF protection, audit logging, profile permissions)
   - Configuring the domain allowlist
   - Viewing audit logs
   - Troubleshooting (session expired, VPN not connected, Playwright install fails, profile permissions wrong)
4. [ ] Validate:
   ```bash
   # Install
   cd mcp-servers/redhat-browser
   bash scripts/install.sh

   # Verify registration
   claude mcp list | grep redhat-browser

   # Login (manual step)
   python cli.py --login

   # Check auth
   python cli.py --check

   # View audit log
   python cli.py --audit-log
   ```

### Phase 6: CLAUDE.md and Documentation Updates

**Goal:** Update project documentation to reflect the new component type.

1. [ ] Update `/Users/imurphy/projects/claude-devkit/CLAUDE.md` with the following specific changes:
   - **Architecture section:** Rename "Three-Tier Structure" heading to reflect the addition. Add `mcp-servers/` to the directory tree diagram with annotation:
     ```
     ├── mcp-servers/         # MCP server applications (process-based, venv-isolated)
     │   └── redhat-browser/  # Authenticated internal site browser
     ```
   - **MCP Server Registry:** Add a new section parallel to "Skill Registry" and "Generator Registry":
     ```
     ## MCP Server Registry
     | Server | Version | Purpose | Transport | Prerequisites |
     |--------|---------|---------|-----------|---------------|
     | redhat-browser | 1.0.0 | Browse Red Hat internal sites via authenticated browser | stdio | Python 3.11+, VPN, Red Hat SSO |
     ```
   - **Data Flow diagram:** Update to show MCP server path:
     ```
     Edit mcp-servers/*/... → git commit → ./scripts/install.sh → claude mcp add → Available in Claude Code
     ```
   - **Development Rules:** Add "For MCP Servers" subsection:
     - Pin exact dependency versions
     - Include `pip-audit` in install scripts
     - Set profile/data directory permissions to `0700`
     - Include audit logging
     - Document data classification obligations
   - **Directory Reference:** Add `/mcp-servers` section describing the directory's purpose, structure, and deployment model
   - **Recommended `.gitignore`:** Add `mcp-servers/*/.venv/` entry
2. [ ] Validate:
   ```bash
   # Smoke test: start Claude Code, verify MCP server is listed
   claude mcp list
   # In Claude Code session:
   # > /mcp   (should show redhat-browser)
   # > Use redhat-browser to check if I'm authenticated
   ```
3. [ ] Commit all changes

## Rollout Plan

### Stage 1: Local Development (Day 1-3)
- Implement Phases 1-4
- All unit tests passing
- Manual testing against source.redhat.com with VPN active
- Verify URL validation blocks SSRF attempts
- Verify audit log records all invocations

### Stage 2: Integration Testing (Day 4-5)
- Implement Phase 5
- Register with Claude Code
- End-to-end test: ask Claude to read an internal page
- Test session expiry and re-authentication flow
- Test error sanitization (verify no internal hostnames in Claude Code output)
- Verify storageState persistence across server restarts

### Stage 3: Documentation and Polish (Day 6)
- Implement Phase 6
- README with security model and troubleshooting guide
- CLAUDE.md updates

### Stage 4: Daily Use Validation (Week 2)
- Use in real work sessions for one week
- Review audit log for unexpected patterns
- Document edge cases and failure modes
- Iterate on content extraction quality (especially Confluence pages)

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **Internal content sent to Anthropic API** | Certain | High | Data classification warning in README; domain allowlist limits scope; user accepts responsibility; audit log provides accountability |
| **SSRF via fetch_page** | Low (with mitigations) | Critical | URL allowlist (*.redhat.com default), SSRF filter (RFC 1918, loopback, metadata), DNS resolution check, HTTPS-only |
| **Profile/auth-state theft** | Medium | Critical | Directory `0700`, files `0600`, ownership check on startup, `--wipe-profile` for secure deletion |
| **Red Hat SSO session expires frequently** | Medium | Medium | `check_auth` tool warns proactively; `--login` CLI makes re-auth fast; `last-login` timestamp tracks session age |
| **Playwright Chromium install blocked by corporate firewall** | Low | High | Document manual Chromium download; support `PLAYWRIGHT_BROWSERS_PATH` env var for pre-installed browsers |
| **Internal pages heavily JS-rendered, content extraction poor** | Medium | Medium | `wait_for` parameter lets user specify CSS selectors; fallback pipeline (semantic selectors); `format: "html"` bypass |
| **readability-lxml returns wrong content for Confluence/Angular pages** | Medium | Medium | Fallback pipeline: semantic selectors `<main>`, `<article>`, `[role="main"]`, `#content`; log which method succeeded |
| **markdownify produces invalid tables** | Medium | Low | Custom `MarkdownConverter` subclass degrades complex tables to indented plain text |
| **Large pages exceed MCP token limits** | Medium | Low | Configurable max_length with truncation; max response size 5MB |
| **Browser process leaks / zombie processes** | Low | Medium | PID file, SIGTERM/SIGINT handlers, atexit cleanup, TargetClosedError detection and auto-relaunch |
| **Concurrent tool calls exhaust page pool** | Medium | Low | `asyncio.Semaphore(3)` with 30s wait timeout; clear `BROWSER_BUSY` error |
| **Dependency supply chain compromise** | Low | High | Exact version pins; `pip-audit` in install script; Playwright Chromium checksum verification |
| **Error messages leak internal hostnames** | Medium | Medium | Error sanitizer strips hostnames/IPs before MCP response; detailed errors logged locally only |
| **Profile directory corruption** | Low | Low | storageState avoids persistent userDataDir corruption bug; `--wipe-profile` CLI for recovery |

## Test Plan

### Unit Tests

```bash
cd /Users/imurphy/projects/claude-devkit/mcp-servers/redhat-browser
python -m pytest tests/ -v
```

**Test coverage:**

| Test File | Coverage |
|-----------|----------|
| `test_auth.py` | SSO redirect detection: Keycloak form, URL patterns, title matching, non-login pages (negative cases) |
| `test_content.py` | HTML extraction, readability fallback pipeline (short content triggers fallback, semantic selector extraction), custom table converter (colspan, rowspan, missing thead), code block preservation, truncation, link extraction, metadata headers |
| `test_url_validator.py` | Domain allowlist matching (exact, wildcard, rejection), SSRF filter (RFC 1918, loopback, link-local, metadata), scheme validation (HTTPS only, reject http/file/javascript/data), DNS resolution check |
| `test_server.py` | MCP tool invocation via protocol, URL rejection for blocked URLs, error sanitization (no internal hostnames in responses), parameter validation, auth failure response |

### Integration Tests (Manual)

These require VPN access and a valid Red Hat SSO session.

1. **Authentication flow:**
   ```bash
   python cli.py --login
   # Manually authenticate in browser
   python cli.py --check
   # Expected: "Authentication status: ACTIVE"
   # Verify: ~/.redhat-browser-mcp/auth-state.json exists with 0600 permissions
   # Verify: ~/.redhat-browser-mcp/last-login exists
   ```

2. **Page fetch:**
   ```bash
   # In Claude Code session with MCP server running:
   # > "Fetch the page at https://source.redhat.com and summarize it"
   # Expected: Claude receives markdown content and provides summary
   # Verify: audit.log contains the fetch entry
   ```

3. **URL rejection:**
   ```bash
   # > "Fetch the page at http://localhost:8080"
   # Expected: URL_REJECTED error (no internal details)
   # > "Fetch the page at http://169.254.169.254/latest/meta-data/"
   # Expected: URL_REJECTED error
   # Verify: audit.log shows status "url_rejected" for both
   ```

4. **Session expiry handling:**
   ```bash
   # Delete auth-state.json, then:
   # > "Fetch https://source.redhat.com"
   # Expected: AUTH_EXPIRED message with re-authentication instructions
   ```

5. **Error sanitization:**
   ```bash
   # Fetch a page that returns an error
   # Verify: MCP response contains no internal hostnames or IP addresses
   ```

### Exact Test Command

```bash
cd /Users/imurphy/projects/claude-devkit/mcp-servers/redhat-browser && python -m pytest tests/ -v --tb=short
```

## Acceptance Criteria

1. [ ] `redhat-browser-mcp --login` launches a headed Chromium browser where the user can authenticate to Red Hat SSO, then exports storageState
2. [ ] `redhat-browser-mcp --check` reports authentication status (ACTIVE or EXPIRED) with approximate session age
3. [ ] Claude Code can call `fetch_page` with a `*.redhat.com` URL and receive clean markdown content
4. [ ] Claude Code can call `list_links` and receive a filtered list of internal links
5. [ ] `fetch_page` rejects non-HTTPS URLs, non-allowlisted domains, and SSRF targets with a generic error
6. [ ] SSO redirect detection correctly identifies login pages and returns actionable guidance
7. [ ] Browser sessions persist across server restarts via storageState (no re-authentication required within SSO session lifetime)
8. [ ] All unit tests pass: `python -m pytest tests/ -v` exits with code 0
9. [ ] `scripts/install.sh` successfully installs dependencies, runs `pip-audit`, registers the MCP server with Claude Code, and `claude mcp list` shows the server
10. [ ] Content extraction handles pages with code blocks, tables (including colspan/rowspan), and nested headings without data loss
11. [ ] `~/.redhat-browser-mcp/` directory has `0700` permissions; all files within have `0600` permissions
12. [ ] `~/.redhat-browser-mcp/audit.log` records all tool invocations with URL, timestamp, status, and content size
13. [ ] Error messages returned via MCP contain no internal hostnames or IP addresses
14. [ ] Server handles concurrent tool calls via semaphore without crashes or race conditions
15. [ ] `pip-audit` reports no known vulnerabilities in pinned dependencies

## Task Breakdown

### Files to Create

| File | Purpose | Lines (est.) |
|------|---------|-------------|
| `mcp-servers/redhat-browser/.gitignore` | Exclude build artifacts | 10 |
| `mcp-servers/redhat-browser/pyproject.toml` | Package metadata and pinned dependencies | 45 |
| `mcp-servers/redhat-browser/server.py` | FastMCP server with 3 tools, error sanitization | 280 |
| `mcp-servers/redhat-browser/browser.py` | Playwright browser manager (storageState, semaphore, PID, signals) | 260 |
| `mcp-servers/redhat-browser/content.py` | HTML extraction with fallback pipeline, custom table converter | 220 |
| `mcp-servers/redhat-browser/auth.py` | SSO redirect detection | 60 |
| `mcp-servers/redhat-browser/url_validator.py` | Domain allowlist + SSRF filter + DNS check | 120 |
| `mcp-servers/redhat-browser/audit.py` | Audit logging + rate limiter | 90 |
| `mcp-servers/redhat-browser/cli.py` | CLI entry point (--login, --check, --serve, --wipe-profile, --audit-log) | 100 |
| `mcp-servers/redhat-browser/scripts/install.sh` | Installation, pip-audit, and Claude Code registration | 50 |
| `mcp-servers/redhat-browser/README.md` | Setup, usage, security model, troubleshooting | 200 |
| `mcp-servers/redhat-browser/tests/__init__.py` | Test package init | 1 |
| `mcp-servers/redhat-browser/tests/test_auth.py` | Auth detection tests | 60 |
| `mcp-servers/redhat-browser/tests/test_content.py` | Content processing + fallback + table tests | 150 |
| `mcp-servers/redhat-browser/tests/test_url_validator.py` | URL validation + SSRF filter tests | 120 |
| `mcp-servers/redhat-browser/tests/test_server.py` | MCP tool integration + error sanitization tests | 120 |
| `mcp-servers/redhat-browser/tests/fixtures/sample_page.html` | Test fixture: internal page | 80 |
| `mcp-servers/redhat-browser/tests/fixtures/confluence_page.html` | Test fixture: Confluence/Angular page | 60 |
| `mcp-servers/redhat-browser/tests/fixtures/complex_tables.html` | Test fixture: tables with colspan/rowspan | 50 |
| `mcp-servers/redhat-browser/tests/fixtures/sso_redirect.html` | Test fixture: Keycloak login | 40 |
| `mcp-servers/redhat-browser/tests/fixtures/expected_output.md` | Test fixture: expected markdown | 30 |

### Files to Modify

| File | Change |
|------|--------|
| `/Users/imurphy/projects/claude-devkit/CLAUDE.md` | Add `mcp-servers/` architecture section, MCP Server Registry, Development Rules for MCP Servers, directory reference, .gitignore update |

### Total Estimated Effort

- **New files:** 21
- **Modified files:** 1
- **Estimated lines of code:** ~2,000
- **Estimated time:** 5-7 days (including manual testing with VPN and iteration on content extraction)

## Context Alignment

### CLAUDE.md Patterns Followed

| Pattern | Alignment |
|---------|-----------|
| **Three-tier structure** | Extended with new `mcp-servers/` tier -- justified because MCP servers are a different deployment model from skills (processes vs markdown files) |
| **Personal tools in contrib/** | **Deviation:** Using `mcp-servers/` instead of `contrib/` because MCP servers require different deployment (process lifecycle, venv, CLI) vs skill deployment (copy SKILL.md). The `contrib/` directory was established for optional skills (journal-skill-blueprint.md, APPROVED), but MCP servers differ in deployment model (running processes with venvs vs. markdown files copied by `deploy.sh`), justifying a distinct top-level directory. |
| **External tool integration (zerg-adoption-priorities.md)** | Followed -- opt-in (user runs install.sh), loosely coupled (self-contained server), swappable (remove via `claude mcp remove`). |
| **Python for generators** | Followed -- Python used consistently with existing tooling |
| **Validate before committing** | Followed -- test suite included with exact test command; `pip-audit` for dependency validation |
| **Conventional commits** | Followed -- commit messages will use `feat(mcp-servers):` prefix |
| **Directory per component** | Followed -- `mcp-servers/redhat-browser/` with self-contained structure |
| **README documentation** | Followed -- README with prerequisites, setup, usage, security model, troubleshooting |
| **Script-based deployment** | Followed -- `scripts/install.sh` for automated setup |

### Deviations with Justification

1. **New top-level directory `mcp-servers/`** -- Skills are static markdown files deployed by copying to `~/.claude/skills/`. MCP servers are running Python processes registered via `claude mcp add`. The deployment, lifecycle, and dependency management are fundamentally different. Placing MCP servers in `contrib/` would require `deploy.sh` changes that conflate two unrelated deployment models. A new top-level directory establishes a clean pattern for future MCP servers (e.g., Jira MCP, Confluence MCP). This is consistent with the `contrib/` precedent (journal-skill-blueprint.md, APPROVED) which chose `contrib/` specifically for optional *skills* -- MCP servers are not skills.

2. **No SKILL.md file** -- MCP servers are not skills. They don't follow the skill v2.0.0 patterns (numbered steps, verdict gates, etc.) because they are infrastructure components, not workflow definitions. Claude Code discovers them via `claude mcp list`, not via `/<skill-name>`.

3. **Virtual environment per server** -- Unlike generators which share the system Python, MCP servers need isolated dependencies (Playwright, etc.) to avoid polluting the system environment. Each server gets its own `.venv/`.

## Next Steps

1. **Execute Phase 1** -- Engineer creates project structure, installs pinned dependencies, implements URL validator and audit logger, verifies MCP server skeleton starts
2. **Execute Phases 2-3 in parallel** -- Browser manager (storageState) and content processor (fallback pipeline) are independent
3. **Execute Phase 4** -- Wire tools together with URL validation, audit logging, and error sanitization
4. **Execute Phase 5** -- CLI, install script, Claude Code registration
5. **Manual testing** -- Authenticate via VPN, fetch real internal pages, verify URL rejection, review audit log, iterate on content quality
6. **Execute Phase 6** -- CLAUDE.md updates (specific sections listed in Phase 6)

**Open questions for the implementer:**
- Confirm Playwright can install Chromium on Red Hat corporate macOS (no MDM restrictions on browser installs)
- Confirm `source.redhat.com` session lifetime (assumed 8 hours; may be shorter)
- Determine if any internal sites use client certificate authentication (not handled in this plan)

## Plan Metadata

- **Plan File:** `./plans/redhat-internal-browser-mcp.md`
- **Affected Components:** New `mcp-servers/redhat-browser/` directory, `CLAUDE.md`
- **Validation:** `cd /Users/imurphy/projects/claude-devkit/mcp-servers/redhat-browser && python -m pytest tests/ -v --tb=short`
- **Version:** 1.0.0

---

## Research Sources

- [MCP Python SDK (GitHub)](https://github.com/modelcontextprotocol/python-sdk) -- Official SDK with FastMCP pattern
- [Claude Code MCP Documentation](https://code.claude.com/docs/en/mcp) -- stdio/SSE/HTTP transport configuration
- [Authenticated Browser MCP Gist](https://gist.github.com/theabbie/d3f3e55882b2028fbfc5ba2323265d53) -- Reference architecture for persistent browser session approach
- [mcp-cookies (GitHub)](https://github.com/jgowdy-godaddy/mcp-cookies) -- Cookie extraction approach (evaluated, not chosen)
- [Playwright Authentication Docs](https://playwright.dev/docs/auth) -- storageState API for authentication reuse
- [Playwright Issue #35466](https://github.com/microsoft/playwright/issues/35466) -- macOS headed/headless profile corruption bug (motivates storageState approach)
- [mcp-chrome (GitHub)](https://github.com/hangwin/mcp-chrome) -- Chrome extension-based approach (evaluated, not chosen)
- [markdownify Issue #49](https://github.com/matthewwithanm/python-markdownify/issues/49) -- Table conversion limitations (motivates custom converter)

## Status: APPROVED

<!-- Context Metadata
discovered_at: 2026-02-24T15:30:00Z
revised_at: 2026-02-24
claude_md_exists: true
recent_plans_consulted: journal-skill-blueprint.md, zerg-adoption-priorities.md
archived_plans_consulted: none
revision_trigger: red team FAIL + feasibility REVISE + librarian required edits
-->
