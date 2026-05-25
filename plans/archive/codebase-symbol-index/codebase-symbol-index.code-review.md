# Code Review: Codebase Symbol Index (Revision Round 2)

**Plan:** `plans/codebase-symbol-index.md` (v1.1, APPROVED)
**Reviewer:** code-reviewer agent
**Date:** 2026-05-25
**Scope:** 8 files (2 new, 6 modified) — post-revision verification
**Prior review:** Previous REVISION_NEEDED verdict with 3 Critical and 4 Major findings

---

## Code Review Summary

The revision round has successfully addressed all six blocking findings from the previous review. The `parser_mode` field is now honest (`"tree-sitter-partial"` when Python-only tree-sitter extraction is active, `"regex-fallback"` otherwise). Both skills now emit `scanner_invocation` audit events. `install.sh` now exports `CLAUDE_DEVKIT`. `/ship` Step 4 now computes and passes import graph data to the code reviewer. The `|| true` in the venv creation `if` condition has been fixed. Tests 32 and 35 now use the correct cleanup pattern. One pre-existing minor finding (M-04, stale `skill_version` in ship state file) remains unresolved but was explicitly flagged in the prior review as pre-existing.

---

## Previous Findings Status

### C-01 — TreeSitterParser `parser_mode` accuracy

**Status: FIXED**

The `Scanner.__init__` method (lines 1356–1371) now implements a three-tier `parser_mode` with accurate semantics:
- `"tree-sitter-partial"` — set when Python grammar is loaded and extracted via QueryCursor (Python is the only language with real tree-sitter extraction).
- `"regex-fallback"` — set when tree-sitter is available but Python grammar is not loaded, or when tree-sitter is not importable at all.

The `_extract_python` method (lines 853–939) is a genuine tree-sitter implementation using the QueryCursor API with pattern matching over the AST. The `_extract_typescript`, `_extract_java`, and `_extract_go` methods delegate to the regex fallback with comments explaining that grammar API variance justifies this choice. The mode string honestly reflects that only Python gets AST-based extraction.

The `CodebaseIndex` dataclass comment on line 73 (`parser_mode: str   # "tree-sitter" | "tree-sitter-partial" | "regex-fallback"`) matches the actual possible values.

**Note:** The `"tree-sitter"` (full, all-languages) mode is documented as future state. This is an acceptable and honest approach.

---

### C-02 — `scanner_invocation` audit events missing from both skills

**Status: FIXED**

Both `/architect` Step 1 (lines 127–136) and `/ship` Step 1 (lines 345–354) now emit `scanner_invocation` audit events. The implementation is consistent across both skills:

```bash
if [ -n "$SCANNER_OUTPUT" ]; then
  SCANNER_HASH=$(printf '%s' "$SCANNER_OUTPUT" | python3 -c "import sys,hashlib; print(hashlib.sha256(sys.stdin.read().encode()).hexdigest())" 2>/dev/null || echo "unknown")
  SCANNER_VERSION=$(python3 "$SCANNER_SCRIPT" --version 2>/dev/null | awk '{print $NF}' || echo "unknown")
  ...
  bash scripts/emit-audit-event.sh ".$STATE_FILE" \
    "{\"event_type\":\"scanner_invocation\",...,\"output_sha256\":\"${SCANNER_HASH}\"}"
fi
```

The event includes scanner version, parser mode, file count, symbol count, and SHA-256 hash of the output — all fields specified by the plan's Security Requirements (Repudiation control). The conditional `[ -n "$SCANNER_OUTPUT" ]` is correct: the event is only emitted when scanner output is non-empty, which avoids logging useless "scanner not available" events.

**Minor note:** The `SCANNER_FILE_COUNT` and `SCANNER_SYMBOL_COUNT` extractions use `grep -oP` patterns (`'Files scanned:\s*\K[0-9]+'` and `'Total symbols:\s*\K[0-9]+'`) that do not match the actual summary output format. The scanner summary header reads `Files: N | Symbols: N`, not `Files scanned: N`. These fields will resolve to `"unknown"` in practice. This is a Minor finding (the hash is still correct; the counts are informational).

