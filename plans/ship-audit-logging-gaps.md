# Plan: Ship Audit Logging Gaps -- Instrumentation Completion, Bug Fixes, and Integration Tests

## Revision Log

| Rev | Date | Trigger | Summary |
|-----|------|---------|---------|
| 1 | 2026-03-28 | QA PASS_WITH_NOTES gaps + code review m1 from ship-run-audit-logging | (1) Add emit calls to Steps 4a/4b/4c/4d, Step 5, and Step 7. (2) Fix Step 6 step_end ordering bug (emitted after state file deletion, always silently dropped). (3) Create integration tests G/H/J. (4) Fix emit-audit-event.sh wc -l first-invocation bug. |
| 2 | 2026-03-28 | Red team FAIL + librarian/feasibility review findings | (F1) Emit retrospective per-substep step_start/step_end markers during result evaluation instead of a single step_4_verification wrapper. (F2) Wrap Step 6 finalization block in PASS-path conditional; restructure FAIL path to emit before state file exists concern. (F3) Capture test output to temp file and display on failure instead of /dev/null. (F4) Eliminate triple-level escaping in tests by writing python3 verification to temp scripts. (F5) Add explicit conditional language to Step 5 emit calls. Librarian: replace line-number references with section-relative anchors; align Goals wording with retrospective marker design. |

## Context

The `ship-run-audit-logging` plan (APPROVED, shipped in commit 0204f26) introduced structured JSONL audit logging for `/ship`, `/architect`, and `/audit` skills. The implementation was shipped with a PASS_WITH_NOTES QA verdict and a PASS code review verdict. Both review artifacts documented specific gaps that were deferred to a follow-up:

1. **QA Gap 1 (Partial):** Steps 4a/4b/4c/4d and Step 5 have zero emit calls. The plan's instrumentation table requires verdict events for code review, tests, QA, and secure review, plus step boundary events for the revision loop. These are the most operationally significant events for accountability.

2. **QA Gap 3 (Partial):** Integration tests G, H, and J from the parent plan were specified but never created. The test suite has 5 general smoke tests but no audit-logging-specific integration tests.

3. **Code Review m1:** Step 6 `step_end` is emitted in a `Bash` block positioned after the finalization block that deletes the state file (`rm -f ".ship-audit-state-${RUN_ID}.json"`). Since `emit-audit-event.sh` exits 0 silently when the state file is missing, `step_end` is always dropped. No execution path for Step 6 produces a `step_end` event.

4. **Bug discovered during /architect run:** `emit-audit-event.sh` line 124 uses `wc -l < "$AUDIT_LOG" 2>/dev/null` to derive the sequence counter. On first invocation, the log file does not exist yet. The `<` redirect on a nonexistent file produces a shell error. The `2>/dev/null` only suppresses `wc`'s stderr, not the shell's redirect error. Under `set -euo pipefail` (line 30), this causes the script to exit before reaching the append operation, meaning the first event is silently dropped.

**Parent plan:** `plans/ship-run-audit-logging.md` (Status: APPROVED, shipped)

**Current skill versions:** ship v3.6.0, architect v3.2.0, audit v3.2.0

**Current test counts:** `generators/test_skill_generator.sh` (53 tests), `scripts/test-integration.sh` (5 tests), `scripts/validate-all.sh` (15 skills)

## Goals

1. **Add emit-audit-event.sh calls to Steps 4a, 4b, 4c, 4d** in `skills/ship/SKILL.md` -- retrospective per-substep `step_start`/`step_end` markers emitted during the coordinator's sequential result evaluation (after parallel Tasks complete), plus `verdict` events for code review, tests, QA, and a `security_decision` event for secure review. This preserves the parent plan's per-substep boundary contract while respecting the constraint that the coordinator cannot interleave Bash calls during parallel Task dispatch.
2. **Add emit-audit-event.sh calls to Step 5** -- step boundary events for the revision loop, conditional on Step 5 actually executing (only when code review returns REVISION_NEEDED)
3. **Add emit-audit-event.sh call to Step 6 step_end** in the correct position (before state file deletion)
4. **Add emit-audit-event.sh calls to Step 7** -- verify existing calls are positioned correctly (they already exist but verify no ordering issues)
5. **Fix the Step 6 step_end ordering bug** -- move step_end emission before the `rm -f` state file cleanup
6. **Fix emit-audit-event.sh wc -l first-invocation bug** -- the `<` redirect on a nonexistent file fails under `set -euo pipefail`
7. **Create integration tests G, H, J** in `scripts/test-integration.sh` for multi-call JSONL correctness, L3 HMAC chain verification, and 10+ call state persistence

## Non-Goals

- Adding new event types or schema changes (the existing schema from the parent plan is sufficient)
- Modifying `/architect` or `/audit` instrumentation (those skills were instrumented in the parent plan and are out of scope)
- Adding negative tests for emit-audit-event.sh error paths (noted as Low in QA report; deferred)
- Bumping skill versions (no version bump needed -- these are gap-fills within the v3.6.0 instrumentation commitment)
- Modifying `audit-log-query.sh`, `audit-event-schema.json`, or any other tooling files

## Assumptions

