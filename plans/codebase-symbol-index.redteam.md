# Red Team Re-Review: Codebase Symbol Index (Revision Round 1)

**Reviewer:** Red Team Agent (security-analyst supplement)
**Plan:** `plans/codebase-symbol-index.md`
**Date:** 2026-05-25
**Plan Version:** 1.1 (Revised)
**Prior Review:** 2026-05-25 (v1.0)

---

## Verdict: PASS

All six Major findings from the initial review have been adequately addressed. The STRIDE coverage gaps (Spoofing and Repudiation) have been filled. No new Critical or Major issues were introduced by the revision. Two Minor observations are noted below but do not block approval.

---

## Original Findings Resolution Status

### F-01: Token budget savings claim is unsubstantiated (Major) -- RESOLVED

The revised plan replaces the unsubstantiated "30-50% savings" claim with qualified language ("estimated 30-50%") in the Problem Statement (line 38) and adds a Phase 6 Measurement and Evaluation gate (lines 816-839) with explicit success thresholds:
- Pass: >=20% token reduction
- Marginal: 10-20% (scanner disabled by default)
- Fail: <10% (scanner integration removed from skills)

The evaluation methodology is concrete: 5 `/architect` runs and 3 `/ship` runs, with and without the scanner, measuring token counts, tool call counts, and wall-clock time. The Goal 1 statement (line 74) now references the evaluation gate instead of asserting a specific reduction target.

**Assessment:** The core concern -- building a feature with no measurement gate to validate its premise -- is fully addressed. Phase 6 provides a rigorous go/no-go decision framework.

---

### F-02: sys.path manipulation for venv activation is fragile and potentially insecure (Major) -- RESOLVED

The revised plan (Decision 5, lines 159-163) replaces `sys.path.insert()` with subprocess re-exec under the venv Python interpreter. The scanner script itself does not activate the venv or manipulate `sys.path` (line 667). The skill Bash invocation block selects the interpreter (venv Python if available, system `python3` if not). If tree-sitter is not importable, regex fallback is used.

Venv ownership verification is added (lines 651-666): `os.stat(venv_dir).st_uid == os.getuid()` before re-exec, with fallback to regex mode on ownership mismatch.

**Assessment:** All three sub-problems (fragility, security, cross-platform) are resolved. Subprocess re-exec is the standard pattern. Ownership verification addresses the module injection vector.

---

### F-03: Cache file in project root is trust boundary violation (Major) -- RESOLVED

The revised plan relocates the cache to `~/.claude-devkit/cache/<project-hash>/index.json` (Decision 4, lines 149-157). The project-hash is SHA-256 of the canonicalized project root (first 12 hex chars). HMAC-SHA256 integrity tag is computed on write and verified on read. HMAC key is derived from `os.getlogin() + os.path.expanduser("~")`.

The STRIDE table entry for cache poisoning (line 448) is raised from Low to Medium. Atomic writes via temp + rename (line 460) prevent partial reads from concurrent invocations.

**Assessment:** The cache is now outside the project root (cannot be accidentally committed or tampered with in shared project directories). HMAC integrity detects tampering. The original attack scenario (attacker modifying cache to omit security-critical files) is mitigated by the HMAC verification. The HMAC key derivation is simple but adequate for the threat model -- it prevents cross-user tampering, which was the primary concern.

Minor note: the HMAC key is deterministic from public information (username + homedir), which means an attacker with knowledge of the user's identity can forge a valid HMAC. This is acceptable because if an attacker can write to `~/.claude-devkit/cache/`, they already have the user's UID, and the ownership check on the venv directory would also be satisfied. The threat model's assumption of "same user, user-owned directory" is the correct boundary here.

---

### F-04: No output size cap enforced (Major) -- RESOLVED

The revised plan adds a `--max-tokens` CLI flag (default 4000, lines 137-145, 281) with a deterministic six-tier truncation strategy:
1. Always include header line (parser mode, language counts, file/symbol totals)
2. Top-N files by symbol density until 70% budget consumed
3. Import graph edges for included files until 85% budget consumed
4. File listing until 95% budget consumed
5. Truncation footer if truncated

Goal 4 (line 77) explicitly states the hard cap. The integration tests include a `--max-tokens` test (Test 8, line 758).

**Assessment:** The truncation strategy is deterministic and prioritizes the most information-dense content. The hard cap directly prevents the context window overflow scenario described in the original finding.

---

### F-05: Caller detection false positives (Major) -- RESOLVED

Caller detection is deferred entirely to v2 (C-02 in Revision Log, line 22). The `CallerEntry` dataclass and `callers{}` field are removed from the data model (line 233). The "Call Hotspots" section is removed from summary output. Blast radius in `/ship` Step 4 now uses import graph edges (deterministic) rather than string-matched call sites (noisy).

