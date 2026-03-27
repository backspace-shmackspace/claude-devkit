# Plan: deep-code-security

## Status: APPROVED

## Context

**Problem:** Claude Code's `/audit` skill performs LLM-based code review -- effective for high-level pattern recognition but limited by the model's inability to perform deterministic static analysis. It cannot parse ASTs, trace dataflow through call graphs, or verify exploitability. A dedicated deep code security analysis product would complement `/audit` by providing tree-sitter-based SAST with taint tracking, sandbox-verified exploit validation, and structured remediation guidance.

**Current state:** No prior work exists. The `/audit` skill (v3.0.0) in claude-devkit provides security scanning via LLM pattern matching. The helper-mcps monorepo at `~/projects/workspaces/helper-mcps/` provides the MCP server blueprint (BaseMCPServer, CredentialProvider, lifecycle state machines, Docker multi-stage builds). This plan creates a new standalone project at `~/projects/deep-code-security/`.

**Constraints:**
- Separate repository from claude-devkit (different lifecycle, deployment, dependencies)
- Must expose an MCP server interface so Claude Code can invoke it
- v1 supports Python and Go via tree-sitter grammars (C as stretch goal); Java and Rust deferred to v1.1
- Exploit verification must run in a containerized sandbox (security boundary) with a fully specified security policy
- MCP server runs natively on the host (stdio transport), not inside a container
- Docker CLI commands are not in the Claude Code tool allowlist and will require manual permission grants during skill execution or build steps
- Thin `/deep-scan` skill in claude-devkit orchestrates the MCP tools
- Must produce structured JSON at every phase for agent consumption

**Known Limitations (v1):**
- **Intraprocedural taint tracking only.** v1 traces dataflow within single functions. In real-world web applications, sources (request handlers) and sinks (database calls) are almost always in different functions separated by 2-3+ call boundaries. v1 will primarily detect "direct" patterns like `cursor.execute("SELECT * FROM " + request.form["id"])` where source and sink are in the same function. Expected detection rate on real-world injection vulnerabilities: **10-25%**. The primary value of v1 is proving the architecture works, not competing with commercial SAST tools.
- **Tree-sitter query brittleness.** Queries match specific AST shapes. Aliased imports (`req = request; req.form`), fully-qualified names (`flask.request.form`), class attribute access (`self.request.form`), and chained calls (`request.form.get("key")`) will produce different AST structures that v1 queries may not cover. Registries target 5-8 well-tested source patterns and 5-8 well-tested sink patterns per language.
- **Exploit verification is a bonus signal, not a penalty.** Most template-based PoCs will fail due to missing execution context (framework setup, dependency injection, state initialization), not because the vulnerability is false. Failed PoCs do not reduce confidence.
- **Cross-language taint tracking is out of scope.** v1 treats each language independently within a scan. Python calling a C extension via FFI, or Go calling C via cgo, is not analyzed.

## Architectural Analysis

### Key Architectural Drivers

1. **Deterministic analysis** -- Tree-sitter provides guaranteed AST parsing; no LLM hallucination of code structure
2. **Multi-language uniformity** -- One taint engine, per-language grammar + registry. Adding a language means adding a YAML file and a tree-sitter grammar, not rewriting the engine.
3. **Verification over heuristics** -- The Auditor phase attempts real exploitation in a sandbox, converting probability into evidence (as a bonus signal)
4. **Agent-native interface** -- MCP tools return structured JSON that Claude Code agents can consume and reason over
5. **Defense in depth for the tool itself** -- The sandbox that verifies exploits must be hardened against the very exploits it tests

### Requirements

| Requirement | Priority | Rationale |
|-------------|----------|-----------|
| Tree-sitter AST parsing for Python and Go (C stretch) | P0 | Core value proposition, scoped to realistic v1 |
| Source/sink YAML registries per language | P0 | Extensibility without code changes |
| Intraprocedural taint tracking | P0 | Minimum viable dataflow analysis |
| Interprocedural taint tracking (call graph) | P1 | Required for real-world vuln detection (v1.1) |
| Containerized exploit sandbox with full security policy | P0 | Security boundary for PoC execution |
| MCP server interface (native stdio, not containerized) | P0 | Integration with Claude Code |
| `/deep-scan` skill in claude-devkit | P1 | Orchestration layer |
| Confidence scoring model (exploit as bonus signal) | P1 | Signal quality for agent decision-making |
| Structured JSON output at every phase | P0 | Agent consumption |
| Remediation guidance (not apply-ready patches) | P1 | Actionable output without trust erosion |
| Path validation with configurable allowlist | P0 | Prevent arbitrary filesystem reads |
| Input size limits and pagination | P0 | Prevent resource exhaustion |

### Trade-offs

| Decision | Option A | Option B | Choice | Rationale |
|----------|----------|----------|--------|-----------|
| Parsing framework | tree-sitter | Language-specific parsers (ast, javac) | tree-sitter | Uniform API, one engine for all languages. Trade-off: tree-sitter queries are less precise than native ASTs for some languages. |
| Taint tracking scope | Intraprocedural only (v1) | Full interprocedural from day 1 | Intraprocedural first | Ship faster, iterate. Interprocedural requires call graph construction which is a significant effort. v1 catches ~10-25% of real injection vulns. |
| Sandbox technology | Docker containers | gVisor/Firecracker | Docker | Available everywhere, well-understood. Hardened with seccomp + no-new-privileges + AppArmor. gVisor is a future enhancement for higher-risk deployments. |
| MCP server deployment | Native stdio process | Containerized with Docker socket | **Native stdio** | Running the MCP server inside a container with Docker socket access grants root-equivalent host access. Native stdio eliminates this attack surface entirely. The MCP server invokes Docker CLI to create sandbox containers. |
| Project location | Inside helper-mcps monorepo | Standalone repo | Standalone | Different domain, different dependencies (tree-sitter grammars, Docker SDK). Would bloat helper-mcps. |
| Language for core tooling | Python | Rust | Python | Consistency with helper-mcps, tree-sitter Python bindings are mature, faster iteration. Trade-off: slower than Rust for large codebases. |
| v1 language scope | 5 languages (Python, Java, C, Rust, Go) | 2-3 languages (Python, Go, C stretch) | **2-3 languages** | 5 languages in the original timeline is infeasible. Each registry needs 1-2 days of iterative testing. Python + Go covers web and systems; C adds memory safety patterns as a stretch goal. Java and Rust deferred to v1.1. |
| Architect output | Apply-ready diffs | Remediation guidance with code examples | **Remediation guidance** | Apply-ready patches are frequently wrong due to library-specific syntax (SQLAlchemy vs psycopg2), cascading caller changes, and multi-finding conflicts. Guidance with code examples avoids trust erosion. |
| Exploit verification weight | 40% of confidence score | 10% bonus-only signal | **10% bonus-only** | Most template PoCs fail due to missing execution context, not because the vuln is false. Penalizing real vulns when PoCs fail undermines the confidence model. |

## Recommended Approach

### High-Level Architecture

```
deep-code-security/
|
|   # Core library
|-- src/
|   |-- deep_code_security/
|   |   |-- __init__.py
|   |   |-- cli.py                      # CLI entry point (standalone usage)
|   |   |
|   |   |-- hunter/                     # Phase 1: Discovery Agent
|   |   |   |-- __init__.py
|   |   |   |-- parser.py               # Tree-sitter AST parsing (multi-language)
|   |   |   |-- registry.py             # YAML source/sink registry loader + query validation
|   |   |   |-- source_sink_finder.py   # AST walker that matches sources and sinks
|   |   |   |-- taint_tracker.py        # Intraprocedural taint propagation engine
|   |   |   |-- call_graph.py           # Interprocedural call graph builder (v1.1 stub)
|   |   |   |-- models.py               # Pydantic models (Finding, Source, Sink, TaintPath)
|   |   |   |-- orchestrator.py         # Hunter phase orchestration
|   |   |   |-- grammars/               # Tree-sitter grammar bindings (installed, not vendored)
|   |   |   |-- queries/                # Tree-sitter query patterns per language
|   |   |   |   |-- python.scm
|   |   |   |   |-- go.scm
|   |   |   |   |-- c.scm               # Stretch goal
|   |   |   |
|   |   |-- auditor/                    # Phase 2: Verification Agent
|   |   |   |-- __init__.py
|   |   |   |-- sandbox.py              # Docker sandbox manager (invokes Docker CLI natively)
|   |   |   |-- exploit_generator.py    # PoC script generation with input sanitization
|   |   |   |-- verifier.py             # Exploit execution and result parsing
|   |   |   |-- confidence.py           # Confidence scoring model (exploit as bonus)
|   |   |   |-- models.py               # Pydantic models (VerifiedFinding, ExploitResult)
|   |   |   |-- orchestrator.py         # Auditor phase orchestration
|   |   |   |-- seccomp-profile.json    # Custom seccomp profile for sandbox containers
|   |   |   |
|   |   |-- architect/                  # Phase 3: Remediation Agent
|   |   |   |-- __init__.py
|   |   |   |-- guidance_generator.py   # Remediation guidance generation (not apply-ready diffs)
|   |   |   |-- dependency_analyzer.py  # Dependency manifest parser
|   |   |   |-- impact_analyzer.py      # Cross-file impact analysis
|   |   |   |-- models.py               # Pydantic models (RemediationGuidance, DependencyImpact)
|   |   |   |-- orchestrator.py         # Architect phase orchestration
|   |   |   |
|   |   |-- mcp/                        # MCP Server (runs natively, not containerized)
|   |   |   |-- __init__.py
|   |   |   |-- __main__.py             # Entry point with lifecycle
|   |   |   |-- server.py               # DeepCodeSecurityMCPServer (BaseMCPServer subclass)
|   |   |   |-- path_validator.py       # Path allowlist validation with symlink resolution
|   |   |   |-- input_validator.py      # RawFinding field sanitization
|   |   |   |
|   |   |-- shared/                     # Internal shared utilities
|   |   |   |-- __init__.py
|   |   |   |-- language.py             # Language detection (file extension mapping)
|   |   |   |-- file_discovery.py       # Recursive file discovery with .gitignore respect
|   |   |   |-- json_output.py          # Structured JSON serialization helpers
|   |   |   |-- config.py               # Global configuration (registry paths, sandbox settings, allowed paths)
|   |   |
|-- registries/                         # YAML source/sink definitions
|   |-- python.yaml
|   |-- go.yaml
|   |-- c.yaml                          # Stretch goal
|   |-- README.md                       # Registry format documentation
|   |
|-- sandbox/                            # Sandbox Docker images
|   |-- Dockerfile.python               # Python exploit runner
|   |-- Dockerfile.go                   # Go exploit runner
|   |-- Dockerfile.c                    # C exploit runner (stretch goal)
|   |-- entrypoint.sh                   # Sandbox execution wrapper (timeout, resource limits)
|   |-- seccomp-default.json            # Seccomp profile for sandbox containers
|   |
|-- tests/
|   |-- __init__.py
|   |-- conftest.py                     # Shared fixtures (sample ASTs, mock registries)
|   |-- test_hunter/
|   |-- test_auditor/
|   |-- test_architect/
|   |-- test_mcp/
|   |-- test_integration/
|   |-- fixtures/
|   |   |-- vulnerable_samples/        # Known-vulnerable code samples per language
|   |   |   |-- python/
|   |   |   |-- go/
|   |   |   |-- c/                      # Stretch goal
|   |   |-- safe_samples/              # Known-safe code (false positive tests)
|   |   |   |-- python/
|   |   |   |-- go/
|   |
|-- pyproject.toml
|-- Makefile
|-- CLAUDE.md
|-- README.md
|-- .gitignore
```

