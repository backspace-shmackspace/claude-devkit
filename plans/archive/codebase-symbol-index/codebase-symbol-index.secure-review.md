# Secure Review Summary — changes — 2026-05-25T12-45-00

## Verdict
PASS_WITH_NOTES

## Critical Findings
Count: 0

(None)

## High Findings
Count: 2

### H-01: Missing venv ownership verification before re-exec (Spoofing)
- **Scan source:** Vulnerability scan
- **File:** `scripts/codebase-scanner.py` (entire file -- mitigation absent)
- **Severity:** High
- **Description:** The STRIDE threat model requires verifying venv ownership via `os.stat().st_uid == os.getuid()` before importing from or re-executing within the scanner venv. The codebase-scanner.py does not perform any ownership check on the venv directory (`~/.claude-devkit/scanner-venv/`) before importing tree-sitter modules from it. A local attacker who can write to `~/.claude-devkit/scanner-venv/` could plant a malicious `tree_sitter_python` (or similar) package that gets loaded via `__import__()` at line 750. The `__import__(pkg)` call on line 750 in `_init_languages()` loads whatever is installed in the venv -- if venv ownership/permissions have been tampered with, this is a code execution vector.
- **CWE:** CWE-426 (Untrusted Search Path)
- **OWASP:** A08:2021 Software and Data Integrity Failures
- **Recommendation:** Before calling `__import__()` for tree-sitter grammar packages, verify that `~/.claude-devkit/scanner-venv/` is owned by the current user (`os.stat(venv_path).st_uid == os.getuid()`) and has mode 0700. Skip tree-sitter and fall back to regex if the check fails.

### H-02: Missing audit trail / repudiation controls (Repudiation)
- **Scan source:** Vulnerability scan
- **File:** `scripts/codebase-scanner.py` (entire file -- mitigation absent)
- **Severity:** High
- **Description:** The STRIDE threat model requires logging a `scanner_invocation` event via `emit-audit-event.sh` containing scanner version, parser mode, file count, symbol count, and output SHA-256. No such audit logging is implemented anywhere in the scanner. The script has zero calls to `emit-audit-event.sh` or any other audit mechanism. Without an audit trail, there is no way to verify what the scanner produced or when it ran, creating a repudiation gap in the security chain.
- **CWE:** CWE-778 (Insufficient Logging)
- **Recommendation:** After scanning completes (around line 1354 in `Scanner.scan()` or in `main()` after output), invoke `emit-audit-event.sh` with event type `scanner_invocation` containing: scanner version, parser mode, file count, symbol count, and SHA-256 of the output string.

## Medium Findings
Count: 3

### M-01: Absolute project_root path leaked in JSON output (Information Disclosure)
- **Scan source:** Data flow scan
- **File:** `scripts/codebase-scanner.py:1087`
- **Severity:** Medium
- **Description:** The STRIDE threat model requires "relative paths only, no file content in summary mode" to prevent secrets-in-paths disclosure. The summary mode correctly uses only relative paths. However, the JSON output format (`format_json()` at line 1087) emits `"project_root": index.project_root` which is the full absolute path (e.g., `/home/user/secret-project/`). This absolute path is also stored in the cache file. While JSON mode is not the default, the absolute path could reveal username, directory structure, or project names that should remain private when the output is consumed by an LLM or stored in artifacts.
- **CWE:** CWE-200 (Exposure of Sensitive Information)
- **Recommendation:** In JSON output, either omit `project_root` entirely or replace it with a relative path or placeholder. The cache file can retain the absolute path internally since it is user-local and permission-protected (mode 0700).

### M-02: HMAC secret derived from guessable inputs (Tampering -- weakened mitigation)
- **Scan source:** Vulnerability scan
- **File:** `scripts/codebase-scanner.py:934-941`
- **Severity:** Medium
- **Description:** The HMAC secret is derived from `USER`, `HOME`, and a hash of the project root -- all of which are easily guessable or observable by any process running as the same user. While the HMAC still prevents *accidental* corruption and cross-user tampering, it does not protect against a deliberate local attacker who can read environment variables (`$USER`, `$HOME`) and compute the project hash. The fallback to `b"claude-devkit-default-secret"` on line 942 is even weaker. The threat model specifies "HMAC-SHA256 integrity" for cache files; this implementation meets the letter but the key derivation is weaker than expected for an integrity control.
- **CWE:** CWE-330 (Use of Insufficiently Random Values)
- **Note:** This is acceptable for the threat model's intent (preventing cache poisoning from *other users* or *accidental corruption*) since the cache directory is mode 0700. However, it would not withstand an attacker who has code execution as the same user. For the stated use case, this is adequate.