---

### C-03 — `install.sh` does not export `CLAUDE_DEVKIT`

**Status: FIXED**

`scripts/install.sh` line 114 now includes `export CLAUDE_DEVKIT="$REPO_DIR"` in the shell config block written to the user's RC file:

```bash
cat >> "$RC_FILE" << EOF
# claude-devkit PATH
export CLAUDE_DEVKIT="$REPO_DIR"
export PATH="\$PATH:$GENERATORS_DIR"
...
EOF
```

This resolves the silent-empty-output failure for user projects outside the claude-devkit repo root. The `${CLAUDE_DEVKIT:-./}` fallback in the skills' Bash blocks will now correctly expand to the repo path for any Claude Code session sourcing the user's RC file.

---

### M-01 — `/ship` Step 4 missing import graph data

**Status: FIXED**

`/ship` Step 4 now has a pre-step Bash block (before the parallel task dispatch) that:
1. Gets the list of changed files via `git diff --name-only HEAD`.
2. Runs the scanner in `--format json` mode.
3. Parses the JSON output using inline Python to extract import edges where `source_file` is in the changed files set.
4. Formats the result as a markdown table: `| Source File | Imports | Kind |`.
5. Retains `$IMPORT_GRAPH_DATA` in coordinator context.

The Step 4a code reviewer prompt explicitly includes this data under the heading `**Import graph (blast radius):**`. Acceptance criterion #9 ("Step 4 receives import graph data (not caller data) for blast radius assessment") is met.

**Observation:** The import graph extraction uses environment variable injection (`SCANNER_JSON_VAR` and `CHANGED_FILES_VAR`) rather than shell string interpolation into the inline Python string — this is the correct pattern for large JSON payloads and avoids quoting issues.

---

### M-02 — `install.sh` venv creation unreachable `else` branch

**Status: FIXED**

The venv creation block (lines 149–158) now correctly gates the `else` branch:

```bash
if $PYTHON_CMD -m venv "$SCANNER_VENV" 2>/dev/null; then
    if [ -f "$SCANNER_VENV/bin/pip" ]; then
        "$SCANNER_VENV/bin/pip" install --quiet -r "$SCANNER_REQS" 2>/dev/null || true
        echo "✅ Scanner venv created at $SCANNER_VENV (tree-sitter mode enabled)"
    else
        echo "⚠️  Scanner venv created but pip not found. Scanner will use regex fallback."
    fi
else
    echo "⚠️  Could not create scanner venv. Scanner will use regex fallback."
fi
```

The `|| true` has been removed from the `if` condition. The `else` branch is now reachable when `python3 -m venv` returns a non-zero exit code. The inner `if [ -f "$SCANNER_VENV/bin/pip" ]` handles the case where the venv was created but pip is missing (e.g., `--without-pip` venv creation on some platforms). The pip install itself still uses `|| true` to prevent install failures from blocking the overall install.

---

### M-03 — Tests 32 and 35 false-pass patterns

**Status: FIXED**

**Test 32** (line 444–446):
```bash
"mkdir -p /tmp/scanner-test-empty && python3 '$REPO_DIR/scripts/codebase-scanner.py' --format summary --quiet /tmp/scanner-test-empty; STATUS=\$?; rm -rf /tmp/scanner-test-empty 2>/dev/null || true; exit \$STATUS"
```
The `;` separates the scanner invocation from the cleanup. `$STATUS` captures the scanner's exit code independently. The `|| true` now only applies to the `rm -rf` cleanup, not the scanner invocation. If the scanner exits non-zero, `STATUS` is non-zero and `exit $STATUS` fails the test correctly. This is exactly the pattern recommended in the previous review.

