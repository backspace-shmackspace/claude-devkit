# Plan: Codebase Symbol Index

**Status:** APPROVED
**Author:** Senior Architect Agent
**Date:** 2026-05-25
**Version:** 1.1
**Revision:** 2026-05-25 -- Addresses review findings

---

## Revision Log

| ID | Source | Severity | Finding | Resolution |
|----|--------|----------|---------|------------|
| C-01 | Feasibility | Critical | tree-sitter 0.25 API breaking change (`Query.matches()` moved to `QueryCursor.matches()`) | Pinned `tree-sitter>=0.25.0`. Replaced all API examples with `QueryCursor` pattern. |
| C-02 | Feasibility | Critical | Caller detection via string matching produces false positives on common names | Deferred caller detection to v2. v1 ships import graph only for blast radius. Removed `CallerEntry` from data model, `callers{}` from `SymbolIndex`, and "Call Hotspots" from summary output. |
| F-01 | Red Team | Major | 30-50% token savings claim is unsubstantiated | Replaced with qualified language ("estimated"). Added measurement methodology to Phase 6 evaluation gate. |
| F-02 | Red Team | Major | `sys.path` manipulation for venv is fragile/insecure | Replaced with subprocess re-exec under venv Python. Scanner script has no venv awareness; `ImportError` triggers regex fallback. |
| F-03 | Red Team | Major | Cache file in project root is trust boundary violation | Relocated default cache to `~/.claude-devkit/cache/<project-hash>/index.json`. Added content-integrity HMAC on write/read. Raised cache poisoning to Medium in STRIDE. |
| F-04 | Red Team | Major | No hard output size cap for summary mode | Added explicit `--max-tokens` flag (default 4000). Summary formatter enforces truncation with deterministic top-N strategy. |
| F-05 | Red Team | Major | Caller detection false positives | Resolved by C-02 deferral. |
| F-06 | Red Team | Major | No measurement gate in rollout plan | Added Phase 6: Measurement and Evaluation (Days 10-14) with success/fail thresholds. |
| R-01 | Librarian | FAIL | `deploy.sh` scope ambiguity | Resolved: scanner is invoked via `$CLAUDE_DEVKIT/scripts/codebase-scanner.py` with `./scripts/` local fallback. `deploy.sh` is NOT modified. Removed from "Files to Modify" table. |
| R-02 | Librarian | FAIL | Missing roadmap placement | Added as v1.1 roadmap item. Phase 5 adds it before marking complete. |
| R-03 | Librarian | FAIL | Incomplete CLAUDE.md update spec in Phase 5 | Phase 5 now explicitly lists: Scripts table, Roadmap, `/configs` directory reference, Troubleshooting for `~/.claude-devkit/`, `.gitignore` recommended section. |
| R-04 | Librarian | FAIL | Understated deviation -- first `.py` file in `scripts/` | Context Alignment deviation 2 rewritten to explicitly acknowledge this is a first. |
| SA-S | Red Team SA | Major | Spoofing missing from STRIDE | Added Spoofing entry: scanner/venv replacement. |
| SA-R | Red Team SA | Major | Repudiation missing from STRIDE | Added Repudiation entry: no audit trail of scanner output. |
| SA-C | Red Team SA | Major | Cache poisoning risk understated | Raised from Low to Medium. Added HMAC integrity. |
| SA-V | Red Team SA | Minor | Venv supply chain not identified as trust boundary | Added venv/PyPI as trust boundary in diagram and STRIDE table. |

---

## Context

### Problem Statement

Claude Code skills `/architect` (Step 1, Context Discovery) and `/ship` (Step 1, Read Plan + Step 4, Code Review) currently discover codebase structure through iterative grep + file reads. This exploratory phase consumes an estimated 30-50% of the token budget per run (see Phase 6 for measurement methodology to validate this estimate). The exploration is non-deterministic -- the same codebase may be explored differently on consecutive runs, and agents frequently re-discover facts that could have been pre-computed once.

The pattern is well-understood: deterministic components (file parsing, symbol extraction, import graph construction) should run before the LLM, not inside it. The LLM should receive structured facts and focus its token budget on reasoning, not on `grep`-ing for function signatures.

### Current State

- `/architect` Step 1 reads `CLAUDE.md` and recent plans. It does NOT read source code structure -- the architect agent discovers it ad-hoc during Step 2.
- `/ship` Step 1 reads the plan file. Coder agents dispatched in Step 2 explore the codebase individually, each spending tokens on the same structural discovery.
- `/ship` Step 4 (Code Review) estimates blast radius heuristically rather than from deterministic import graph data.
- No existing script in `scripts/` performs source code analysis.

### Roadmap Placement

This feature is a v1.1 roadmap item for CLAUDE.md:
```
### v1.1 (Next)
- [ ] Codebase symbol index (deterministic scanner for agent context)
- [ ] CLAUDE.md template generator (broader than security section)
- [ ] Project initializer (full project setup)
- [ ] Skill version upgrade tool
```

### Prior Art

Three implementations inform this design:

1. **Shrike nano-analyzer** (`~/projects/shrike/lab/scripts/nano-analyzer.py`) -- Working code. `discover_files()` at line 995 handles recursive file walking, symlink skipping, large file filtering (>200K chars), binary detection. `resolve_headers()` at line 1065 traces include dependencies. Proven patterns for safe file traversal. (Note: local-only artifact, not in this repo.)

2. **Balor-fianna deterministic source scanner** (`~/projects/balor-fianna/plans/deterministic-source-scanner.md`) -- ADR (DRAFT). Proposes `JavaSourceScanner` with `SymbolTable`, `SymbolDelta`, `VulnPattern` using `py-tree-sitter` + `tree-sitter-java`. Establishes the data model: classes, methods (with signatures), fields (with types), imports. (Note: local-only artifact, not in this repo.)

3. **Journal decision** (`~/journal/decisions/2026-05-25-deterministic-source-scanner.md`) -- Proposes polyglot tree-sitter scanner as Tier 0 on claude-devkit roadmap. Lists MCP server as future evolution. (Note: local-only artifact, not in this repo.)

---

## Goals

1. Reduce token budget spent on codebase exploration in `/architect` and `/ship` (target: measurable reduction validated in Phase 6 evaluation gate; success threshold >=20%).
2. Provide deterministic, reproducible codebase structural facts to all agent invocations within a skill run.
3. Support Python and TypeScript as primary languages, with Java and Go as secondary.
4. Produce output compact enough to fit in agent context (hard cap: 4000 tokens default, configurable via `--max-tokens`) without dominating the token budget.
5. Degrade gracefully when tree-sitter is unavailable -- fall back to regex-based extraction, never block skill execution.

## Non-Goals

1. Replace the LSP (Language Server Protocol) -- the scanner extracts structural facts, not type-checked semantics.
2. Build an MCP server (future evolution, not Phase 1).
3. Full cross-file type resolution or whole-program analysis.
4. Support for compiled languages that require build systems (C/C++ with complex `#include` paths).
5. Replace `/secure-review` or `/audit` -- the scanner provides structural context, not security analysis.
6. Real-time incremental updates (run-once-per-invocation is sufficient for v1).
7. Caller/call-site detection (deferred to v2 -- see C-02 in Revision Log. v1 provides import graph for blast radius).

## Assumptions

1. Python 3.10+ is available on all target platforms (macOS, Linux dev environments). The codebase already depends on `python3` for `emit-audit-event.sh`, `compute-run-score.sh`, and `score-reflector.sh`.
2. `py-tree-sitter` (>=0.25.0) and language grammar packages can be installed via `pip` in a venv. They are MIT-licensed and have no transitive dependencies beyond a C compiler for the binding.
3. The scanner will run at the start of skill invocations, adding <5 seconds for a typical project (10K lines). Tree-sitter parses at ~10K lines/second.
4. Output format targets ~50 bytes per symbol entry. A 50-file project with ~500 symbols produces ~25KB of index data, which the summary formatter truncates to fit the 4000-token hard cap.
5. Skills will be modified to invoke the scanner and pass its output to agents, but the scanner itself has no dependency on skill internals.

