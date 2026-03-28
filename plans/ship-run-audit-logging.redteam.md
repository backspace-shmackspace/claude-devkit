# Red Team Review: Ship Run Audit Logging (Round 2)

**Plan:** `plans/ship-run-audit-logging.md` (Rev 2)
**Reviewer:** security-analyst (red team mode)
**Date:** 2026-03-27
**Round:** 2 (previous round: FAIL, 1 Critical / 4 Major / 3 Minor / 2 Info)
**Frameworks Applied:** STRIDE, DREAD, threat-model-gate checklist

---

## Verdict: PASS

All Round 1 Critical and Major findings have been resolved. The revision demonstrates genuine architectural corrections rather than cosmetic patches. Two new Minor findings were introduced by the revision. No new Critical or Major issues.

---

## Round 1 Finding Resolution

### F1 (was Critical): L3 HMAC Key Unverifiable Post-Run -- RESOLVED

**Round 1 issue:** The HMAC key was ephemeral (shell variable), lost when the session ended, making the L3 chain unverifiable after the run. This undermined the entire L3 value proposition.

**Resolution in Rev 2:** The plan now persists the HMAC key to a dedicated file (`.ship-audit-key-${RUN_ID}`, mode 0600) at Step 0 (lines 908-913). The key file is committed alongside the log at L3 (lines 557-563). The `verify-chain` command in the query utility reads from this persisted key file (line 598). The trade-offs section (line 56) explicitly documents the accepted limitation: persisting the key means an attacker with filesystem access could read the key and forge the chain. The plan correctly frames L3 as "tamper detection for uncoordinated modifications, not tamper prevention against an adversary with full filesystem access" (line 1081).

**Assessment:** Satisfactory. The plan chose option 1 from the Round 1 remediation list (persist key to disk) rather than option 3 (asymmetric signing). This is the pragmatic choice -- it delivers verifiable chains with the lowest implementation complexity. The security boundary is clearly documented. The Deviations table (line 1081) is honest about what L3 does and does not provide.

**Residual risk:** Medium. An attacker with repo write access at L3 can read the key and forge the chain. This is accepted and documented. Kagenti/OTel is the path to proper signing.

---

### F4 (was Major, reclassified to architectural): Shell State Persistence -- RESOLVED

**Round 1 issue:** The inline bash function defined in Step 0 would not exist in subsequent Bash tool calls because Claude Code spawns a fresh shell for each invocation. All audit events after Step 0 would silently fail.

**Resolution in Rev 2:** The plan replaces the inline function with a standalone helper script `scripts/emit-audit-event.sh` (Section 2, lines 362-458). Each step invokes it as a one-liner (lines 481-491). All per-run state is stored in a JSON state file on disk (`.ship-audit-state-${RUN_ID}.json`, lines 378-391). The sequence counter is derived from `wc -l` of the log file (line 421), eliminating the need for a persistent shell variable. The HMAC previous hash is read from the last line of the log file (line 436), eliminating `AUDIT_PREV_HMAC` as a shell variable.

**Assessment:** Satisfactory. This is a clean architectural fix that eliminates the entire class of cross-call state problems. The state file approach (create once at Step 0, read from disk on every call) is the correct pattern for the Claude Code execution model. The pseudocode in lines 406-448 demonstrates the approach clearly.

One observation: the state file is a JSON file parsed with `python3` (line 418, "parse state file with python3 for reliability"). This is appropriate given the plan already uses `python3` for JSON escaping. The `python3` dependency is documented in Assumptions (line 102).

---

### F2 (was Major): security_decision Verification -- RESOLVED

**Round 1 issue:** Step 6 verification only checked that `run_start` existed. It did not verify event counts or the presence of `security_decision` events, contradicting the plan's own STRIDE mitigations.

**Resolution in Rev 2:** Step 6 verification (lines 512-572) now includes three checks:
1. `run_start` existence (line 523)
2. Minimum event count against a threshold (lines 528-530)
3. `security_decision` event presence when security skills are deployed (lines 534-544) -- this checks whether `secrets-scan`, `secure-review`, or `dependency-audit` skills exist in `~/.claude/skills/` and, if any are deployed, verifies that at least one `security_decision` event was logged

The STRIDE analysis (line 150) now correctly labels the residual risk as "High" rather than "Medium", acknowledging this is a detective control.

**Assessment:** Satisfactory. The verification is substantively more robust. The check for deployed security skills (via `ls ~/.claude/skills/*/SKILL.md`) is the right approach -- it ties the expected events to the actual skill deployment state rather than hardcoding assumptions.

---

### F3 (was Major): JSON Escaping -- RESOLVED

**Round 1 issue:** The `_audit_escape` bash function missed carriage returns, form feeds, and RFC 8259 control characters (0x00-0x1F).

**Resolution in Rev 2:** The plan replaces `_audit_escape` with `python3 -c "import json,sys; print(json.dumps(sys.argv[1])[1:-1])"` (lines 397, 427-428). The trade-offs table (line 57) documents the decision and rationale. The fallback to `printf '%s'` when `python3` is unavailable preserves the non-blocking principle.

