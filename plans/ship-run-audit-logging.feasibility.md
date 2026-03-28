# Feasibility Review (Round 2): Ship Run Audit Logging

**Plan:** `plans/ship-run-audit-logging.md` (Rev 2)
**Reviewer:** code-reviewer agent (feasibility review)
**Date:** 2026-03-27
**Round:** 2 (prior round: 2 Critical, 3 Major)
**Skill versions evaluated:** ship v3.5.0, architect v3.1.0, audit v3.1.0

---

## Verdict: PASS

All 5 issues from Round 1 have been resolved. No new critical or major issues introduced. Three minor issues identified, none blocking.

---

## Round 1 Resolution Verification

### C1. Shell state persistence -- RESOLVED

**Round 1:** Inline bash function `emit_audit_event` defined in Step 0 would be undefined in Steps 1-7 because each Bash tool call spawns a fresh shell.

**Round 2 fix:** Replaced with standalone `scripts/emit-audit-event.sh` helper script. The script reads all state from a disk-based state file (`.ship-audit-state-${RUN_ID}.json`), requires no persistent shell variables or functions, and is invoked as a one-liner from each step.

**Assessment:** Fully resolved. The helper script approach is technically sound:
- State file is created via `python3` (reliable JSON writing) in Step 0.
- Each subsequent step invokes `bash scripts/emit-audit-event.sh "$STATE_FILE" '{...}'` -- a self-contained process that reads state, derives sequence from `wc -l`, appends an event, and exits.
- No shell state crosses call boundaries. Each invocation is stateless with respect to the calling shell.
- The script path (`scripts/emit-audit-event.sh`) is consistent with existing utilities in `scripts/` (`deploy.sh`, `validate-all.sh`, `install.sh`).

### C2. JSON escaping -- RESOLVED

**Round 1:** `_audit_escape` missed carriage returns, form feeds, and RFC 8259 control characters (0x00-0x1F).

**Round 2 fix:** Replaced with `python3 -c "import json,sys; print(json.dumps(sys.argv[1])[1:-1])"` with `|| printf '%s'` fallback.

**Assessment:** Fully resolved. `json.dumps()` handles all RFC 8259 requirements. The fallback preserves the non-blocking principle. The `[1:-1]` slice to strip outer quotes is correct (json.dumps produces `"escaped_string"`, and we want just `escaped_string` for embedding into a larger JSON template).

### M1. L3 HMAC key persistence -- RESOLVED

**Round 1:** Ephemeral HMAC key was lost when the shell session ended, making the L3 chain unverifiable post-run.

**Round 2 fix:** Key persisted to `.ship-audit-key-${RUN_ID}` file with `chmod 600`. At L3, key file is committed alongside the log via `git add --force`. Query utility `verify-chain` reads the key from the persisted file.

**Assessment:** Fully resolved. The design accepts an explicit trade-off: L3 provides tamper *detection* (detecting uncoordinated modifications) not tamper *prevention* (the key is committed to the same repo as the log). This is clearly documented in the plan. The 0600 permission model is adequate for the stated threat model (developer-level non-repudiation, not adversarial resistance). See Minor m1 below for a note on the key file format.

### M2. `duration_ms` dropped -- RESOLVED

**Round 1:** Computing `duration_ms` required persisting a start timestamp across Bash tool calls, which is impossible given shell state non-persistence.

**Round 2 fix:** Dropped `duration_ms` from the per-event schema entirely. Duration is computed at query time by the `timeline` command in `audit-log-query.sh` from `step_start`/`step_end` timestamp pairs.

**Assessment:** Fully resolved. The approach is clean -- the data (timestamps on `step_start` and `step_end`) is already captured; computing the delta is a query-time concern. The plan correctly notes this in the schema section, the trade-offs table, and the query utility description.

### M3. Sequence counter -- RESOLVED

**Round 1:** `AUDIT_SEQ` shell variable could not persist across Bash tool calls.

**Round 2 fix:** Sequence derived from `wc -l` of the log file plus 1. Stateless per invocation.

**Assessment:** Fully resolved. `wc -l` is reliable for append-only JSONL files where each event is exactly one line. The helper script controls the write (single `printf '%s\n'` per invocation), so partial lines are not a concern under normal operation.

---

## New Issues Assessment

No new critical or major issues introduced by the revision. The helper script architecture is well-designed. Three minor observations follow.

---

## Minor Suggestions (Consider)

### m1. State file created with shell interpolation into Python string -- injection risk

**Risk level:** Minor (Low probability, Low impact)

In the Step 0 modifications, the state file is created via:
```python
python3 -c "
state = {
    'run_id': '${RUN_ID}',
    ...
    'hmac_key': '${HMAC_KEY}'
}
..."
```

The `${RUN_ID}` and `${HMAC_KEY}` values are interpolated into a Python string literal inside a bash heredoc. `RUN_ID` is generated from `date` + `/dev/urandom` filtered to `[a-z0-9]`, so it is safe. `HMAC_KEY` is also filtered to `[a-zA-Z0-9]` (64 chars from `tr -dc`), so it is also safe. But if a future change relaxes the character set for either value, a single quote in the value would break the Python syntax.

**Recommended adjustment:** Use `json.dumps()` to write the state file rather than string interpolation into Python source. The helper script already depends on `python3`; using `json.dumps()` for the state file creation is consistent. For example, pass the values as `sys.argv` arguments to the Python script rather than interpolating them into the code string. This is a robustness improvement, not a current vulnerability.

### m2. State file cleanup on abnormal termination

**Risk level:** Minor

