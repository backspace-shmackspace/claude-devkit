# Review: Re-architect Red Hat Internal Browser MCP to helper-mcps (Revision 1)

**Reviewed:** 2026-02-24
**Plan file:** `./plans/redhat-browser-mcp-v2.md`
**Reviewer:** code-reviewer (claude-devkit)
**Revision round:** 1 (previous review: 2026-02-24)
**Verdict:** FAIL

---

## Summary

This is revision round 1. The previous review identified 3 required edits. None of the 3 have been addressed -- the plan file appears unchanged from the prior review. The plan itself remains architecturally sound, but the required edits must be applied before it can pass.

---

## Previous Required Edits -- Status

### 1. Confirm read-only invariant -- NOT ADDRESSED

**Previous requirement:** Add an explicit statement in Context or Goals confirming the server is read-only per the `helper-mcps` CLAUDE.md invariant (Security Constraints > Read-Only Invariant). Ensure Phase 10 item 4 specifies updating the CLAUDE.md opening description.

**Current state:** The Context section (lines 1-11) and Goals section (lines 14-25) contain no mention of the read-only invariant. Phase 10 item 4 (lines 554-557) says "Update project description" but does not specify that the opening sentence of `helper-mcps/CLAUDE.md` ("Read-only MCP servers for Jira, Google Workspace, and Gmail") must be updated to include Red Hat Browser.

### 2. Address non-root Docker user -- NOT ADDRESSED

**Previous requirement:** Add a `USER` directive to the Dockerfile in Phase 8, or document why Playwright requires root as a deviation from the `helper-mcps` CLAUDE.md rule (Security Constraints > Docker Security: "Non-root user in all containers").

**Current state:** The Dockerfile at lines 421-448 has no `RUN adduser` or `USER` directive. The Deviations table (lines 734-744) has no entry for non-root user.

### 3. Fix Assumption #5 (`_is_retryable` and httpx) -- NOT ADDRESSED

**Previous requirement:** Correct the factually incorrect description of when the `import httpx` triggers. Choose a fix strategy and update the text.

**Current state:** Assumption 5 (line 40) still reads: "This is acceptable because the function only triggers on actual httpx exceptions." The Risk Assessment table (line 601) still reads: "httpx is only imported inside the exception handler." Both statements are incorrect -- `import httpx` executes unconditionally in the `_is_retryable()` function body at `server_base.py:107`. If `httpx` is not installed, every call to `_is_retryable()` will raise `ModuleNotFoundError`, breaking `ToolError` wrapping for all exceptions.

---

## Conflicts with Project Rules

### helper-mcps CLAUDE.md Conflicts

- **Read-Only Invariant (Security Constraints > Read-Only Invariant).** The plan does not explicitly acknowledge that the server conforms to the read-only invariant. The `helper-mcps` CLAUDE.md states: "All MCP servers are strictly read-only -- they never create, update, or delete resources in external services." The redhat-browser-mcp is read-only in practice but this must be stated explicitly.

- **Docker Security > Non-root user (Security Constraints > Docker Security).** The Dockerfile in Phase 8 does not include a non-root user. The `helper-mcps` CLAUDE.md mandates: "Non-root user in all containers."

- **`_is_retryable()` httpx coupling (Shared Library > server_base.py).** The plan's Assumption #5 and Risk Assessment contain incorrect descriptions of the `_is_retryable()` behavior. The `import httpx` at the top of the function body is unconditional and will raise `ModuleNotFoundError` when httpx is not installed, preventing ToolError wrapping from working.

### claude-devkit CLAUDE.md Conflicts

- **No conflicts.** Same assessment as previous review. Phase 11 correctly handles removal of `mcp-servers/` references.

---

## Historical Alignment

- **No new issues.** The Context Alignment section (lines 708-744) remains thorough. Prior plan citations are accurate. No contradictions with prior plans or review decisions.

---

## Required Edits (3)

These are the same 3 edits from the previous review, restated for clarity.

1. **Confirm read-only invariant.** Add a sentence to the Goals or Context section: "The server is strictly read-only -- it fetches and returns page content but never creates, updates, or deletes external resources, conforming to the helper-mcps read-only invariant." In Phase 10 item 4, add explicit text: "Update the CLAUDE.md opening description from 'Read-only MCP servers for Jira, Google Workspace, and Gmail' to include Red Hat Browser."

2. **Address non-root Docker user.** Either:
   - (a) Add `RUN adduser --disabled-password --no-create-home appuser` and `USER appuser` to the Dockerfile in Phase 8, plus `RUN chown -R appuser /app` before the USER directive, OR
   - (b) Add a row to the Deviations table: "Runs as root in container | Playwright Chromium requires root for sandboxing; running as non-root requires `--no-sandbox` flag which weakens Chromium's security model. Root in a read-only container with no network egress beyond Playwright is acceptable."
   Choose whichever is accurate for the target Playwright version.

3. **Fix Assumption #5 and Risk Assessment row 3.** The `import httpx` in `_is_retryable()` is unconditional -- it is not inside an exception handler or guarded by a try/except. Update the assumption text to acknowledge this. Recommended fix: add `httpx` to `redhat-browser-mcp/requirements.txt` (simplest, one-line change), or plan a one-line `try/except ImportError` wrapper in `server_base.py` as part of Phase 10. Update the Risk Assessment row to match the chosen strategy.

---

## Optional Suggestions

- **Data Classification warning.** The original plan (`redhat-internal-browser-mcp.md`) had a prominent "Data Classification and Acceptable Use" section. Consider referencing it or adding equivalent text to Phase 6 tool descriptions or Phase 10 CLAUDE.md updates.

- **File permissions for storageState.** Phase 1, item 1 claims the provider will "verify file permissions (0o600) matching PATCredentialProvider security pattern," but `PATCredentialProvider` in `shared/auth.py` does not actually check permissions. Either remove this claim or implement it as a genuine new feature.

- **Integration test marker.** Phase 9 references `@pytest.mark.integration` but this marker is not registered in `pyproject.toml`. Add it under `[tool.pytest.ini_options] markers` to avoid pytest warnings.

- **Playwright version pinning.** `requirements.txt` specifies `playwright>=1.40.0` (minimum only). Given storageState format sensitivity, consider pinning to a specific version.

---

## What Went Well

- The plan's overall architecture is strong and well-aligned with monorepo conventions.
- Phased implementation with 12 clearly scoped phases and validation steps at each phase.
- Comprehensive file manifest (16 files to create, 6 to modify, 1 directory to delete).
- Deviations from monorepo patterns are documented with justifications.
- Prior plans properly cited with relationship descriptions.
- The auth pattern decision (`get_headers()` raising `AuthenticationError`) is well-reasoned.

---

## Verdict: FAIL

The plan has not been revised since the previous review. All 3 required edits remain unaddressed. None require architectural changes -- they are minor text additions and corrections. Apply the 3 edits and resubmit for review.