### Data Flow

```
Target Codebase (path -- validated against allowlist)
        |
        v
  +------------------+
  |    HUNTER         |  tree-sitter parse -> source/sink match -> taint track
  |  (Discovery)      |  Output: RawFinding[] (JSON, paginated)
  +------------------+
        |
        v
  +------------------+
  |    AUDITOR        |  For each finding (max N): generate PoC -> sanitize -> run in sandbox -> score
  |  (Verification)   |  Output: VerifiedFinding[] (JSON) with confidence 0-100
  +------------------+  Exploit verification is bonus-only (10% weight)
        |
        v
  +------------------+
  |    ARCHITECT      |  For each verified finding: analyze context -> generate guidance
  |  (Remediation)    |  Output: RemediationGuidance[] (JSON) with explanation + code examples
  +------------------+
        |
        v
  Structured Report (JSON + Markdown summary)
```

### MCP Tool Interface

The MCP server exposes 5 tools. The server runs as a **native stdio process** on the host (not containerized). It invokes Docker/Podman CLI to create sandbox containers for exploit verification.

| Tool | Description | Input | Output |
|------|-------------|-------|--------|
| `deep_scan_hunt` | Run Hunter phase (AST parse + taint track) | `{ path: string, languages?: string[], severity_threshold?: string, max_results?: int, offset?: int }` | `{ findings: RawFinding[], stats: ScanStats, total_count: int, has_more: bool }` |
| `deep_scan_verify` | Run Auditor phase on findings | `{ findings: RawFinding[], sandbox_timeout?: int, max_verifications?: int }` | `{ verified: VerifiedFinding[], stats: VerifyStats }` |
| `deep_scan_remediate` | Run Architect phase on verified findings | `{ verified: VerifiedFinding[], target_path: string }` | `{ guidance: RemediationGuidance[], stats: RemediateStats }` |
| `deep_scan_full` | Run all three phases sequentially | `{ path: string, languages?: string[], severity_threshold?: string, max_results?: int, max_verifications?: int }` | `{ findings: RawFinding[], verified: VerifiedFinding[], guidance: RemediationGuidance[] }` |
| `deep_scan_status` | Check sandbox health and registry info | `{}` | `{ sandbox_available: bool, registries: string[], languages: string[] }` |

### Key Data Models (Pydantic v2)

```python
class Source(BaseModel):
    """A user input entry point."""
    file: str
    line: int
    column: int
    function: str          # e.g., "request.form.get"
    category: str          # e.g., "web_input", "cli_input", "file_read"
    language: str

class Sink(BaseModel):
    """A dangerous function call."""
    file: str
    line: int
    column: int
    function: str          # e.g., "os.system", "eval"
    category: str          # e.g., "command_injection", "sql_injection", "code_execution"
    language: str

class TaintPath(BaseModel):
    """A dataflow path from source to sink."""
    steps: list[TaintStep]  # Each step: file, line, variable, transform

class RawFinding(BaseModel):
    """A potential vulnerability discovered by the Hunter."""
    id: str                 # UUID
    source: Source
    sink: Sink
    taint_path: TaintPath
    vulnerability_class: str  # CWE category (e.g., "CWE-78: OS Command Injection")
    severity: str             # Critical / High / Medium / Low (from registry)
    language: str
    raw_confidence: float     # 0.0-1.0 (heuristic, pre-verification)

class ExploitResult(BaseModel):
    """Result of a sandbox exploit attempt."""
    exploit_script_hash: str  # SHA-256 hash (not full script -- avoid storing exploit code in outputs)
    exit_code: int
    stdout_truncated: str     # First 2KB only
    stderr_truncated: str     # First 2KB only
    exploitable: bool
    execution_time_ms: int

class VerifiedFinding(BaseModel):
    """A finding that has been through the Auditor."""
    finding: RawFinding
    exploit_results: list[ExploitResult]
    confidence_score: int    # 0-100
    verification_status: str  # "confirmed", "likely", "unconfirmed", "false_positive"

class RemediationGuidance(BaseModel):
    """Remediation guidance for a vulnerability."""
    finding_id: str
    vulnerability_explanation: str   # What the vulnerability is and why it is dangerous
    fix_pattern: str                 # General fix approach (e.g., "Use parameterized queries")
    code_example: str                # Illustrative code snippet showing the fix concept
    dependency_impact: DependencyImpact | None
    effort_estimate: str             # "trivial", "small", "medium", "large"
    test_suggestions: list[str]
    # NOTE: No before/after diffs. Guidance only.

class DependencyImpact(BaseModel):
    """Impact of a fix on project dependencies."""
    manifest_file: str       # e.g., "requirements.txt", "go.mod"
    current_deps: list[str]
    required_changes: list[str]  # New deps or version bumps needed
    breaking_risk: str       # "none", "minor", "major"
```

### YAML Registry Format

Each language gets a registry file defining its sources and sinks:

```yaml
# registries/python.yaml
language: python
version: "1.0.0"

sources:
  web_input:
    - pattern: "request.form"
      tree_sitter_query: "(attribute object: (identifier) @obj attribute: (identifier) @attr (#eq? @obj \"request\") (#eq? @attr \"form\"))"
      severity: high
    - pattern: "request.args"
      tree_sitter_query: "(attribute object: (identifier) @obj attribute: (identifier) @attr (#eq? @obj \"request\") (#eq? @attr \"args\"))"
      severity: high
  cli_input:
    - pattern: "sys.argv"
      tree_sitter_query: "(attribute object: (identifier) @obj attribute: (identifier) @attr (#eq? @obj \"sys\") (#eq? @attr \"argv\"))"
      severity: medium
    - pattern: "input()"
      tree_sitter_query: "(call function: (identifier) @fn (#eq? @fn \"input\"))"
      severity: medium

sinks:
  command_injection:
    cwe: "CWE-78"
    entries:
      - pattern: "os.system"
        tree_sitter_query: "(attribute object: (identifier) @obj attribute: (identifier) @attr (#eq? @obj \"os\") (#eq? @attr \"system\"))"
        severity: critical
      - pattern: "subprocess.call"
        tree_sitter_query: "(attribute object: (identifier) @obj attribute: (identifier) @attr (#eq? @obj \"subprocess\") (#match? @attr \"^(call|run|Popen|check_output|check_call)$\"))"
        severity: critical
  sql_injection:
    cwe: "CWE-89"
    entries:
      - pattern: "cursor.execute"
        tree_sitter_query: "(call function: (attribute object: (identifier) @obj attribute: (identifier) @attr (#eq? @attr \"execute\")) arguments: (argument_list (binary_operator)))"
        severity: critical
  code_execution:
    cwe: "CWE-94"
    entries:
      - pattern: "eval"
        tree_sitter_query: "(call function: (identifier) @fn (#eq? @fn \"eval\"))"
        severity: critical
      - pattern: "exec"
        tree_sitter_query: "(call function: (identifier) @fn (#eq? @fn \"exec\"))"
        severity: critical

# NOTE: v1 queries target direct patterns only. Known gaps:
# - Aliased imports (req = request; req.form) -- not matched
# - Fully qualified (flask.request.form) -- not matched
# - Class attribute (self.request.form) -- not matched
# - Chained calls (request.form.get("key")) -- partial match only
# These gaps are documented and expected. See Known Limitations.

sanitizers:
  - pattern: "shlex.quote"
    neutralizes: ["command_injection"]
  - pattern: "parameterized query"
    neutralizes: ["sql_injection"]
    description: "Using ? or %s placeholders with separate args tuple"
```

### Confidence Scoring Model

The confidence score (0-100) is computed as a weighted composite. **Exploit verification is a bonus-only signal** -- it can increase confidence but a failed PoC does not penalize a finding. This reflects the reality that most template-based PoCs fail due to missing execution context, not because the vulnerability is false.

| Factor | Weight | Score Range | Description |
|--------|--------|-------------|-------------|
| Taint path completeness | 45% | 0-100 | Full path (100), partial (50), heuristic only (20) |
| Sanitizer absence | 25% | 0-100 | No sanitizer found (100), partial sanitizer (50), full sanitizer (0) |
| CWE severity baseline | 20% | 0-100 | Critical CWE (100), High (75), Medium (50), Low (25) |
| Exploit verification | 10% | 0-100 | **Bonus only**: Confirmed exploitable adds 10 points. Failed/inconclusive adds 0 (no penalty). |

Formula: `base_confidence = 0.45 * taint + 0.25 * sanitizer + 0.20 * cwe_baseline`
Bonus: `confidence = base_confidence + (0.10 * exploit_score if exploit_score > 0 else 0)`

Thresholds:
- `>= 75`: "confirmed" -- high confidence, should be fixed
- `>= 45`: "likely" -- probably real, warrants investigation
- `>= 20`: "unconfirmed" -- possible but unverified
- `< 20`: "false_positive" -- likely not exploitable