1. The existing `emit-audit-event.sh` helper script is correct apart from the `wc -l` bug -- no other changes needed
2. The existing state file creation in Step 0 is correct and produces a valid state file for all subsequent calls
3. Steps 4a/4b/4c/4d run in parallel via Task calls -- the coordinator cannot interleave Bash calls during parallel dispatch, so per-substep `step_start`/`step_end` markers are emitted retrospectively during the coordinator's sequential result evaluation phase (after all Tasks complete)
4. Step 7 already has step_start and step_end emit calls (at the beginning and end of the Step 7 section in current SKILL.md) -- these only need verification, not new additions
5. The `$RUN_ID` variable is available in all steps because the coordinator retains it from Step 0 output

## Proposed Design

### 1. Fix emit-audit-event.sh wc -l First-Invocation Bug

**Current code (line 124):**
```bash
SEQUENCE=$(( $(wc -l < "$AUDIT_LOG" 2>/dev/null | tr -d ' ') + 1 ))
```

**Problem:** When `$AUDIT_LOG` does not exist (first invocation), the `<` input redirect fails at the shell level. The `2>/dev/null` suppresses `wc`'s stderr but not the shell's redirect error. Under `set -euo pipefail`, this causes immediate script exit before reaching the `printf '%s\n' "$FULL_EVENT" >> "$AUDIT_LOG"` append operation.

**Fix:** Replace the `< redirect` pattern with `wc -l` using a filename argument (which returns `0 filename` for nonexistent files gracefully) or use a conditional:

```bash
if [ -f "$AUDIT_LOG" ]; then
  SEQUENCE=$(( $(wc -l < "$AUDIT_LOG" | tr -d ' ') + 1 ))
else
  SEQUENCE=1
fi
```

This is the safest fix because:
- `wc -l < file` is fine when the file exists (the `<` redirect succeeds)
- When the file does not exist, we know the sequence is 1
- No `2>/dev/null` needed on the success path, preserving real errors
- The conditional check (`[ -f "$AUDIT_LOG" ]`) is the idiomatic pattern under `set -euo pipefail`

### 2. Add Emit Calls to Step 4 (Parallel Verification)

Step 4 dispatches four parallel tasks (4a code review, 4b tests, 4c QA, 4d secure review). The parent plan's instrumentation table (lines 504-507) specifies individual `step_start`/`step_end` boundaries for each substep. Since the substeps run as parallel Tasks, the coordinator cannot emit real-time start/end markers for each. Instead, we emit **retrospective per-substep markers** during the coordinator's sequential result evaluation phase (after all parallel Tasks complete). These markers preserve the parent plan's per-substep schema contract (`step_4a`, `step_4b`, `step_4c`, `step_4d` identifiers), enabling `audit-log-query.sh timeline` to display individual substep entries and future OTel migration to reconstruct per-substep spans.

**Timing caveat:** The retrospective markers reflect the order in which the coordinator evaluates results, not the actual parallel execution timing. Each substep's `step_start`/`step_end` pair brackets the coordinator's evaluation of that substep's result (reading the verdict, emitting events), not the Task's execution duration. This is documented as a known limitation.

The emit calls are positioned:

- **After all parallel Tasks complete, during sequential result evaluation:** For each substep in order (4a, 4b, 4c, 4d): `step_start(step_4X)`, then the `verdict` or `security_decision` event, then `step_end(step_4X)`

**Exact insertion points in SKILL.md:**

**After the "### Result evaluation" section** (after the L1/L2 result matrix and the stop/continue decision prose, before the "If stopping" output paragraph), insert:

```markdown
**Emit retrospective per-substep audit events for Step 4 results:**

The coordinator evaluates each substep's result sequentially below. For each substep, a `step_start`/`step_end` pair brackets the verdict emission. These are retrospective markers -- the parallel Tasks have already completed. The markers preserve the parent plan's per-substep identifiers (`step_4a`, `step_4b`, `step_4c`, `step_4d`) for timeline reconstruction.

The coordinator MUST replace VERDICT variables with actual values from the result evaluation above.

Tool: `Bash`

```bash
# Step 4a -- Code review retrospective markers
# CODE_REVIEW_VERDICT: "PASS", "REVISION_NEEDED", or "FAIL"
bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_start","step":"step_4a_code_review","step_name":"Code review (retrospective)","agent_type":"coordinator"}'

bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  "{\"event_type\":\"verdict\",\"step\":\"step_4a_code_review\",\"verdict\":\"${CODE_REVIEW_VERDICT}\",\"verdict_source\":\"code_review\",\"agent_type\":\"code-reviewer\"}"

bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_end","step":"step_4a_code_review","step_name":"Code review (retrospective)","agent_type":"coordinator"}'

# Step 4b -- Tests retrospective markers
# TEST_VERDICT: "PASS" or "FAIL"
bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_start","step":"step_4b_tests","step_name":"Tests (retrospective)","agent_type":"coordinator"}'

bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  "{\"event_type\":\"verdict\",\"step\":\"step_4b_tests\",\"verdict\":\"${TEST_VERDICT}\",\"verdict_source\":\"tests\",\"agent_type\":\"coordinator\"}"

bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_end","step":"step_4b_tests","step_name":"Tests (retrospective)","agent_type":"coordinator"}'

# Step 4c -- QA retrospective markers
# QA_VERDICT: "PASS", "PASS_WITH_NOTES", or "FAIL"
bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_start","step":"step_4c_qa","step_name":"QA (retrospective)","agent_type":"coordinator"}'

bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  "{\"event_type\":\"verdict\",\"step\":\"step_4c_qa\",\"verdict\":\"${QA_VERDICT}\",\"verdict_source\":\"qa\",\"agent_type\":\"qa-engineer\"}"

bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_end","step":"step_4c_qa","step_name":"QA (retrospective)","agent_type":"coordinator"}'

# Step 4d -- Secure review retrospective markers (conditional: only if gate ran)
# SECURE_REVIEW_GATE_VERDICT: "PASS", "PASS_WITH_NOTES", "BLOCKED", or "not-run"
# SECURE_REVIEW_ACTION: "pass", "block", "override", or "skip"
# SECURE_REVIEW_EFFECTIVE_VERDICT: "PASS", "PASS_WITH_NOTES", or "BLOCKED"
bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_start","step":"step_4d_secure_review","step_name":"Secure review (retrospective)","agent_type":"coordinator"}'

bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  "{\"event_type\":\"security_decision\",\"step\":\"step_4d_secure_review\",\"gate\":\"secure_review\",\"gate_verdict\":\"${SECURE_REVIEW_GATE_VERDICT:-not-run}\",\"action\":\"${SECURE_REVIEW_ACTION:-skip}\",\"effective_verdict\":\"${SECURE_REVIEW_EFFECTIVE_VERDICT:-PASS}\"}"

bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_end","step":"step_4d_secure_review","step_name":"Secure review (retrospective)","agent_type":"coordinator"}'
```
```

### 3. Add Emit Calls to Step 5 (Revision Loop)

Step 5 is conditional -- it only triggers when code review returns REVISION_NEEDED. **These emit calls are part of Step 5 and MUST NOT execute if Step 5 is skipped.** The coordinator follows the conditional trigger at the top of Step 5 ("Trigger: Step 4 code review verdict is REVISION_NEEDED"). If Step 4 passes and the coordinator proceeds directly to Step 6, the Step 5 section (including these emit calls) is skipped entirely.

The emit calls wrap the entire revision loop:

**Before the "### 5a -- Coder fixes" header** (inside the Step 5 conditional section, after the trigger paragraph), insert:

```markdown
**Emit step_start for Step 5 (only if Step 5 is executing):**

These emit calls are conditional on Step 5 actually executing. If Step 4 code review returned PASS, skip this entire Step 5 section including these emit calls.

Tool: `Bash`

```bash
bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_start","step":"step_5_revision_loop","step_name":"Revision loop","agent_type":"coordinator"}'
```
```

**After the "Max 2 revision rounds total" paragraph** (at the end of the Step 5 section, before Step 6), insert:

```markdown
**Emit step_end for Step 5 (only if Step 5 executed):**

Tool: `Bash`

```bash
bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_end","step":"step_5_revision_loop","step_name":"Revision loop","agent_type":"coordinator"}'
```
```

### 4. Fix Step 6 step_end Ordering Bug and FAIL-Path State File Issue

**Current bug:** The Step 6 `step_end` emit call is positioned after the finalization block that deletes the state file (`rm -f ".ship-audit-state-${RUN_ID}.json"`). Because `emit-audit-event.sh` exits 0 silently when the state file is missing, `step_end` is always dropped. The orphaned `step_end` block sits after the finalization bash block and the `**If FAIL:**` section.

**FAIL-path problem (F2):** The current SKILL.md structure has the finalization bash block appearing before the `**If PASS:**` / `**If FAIL:**` conditional prose. The coordinator reads linearly -- if the finalization block is not wrapped in a conditional, it may execute on both PASS and FAIL paths, deleting the state file before the FAIL-path emit calls can run.

**Fix (structural):** The finalization bash block in SKILL.md must be restructured so that:

1. **The finalization block is explicitly part of the PASS path.** Move it under the `**If PASS:**` section, or add a conditional wrapper (e.g., a preceding prose instruction: "Execute the following finalization block ONLY if the commit gate verdict is PASS or PASS_WITH_NOTES").
2. **The FAIL path has its own dedicated bash block** that emits `step_end` and `run_end` before cleaning up the state file.

**Specific changes:**

**Restructure the Step 6 finalization flow.** In the current SKILL.md, after the commit gate verdict evaluation:

```markdown
**If PASS or PASS_WITH_NOTES:**

Execute the finalization block below. (The existing finalization bash block is moved here, under this conditional header.)

[existing finalization bash block contents, with step_end inserted before rm -f]

```bash
  # ... existing finalization logic (commit, archive, etc.) ...

  # Emit step_end for Step 6 (MUST be before state file deletion)
  bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
    '{"event_type":"step_end","step":"step_6_commit_gate","step_name":"Commit gate","agent_type":"coordinator"}'

  # Do NOT delete state file here on PASS path -- Step 7 needs it for emit calls.
  # State file cleanup happens at the end of Step 7.
