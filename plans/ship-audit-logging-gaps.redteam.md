# Red Team Review (Round 2): ship-audit-logging-gaps

**Plan:** `plans/ship-audit-logging-gaps.md`
**Reviewer:** Red team (critical analysis, Round 2)
**Date:** 2026-03-28

---

## Verdict: PASS

No Critical findings. All five Round 1 findings have been addressed. Three new Minor findings and two Info findings identified in the revision.

---

## Previous Findings Status

### F1 -- Step 4 instrumentation deviation (was Critical) -- RESOLVED

The revised plan replaces the single `step_4_verification` wrapper with retrospective per-substep markers (`step_4a_code_review`, `step_4b_tests`, `step_4c_qa`, `step_4d_secure_review`). These are emitted during the coordinator's sequential result evaluation phase after all parallel Tasks complete, which is the correct architectural choice given the constraint that the coordinator cannot interleave Bash calls during parallel dispatch.

The plan explicitly documents the timing caveat (markers reflect evaluation order, not parallel execution timing) in both the Proposed Design section and the Deviations table. The identifiers match the parent plan's instrumentation table (lines 504-507). The OTel span hierarchy reconstruction path is preserved.

Verified: The Deviations table entry is thorough and honest about the limitation.

**Status: Resolved.**

### F2 -- Step 6 FAIL path state file assumption (was Major) -- RESOLVED

The revised plan restructures the Step 6 flow with explicit PASS/FAIL path separation:
- The finalization bash block (including `rm -f`, `run_end`, `git add`, archive) is explicitly placed under the `**If PASS or PASS_WITH_NOTES:**` conditional header.
- The FAIL path gets a dedicated bash block that emits `step_end` and `run_end` before cleaning up the state file.
- The plan explicitly states "Do NOT run the finalization block above" under the FAIL path.

The structural guarantee is sound: on the FAIL path, the finalization block is skipped (it lives under the PASS conditional), so the state file survives for the FAIL-path emit calls. On the PASS path, the state file is now kept alive through Step 7 (cleanup moved to Step 7 end).

Verified against the current SKILL.md (line 1110): the existing `rm -f` is inside the finalization block that the plan moves under the PASS conditional.

**Status: Resolved.**

### F3 -- Integration test output suppression (was Major) -- RESOLVED

The revised plan modifies the `run_test` function to capture stdout/stderr to a temp file via `mktemp`, display the first 20 lines on failure, and clean up the temp file. This directly addresses the debugging concern.

One minor observation: the proposed code uses `cat "$test_output_file" | head -20` which is a useless-use-of-cat (could be `head -20 "$test_output_file"`), but this is cosmetic and does not affect correctness.

**Status: Resolved.**

### F4 -- Test variable escaping fragility (was Major) -- RESOLVED

The revised plan replaces inline `python3 -c` strings with temp-file python3 verification scripts written via heredoc. Shell variables are expanded during the heredoc write (unquoted delimiter `PYEOF`), and `python3` reads the temp file. This eliminates the triple-level escaping chain entirely.

Verified: The test code in the plan uses `cat > "$VERIFY_SCRIPT" <<PYEOF` with an unquoted delimiter, which means `$TEST_RUN_ID`, `$TEST_LOG`, and `$TEST_HMAC_KEY` are expanded by the shell during the write. The resulting python3 script contains literal string values, not shell variable references. The `python3 "$VERIFY_SCRIPT"` call then executes pure python3 with no escaping concerns.

**Status: Resolved.**

### F5 -- Step 5 conditional emit calls (was Major) -- RESOLVED

The revised plan adds explicit conditional language to both Step 5 emit call insertion points:
- "These emit calls are conditional on Step 5 actually executing. If Step 4 code review returned PASS, skip this entire Step 5 section including these emit calls."
- "MUST NOT execute if Step 5 is skipped."
- The preamble in Proposed Design section 3 reinforces: "These emit calls are part of Step 5 and MUST NOT execute if Step 5 is skipped."

The coordinator's existing conditional trigger at the top of Step 5 ("Trigger: Step 4 code review verdict is REVISION_NEEDED") provides the structural boundary. The redundant explicit language in the emit call instructions provides a safety net for the LLM coordinator.

**Status: Resolved.**

