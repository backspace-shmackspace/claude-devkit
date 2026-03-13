# Feasibility Review: deep-code-security (Round 2)

**Plan:** `./plans/deep-code-security.md`
**Reviewed:** 2026-03-12
**Reviewer:** code-reviewer agent (feasibility assessment)
**Previous Review:** 2026-03-12 (Round 1 verdict: REVISE)

## Verdict: PASS

The revised plan has addressed all Critical and Major findings from Round 1. The scope reduction to Python + Go (C stretch), the fully specified sandbox security policy, the bonus-only confidence model, and the addition of Phase 0 (dependency spike) collectively transform this from an ambitious-but-overscoped plan into a realistic and well-bounded v1. The plan is ready for implementation.

---

## Round 1 Finding Resolution Status

### Critical Findings

| ID | Finding | Addressed? | Resolution | Adequate? |
|----|---------|-----------|------------|-----------|
| C1 | Sandbox security: tmpfs noexec underspecified | **Yes** | Lines 403-418: Full 12-point security policy now specified. noexec enforced on tmpfs. Seccomp profile, no-new-privileges, cap-drop=ALL, PID limits, non-root user, read-only FS all explicitly listed. Podman rootless preferred. Credential file exclusion list added. | **Yes.** This is thorough. The policy is concrete and auditable. Each control is named with its Docker flag. |
| C2 | Exploit PoC generation harder than described; 40% weight overconfident | **Yes** | Lines 24, 343-359, 985-990: Confidence model restructured. Exploit verification is now 10% bonus-only (not penalty). Weights: taint 45%, sanitizer 25%, CWE 20%, exploit 10% bonus. Known Limitations section explicitly states most PoCs will fail due to context issues. | **Yes.** The bonus-only model correctly prevents the systematic underrating of real vulnerabilities that was the core concern. |
| C3 | Tree-sitter query fragility underestimated; 3-4 days for 5 languages unrealistic | **Yes** | Lines 14, 23, 64, 326-331, 824, 844-848: Scope reduced to Python + Go (C stretch). Registries explicitly target 5-8 patterns per language. Phase 2 budget increased to 5-7 days (1-2 days per language). Known gaps documented inline in the registry YAML. | **Yes.** The combination of fewer languages, fewer patterns, and more time per language is realistic. |

### Major Findings

| ID | Finding | Addressed? | Resolution | Adequate? |
|----|---------|-----------|------------|-----------|
| M1 | Time estimates 2-3x too low for 5-language scope | **Yes** | Lines 64, 1395: Scope reduced to 2-3 languages. Total estimate revised to 6-8 weeks (from 22-30 days). Individual phase estimates increased: Phase 2 to 5-7 days, Phase 3 to 6-8 days, Phase 5 to 5-7 days, Phase 6 to 3-5 days, Phase 9 to 3-5 days. Phase 0 (1 day) added. | **Yes.** The revised estimates are credible for the reduced scope. |
| M2 | tree-sitter-languages vs individual grammar packages unresolved | **Yes** | Lines 482, 766-778: Phase 0 dependency spike added as a blocking gate. Plan commits to individual grammar packages (`tree-sitter-python`, `tree-sitter-go`) with `tree-sitter>=0.23.0`. Spike validates compatibility on Python 3.12 before any implementation begins. Results documented in SPIKE.md. | **Yes.** This is exactly the right approach -- validate before committing. |
| M3 | Intraprocedural taint tracking has narrow real-world coverage | **Yes** | Lines 21-23, 59, 1167: Known Limitations section added at the top of the plan with explicit detection rate estimate (10-25%). Stated that v1's primary value is proving the architecture. Interprocedural analysis listed as P1 for v1.1. | **Yes.** Expectations are now calibrated appropriately. |
| M4 | Architect phase patch generation oversimplified | **Yes** | Lines 65, 108-112, 256-265, 475, 551-558, 1022-1027: Architect output reframed from apply-ready diffs to remediation guidance. `RemediationGuidance` model includes vulnerability explanation, fix pattern, and code example -- but no before/after diffs. `guidance_generator.py` replaces `patch_generator.py`. Explicit comment in model: "No Patch model -- guidance only." | **Yes.** This is a significant improvement. Guidance with code examples avoids the broken-patch trust erosion problem. |
| M5 | MCP tool input size limits | **Yes** | Lines 198, 506-508, 606-607, 640-642: Pagination added to `deep_scan_hunt` (max_results, offset, total_count, has_more). `deep_scan_verify` accepts finding IDs referencing server-side session store instead of full finding arrays. `max_verifications` parameter added (default 50). | **Yes.** The combination of pagination, ID-based references, and verification caps addresses all three vectors (MCP message size, context window, memory). |

### Minor Findings