```

**If FAIL:**
- Do NOT commit.
- Do NOT run the finalization block above.

Tool: `Bash`

```bash
# Emit step_end for Step 6 on FAIL path, then run_end, then cleanup.
# The state file still exists because the finalization block (which contains rm -f) was skipped.
bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_end","step":"step_6_commit_gate","step_name":"Commit gate","agent_type":"coordinator"}'
bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  "{\"event_type\":\"run_end\",\"outcome\":\"failure\",\"plan_file\":\"${PLAN_PATH:-${ARGUMENTS:-unknown}}\"}"
rm -f ".ship-audit-state-${RUN_ID}.json"
```

- Output: "QA validation failed. See `./plans/[name].qa-report.md`."
- Stop the workflow.
```

Then remove the orphaned `**Emit step_end for Step 6:**` block that currently sits after the finalization section.

### 5. Verify Step 7 Emit Calls

Step 7 already has `step_start` and `step_end` emit calls (at the beginning and end of the Step 7 section in SKILL.md). However, Step 7 runs after the state file has been deleted in Step 6's finalization block. This means Step 7's emit calls will also be silently dropped.

**Fix:** The state file deletion must move from Step 6's finalization block to after Step 7 completes. Alternatively, emit step_end for Step 6 before state file deletion but keep the state file alive through Step 7, then delete it at the end of Step 7.

**Chosen approach:** Remove the `rm -f ".ship-audit-state-${RUN_ID}.json"` from Step 6's finalization block on the PASS path. Add state file cleanup at the end of Step 7 instead (after step_end emission). On the FAIL path (Step 6), the state file is still cleaned up immediately since Step 7 is skipped.

**Changes to Step 6 finalization block (PASS path):**

Remove the `rm -f ".ship-audit-state-${RUN_ID}.json"` line from the finalization bash block:
```bash
  # Cleanup state file (not needed after run)
  rm -f ".ship-audit-state-${RUN_ID}.json"
```

**Changes to Step 7 (end of step):**

After the existing `step_end` emission (at the end of the Step 7 section), add state file cleanup:

```bash
bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_end","step":"step_7_retro","step_name":"Retro capture","agent_type":"coordinator"}'

# Final cleanup: remove audit state file (kept alive through Step 7 for event emission)
rm -f ".ship-audit-state-${RUN_ID}.json"
```

### 6. Integration Tests G, H, J

Add three new integration tests to `scripts/test-integration.sh` that exercise `emit-audit-event.sh` in isolation (no LLM required).

**Test output capture (F3 fix):** The existing `run_test` function redirects all output to `/dev/null`. For these tests (which use `python3 -c` assertions), this makes debugging failures impossible. Modify `run_test` to capture stdout/stderr to a temp file and display the captured output on failure. Change:

```bash
eval "$test_command" > /dev/null 2>&1
```

to:

```bash
local test_output_file
test_output_file=$(mktemp)
eval "$test_command" > "$test_output_file" 2>&1
local actual_exit=$?
if [ "$actual_exit" -ne "$expected_exit" ]; then
  echo "  Output:"
  cat "$test_output_file" | head -20
fi
rm -f "$test_output_file"
```

**Test variable escaping (F4 fix):** The tests use `python3 -c` with assertions that reference shell variables. To avoid triple-level escaping fragility (plan markdown -> bash string -> eval -> python3 -c), each test writes its python3 verification script to a temp file and executes it. This eliminates all escaping concerns -- the python3 code is written as a heredoc to a temp file, shell variables are expanded during the write, and `python3` reads the temp file.

**Test G (Test 6): Multi-call JSONL emission correctness**
- Create a state file with advisory maturity (no HMAC)
- Call `emit-audit-event.sh` three times in separate bash invocations (simulating separate Bash tool calls)
- Write a python3 verification script to a temp file (shell variables expanded during write)
- Verify: 3 lines in the JSONL file, each valid JSON, sequence numbers 1/2/3, correct `run_id`, `skill`, `skill_version` in every line, correct `event_type` values

**Test H (Test 7): L3 HMAC chain verification**
- Create a state file with `security_maturity=audited` and a known HMAC key
- Call `emit-audit-event.sh` three times
- Write a python3 verification script to a temp file (HMAC key ordering assumption: python3 json.dumps preserves insertion order on CPython 3.7+; test includes a comment noting this)
- Verify: each line has a non-empty `hmac` field, all three `hmac` values are different (chain, not static), chain is replayable by computing HMAC-SHA256(event_json + prev_hmac, key) for each event

**Test J (Test 8): 10+ call state persistence**
- Create a state file with advisory maturity
- Call `emit-audit-event.sh` 12 times with different event types (simulating a realistic ship run: run_start, step_start, step_end, verdict, security_decision, file_modification, run_end)
- Write a python3 verification script to a temp file
- Verify: 12 lines, correct sequence 1-12, all valid JSON, run_id consistent across all 12 events

## Interfaces / Schema Changes

None. All event types and fields already exist in `configs/audit-event-schema.json`. This plan adds emit calls for events that were already defined but never emitted.

## Data Migration

None.

## Rollout Plan