---

## Previous Minor/Info Findings Status

### F6 -- No run_end on non-Step-6 failure paths (was Minor) -- ACKNOWLEDGED

The plan does not address this, which is appropriate since its scope is Steps 4/5/6/7. The plan's Non-Goals section does not explicitly mention this gap, but the scope limitation is clear from the Context and Goals sections. The parent plan specification ("emitted once at the end of the run (Step 6 or on workflow stop)") remains partially unfulfilled for early-exit paths.

**Status: Acknowledged (out of scope). Remains a gap for future work.**

### F7 -- Stale commit_sha in run_end (was Minor) -- ACKNOWLEDGED

The plan preserves the existing `run_end` position (before the commit) and does not move it post-commit even though the state file now survives through Step 7. The revised plan does not acknowledge this missed opportunity.

**Status: Acknowledged (not addressed, but not a regression).**

### F8 -- wc -l fix edge case (was Minor) -- ACKNOWLEDGED

The proposed `[ -f "$AUDIT_LOG" ]` conditional fix is unchanged in the revision. The edge case (permission denied on an existing file) remains theoretically possible but practically unlikely. The script's "always exit 0" design note (line 27) is violated under this edge case, but the fix is still a strict improvement over the original code (which failed on the common case of a nonexistent file).

**Status: Acknowledged (accepted risk).**

### F9 -- EXPECTED_MIN threshold not updated (was Minor) -- NOT ADDRESSED

The plan adds ~12 new events for a typical run (4 substep pairs x 3 events each for Step 4, plus 2 events for Step 5 when triggered). The `EXPECTED_MIN=5` threshold in Step 6 verification (line 1069 of current SKILL.md) remains unchanged. With full instrumentation, a run reaching Step 6 should have at least 25+ events. A threshold of 5 catches only catastrophic logging failures, not instrumentation regressions.

The revision does not mention this. The plan's Risks table notes "With more events emitted, the minimum threshold becomes more meaningful" -- this is backwards reasoning. More events makes a low threshold *less* meaningful because it has less discriminating power.

**Status: Not addressed. See N3 below.**

### F10 -- No version bump ambiguity (was Info) -- ACKNOWLEDGED

Unchanged. The justification in the Deviations table is reasonable.

### F11 -- Rollout ordering (was Info) -- ACKNOWLEDGED

Unchanged. Ships as a single commit, so the ordering is documentation only.

### F12 -- Test H HMAC key ordering assumption (was Info) -- RESOLVED

The revised plan adds a comment in the Test H python3 code: "NOTE: This test assumes json.dumps preserves insertion order (CPython 3.7+). If emit-audit-event.sh changes its JSON serialization order, this test will fail with an HMAC mismatch -- not a chain corruption bug."

**Status: Resolved.**

---

## New Findings

### N1 -- Test H HMAC verification uses openssl but test does not verify openssl availability (Minor)

Test H creates an L3 state file with `security_maturity=audited` and a known HMAC key. The `emit-audit-event.sh` script computes HMAC via `openssl dgst -sha256 -hmac "$HMAC_KEY"` (line 203). If `openssl` is not available on the test machine, the script falls back to inserting an empty `hmac` field (lines 213-222). The test then asserts `event['hmac'] != ''` and `stored_hmac == expected`, both of which will fail.

The test would report "HMAC mismatch" or "empty hmac" rather than "openssl not found," making the failure confusing. The test should include a pre-check `which openssl >/dev/null 2>&1 || { echo "SKIP: openssl not available"; exit 0; }` or the plan should note that `openssl` is a test prerequisite.

In practice, `openssl` is available on all target platforms (macOS includes LibreSSL, Linux distributions include OpenSSL), so this is unlikely to cause real failures.

**Severity: Minor.**

### N2 -- FAIL-path run_end emits outcome "failure" but parent plan schema says "success" or "failure" without defining when "failure" is used (Minor)

The proposed FAIL-path bash block in Proposed Design section 4 emits:

```json
{"event_type":"run_end","outcome":"failure","plan_file":"..."}
```

The parent plan's `run_end` schema example (line 326-342) shows `"outcome": "success"` in the example but does not define the enum of valid `outcome` values. The existing Step 6 finalization block emits `"outcome":"success"`. The plan introduces `"outcome":"failure"` for the FAIL path without verifying this is a recognized value in the schema.