### M-03: TOCTOU gap between symlink check and file open (Information Disclosure)
- **Scan source:** Vulnerability scan
- **File:** `scripts/codebase-scanner.py:243-307`
- **Severity:** Medium
- **Description:** The symlink check at line 243 (`os.path.islink()`) and the path canonicalization at line 250 (`os.path.realpath()`) happen before the file is opened for reading at line 307. A race condition exists where a regular file could be replaced with a symlink pointing outside the project root between the check and the open. This is a classic TOCTOU (Time-of-Check-Time-of-Use) vulnerability. In practice, exploitation requires the attacker to have write access to the project directory and win a race, making this a low-probability attack.
- **CWE:** CWE-367 (Time-of-Check Time-of-Use)
- **Recommendation:** Re-verify the file descriptor after opening (e.g., `os.fstat(fd)` to check inode matches expected, or open with `O_NOFOLLOW`). Alternatively, accept this risk given the threat model's assumption that the project directory is under user control.

## Low Findings
Count: 3

### L-01: install.sh venv creation always succeeds due to `|| true`
- **Scan source:** Vulnerability scan
- **File:** `scripts/install.sh:147`
- **Severity:** Low
- **Description:** The venv creation command `$PYTHON_CMD -m venv "$SCANNER_VENV" 2>/dev/null || true` will always exit 0 due to `|| true`, making the `else` branch (line 154-156) unreachable. If venv creation partially fails (e.g., creates directory but not `bin/pip`), the inner check at line 148 handles this, so the impact is cosmetic/logging only.
- **Recommendation:** Remove `|| true` and let the `if` statement naturally handle the exit code.

### L-02: Regex patterns could match inside string literals or comments
- **Scan source:** Vulnerability scan
- **File:** `scripts/codebase-scanner.py:347-394`
- **Severity:** Low
- **Description:** The regex fallback parser uses `re.MULTILINE` patterns that match on any line, including inside string literals, docstrings, and comments. This could produce false positive symbols (e.g., a docstring containing `def example_function():` would be extracted as a real function). This is not a security issue per se, but could inject misleading symbol data into the index that gets consumed by an LLM.
- **Impact:** Low -- the scanner is a code index tool, not a security enforcement tool. False positives in symbol extraction are a quality issue, not a security issue.

### L-03: uninstall.sh uses `rm -rf` on user-controlled paths
- **Scan source:** Data flow scan
- **File:** `scripts/uninstall.sh:79-80`
- **Severity:** Low
- **Description:** The uninstall script runs `rm -rf "$HOME/.claude-devkit/scanner-venv"` and `rm -rf "$HOME/.claude-devkit/cache"`. These paths are derived from `$HOME` which is user-controlled. In a scenario where `$HOME` is manipulated (e.g., via environment variable override before running the script), this could delete unexpected directories. The risk is extremely low since: (a) the user explicitly invokes uninstall.sh, (b) `$HOME` manipulation would require the user to have already compromised their own environment.
- **Recommendation:** Acceptable as-is. The paths are well-scoped and the script is interactive.

## Risk Score
4/10

Assessment: The scanner implements most security controls correctly. Path traversal prevention, symlink rejection, null byte handling, DoS limits, and cache integrity are all present and functional. Two high-severity gaps exist: the missing venv ownership verification (H-01) and the missing audit trail (H-02). Both are specified in the threat model but not implemented. Neither creates an immediately exploitable vulnerability in normal usage, but they represent unmet security requirements from the plan.

## Action Items

1. **[H-01]** Add venv ownership verification (`os.stat().st_uid == os.getuid()`) before tree-sitter imports in `_init_languages()`. Fall back to regex if check fails.
2. **[H-02]** Add `scanner_invocation` audit event emission via `emit-audit-event.sh` after scan completion. Include version, parser mode, file count, symbol count, output SHA-256.
3. **[M-01]** Remove or redact absolute `project_root` from JSON output format. Keep relative paths only in user-facing output.
4. **[M-02]** Acknowledged -- HMAC derivation is acceptable for stated threat model (same-user cache integrity with mode 0700 directory protection).
5. **[M-03]** Acknowledged -- TOCTOU gap is low-probability given project directory is user-controlled. Consider `O_NOFOLLOW` for defense-in-depth.

