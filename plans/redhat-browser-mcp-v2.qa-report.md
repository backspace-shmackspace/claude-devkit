# QA Report: Re-architect Red Hat Internal Browser MCP to helper-mcps

**Plan:** `plans/redhat-browser-mcp-v2.md`
**Date:** 2026-02-24
**Revision Round:** 2
**QA Engineer:** qa-engineer agent
**Verdict:** FAIL

---

## Previous Blocker Resolution Status

| Blocker | Description | Status |
|---------|-------------|--------|
| BLOCKER-1 | Test import failure (`ModuleNotFoundError: No module named 'redhat_browser_mcp'`) | **RESOLVED** -- All test files now use `sys.path` manipulation matching jira-mcp pattern. Tests import directly (e.g., `from server import RedHatBrowserMCPServer`). All 6 test files are collected by pytest (125 items total including shared auth). |
| BLOCKER-2 | Relative import conflict in source modules (`from .browser_client import ...`) | **RESOLVED** -- `server.py` now uses direct imports: `from browser_client import BrowserClient`, `from content import ContentExtractionError`, `from url_validator import URLValidationError`. `browser_client.py` uses direct imports for local modules and qualified imports for shared modules (`from shared.auth import ...`). Consistent with `__main__.py`'s `sys.path` approach. |

**Both blockers from the previous QA round have been fixed.**

---

## Previous Deviation Resolution Status

| Deviation | Description | Status |
|-----------|-------------|--------|
| DEV-1 | Tool names changed (`list_page_links`, `get_audit_log` instead of `list_links`, `check_auth`) | **RESOLVED** -- `server.py` now registers `fetch_page`, `list_links`, and `check_auth` matching plan's explicit non-goal constraint. |
| DEV-2 | `get_headers()` raises `NotImplementedError` instead of returning empty dict | **RESOLVED** -- `shared/auth.py` line 336-350: `get_headers()` now returns `{}` with a logged warning. LSP-compliant. Test `test_get_headers_returns_empty_dict_with_warning` in `tests/test_auth.py` confirms this. |
| DEV-3 | `get_storage_state()` replaced with `get_storage_state_path()` | **ACCEPTED (unchanged)** -- Still returns `Path` via `get_storage_state_path()`. Functionally correct: Playwright's `new_context(storage_state=str(path))` accepts a file path. This is a pragmatic deviation. |
| DEV-4 | Missing `config.py` and `requirements.txt` | **RESOLVED** -- `config.py` (63 lines) exists with `load_config()` function reading env vars: `REDHAT_BROWSER_ALLOWED_DOMAINS`, `REDHAT_BROWSER_RATE_LIMIT`, `REDHAT_BROWSER_MAX_RESPONSE_SIZE`, `REDHAT_BROWSER_BROWSER_LAUNCH_TIMEOUT`, `REDHAT_BROWSER_AUDIT_DIR`. `requirements.txt` (17 lines) lists all dependencies. |
| DEV-5 | `audit.py` as separate module (plan said inline in `browser_client.py`) | **ACCEPTED (unchanged)** -- `audit.py` remains separate. Cleaner architecture than inlining into `browser_client.py`. |
| DEV-6 | Environment variable names differ from plan | **ACCEPTED (unchanged)** -- Uses `PLAYWRIGHT_STORAGE_STATE_PATH` instead of plan's `MCP_STORAGE_STATE_PATH`. Consistent across all files. |
| DEV-7 | docker-compose.yml missing env vars and audit volume | **PARTIALLY RESOLVED** -- `docker-compose.yml` now includes `REDHAT_BROWSER_AUDIT_DIR=/audit` and an audit volume mount at line 74. Still missing `REDHAT_BROWSER_AUTH_TYPE` env var, but `auth_adapter.py` always creates `PlaywrightStorageStateProvider` so this var would be unused. |

---

## Acceptance Criteria Coverage

| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | `PlaywrightStorageStateProvider` exists with correct `get_headers()` behavior | **MET** | Class at `shared/auth.py:302`. `get_headers()` returns `{}` with warning (line 346-350). `get_storage_state_path()` returns `Path`. `validate()` checks file existence and JSON structure. `refresh_if_needed()` re-validates. 7 test classes in `tests/test_auth.py` covering init, validate, get_headers, get_storage_state_path, refresh. |
| 2 | Package structure matches jira-mcp | **MET** | `redhat-browser-mcp/` contains: `__init__.py`, `__main__.py`, `server.py`, `browser_client.py`, `auth_adapter.py`, `audit.py`, `content.py`, `url_validator.py`, `config.py`, `requirements.txt`, `Dockerfile`, `tests/`. Structure parallels jira-mcp. |
| 3 | `RedHatBrowserMCPServer` inherits `BaseMCPServer` with 3 tools | **MET** | `server.py:26`: `class RedHatBrowserMCPServer(BaseMCPServer)`. Registers 3 tools: `fetch_page` (line 40), `list_links` (line 61), `check_auth` (line 82). Tool names match plan. |
| 4 | Lifecycle state machine in `__main__.py` | **MET** | Full lifecycle: INITIALIZING -> SERVICE_VALIDATED -> STDIO_VALIDATED -> READY. Signal handlers (SIGTERM/SIGINT), atexit cleanup, ready timeout watchdog. Follows jira-mcp pattern exactly. |
| 5 | Structured logging (no `print()`) | **MET** | Zero `print()` calls in source. All modules use `logging.getLogger()`. `__main__.py` calls `configure_logging("redhat-browser-mcp")`. |
| 6 | `ToolError` returns (no emoji strings) | **MET** | `server.py` wraps all errors in `ToolError` with `retryable` flag. `BaseMCPServer.call_tool` catches unhandled exceptions and wraps in `ToolError`. No emoji strings found anywhere. |
| 7 | SSRF protection preserved | **MET** | `url_validator.py` preserves all checks: loopback, link-local, private IP, cloud metadata (169.254.169.254, fd00:ec2::254), DNS resolution check, domain allowlist. `_check_ip_blocked()` and `validate_url()` fully implemented. |
| 8 | Content extraction preserved | **MET** | `content.py` preserves full fallback pipeline: readability -> article -> main -> body -> fallback. `TableAwareMarkdownConverter`, `extract_main_content()`, `extract_links()`, `sanitize_error_message()` all present. |
| 9 | Rate limiting preserved | **MET** | `audit.py` implements sliding window rate limiting via `check_rate_limit()` with configurable limit (default: 30/min). `browser_client.py` calls `check_rate_limit()` before each fetch. Tests verify rate limit enforcement. |
| 10 | Tests exist for all modules | **PARTIAL** | Test files exist for all 6 modules: `test_server.py`, `test_browser_client.py`, `test_auth_adapter.py`, `test_audit.py`, `test_content.py`, `test_url_validator.py`. However, **17 of 72 redhat-browser-mcp tests fail** (see BLOCKER-1 and BLOCKER-2 below). |
| 11 | `config.py` and `requirements.txt` exist | **MET** | `config.py` has `load_config()` with env var overrides. `requirements.txt` lists 7 dependencies. Note: `requirements.txt` lists `html2text==2024.2.26` but `content.py` imports `markdownify` not `html2text`. Both are installed in `.venv` but the requirements file has a mismatch with the Dockerfile which correctly lists `markdownify==0.13.1`. |
| 12 | Dockerfile is correct | **MET (structurally)** | Multi-stage build: builder installs Playwright + Chromium, runtime copies binaries. Non-root user `mcp`. `/secrets` and `/audit` directories created. `CMD ["python", "-m", "redhat-browser-mcp"]`. Cannot verify Docker build (no Docker in session). |
| 13 | `pyproject.toml`, `Makefile`, `docker-compose.yml` updated | **MET** | `pyproject.toml`: testpaths and coverage source include `redhat-browser-mcp`. `Makefile`: `test-redhat-browser` and `build-redhat-browser` targets present, included in `build-all`. `docker-compose.yml`: service defined with volume mounts, healthcheck, and `shm_size: "2gb"`. |
| 14 | `mcp-servers/` deleted from claude-devkit | **MET** | Directory does not exist. CLAUDE.md has "MCP Servers (Migrated)" section explaining the migration. |

---

## Blocking Issues

### BLOCKER-1: `pytest-asyncio` Not Installed -- 16 Async Test Failures

**Severity:** Critical (blocks acceptance criterion 10)

All 16 async tests across `test_server.py` and `test_browser_client.py` fail with:

```
async def functions are not natively supported.
You need to install a suitable plugin for your async framework, for example:
  - pytest-asyncio
```

The tests use `@pytest.mark.asyncio` decorator and `pyproject.toml` has `asyncio_mode = "auto"`, but `pytest-asyncio` is **not installed** in the `.venv` (Python 3.12). Only `anyio` is installed, and `anyio` does not support the `@pytest.mark.asyncio` decorator.

**Failing tests (16):**
- `test_server.py`: 6 tests (all handler tests)
- `test_browser_client.py`: 9 tests (start, close, check_auth_status, validate_connection, semaphore, rate_limit)
- Note: `test_browser_client.py::TestSemaphoreConcurrencyControl::test_semaphore_limits_concurrent_operations` is a sync test incorrectly decorated with `@pytest.mark.asyncio`

**Fix Required:** Add `pytest-asyncio` to the dev dependencies or switch tests to use `anyio` backend (matching whatever pattern the other MCP servers use). The `pyproject.toml` already configures `asyncio_mode = "auto"` which suggests `pytest-asyncio` was intended.

### BLOCKER-2: `test_url_validator.py::test_allows_custom_domain_pattern` Fails

**Severity:** Medium (1 test failure indicating a logic bug)

Test expects `validate_url("https://example.com", allowed_domains=["*.example.com"])` to pass, but `fnmatch.fnmatch("example.com", "*.example.com")` returns `False` because `*` in fnmatch does not match an empty prefix.