### Sandbox Architecture and Security Policy

The MCP server runs as a **native stdio process** on the host. It invokes Docker (or Podman rootless) to create isolated sandbox containers for exploit verification. This eliminates the Docker socket mount attack vector entirely.

```
Host Machine
  |
  +-- MCP Server (native Python process, stdio transport)
  |     - Runs as current user
  |     - Invokes Docker CLI (or Podman) to create sandbox containers
  |     - Path validation: only scans directories in DCS_ALLOWED_PATHS
  |     - Input validation: sanitizes all RawFinding fields before template interpolation
  |     - Rate limiting: max DCS_MAX_CONCURRENT_SANDBOXES containers (default: 2)
  |     - Audit logging: all tool invocations logged with timestamp, tool, params, result count
  |
  +-- Docker/Podman daemon
       |
       +-- deep-code-security-sandbox-python:latest
       |     - Python 3.12-slim
       |     - No network (--network=none)
       |     - Read-only filesystem (--read-only)
       |     - tmpfs for /tmp (writable, noexec, nosuid, size=64m)
       |     - 512MB memory limit (--memory=512m)
       |     - 30s execution timeout (configurable)
       |     - Non-root user (--user=65534:65534)
       |     - No capabilities (--cap-drop=ALL)
       |     - No new privileges (--security-opt=no-new-privileges)
       |     - Custom seccomp profile (--security-opt seccomp=seccomp-default.json)
       |     - PID limit (--pids-limit=64)
       |     - Target code mounted read-only at /target
       |     - PoC script mounted read-only at /exploit/poc.py
       |     - No access to .env, .git/config, credential files
       |
       +-- deep-code-security-sandbox-go:latest
       |     - golang:1.22-alpine base
       |     - (Same security constraints as above)
       |
       +-- deep-code-security-sandbox-c:latest  (stretch goal)
             - gcc:12-slim base
             - (Same security constraints as above)
```

**Sandbox security policy (mandatory for all containers):**

1. `--network=none` -- No network access; exploits cannot phone home or pivot
2. `--read-only` -- Read-only root filesystem
3. `--tmpfs /tmp:rw,noexec,nosuid,size=64m` -- Writable temp with noexec enforced (PoC executes via interpreter, not direct binary execution)
4. `--cap-drop=ALL` -- No Linux capabilities
5. `--security-opt=no-new-privileges` -- Prevent privilege escalation via setuid/setgid
6. `--security-opt seccomp=seccomp-default.json` -- Custom seccomp profile whitelisting only syscalls needed by the language runtime (read, write, open, close, mmap, etc.; blocks ptrace, mount, reboot, etc.)
7. `--pids-limit=64` -- Prevent fork bombs
8. `--memory=512m` -- Memory ceiling
9. `--user=65534:65534` -- Run as nobody
10. Target code mounted read-only at `/target` -- exploit cannot modify analyzed code
11. PoC script mounted read-only at `/exploit/` -- script provided by host, not writable by container
12. `.env`, `.git/config`, `*.pem`, `*.key`, `id_rsa*` excluded from mounts via explicit exclude list

**Container runtime preference:** Podman rootless is preferred when available (avoids the Docker daemon entirely). Docker is supported with the security policy above. The `DCS_CONTAINER_RUNTIME` env var controls selection (default: auto-detect, prefer podman).

### Path Validation

All MCP tools that accept filesystem paths enforce validation:

1. **Allowlist:** Paths must be within directories listed in `DCS_ALLOWED_PATHS` (comma-separated, defaults to current working directory)
2. **Symlink resolution:** `os.path.realpath()` is called before validation; resolved path must still be within the allowlist
3. **Path traversal prevention:** Paths containing `..` after normalization are rejected
4. **No special files:** Reject paths to `/proc`, `/sys`, `/dev`, block devices, and named pipes
5. **File count limit:** `DCS_MAX_FILES` (default: 10,000) caps the number of files scanned per invocation
6. **Symlink cycle detection:** File discovery does not follow symlinks outside the target root

### Input Validation for Exploit Generation

All `RawFinding` fields are validated before template interpolation in the exploit generator:

1. **Function names:** Must match `^[a-zA-Z_][a-zA-Z0-9_.]*$` (reject anything with shell metacharacters, quotes, semicolons)
2. **File paths:** Must match `^[a-zA-Z0-9_/.\-]+$` and pass path validation
3. **Variable names:** Must match `^[a-zA-Z_][a-zA-Z0-9_]*$`
4. **Template engine:** Use Jinja2 with `SandboxedEnvironment` and autoescaping rather than Python string formatting
5. **Finding provenance:** `deep_scan_verify` only accepts finding IDs that reference a previous `deep_scan_hunt` result stored server-side (in-memory session store). External callers cannot inject arbitrary findings.

### `/deep-scan` Skill Design

The `/deep-scan` skill in claude-devkit follows the **Scan archetype** (like `/audit`):

```
Step 0 -- Determine scope and validate prerequisites
Step 1 -- Run Hunter (MCP: deep_scan_hunt) -- paginate if results exceed max_results
Step 2 -- Run Auditor (MCP: deep_scan_verify) -- conditional on Docker availability, max 50 verifications
Step 3 -- Run Architect (MCP: deep_scan_remediate)
Step 4 -- Synthesis (coordinator reads all outputs)
Step 5 -- Verdict gate (PASS / PASS_WITH_NOTES / BLOCKED based on confirmed findings)
Step 6 -- Archive on completion
```

## Goals

1. Build a working tree-sitter-based SAST engine supporting Python and Go (C as stretch goal)
2. Implement source/sink matching via YAML registries with tree-sitter queries (5-8 patterns per language)
3. Implement intraprocedural taint tracking with explicit detection rate expectations (~10-25%)
4. Build containerized sandbox for exploit verification with fully specified security policy
5. Expose all functionality via MCP server (native stdio transport, with path validation and input sanitization)
6. Create `/deep-scan` skill in claude-devkit for orchestration
7. Produce structured JSON at every phase with pagination support
8. Achieve 90% test coverage

## Non-Goals

1. **Replacing commercial SAST tools** -- This is a complement to LLM-based review, not a replacement for Snyk/Semgrep/CodeQL
2. **Full interprocedural analysis in v1** -- Call graph construction across files is deferred to v1.1
3. **Dynamic instrumentation (DAST/IAST)** -- Out of scope; the Auditor phase uses static PoC generation, not runtime instrumentation
4. **UI/dashboard** -- CLI and MCP interface only; no web frontend
5. **Custom tree-sitter grammar development** -- Using existing community grammars only
6. **Support for languages beyond Python, Go, and C in v1** -- Java, Rust, TypeScript, PHP, Ruby, etc. are v1.1+
7. **Real-time / incremental scanning** -- Full scan each invocation; no file-watching mode
8. **Apply-ready patches** -- Architect phase produces remediation guidance with code examples, not auto-applicable diffs
9. **Cross-language taint tracking** -- Each language analyzed independently; FFI boundaries not traced

## Assumptions

1. Docker or Podman (preferably rootless) is available on the host machine for sandbox execution
2. Python 3.12+ is the runtime (consistent with helper-mcps)
3. tree-sitter Python bindings (`tree-sitter>=0.23` with individual grammar packages `tree-sitter-python`, `tree-sitter-go`, `tree-sitter-c`) are compatible -- **must be validated by dependency spike before Phase 1**
4. The MCP SDK (`mcp` package) is available at version >=1.26.0
5. The helper-mcps `shared/` library (at `~/projects/workspaces/helper-mcps/`) can be vendored for BaseMCPServer, logging, lifecycle patterns
6. Claude Code agents can invoke MCP tools and process structured JSON responses
7. The Auditor's exploit generation will use template-based PoCs with Jinja2 sandboxed templates, with LLM-assisted generation as a future enhancement
8. Target codebases are local (no remote repository cloning in v1)
9. Docker CLI commands will trigger Claude Code permission prompts (not in the tool allowlist)

## Proposed Design

### Component Details

#### 1. Hunter (Discovery Agent)

**Input:** Directory path (validated against allowlist), optional language filter, optional severity threshold, pagination params

**Process:**
1. **Path validation:** Validate path against `DCS_ALLOWED_PATHS`, resolve symlinks, reject traversal attempts
2. **File discovery:** Walk the target directory, respect `.gitignore`, identify language by extension, enforce `DCS_MAX_FILES` limit, do not follow symlinks outside target root
3. **AST parsing:** For each file, parse with the appropriate tree-sitter grammar
4. **Source/sink matching:** Run tree-sitter queries from the language's YAML registry against the AST
5. **Taint tracking (intraprocedural):**
   - For each source found, track variable assignments and transformations within the same function
   - Use a worklist algorithm: start from source, follow assignments (`x = source_var`), function arguments, string concatenations
   - Mark variables as tainted, propagate through the function body
   - When a tainted variable reaches a sink, record the full path
6. **Output:** Paginated list of `RawFinding` objects serialized as JSON, with `total_count` and `has_more`

**Key implementation details:**
- `parser.py` wraps `tree_sitter.Parser` with grammar loading per language
- `registry.py` loads YAML files, validates schema, **compiles and validates tree-sitter queries at load time** (reject malformed queries), caches compiled queries, enforces query execution timeouts and result size caps
- `source_sink_finder.py` runs tree-sitter queries against AST nodes
- `taint_tracker.py` implements the worklist algorithm with a `TaintState` that maps variable names to taint status within a function scope
- Files are processed sequentially and ASTs released after each file to bound memory

#### 2. Auditor (Verification Agent)

**Input:** List of `RawFinding` objects (validated via session store, not raw external JSON), sandbox configuration

**Process:**
1. **Finding validation:** Verify each finding ID references a previous `deep_scan_hunt` result in the server-side session store. Reject externally-crafted findings.
2. **Input sanitization:** Validate all RawFinding fields (function names, file paths, variable names) against strict regex patterns before any template use.
3. **PoC generation:** For each finding (up to `max_verifications`, default 50), generate an exploit script using Jinja2 `SandboxedEnvironment`:
   - SQL injection: Script that passes `'; DROP TABLE users; --` through the source path
   - Command injection: Script that passes `; id` through the source path
   - Path traversal: Script that passes `../../etc/passwd` through the source path
   - Each template is parameterized with the validated source/sink from the finding