---

## Architectural Analysis

### Key Drivers

| Driver | Weight | Implication |
|--------|--------|-------------|
| Token efficiency | High | Output must be compact; agents must not explore what the scanner already knows |
| Graceful degradation | High | Missing tree-sitter must never block `/architect` or `/ship` |
| Polyglot support | Medium | Python + TypeScript are required; Java + Go are stretch goals |
| Performance | Medium | Must complete in <5s for typical projects; <30s for large monorepos |
| Maintainability | Medium | Single script, minimal dependencies, follows existing scripts/ patterns |
| Future extensibility | Low | MCP server evolution is planned but not designed here |

### Design Decisions

**Decision 1: Standalone Python script in `scripts/`**

The scanner is `scripts/codebase-scanner.py` -- a standalone Python script. It reads files, produces structured output to stdout, and exits. Skills invoke it via `Bash` tool calls.

*Rationale:* Follows established claude-devkit pattern. No new infrastructure. Skills already invoke scripts via Bash. The script can be tested independently.

*Deviation note:* This is the first standalone `.py` file in `scripts/`. Existing scripts are either pure `.sh` files or bash wrappers around embedded `python3 -c` blocks (`compute-run-score.sh`, `score-reflector.sh`). A standalone `.py` is justified by the complexity of tree-sitter integration and the structured data model -- the bash-wrapping-embedded-python pattern would be unwieldy at 800+ lines.

*Alternative rejected:* Python module in a new `lib/` directory. Would introduce a new directory tier not documented in CLAUDE.md and would require import path management.

**Decision 2: Tree-sitter with regex fallback**

Primary parsing uses `py-tree-sitter` (>=0.25.0) with language-specific grammars and the `QueryCursor` API. If tree-sitter is not installed, the script falls back to regex-based extraction that captures function/class names and imports (lower fidelity but still useful).

*Rationale:* Tree-sitter provides accurate AST-based extraction. Regex fallback ensures the scanner never blocks skill execution. The fallback is analogous to how `/ship` degrades when security skills are not deployed.

*Alternative rejected:* Regex-only. Regex cannot distinguish methods from local variables, cannot extract parameter types, cannot build accurate import graphs. The balor-fianna ADR documents regex limitations: "can't distinguish method calls from annotations, misses field renames, treats symbol occurrences in comments as present."

**Decision 3: JSON output format with compact summary mode and hard token cap**

The scanner outputs JSON to stdout. Two modes:
- `--format full`: Complete symbol index (for caching/debugging).
- `--format summary` (default): Compact text summary optimized for LLM consumption, enforced by a `--max-tokens N` hard cap (default: 4000).

The summary formatter uses a deterministic truncation strategy when output exceeds the cap:
1. Always include: header line (parser mode, language counts, file/symbol totals).
2. Rank files by symbol density (symbols per file, descending).
3. Include top-N files until 70% of token budget consumed.
4. Include import graph edges for included files until 85% of budget consumed.
5. Include file listing (name + line count only) until 95% of budget consumed.
6. Append `... and N more files/symbols omitted (--max-tokens 4000)` if truncated.

*Rationale:* JSON for machine consumption (future MCP server, tooling integration). Summary mode for direct injection into agent prompts. The hard cap prevents the scanner from consuming an unbounded share of the agent's context window.

**Decision 4: File-based cache in user-scoped directory with HMAC integrity**

The scanner writes its full output to `~/.claude-devkit/cache/<project-hash>/index.json`, where `<project-hash>` is SHA-256 of the canonicalized project root path (first 12 hex chars). On subsequent runs, it compares file modification times and content hashes against the cached index. Only changed files are re-parsed.

The cache includes an HMAC-SHA256 integrity tag computed over the JSON content, keyed with a per-user secret derived from `os.getlogin() + os.path.expanduser("~")`. On read, the HMAC is verified; mismatches trigger a full rescan with a warning on stderr.

*Rationale:* The cache is consumed by LLM prompts, making it a trust-sensitive artifact. Storing it outside the project root prevents accidental git commits and reduces the attack surface from shared project directories. The HMAC detects tampering without requiring external key management. Within a single `/ship` run, the scanner may be invoked multiple times (Step 1, Step 2 for each coder, Step 4 for review). Caching avoids redundant parsing.

*Alternative rejected:* Cache in project root (`.codebase-index.json`). This is a trust boundary violation: the cache is in the same directory as untrusted project files, could be committed to git via `git add --force`, and could be tampered with in shared filesystem scenarios.

**Decision 5: Virtual environment with subprocess re-exec**

Tree-sitter is installed in a dedicated venv at `~/.claude-devkit/scanner-venv/`. The `install.sh` script creates this venv and installs pinned packages from a requirements file. Skills invoke the scanner via the venv's Python interpreter when available; otherwise the system `python3` is used (triggering regex fallback).

*Rationale:* Avoids polluting system Python. Follows the externally-managed-environment pattern required by Homebrew Python 3.14. The venv is user-scoped (not project-scoped) so it serves all projects. Subprocess re-exec (rather than `sys.path` manipulation) is the standard pattern for consuming a venv from an external script -- it avoids module shadowing risks, multi-version glob fragility, and platform-specific site-packages path differences.

**Decision 6: Scanner invoked via `$CLAUDE_DEVKIT` env var (no `deploy.sh` changes)**

Skills reference the scanner via `$CLAUDE_DEVKIT/scripts/codebase-scanner.py`, with `./scripts/codebase-scanner.py` as a local fallback (for running within the claude-devkit repo itself). `deploy.sh` is NOT modified -- it remains scoped to deploying skills to `~/.claude/skills/`, consistent with its documented purpose in CLAUDE.md.

*Rationale:* `$CLAUDE_DEVKIT` is already set by `install.sh` and is available in Claude Code's Bash tool environment (which inherits the user's shell RC). Expanding `deploy.sh` to copy scripts to `~/.claude/scripts/` would change its documented scope and create a directory (`~/.claude/scripts/`) that is not owned by claude-devkit.

---

## Proposed Design

### Component Architecture

```
scripts/codebase-scanner.py          # Main script (standalone, ~800 lines)
    |
    +-- FileDiscovery                # Walk dirs, filter by extension, skip symlinks/large/binary
    |     (adapted from nano-analyzer discover_files())
    |
    +-- TreeSitterParser             # Parse files via py-tree-sitter (>=0.25.0, QueryCursor API)
    |     +-- PythonExtractor        # Python-specific symbol extraction
    |     +-- TypeScriptExtractor    # TypeScript/JavaScript-specific extraction
    |     +-- JavaExtractor          # Java-specific extraction (stretch)
    |     +-- GoExtractor            # Go-specific extraction (stretch)
    |
    +-- RegexFallbackParser          # Regex-based extraction when tree-sitter unavailable
    |
    +-- SymbolIndex                  # Aggregated symbol data across all files
    |     +-- symbols[]              # Functions, classes, methods with signatures
    |     +-- imports{}              # Import graph (file -> imported modules)
    |
    +-- OutputFormatter              # JSON full / text summary with token cap
    |
    +-- CacheManager                 # ~/.claude-devkit/cache/<hash>/index.json read/write/invalidate

configs/scanner-languages.json       # Language grammar configuration (extensions, queries)
```

### Data Model