## Scan Coverage
- Scope: changes (uncommitted modifications)
- Files reviewed: `scripts/codebase-scanner.py` (1790 lines, NEW), `configs/scanner-languages.json` (46 lines, NEW), `scripts/install.sh` (modified, +27 lines), `scripts/uninstall.sh` (modified, +7 lines)
- Vulnerability scan: Inline (this report)
- Data flow scan: Inline (this report)
- Auth/authz scan: Not applicable (no authentication/authorization logic in scope)
- Security-analyst agent: not found

## Threat Model Coverage

| STRIDE Category | Plan-Identified Threat | Implementation Status | Evidence |
|----------------|----------------------|---------------------|----------|
| Tampering | Malicious filenames cause path traversal | IMPLEMENTED | `codebase-scanner.py:250` (`os.path.realpath()`), `:255` (reject outside project root), `:260` (reject null bytes) |
| Spoofing | Scanner/venv replaced with malicious copy | NOT_IMPLEMENTED | No `os.stat().st_uid == os.getuid()` check exists anywhere in the codebase. `install.sh:135` sets `chmod 700` on the parent directory but the scanner never verifies ownership at runtime. |
| Repudiation | No audit trail of scanner invocations | NOT_IMPLEMENTED | No calls to `emit-audit-event.sh` or any audit logging mechanism found in `codebase-scanner.py`. No `scanner_invocation` event type emitted. |
| Information Disclosure | Symlink escape leaks file content outside project | IMPLEMENTED | `codebase-scanner.py:243` (`os.path.islink()` check before any file operation), `:255` (path canonicalization rejects paths outside project root) |
| Denial of Service | Parser crash on malformed input | IMPLEMENTED | `codebase-scanner.py:766-789` (`signal.alarm(5)` per-file timeout), `:812-815` (try/except with regex fallback on timeout/error), tree-sitter is memory-safe parser |
| Denial of Service | Oversized project exhausts resources | IMPLEMENTED | `codebase-scanner.py:189` (`max_files=500` default), `:190` (`max_file_size=200_000` default), `:236-238` (file count enforcement), `:295-298` (size enforcement) |
| Tampering | Cache poisoning with modified index data | IMPLEMENTED | `codebase-scanner.py:944-945` (HMAC-SHA256 via `hmac.new()`), `:981` (schema version check), `:988-991` (HMAC verification with `hmac.compare_digest()`), `:1023` (`os.makedirs(mode=0o700)`), `:1054-1058` (atomic write via `tempfile.mkstemp()` + `os.replace()`) |
| Elevation of Privilege | Output injection via crafted symbol names | IMPLEMENTED | `codebase-scanner.py:163-169` (`sanitize_symbol()`: strips non-printable chars via `isprintable()`, removes disallowed chars via regex, hard cap at 200 chars). Applied to all symbol extraction (lines 446, 464, 482, 493, 527, 542, 556, 570, 585, 621, 635, 662, 680) |
| Information Disclosure | Secrets in file paths exposed in output | PARTIALLY_IMPLEMENTED | Summary mode uses relative paths only (correct). JSON mode (`codebase-scanner.py:1087`) exposes absolute `project_root` path. Cache file also stores absolute path. |
| Tampering | Malicious PyPI package in venv | PARTIALLY_IMPLEMENTED | `install.sh:138-144` pins versions with ranges (e.g., `tree-sitter>=0.25.0,<0.26`). `install.sh:135` sets `chmod 700` on `~/.claude-devkit/`. However: (a) no integrity hashes (`--hash`) in requirements, (b) no runtime ownership verification of venv in scanner (see H-01). |

**Coverage Summary:**
- Threats addressed: 6/10
- Threats partially addressed: 2/10
- Threats not addressed: 2/10
- Not applicable: 0/10

## Redaction Notice
All secret values in findings have been redacted (first 4 / last 4 characters shown).
Actual values are never included in security reports. No secrets were detected in the reviewed files.