4. **Sandbox execution:** Run the appropriate language sandbox container with full security policy:
   - Mount target code read-only (excluding .env, credentials, .git/config)
   - Mount PoC script read-only
   - Apply seccomp profile, no-new-privileges, PID limits
   - Execute with timeout and resource limits
   - Capture stdout, stderr (truncated to 2KB), exit code
5. **Confidence scoring:** Apply the weighted model with exploit as bonus-only signal
6. **Output:** List of `VerifiedFinding` objects (exploit scripts stored as SHA-256 hashes, not full text)

**Key implementation details:**
- `exploit_generator.py` uses Jinja2 `SandboxedEnvironment` for template rendering, with strict field validation before interpolation
- `sandbox.py` manages Docker/Podman container lifecycle via subprocess (not Docker SDK with socket), applies full security policy from `seccomp-default.json`
- `verifier.py` orchestrates generation -> execution -> scoring
- `confidence.py` implements the bonus-only scoring formula
- Concurrency limited by `DCS_MAX_CONCURRENT_SANDBOXES` semaphore (default: 2)

#### 3. Architect (Remediation Agent)

**Input:** List of `VerifiedFinding` objects, target path (validated against allowlist)

**Process:**
1. **Context gathering:** For each finding, read the surrounding code context (function, class, module) from validated paths only
2. **Guidance generation:** Generate remediation guidance (NOT apply-ready diffs):
   - Vulnerability explanation: what it is, why it is dangerous, CWE reference
   - General fix pattern: e.g., "Use parameterized queries instead of string concatenation"
   - Code example: illustrative snippet showing the fix concept (not a patch against the actual code)
   - Language- and library-specific notes where applicable
3. **Dependency analysis:** Parse manifest files to check if fixes require new dependencies
4. **Impact analysis:** Identify other call sites of the affected function
5. **Output:** List of `RemediationGuidance` objects

**Key implementation details:**
- `guidance_generator.py` produces explanatory guidance with code examples, not before/after diffs
- `dependency_analyzer.py` parses requirements.txt, pyproject.toml, go.mod
- `impact_analyzer.py` uses tree-sitter to find all call sites of the affected function

### Integration with helper-mcps Patterns

The MCP server follows the helper-mcps architecture (vendored from `~/projects/workspaces/helper-mcps/`):

1. **Inherits BaseMCPServer** from shared/ (vendored copy with `VENDORED_FROM.md` noting source commit hash; Makefile includes `check-vendor` target that compares against upstream HEAD)
2. **Lifecycle state machine:** INITIALIZING -> SERVICE_VALIDATED -> STDIO_VALIDATED -> READY -> SHUTTING_DOWN -> STOPPED
3. **Structured logging to stderr** via `configure_logging()`
4. **Pydantic v2 models** for all data structures
5. **ToolError returns** with `retryable` flag on failures
6. **Runs natively as stdio process** (no Docker container for the MCP server itself)
7. **Audit logging:** All tool invocations logged with timestamp, tool name, input parameters, finding count, verdict, and duration

### Trust Model

The MCP server uses stdio transport. The trust model is:

1. **Trust boundary:** The process that spawns the MCP server is trusted (Claude Code or CLI user)
2. **Primary access control:** Input validation (path allowlists, finding schema validation, field sanitization)
3. **Defense in depth:** Sandbox security policy limits blast radius of any exploit code
4. **No authentication on tools:** Consistent with all stdio MCP servers. Any process that can spawn the server can invoke all tools.
5. **Rate limiting:** Concurrency semaphore on sandbox execution prevents resource exhaustion
6. **Audit trail:** All invocations logged with full parameters for forensic review
7. **`~/.claude/settings.json` is a trust root:** Its integrity must be maintained by the user

### Integration with claude-devkit

The `/deep-scan` skill lives at `~/projects/claude-devkit/skills/deep-scan/SKILL.md` and follows the Scan archetype pattern. It invokes the MCP tools via Claude Code's MCP integration.

## Interfaces / Schema Changes

### MCP Tool Schemas

#### `deep_scan_hunt`
```json
{
  "input": {
    "type": "object",
    "properties": {
      "path": { "type": "string", "description": "Absolute path to target codebase (must be in DCS_ALLOWED_PATHS)" },
      "languages": { "type": "array", "items": { "type": "string" }, "description": "Filter to specific languages (python, go, c)" },
      "severity_threshold": { "type": "string", "enum": ["critical", "high", "medium", "low"], "description": "Minimum severity to report (default: medium)" },
      "max_results": { "type": "integer", "default": 100, "description": "Maximum findings to return per page" },
      "offset": { "type": "integer", "default": 0, "description": "Pagination offset" }
    },
    "required": ["path"]
  },
  "output": {
    "type": "object",
    "properties": {
      "findings": { "type": "array", "items": { "$ref": "#/RawFinding" } },
      "stats": {
        "type": "object",
        "properties": {
          "files_scanned": { "type": "integer" },
          "files_skipped": { "type": "integer" },
          "languages_detected": { "type": "array", "items": { "type": "string" } },
          "sources_found": { "type": "integer" },
          "sinks_found": { "type": "integer" },
          "taint_paths_found": { "type": "integer" },
          "scan_duration_ms": { "type": "integer" }
        }
      },
      "total_count": { "type": "integer" },
      "has_more": { "type": "boolean" }
    }
  }
}
```

#### `deep_scan_verify`
```json
{
  "input": {
    "type": "object",
    "properties": {
      "finding_ids": { "type": "array", "items": { "type": "string" }, "description": "Finding IDs from a previous deep_scan_hunt (server-side session store)" },
      "sandbox_timeout_seconds": { "type": "integer", "default": 30, "description": "Per-exploit timeout" },
      "max_verifications": { "type": "integer", "default": 50, "description": "Maximum findings to verify (prioritized by severity)" }
    },
    "required": ["finding_ids"]
  },
  "output": {
    "type": "object",
    "properties": {
      "verified": { "type": "array", "items": { "$ref": "#/VerifiedFinding" } },
      "stats": {
        "type": "object",
        "properties": {
          "total_findings": { "type": "integer" },
          "verified_count": { "type": "integer" },
          "skipped_count": { "type": "integer" },
          "confirmed": { "type": "integer" },
          "likely": { "type": "integer" },
          "unconfirmed": { "type": "integer" },
          "false_positives": { "type": "integer" },
          "verification_duration_ms": { "type": "integer" }
        }
      }
    }
  }
}
```

#### `deep_scan_remediate`
```json
{
  "input": {
    "type": "object",
    "properties": {
      "finding_ids": { "type": "array", "items": { "type": "string" }, "description": "Verified finding IDs from deep_scan_verify" },
      "target_path": { "type": "string", "description": "Path to target codebase (validated against DCS_ALLOWED_PATHS)" }
    },
    "required": ["finding_ids", "target_path"]
  },
  "output": {
    "type": "object",
    "properties": {
      "guidance": { "type": "array", "items": { "$ref": "#/RemediationGuidance" } },
      "stats": {
        "type": "object",
        "properties": {
          "total_verified": { "type": "integer" },
          "guidance_generated": { "type": "integer" },
          "dependencies_affected": { "type": "integer" },
          "remediation_duration_ms": { "type": "integer" }
        }
      }
    }
  }
}
```

#### `deep_scan_full`
```json
{
  "input": {
    "type": "object",
    "properties": {
      "path": { "type": "string" },
      "languages": { "type": "array", "items": { "type": "string" } },
      "severity_threshold": { "type": "string", "enum": ["critical", "high", "medium", "low"] },
      "sandbox_timeout_seconds": { "type": "integer", "default": 30 },
      "skip_verification": { "type": "boolean", "default": false, "description": "Skip Auditor phase (faster, less accurate)" },
      "max_results": { "type": "integer", "default": 100 },
      "max_verifications": { "type": "integer", "default": 50 }
    },
    "required": ["path"]
  }
}
```

#### `deep_scan_status`
```json
{
  "input": { "type": "object", "properties": {} },
  "output": {
    "type": "object",
    "properties": {
      "sandbox_available": { "type": "boolean" },
      "container_runtime": { "type": "string", "enum": ["podman", "docker", "none"] },
      "registries_loaded": { "type": "array", "items": { "type": "string" } },
      "languages_supported": { "type": "array", "items": { "type": "string" } },
      "server_version": { "type": "string" },
      "allowed_paths": { "type": "array", "items": { "type": "string" } }
    }
  }
}
```

### Claude Code MCP Configuration

Add to `~/.claude/settings.json` (or project-level):

```json
{
  "mcpServers": {
    "deep-code-security": {
      "command": "python",
      "args": ["-m", "deep_code_security.mcp"],
      "cwd": "/Users/imurphy/projects/deep-code-security",
      "env": {
        "DCS_REGISTRY_PATH": "/Users/imurphy/projects/deep-code-security/registries",
        "DCS_SANDBOX_TIMEOUT": "30",
        "DCS_CONTAINER_RUNTIME": "auto",
        "DCS_ALLOWED_PATHS": "/Users/imurphy/projects",
        "DCS_MAX_FILES": "10000",
        "DCS_MAX_CONCURRENT_SANDBOXES": "2"
      }
    }
  }
}
```

**Note:** The MCP server runs as a native Python process via stdio. It does NOT run inside a Docker container. Docker/Podman is only used for sandbox containers that execute exploit PoCs.

## Data Migration

No data migration required. This is a greenfield project.

## Implementation Plan

### Phase 0: Dependency Spike (tree-sitter compatibility)
**Estimated effort:** 1 day
**Dependencies:** None
**Parallel with:** Nothing (blocking risk)

1. [ ] Write a 20-line test script that:
   - Installs `tree-sitter>=0.23.0`, `tree-sitter-python`, `tree-sitter-go` on Python 3.12
   - Parses a Python file and a Go file
   - Runs a tree-sitter query against each AST
   - Confirms the API works as expected (Language.build, Parser.parse, Node.query)
2. [ ] If `tree-sitter>=0.23` works: proceed with individual grammar packages, pin exact versions in pyproject.toml
3. [ ] If incompatible: determine the correct version matrix and document workarounds
4. [ ] Document results in `~/projects/deep-code-security/SPIKE.md`