```python
@dataclass
class SymbolEntry:
    name: str                    # "MyClass.my_method" or "standalone_function"
    kind: str                    # "class" | "function" | "method" | "interface" | "type"
    file: str                    # Relative path from project root
    line: int                    # 1-based line number
    signature: str               # "def my_method(self, x: int) -> bool" (condensed)
    visibility: str              # "public" | "private" | "internal" | "exported"

@dataclass
class ImportEntry:
    source_file: str             # File that imports
    target: str                  # What is imported ("os.path", "./utils", "lodash")
    kind: str                    # "stdlib" | "local" | "third_party"
    names: list[str]             # Specific names imported (["join", "dirname"])

@dataclass
class CodebaseIndex:
    project_root: str
    scan_time: str               # ISO 8601
    scanner_version: str
    parser_mode: str             # "tree-sitter" | "regex-fallback"
    languages: dict[str, int]    # {"python": 42, "typescript": 18}
    file_count: int
    symbol_count: int
    files: list[FileEntry]       # Per-file metadata (path, lines, language)
    symbols: list[SymbolEntry]
    imports: list[ImportEntry]
    # NOTE: callers/call-site detection deferred to v2 (see Revision Log C-02)
```

### Summary Output Format

The summary mode produces a compact, LLM-optimized text block enforced by the `--max-tokens` hard cap (default 4000). Example for a 30-file Python project:

```
## Codebase Structure (auto-generated by codebase-scanner v1.0.0)
Parser: tree-sitter | Languages: python(24), typescript(6) | Files: 30 | Symbols: 187

### Key Modules
- src/auth/handler.py: AuthHandler(login, logout, refresh_token, validate_session)
- src/auth/middleware.py: AuthMiddleware(process_request, check_permissions)
- src/api/routes.py: create_app(), register_routes(app), health_check()
- src/api/users.py: UserRouter(get_user, create_user, update_user, delete_user)
- src/db/models.py: User, Session, Permission (SQLAlchemy models)
- src/db/queries.py: get_user_by_id(id:int), find_sessions(user_id:int, active:bool)

### Import Graph (top-level)
- src/api/* -> src/auth/*, src/db/*
- src/auth/* -> src/db/models
- src/db/* -> sqlalchemy, os

### File Listing (30 files, 4,218 lines)
src/auth/handler.py (245 lines) | src/auth/middleware.py (89 lines) | ...
```

If the output exceeds the token cap, the deterministic truncation strategy (Decision 3) applies and a footer is appended:
```
... and 12 more files, 94 more symbols omitted (--max-tokens 4000)
```

This format fits within the 4000-token hard cap for typical projects and provides the structural facts that agents currently spend time discovering via grep.

### CLI Interface

```
Usage: python3 scripts/codebase-scanner.py [OPTIONS] [PATH]

Arguments:
  PATH                Project root directory (default: current directory)

Options:
  --format FORMAT     Output format: summary (default), json
  --languages LANGS   Comma-separated language filter (default: auto-detect)
  --max-files N       Maximum files to scan (default: 500)
  --max-file-size N   Maximum file size in bytes (default: 200000)
  --max-tokens N      Maximum output tokens for summary mode (default: 4000)
  --no-cache          Skip cache, force full rescan
  --include PATTERN   Include only files matching glob pattern (repeatable)
  --exclude PATTERN   Exclude files matching glob pattern (repeatable)
  --quiet             Suppress stderr progress messages
  --version           Print version and exit
  --self-test         Run internal validation tests
  --help              Print this help and exit

Exit codes:
  0   Success (output on stdout)
  0   Success with regex fallback (output on stdout, warning on stderr)
  1   Fatal error (no output)
  2   Invalid arguments
```

Default exclusions (hardcoded, not configurable):
- `node_modules/`, `__pycache__/`, `.git/`, `.venv/`, `venv/`, `dist/`, `build/`
- `*.min.js`, `*.min.css`, `*.map`, `*.lock`, `*.sum`
- Binary files (detected by null byte in first 8KB)

---

## Integration Points

### /architect Step 1 -- Context Discovery (Modified)

**Current behavior:** Reads `CLAUDE.md` and recent plans only. The architect agent discovers codebase structure ad-hoc during Step 2.

**New behavior:** After reading `CLAUDE.md` and plans, run the scanner and include its output in `$CONTEXT_BLOCK`.

```markdown
## Step 1 -- Context Discovery

[... existing parallel reads ...]

4. **Codebase structure:** Run codebase scanner to extract structural facts.

Tool: `Bash`

\`\`\`bash
# Run codebase scanner (degrades gracefully if tree-sitter not installed)
SCANNER_PYTHON="${HOME}/.claude-devkit/scanner-venv/bin/python3"
SCANNER_SCRIPT="${CLAUDE_DEVKIT:-./}/scripts/codebase-scanner.py"
if [ ! -f "$SCANNER_SCRIPT" ]; then
  SCANNER_SCRIPT="./scripts/codebase-scanner.py"
fi
if [ -x "$SCANNER_PYTHON" ]; then
  SCANNER_OUTPUT=$("$SCANNER_PYTHON" "$SCANNER_SCRIPT" --format summary --quiet 2>/dev/null || echo "")
else
  SCANNER_OUTPUT=$(python3 "$SCANNER_SCRIPT" --format summary --quiet 2>/dev/null || echo "")
fi
echo "$SCANNER_OUTPUT"
\`\`\`

**Append to $CONTEXT_BLOCK:**

### Codebase Structure (auto-generated)
[Scanner output, or "Scanner not available. Agent will discover structure during planning."]
```

Impact: The architect agent receives a pre-computed symbol index at the start of Step 2, reducing exploratory grep/read cycles. The agent can immediately reference specific files, functions, and import relationships.

### /ship Step 1 -- Read Plan (Modified)

**Current behavior:** Coordinator reads the plan file. Coders receive the plan + `CLAUDE.md` context.

**New behavior:** Coordinator also runs the scanner. Each coder receives the plan + codebase structure summary relevant to their work group's file scope.

```markdown
## Step 1 -- Coordinator reads plan

[... existing plan reading ...]

**Run codebase scanner:**

Tool: `Bash`

\`\`\`bash
SCANNER_PYTHON="${HOME}/.claude-devkit/scanner-venv/bin/python3"
SCANNER_SCRIPT="${CLAUDE_DEVKIT:-./}/scripts/codebase-scanner.py"
if [ ! -f "$SCANNER_SCRIPT" ]; then
  SCANNER_SCRIPT="./scripts/codebase-scanner.py"
fi
if [ -x "$SCANNER_PYTHON" ]; then
  SCANNER_OUTPUT=$("$SCANNER_PYTHON" "$SCANNER_SCRIPT" --format summary --quiet 2>/dev/null || echo "")
else
  SCANNER_OUTPUT=$(python3 "$SCANNER_SCRIPT" --format summary --quiet 2>/dev/null || echo "")
fi
echo "$SCANNER_OUTPUT"
\`\`\`

[... include SCANNER_OUTPUT in coder dispatch prompts ...]
```

Impact: Coder agents start with structural context, reducing redundant file exploration across parallel work groups.

### /ship Step 4 -- Code Review (Modified)

**Current behavior:** Code reviewer estimates blast radius heuristically.

**New behavior:** Reviewer receives deterministic import graph data.

When dispatching the code reviewer, include:
```
**Import graph data (pre-computed):**
[Filtered scanner output showing import relationships for files in git diff --name-only]
```

The coordinator filters the scanner's import graph to include only files that appear in `git diff --name-only` output, plus files that import those modified files (reverse import edges). This provides deterministic blast radius: "changes to `src/auth/handler.py` affect `src/api/routes.py` and `src/api/users.py` (which import `src/auth/handler`)."

Impact: Code review blast radius is derived from deterministic import relationships rather than heuristic grep. (Note: full call-site-level blast radius is deferred to v2.)