**Assessment:** This is the correct resolution. Deferring a known-broken feature is better than shipping it with disclaimers. The import graph provides sufficient blast radius data for v1, and the Future Evolution section (lines 1036-1043) documents v2 approaches with scope-aware matching.

---

### F-06: No measurement gate in rollout plan (Major) -- RESOLVED

Phase 6 (lines 816-839) adds a 2-3 day Measurement and Evaluation gate at Days 10-14 with:
- Baseline measurements (scanner disabled): 5 `/architect` + 3 `/ship` runs
- Treatment measurements (scanner enabled): same workload
- Three-tier evaluation: Pass (>=20%), Marginal (10-20%), Fail (<10%)
- Explicit consequence for each tier (keep/disable-by-default/remove)
- Written measurement report saved to `plans/codebase-scanner-evaluation.md`

The rollout plan (lines 844-878) integrates Phase 6 as a distinct stage after Phase 4-5.

**Assessment:** The measurement gate is rigorous and actionable. The three-tier evaluation with explicit consequences prevents the "ship and forget" failure mode described in the original finding.

---

### F-07: deploy.sh integration is hand-waved (Minor) -- RESOLVED

Decision 6 (lines 165-169) explicitly states: "deploy.sh is NOT modified." The scanner is invoked via `$CLAUDE_DEVKIT/scripts/codebase-scanner.py` with `./scripts/codebase-scanner.py` as local fallback. The ambiguous `deploy.sh` copy block is removed. The "Files to Modify" table (lines 989-996) does not include `deploy.sh`.

---

### F-08: Regex fallback fidelity is not tested against tree-sitter baseline (Minor) -- PARTIALLY RESOLVED

The plan does not add an explicit fidelity comparison test (regex vs tree-sitter on the same codebase). However, the `--self-test` flag (line 903) includes "Regex extraction for all 4 languages (using inline test snippets)" which validates that regex extraction produces expected results on known input. The deferral of caller detection (which was the highest false-positive risk) reduces the impact of regex fallback inaccuracy.

The 70% figure is still not substantiated, but it now has lower impact since:
1. Caller detection (the most error-prone feature) is deferred.
2. The summary output labels the parser mode (`Parser: regex-fallback`) so agents know the fidelity level.

**Assessment:** Acceptable. The inline test snippets provide a regression baseline. A cross-parser comparison test would be nice-to-have but is not blocking.

---

### F-09: No consideration of concurrent scanner invocations (Minor) -- RESOLVED

The revised plan specifies atomic writes (temp + rename) for the cache file (line 460) and explicitly names this pattern in mitigations (line 460) and Context Alignment (line 1011).

---

### F-10: 800-line single-file script difficult to test and maintain (Minor) -- UNCHANGED

The plan retains the single-file design with `--self-test`. The original recommendation to split into a main script and a test script was not adopted.

**Assessment:** Acceptable for v1. The `--self-test` pattern is used by other tools in the ecosystem and the script is standalone with no cross-file dependencies. If the script grows beyond ~1200 lines in v2 (caller detection), splitting should be reconsidered.

---

### F-11: SHA-256 of first 4KB is a weak invalidation signal (Info) -- RESOLVED

The revised plan changes cache invalidation to use "SHA-256 of entire file content" (line 558: "content hashes (SHA-256 of entire file content)"). This eliminates the stale-cache risk for files larger than 4KB.

---

### F-12: tree-sitter query syntax varies across grammar versions (Info) -- RESOLVED

The revised plan adds version pins to `scanner-languages.json` (lines 496-533, e.g., `"tree_sitter_package": "tree-sitter-python>=0.23,<1.0"`) and to the requirements file (lines 596-602, e.g., `tree-sitter>=0.25.0,<0.26`).

---

## Security-Analyst Supplement Status

### STRIDE Coverage

| Category | v1.0 Status | v1.1 Status | Assessment |
|----------|------------|------------|------------|
| **S -- Spoofing** | Missing | **Added** (line 443) | Scanner/venv replacement addressed. Mitigation: venv ownership verification (`st_uid == getuid()`), scanner invoked from git-controlled `$CLAUDE_DEVKIT`. Failure mode defined (ownership mismatch -> regex fallback with warning). |
| **T -- Tampering** | Partial | **Strengthened** | Cache poisoning raised to Medium. HMAC integrity added. Path traversal unchanged (already adequate). Malicious PyPI package added as new entry (line 451). |
| **R -- Repudiation** | Missing | **Added** (line 444) | Scanner invocation logged to JSONL audit log via `emit-audit-event.sh` with version, parser mode, file/symbol count, and output SHA-256 hash. |
| **I -- Information Disclosure** | Yes | Unchanged | Symlink escape and secrets-in-paths remain adequately mitigated. |
| **D -- Denial of Service** | Yes | Unchanged | Parser crash and oversized project remain adequately mitigated. |
| **E -- Elevation of Privilege** | Yes | Unchanged | Scanner output does not expand LLM access surface. |