| ID | Finding | Addressed? | Resolution |
|----|---------|-----------|------------|
| m1 | Missing pathspec dependency | **Yes** | Line 794: `pathspec>=0.12.0` explicitly listed in pyproject.toml dependencies. |
| m2 | No rate limiting on sandbox execution | **Yes** | Lines 373, 524, 642, 956: `max_verifications` parameter (default 50) and `DCS_MAX_CONCURRENT_SANDBOXES` semaphore (default 2). |
| m3 | Rust unsafe scanning is a different problem domain | **Yes** | Lines 14, 473: Rust deferred to v1.1. Not in v1 scope. |
| m4 | No consideration of monorepo/polyglot scanning | **Yes** | Lines 25, 476: Cross-language taint tracking explicitly listed as a Non-Goal. v1 treats each language independently. |
| m5 | deep_scan_full conflates orchestration | **Partially** | Lines 201, 707-708: `skip_verification` flag added to deep_scan_full. However, no progress events or start/poll pattern added. The `/deep-scan` skill uses individual tools sequentially (lines 1088-1095), which mitigates this for the primary use case. |
| m6 | Vendoring helper-mcps shared/ creates maintenance burden | **Yes** | Lines 569, 803, 1204-1205: `VENDORED_FROM.md` with source commit hash. `check-vendor` Makefile target compares against upstream HEAD. |

**Resolution Summary:** 3/3 Critical addressed. 5/5 Major addressed. 5/6 Minor addressed, 1 partially addressed (acceptable -- the skill-level mitigation covers the primary use case).

---

## New Concerns from Revised Plan

### Minor Concerns

#### m-new-1. Session Store Lifecycle and Memory Bounds Are Unspecified

The plan introduces a server-side session store (in-memory dict keyed by scan ID) for finding provenance (lines 439, 519-522, 890, 1056). This is a good security decision (prevents external finding injection), but the plan does not specify:

- **Eviction policy:** How long do scan results persist? If the MCP server runs for days, stale sessions accumulate.
- **Memory ceiling:** A large scan producing thousands of findings stored in-memory could consume significant memory, especially across multiple scans.
- **Session ID format:** How are scan IDs generated? They should be cryptographically random to prevent guessing.

**Recommendation:** Add a simple LRU or TTL-based eviction policy (e.g., retain last 10 scans or expire after 1 hour). Document the session ID generation strategy (UUID4 is sufficient). This is Minor because the MCP server is typically short-lived (spawned per Claude Code session) and memory pressure is unlikely in practice.

#### m-new-2. Go Exploit Verification in Sandbox Requires Compilation

The plan describes sandbox containers for exploit verification, but Go PoCs require compilation before execution. The `golang:1.22-alpine` sandbox image (line 396) would need the Go compiler and toolchain available inside the container, which significantly increases the image size and attack surface compared to the Python sandbox (which just needs the interpreter).

**Recommendation:** Consider whether Go exploit verification is worth the added complexity in v1. The Go sandbox image will be ~300MB+ (vs ~50MB for Python slim). If Go verification is included, ensure the seccomp profile accounts for the additional syscalls that `go build` requires (especially `clone` for goroutines and `execve` for the compiler). Alternatively, pre-compile Go PoCs on the host and mount only the binary into a minimal sandbox -- though this trades one complexity for another.

#### m-new-3. Sensitive File Exclusion List Is Not Exhaustive

The credential file exclusion list (line 412, 952) covers `.env`, `.git/config`, `*.pem`, `*.key`, `id_rsa*`. Common sensitive files not covered include:

- `.netrc`, `.npmrc` (may contain tokens)
- `*.p12`, `*.pfx` (certificate bundles)
- `*.json` files in `~/.config/` (gcloud, AWS credentials)
- `.docker/config.json` (Docker registry auth)

**Recommendation:** This is low risk because the sandbox mount is scoped to the target codebase directory (not the home directory), and the mount is read-only. However, consider making the exclusion list configurable via `DCS_EXCLUDE_PATTERNS` for users who have credentials checked into their repos (a bad practice, but it happens). Alternatively, add `.netrc` and `.npmrc` to the default list.

#### m-new-4. No Explicit Handling of Binary Files in File Discovery

The file discovery module (line 500-501) walks directories and identifies language by extension, but the plan does not mention skipping binary files. A directory might contain compiled `.pyc` files, `.so` shared objects, or large data files that tree-sitter cannot parse. Attempting to parse these will waste time and may cause parser errors.

**Recommendation:** Add a binary file detection step (check for null bytes in the first 8KB, or use the `mimetypes` module) before passing files to the tree-sitter parser. Skip non-text files silently and count them in `files_skipped`.

---

## Assessment of Revised Plan

### Implementation Complexity

The revised estimates are realistic for the reduced scope:

| Phase | Estimate | Assessment |
|-------|----------|------------|
| Phase 0: Dependency Spike | 1 day | Reasonable. This is a 20-line script plus documentation. |
| Phase 1: Scaffolding | 2-3 days | Reasonable. Standard project setup with helper-mcps vendoring. |
| Phase 2: Parser + Registry | 5-7 days | Realistic for 2 languages (Python + Go) at 1-2 days per language including test fixtures. |
| Phase 3: Taint Tracking | 6-8 days | Realistic. The per-language AST node type mapping (Python `binary_operator` vs Go `binary_expression`) is explicitly acknowledged as a time sink. |
| Phase 4: Sandbox | 3-4 days | Reasonable. 2 Dockerfiles + entrypoint + seccomp profile + security hardening. |
| Phase 5: Auditor | 5-7 days | Reasonable given the reduced template scope and bonus-only scoring model. |
| Phase 6: Architect | 3-5 days | Reasonable. Guidance generation is simpler than patch generation. Only 2 manifest parsers (requirements.txt/pyproject.toml + go.mod). |
| Phase 7: MCP Server | 2-3 days | Reasonable given helper-mcps patterns. |
| Phase 8: Skill | 1-2 days | Reasonable. Thin orchestration layer. |
| Phase 9: Integration | 3-5 days | Reasonable. End-to-end testing across 2 languages. |
| **Total** | **32-45 days (6-8 weeks)** | **Credible.** |

### Language Scope Decision (Python + Go)

The reduction from 5 languages to 2 (with C as stretch) is the single most impactful change in the revision. This is appropriate for v1 because:

1. **Python** is the most common target for SAST tools and has the best tree-sitter query documentation.
2. **Go** provides coverage of a compiled, statically-typed language with different AST structures, validating that the engine is truly multi-language.
3. **C as stretch** adds memory safety analysis (buffer overflows, format strings) which is a distinct vulnerability class from injection.
4. Java and Rust can be added in v1.1 by creating new YAML registries and tree-sitter query files -- the architecture supports this cleanly.

### Test Coverage

The test plan is comprehensive. Key strengths:

- False positive tests (safe samples producing zero findings) prevent the most trust-eroding failure mode.
- Input sanitization tests (malicious function names with shell metacharacters) validate the security boundary.
- Finding provenance tests (fabricated IDs rejected) validate the session store security model.
- The bonus-only confidence scoring has a dedicated test asserting that failed exploits do not reduce base confidence.

### Missing Edge Cases

1. **Empty files:** What happens when tree-sitter parses an empty source file? This should be handled gracefully (zero findings, no error).
2. **Extremely long lines:** Tree-sitter handles this, but the taint tracker's variable tracking may need a line-length or AST-depth bound to prevent pathological cases.
3. **Unicode in source files:** Tree-sitter handles UTF-8, but the regex validators for function names (`^[a-zA-Z_][a-zA-Z0-9_.]*$`) will reject valid identifiers in languages that support Unicode identifiers (Python 3 supports Unicode variable names). This is acceptable for v1 but should be documented.

---

## What the Revised Plan Gets Right

1. **Honest scope calibration.** The Known Limitations section at the top of the plan sets realistic expectations before the reader encounters the architecture. This prevents the plan from being judged against aspirations it does not claim.

2. **Phase 0 as a blocking gate.** The dependency spike before any implementation is a mature engineering decision. Many projects discover dependency incompatibilities in week 3 instead of day 1.

3. **Finding provenance via session store.** Using server-side session storage with ID references (instead of passing full finding arrays between tools) simultaneously solves the MCP message size problem and prevents external injection of crafted findings.

4. **Credential file exclusion from sandbox mounts.** The explicit list of files excluded from read-only mounts (`.env`, `.git/config`, `*.pem`, `*.key`, `id_rsa*`) shows defense-in-depth thinking.

5. **Guidance over patches.** The decision to produce remediation guidance with code examples rather than apply-ready diffs is the right tradeoff for v1. It avoids the failure mode where broken patches erode trust in the entire tool.

6. **Query validation at load time.** Compiling and validating tree-sitter queries when the registry loads (not at query execution time) catches malformed queries early and provides clear error messages.

---

## Recommendations

Prioritized from most to least impactful:

1. **Add session store eviction policy** (Minor) -- LRU or TTL-based cleanup to prevent memory growth in long-running MCP server processes.

2. **Address Go sandbox image size and syscall profile** (Minor) -- Document the Go sandbox's larger attack surface due to the compiler toolchain, and ensure the seccomp profile covers `go build` syscalls.

3. **Add binary file detection in file discovery** (Minor) -- Skip non-text files before passing to tree-sitter parser.

4. **Make credential exclusion list configurable** (Minor) -- Add `DCS_EXCLUDE_PATTERNS` env var with sensible defaults.

5. **Document Unicode identifier limitation** (Minor) -- Note that v1 regex validators reject Unicode identifiers.

---

## Summary

The revised plan has substantively addressed every Critical and Major finding from Round 1. The three most impactful changes -- reducing language scope to Python + Go, fully specifying the sandbox security policy, and restructuring the confidence model to bonus-only -- resolve the feasibility concerns that prompted the REVISE verdict. The remaining new concerns are all Minor and none of them block implementation. The 6-8 week timeline is credible for the described scope. This plan is ready to proceed.

<!-- Review Metadata
reviewed_at: 2026-03-12T17:45:00
plan_file: ./plans/deep-code-security.md
round: 2
previous_verdict: REVISE
verdict: PASS
critical_count: 0
major_count: 0
minor_count: 5
round1_critical_resolved: 3/3
round1_major_resolved: 5/5
round1_minor_resolved: 5/6 (1 partial)
-->