---

## Security Requirements

This feature involves file system operations (reading source files, writing cache files) and path traversal. The scanner processes untrusted input (arbitrary source files in user projects).

### Assets at Risk

| Asset | Classification | Risk |
|-------|---------------|------|
| Source code files | Internal-Confidential | Read-only access; scanner reads file contents for parsing |
| Cache file (`~/.claude-devkit/cache/`) | Internal | Contains file paths and symbol names; no source code bodies. HMAC-protected. |
| Scanner output (stdout) | Internal | Contains structural facts; injected into agent prompts |
| Virtual environment (`~/.claude-devkit/scanner-venv/`) | Public | Standard Python packages; no secrets. Supply chain trust boundary. |

### Trust Boundaries

```
+---------------------------+      +----------------------------+
|  User's project directory |      |  Scanner script            |
|  (untrusted file content) | ---> |  (trusted code, runs as    |
|                           |      |   user's UID)              |
+---------------------------+      +----------------------------+
                                          |
                                          v
                                   +----------------------------+
                                   |  User-scoped cache + stdout|
                                   |  (~/.claude-devkit/cache/) |
                                   |  (consumed by skills/LLM)  |
                                   +----------------------------+

+---------------------------+
|  PyPI / venv packages     |
|  (third-party supply      | ---> Scanner imports tree-sitter
|   chain, trust boundary)  |      from this venv at runtime
+---------------------------+
```