**Assessment:** Satisfactory. `json.dumps()` handles all RFC 8259 escaping requirements by definition. The `[1:-1]` slice correctly strips the surrounding double quotes that `json.dumps` adds to strings. The fallback path is documented as a degradation (risk of invalid JSON) rather than silent success.

---

### F5 (was Major): OTel Mapping Semantic Mismatches -- RESOLVED

**Round 1 issue:** The plan claimed OTel migration was a "format adapter, not a schema redesign" while having semantic gaps (run_id is not a valid trace_id, flat events do not encode span hierarchy, sequence number was dropped in the mapping).

**Resolution in Rev 2:** The plan now includes an honest OTel Migration Assessment section (lines 623-641) that explicitly states "The migration from JSONL to OTel spans is not a trivial field rename. It requires a format adapter that performs span hierarchy reconstruction." The section details four specific challenges:

1. **trace_id generation** (line 627): Correctly notes `run_id` format is not a valid OTel `trace_id` and the adapter must generate a conformant one, carrying `run_id` as baggage.
2. **Span hierarchy reconstruction** (lines 629-633): Correctly notes the flat event sequence has no parent-child encoding. The adapter must infer hierarchy from step naming conventions. Correctly acknowledges this is "fragile and convention-dependent."
3. **Concurrent spans** (line 635): Correctly notes Steps 4a/4b/4c run in parallel and must produce sibling spans.
4. **Sequence preservation** (lines 636-637): `sequence` is now preserved in the OTel mapping as span attribute `devkit.ship.sequence` (line 216), with the rationale that OTel timestamps do not guarantee ordering.

The OTel Field Mapping table (lines 199-220) includes migration notes for fields where the mapping is non-trivial, particularly `run_id` (line 203) and `parent_step` (line 210).

**Assessment:** Satisfactory. The plan no longer oversells the OTel migration path. The effort estimate ("Medium... 50-100 lines of Python... bounded, well-defined task" at line 639) is reasonable. The recommendation to defer building the adapter until Kagenti provides a collector (line 641) is pragmatic.

**One note:** The plan did not adopt the Round 1 suggestion to generate `run_id` as a 128-bit UUID directly usable as a `trace_id`. The plan retains the human-readable format (`20260327-143052-a1b2c3`) and documents that the adapter must generate a separate `trace_id`. This is an acceptable design choice -- the human-readable format is more useful for the file-based approach (grepping, visual identification), and UUID generation adds complexity to the bash helper script for a benefit that only materializes during OTel migration.

---

### Round 1 Minor/Info Findings Status

| ID | Severity | Status | Notes |
|----|----------|--------|-------|
| F6 | Major | Addressed | CRA compliance claim is now scoped as "infrastructure that enables future CRA compliance" (line 1106). The Next Steps section explicitly states CRA event type mapping is "future work contingent on compliance team input." |
| F7 | Minor | Partially addressed | Failure modes table added (lines 160-167) covering `openssl` unavailability, `python3` unavailability, `/dev/urandom` not readable, directory not writable, disk full, concurrent runs. Assets still lack CIA triads per threat-model-gate checklist, but this is an Info-level gap for the plan's maturity. |
| F8 | Minor | Addressed | The timestamp fallback is now documented as `date -u` with fallback to `date` without `-u` (line 726). The identical-fallback bug from Rev 1 is eliminated. |
| F9 | Minor | Addressed | Concurrent /ship runs are documented as a git concurrency issue (line 167, line 725). |
| F10 | Info | Acknowledged | Log accumulation noted in Risks (line 722). The plan suggests documentation for periodic cleanup rather than automated rotation. Acceptable for the file-based approach. |
| F11 | Info | Addressed | The chicken-and-egg problem with `run_end` timing is now explicitly documented as a "Known limitation" (lines 344-344) with clear language: "`commit_sha` should be treated as 'last known HEAD at run completion' rather than 'the commit containing this run's changes.'" This is honest documentation of a genuine design tension. |

---

## New Findings (Introduced by Rev 2)

### N1 -- State File Contains HMAC Key in Plaintext JSON [Minor]

The state file `.ship-audit-state-${RUN_ID}.json` contains the HMAC key at L3 (line 391: `"hmac_key": "<64-char-key>"`). The state file is created at Step 0 and deleted at Step 6 (line 569). During the run (potentially minutes to hours), the key exists in plaintext in a predictable path in the working directory.

The key file (`.ship-audit-key-${RUN_ID}`, mode 0600) also persists the key, but at least has restricted permissions. The state file has no documented permission restriction.

**Risk:** Low. The state file has a short lifetime (deleted at Step 6). Anyone with access to the working directory during a run can already read the audit log, the code, and everything else. The HMAC key protects against post-run tampering, not during-run access.

