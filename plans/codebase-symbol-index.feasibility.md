# Feasibility Re-Review: Codebase Symbol Index (v1.1)

**Reviewer:** Code Reviewer Agent
**Date:** 2026-05-25
**Plan:** `plans/codebase-symbol-index.md` (v1.1, revised)
**Previous Review:** 2026-05-25 (v1.0)
**Verdict:** PASS

---

## Summary

The revised plan addresses all five original findings. C-01 (tree-sitter API) and C-02 (caller detection) are fully resolved. M-01 (venv activation) is fully resolved. M-02 (effort estimate) is resolved -- the revised estimate is now slightly generous rather than optimistic, which is the safer direction. M-03 (deploy.sh integration) is partially resolved: the plan correctly avoids modifying `deploy.sh`, but its claim that `install.sh` sets `$CLAUDE_DEVKIT` is factually incorrect -- `install.sh` does not export that variable. This is a new concern (N-01 below) that must be fixed but does not change the verdict.

The revision also incorporated findings from the red team and librarian reviews (F-01 through F-06, R-01 through R-04, SA-S through SA-V). The plan is materially improved and ready for implementation with one required fix.

---

## Original Findings Resolution

### C-01: tree-sitter 0.25 API incompatibility -- RESOLVED

The plan now pins `tree-sitter>=0.25.0,<0.26` (line 94, line 596) and all code examples use the correct `QueryCursor` API chain: `Query(language, pattern)` then `QueryCursor(query).matches(root_node)` (lines 631-638). The revision log entry correctly describes the fix.

Verified: tree-sitter is not installed system-wide on this machine (Python 3.14), confirming that the regex fallback path will activate for the default case. The API examples in the plan match the 0.25+ documentation.

### C-02: Caller detection false positives -- RESOLVED

Caller detection is cleanly deferred to v2. The revision removes `CallerEntry` from the data model (line 233), removes `callers{}` from `SymbolIndex`, removes "Call Hotspots" from the summary output, and adds caller detection to Non-Goals (line 87) and Future Evolution (lines 1035-1042). The import graph is retained as the v1 mechanism for blast radius assessment (lines 386-392), which provides accurate, false-positive-free structural data.

The deferral is the right call. The v2 options listed (scope-aware matching, SymbolDelta, import-path-qualified references) are reasonable paths forward.

### M-01: Venv activation via sys.path manipulation -- RESOLVED

The plan replaces `sys.path` manipulation with subprocess re-exec under the venv Python interpreter. The skill invocation blocks (lines 322-332) use `$SCANNER_PYTHON` to invoke the venv's Python directly. The scanner script itself has no venv awareness -- it just imports tree-sitter and catches `ImportError` for the regex fallback (lines 663-667). This is the standard pattern.

The plan also adds venv ownership verification (`os.stat().st_uid == os.getuid()`) before re-exec (lines 651-666), which is a security improvement beyond the original recommendation.

### M-02: Effort estimate -- RESOLVED

The original estimate was 3-5 days. The original review recommended 5-7 days. The revised plan estimates 7-9 days for implementation phases (1-5), plus 2-3 days for evaluation (Phase 6). The Phase 1 estimate moved from 2-3 to 3-4 days, and Phase 2 from 1-2 to 2-3 days. These are realistic. The addition of Phase 6 (measurement) adds further effort but is well-justified by the F-06 finding.

### M-03: deploy.sh integration path -- PARTIALLY RESOLVED (see N-01)

The plan correctly decides NOT to modify `deploy.sh` (line 167, R-01 resolution). It uses `$CLAUDE_DEVKIT/scripts/codebase-scanner.py` with a `./scripts/` local fallback. It adds an integration test for `$CLAUDE_DEVKIT` availability (lines 705-708).

However, the plan states that `$CLAUDE_DEVKIT` is "already set by `install.sh`" (line 169). This is factually incorrect -- see N-01 below.

---

## New Concerns

### N-01 (Major): `$CLAUDE_DEVKIT` env var is not set by `install.sh`

The plan states at line 169: "`$CLAUDE_DEVKIT` is already set by `install.sh` and is available in Claude Code's Bash tool environment."

I read `scripts/install.sh` (all 174 lines). It does NOT set `$CLAUDE_DEVKIT`. It sets:
- `PATH` to include `$REPO_DIR/generators`
- Aliases for `gen-skill`, `gen-agent`, `validate-skill`, etc.

The `$CLAUDE_DEVKIT` variable appears only in the **manual installation** section of `CLAUDE.md` (line 374: `export CLAUDE_DEVKIT="$HOME/projects/claude-devkit"`). It is not part of the automated installation path.

This means:
1. The scanner invocation in skills (`$CLAUDE_DEVKIT/scripts/codebase-scanner.py`) will resolve to `/scripts/codebase-scanner.py` (empty string + path) for any user who ran `install.sh` instead of manually editing their shell RC.
2. The local fallback (`./scripts/codebase-scanner.py`) will only work when running from the claude-devkit repo itself, not from other projects.
3. The integration test at line 706 (`test -n "$CLAUDE_DEVKIT"`) will fail for automated installations.

**Impact:** Scanner invocation will silently fail (empty output, treated as "scanner not available") for the majority of users.