### Phase 1: Project Scaffolding and Core Infrastructure
**Estimated effort:** 2-3 days
**Dependencies:** Phase 0 complete
**Parallel with:** Nothing (must complete first)

1. [ ] Create project directory at `~/projects/deep-code-security/`
2. [ ] Create `pyproject.toml` with dependencies:
   - `tree-sitter>=0.23.0` (pinned to exact version from spike)
   - `tree-sitter-python`, `tree-sitter-go` (individual grammar packages, pinned)
   - `tree-sitter-c` (stretch goal, pinned)
   - `pydantic>=2.0.0`
   - `mcp>=1.26.0`
   - `pyyaml>=6.0`
   - `jinja2>=3.1.0` (sandboxed template engine for PoC generation)
   - `pathspec>=0.12.0` (.gitignore parsing)
   - `click>=8.0` (CLI)
   - Dev: `pytest`, `pytest-asyncio`, `pytest-cov`, `ruff`, `bandit`
   - **Not included:** `docker` Python SDK. Sandbox invokes Docker/Podman via subprocess.
3. [ ] Create `Makefile` with targets: `lint`, `test`, `test-hunter`, `test-auditor`, `test-architect`, `test-mcp`, `sast`, `security`, `build`, `clean`, `check-vendor`
4. [ ] Create `.gitignore` (Python standard + test outputs + sandbox artifacts)
5. [ ] Create full directory structure as specified in architecture
6. [ ] Vendor the helper-mcps `shared/` library from `~/projects/workspaces/helper-mcps/` (server_base.py, logging_config.py, lifecycle.py, types.py, auth.py)
   - Vendor into `src/deep_code_security/mcp/shared/` with a `VENDORED_FROM.md` noting the source commit hash
   - Add `check-vendor` Makefile target that compares vendored commit hash against upstream HEAD
7. [ ] Create `src/deep_code_security/__init__.py` with version
8. [ ] Create `src/deep_code_security/shared/language.py` (extension-to-language mapping for python, go, c)
9. [ ] Create `src/deep_code_security/shared/file_discovery.py` (walk directories, respect .gitignore via `pathspec`, enforce `DCS_MAX_FILES`, do not follow symlinks outside target root)
10. [ ] Create `src/deep_code_security/shared/json_output.py` (Pydantic model serialization helpers)
11. [ ] Create `src/deep_code_security/shared/config.py` (env-based configuration: registry path, sandbox timeout, container runtime, allowed paths, max files, max concurrent sandboxes)
12. [ ] Create `src/deep_code_security/mcp/path_validator.py`:
    - `validate_path(path: str, allowed_paths: list[str]) -> str` (returns resolved path or raises)
    - Resolve symlinks with `os.path.realpath()`
    - Reject `..` after normalization
    - Reject `/proc`, `/sys`, `/dev`, block devices, named pipes
13. [ ] Create `src/deep_code_security/mcp/input_validator.py`:
    - `validate_function_name(name: str) -> str` (must match `^[a-zA-Z_][a-zA-Z0-9_.]*$`)
    - `validate_variable_name(name: str) -> str` (must match `^[a-zA-Z_][a-zA-Z0-9_]*$`)
    - `validate_file_path(path: str) -> str` (must match `^[a-zA-Z0-9_/.\-]+$` and pass path validation)
    - `validate_raw_finding(finding: RawFinding) -> RawFinding` (validates all fields)
14. [ ] Create initial `CLAUDE.md` for the new project
15. [ ] Run validation: `cd ~/projects/deep-code-security && make lint && make test`
16. [ ] `git init && git add . && git commit -m "feat: initial project scaffolding"`

### Phase 2: Hunter -- Tree-Sitter Parser and Registry
**Estimated effort:** 5-7 days (1-2 days per language for registry development and testing)
**Dependencies:** Phase 1 complete
**Parallel with:** Phase 4 (sandbox images) can start once Phase 1 is done

1. [ ] Create `src/deep_code_security/hunter/models.py` with all Pydantic models: `Source`, `Sink`, `TaintStep`, `TaintPath`, `RawFinding`, `ScanStats`
2. [ ] Create `src/deep_code_security/hunter/parser.py`:
   - `TreeSitterParser` class wrapping `tree_sitter.Parser`
   - `parse_file(path: str, language: str) -> tree_sitter.Tree`
   - `parse_string(code: str, language: str) -> tree_sitter.Tree`
   - Grammar loading with lazy initialization (load grammar on first use per language)
   - Language detection from file extension
3. [ ] Create `src/deep_code_security/hunter/registry.py`:
   - `SourceSinkRegistry` class
   - `load_registry(language: str, registry_dir: str) -> Registry`
   - YAML schema validation (fail fast on malformed registries)
   - **Compile and validate all tree-sitter queries at load time** (catch syntax errors early)
   - Query execution timeout (default 5s per query)
   - Query result size cap (default 1000 matches per query)
   - Registry path restricted to `DCS_REGISTRY_PATH` only (no user override to arbitrary directories)
   - Include registry version hash in scan output metadata for reproducibility
4. [ ] Create YAML registry files in `registries/` (5-8 source patterns, 5-8 sink patterns each):
   - `registries/python.yaml` -- Flask/Django request, sys.argv, input(), os.system, eval, exec, subprocess, cursor.execute. Document known gaps (aliased imports, fully-qualified, class attributes).
   - `registries/go.yaml` -- http.Request, os.Args, exec.Command, database/sql with string concat. Document known gaps.
   - `registries/c.yaml` (stretch goal) -- argv, scanf, gets, fgets from stdin, system(), popen(), sprintf, strcpy. Document known gaps.
   - `registries/README.md` -- Registry format documentation with known limitations
5. [ ] Create `src/deep_code_security/hunter/source_sink_finder.py`:
   - `find_sources(tree: Tree, registry: Registry) -> list[Source]`
   - `find_sinks(tree: Tree, registry: Registry) -> list[Sink]`
   - Uses tree-sitter query API to match patterns from registry
6. [ ] Create tree-sitter query files in `src/deep_code_security/hunter/queries/`:
   - `python.scm`, `go.scm`, `c.scm` (stretch)
   - These contain reusable query fragments shared across registries
7. [ ] Create tests:
   - `tests/test_hunter/test_parser.py` -- Parse each language, verify AST structure
   - `tests/test_hunter/test_registry.py` -- Load each registry, validate schema, test query compilation, **test malformed query rejection**, test query timeout enforcement
   - `tests/test_hunter/test_source_sink_finder.py` -- Match known sources/sinks in fixture files
8. [ ] Create test fixtures in `tests/fixtures/vulnerable_samples/` and `tests/fixtures/safe_samples/` for Python and Go (C stretch)
9. [ ] Run validation: `make test-hunter`
10. [ ] Commit: `git add . && git commit -m "feat(hunter): tree-sitter parser and source/sink registry"`

### Phase 3: Hunter -- Taint Tracking Engine
**Estimated effort:** 6-8 days
**Dependencies:** Phase 2 complete
**Parallel with:** Phase 4 (sandbox images)

1. [ ] Create `src/deep_code_security/hunter/taint_tracker.py`:
   - `TaintState` class tracking tainted variables within a function scope
   - `TaintEngine` class implementing worklist algorithm:
     1. Seed worklist with source variables
     2. Process each worklist entry: follow assignments, function arguments, concatenations
     3. Mark reached variables as tainted
     4. When a tainted variable reaches a sink argument, record the `TaintPath`
   - Support for common propagation patterns:
     - Direct assignment: `x = tainted_var`
     - String concatenation: `query = "SELECT * FROM " + tainted_var`
     - String formatting: `query = f"SELECT * FROM {tainted_var}"`
     - Function argument passing (intra-function only in v1)
   - Support for sanitizer detection (from registry `sanitizers` section):
     - If a tainted variable passes through a sanitizer before reaching a sink, mark the path as sanitized
     - Sanitized paths get a lower raw_confidence score
   - **Note:** Each language's AST node types differ (Python `binary_operator` vs Go `binary_expression` vs C `binary_expression` with different child structures). The taint engine must handle per-language node type mappings. Budget time for this.
2. [ ] Create `src/deep_code_security/hunter/orchestrator.py`:
   - `HunterOrchestrator` class
   - `scan(target_path: str, languages: list[str] | None, severity_threshold: str, max_results: int, offset: int) -> tuple[list[RawFinding], ScanStats, int, bool]`
   - Orchestrates: path validation -> file discovery -> parse -> find sources/sinks -> taint track -> aggregate findings -> paginate
   - Process files sequentially, release ASTs after each file to bound memory
   - Store findings in server-side session for subsequent verify/remediate calls
3. [ ] Create tests:
   - `tests/test_hunter/test_taint_tracker.py`:
     - Test direct assignment propagation
     - Test string concatenation propagation
     - Test string formatting propagation
     - Test sanitizer detection (taint killed by sanitizer)
     - Test no false path when source and sink are in different scopes
     - Test multiple sources reaching same sink
   - `tests/test_hunter/test_orchestrator.py`:
     - Integration test: scan `tests/fixtures/vulnerable_samples/python/sql_injection.py`, expect specific findings
     - Integration test: scan `tests/fixtures/safe_samples/python/parameterized_query.py`, expect zero findings
     - Test with language filter
     - Test with severity threshold
     - Test pagination (max_results, offset)
     - Test path validation rejection
     - Test file count limit enforcement
4. [ ] Run validation: `make test-hunter`
5. [ ] Commit: `git add . && git commit -m "feat(hunter): intraprocedural taint tracking engine"`

### Phase 4: Sandbox Infrastructure
**Estimated effort:** 3-4 days
**Dependencies:** Phase 1 complete
**Parallel with:** Phases 2 and 3

1. [ ] Create `sandbox/seccomp-default.json`:
   - Whitelist only syscalls needed by language runtimes (read, write, open, close, mmap, brk, etc.)
   - Block dangerous syscalls: ptrace, mount, reboot, kexec_load, init_module, etc.
   - Document rationale for each allowed syscall