**Remediation:** Add `chmod 600 "$STATE_FILE"` after creation. This is a one-line addition that aligns the state file's permissions with the key file's permissions. The `.gitignore` already covers state files (line 669).

---

### N2 -- `PLAN_PATH` and `SECURITY_OVERRIDE_REASON` Interpolated into JSON String [Minor]

In the Step 0 state file creation block (lines 916-928), `${RUN_ID}`, `${AUDIT_LOG}`, `${SECURITY_MATURITY}`, and `${HMAC_KEY}` are interpolated into a Python string that constructs JSON. This is safe for these values because they are internally generated (no user input in RUN_ID, AUDIT_LOG, or HMAC_KEY; SECURITY_MATURITY is one of three fixed strings).

However, in the `run_start` emission (lines 931-934), `${PLAN_PATH}` is interpolated into a JSON string argument to the helper script. Plan file paths could theoretically contain characters that break the JSON structure (double quotes, backslashes, single quotes). The helper script uses `python3 json.dumps()` for escaping values it constructs, but the event JSON passed as `$2` to the script is a raw JSON string constructed in the SKILL.md bash block, not processed through the escaping function.

Similarly, `${SECURITY_OVERRIDE_REASON}` (a user-provided string) is interpolated into event JSON arguments at security decision emission points (not shown in the plan's Step 0 example, but implied by the instrumentation table at line 496).

**Risk:** Low. Plan file paths in this codebase follow simple naming conventions (alphanumeric, hyphens, dots). Override reasons are typed by the user who is running `/ship` on their own machine. This is not a remote injection vector. But a path containing `"` or `'` would produce malformed JSON that silently fails (the helper script appends to the log with `|| true`).

**Remediation:** The helper script should validate that `$2` (the partial event JSON) is valid JSON before merging it with common fields. The pseudocode (line 418) shows `# ... parse state file with python3 for reliability ...` but does not show validation of the event JSON argument. Add: `python3 -c "import json,sys; json.loads(sys.argv[1])" "$EVENT_JSON" 2>/dev/null || { echo "Warning: invalid event JSON" >&2; exit 0; }` at the top of the script.

---

## STRIDE Verification (Rev 2)

Verifying that the Round 1 STRIDE supplemental findings have been addressed.

### Spoofing

**Round 1 supplemental:** No identity field for agent instances; coder events lack `work_group` differentiation.

**Rev 2 status:** The `file_modification` event includes `work_group` and `work_group_name` (lines 321-322). The `step_start` event for coder steps includes `work_groups` count (line 252) but not the specific `work_group` index. This is a partial improvement. Full agent identity resolution is correctly deferred to Kagenti/SPIFFE.

### Tampering

**Round 1 supplemental:** Step 6 should verify the L3 HMAC chain, not just check for `run_start`.

**Rev 2 status:** Step 6 verification (lines 512-572) does not invoke the `verify-chain` command during the /ship workflow itself. It checks event counts and security_decision presence, but does not replay the HMAC chain. The chain verification remains a post-hoc operation via `scripts/audit-log-query.sh verify-chain <run_id>`.

This is an acceptable trade-off: HMAC chain verification at Step 6 adds complexity and latency for a check that is most valuable post-run (auditor reviewing historical logs), not mid-run. The Step 6 checks are already substantively better than Round 1.

### Repudiation

**Round 1 supplemental:** Residual risk should be Medium, not Low, for L3.

**Rev 2 status:** The STRIDE analysis (line 152) now rates the residual risk as "Medium (not Low) because the LLM self-reports -- there is no independent observer until Kagenti." This is correct.

---

## Summary of Findings by Severity

| Severity | Count | IDs | Notes |
|----------|-------|-----|-------|
| Critical | 0 | -- | F1 resolved |
| Major | 0 | -- | F2, F3, F4, F5 all resolved |
| Minor | 2 | N1, N2 | New findings from revision; both Low risk |
| Info | 0 | -- | -- |

## Recommendation

**Approve this plan.** All Round 1 blocking findings are resolved with genuine architectural corrections. The two new Minor findings (N1: state file permissions, N2: event JSON validation) are Low risk and can be addressed during implementation without plan revision.

The plan demonstrates intellectual honesty about its limitations (L3 tamper detection vs prevention, OTel migration complexity, LLM self-reporting trust gap, `run_end` timing). This honesty is more valuable than false claims of stronger guarantees.

---

<!-- Context Metadata
reviewed_at: 2026-03-27T23:45:00Z
plan_version: Rev 2 (2026-03-27)
previous_review: Round 1 FAIL (2026-03-27T23:00:00Z)
frameworks: STRIDE, DREAD, threat-model-gate v1.0.0
severity_counts: {critical: 0, major: 0, minor: 2, info: 0}
verdict: PASS
round_1_findings_resolved: F1, F2, F3, F4, F5
round_1_findings_partially_addressed: F6, F7, F8, F9
round_1_findings_acknowledged: F10, F11
new_findings: N1, N2
-->