The primary trust boundary is between untrusted file content (user's project files, which may contain adversarial content) and the scanner's file system operations. A secondary trust boundary exists between the scanner and PyPI-sourced packages in the venv (tree-sitter and language grammars). The scanner MUST NOT:
- Execute any code from scanned files
- Follow symlinks outside the project root
- Read files outside the project root
- Write files outside the project root or `~/.claude-devkit/`

### STRIDE Analysis

| Threat | Category | Risk | Mitigation |
|--------|----------|------|------------|
| Malicious filenames cause path traversal | **T**ampering | Medium | Canonicalize all paths via `os.path.realpath()`. Reject any resolved path outside the project root. Reject filenames containing null bytes. Failure mode: file is skipped, diagnostic emitted to stderr. |
| Scanner script or venv replaced with malicious version | **S**poofing | Medium | Scanner is invoked via `$CLAUDE_DEVKIT` which points to a git-controlled directory. Venv is created by `install.sh` under `~/.claude-devkit/` (user-owned, mode 0700). Mitigation: verify venv directory ownership (`os.stat().st_uid == os.getuid()`) before re-exec. Failure mode: ownership mismatch triggers regex fallback with warning. |
| No audit trail of scanner output consumed by agents | **R**epudiation | Low | When `/ship` or `/architect` invoke the scanner, log a `scanner_invocation` event to the JSONL audit log via `emit-audit-event.sh` containing: scanner version, parser mode, file count, symbol count, and SHA-256 hash of the output. Enables post-hoc verification that the scanner output matched the agent's context. |
| Symlink escape reads files outside project | **I**nformation Disclosure | Medium | Skip all symlinks (following nano-analyzer pattern). `os.path.islink()` check before any `open()`. Failure mode: symlink is skipped, diagnostic emitted to stderr. |
| Adversarial file content causes parser crash | **D**enial of Service | Low | tree-sitter is a memory-safe parser (defense-in-depth; not primary mitigation). Primary mitigation: wrap parse calls in try/except, set per-file timeout of 5 seconds. Failure mode: file is skipped, parse error count incremented. |
| Oversized project exhausts memory | **D**enial of Service | Medium | `--max-files 500` default cap. `--max-file-size 200000` (bytes) default cap. Total memory bounded by file count * max size. Failure mode: files beyond limit are skipped with count reported. |
| Cache file poisoning injects false structural data | **T**ampering | Medium | Cache stored in user-scoped directory (`~/.claude-devkit/cache/`), not project root. HMAC-SHA256 integrity tag verified on read. Schema version check discards incompatible caches. Atomic writes (temp + rename) prevent partial reads. Failure mode: HMAC mismatch or schema mismatch triggers full rescan with warning. |
| Scanner output injected into LLM prompt | **E**levation of Privilege | Low | Scanner output contains symbol names and file paths only -- no source code bodies, no executable content. Output is deterministic (same input produces same output). Hard token cap prevents context window overflow. The LLM already has full file access via Read tool, so the scanner output does not expand the LLM's access surface. |
| Scanner reads secrets from file names/paths | **I**nformation Disclosure | Low | File paths in output are relative to project root. No file content is included in summary mode. Full mode includes signatures but not function bodies. |
| Malicious PyPI package in venv executes arbitrary code | **T**ampering | Low | Packages are pinned to specific versions in `~/.claude-devkit/scanner-requirements.txt`. Venv directory is user-owned (mode 0700). tree-sitter and grammar packages are high-profile, widely-used projects (>10K GitHub stars). Failure mode: if tree-sitter import fails, regex fallback is used. |

### Proposed Mitigations (implemented in code)

1. **Path canonicalization:** Every file path is resolved via `os.path.realpath()` and verified to be a descendant of the project root before opening. If `realpath()` raises an exception (e.g., permission denied), the file is skipped and a diagnostic is emitted to stderr.
2. **Symlink rejection:** All symlinks are skipped with a diagnostic message (following nano-analyzer `discover_files()` pattern).
3. **Size limits:** Per-file (200KB default) and per-project (500 files default) limits prevent resource exhaustion.
4. **No code execution:** The scanner ONLY reads files and parses syntax trees. It does not `import`, `exec`, `eval`, or subprocess any scanned code.
5. **Safe parser:** tree-sitter is a memory-safe incremental parser. Parse failures are caught and logged; the file is skipped. Per-file timeout fires via `signal.alarm(5)` on Unix; on timeout, the parse is aborted and the file is skipped cleanly (tree-sitter parse state is per-call, no global state corruption).
6. **Cache integrity:** Cache files are stored in `~/.claude-devkit/cache/<project-hash>/` (user-scoped, mode 0700). HMAC-SHA256 integrity tag is computed on write and verified on read. Schema version mismatch triggers full rescan. Atomic writes (write to temp file, `os.rename()`) prevent partial reads from concurrent invocations.
7. **Output sanitization:** Symbol names in output are filtered to printable ASCII + common Unicode identifiers. Control characters are stripped. If a symbol name is entirely stripped, it is omitted from output with a diagnostic.
8. **Output size cap:** Summary mode enforces a hard token cap (`--max-tokens`, default 4000) with deterministic truncation.
9. **Venv ownership verification:** Before re-exec under the venv Python, verify that the venv directory is owned by the current user (`os.stat().st_uid == os.getuid()`). Ownership mismatch triggers regex fallback with a warning.

---

## Interfaces / Schema Changes

### New Files

| File | Purpose | Size Estimate |
|------|---------|---------------|
| `scripts/codebase-scanner.py` | Main scanner script | ~800 lines |
| `configs/scanner-languages.json` | Language configuration (extensions, tree-sitter queries) | ~150 lines |

### Modified Files

| File | Phase | Change | Scope |
|------|-------|--------|-------|
| `skills/architect/SKILL.md` | 3 | Add scanner invocation to Step 1 Context Discovery | ~15 lines added to Step 1 |
| `skills/ship/SKILL.md` | 3 | Add scanner invocation to Step 1 Read Plan | ~15 lines added to Step 1 |
| `scripts/install.sh` | 2 | Add scanner venv setup (optional, non-blocking) | ~25 lines added |
| `scripts/uninstall.sh` | 5 | Add scanner venv and cache cleanup | ~5 lines added |
| `scripts/test-integration.sh` | 4 | Add 6-8 scanner integration tests | ~60 lines added |
| `CLAUDE.md` | 5 | Document scanner in Scripts, Configs, Roadmap, Troubleshooting, .gitignore sections | ~40 lines added |
| `.gitignore` | 1 | Add `~/.claude-devkit/cache/` comment (cache is outside project root; no project .gitignore entry needed) | Comment only |

### New Configuration: `configs/scanner-languages.json`

```json
{
  "version": "1.0.0",
  "languages": {
    "python": {
      "extensions": [".py"],
      "tree_sitter_package": "tree-sitter-python>=0.23,<1.0",
      "queries": {
        "classes": "(class_definition name: (identifier) @name)",
        "functions": "(function_definition name: (identifier) @name parameters: (parameters) @params)",
        "methods": "(class_definition body: (block (function_definition name: (identifier) @name parameters: (parameters) @params)))",
        "imports": ["(import_statement)", "(import_from_statement)"]
      }
    },
    "typescript": {
      "extensions": [".ts", ".tsx", ".js", ".jsx"],
      "tree_sitter_package": "tree-sitter-typescript>=0.23,<1.0",
      "queries": {
        "classes": "(class_declaration name: (type_identifier) @name)",
        "functions": "(function_declaration name: (identifier) @name parameters: (formal_parameters) @params)",
        "methods": "(method_definition name: (property_identifier) @name parameters: (formal_parameters) @params)",
        "imports": ["(import_statement)"],
        "exports": ["(export_statement)", "(export_default_declaration)"]
      }
    },
    "java": {
      "extensions": [".java"],
      "tree_sitter_package": "tree-sitter-java>=0.23,<1.0",
      "queries": {
        "classes": "(class_declaration name: (identifier) @name)",
        "functions": "(method_declaration name: (identifier) @name parameters: (formal_parameters) @params)",
        "imports": ["(import_declaration)"]
      }
    },
    "go": {
      "extensions": [".go"],
      "tree_sitter_package": "tree-sitter-go>=0.23,<1.0",
      "queries": {
        "functions": "(function_declaration name: (identifier) @name parameters: (parameter_list) @params)",
        "methods": "(method_declaration name: (field_identifier) @name parameters: (parameter_list) @params)",
        "types": "(type_declaration (type_spec name: (type_identifier) @name))",
        "imports": ["(import_declaration)"]
      }
    }
  }
}
```

---

## Data Migration

None. This is a new capability with no existing data to migrate.

---

## Implementation Plan

### Phase 1: Core Scanner Script (scripts/codebase-scanner.py)

**Estimated effort:** 3-4 days
**Dependencies:** None (regex fallback works without tree-sitter)
**Deliverable:** Working scanner script that produces structured output

1. [ ] Create `scripts/codebase-scanner.py` with the following modules:
   - `FileDiscovery` class: recursive file walking with extension filtering, symlink skipping, size limits, binary detection, gitignore-aware exclusions. Adapted from nano-analyzer `discover_files()` (line 995-1054).
   - `RegexFallbackParser` class: regex-based extraction for Python (function/class defs, imports), TypeScript (function/class/interface declarations, imports/exports), Java (class/method declarations, imports), Go (func/type declarations, imports).
   - `SymbolIndex` class: aggregation of symbols and imports across files. (Note: no `callers` field -- deferred to v2.)
   - `CacheManager` class: `~/.claude-devkit/cache/<project-hash>/index.json` read/write/invalidation based on file mtimes and content hashes (SHA-256 of entire file content). HMAC-SHA256 integrity tag on write/read.
   - `OutputFormatter` class: JSON full mode, text summary mode with `--max-tokens` hard cap and deterministic truncation.
   - `main()`: CLI argument parsing, orchestration, output.
   - Path canonicalization and symlink rejection in `FileDiscovery`.
   - Per-file parse timeout (5 seconds via `signal.alarm()` on Unix).

2. [ ] Create `configs/scanner-languages.json` with language configurations for Python, TypeScript, Java, Go. Pin grammar package version ranges.

3. [ ] Make script executable: `chmod +x scripts/codebase-scanner.py`.

4. [ ] Run validation: Test against claude-devkit itself (Python + shell), a sample TypeScript project, and an empty directory.
   ```bash
   # Test against claude-devkit (regex fallback, no tree-sitter)
   python3 scripts/codebase-scanner.py --format summary .
   python3 scripts/codebase-scanner.py --format json . | python3 -m json.tool > /dev/null
   
   # Test with empty directory
   mkdir -p /tmp/empty-test && python3 scripts/codebase-scanner.py /tmp/empty-test
   
   # Test with --max-files 5
   python3 scripts/codebase-scanner.py --format summary --max-files 5 .
   
   # Test --max-tokens truncation
   python3 scripts/codebase-scanner.py --format summary --max-tokens 500 .
   
   # Test self-test
   python3 scripts/codebase-scanner.py --self-test
   ```

5. [ ] Commit: `feat(scripts): add codebase-scanner.py for deterministic symbol index`

### Phase 2: Tree-sitter Integration and Virtual Environment

**Estimated effort:** 2-3 days
**Dependencies:** Phase 1
**Deliverable:** Tree-sitter parsing mode with venv-based dependency management

1. [ ] Create `~/.claude-devkit/scanner-requirements.txt` with pinned versions:
   ```
   tree-sitter>=0.25.0,<0.26
   tree-sitter-python>=0.23,<1.0
   tree-sitter-typescript>=0.23,<1.0
   tree-sitter-java>=0.23,<1.0
   tree-sitter-go>=0.23,<1.0
   ```

2. [ ] Extend `scripts/install.sh` to create scanner venv:
   ```bash
   # Scanner virtual environment (optional -- scanner falls back to regex without it)
   SCANNER_VENV="$HOME/.claude-devkit/scanner-venv"
   SCANNER_REQS="$HOME/.claude-devkit/scanner-requirements.txt"
   mkdir -p "$HOME/.claude-devkit"
   chmod 700 "$HOME/.claude-devkit"
   
   # Write pinned requirements
   cat > "$SCANNER_REQS" << 'REQS'
   tree-sitter>=0.25.0,<0.26
   tree-sitter-python>=0.23,<1.0
   tree-sitter-typescript>=0.23,<1.0
   tree-sitter-java>=0.23,<1.0
   tree-sitter-go>=0.23,<1.0
   REQS
   
   if command -v python3 &>/dev/null; then
     echo "Setting up codebase scanner virtual environment..."
     python3 -m venv "$SCANNER_VENV" 2>/dev/null || true
     if [ -f "$SCANNER_VENV/bin/pip" ]; then
       "$SCANNER_VENV/bin/pip" install --quiet -r "$SCANNER_REQS" 2>/dev/null || true
       echo "Scanner venv created at $SCANNER_VENV"
     fi
   fi
   ```

3. [ ] Implement `TreeSitterParser` using the tree-sitter >=0.25.0 `QueryCursor` API:
   ```python
   # Correct API for tree-sitter 0.25+
   from tree_sitter import Language, Parser, Query, QueryCursor
   
   parser = Parser()
   parser.language = language
   tree = parser.parse(source_bytes)
   
   query = Query(language, query_pattern)
   cursor = QueryCursor(query)
   matches = cursor.matches(tree.root_node)
   ```
   Language-specific extractors:
   - `PythonExtractor`: classes, functions, methods, decorators, imports (from/import), type annotations in signatures.
   - `TypeScriptExtractor`: classes, functions, methods, interfaces, type aliases, imports, exports, arrow functions assigned to const.
   - `JavaExtractor`: classes, interfaces, methods, fields, imports, annotations.
   - `GoExtractor`: functions, methods (with receiver type), types (struct/interface), imports.

4. [ ] Add venv ownership verification before subprocess re-exec:
   ```python
   def _get_scanner_python():
       """Return venv Python path if available and owned by current user."""
       venv_python = os.path.expanduser("~/.claude-devkit/scanner-venv/bin/python3")
       if os.path.isfile(venv_python):
           venv_dir = os.path.expanduser("~/.claude-devkit/scanner-venv")
           try:
               if os.stat(venv_dir).st_uid == os.getuid():
                   return venv_python
               else:
                   print("WARNING: scanner-venv not owned by current user, using regex fallback",
                         file=sys.stderr)
           except OSError:
               pass
       return None
   ```
   Note: The scanner script itself does NOT activate the venv or manipulate `sys.path`. It simply attempts `import tree_sitter` -- if that fails (because it was invoked via system `python3`), it uses regex fallback. The venv selection happens in the skill's Bash invocation block (see Integration Points above).

5. [ ] Run validation:
   ```bash
   # Install tree-sitter via venv
   ~/.claude-devkit/scanner-venv/bin/pip install -r ~/.claude-devkit/scanner-requirements.txt
   
   # Test tree-sitter mode
   ~/.claude-devkit/scanner-venv/bin/python3 scripts/codebase-scanner.py --format summary .
   # Should output "Parser: tree-sitter" (not "regex-fallback")
   
   # Test fallback by invoking with system python (no tree-sitter)
   python3 scripts/codebase-scanner.py --format summary .
   # Should output "Parser: regex-fallback" (unless tree-sitter installed system-wide)
   ```

6. [ ] Commit: `feat(scripts): add tree-sitter parsing to codebase-scanner`

### Phase 3: Skill Integration (/architect and /ship)

**Estimated effort:** 1 day
**Dependencies:** Phase 1 (Phase 2 is nice-to-have but not required)
**Deliverable:** Skills consume scanner output in context blocks

1. [ ] Modify `skills/architect/SKILL.md` Step 1 (Context Discovery):
   - Add a parallel read for codebase scanner output after the existing CLAUDE.md and plans reads.
   - Use `$CLAUDE_DEVKIT/scripts/codebase-scanner.py` as primary path, `./scripts/codebase-scanner.py` as fallback.
   - Use venv Python as primary interpreter, system `python3` as fallback.
   - Add scanner output to `$CONTEXT_BLOCK` under a `### Codebase Structure` heading.
   - If scanner output is empty, add "Scanner not available. Agent will discover structure during planning."
   - Log `scanner_invocation` audit event (version, parser mode, file count, symbol count, output SHA-256).

2. [ ] Modify `skills/ship/SKILL.md` Step 1 (Read Plan):
   - Add scanner invocation after plan reading (same invocation pattern as /architect).
   - Include scanner output in coder dispatch prompts for Step 2.
   - Include filtered scanner output (import graph for modified files) in code review prompt for Step 4.
   - Log `scanner_invocation` audit event.

3. [ ] Add integration test for `$CLAUDE_DEVKIT` env var availability:
   ```bash
   run_test $N "CLAUDE_DEVKIT env var is set" \
     "test -n \"$CLAUDE_DEVKIT\" && test -d \"$CLAUDE_DEVKIT\"" "0"
   ```

4. [ ] Run validation: Invoke `/architect` and `/ship` manually on a test project to verify scanner output appears in context.

5. [ ] Validate modified skills:
   ```bash
   python3 generators/validate_skill.py skills/architect/SKILL.md
   python3 generators/validate_skill.py skills/ship/SKILL.md
   ```

6. [ ] Commit: `feat(skills): integrate codebase-scanner into /architect and /ship`

### Phase 4: Integration Tests

**Estimated effort:** 0.5 days
**Dependencies:** Phase 1
**Deliverable:** Integration tests added to `scripts/test-integration.sh`

1. [ ] Add scanner integration tests to `scripts/test-integration.sh` (targeting 6-8 new tests):
   ```bash
   # Test 1: Scanner runs without errors on claude-devkit
   run_test $N "Scanner runs on project root" \
     "python3 $REPO_DIR/scripts/codebase-scanner.py --format summary --quiet $REPO_DIR" "0"
   
   # Test 2: Scanner JSON output is valid JSON
   run_test $N "Scanner JSON output is valid" \
     "python3 $REPO_DIR/scripts/codebase-scanner.py --format json --quiet $REPO_DIR | python3 -m json.tool > /dev/null" "0"
   
   # Test 3: Scanner handles empty directory
   run_test $N "Scanner handles empty directory" \
     "mkdir -p /tmp/scanner-test-empty && python3 $REPO_DIR/scripts/codebase-scanner.py --format summary --quiet /tmp/scanner-test-empty && rm -rf /tmp/scanner-test-empty" "0"
   
   # Test 4: Scanner respects --max-files limit
   run_test $N "Scanner respects max-files limit" \
     "python3 $REPO_DIR/scripts/codebase-scanner.py --format json --max-files 3 --quiet $REPO_DIR | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"file_count\"]<=3, f\"Expected <=3 files, got {d[\"file_count\"]}\"'" "0"
   
   # Test 5: Scanner summary contains expected sections
   run_test $N "Scanner summary has structure sections" \
     "python3 $REPO_DIR/scripts/codebase-scanner.py --format summary --quiet $REPO_DIR | grep -q '## Codebase Structure'" "0"
   
   # Test 6: Scanner rejects symlink escape
   run_test $N "Scanner rejects symlink escape" \
     "mkdir -p /tmp/scanner-symlink-test && ln -sf /etc/passwd /tmp/scanner-symlink-test/escape.py && python3 $REPO_DIR/scripts/codebase-scanner.py --format json --quiet /tmp/scanner-symlink-test | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"file_count\"]==0' && rm -rf /tmp/scanner-symlink-test" "0"
   
   # Test 7: Scanner --self-test passes
   run_test $N "Scanner self-test passes" \
     "python3 $REPO_DIR/scripts/codebase-scanner.py --self-test" "0"
   
   # Test 8: Scanner --max-tokens truncates output
   run_test $N "Scanner respects max-tokens cap" \
     "OUTPUT=\$(python3 $REPO_DIR/scripts/codebase-scanner.py --format summary --max-tokens 200 --quiet $REPO_DIR) && CHARS=\$(echo \"\$OUTPUT\" | wc -c) && test \$CHARS -lt 2000" "0"
   ```

2. [ ] Update test count in `scripts/test-integration.sh` header comment.

3. [ ] Run validation:
   ```bash
   bash scripts/test-integration.sh
   ```

4. [ ] Commit: `test(scripts): add codebase-scanner integration tests`

### Phase 5: Documentation and Polish

**Estimated effort:** 0.5 days
**Dependencies:** Phase 3
**Deliverable:** Updated CLAUDE.md, install.sh scanner setup, final validation

1. [ ] Update `CLAUDE.md` with the following specific changes:
   - **Scripts section table:** Add `codebase-scanner.py` entry: "Deterministic codebase symbol index for agent context (tree-sitter with regex fallback)."
   - **Roadmap section:** Add "Codebase symbol index" to v1.1 items. Mark as completed if Phase 1-4 are done.
   - **`/configs` directory reference:** Add `scanner-languages.json` to the Contents list: "Language grammar configuration for codebase scanner (extensions, tree-sitter queries, package versions)."
   - **Troubleshooting section:** Add entry for `~/.claude-devkit/`: "Scanner venv at `~/.claude-devkit/scanner-venv/` and cache at `~/.claude-devkit/cache/`. Remove with `rm -rf ~/.claude-devkit/` or run `./scripts/uninstall.sh`."
   - **Recommended `.gitignore` section:** No project `.gitignore` entry needed (cache is in `~/.claude-devkit/`, not project root).
   - **Data Flow section:** Add scanner as a pre-processing step before skill invocation.

2. [ ] Update `scripts/install.sh` with scanner venv creation (from Phase 2 step 2).

3. [ ] Update `scripts/uninstall.sh` to clean up scanner venv and cache:
   ```bash
   rm -rf "$HOME/.claude-devkit/scanner-venv"
   rm -rf "$HOME/.claude-devkit/cache"
   # Remove ~/.claude-devkit/ if empty
   rmdir "$HOME/.claude-devkit" 2>/dev/null || true
   ```

4. [ ] Final validation:
   ```bash
   # Full test suite
   bash generators/test_skill_generator.sh
   bash scripts/test-integration.sh
   
   # Scanner self-test
   python3 scripts/codebase-scanner.py --self-test
   
   # Validate modified skills
   python3 generators/validate_skill.py skills/architect/SKILL.md
   python3 generators/validate_skill.py skills/ship/SKILL.md
   
   # Validate deploy
   ./scripts/deploy.sh --validate
   ```

5. [ ] Commit: `docs: document codebase-scanner in CLAUDE.md and install scripts`

### Phase 6: Measurement and Evaluation

**Estimated effort:** 2-3 days (Days 10-14 after deployment)
**Dependencies:** Phase 3 (scanner integrated into skills)
**Deliverable:** Measurement report with go/no-go decision

This phase validates that the scanner delivers measurable value. Without this gate, the feature remains deployed regardless of whether it helps.

1. [ ] **Baseline measurement (scanner disabled):** Run 5 `/architect` invocations on claude-devkit with the scanner invocation commented out. For each run, record:
   - Total tokens consumed (from Claude Code session metadata or audit log `run_end` event).
   - Number of `Read` and `Grep` tool calls in Steps 1-2 (count from session transcript).
   - Wall-clock time for Step 1 (Context Discovery) from audit log timestamps.
   - Qualitative note: did the agent discover the codebase structure adequately?

2. [ ] **Treatment measurement (scanner enabled):** Run 5 `/architect` invocations on the same project with the scanner enabled. Record the same metrics.

3. [ ] **Repeat for `/ship`:** Run 3 `/ship` invocations with and without scanner on a representative plan.

4. [ ] **Evaluate against success thresholds:**
   - **Pass:** Token reduction >=20% for exploration-related tool calls AND scanner output <=4000 tokens AND scanner latency <5 seconds. --> Scanner integration remains enabled.
   - **Marginal (10-20% reduction):** Scanner integration is disabled by default; users can enable via CLI flag. Investigate whether the summary format needs redesign.
   - **Fail (<10% reduction or net-negative):** Scanner integration is removed from skills. Scanner script remains in `scripts/` as a standalone tool but is not auto-invoked.

5. [ ] **Write measurement report:** Save to `plans/codebase-scanner-evaluation.md` with raw data, analysis, and go/no-go decision.

6. [ ] Commit: `docs: codebase-scanner evaluation report`

---

## Rollout Plan

### Phase 1-2: Development (Days 1-7)

- Implement scanner script with regex fallback (Phase 1) and tree-sitter (Phase 2).
- Test against claude-devkit itself, sample TypeScript projects, edge cases (empty dirs, giant files, symlinks).
- No skill changes yet -- scanner is standalone and can be invoked manually.

### Phase 3: Integration (Day 8)

- Modify `/architect` and `/ship` skills to invoke scanner.
- Test with manual `/architect` and `/ship` invocations.
- Deploy skills via `./scripts/deploy.sh`.

### Phase 4-5: Testing and Documentation (Days 8-9)

- Add integration tests.
- Update CLAUDE.md and install scripts.
- Run full test suite.

### Phase 6: Evaluation (Days 10-14)

- Run baseline and treatment measurements.
- Evaluate against success thresholds (>=20% token reduction).
- Write evaluation report with go/no-go decision.
- If evaluation fails, disable scanner integration in skills (keep standalone script).

### Rollback Plan

If the scanner causes issues:

1. **Scanner errors:** The scanner exits 0 with empty output on all error paths. Skills treat empty output as "scanner not available" and continue with existing behavior. No rollback needed.
2. **Skill regression:** Revert the skill SKILL.md changes (Phase 3). The scanner script remains in `scripts/` but is not invoked.
3. **Tree-sitter dependency issues:** Remove the venv (`rm -rf ~/.claude-devkit/scanner-venv`). Scanner falls back to regex mode.
4. **Performance regression:** Add `--max-files 100` to skill invocations to limit scan scope.
5. **Evaluation failure:** If Phase 6 measurements show <10% token reduction, remove scanner invocations from skills. Scanner remains available as a manual CLI tool.

---

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| tree-sitter Python 3.14 compatibility issues | Medium | Low | Regex fallback ensures scanner works without tree-sitter. tree-sitter has broad Python version support. Pin to `>=0.25.0,<0.26`. |
| Scanner output too large for agent context | Low | Medium | Hard `--max-tokens` cap (default 4000) with deterministic truncation. `--max-files` cap. Empirical testing on real projects to calibrate. |
| Scanner adds latency to `/architect` startup | Low | Low | <5s for typical projects. Runs in parallel with other Step 1 reads. Cache eliminates re-parse on subsequent invocations in same session. |
| Regex fallback produces low-quality output | Medium | Medium | Acceptable tradeoff. Regex captures a meaningful subset of symbols. Summary output includes `Parser: regex-fallback` label so agents know the fidelity level. |
| tree-sitter query syntax varies across grammar versions | Medium | Low | Pin grammar version ranges in `scanner-languages.json` and `scanner-requirements.txt`. Catch query parse errors and fall back to regex for that language. |
| Scanner does not deliver measurable token savings | Medium | High | Phase 6 evaluation gate with pass/marginal/fail thresholds. If <10% reduction, scanner integration is removed from skills. |
| Venv supply chain compromise (malicious tree-sitter package) | Low | Medium | Pinned versions in requirements file. Venv directory user-owned (mode 0700). Ownership verification before re-exec. tree-sitter is widely used (>10K stars, used by Neovim, Helix, GitHub). |
| New dependency (tree-sitter) introduces supply chain risk | Low | Medium | tree-sitter is MIT-licensed, maintained by the tree-sitter organization (GitHub), widely used. Installed in isolated venv, not system-wide. |

---

## Test Plan

### Unit-Level Testing (within `codebase-scanner.py`)

The script includes a `--self-test` flag that runs internal validation:

```bash
python3 scripts/codebase-scanner.py --self-test
```

This tests:
- File discovery with symlink rejection
- Path canonicalization and escape prevention
- Regex extraction for all 4 languages (using inline test snippets)
- JSON output schema validation
- Summary output format
- Summary output token cap enforcement
- Cache write/read/invalidation/HMAC verification
- Empty directory handling
- Binary file detection
- Maximum file size enforcement

### Integration Testing

```bash
# Run all integration tests (includes scanner tests from Phase 4)
bash scripts/test-integration.sh
```

### Manual Testing

```bash
# Test against claude-devkit (Python/shell project)
python3 scripts/codebase-scanner.py --format summary .

# Test against a TypeScript project
python3 scripts/codebase-scanner.py --format summary ~/projects/some-ts-project

# Test JSON mode
python3 scripts/codebase-scanner.py --format json . | python3 -m json.tool

# Test cache behavior
python3 scripts/codebase-scanner.py --format summary .  # First run: full scan
python3 scripts/codebase-scanner.py --format summary .  # Second run: cache hit (faster)
python3 scripts/codebase-scanner.py --no-cache --format summary .  # Force rescan

# Test token cap
python3 scripts/codebase-scanner.py --format summary --max-tokens 500 .  # Truncated output

# Test graceful degradation (invoke with system python, no tree-sitter)
python3 scripts/codebase-scanner.py --format summary .  # Should use regex fallback if no tree-sitter
```

### Exact Test Command

```bash
# Full validation suite
bash generators/test_skill_generator.sh && bash scripts/test-integration.sh && python3 scripts/codebase-scanner.py --self-test
```

---

## Acceptance Criteria

1. `python3 scripts/codebase-scanner.py --format summary .` produces structured output for claude-devkit within 5 seconds.
2. `python3 scripts/codebase-scanner.py --format json . | python3 -m json.tool` produces valid JSON.
3. Scanner correctly extracts Python function/class definitions, imports, and method signatures from claude-devkit's `generators/` and `scripts/` directories.
4. Scanner handles empty directories, symlinks, binary files, and oversized files without errors (exit code 0).
5. Scanner falls back to regex mode when tree-sitter is not installed, with a diagnostic message on stderr.
6. Scanner summary output respects `--max-tokens` hard cap (default 4000 tokens).
7. `/architect` Step 1 includes scanner output in `$CONTEXT_BLOCK` when scanner is available.
8. `/ship` Step 1 includes scanner output in coder dispatch prompts.
9. `/ship` Step 4 receives import graph data (not caller data) for blast radius assessment.
10. All existing tests pass (`bash generators/test_skill_generator.sh` and `bash scripts/test-integration.sh`).
11. Scanner integration tests pass (6+ new tests in `test-integration.sh`).
12. No path traversal is possible: symlinks are rejected, all paths are canonicalized against project root.
13. Cache file is stored in `~/.claude-devkit/cache/`, not project root, with HMAC integrity verification.
14. Phase 6 evaluation gate produces a measurement report with a go/no-go decision.

---

## Task Breakdown

### New Files to Create

| File | Phase | Description |
|------|-------|-------------|
| `scripts/codebase-scanner.py` | 1-2 | Main scanner script (~800 lines) |
| `configs/scanner-languages.json` | 1 | Language grammar configuration (~150 lines) |

### Files to Modify

| File | Phase | Description |
|------|-------|-------------|
| `skills/architect/SKILL.md` | 3 | Add scanner invocation to Step 1 (~15 lines) |
| `skills/ship/SKILL.md` | 3 | Add scanner invocation to Step 1 (~15 lines) |
| `scripts/install.sh` | 2 | Add scanner venv setup (~25 lines) |
| `scripts/uninstall.sh` | 5 | Add scanner venv and cache cleanup (~5 lines) |
| `scripts/test-integration.sh` | 4 | Add 6-8 scanner integration tests (~60 lines) |
| `CLAUDE.md` | 5 | Document scanner in Scripts, Configs, Roadmap, Troubleshooting (~40 lines) |

---

## Context Alignment

### CLAUDE.md Patterns Followed

1. **Scripts in `scripts/` directory** -- The scanner follows the established pattern of standalone scripts (`emit-audit-event.sh`, `compute-run-score.sh`, `score-reflector.sh`).
2. **Python with no external dependencies (for core functionality)** -- Regex fallback mode has zero dependencies. Tree-sitter is optional and isolated in a venv.
3. **Graceful degradation** -- Follows the same pattern as security skills: available when deployed, warnings when not. Scanner available when tree-sitter installed, regex fallback when not.
4. **Integration testing in `test-integration.sh`** -- New tests follow the existing `run_test()` pattern with numbered tests, expected exit codes, and the existing color-coded output format.
5. **Conventional commits** -- All commits follow `feat(scope):` / `test(scope):` / `docs:` patterns documented in CLAUDE.md.
6. **Configs in `configs/` directory** -- Language configuration follows the pattern of `skill-patterns.json` and `score-dimensions.json`.
7. **Atomic writes** -- Cache file uses atomic write (write to temp, `os.rename()`) to prevent partial reads from concurrent access -- a general best practice applied to cache file I/O.
8. **Exit code conventions** -- 0 for success, 1 for fatal error, 2 for invalid arguments (same as `validate_skill.py`).
9. **Scanner invoked via `$CLAUDE_DEVKIT` env var** -- Follows the env var set by `install.sh`, consistent with how generators are already referenced. `deploy.sh` scope is unchanged.
10. **Audit event logging** -- Scanner invocations are logged via `emit-audit-event.sh` (same pattern as `/ship`, `/architect`, `/audit`).

### Prior Plans This Builds Upon

1. **devkit-hygiene-improvements.md** (APPROVED) -- Established the integration test infrastructure in `test-integration.sh` that the scanner tests extend.
2. **agentic-sdlc-security-skills.md** (APPROVED) -- Established the pattern of conditional skill invocation in `/ship` (security gates run only if skills are deployed). The scanner follows the same pattern: invoked only if available.
3. **audit-remove-mcp-deps.md** (APPROVED) -- Established the precedent of keeping scripts standalone rather than introducing service dependencies.

### Deviations from Established Patterns

1. **New directory: `~/.claude-devkit/`** -- The scanner venv lives at `~/.claude-devkit/scanner-venv/` and the cache at `~/.claude-devkit/cache/`. This is a new user-scoped directory. This is justified because:
   - The venv cannot live in the project (would be project-specific, redundant across projects).
   - The venv cannot live in `~/.claude/` (that directory is owned by Claude Code, not claude-devkit).
   - The cache cannot live in the project root (trust boundary violation -- see F-03 in Revision Log).
   - `~/.claude-devkit/` is a clean namespace for claude-devkit user-scoped resources.

2. **First standalone `.py` file in `scripts/`** -- All existing scripts in `scripts/` are `.sh` files. The Python-in-scripts precedent is bash scripts wrapping embedded `python3 -c` blocks (`compute-run-score.sh`, `score-reflector.sh`), not standalone `.py` files. `codebase-scanner.py` is the first standalone `.py` file in this directory. This is justified by the complexity of tree-sitter integration, the structured data model with multiple classes, and the ~800+ line size -- the bash-wrapping-embedded-python pattern would be unwieldy at this scale.

---

## Future Evolution

### Caller/Call-Site Detection (v2)

Caller detection was deferred from v1 due to false positive risk with string-matching approaches (see C-02 in Revision Log). v2 caller detection options:

1. **tree-sitter scope-aware matching:** Use the AST to resolve symbol references within their lexical scope, reducing false positives from common names.
2. **SymbolDelta for Code Review:** Compute a diff between pre-change and post-change symbol indexes, providing the code reviewer with added/removed/renamed symbols, changed signatures, and modified import graph edges. This is the `SymbolDelta` concept from the balor-fianna ADR.
3. **Import-path-qualified references:** For Python, match `module.symbol` rather than just `symbol`. For TypeScript, trace imports to resolve which `get()` is which.

### MCP Server (v2, not in scope)

The scanner's `SymbolIndex` data model is designed to be exposed via MCP tools in a future iteration:
- `list_symbols(file?: string, kind?: string)` -- List symbols, optionally filtered.
- `get_dependencies(file: string)` -- Get import graph for a file.
- `find_pattern(query: string)` -- tree-sitter query for vulnerability patterns.

The MCP server would live in the `helper-mcps` monorepo (following the migration documented in CLAUDE.md) and consume the scanner as a library.

### Incremental Updates (v2)

File-watcher integration for real-time index updates within a Claude Code session. Not needed for v1 (run-once-per-invocation with caching is sufficient).

---

<!-- Context Metadata
discovered_at: 2026-05-25T11:24:00Z
revised_at: 2026-05-25T14:30:00Z
claude_md_exists: true
recent_plans_consulted: agentic-sdlc-security-skills.md, audit-remove-mcp-deps.md, devkit-hygiene-improvements.md
archived_plans_consulted: agentic-sdlc-next-phase.feasibility.md, agentic-sdlc-next-phase.secure-review.md
-->