**STRIDE coverage is now 6/6.** All categories have at least one entry with specific mitigations and defined failure modes.

### Trust Boundaries

The venv/PyPI supply chain trust boundary is now explicitly identified in the trust boundary diagram (lines 425-429) and in the STRIDE table (line 451, "Malicious PyPI package in venv executes arbitrary code"). Mitigation: pinned versions in requirements file, venv user-owned (mode 0700), tree-sitter is a widely-used high-profile project.

### Failure Modes

The revised plan adds explicit failure modes to mitigations:
- Path canonicalization failure: "file is skipped, diagnostic emitted to stderr" (line 442)
- Venv ownership mismatch: "triggers regex fallback with warning" (line 443)
- HMAC mismatch: "triggers full rescan with warning" (line 448)
- `realpath()` exception: "file is skipped and a diagnostic is emitted to stderr" (line 455)
- Output sanitization strips entire name: "omitted from output with a diagnostic" (line 461)
- Per-file timeout: "parse is aborted and the file is skipped cleanly (tree-sitter parse state is per-call, no global state corruption)" (line 459)

**Assessment:** All five missing failure modes identified in the original review are now defined. Each mitigation states what happens when the control fails.

---

## New Issues Introduced by Revision

### N-01: HMAC key derivation from public information (Info)

The HMAC key is derived from `os.getlogin() + os.path.expanduser("~")` (line 153). These are public values -- any process running as the same user (or with knowledge of the username and homedir) can compute the same key. This means the HMAC protects against cross-user tampering but not against a malicious process running as the same user.

**Impact:** Low. If a malicious process is running as the user, it has direct access to all files the user can read/write, including the cache directory. The HMAC is defense-in-depth against scenarios like shared filesystems or accidental cache file swaps, not against same-user attacks. The threat model correctly scopes the cache as a "same user, same script" artifact.

**Recommendation:** No action required for v1. If the scanner evolves to handle more sensitive data (e.g., source code bodies), consider a randomly-generated key stored in `~/.claude-devkit/.cache-key` (user-readable only).

### N-02: `signal.alarm()` timeout is Unix-only (Info)

The per-file timeout uses `signal.alarm(5)` (line 459), which is not available on Windows. The plan states macOS and Linux as target platforms (Assumption 1, line 92), so this is not a blocker. However, if Windows support is ever added, this will need a threading-based timeout.

**Recommendation:** No action required. Document the Unix-only limitation in a code comment near the `signal.alarm()` call.

---

## Summary of Revision Assessment

| Original Finding | Severity | Resolution Status |
|-----------------|----------|-------------------|
| F-01: Unsubstantiated token savings | Major | RESOLVED -- Phase 6 evaluation gate added |
| F-02: sys.path manipulation | Major | RESOLVED -- Subprocess re-exec + ownership verification |
| F-03: Cache trust boundary | Major | RESOLVED -- Relocated to ~/.claude-devkit/ + HMAC |
| F-04: No output size cap | Major | RESOLVED -- --max-tokens hard cap with deterministic truncation |
| F-05: Caller detection false positives | Major | RESOLVED -- Deferred to v2 |
| F-06: No measurement gate | Major | RESOLVED -- Phase 6 with three-tier evaluation |
| F-07: deploy.sh ambiguity | Minor | RESOLVED -- Decision 6 clarifies: no deploy.sh changes |
| F-08: Regex fallback fidelity | Minor | PARTIALLY RESOLVED -- Inline tests but no cross-parser comparison |
| F-09: Concurrent invocations | Minor | RESOLVED -- Atomic writes (temp + rename) |
| F-10: Single-file complexity | Minor | UNCHANGED -- Acceptable for v1 |
| F-11: 4KB content hash | Info | RESOLVED -- Full-file SHA-256 |
| F-12: Grammar version pins | Info | RESOLVED -- Pinned in config and requirements |
| SA-S: Spoofing missing | Major | RESOLVED -- STRIDE entry added |
| SA-R: Repudiation missing | Major | RESOLVED -- STRIDE entry + audit logging added |
| SA-C: Cache poisoning understated | Major | RESOLVED -- Raised to Medium + HMAC |
| SA-V: Venv trust boundary | Minor | RESOLVED -- Added to diagram and STRIDE |

| New Issue | Severity | Status |
|-----------|----------|--------|
| N-01: HMAC key from public info | Info | Acknowledged, acceptable for v1 |
| N-02: signal.alarm() Unix-only | Info | Acknowledged, platforms scoped to macOS/Linux |

**Verdict rationale:** All six Major findings are resolved. All Security-Analyst supplement gaps (Spoofing, Repudiation, cache risk rating, venv trust boundary, failure modes) are addressed. Two new Info-level observations do not affect the verdict. The plan is significantly improved from v1.0 and is ready for implementation.