```
URLValidationError: Domain not in allowlist: example.com
```

The test asserts that `*.example.com` should match `example.com` (bare domain), but `fnmatch` glob matching requires at least one character before the dot. This is either a test bug (should use `example.com` in allowed_domains or `sub.example.com` in URL) or a code bug (should also check exact domain match without wildcard).

**Impact:** URL allowlist will not match bare domains when only wildcard patterns are configured. For the default `*.redhat.com` pattern, `redhat.com` (without subdomain) would also be rejected.

---

## Remaining Deviations (Non-Blocking)

### DEV-R1: `requirements.txt` Lists `html2text` but Code Uses `markdownify`

`requirements.txt` line 16 lists `html2text==2024.2.26`, but `content.py` imports `from markdownify import MarkdownConverter`. The Dockerfile correctly lists `markdownify==0.13.1` but does not list `html2text`. Both packages are installed in `.venv`, but the `requirements.txt` is inconsistent with actual code usage.

### DEV-R2: `config.py` Is Not Used by `__main__.py`

`config.py` defines `load_config()` but `__main__.py` never calls it. `BrowserClient` receives parameters directly from the constructor defaults in `__main__.py`. Configuration from environment variables will not be loaded at runtime unless `config.py` is wired in.

### DEV-R3: Dockerfile Uses Older Playwright Version

`Dockerfile` line 24 installs `playwright==1.41.2` but `requirements.txt` specifies `playwright==1.51.0`. Version mismatch could cause runtime issues if APIs differ.

### DEV-R4: `_is_retryable()` Returns True for Playwright Timeouts

`server_base.py:128` returns `True` for Playwright `TimeoutError`. The plan's analysis states that "browser state corruption requires a restart, not a retry." However, this behavior benefits all servers equally and is a design decision rather than a bug.

---

## Test Results Summary

```
Total collected:     125 items
Passed:              108
Failed:              17
Warnings:            18

Breakdown of failures:
  - 16 async test failures (missing pytest-asyncio)
  - 1 URL validator test failure (fnmatch logic bug)
```

**Test files and their status:**

| Test File | Total | Pass | Fail | Root Cause |
|-----------|-------|------|------|------------|
| `test_audit.py` | 10 | 10 | 0 | -- |
| `test_auth_adapter.py` | 3 | 3 | 0 | -- |
| `test_browser_client.py` | 13 | 4 | 9 | Missing `pytest-asyncio` |
| `test_content.py` | 12 | 12 | 0 | -- |
| `test_server.py` | 8 | 2 | 6 | Missing `pytest-asyncio` |
| `test_url_validator.py` | 13 | 12 | 1 | fnmatch logic bug |
| `tests/test_auth.py` (shared) | 53 | 53 | 0 | -- |
| **Subtotals** | **112** | **96** | **16** | |

(13 items from other shared test files also passed but not shown.)

---

## Comparison with Previous QA Report

| Metric | Round 1 | Round 2 | Delta |
|--------|---------|---------|-------|
| Blocking Issues | 2 | 2 | Same count but different issues |
| Plan Deviations | 7 | 4 (non-blocking) | -3 (3 fixed) |
| Missing Test Files | 2 | 0 | -2 (both created) |
| Criteria Met | 8/14 | 11/14 | +3 |
| Criteria Partial | 3/14 | 1/14 | -2 |
| Criteria Failed | 2/14 | 0/14 | -2 |
| Test Pass Rate | 0% (all import failures) | 85% (108/125) | +85% |

Significant progress between rounds. The import and relative-import issues are fully resolved. Tool names now match the plan. `config.py`, `requirements.txt`, `test_browser_client.py`, and `test_auth_adapter.py` have all been created.

---

## Required Fixes for PASS

1. **Install `pytest-asyncio`** in `.venv` and verify all 16 async tests pass. Alternatively, add `pytest-asyncio` to the project's dev dependency list so future installs include it.

2. **Fix `test_allows_custom_domain_pattern`** -- either update the test to use a URL that matches the wildcard pattern (e.g., `sub.example.com`), or update `validate_url()` to also check exact domain match alongside wildcard match.

---

## Summary

| Category | Count |
|----------|-------|
| Blocking Issues | 2 |
| Non-Blocking Deviations | 4 |
| Criteria Met | 11 of 14 |
| Criteria Partial | 1 of 14 |
| Tests Passing | 108 of 125 (86%) |

The implementation has made substantial progress since Round 1. Both previous blockers are resolved, tool names are corrected, and all missing files have been created. The remaining blockers are smaller in scope: a missing test dependency (`pytest-asyncio`) and one test/logic mismatch in URL validation. Once those are fixed, the suite should pass cleanly and this implementation will meet acceptance criteria.

---

**Verdict: FAIL**

Two blocking issues remain: (1) `pytest-asyncio` is not installed, causing 16 async test failures, and (2) one URL validator test fails due to an fnmatch wildcard matching edge case. Both are straightforward fixes.