**Required fix (pick one):**
- **(A)** Add `export CLAUDE_DEVKIT="$REPO_DIR"` to `install.sh` alongside the existing PATH export. This is the minimal fix and aligns `install.sh` with what CLAUDE.md documents.
- **(B)** Change the skill invocation to derive the scanner path from the generators PATH entry (which `install.sh` does set), e.g., `$(dirname $(which generate_skill.py))/../scripts/codebase-scanner.py`. This is fragile and not recommended.
- **(C)** Ship the scanner to `~/.claude-devkit/bin/codebase-scanner` during `install.sh` and reference it by absolute path. This is cleaner but changes the deployment model.

Option (A) is recommended. It is a one-line addition to `install.sh` and makes the plan's assumption correct.

### N-02 (Minor): HMAC key derivation has no entropy

The cache HMAC key is derived from `os.getlogin() + os.path.expanduser("~")` (line 153). On this machine, that produces `root/Users/imurphy` -- a string that is trivially guessable by any process running as the same user. Since the cache is already stored in a user-owned directory (`~/.claude-devkit/cache/`, mode 0700), the HMAC adds marginal security over filesystem permissions alone.

This is not a blocking issue because the threat model is cache tampering by a different user or process, and the mode 0700 directory permission is the primary control. But the plan should not imply that the HMAC provides meaningful protection beyond integrity detection for accidental corruption. If the plan intends the HMAC to defend against adversarial tampering, the key needs real entropy (e.g., a random key generated at install time and stored in `~/.claude-devkit/.hmac-key`).

**Recommendation:** Either (a) generate a random key during `install.sh` and store it in `~/.claude-devkit/.hmac-key`, or (b) document in the STRIDE table that the HMAC detects accidental corruption only, not adversarial tampering by a same-user attacker.

---

## Original Minor Suggestions Status

| ID | Finding | Status |
|----|---------|--------|
| m-01 | Content hash using first 4KB is insufficient | RESOLVED -- Phase 1 spec now says "SHA-256 of entire file content" (line 558). |
| m-02 | Missing `.gitignore`-awareness in file discovery | PARTIALLY ADDRESSED -- FileDiscovery spec says "gitignore-aware exclusions" (line 555) but does not specify the mechanism. The `git ls-files` recommendation was not adopted. Acceptable for v1 with hardcoded exclusions; can be improved later. |
| m-03 | `--format compact` mentioned but never defined | RESOLVED -- Removed from CLI interface. Only `summary` and `json` remain (line 285). |
| m-04 | Cache file location should be configurable per-project | RESOLVED BY DESIGN CHANGE -- Cache moved to `~/.claude-devkit/cache/<project-hash>/` (user-scoped). Per-project configuration is no longer needed since each project gets its own hash-namespaced directory. |
| m-05 | TypeScript query references `import_declaration` (Java node type) | RESOLVED -- TypeScript imports now correctly use `import_statement` (line 511). |

---

## What the Revision Did Well

1. **Clean scope reduction on caller detection (C-02).** Rather than attempting a partial fix, the plan removes caller detection entirely from v1 and provides a clear rationale. The import graph alone delivers the blast radius value.

2. **Comprehensive revision log.** The table at lines 13-31 maps every finding to a resolution with enough detail to verify without re-reading the original reviews.

3. **Phase 6 measurement gate (F-06).** Adding concrete success/marginal/fail thresholds (>=20% / 10-20% / <10% token reduction) turns a speculative benefit claim into a testable hypothesis. The rollback path for evaluation failure is well-defined.

4. **Cache relocation (F-03).** Moving the cache from project root to `~/.claude-devkit/cache/<project-hash>/` eliminates the trust boundary concern and the `.gitignore` maintenance burden.

5. **STRIDE completeness (SA-S, SA-R, SA-C, SA-V).** Adding Spoofing, Repudiation, and upgrading cache poisoning to Medium shows the security analysis is being treated as a living document rather than a checkbox.

---

## Recommendations

1. **[N-01, REQUIRED] Fix `$CLAUDE_DEVKIT` in `install.sh`.** Add `export CLAUDE_DEVKIT="$REPO_DIR"` to the automated installation. Without this, the scanner invocation will silently fail for all users who used automated installation. This is a one-line fix in `install.sh` (Phase 2, step 2) and should also be noted in Phase 5 documentation.

2. **[N-02, SUGGESTED] Strengthen or de-scope HMAC key derivation.** Either generate a random key at install time or document that the HMAC is for corruption detection only.

3. **[m-02, OPTIONAL] Consider `git ls-files` for file discovery.** The "gitignore-aware exclusions" claim in the FileDiscovery spec is vague. If the implementation uses hardcoded exclusions only, the spec should say so explicitly rather than implying `.gitignore` parsing.

---

## Verdict: PASS

All critical and major findings from the original review are resolved. The one new concern (N-01: `$CLAUDE_DEVKIT` not set by `install.sh`) is a real bug that will cause silent failure, but it is a one-line fix in `install.sh` that the implementer can address in Phase 2 without any architectural change to the plan.

The plan should proceed to implementation. The implementer should fix N-01 before or during Phase 2.