The state file (`.ship-audit-state-${RUN_ID}.json`) is deleted in Step 6. If the `/ship` run crashes or is interrupted before Step 6, the state file remains on disk. The plan adds `.ship-audit-state-*` to `.gitignore`, so orphaned state files will not clutter `git status`. However, the existing Step 0 cleanup logic (which cleans up orphaned `.ship-worktrees-*.tmp` files) does not cover orphaned state files.

**Recommended adjustment:** Add orphaned state file cleanup to the existing Step 0 cleanup block. Apply the same orphan-detection pattern: if a `.ship-audit-state-*.json` file exists but no corresponding worktree tracking file exists (indicating the run is not active), delete it. Alternatively, clean up all state files older than 24 hours. This is not blocking -- orphaned state files are small (~200 bytes) and gitignored.

### m3. `run_end` chicken-and-egg is documented but `commit_sha` field is misleading

**Risk level:** Minor

The plan honestly documents the chicken-and-egg problem: `run_end` is emitted before the final `git commit`, so `commit_sha` points to the previous commit. The field name `commit_sha` implies it is the SHA of the commit containing this run's changes, but it is actually "last known HEAD at run completion."

**Recommended adjustment:** Consider renaming to `head_sha` or `pre_commit_sha` to make the semantics explicit. Alternatively, keep `commit_sha` but add a note in the JSON Schema (`configs/audit-event-schema.json`) documenting that it is the HEAD SHA at `run_end` emission time, not the final commit SHA. This avoids confusion when someone queries the log and tries to `git show` the SHA.

---

## What Went Well

1. **All Round 1 issues addressed directly.** The revision log maps each fix to its source finding (RT-F1 through RT-F5, FS-C1, FS-C2, FS-M1 through FS-M3). No findings were dismissed or hand-waved.

2. **Helper script architecture is sound.** The separation of concerns is clean: SKILL.md defines *when* to emit events (one-liner calls), `emit-audit-event.sh` defines *how* to emit events (JSON construction, HMAC, sequencing). Changes to emission logic require modifying one file, not three SKILL.md files.

3. **State file lifecycle is correct.** Created in Step 0, read by helper script in Steps 1-7, deleted in Step 6 cleanup. The state file contains exactly the information the helper script needs (run_id, log path, skill, version, maturity, hmac_key). No redundant or missing fields.

4. **Test plan is significantly improved.** Round 1 identified a gap (no multi-call integration test). Round 2 adds Test G (multi-call JSONL production), Test H (L3 HMAC chain across calls), and Test J (10+ invocation state persistence). These directly exercise the actual runtime pattern.

5. **OTel migration honesty.** The revision upgrades the OTel assessment from "trivial field rename" to "span hierarchy reconstruction required." The adapter effort estimate (50-100 lines of Python, medium complexity) is realistic. The recommendation to defer until Kagenti provides a collector is pragmatic.

6. **0600 key permission model is adequate.** For the stated threat model (developer-level tamper detection, not adversarial prevention), restricting the key file to owner-read-write is proportionate. The plan correctly identifies that Kagenti/OTel with SPIFFE signing is the path to adversarial-grade integrity.

---

## Recommendations

1. **[Minor] Use `sys.argv` for state file creation (m1).** Replace shell interpolation into Python string literals with argument passing. Prevents a future injection surface if character sets change.

2. **[Minor] Add orphaned state file cleanup to Step 0 (m2).** Extend the existing cleanup block to remove `.ship-audit-state-*.json` files from previous aborted runs.

3. **[Minor] Clarify `commit_sha` semantics (m3).** Rename to `head_sha` or document the pre-commit semantics in the schema.

---

## Technical Soundness Assessment

| Component | Assessment |
|-----------|------------|
| Helper script architecture (`scripts/emit-audit-event.sh`) | Sound. Stateless per invocation, reads from disk, appends to log, exits. No cross-call dependencies. |
| State file lifecycle (`.ship-audit-state-${RUN_ID}.json`) | Correct. Created Step 0, read Steps 1-7, deleted Step 6. Single writer (Step 0), single reader (helper script). |
| Sequence derivation (`wc -l`) | Sound. Append-only JSONL with one line per event makes line count a reliable sequence source. |
| JSON escaping (`python3 json.dumps`) | Sound. Handles all RFC 8259 control characters. Fallback to raw string is documented. |
| L3 HMAC chain with persisted key | Adequate for stated threat model. Key committed at L3 means tamper detection, not prevention. Clearly documented. |
| Key file permissions (0600) | Adequate. Prevents casual read by other users on shared systems. Not a defense against root. |
| Symlink check before write | Sound. Prevents the symlink-to-sensitive-file attack on the predictable log path. |
| Step 6 verification (run_start, event count, security_decision) | Sound. Non-blocking verification is the right choice -- logging failure should not prevent shipping code. |
| SKILL.md size increase (~50 lines, ~5%) | Acceptable. One-liner calls keep the addition minimal. |
| Test plan | Adequate. Multi-call integration tests (G, H, J) exercise the actual runtime pattern. Schema validation (D) and utility help tests (E, F) provide basic coverage. |

---

<!-- Context Metadata
discovered_at: 2026-03-27T23:45:00Z
claude_md_exists: true
plan_reviewed: plans/ship-run-audit-logging.md (Rev 2)
skill_files_reviewed: skills/ship/SKILL.md (v3.5.0, 944 lines)
prior_feasibility_reviewed: plans/ship-run-audit-logging.feasibility.md (Round 1)
round: 2
prior_findings_resolved: 5/5 (C1, C2, M1, M2, M3)
new_findings: 0 Critical, 0 Major, 3 Minor
-->