1. Fix `emit-audit-event.sh` wc -l bug (must be first -- all other changes depend on this working)
2. Restructure Step 6: wrap finalization block under PASS-path conditional, insert step_end before rm -f
3. Add Step 6 FAIL-path dedicated bash block (step_end, run_end, state file cleanup)
4. Move state file cleanup from Step 6 PASS path to end of Step 7
5. Add Step 4 retrospective per-substep emit calls (step_start/verdict/step_end for each of 4a-4d)
6. Add Step 5 conditional emit calls (step_start, step_end with explicit skip language)
7. Remove orphaned step_end block after Step 6
8. Modify `run_test` function to capture output and display on failure
9. Create integration tests G/H/J with temp-file python3 verification
10. Run full test suite
11. Deploy and verify

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| SKILL.md becomes longer (more prompt tokens) | Certain | Low | Each emit call is ~3 lines. With retrospective per-substep markers, adding ~60 lines to the existing file is ~5% increase. Well within acceptable bounds. |
| LLM does not faithfully execute new emit calls | Medium | Medium | Same residual risk as existing emit calls. Step 6 verification already checks minimum event count. With more events emitted, the minimum threshold becomes more meaningful. |
| Parallel Step 4 tasks complete out of order, affecting emit call execution | Low | Low | Verdict events are emitted after all parallel tasks complete, during the coordinator's result evaluation. The coordinator serializes at that point. |
| State file kept alive through Step 7 creates a longer window for race conditions | Low | Low | State file is per-run (contains RUN_ID in filename). Concurrent runs use different state files. |

## Test Plan

### Existing Tests (must still pass)

```bash
# Unit tests (53 tests)
cd ~/projects/claude-devkit && bash generators/test_skill_generator.sh

# Validate all skills (15 skills)
cd ~/projects/claude-devkit && ./scripts/validate-all.sh

# Existing integration tests (5 tests)
cd ~/projects/claude-devkit && bash scripts/test-integration.sh
```

### New Integration Tests

**Test 6 (G): emit-audit-event.sh produces valid JSONL across multiple calls**

Each test writes its python3 verification to a temp script file, avoiding triple-level escaping. Shell variables are expanded during the heredoc write (unquoted heredoc delimiter).

```bash
run_test 6 "emit-audit-event.sh multi-call JSONL correctness" \
    "TEST_RUN_ID=\"test-g-\$(date +%s)\" && \
     TEST_STATE=\"/tmp/integration-smoke-test/.ship-audit-state-\${TEST_RUN_ID}.json\" && \
     TEST_LOG=\"/tmp/integration-smoke-test/plans/audit-logs/ship-\${TEST_RUN_ID}.jsonl\" && \
     VERIFY_SCRIPT=\"/tmp/integration-smoke-test/verify-g-\${TEST_RUN_ID}.py\" && \
     mkdir -p /tmp/integration-smoke-test/plans/audit-logs && \
     printf '{\"run_id\":\"%s\",\"audit_log\":\"%s\",\"skill\":\"ship\",\"skill_version\":\"3.6.0\",\"security_maturity\":\"advisory\",\"hmac_key\":\"\"}' \"\$TEST_RUN_ID\" \"\$TEST_LOG\" > \"\$TEST_STATE\" && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"run_start\",\"plan_file\":\"./plans/test.md\"}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"step_start\",\"step\":\"step_0\",\"step_name\":\"Pre-flight\"}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"step_end\",\"step\":\"step_0\",\"step_name\":\"Pre-flight\"}' && \
     cat > \"\$VERIFY_SCRIPT\" <<PYEOF
import json
with open('\$TEST_LOG') as f:
    lines = f.readlines()
assert len(lines) == 3, f'Expected 3 events, got {len(lines)}'
for i, line in enumerate(lines):
    event = json.loads(line)
    assert event['sequence'] == i + 1, f'Expected sequence {i+1}, got {event[\"sequence\"]}'
    assert event['run_id'] == '\$TEST_RUN_ID'
    assert event['skill'] == 'ship'
    assert event['skill_version'] == '3.6.0'
types = [json.loads(l)['event_type'] for l in lines]
assert types == ['run_start', 'step_start', 'step_end'], f'Wrong event types: {types}'
print('PASS: Multi-call emission produces valid sequenced JSONL')
PYEOF
     python3 \"\$VERIFY_SCRIPT\" && \
     rm -f \"\$TEST_STATE\" \"\$TEST_LOG\" \"\$VERIFY_SCRIPT\"" \
    0
```

**Test 7 (H): L3 HMAC chain produces verifiable chain across calls**