**Test 35** (line 456–458):
```bash
"mkdir -p /tmp/scanner-symlink-test && ln -sf /etc/passwd /tmp/scanner-symlink-test/escape.py && python3 '$REPO_DIR/scripts/codebase-scanner.py' --format json --quiet /tmp/scanner-symlink-test | python3 -c 'import json,sys; d=json.load(sys.stdin); fc=d[\"file_count\"]; assert fc==0, f\"Expected 0 files, got {fc}\"; print(\"PASS\")'; STATUS=\$?; rm -rf /tmp/scanner-symlink-test 2>/dev/null || true; exit \$STATUS"
```
Same pattern. `STATUS` captures the exit code of the pipeline (python3 assertion), not the cleanup. The `|| true` only guards the cleanup. If the python3 assertion fails (`assert fc==0`), `STATUS` is non-zero and the test fails correctly.

---

### M-04 — `skill_version` stale in ship state file (3.7.0 vs 3.8.0)

**Status: NOT_FIXED** (pre-existing, acceptable)

`skills/ship/SKILL.md` line 102 still hardcodes `'skill_version': '3.7.0'` in the state file creation block. The frontmatter declares `version: 3.8.0`. This was explicitly flagged as a pre-existing issue in the previous review and not in the revision scope. It remains a Minor finding on next contact with the ship skill.

---

## New Findings

### N-01 — `SCANNER_FILE_COUNT` and `SCANNER_SYMBOL_COUNT` regex patterns don't match actual output format [Minor]

**Location:** `skills/architect/SKILL.md` lines 131–132; `skills/ship/SKILL.md` lines 349–350

The patterns used to extract these values are:
```bash
SCANNER_FILE_COUNT=$(printf '%s' "$SCANNER_OUTPUT" | grep -oP 'Files scanned:\s*\K[0-9]+' 2>/dev/null || echo "unknown")
SCANNER_SYMBOL_COUNT=$(printf '%s' "$SCANNER_OUTPUT" | grep -oP 'Total symbols:\s*\K[0-9]+' 2>/dev/null || echo "unknown")
```

The scanner's actual summary header format is:
```
Parser: tree-sitter-partial | Languages: python(N) | Files: N | Symbols: N
```

The patterns match `Files scanned:` and `Total symbols:` which do not appear in the output. In practice, both values resolve to `"unknown"` in the `scanner_invocation` audit event. The `SCANNER_PARSER_MODE` extraction (`'Parser:\s*\K\S+'`) does match correctly.

**Impact:** Low — the SHA-256 hash (the primary audit control) is correct. The file/symbol counts in the audit event are informational only. No functional regression.

**Fix (minor):** Update patterns to match actual output:
```bash
SCANNER_FILE_COUNT=$(printf '%s' "$SCANNER_OUTPUT" | grep -oP 'Files:\s*\K[0-9]+' 2>/dev/null || echo "unknown")
SCANNER_SYMBOL_COUNT=$(printf '%s' "$SCANNER_OUTPUT" | grep -oP 'Symbols:\s*\K[0-9]+' 2>/dev/null || echo "unknown")
```

---

### N-02 — `_extract_python` falls back to regex when query returns no symbols AND no imports [Minor — logic gap]

**Location:** `scripts/codebase-scanner.py`, lines 935–938

```python
# If we got no symbols at all from tree-sitter queries, fall back to regex for this file
if not symbols and not imports:
    return self._regex_fallback._parse_python(rel_path, content)
```

This fallback fires for Python files with no top-level functions, classes, or imports — e.g., `__init__.py` with only `__all__ = [...]`, pure constants files, or stub files. For these files, tree-sitter correctly returns empty results but the code treats it as a query failure and runs regex, which also returns empty results. The double-parse is harmless but creates unnecessary overhead for empty/stub files.

More importantly: a Python file that is genuinely empty of parseable symbols will still be processed twice. The `parser_mode` header will still say `"tree-sitter-partial"` even though some files effectively ran in `"regex-fallback"` mode.

