#!/usr/bin/env bash
#
# Integration smoke tests for claude-devkit
# Tests live end-to-end paths: generate -> validate -> deploy -> undeploy
#
# Usage:
#   bash scripts/test-integration.sh
#
# These are smoke tests that verify infrastructure paths work.
# They do NOT test LLM skill execution (which requires an active Claude session).
#
# 8 tests: coordinator lifecycle, validate-all, pipeline lifecycle, unit meta-test,
#          emit-audit-event JSONL correctness, L3 HMAC chain, 10+ call state persistence, cleanup

set -e

# Colors
RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
BLUE='\033[94m'
RESET='\033[0m'

# Counters
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"  # Repo root (parent of scripts/)
GENERATE_PY="$REPO_DIR/generators/generate_skill.py"
VALIDATE_PY="$REPO_DIR/generators/validate_skill.py"
DEPLOY_DIR="$HOME/.claude/skills"
TEST_DIR="/tmp/integration-smoke-test"

# Trap handler: clean up all smoke artifacts on exit/interruption
cleanup() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
    rm -rf "$DEPLOY_DIR/smoke-coord" 2>/dev/null || true
    rm -rf "$DEPLOY_DIR/smoke-pipe" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Clean up test directory at start
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Test runner function (same pattern as test_skill_generator.sh)
run_test() {
    local test_num="$1"
    local test_name="$2"
    local test_command="$3"
    local expected_exit="$4"

    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    echo ""
    echo -e "${BLUE}Test $test_num: $test_name${RESET}"

    local test_output_file
    test_output_file=$(mktemp)

    set +e
    eval "$test_command" > "$test_output_file" 2>&1
    local actual_exit=$?
    set -e

    if [[ "$expected_exit" == "0" && $actual_exit -eq 0 ]]; then
        echo -e "${GREEN}  PASS${RESET}"
        PASS_COUNT=$((PASS_COUNT + 1))
    elif [[ "$expected_exit" != "0" && $actual_exit -ne 0 ]]; then
        echo -e "${GREEN}  PASS${RESET}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}  FAIL (expected exit $expected_exit, got $actual_exit)${RESET}"
        echo "  Output:"
        head -20 "$test_output_file"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    rm -f "$test_output_file"
}

echo "========================================"
echo "Claude Devkit Integration Smoke Tests"
echo "========================================"

# Test 1: Generate a coordinator skill, deploy it, verify deployment
run_test 1 "Generate, deploy, and verify a coordinator skill" \
    "python3 '$GENERATE_PY' smoke-coord -d 'Smoke test coordinator.' -a coordinator -t '$TEST_DIR' --force && \
     mkdir -p '$DEPLOY_DIR/smoke-coord' && \
     cp '$TEST_DIR/skills/smoke-coord/SKILL.md' '$DEPLOY_DIR/smoke-coord/SKILL.md' && \
     [ -f '$DEPLOY_DIR/smoke-coord/SKILL.md' ] && \
     rm -rf '$DEPLOY_DIR/smoke-coord'" \
    0

# Test 2: Run validate-all.sh and verify exit code 0
run_test 2 "validate-all.sh passes for all skills" \
    "bash '$REPO_DIR/scripts/validate-all.sh'" \
    0

# Test 3: Full lifecycle -- generate pipeline skill, validate, deploy, undeploy
run_test 3 "Full lifecycle: generate, validate, deploy, undeploy a pipeline skill" \
    "python3 '$GENERATE_PY' smoke-pipe -d 'Smoke test pipeline.' -a pipeline -t '$TEST_DIR' --force && \
     python3 '$VALIDATE_PY' '$TEST_DIR/skills/smoke-pipe/SKILL.md' && \
     mkdir -p '$DEPLOY_DIR/smoke-pipe' && \
     cp '$TEST_DIR/skills/smoke-pipe/SKILL.md' '$DEPLOY_DIR/smoke-pipe/SKILL.md' && \
     [ -f '$DEPLOY_DIR/smoke-pipe/SKILL.md' ] && \
     rm -rf '$DEPLOY_DIR/smoke-pipe' && \
     [ ! -d '$DEPLOY_DIR/smoke-pipe' ]" \
    0

# Test 4: Meta-test -- run the unit test suite from within the integration test
run_test 4 "Unit test suite passes (meta-test)" \
    "bash '$REPO_DIR/generators/test_skill_generator.sh'" \
    0

# Test 6 (G): emit-audit-event.sh multi-call JSONL correctness
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

# Test 7 (H): L3 HMAC chain produces verifiable chain across calls
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

# Test 8 (J): 10+ call state persistence
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

# Test 9: Cleanup
echo ""
echo -e "${BLUE}Test 9: Cleanup${RESET}"
rm -rf "$TEST_DIR" || true
rm -rf "$DEPLOY_DIR/smoke-coord" || true
rm -rf "$DEPLOY_DIR/smoke-pipe" || true
if [[ ! -d "$TEST_DIR" ]]; then
    echo -e "${GREEN}  PASS${RESET}"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}  FAIL${RESET}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
TOTAL_COUNT=$((TOTAL_COUNT + 1))

# Summary
echo ""
echo "========================================"
echo "Integration Test Summary"
echo "========================================"
echo "Total:  $TOTAL_COUNT"
echo -e "${GREEN}Pass:   $PASS_COUNT${RESET}"
echo -e "${RED}Fail:   $FAIL_COUNT${RESET}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}All integration tests passed!${RESET}"
    exit 0
else
    echo -e "${RED}Some integration tests failed${RESET}"
    exit 1
fi