```bash
run_test 7 "emit-audit-event.sh L3 HMAC chain verification" \
    "TEST_RUN_ID=\"test-h-\$(date +%s)\" && \
     TEST_HMAC_KEY=\"abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789\" && \
     TEST_STATE=\"/tmp/integration-smoke-test/.ship-audit-state-\${TEST_RUN_ID}.json\" && \
     TEST_LOG=\"/tmp/integration-smoke-test/plans/audit-logs/ship-\${TEST_RUN_ID}.jsonl\" && \
     VERIFY_SCRIPT=\"/tmp/integration-smoke-test/verify-h-\${TEST_RUN_ID}.py\" && \
     mkdir -p /tmp/integration-smoke-test/plans/audit-logs && \
     printf '{\"run_id\":\"%s\",\"audit_log\":\"%s\",\"skill\":\"ship\",\"skill_version\":\"3.6.0\",\"security_maturity\":\"audited\",\"hmac_key\":\"%s\"}' \"\$TEST_RUN_ID\" \"\$TEST_LOG\" \"\$TEST_HMAC_KEY\" > \"\$TEST_STATE\" && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"run_start\"}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"step_start\",\"step\":\"step_0\"}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"step_end\",\"step\":\"step_0\"}' && \
     cat > \"\$VERIFY_SCRIPT\" <<PYEOF
import json, hmac, hashlib
# NOTE: This test assumes json.dumps preserves insertion order (CPython 3.7+).
# If emit-audit-event.sh changes its JSON serialization order, this test will
# fail with an HMAC mismatch -- not a chain corruption bug.
key = '\$TEST_HMAC_KEY'
with open('\$TEST_LOG') as f:
    lines = f.readlines()
assert len(lines) == 3, f'Expected 3 events, got {len(lines)}'
prev_hmac = 'genesis'
for i, line in enumerate(lines):
    event = json.loads(line)
    assert 'hmac' in event, f'Event {i} missing hmac field'
    assert event['hmac'] != '', f'Event {i} has empty hmac'
    # Verify chain: strip hmac from event, recompute
    stored_hmac = event['hmac']
    event_copy = {k: v for k, v in event.items() if k != 'hmac'}
    event_json = json.dumps(event_copy, separators=(',', ':'))
    expected = hmac.new(key.encode(), (event_json + prev_hmac).encode(), hashlib.sha256).hexdigest()
    assert stored_hmac == expected, f'Event {i} HMAC mismatch: {stored_hmac} != {expected}'
    prev_hmac = stored_hmac
# Verify all HMACs are different (chain, not static)
hmacs = [json.loads(l)['hmac'] for l in lines]
assert len(set(hmacs)) == 3, f'HMACs are not unique: {hmacs}'
print('PASS: L3 HMAC chain is valid and verifiable')
PYEOF
     python3 \"\$VERIFY_SCRIPT\" && \
     rm -f \"\$TEST_STATE\" \"\$TEST_LOG\" \"\$VERIFY_SCRIPT\"" \
    0
```

**Test 8 (J): 10+ call state persistence**

```bash
run_test 8 "emit-audit-event.sh 10+ call state persistence" \
    "TEST_RUN_ID=\"test-j-\$(date +%s)\" && \
     TEST_STATE=\"/tmp/integration-smoke-test/.ship-audit-state-\${TEST_RUN_ID}.json\" && \
     TEST_LOG=\"/tmp/integration-smoke-test/plans/audit-logs/ship-\${TEST_RUN_ID}.jsonl\" && \
     VERIFY_SCRIPT=\"/tmp/integration-smoke-test/verify-j-\${TEST_RUN_ID}.py\" && \
     mkdir -p /tmp/integration-smoke-test/plans/audit-logs && \
     printf '{\"run_id\":\"%s\",\"audit_log\":\"%s\",\"skill\":\"ship\",\"skill_version\":\"3.6.0\",\"security_maturity\":\"advisory\",\"hmac_key\":\"\"}' \"\$TEST_RUN_ID\" \"\$TEST_LOG\" > \"\$TEST_STATE\" && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"run_start\"}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"step_start\",\"step\":\"step_0\"}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"security_decision\",\"gate\":\"secrets_scan\"}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"step_end\",\"step\":\"step_0\"}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"step_start\",\"step\":\"step_1\"}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"step_end\",\"step\":\"step_1\"}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"step_start\",\"step\":\"step_3c\"}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"step_end\",\"step\":\"step_3c\"}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"file_modification\",\"files_modified\":[\"src/a.ts\"]}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"verdict\",\"verdict\":\"PASS\",\"verdict_source\":\"code_review\"}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"security_decision\",\"gate\":\"dependency_audit\"}' && \
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"run_end\",\"outcome\":\"success\"}' && \
     cat > \"\$VERIFY_SCRIPT\" <<PYEOF
import json
with open('\$TEST_LOG') as f:
    lines = f.readlines()
assert len(lines) == 12, f'Expected 12 events, got {len(lines)}'
run_ids = set()
for i, line in enumerate(lines):
    event = json.loads(line)
    assert event['sequence'] == i + 1, f'Sequence mismatch at event {i}: expected {i+1}, got {event[\"sequence\"]}'
    run_ids.add(event['run_id'])
    assert event['skill'] == 'ship'
    assert event['skill_version'] == '3.6.0'
    assert event['security_maturity'] == 'advisory'
assert len(run_ids) == 1, f'Multiple run_ids found: {run_ids}'
assert '\$TEST_RUN_ID' in run_ids, f'Wrong run_id'
# Verify event types match expected sequence
expected_types = ['run_start','step_start','security_decision','step_end','step_start','step_end','step_start','step_end','file_modification','verdict','security_decision','run_end']
actual_types = [json.loads(l)['event_type'] for l in lines]
assert actual_types == expected_types, f'Event type mismatch: {actual_types}'
print('PASS: 12 events across 12 separate calls with consistent state')
PYEOF
     python3 \"\$VERIFY_SCRIPT\" && \
     rm -f \"\$TEST_STATE\" \"\$TEST_LOG\" \"\$VERIFY_SCRIPT\"" \
    0
```