Checking `configs/audit-event-schema.json` would confirm whether `"failure"` is valid. The plan's Non-Goals say "Adding new event types or schema changes" is out of scope, but `outcome: "failure"` may constitute a new enum value rather than a new event type.

In practice this is likely fine since the schema is descriptive (JSONL is schema-flexible), and "failure" is the obvious complement to "success." But the plan should at least note the assumption.

**Severity: Minor.**

### N3 -- EXPECTED_MIN=5 not updated despite plan adding 12+ new events per run (Minor)

Carried forward from F9 (Round 1). The plan adds retrospective per-substep markers for Step 4 (12 events: 4 substep x step_start + verdict/security_decision + step_end) and Step 5 boundary events (2 events when triggered). A successful run reaching Step 6 will now produce approximately 30+ events.

The `EXPECTED_MIN=5` threshold was set when instrumentation was sparse. With the plan's additions, 5 is only ~16% of the expected event count. A threshold of 15-20 would catch real instrumentation regressions (e.g., if a future SKILL.md edit accidentally removes the Step 4 emit block) while still allowing for early-exit runs (which produce fewer events).

The plan's acceptance criteria (item 2) says "Steps 4a/4b/4c/4d have retrospective per-substep step_start/step_end markers and verdict/security_decision events" -- but the Step 6 verification check's low threshold means this acceptance criterion has no runtime enforcement. If the LLM coordinator skips the Step 4 emit block, the Step 6 check will not catch it (5 events from Steps 0-3 alone exceeds the threshold).

Updating `EXPECTED_MIN` is a one-line change that falls within the plan's scope ("Fix Step 6 step_end ordering bug" already modifies the finalization block). The plan should either update the threshold or add it as a known gap.

**Severity: Minor.**

### N4 -- Cleanup test renumbering may break CI references (Info)

The plan renumbers the existing Cleanup test from Test 5 to Test 9 to accommodate the three new tests (6, 7, 8). The current Cleanup test (lines 112-124 of `test-integration.sh`) is not a `run_test` call -- it is inline code with a manual `echo -e "${BLUE}Test 5: Cleanup${RESET}"`. If any CI configuration or documentation references "Test 5" by name, the renumbering could cause confusion.

In practice, no CI references to specific test numbers were found in the codebase. The renumbering is safe.

**Severity: Info.**

### N5 -- Step 4 retrospective markers produce 12 sequential Bash calls in a single evaluation phase (Info)

The Step 4 emit block contains 12 `bash scripts/emit-audit-event.sh` calls (3 per substep x 4 substeps). Each call spawns a bash subprocess, reads the state file, invokes python3 multiple times (for JSON construction), and appends to the log file. This adds approximately 3-5 seconds of wall-clock time to every /ship run (12 process spawns, each involving python3 startup).

The plan's Risks table notes "Each emit call is ~3 lines. With retrospective per-substep markers, adding ~60 lines to the existing file is ~5% increase." This addresses prompt token impact but not execution time. The execution time cost is acceptable (3-5 seconds in a workflow that typically takes 5-10 minutes), but the plan should acknowledge it as a tradeoff.

A future optimization could batch all 12 calls into a single python3 invocation that appends 12 lines, but this is premature optimization and not worth addressing in this plan.

**Severity: Info.**

---

## Summary

| Severity | Count | Findings |
|----------|-------|----------|
| Critical | 0 | -- |
| Major | 0 | -- |
| Minor | 3 | N1 (openssl test prereq), N2 (outcome "failure" schema validation), N3 (EXPECTED_MIN threshold) |
| Info | 2 | N4 (test renumbering), N5 (12 sequential Bash calls) |

All five Round 1 findings (F1-F5) are resolved. The revision addresses each finding substantively rather than superficially. The retrospective per-substep marker design (F1 resolution) is the most significant change and is well-reasoned -- it preserves the parent plan's schema contract while honestly documenting the timing limitation.

The three Minor findings (N1, N2, N3) are implementable as small additions during the implementation phase. N3 (EXPECTED_MIN update) is the most impactful because it provides runtime enforcement of the plan's core deliverable (Step 4 instrumentation).