**Fix:** Change the fallback condition to only trigger on genuine query failures, not empty results:

```python
# Symbol+import extraction succeeded (possibly empty results for stub/init files)
return symbols, imports
```

The existing fallback inside `try/except` (line 897–899) handles actual API failures.

---

### N-03 — Test count in header comment is accurate [Positive confirmation]

The test-integration.sh header comment says "37 tests" (line 14). Numbered tests run 1–37 via `run_test()`, plus one manual Test 9 cleanup step. The CLAUDE.md scripts section says "37 tests" and also "codebase-scanner integration tests (8 tests)". Tests 30–37 are the 8 scanner tests. Counts are consistent.

---

## Positives

- **`parser_mode` is now trustworthy.** The `"tree-sitter-partial"` value accurately communicates that only Python extraction uses tree-sitter AST. Agents receiving scanner output can reason correctly about fidelity level.

- **Python tree-sitter extraction is substantive.** `_extract_python` implements the QueryCursor API for both function/class extraction and import extraction, with appropriate exception handling and a genuine regex fallback for QueryCursor failures. The query strings use correct tree-sitter pattern syntax.

- **Audit event design is robust.** The `scanner_invocation` event captures the SHA-256 hash of the output — not just metadata. This is the right implementation of the repudiation control: the hash allows post-hoc verification that the scanner output injected into agent context matches what was logged.

- **Import graph for blast radius is cleanly implemented.** The Step 4 pre-step uses environment variable injection for the JSON payload rather than shell string interpolation, avoiding quoting issues with large JSON strings. The Python inline script handles exceptions gracefully and produces a clear "Import graph unavailable" fallback.

- **`install.sh` venv creation error handling is correct.** The `else` branch is now reachable. The inner `if [ -f pip ]` check handles the pip-absent case separately. The pattern is: venv creation failure → informative warning → scanner degrades to regex. This matches the plan's graceful degradation requirement.

- **`uninstall.sh` scanner cleanup is correct.** Lines 78–81 remove the venv, cache, and the `~/.claude-devkit/` directory (with `rmdir` that only succeeds if empty — correct behavior if other artifacts exist).

- **CLAUDE.md documentation is complete.** Scanner appears in: Scripts table (line 922), Configs section (line 909), Data Flow diagram (line 90), test count (line 931), and Troubleshooting section (lines 1154–1167). Roadmap placement is also present. The plan's Phase 5 documentation requirements are met.

- **Test 33 assertion is an improvement over the plan's template.** The plan suggested `assert d["file_count"]<=3` but the actual test (line 449) uses `fc=d["file_count"]; assert fc<=3, f"Expected <=3 files, got {fc}"` — the `f-string` diagnostic message makes test failures actionable.

---

## Verdict: PASS

All Critical and Major findings from the previous review have been resolved:

| Finding | Status |
|---------|--------|
| C-01: `parser_mode` accuracy | FIXED |
| C-02: `scanner_invocation` audit events | FIXED |
| C-03: `install.sh` missing `export CLAUDE_DEVKIT` | FIXED |
| M-01: `/ship` Step 4 import graph data | FIXED |
| M-02: `install.sh` unreachable `else` branch | FIXED |
| M-03: Tests 32 and 35 false-pass patterns | FIXED |

Remaining items are Minor or pre-existing:
- **M-04** (pre-existing, not in revision scope): `skill_version` stale in ship state file
- **N-01** (new, Minor): `SCANNER_FILE_COUNT`/`SCANNER_SYMBOL_COUNT` regex patterns don't match actual summary format — counts log as "unknown" but hash is correct
- **N-02** (new, Minor): Double-parse on empty Python files due to `if not symbols and not imports` fallback condition

Neither N-01 nor N-02 is a correctness issue for the feature's primary goal. The implementation can ship.