### Exact Test Command

```bash
# Run all tests in sequence
cd ~/projects/claude-devkit && \
  bash generators/test_skill_generator.sh && \
  ./scripts/validate-all.sh && \
  bash scripts/test-integration.sh
```

## Acceptance Criteria

1. `emit-audit-event.sh` correctly appends the first event when the log file does not yet exist (no silent failure under `set -euo pipefail`)
2. Steps 4a/4b/4c/4d have retrospective per-substep `step_start`/`step_end` markers and `verdict`/`security_decision` events emitted during the coordinator's result evaluation phase (using identifiers `step_4a_code_review`, `step_4b_tests`, `step_4c_qa`, `step_4d_secure_review`)
3. Step 5 has `step_start` and `step_end` events bracketing the revision loop, with explicit conditional language ensuring they do not execute when Step 5 is skipped
4. Step 6 finalization block is wrapped under the PASS-path conditional so it does not execute on the FAIL path
5. Step 6 `step_end` is emitted before the state file is deleted (not after)
6. Step 6 FAIL path has a dedicated bash block that emits `step_end` and `run_end` before state file cleanup (state file is guaranteed to exist because finalization block was skipped)
7. Step 7 emit calls succeed (state file is not deleted until after Step 7 completes)
8. State file cleanup happens at the end of Step 7 (PASS path) or end of Step 6 (FAIL path)
9. Integration test G passes: 3 calls produce 3 sequenced, valid JSONL events
10. Integration test H passes: L3 HMAC chain is verifiable by replaying events with the key
11. Integration test J passes: 12 calls produce 12 sequenced events with consistent run_id
12. `run_test` function captures output and displays it on failure (not redirected to /dev/null)
13. Integration tests use temp-file python3 verification scripts (no triple-level escaping)
14. `generators/test_skill_generator.sh` passes (53 tests, 0 failures)
15. `scripts/validate-all.sh` passes (15 skills, 0 failures)
16. `scripts/test-integration.sh` passes (8 tests, 0 failures)

## Task Breakdown

### Files to Modify

| File | Change Summary |
|------|---------------|
| `scripts/emit-audit-event.sh` | Fix SEQUENCE line: replace `wc -l < "$AUDIT_LOG" 2>/dev/null` with conditional check that handles nonexistent log file on first invocation |
| `skills/ship/SKILL.md` | (1) Add retrospective per-substep step_start/step_end + verdict/security_decision emit calls for Step 4 during result evaluation. (2) Add conditional step_start/step_end emit calls for Step 5. (3) Wrap Step 6 finalization block under PASS-path conditional. (4) Insert Step 6 step_end before state file deletion. (5) Add FAIL-path bash block with step_end, run_end, and state file cleanup. (6) Move state file cleanup from Step 6 to Step 7 on PASS path. (7) Remove orphaned step_end block after Step 6. |
| `scripts/test-integration.sh` | (1) Modify `run_test` to capture output to temp file and display on failure instead of /dev/null. (2) Add 3 new integration tests (G/H/J) as Tests 6, 7, 8 using temp-file python3 verification scripts. (3) Update header comment and test count. |

### No Files to Create

All changes are modifications to existing files.

### Detailed Change List

#### 1. `scripts/emit-audit-event.sh` -- Fix wc -l bug

**Location:** Line 124

**Current:**
```bash
SEQUENCE=$(( $(wc -l < "$AUDIT_LOG" 2>/dev/null | tr -d ' ') + 1 ))
```

**Replace with:**
```bash
if [ -f "$AUDIT_LOG" ]; then
  SEQUENCE=$(( $(wc -l < "$AUDIT_LOG" | tr -d ' ') + 1 ))
else
  SEQUENCE=1
fi
```

#### 2. `skills/ship/SKILL.md` -- Add Step 4 emit calls

**Insert after the Result evaluation section** (after the L1/L2 result matrix and the stop/continue decision, before the "If stopping" output paragraph):

Retrospective per-substep markers: for each of 4a, 4b, 4c, 4d in sequence, emit `step_start`, then the `verdict` or `security_decision` event, then `step_end`. See Proposed Design section 2 for exact content.

#### 3. `skills/ship/SKILL.md` -- Add Step 5 emit calls

**Insert inside the Step 5 conditional section** (after the trigger paragraph "Trigger: Step 4 code review verdict is REVISION_NEEDED", before `### 5a -- Coder fixes`):

Step 5 step_start emit call with explicit conditional language: "MUST NOT execute if Step 5 is skipped."

**Insert at the end of the Step 5 section** (after the "Max 2 revision rounds" paragraph, before Step 6):

Step 5 step_end emit call with matching conditional language. See Proposed Design section 3 for exact content.

#### 4. `skills/ship/SKILL.md` -- Fix Step 6 step_end ordering and FAIL-path state file issue