2. [ ] Create `sandbox/entrypoint.sh`:
   - Accept PoC script path as argument
   - Set resource limits (ulimit)
   - Execute with timeout
   - Capture exit code, stdout (truncated 2KB), stderr (truncated 2KB)
   - Output structured JSON result
3. [ ] Create `sandbox/Dockerfile.python`:
   - Python 3.12-slim base
   - Non-root user (65534:65534)
   - Copy entrypoint.sh
   - Copy seccomp profile
   - No network, read-only fs, tmpfs for /tmp with noexec
4. [ ] Create `sandbox/Dockerfile.go`:
   - golang:1.22-alpine base
   - Same security constraints
5. [ ] Create `sandbox/Dockerfile.c` (stretch goal):
   - gcc:12-slim base
   - Same security constraints
6. [ ] Create `src/deep_code_security/auditor/sandbox.py`:
   - `SandboxManager` class using **subprocess** (not Docker SDK)
   - Auto-detect container runtime: prefer Podman rootless, fall back to Docker
   - `build_images()` -- Build sandbox images (idempotent)
   - `run_exploit(language: str, target_path: str, poc_script: str, timeout: int) -> ExploitResult`
   - Container creation with full security policy:
     - `--network=none`
     - `--read-only`
     - `--tmpfs /tmp:rw,noexec,nosuid,size=64m`
     - `--cap-drop=ALL`
     - `--security-opt=no-new-privileges`
     - `--security-opt seccomp=seccomp-default.json`
     - `--pids-limit=64`
     - `--memory=512m`
     - `--user=65534:65534`
     - Mount target code read-only (with explicit exclusion of .env, .git/config, *.pem, *.key, id_rsa*)
     - Mount PoC script read-only
   - Container lifecycle: create -> start -> wait (with timeout) -> read logs (truncated) -> remove
   - Health check: `is_available() -> bool` (container runtime reachable, images built)
   - Concurrency semaphore: `DCS_MAX_CONCURRENT_SANDBOXES` (default: 2)
7. [ ] Create tests:
   - `tests/test_auditor/test_sandbox.py`:
     - Test sandbox creation command construction (verify all security flags present)
     - Test timeout enforcement
     - Test resource limit application
     - Test container cleanup on success and failure
     - Test credential file exclusion from mounts
     - Test concurrency semaphore
8. [ ] Build sandbox images: `cd ~/projects/deep-code-security && make build-sandboxes`
9. [ ] Run validation: `make test-auditor`
10. [ ] Commit: `git add . && git commit -m "feat(auditor): containerized sandbox infrastructure with security policy"`

### Phase 5: Auditor -- Exploit Verification
**Estimated effort:** 5-7 days
**Dependencies:** Phase 3 and Phase 4 complete

1. [ ] Create `src/deep_code_security/auditor/models.py`:
   - `ExploitResult` (with `exploit_script_hash` not full script), `VerifiedFinding`, `VerifyStats` Pydantic models
2. [ ] Create `src/deep_code_security/auditor/exploit_generator.py`:
   - Jinja2 `SandboxedEnvironment` for template rendering
   - Template registry mapping vulnerability_class -> PoC template
   - `generate_exploit(finding: RawFinding) -> str` (returns PoC script content)
   - **All finding fields validated by `input_validator.py` before template interpolation**
   - Templates for: SQL injection, command injection, path traversal, code execution
   - Each template is parameterized with validated source/sink from the finding
   - Buffer overflow and format string templates for C (stretch goal)
3. [ ] Create `src/deep_code_security/auditor/confidence.py`:
   - `compute_confidence(finding: RawFinding, exploit_results: list[ExploitResult]) -> tuple[int, str]`
   - Implements **bonus-only** weighted scoring model:
     - `base = 0.45 * taint + 0.25 * sanitizer + 0.20 * cwe_baseline`
     - `bonus = 0.10 * exploit_score if exploit_score > 0 else 0`
     - `confidence = base + bonus`
   - Returns (score, verification_status)
   - **Exploit failure does NOT penalize** -- a failed PoC leaves the base score unchanged
4. [ ] Create `src/deep_code_security/auditor/verifier.py`:
   - `Verifier` class
   - `verify_finding(finding: RawFinding, sandbox: SandboxManager) -> VerifiedFinding`
   - Orchestrates: validate finding -> generate PoC -> run in sandbox -> score -> wrap result
   - Store exploit scripts only in ephemeral sandbox logs; return SHA-256 hash in result
5. [ ] Create `src/deep_code_security/auditor/orchestrator.py`:
   - `AuditorOrchestrator` class
   - `verify(finding_ids: list[str], sandbox_timeout: int, max_verifications: int) -> tuple[list[VerifiedFinding], VerifyStats]`
   - Retrieve findings from server-side session store (not from external input)
   - Process up to `max_verifications` findings, prioritized by severity
   - Graceful degradation: if Docker/Podman unavailable, skip verification, use base confidence only
6. [ ] Create tests:
   - `tests/test_auditor/test_confidence.py`:
     - Test each scoring factor independently
     - Test combined scoring with known inputs
     - Test threshold classification
     - **Test that failed exploit does not reduce base confidence**
   - `tests/test_auditor/test_verifier.py`:
     - Test exploit generation for each vulnerability class
     - Test verification flow with mock sandbox
     - Test input validation rejects malicious function names (semicolons, quotes, backticks)
     - Test that exploit scripts are stored as hashes, not full text
7. [ ] Run validation: `make test-auditor`
8. [ ] Commit: `git add . && git commit -m "feat(auditor): exploit verification with bonus-only confidence scoring"`

### Phase 6: Architect -- Remediation Guidance
**Estimated effort:** 3-5 days
**Dependencies:** Phase 5 complete

1. [ ] Create `src/deep_code_security/architect/models.py`:
   - `RemediationGuidance`, `DependencyImpact`, `RemediateStats` Pydantic models
   - **No `Patch` model** -- guidance only, not apply-ready diffs
2. [ ] Create `src/deep_code_security/architect/guidance_generator.py`:
   - Template registry mapping (vulnerability_class, language) -> guidance template
   - `generate_guidance(finding: VerifiedFinding, context: str) -> RemediationGuidance`
   - Produces: vulnerability explanation, general fix pattern, illustrative code example
   - Does NOT produce before/after diffs or apply-ready patches
3. [ ] Create `src/deep_code_security/architect/dependency_analyzer.py`:
   - `DependencyAnalyzer` class
   - `analyze(target_path: str, guidance: list[RemediationGuidance]) -> DependencyImpact | None`
   - Parse: requirements.txt, pyproject.toml, go.mod
   - Check if recommended fixes require new dependencies
4. [ ] Create `src/deep_code_security/architect/impact_analyzer.py`:
   - Use tree-sitter to find all call sites of affected functions
   - `analyze_impact(target_path: str, affected_function: str, language: str) -> list[str]`
5. [ ] Create `src/deep_code_security/architect/orchestrator.py`:
   - `ArchitectOrchestrator` class
   - `remediate(finding_ids: list[str], target_path: str) -> tuple[list[RemediationGuidance], RemediateStats]`
   - Retrieve findings from session store, validate target_path against allowlist
6. [ ] Create tests:
   - `tests/test_architect/test_guidance_generator.py`
   - `tests/test_architect/test_dependency_analyzer.py` (parse requirements.txt, pyproject.toml, go.mod)
7. [ ] Run validation: `make test-architect`
8. [ ] Commit: `git add . && git commit -m "feat(architect): remediation guidance and dependency analysis"`

### Phase 7: MCP Server
**Estimated effort:** 2-3 days
**Dependencies:** Phases 5 and 6 complete

1. [ ] Create `src/deep_code_security/mcp/server.py`:
   - `DeepCodeSecurityMCPServer(BaseMCPServer)` class
   - Register 5 tools: `deep_scan_hunt`, `deep_scan_verify`, `deep_scan_remediate`, `deep_scan_full`, `deep_scan_status`
   - Each tool handler: validate inputs -> call orchestrator -> serialize output -> return TextContent
   - Error handling: catch exceptions, return ToolError with retryable flag
   - **Audit logging:** Log every tool invocation with timestamp, tool name, input parameters (paths redacted to basename), finding count, verdict, duration
   - Server-side session store for findings (in-memory dict keyed by scan ID)
2. [ ] Create `src/deep_code_security/mcp/__main__.py`:
   - Lifecycle: INITIALIZING -> SERVICE_VALIDATED -> STDIO_VALIDATED -> READY
   - Signal handlers (SIGTERM, SIGINT)
   - Docker/Podman availability check during SERVICE_VALIDATED (non-blocking warning if unavailable)
   - Path validation config loaded from `DCS_ALLOWED_PATHS`
3. [ ] Create `src/deep_code_security/cli.py`:
   - Click-based CLI for standalone usage (not through MCP)
   - Commands: `hunt`, `verify`, `remediate`, `full-scan`, `status`
   - JSON output to stdout, human-readable summary to stderr
4. [ ] Create tests:
   - `tests/test_mcp/test_server.py`:
     - Test tool registration (all 5 tools present)
     - Test each handler with mock orchestrators
     - Test error handling (ToolError returns)
     - Test path validation rejection (paths outside DCS_ALLOWED_PATHS)
     - Test input validation rejection (malicious finding fields)
     - Test audit logging output
   - `tests/test_integration/test_end_to_end.py`:
     - Full pipeline test: scan known-vulnerable Python sample -> verify -> remediate
     - Verify JSON structure at each phase
     - Verify confidence scores (bonus-only model)
     - Verify pagination works
5. [ ] Run validation: `make test-mcp && make test`
6. [ ] Commit: `git add . && git commit -m "feat(mcp): MCP server with 5 tools, path validation, and audit logging"`

### Phase 8: `/deep-scan` Skill in claude-devkit
**Estimated effort:** 1-2 days
**Dependencies:** Phase 7 complete

1. [ ] Create `~/projects/claude-devkit/skills/deep-scan/SKILL.md`:
   - Frontmatter: name=deep-scan, model=claude-opus-4-6, version=1.0.0
   - Follows Scan archetype
   - Step 0: Determine scope, validate MCP server available (`deep_scan_status`)
   - Step 1: Run Hunter (`deep_scan_hunt` via MCP) -- paginate if `has_more` is true
   - Step 2: Run Auditor (`deep_scan_verify` via MCP) -- conditional on Docker availability, max 50 verifications
   - Step 3: Run Architect (`deep_scan_remediate` via MCP)
   - Step 4: Synthesis -- coordinator reads all outputs, generates summary
   - Step 5: Verdict gate (PASS/PASS_WITH_NOTES/BLOCKED based on confirmed findings)
   - Step 6: Archive to `./plans/archive/deep-scan/[timestamp]/`
   - All 11 skill patterns followed (coordinator, numbered steps, tool declarations, verdict gates, timestamped artifacts, structured reporting, bounded iterations N/A (Scan archetype has no revision loops), model selection, scope parameters, archive on success, worktree isolation N/A)
   - **Note in skill:** The `/deep-scan` skill invokes MCP tools which may trigger Docker CLI permission prompts (Docker is not in the Claude Code tool allowlist)
2. [ ] Validate skill: `validate-skill ~/projects/claude-devkit/skills/deep-scan/SKILL.md`
3. [ ] Deploy skill: `cd ~/projects/claude-devkit && ./scripts/deploy.sh deep-scan`
4. [ ] Update `~/projects/claude-devkit/CLAUDE.md`:
   - Add deep-scan to Skill Registry table
   - Add deep-scan artifact locations
   - Add MCP server configuration note
5. [ ] Commit in claude-devkit: `git add . && git commit -m "feat(skills): add /deep-scan skill for deep code security analysis"`

### Phase 9: Integration Testing and Documentation
**Estimated effort:** 3-5 days
**Dependencies:** Phase 8 complete

1. [ ] Create comprehensive integration test suite in `tests/test_integration/`:
   - `test_end_to_end.py`: Full pipeline with Python and Go (C if stretch goal completed)
   - `test_false_positives.py`: Verify safe samples produce zero confirmed findings
   - `test_mcp_integration.py`: Test MCP tool invocation via subprocess
   - `test_path_validation.py`: Test that paths outside allowlist are rejected end-to-end
   - `test_input_sanitization.py`: Test that malicious finding fields are rejected end-to-end
2. [ ] Create `README.md` with:
   - Installation instructions
   - Quick start guide
   - Registry format documentation
   - Architecture overview
   - **Known Limitations section** (intraprocedural only, expected detection rates, query gaps)
   - Contributing guide
3. [ ] Finalize `CLAUDE.md` for the deep-code-security project
4. [ ] Run full validation: `make lint && make test && make sast && make security`
5. [ ] Verify coverage: `pytest --cov --cov-report=term-missing --cov-fail-under=90`
6. [ ] Commit: `git add . && git commit -m "feat: integration tests and documentation"`

## Rollout Plan

### Stage 1: Internal Testing (Week 1-2)
- Run against claude-devkit codebase (Python)
- Run against helper-mcps codebase at `~/projects/workspaces/helper-mcps/` (Python)
- Validate false positive rate on known-safe code
- Tune YAML registries based on results
- Benchmark detection rate against manually-identified vulnerabilities and document results
- **Note:** Docker commands during testing will trigger Claude Code permission prompts

### Stage 2: Multi-Language Validation (Week 3-4)
- Test against open-source projects with known CVEs:
  - Python: Django or Flask projects with publicly disclosed injection CVEs
  - Go: popular Go web frameworks with known vulnerabilities
  - C (if stretch goal completed): historical buffer overflow CVEs in small C projects
- Measure detection rate and false positive rate
- Document actual v1 detection rate vs the estimated 10-25%
- **Note:** Specific CVE targets should be identified during Stage 1 based on available test data

### Stage 3: Claude Code Integration (Week 5-6)
- Configure MCP server in `~/.claude/settings.json`
- Test `/deep-scan` skill end-to-end
- Validate MCP tool responses are correctly consumed by skill
- Run alongside `/audit` to compare coverage
- Test pagination with large codebases

### Stage 4: Production Readiness (Week 7-8)
- Document known limitations (intraprocedural only, expected detection rates, query gaps)
- Create runbook for common issues
- Tag v1.0.0 release
- Plan v1.1 scope: Java, Rust, interprocedural taint tracking, additional registry patterns

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Tree-sitter query complexity -- queries may be brittle across code styles (aliased imports, fully-qualified names, chained calls) | High | Medium | Scope v1 registries to 5-8 well-tested patterns per language. Document known gaps explicitly. Use test fixtures as regression suite. |
| False positive rate too high -- noisy results erode trust | High | High | Conservative default severity threshold (medium). Bonus-only confidence scoring. Iterate registries based on real-world testing in rollout stages. |
| Sandbox escape -- exploit PoC escapes container | Low | Critical | Full security policy: no network, read-only fs, no capabilities, non-root, seccomp profile, no-new-privileges, PID limits, memory limits. MCP server runs natively (no Docker socket exposure). Podman rootless preferred. |
| Intraprocedural-only taint tracking misses most real bugs | High | Medium | Expected limitation for v1 (~10-25% detection rate). Documented in Known Limitations. Primary v1 value is proving the architecture, not competing with commercial SAST. Interprocedural analysis is the P1 priority for v1.1. |
| Docker dependency -- tool unusable without Docker/Podman | Medium | Medium | Graceful degradation: Auditor phase becomes optional. Hunter and Architect still work without Docker. Base confidence used without exploit bonus. |
| tree-sitter grammar incompatibilities (v0.21->v0.23 API changes) | Medium | High | **Phase 0 spike** validates dependency chain before any implementation. Pin exact versions. |
| Performance on large codebases -- file count, memory, output size | Medium | Medium | DCS_MAX_FILES limit (10,000). Sequential file processing with AST release. Paginated output. DCS_MAX_CONCURRENT_SANDBOXES semaphore. |
| MCP SDK API changes -- SDK is evolving | Low | Medium | Pin MCP SDK version. Monitor releases. BaseMCPServer abstraction layer buffers against API changes. |
| Exploit PoC generation quality -- template-based PoCs may not trigger real vulnerabilities | High | Low | PoC verification is bonus-only signal (10% weight). Failed PoCs do not penalize findings. Start with well-known exploit patterns for direct injection. |
| Arbitrary filesystem read via path parameter | Medium | High | Path validation with DCS_ALLOWED_PATHS allowlist, symlink resolution, traversal rejection, and special file blocking. |
| Code injection via crafted finding fields in exploit templates | Medium | High | Jinja2 SandboxedEnvironment with strict field validation. Server-side session store prevents external finding injection. |
| YAML registry poisoning via malicious tree-sitter queries | Low | Medium | Registry path restricted to DCS_REGISTRY_PATH only. Queries compiled and validated at load time. Query execution timeouts and result size caps. |

## Test Plan

### Test Command

```bash
# From ~/projects/deep-code-security/

# Run all tests
make test
# Equivalent to: pytest -v --cov=src/deep_code_security --cov-report=term-missing --cov-fail-under=90

# Run by component
make test-hunter    # pytest tests/test_hunter/ -v --cov=src/deep_code_security/hunter
make test-auditor   # pytest tests/test_auditor/ -v --cov=src/deep_code_security/auditor
make test-architect # pytest tests/test_architect/ -v --cov=src/deep_code_security/architect
make test-mcp       # pytest tests/test_mcp/ -v --cov=src/deep_code_security/mcp

# Run integration tests (requires Docker or Podman)
make test-integration  # pytest tests/test_integration/ -v --timeout=120

# Linting
make lint           # ruff check .

# Security scanning
make sast           # bandit -r src/
make security       # make sast && pip-audit

# Vendor check
make check-vendor   # Compare vendored shared/ against upstream helper-mcps HEAD
```

### Test Categories

| Category | Count (est.) | Coverage Target | Description |
|----------|-------------|-----------------|-------------|
| Hunter unit tests | 25-30 | 95% | Parser, registry, source/sink finder, taint tracker |
| Auditor unit tests | 15-20 | 90% | Sandbox (mocked), confidence scoring, exploit generation, input validation |
| Architect unit tests | 10-15 | 90% | Guidance generation, dependency parsing, impact analysis |
| MCP server tests | 10-15 | 90% | Tool registration, handler dispatch, error handling, path validation, audit logging |
| Integration tests | 5-10 | N/A | End-to-end pipeline with real tree-sitter and fixture files |
| False positive tests | 5-10 | N/A | Verify safe code produces zero confirmed findings |
| Security tests | 5-8 | N/A | Path validation, input sanitization, finding injection prevention |

### Key Test Scenarios

1. **Python SQL injection detection:** Scan `tests/fixtures/vulnerable_samples/python/sql_injection.py` containing `cursor.execute("SELECT * FROM users WHERE id=" + user_input)`. Expect: 1 finding, CWE-89, Critical severity.
2. **Python safe parameterized query:** Scan `tests/fixtures/safe_samples/python/parameterized_query.py` containing `cursor.execute("SELECT * FROM users WHERE id=?", (user_input,))`. Expect: 0 findings.
3. **Go command injection:** Scan `tests/fixtures/vulnerable_samples/go/command_injection.go` containing `exec.Command("sh", "-c", userInput)`. Expect: 1 finding, CWE-78, Critical severity.
4. **Multi-language scan:** Scan a directory containing Python + Go files. Expect: findings from both languages with correct language labels.
5. **Confidence scoring (bonus-only):** Given a confirmed exploit result, verify confidence includes 10-point bonus. Given a failed exploit, verify confidence equals base score (no penalty).
6. **Sandbox timeout:** Submit a PoC that sleeps for 60s with a 5s timeout. Verify the sandbox kills it and returns timeout error.
7. **MCP tool round-trip:** Call `deep_scan_hunt` via MCP protocol, verify JSON response parses with pagination fields.
8. **Path validation:** Call `deep_scan_hunt` with `path: "/etc"`. Verify rejection with clear error message.
9. **Input sanitization:** Craft a finding with function name `os.system; rm -rf /`. Verify rejection before template interpolation.
10. **Finding provenance:** Call `deep_scan_verify` with fabricated finding IDs not from a previous hunt. Verify rejection.

## Acceptance Criteria