**Restructure the finalization flow:**
- Wrap the existing finalization bash block under the `**If PASS or PASS_WITH_NOTES:**` conditional so it only executes on the PASS path
- Insert `step_end` emission inside the finalization block, before the `rm -f` line
- On the PASS path, remove the `rm -f` line (state file must survive for Step 7)
- Remove the orphaned `**Emit step_end for Step 6:**` block after the finalization section

**Add FAIL-path bash block:**
- Under `**If FAIL:**`, add a dedicated bash block that emits `step_end`, then `run_end`, then `rm -f` for the state file
- Add explicit instruction: "Do NOT run the finalization block above"
- The state file still exists at this point because the finalization block was skipped

See Proposed Design section 4 for exact content.

#### 5. `skills/ship/SKILL.md` -- Move state file cleanup to Step 7

**After the existing Step 7 step_end emission** (at the end of the Step 7 section):
- Add `rm -f ".ship-audit-state-${RUN_ID}.json"` as the final action of the entire /ship workflow

#### 6. `scripts/test-integration.sh` -- Modify run_test and add Tests G, H, J

**Modify `run_test` function:** Capture stdout/stderr to a temp file instead of `/dev/null`. On failure, display the first 20 lines of captured output to aid debugging. See Proposed Design section 6 for exact content.

**Update header comment:** Change test count from 5 to 8.

**Insert before Test 5 (Cleanup):** Add Tests 6, 7, 8 as `run_test` calls. Each test writes its python3 verification to a temp script file (heredoc with unquoted delimiter for shell variable expansion), then executes it. This eliminates triple-level escaping.

**Adjust Cleanup test number:** Renumber from Test 5 to Test 9.

## Context Alignment

### CLAUDE.md Patterns Followed

| Pattern | How This Plan Follows It |
|---------|-------------------------|
| **Numbered steps** | Emit calls follow existing step numbering. No new steps are added. |
| **Verdict gates** | Verdict events capture values at existing gates (code review, tests, QA). No new verdicts introduced. |
| **Timestamped artifacts** | No new artifact types. Existing JSONL format is unchanged. |
| **Bounded iterations** | Step 5 emit calls respect existing "max 2 revision rounds" constraint. |
| **Archive on success** | No changes to archival behavior. |

### Prior Plans Referenced

| Plan | Relationship |
|------|-------------|
| `plans/ship-run-audit-logging.md` | **Parent plan.** This plan completes the instrumentation that was shipped incomplete. References the instrumentation table (plan lines 493-510), test specifications (G/H/J), and event schema. |
| `plans/devkit-hygiene-improvements.md` | **Pattern.** Follows the test-first, validate-all pattern established in this plan. |
| `plans/agentic-sdlc-next-phase.md` | **Pattern.** Extends the integration test suite established in this plan. |

### Archived Plans Consulted

| Archive | Findings Used |
|---------|---------------|
| `plans/archive/ship-run-audit-logging/ship-run-audit-logging.qa-report.md` | QA Gap 1 (Steps 4/5 uninstrumented), Gap 3 (Tests G/H/J absent). Exact line references for missing emit calls. |
| `plans/archive/ship-run-audit-logging/ship-run-audit-logging.code-review.md` | Minor m1 (Step 6 step_end ordering bug). Exact description of the state file deletion race. |

### Deviations from Established Patterns

| Deviation | Justification |
|-----------|---------------|
| **No version bump** | This plan completes work committed under v3.6.0. The instrumentation was promised in the v3.6.0 plan but incompletely delivered. Bumping the version again would misrepresent the scope of changes (gap-fills, not new features). |
| **State file cleanup moved from Step 6 to Step 7** | The parent plan placed cleanup in Step 6 because Step 7 did not exist when the cleanup was designed. Now that Step 7 has emit calls, the state file must survive through Step 7. The FAIL path (Step 6 stops workflow, Step 7 skipped) still cleans up in Step 6. |
| **Step 4 per-substep markers are retrospective, not real-time** | The parent plan's instrumentation table (lines 504-507) specifies `step_start`/`step_end` for each of Steps 4a-4d. Since these substeps run as parallel Tasks, the coordinator cannot emit real-time start/end markers during parallel dispatch. This plan emits retrospective per-substep markers during the coordinator's sequential result evaluation phase. The markers use the parent plan's identifiers (`step_4a_code_review`, `step_4b_tests`, `step_4c_qa`, `step_4d_secure_review`) and preserve the per-substep schema contract for timeline reconstruction and future OTel span hierarchy. The timing values reflect result evaluation order, not parallel execution duration. |

---

<!-- Context Metadata
discovered_at: 2026-03-28T17:32:00Z
revised_at: 2026-03-28
claude_md_exists: true
recent_plans_consulted: ship-run-audit-logging.md, devkit-hygiene-improvements.md, agentic-sdlc-next-phase.md
archived_plans_consulted: ship-run-audit-logging (code-review, qa-report)
review_artifacts_addressed: ship-audit-logging-gaps.redteam.md (F1-F5), ship-audit-logging-gaps.review.md (required edits 1-2), ship-audit-logging-gaps.feasibility.md (M1 comment)
-->

## Status: APPROVED