1. [ ] `make test` passes with 90%+ coverage across all components
2. [ ] `make lint` passes with zero errors
3. [ ] `make sast` passes with zero high/critical findings
4. [ ] Hunter correctly identifies sources and sinks for Python and Go using tree-sitter
5. [ ] Hunter's taint tracker finds direct assignment, string concatenation, and string formatting propagation paths
6. [ ] Hunter returns zero confirmed findings for all safe sample fixtures
7. [ ] Auditor sandbox runs exploit PoCs with full security policy (seccomp, no-new-privileges, PID limits, noexec tmpfs)
8. [ ] Auditor confidence scoring model uses bonus-only exploit weighting (10%)
9. [ ] Architect generates remediation guidance (not apply-ready diffs) for SQL injection, command injection, and path traversal
10. [ ] Architect correctly parses requirements.txt, pyproject.toml, and go.mod
11. [ ] MCP server registers all 5 tools and handles requests/responses as structured JSON
12. [ ] MCP server runs as native stdio process (not containerized, no Docker socket)
13. [ ] MCP server validates all paths against `DCS_ALLOWED_PATHS` allowlist
14. [ ] MCP server validates all RawFinding fields before exploit template interpolation
15. [ ] MCP server provides pagination on `deep_scan_hunt` results
16. [ ] MCP server logs all tool invocations for audit trail
17. [ ] `/deep-scan` skill in claude-devkit passes `validate-skill` and follows Scan archetype
18. [ ] `/deep-scan` skill deploys successfully via `deploy.sh`
19. [ ] End-to-end: `/deep-scan ~/projects/claude-devkit` produces a structured report with verdict
20. [ ] README documents known limitations (intraprocedural only, ~10-25% detection rate, query gaps)

## Task Breakdown: Files to Create or Modify

### New Project: `~/projects/deep-code-security/`

**Root files:**
- `~/projects/deep-code-security/pyproject.toml` (create)
- `~/projects/deep-code-security/Makefile` (create)
- `~/projects/deep-code-security/.gitignore` (create)
- `~/projects/deep-code-security/CLAUDE.md` (create)
- `~/projects/deep-code-security/README.md` (create)
- `~/projects/deep-code-security/SPIKE.md` (create -- Phase 0 results)

**Source -- shared:**
- `~/projects/deep-code-security/src/deep_code_security/__init__.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/cli.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/shared/__init__.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/shared/language.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/shared/file_discovery.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/shared/json_output.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/shared/config.py` (create)

**Source -- hunter:**
- `~/projects/deep-code-security/src/deep_code_security/hunter/__init__.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/hunter/models.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/hunter/parser.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/hunter/registry.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/hunter/source_sink_finder.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/hunter/taint_tracker.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/hunter/call_graph.py` (create -- stub for v1.1)
- `~/projects/deep-code-security/src/deep_code_security/hunter/orchestrator.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/hunter/queries/python.scm` (create)
- `~/projects/deep-code-security/src/deep_code_security/hunter/queries/go.scm` (create)
- `~/projects/deep-code-security/src/deep_code_security/hunter/queries/c.scm` (create -- stretch)

**Source -- auditor:**
- `~/projects/deep-code-security/src/deep_code_security/auditor/__init__.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/auditor/models.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/auditor/sandbox.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/auditor/exploit_generator.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/auditor/verifier.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/auditor/confidence.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/auditor/orchestrator.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/auditor/seccomp-profile.json` (create)

**Source -- architect:**
- `~/projects/deep-code-security/src/deep_code_security/architect/__init__.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/architect/models.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/architect/guidance_generator.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/architect/dependency_analyzer.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/architect/impact_analyzer.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/architect/orchestrator.py` (create)

**Source -- MCP:**
- `~/projects/deep-code-security/src/deep_code_security/mcp/__init__.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/mcp/__main__.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/mcp/server.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/mcp/path_validator.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/mcp/input_validator.py` (create)
- `~/projects/deep-code-security/src/deep_code_security/mcp/shared/` (create -- vendored from helper-mcps)

**Registries:**
- `~/projects/deep-code-security/registries/python.yaml` (create)
- `~/projects/deep-code-security/registries/go.yaml` (create)
- `~/projects/deep-code-security/registries/c.yaml` (create -- stretch)
- `~/projects/deep-code-security/registries/README.md` (create)

**Sandbox:**
- `~/projects/deep-code-security/sandbox/entrypoint.sh` (create)
- `~/projects/deep-code-security/sandbox/seccomp-default.json` (create)
- `~/projects/deep-code-security/sandbox/Dockerfile.python` (create)
- `~/projects/deep-code-security/sandbox/Dockerfile.go` (create)
- `~/projects/deep-code-security/sandbox/Dockerfile.c` (create -- stretch)

**Tests:**
- `~/projects/deep-code-security/tests/__init__.py` (create)
- `~/projects/deep-code-security/tests/conftest.py` (create)
- `~/projects/deep-code-security/tests/test_hunter/` (create -- 5 test files)
- `~/projects/deep-code-security/tests/test_auditor/` (create -- 3 test files)
- `~/projects/deep-code-security/tests/test_architect/` (create -- 2 test files)
- `~/projects/deep-code-security/tests/test_mcp/` (create -- 1 test file)
- `~/projects/deep-code-security/tests/test_integration/` (create -- 5 test files)
- `~/projects/deep-code-security/tests/fixtures/vulnerable_samples/python/` (create -- 3 files)
- `~/projects/deep-code-security/tests/fixtures/vulnerable_samples/go/` (create -- 2 files)
- `~/projects/deep-code-security/tests/fixtures/safe_samples/python/` (create -- 2 files)
- `~/projects/deep-code-security/tests/fixtures/safe_samples/go/` (create -- 1 file)

### Modifications in claude-devkit: `~/projects/claude-devkit/`

- `~/projects/claude-devkit/skills/deep-scan/SKILL.md` (create)
- `~/projects/claude-devkit/CLAUDE.md` (modify -- add deep-scan to skill registry)

**Total files: ~75 new files, 1 modified file** (reduced from ~90 due to language scope reduction)

## Context Alignment

### CLAUDE.md Patterns Followed

| Pattern | Alignment | Notes |
|---------|-----------|-------|
| Scan archetype | Full | `/deep-scan` skill follows the exact Scan archetype: scope detection -> parallel scans -> synthesis -> verdict gate -> archive |
| Numbered steps | Full | `/deep-scan` uses `## Step N -- [Action]` format |
| Tool declarations | Full | Each step declares `Tool:` (MCP tools for Steps 1-3, Read for Step 4) |
| Verdict gates | Full | Step 5 uses PASS / PASS_WITH_NOTES / BLOCKED |
| Timestamped artifacts | Full | All outputs use `[timestamp]` in filenames |
| Structured reporting | Full | Outputs to `./plans/` directory |
| Model selection | Full | Frontmatter specifies `model: claude-opus-4-6` |
| Scope parameters | Full | `## Inputs` with `$ARGUMENTS` |
| Archive on success | Full | Step 6 archives to `./plans/archive/deep-scan/[timestamp]/` |
| MCP server pattern | Adapted | Follows helper-mcps architecture (BaseMCPServer, lifecycle, structured logging) but runs natively instead of containerized |
| Coordinator pattern | Full | Skill coordinates MCP tool invocations, does not perform analysis itself |

### Prior Plans

- No prior plans for this feature exist. This is the first deep code security analysis plan.
- The `/audit` skill (v3.0.0) is a related but distinct capability -- it uses LLM pattern matching, not AST-based static analysis. `/deep-scan` complements `/audit` rather than replacing it.
- The `redhat-internal-browser-mcp.md` plan established the helper-mcps pattern and MCP migration rationale that this plan follows.

### Deviations from Established Patterns

| Deviation | Justification |
|-----------|---------------|
| Separate project (not inside claude-devkit) | Different lifecycle, heavy dependencies (tree-sitter grammars, subprocess-based Docker invocation), different deployment model. Follows the same rationale as the MCP server migration to helper-mcps. |
| MCP tools instead of Task subagents | The analysis is deterministic (tree-sitter based), not LLM-based. MCP is the correct interface for programmatic tooling. Task subagents are for LLM-delegated work. |
| No worktree isolation in `/deep-scan` | Read-only analysis skill. No code modifications, so no conflict risk. Worktree isolation is for write operations. |
| Bounded iterations pattern not applicable | Scan archetype does not have revision loops. Each phase runs once. |
| MCP server runs natively instead of containerized | Running the MCP server in a container with Docker socket access creates a root-equivalent host compromise vector (F-01). Native stdio eliminates this entirely while maintaining the same MCP interface. |

## Next Steps

1. **Approve this plan** -- Move status from DRAFT to APPROVED
2. **Execute Phase 0** -- Dependency spike (blocking: validates tree-sitter compatibility)
3. **Execute Phase 1** -- Project scaffolding (Engineer)
4. **Execute Phases 2-3 with 4 in parallel** -- Hunter core (Phase 2-3) and Sandbox infra (Phase 4) can be developed concurrently
5. **Execute Phase 5** -- Auditor (depends on Phases 3+4)
6. **Execute Phase 6** -- Architect (depends on Phase 5)
7. **Execute Phase 7** -- MCP Server (depends on Phases 5+6)
8. **Execute Phase 8** -- `/deep-scan` skill (depends on Phase 7)
9. **Execute Phase 9** -- Integration testing and documentation

**Estimated total effort:** 6-8 weeks (revised from 4-5 weeks based on feasibility review)

## Plan Metadata

- **Plan File:** `./plans/deep-code-security.md`
- **Affected Components:**
  - New project: `~/projects/deep-code-security/` (all files)
  - claude-devkit: `skills/deep-scan/SKILL.md` (new), `CLAUDE.md` (modified)
- **Validation:**
  - `cd ~/projects/deep-code-security && make lint && make test`
  - `cd ~/projects/deep-code-security && make sast && make security`
  - `validate-skill ~/projects/claude-devkit/skills/deep-scan/SKILL.md`
  - `cd ~/projects/claude-devkit && ./scripts/deploy.sh deep-scan`

<!-- Context Metadata
discovered_at: 2026-03-12T14:00:00
revised_at: 2026-03-12
claude_md_exists: true
recent_plans_consulted: redhat-internal-browser-mcp.md
archived_plans_consulted: none
revision_reason: Address Critical/Major findings from red team (FAIL), feasibility (REVISE), and librarian (PASS with edits) reviews
-->
