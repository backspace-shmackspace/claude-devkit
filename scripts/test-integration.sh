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
# 80 tests: coordinator lifecycle, validate-all, pipeline lifecycle, unit meta-test,
#           emit-audit-event JSONL correctness, L3 HMAC chain, 10+ call state persistence,
#           threat model consumption structural tests (10 tests),
#           quantitative scoring tests (8 tests: 4 positive, 4 negative/edge cases),
#           fix skill structural tests (2 tests),
#           codebase-scanner integration tests (8 tests),
#           scanner value instrumentation tests (5 tests),
#           anti-pattern scan structural tests (6 tests),
#           meta-harness CLI tests (13 tests: help/version, init lifecycle,
#           validation rejections, status, deploy delegation, security guards),
#           detached execution tests (20 tests: run ID, flag parsing, watcher
#           lifecycle, jobs, result, logs, clean, security), cleanup

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
DEVKIT_CLI="$REPO_DIR/scripts/devkit_cli.py"
HARNESS_TEST_DIR="/tmp/devkit-harness-test"
HARNESS_NOTGIT_DIR="/tmp/devkit-harness-notgit"
HARNESS_NONEXISTENT_DIR="/tmp/devkit-harness-nonexistent"
HARNESS_SYMLINK="/tmp/devkit-harness-symlink"
HARNESS_REGISTRY_DIR="/tmp/devkit-harness-registry"
MOCK_CLAUDE="/tmp/devkit-mock-claude"
DETACH_RUNS_CLEANUP_PREFIX="test-detach-"

# Isolate all meta-harness registry writes from the real
# ~/.claude-devkit/registry.json -- devkit_cli.py's get_registry_path()
# honors this env var when set (test-only hook). Without it, every run of
# this suite would permanently register HARNESS_TEST_DIR (and friends) into
# the developer's real registry with no way to unregister (devkit
# prune/unregister is out of scope for the meta-harness MVP).
export DEVKIT_REGISTRY_OVERRIDE="$HARNESS_REGISTRY_DIR/test-registry.json"

# Trap handler: clean up all smoke artifacts on exit/interruption
cleanup() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
    rm -rf "$DEPLOY_DIR/smoke-coord" 2>/dev/null || true
    rm -rf "$DEPLOY_DIR/smoke-pipe" 2>/dev/null || true
    rm -f "$HARNESS_SYMLINK" 2>/dev/null || true
    rm -rf "$HARNESS_TEST_DIR" 2>/dev/null || true
    rm -rf "$HARNESS_NOTGIT_DIR" 2>/dev/null || true
    rm -rf "$HARNESS_NONEXISTENT_DIR" 2>/dev/null || true
    rm -rf "$HARNESS_REGISTRY_DIR" 2>/dev/null || true
    rm -f "$MOCK_CLAUDE" 2>/dev/null || true
    # Clean up detach test run directories
    if [ -d "$HOME/.claude-devkit/runs" ]; then
        for d in "$HOME/.claude-devkit/runs/${DETACH_RUNS_CLEANUP_PREFIX}"*; do
            rm -rf "$d" 2>/dev/null || true
        done
    fi
}
trap cleanup EXIT INT TERM

# Clean up test directory at start
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Clean up and set up meta-harness test fixtures at start
rm -f "$HARNESS_SYMLINK" 2>/dev/null || true
rm -rf "$HARNESS_TEST_DIR" 2>/dev/null || true
rm -rf "$HARNESS_NOTGIT_DIR" 2>/dev/null || true
rm -rf "$HARNESS_NONEXISTENT_DIR" 2>/dev/null || true
rm -rf "$HARNESS_REGISTRY_DIR" 2>/dev/null || true
mkdir -p "$HARNESS_TEST_DIR"
git -C "$HARNESS_TEST_DIR" init -q
mkdir -p "$HARNESS_NOTGIT_DIR"

# Create mock claude script for detached execution tests
cat > "$MOCK_CLAUDE" << 'MOCKEOF'
#!/bin/bash
echo '{"result":"mock output","usage":{"input_tokens":100,"output_tokens":50}}'
echo "mock progress" >&2
MOCKEOF
chmod +x "$MOCK_CLAUDE"

# Clean up any leftover detach test runs from prior crashes
if [ -d "$HOME/.claude-devkit/runs" ]; then
    for d in "$HOME/.claude-devkit/runs/${DETACH_RUNS_CLEANUP_PREFIX}"*; do
        rm -rf "$d" 2>/dev/null || true
    done
fi

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
     bash '$REPO_DIR/scripts/emit-audit-event.sh' \"\$TEST_STATE\" '{\"event_type\":\"run_start\",\"plan_file\":\".devkit/plans/test.md\"}' && \
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

# --- Threat model consumption structural tests ---

# Test 10: /ship SKILL.md contains the conditional THREAT MODEL CONTEXT prompt block
run_test 10 "ship SKILL.md contains THREAT MODEL CONTEXT prompt block" \
    "grep -q 'THREAT MODEL CONTEXT:' '$REPO_DIR/skills/ship/SKILL.md'" \
    0

# Test 11: /ship SKILL.md contains the security_requirements_present audit field
run_test 11 "ship SKILL.md contains security_requirements_present audit field" \
    "grep -q 'security_requirements_present' '$REPO_DIR/skills/ship/SKILL.md'" \
    0

# Test 12: /ship SKILL.md contains the threat model gap retro capture block
run_test 12 "ship SKILL.md contains threat model gap retro capture" \
    "grep -q 'Threat model gaps' '$REPO_DIR/skills/ship/SKILL.md'" \
    0

# Test 13: /architect SKILL.md contains Stage 2 plan content scan
run_test 13 "architect SKILL.md contains Stage 2 plan content scan" \
    "grep -q 'Stage 2' '$REPO_DIR/skills/architect/SKILL.md'" \
    0

# Test 14: /architect SKILL.md contains Required security-analyst language
run_test 14 "architect SKILL.md contains Required (when threat-model-gate) language" \
    "grep -q 'Required (when threat-model-gate' '$REPO_DIR/skills/architect/SKILL.md'" \
    0

# Test 15: /secure-review SKILL.md contains Threat Model Coverage section template
run_test 15 "secure-review SKILL.md contains Threat Model Coverage section template" \
    "grep -q '## Threat Model Coverage' '$REPO_DIR/skills/secure-review/SKILL.md'" \
    0

# Test 16: /ship version bumped to 3.8.0
run_test 16 "ship SKILL.md version is 3.8.0" \
    "grep -q 'version: 3.8.0' '$REPO_DIR/skills/ship/SKILL.md'" \
    0

# Test 17: /architect version bumped to 3.4.0
run_test 17 "architect SKILL.md version is 3.4.0" \
    "grep -q 'version: 3.4.0' '$REPO_DIR/skills/architect/SKILL.md'" \
    0

# Test 18: /secure-review version bumped to 1.2.0
run_test 18 "secure-review SKILL.md version is 1.2.0" \
    "grep -q 'version: 1.2.0' '$REPO_DIR/skills/secure-review/SKILL.md'" \
    0

# Test 19: /ship SKILL.md does NOT contain the removed SECURITY CONTEXT marker
run_test 19 "ship SKILL.md does not reference SECURITY CONTEXT marker" \
    "! grep -q 'SECURITY CONTEXT:' '$REPO_DIR/skills/ship/SKILL.md'" \
    0

# --- Quantitative scoring tests ---

# Test 20 (positive): compute-run-score.sh produces valid JSON for a synthetic log
run_test 20 "compute-run-score.sh produces valid JSON for a complete synthetic log" \
    "SCORE_LOG=\"/tmp/integration-smoke-test/score-test-complete.jsonl\" && \
     mkdir -p /tmp/integration-smoke-test && \
     printf '{\"event_type\":\"run_start\",\"timestamp\":\"2026-05-09T10:00:00.000Z\",\"run_id\":\"test-score-1\"}\n' > \"\$SCORE_LOG\" && \
     printf '{\"event_type\":\"verdict\",\"verdict\":\"PASS\",\"verdict_source\":\"code_review\"}\n' >> \"\$SCORE_LOG\" && \
     printf '{\"event_type\":\"security_decision\",\"gate\":\"secrets_scan\",\"gate_verdict\":\"PASS\",\"action\":\"pass\",\"effective_verdict\":\"PASS\"}\n' >> \"\$SCORE_LOG\" && \
     printf '{\"event_type\":\"verdict\",\"verdict\":\"PASS\",\"verdict_source\":\"qa\"}\n' >> \"\$SCORE_LOG\" && \
     OUTPUT=\$(bash '$REPO_DIR/scripts/compute-run-score.sh' \"\$SCORE_LOG\") && \
     python3 -c \"
import json, sys
data = json.loads(sys.argv[1])
assert data['event_type'] == 'run_score', 'wrong event_type'
assert 'dimensions' in data, 'missing dimensions'
assert 'composite' in data, 'missing composite'
dims = {d['name']: d['score'] for d in data['dimensions']}
assert dims.get('efficiency') == 1.0, f'expected efficiency 1.0, got {dims.get(\\\"efficiency\\\")}'
assert dims.get('security') == 1.0, f'expected security 1.0, got {dims.get(\\\"security\\\")}'
assert dims.get('quality') == 1.0, f'expected quality 1.0, got {dims.get(\\\"quality\\\")}'
print('PASS: valid JSON with correct scores')
\" \"\$OUTPUT\" && \
     rm -f \"\$SCORE_LOG\"" \
    0

# Test 21 (positive): compute-run-score.sh handles empty log gracefully (neutral scores)
run_test 21 "compute-run-score.sh handles empty log with neutral scores" \
    "SCORE_LOG=\"/tmp/integration-smoke-test/score-test-empty.jsonl\" && \
     mkdir -p /tmp/integration-smoke-test && \
     printf '' > \"\$SCORE_LOG\" && \
     OUTPUT=\$(bash '$REPO_DIR/scripts/compute-run-score.sh' \"\$SCORE_LOG\") && \
     python3 -c \"
import json, sys
data = json.loads(sys.argv[1])
assert data['event_type'] == 'run_score', 'wrong event_type'
assert data['composite'] == 0.5, f'expected composite 0.5, got {data[\\\"composite\\\"]}'
dims = {d['name']: d['score'] for d in data['dimensions']}
for name, score in dims.items():
    assert score == 0.5, f'expected neutral 0.5 for {name}, got {score}'
print('PASS: empty log returns neutral scores')
\" \"\$OUTPUT\" && \
     rm -f \"\$SCORE_LOG\"" \
    0

# Test 22 (positive): audit-log-query.sh scores command handles run_score events
run_test 22 "audit-log-query.sh scores command parses run_score events" \
    "SCORE_RUN_ID=\"test-scores-\$(date +%s)\" && \
     SCORE_LOG=\"/tmp/integration-smoke-test/plans/audit-logs/ship-\${SCORE_RUN_ID}.jsonl\" && \
     mkdir -p /tmp/integration-smoke-test/plans/audit-logs && \
     printf '{\"event_type\":\"run_start\",\"run_id\":\"%s\",\"timestamp\":\"2026-05-09T10:00:00.000Z\",\"skill\":\"ship\",\"skill_version\":\"3.8.0\",\"security_maturity\":\"advisory\",\"sequence\":1}\n' \"\$SCORE_RUN_ID\" > \"\$SCORE_LOG\" && \
     printf '{\"event_type\":\"run_score\",\"run_id\":\"%s\",\"timestamp\":\"2026-05-09T10:05:00.000Z\",\"skill\":\"ship\",\"skill_version\":\"3.8.0\",\"security_maturity\":\"advisory\",\"sequence\":2,\"dimensions\":[{\"name\":\"efficiency\",\"score\":1.0,\"weight\":0.3333,\"details\":\"0 revision round(s)\"},{\"name\":\"security\",\"score\":0.5,\"weight\":0.3333,\"details\":\"neutral\"},{\"name\":\"quality\",\"score\":0.7,\"weight\":0.3333,\"details\":\"code_review:PASS\"}],\"composite\":0.7333}\n' \"\$SCORE_RUN_ID\" >> \"\$SCORE_LOG\" && \
     AUDIT_LOG_DIR=/tmp/integration-smoke-test/plans/audit-logs '$REPO_DIR/scripts/audit-log-query.sh' scores \"\$SCORE_RUN_ID\" 2>/dev/null | grep -q 'efficiency' && \
     AUDIT_LOG_DIR=/tmp/integration-smoke-test/plans/audit-logs '$REPO_DIR/scripts/audit-log-query.sh' scores \"\$SCORE_RUN_ID\" 2>/dev/null | grep -q 'Composite score' && \
     rm -f \"\$SCORE_LOG\"" \
    0

# Test 23 (positive): audit-log-query.sh trend command aggregates across multiple logs
run_test 23 "audit-log-query.sh trend command aggregates run_score events across logs" \
    "TREND_DIR=\"/tmp/integration-smoke-test/plans/audit-logs\" && \
     mkdir -p \"\$TREND_DIR\" && \
     for i in 1 2 3; do \
       RUN_ID=\"trend-test-\${i}-\$(date +%s)\${i}\" && \
       LOG=\"\${TREND_DIR}/ship-\${RUN_ID}.jsonl\" && \
       printf '{\"event_type\":\"run_score\",\"run_id\":\"%s\",\"timestamp\":\"2026-05-09T10:0%s:00.000Z\",\"skill\":\"ship\",\"skill_version\":\"3.8.0\",\"security_maturity\":\"advisory\",\"sequence\":1,\"dimensions\":[{\"name\":\"efficiency\",\"score\":0.8,\"weight\":0.3333,\"details\":\"test\"},{\"name\":\"security\",\"score\":0.9,\"weight\":0.3333,\"details\":\"test\"},{\"name\":\"quality\",\"score\":0.7,\"weight\":0.3333,\"details\":\"test\"}],\"composite\":0.8}\n' \"\$RUN_ID\" \"\$i\" > \"\$LOG\"; \
     done && \
     AUDIT_LOG_DIR=\"\$TREND_DIR\" '$REPO_DIR/scripts/audit-log-query.sh' trend 10 2>/dev/null | grep -q 'Composite\|composite\|efficiency\|No score' && \
     rm -f \"\$TREND_DIR\"/ship-trend-test-*.jsonl" \
    0

# Test 24 (negative): compute-run-score.sh with nonexistent file exits 0 with neutral scores
run_test 24 "compute-run-score.sh with nonexistent file exits 0 with neutral scores" \
    "OUTPUT=\$(bash '$REPO_DIR/scripts/compute-run-score.sh' '/tmp/does-not-exist-score.jsonl' 2>/dev/null) && \
     python3 -c \"
import json, sys
data = json.loads(sys.argv[1])
assert data['event_type'] == 'run_score', 'wrong event_type'
assert data['composite'] == 0.5, f'expected neutral composite 0.5, got {data[\\\"composite\\\"]}'
print('PASS: nonexistent file returns neutral scores with exit 0')
\" \"\$OUTPUT\"" \
    0

# Test 25 (negative): compute-run-score.sh with incomplete log (no run_end) computes from available events
run_test 25 "compute-run-score.sh with incomplete log (no run_end) still computes scores" \
    "SCORE_LOG=\"/tmp/integration-smoke-test/score-test-incomplete.jsonl\" && \
     mkdir -p /tmp/integration-smoke-test && \
     printf '{\"event_type\":\"run_start\",\"timestamp\":\"2026-05-09T10:00:00.000Z\",\"run_id\":\"test-incomplete\"}\n' > \"\$SCORE_LOG\" && \
     printf '{\"event_type\":\"verdict\",\"verdict\":\"REVISION_NEEDED\",\"verdict_source\":\"code_review\"}\n' >> \"\$SCORE_LOG\" && \
     printf '{\"event_type\":\"verdict\",\"verdict\":\"PASS\",\"verdict_source\":\"code_review\"}\n' >> \"\$SCORE_LOG\" && \
     OUTPUT=\$(bash '$REPO_DIR/scripts/compute-run-score.sh' \"\$SCORE_LOG\") && \
     python3 -c \"
import json, sys
data = json.loads(sys.argv[1])
assert data['event_type'] == 'run_score', 'wrong event_type'
dims = {d['name']: d['score'] for d in data['dimensions']}
# 2 code_review verdicts = 1 revision round = efficiency 0.6
assert dims.get('efficiency') == 0.6, f'expected efficiency 0.6, got {dims.get(\\\"efficiency\\\")}'
# First CR was REVISION_NEEDED -> quality penalty -0.3 -> 0.7
assert dims.get('quality') == 0.7, f'expected quality 0.7, got {dims.get(\\\"quality\\\")}'
print('PASS: incomplete log scored from available events')
\" \"\$OUTPUT\" && \
     rm -f \"\$SCORE_LOG\"" \
    0

# Test 26 (negative): compute-run-score.sh with malformed JSONL lines skips bad lines
run_test 26 "compute-run-score.sh with malformed JSONL skips bad lines and computes from valid ones" \
    "SCORE_LOG=\"/tmp/integration-smoke-test/score-test-malformed.jsonl\" && \
     mkdir -p /tmp/integration-smoke-test && \
     printf '{\"event_type\":\"run_start\",\"timestamp\":\"2026-05-09T10:00:00.000Z\"}\n' > \"\$SCORE_LOG\" && \
     printf 'NOT VALID JSON {{{{ broken\n' >> \"\$SCORE_LOG\" && \
     printf '{\"event_type\":\"security_decision\",\"gate\":\"secrets_scan\",\"gate_verdict\":\"BLOCKED\",\"action\":\"block\",\"effective_verdict\":\"BLOCKED\"}\n' >> \"\$SCORE_LOG\" && \
     printf 'also broken json\n' >> \"\$SCORE_LOG\" && \
     OUTPUT=\$(bash '$REPO_DIR/scripts/compute-run-score.sh' \"\$SCORE_LOG\" 2>/dev/null) && \
     python3 -c \"
import json, sys
data = json.loads(sys.argv[1])
assert data['event_type'] == 'run_score', 'wrong event_type'
dims = {d['name']: d['score'] for d in data['dimensions']}
# BLOCKED security gate -> 1.0 - 0.3 = 0.7
assert dims.get('security') == 0.7, f'expected security 0.7, got {dims.get(\\\"security\\\")}'
print('PASS: malformed lines skipped, valid events scored correctly')
\" \"\$OUTPUT\" && \
     rm -f \"\$SCORE_LOG\"" \
    0

# Test 27 (negative): audit-log-query.sh trend with 0 scored runs shows "No score data found"
run_test 27 "audit-log-query.sh trend with 0 scored runs shows no score data message" \
    "EMPTY_DIR=\"/tmp/integration-smoke-test/empty-audit-logs-\$(date +%s)\" && \
     mkdir -p \"\$EMPTY_DIR\" && \
     AUDIT_LOG_DIR=\"\$EMPTY_DIR\" '$REPO_DIR/scripts/audit-log-query.sh' trend 2>/dev/null | grep -q 'No score data' && \
     rm -rf \"\$EMPTY_DIR\"" \
    0

# Test 28: fix SKILL.md version is 1.0.0
run_test 28 "fix SKILL.md version is 1.0.0" \
    "grep -q 'version: 1.0.0' '$REPO_DIR/skills/fix/SKILL.md'" \
    0

# Test 29: fix SKILL.md contains Pipeline archetype steps
run_test 29 "fix SKILL.md contains Pipeline archetype steps" \
    "grep -q 'Step 0' '$REPO_DIR/skills/fix/SKILL.md' && grep -q 'Step 4' '$REPO_DIR/skills/fix/SKILL.md'" \
    0

# Tests 30-37: codebase-scanner integration tests
run_test 30 "Scanner runs on project root without errors" \
    "python3 '$REPO_DIR/scripts/codebase-scanner.py' --format summary --quiet '$REPO_DIR'" \
    0

run_test 31 "Scanner JSON output is valid JSON" \
    "python3 '$REPO_DIR/scripts/codebase-scanner.py' --format json --quiet '$REPO_DIR' | python3 -m json.tool > /dev/null" \
    0

run_test 32 "Scanner handles empty directory" \
    "mkdir -p /tmp/scanner-test-empty && python3 '$REPO_DIR/scripts/codebase-scanner.py' --format summary --quiet /tmp/scanner-test-empty; STATUS=\$?; rm -rf /tmp/scanner-test-empty 2>/dev/null || true; [ \"\$STATUS\" -eq 0 ]" \
    0

run_test 33 "Scanner respects --max-files limit" \
    "python3 '$REPO_DIR/scripts/codebase-scanner.py' --format json --max-files 3 --no-cache --quiet '$REPO_DIR' | python3 -c 'import json,sys; d=json.load(sys.stdin); fc=d[\"file_count\"]; assert fc<=3, f\"Expected <=3 files, got {fc}\"; print(\"PASS\")'" \
    0

run_test 34 "Scanner summary contains expected structure header" \
    "python3 '$REPO_DIR/scripts/codebase-scanner.py' --format summary --quiet '$REPO_DIR' | grep -q '## Codebase Structure'" \
    0

run_test 35 "Scanner rejects symlink escape" \
    "mkdir -p /tmp/scanner-symlink-test && ln -sf /etc/passwd /tmp/scanner-symlink-test/escape.py && python3 '$REPO_DIR/scripts/codebase-scanner.py' --format json --quiet /tmp/scanner-symlink-test | python3 -c 'import json,sys; d=json.load(sys.stdin); fc=d[\"file_count\"]; assert fc==0, f\"Expected 0 files, got {fc}\"; print(\"PASS\")'; STATUS=\$?; rm -rf /tmp/scanner-symlink-test 2>/dev/null || true; [ \"\$STATUS\" -eq 0 ]" \
    0

run_test 36 "Scanner --self-test passes" \
    "python3 '$REPO_DIR/scripts/codebase-scanner.py' --self-test" \
    0

run_test 37 "Scanner --max-tokens truncates output to reasonable size" \
    "OUTPUT=\$(python3 '$REPO_DIR/scripts/codebase-scanner.py' --format summary --max-tokens 200 --quiet '$REPO_DIR') && CHARS=\$(printf '%s' \"\$OUTPUT\" | wc -c) && test \"\$CHARS\" -lt 2000" \
    0

# --- Scanner value instrumentation tests ---

# Test 38: compute-run-score.sh extracts scanner_mode from scanner_invocation event
run_test 38 "compute-run-score.sh extracts scanner_mode from scanner_invocation event" \
    "SCORE_LOG=\"/tmp/integration-smoke-test/score-test-scanner-mode.jsonl\" && \
     mkdir -p /tmp/integration-smoke-test && \
     printf '{\"event_type\":\"run_start\",\"timestamp\":\"2026-05-25T10:00:00.000Z\",\"run_id\":\"test-scanner-mode-1\"}\n' > \"\$SCORE_LOG\" && \
     printf '{\"event_type\":\"scanner_invocation\",\"parser_mode\":\"tree-sitter-partial\",\"output_token_count\":1500,\"scanner_version\":\"1.0.0\",\"file_count\":6,\"symbol_count\":112,\"output_sha256\":\"abc123\"}\n' >> \"\$SCORE_LOG\" && \
     printf '{\"event_type\":\"verdict\",\"verdict\":\"PASS\",\"verdict_source\":\"code_review\"}\n' >> \"\$SCORE_LOG\" && \
     OUTPUT=\$(bash '$REPO_DIR/scripts/compute-run-score.sh' \"\$SCORE_LOG\") && \
     python3 -c \"
import json, sys
data = json.loads(sys.argv[1])
assert data.get('scanner_mode') == 'tree-sitter-partial', f'expected scanner_mode tree-sitter-partial, got {data.get(\\\"scanner_mode\\\")}'
assert data.get('scanner_tokens') == 1500, f'expected scanner_tokens 1500, got {data.get(\\\"scanner_tokens\\\")}'
print('PASS: scanner_mode and scanner_tokens extracted from scanner_invocation')
\" \"\$OUTPUT\" && \
     rm -f \"\$SCORE_LOG\"" \
    0

# Test 39: compute-run-score.sh defaults scanner_mode to "absent" when no scanner_invocation
run_test 39 "compute-run-score.sh defaults scanner_mode to absent when no scanner_invocation" \
    "SCORE_LOG=\"/tmp/integration-smoke-test/score-test-scanner-absent.jsonl\" && \
     mkdir -p /tmp/integration-smoke-test && \
     printf '{\"event_type\":\"run_start\",\"timestamp\":\"2026-05-25T10:00:00.000Z\",\"run_id\":\"test-scanner-absent-1\"}\n' > \"\$SCORE_LOG\" && \
     printf '{\"event_type\":\"verdict\",\"verdict\":\"PASS\",\"verdict_source\":\"code_review\"}\n' >> \"\$SCORE_LOG\" && \
     OUTPUT=\$(bash '$REPO_DIR/scripts/compute-run-score.sh' \"\$SCORE_LOG\") && \
     python3 -c \"
import json, sys
data = json.loads(sys.argv[1])
assert data.get('scanner_mode') == 'absent', f'expected scanner_mode absent, got {data.get(\\\"scanner_mode\\\")}'
assert data.get('scanner_tokens') == 0, f'expected scanner_tokens 0, got {data.get(\\\"scanner_tokens\\\")}'
print('PASS: scanner_mode defaults to absent and scanner_tokens to 0 when no scanner_invocation')
\" \"\$OUTPUT\" && \
     rm -f \"\$SCORE_LOG\"" \
    0

# Test 40: scanner-value-report.sh runs without errors on empty audit-logs directory
run_test 40 "scanner-value-report.sh exits 0 on empty audit-logs directory" \
    "EMPTY_LOGS=\"/tmp/integration-smoke-test/empty-scanner-logs-\$(date +%s)\" && \
     mkdir -p \"\$EMPTY_LOGS\" && \
     OUTPUT=\$(bash '$REPO_DIR/scripts/scanner-value-report.sh' --audit-log-dir \"\$EMPTY_LOGS\" 2>/dev/null) && \
     echo \"\$OUTPUT\" | grep -iq 'No ship' && \
     rm -rf \"\$EMPTY_LOGS\"" \
    0

# Test 41: scanner-value-report.sh produces markdown output for synthetic scored runs
run_test 41 "scanner-value-report.sh produces cohort table for synthetic run_score events" \
    "SYNTH_LOGS=\"/tmp/integration-smoke-test/synth-scanner-logs-\$(date +%s)\" && \
     mkdir -p \"\$SYNTH_LOGS\" && \
     for i in 1 2 3; do \
       RUN_ID=\"synth-ts-\${i}-\$(date +%s)\${i}\" && \
       LOG=\"\${SYNTH_LOGS}/ship-\${RUN_ID}.jsonl\" && \
       printf '{\"event_type\":\"run_score\",\"run_id\":\"%s\",\"timestamp\":\"2026-05-25T10:0%s:00.000Z\",\"skill\":\"ship\",\"skill_version\":\"3.8.0\",\"security_maturity\":\"advisory\",\"sequence\":1,\"dimensions\":[{\"name\":\"efficiency\",\"score\":0.9,\"weight\":0.3333,\"details\":\"test\"},{\"name\":\"security\",\"score\":0.9,\"weight\":0.3333,\"details\":\"test\"},{\"name\":\"quality\",\"score\":0.9,\"weight\":0.3333,\"details\":\"test\"}],\"composite\":0.9,\"scanner_mode\":\"tree-sitter-partial\",\"scanner_tokens\":1500}\n' \"\$RUN_ID\" \"\$i\" > \"\$LOG\"; \
     done && \
     for i in 1 2 3; do \
       RUN_ID=\"synth-rf-\${i}-\$(date +%s)\${i}\" && \
       LOG=\"\${SYNTH_LOGS}/ship-\${RUN_ID}.jsonl\" && \
       printf '{\"event_type\":\"run_score\",\"run_id\":\"%s\",\"timestamp\":\"2026-05-25T10:0%s:00.000Z\",\"skill\":\"ship\",\"skill_version\":\"3.8.0\",\"security_maturity\":\"advisory\",\"sequence\":1,\"dimensions\":[{\"name\":\"efficiency\",\"score\":0.7,\"weight\":0.3333,\"details\":\"test\"},{\"name\":\"security\",\"score\":0.7,\"weight\":0.3333,\"details\":\"test\"},{\"name\":\"quality\",\"score\":0.7,\"weight\":0.3333,\"details\":\"test\"}],\"composite\":0.7,\"scanner_mode\":\"regex-fallback\",\"scanner_tokens\":1000}\n' \"\$RUN_ID\" \"\$i\" > \"\$LOG\"; \
     done && \
     OUTPUT=\$(bash '$REPO_DIR/scripts/scanner-value-report.sh' --audit-log-dir \"\$SYNTH_LOGS\" 2>/dev/null) && \
     echo \"\$OUTPUT\" | grep -q 'Cohort' && \
     rm -rf \"\$SYNTH_LOGS\"" \
    0

# Test 42: scanner_invocation is registered in audit-event-schema.json
run_test 42 "scanner_invocation is in audit-event-schema.json event_type enum" \
    "grep -q '\"scanner_invocation\"' '$REPO_DIR/configs/audit-event-schema.json'" \
    0

# --- Anti-pattern scan structural tests (56-61) ---

# Test 56: audit SKILL.md version is 3.3.0
run_test 56 "audit SKILL.md version is 3.3.0" \
    "grep -q 'version: 3.3.0' '$REPO_DIR/skills/audit/SKILL.md'" \
    0

# Test 57: audit SKILL.md contains anti-pattern scan step identifier
run_test 57 "audit SKILL.md contains step_4_antipattern_scan identifier" \
    "grep -q 'step_4_antipattern_scan' '$REPO_DIR/skills/audit/SKILL.md'" \
    0

# Test 58: audit SKILL.md contains antipatterns.md artifact reference
run_test 58 "audit SKILL.md contains antipatterns.md artifact reference" \
    "grep -q 'antipatterns.md' '$REPO_DIR/skills/audit/SKILL.md'" \
    0

# Test 59: audit SKILL.md contains renumbered QA regression step
run_test 59 "audit SKILL.md contains step_5_qa_regression identifier" \
    "grep -q 'step_5_qa_regression' '$REPO_DIR/skills/audit/SKILL.md'" \
    0

# Test 60: audit SKILL.md contains renumbered synthesis step
run_test 60 "audit SKILL.md contains step_6_synthesis identifier" \
    "grep -q 'step_6_synthesis' '$REPO_DIR/skills/audit/SKILL.md'" \
    0

# Test 61: audit SKILL.md contains renumbered gate step
run_test 61 "audit SKILL.md contains step_7_gate identifier" \
    "grep -q 'step_7_gate' '$REPO_DIR/skills/audit/SKILL.md'" \
    0

# --- Meta-harness CLI tests (43-55) ---
# Fixtures created at script startup: HARNESS_TEST_DIR (initialized git repo),
# HARNESS_NOTGIT_DIR (plain directory, no .git), HARNESS_NONEXISTENT_DIR (never
# created), HARNESS_SYMLINK (created inline in Test 51).

# Test 43: devkit --help exits 0
run_test 43 "devkit --help exits 0" \
    "python3 '$DEVKIT_CLI' --help" \
    0

# Test 44: devkit --version exits 0 and matches semver format
run_test 44 "devkit --version exits 0 and matches semver format" \
    "python3 '$DEVKIT_CLI' --version | grep -qE '[0-9]+\.[0-9]+\.[0-9]+'" \
    0

# Test 45: devkit init on a valid git repo creates state.json with required fields
run_test 45 "devkit init on valid git repo creates state.json with required fields" \
    "python3 '$DEVKIT_CLI' init '$HARNESS_TEST_DIR' && \
     python3 -c \"
import json
with open('$HARNESS_TEST_DIR/.devkit/state.json') as f:
    data = json.load(f)
assert data.get('schema_version') == '1.0.0', 'missing/invalid schema_version'
assert data.get('project_name') == 'devkit-harness-test', 'missing/invalid project_name'
assert isinstance(data.get('initialized_at'), str) and data['initialized_at'], 'missing initialized_at'
assert isinstance(data.get('devkit_version'), str) and data['devkit_version'], 'missing devkit_version'
print('PASS: state.json schema valid')
\"" \
    0

# Test 46: devkit init adds .devkit/ to the target's .gitignore
run_test 46 "devkit init adds .devkit/ to target .gitignore" \
    "grep -qF '.devkit/' '$HARNESS_TEST_DIR/.gitignore'" \
    0

# Test 47: devkit init on a non-git directory exits 1
run_test 47 "devkit init on non-git directory exits 1" \
    "python3 '$DEVKIT_CLI' init '$HARNESS_NOTGIT_DIR'" \
    1

# Test 48: devkit init on a nonexistent path exits 1
run_test 48 "devkit init on nonexistent path exits 1" \
    "python3 '$DEVKIT_CLI' init '$HARNESS_NONEXISTENT_DIR'" \
    1

# Test 49: devkit status (fleet view) shows the project registered by init
run_test 49 "devkit status shows project registered by init" \
    "python3 '$DEVKIT_CLI' status | grep -q 'devkit-harness-test'" \
    0

# Test 50: devkit deploy delegates to deploy.sh (exit code matches deploy.sh --help)
run_test 50 "devkit deploy --help delegates to deploy.sh" \
    "python3 '$DEVKIT_CLI' deploy --help" \
    0

# Test 51: devkit init on a symlink to a git repo exits 1 (symlink rejection, TB-2)
run_test 51 "devkit init on symlink-to-git-repo exits 1" \
    "ln -sf '$HARNESS_TEST_DIR' '$HARNESS_SYMLINK' && \
     python3 '$DEVKIT_CLI' init '$HARNESS_SYMLINK'" \
    1

# Test 52: devkit init on a path outside allowed_roots exits 1 (STRIDE Elevation)
run_test 52 "devkit init on path outside allowed_roots exits 1" \
    "python3 '$DEVKIT_CLI' init /etc" \
    1

# Test 53: oversized state.json produces a warning but devkit status still exits 0 (STRIDE DoS)
run_test 53 "oversized state.json warns on stderr; devkit status still exits 0" \
    "python3 -c \"print('x' * 100000)\" > '$HARNESS_TEST_DIR/.devkit/state.json' && \
     OUTPUT=\$(python3 '$DEVKIT_CLI' status '$HARNESS_TEST_DIR' 2>&1); STATUS_EXIT=\$?; \
     echo \"\$OUTPUT\" | grep -qi warning && [ \"\$STATUS_EXIT\" -eq 0 ]" \
    0

# Test 54: invalid skill name (path traversal attempt) is rejected (TB-1)
run_test 54 "invalid skill name (path traversal) is rejected" \
    "python3 '$DEVKIT_CLI' ../../etc/passwd '$HARNESS_TEST_DIR'" \
    1

# Test 55: skill argument starting with -- is rejected before the "--"
# separator (CLI flag injection guard, STRIDE Tampering), but the same
# argument is forwarded verbatim -- not rejected -- after an explicit "--"
# separator (mvp-meta-harness code review M-1: the pre-separator restriction
# is real defense-in-depth, but re-applying it post-separator broke every
# documented skill flag, e.g. `/architect --fast`, with no security benefit
# since subprocess.run() is always list-form with the prompt as one argv
# element). Does not invoke a real `claude` process (see file header note on
# not testing LLM execution) -- imports devkit_cli directly to check the
# split/validate logic that main() uses for dispatch.
run_test 55 "pre-separator -- argument rejected; post-separator -- argument forwarded verbatim" \
    "python3 '$DEVKIT_CLI' audit '$HARNESS_TEST_DIR' --system-prompt foo; PRE_EXIT=\$?; \
     [ \"\$PRE_EXIT\" -eq 1 ] && \
     python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

# No literal '--' token -> the entire arg list is pre-separator and
# validate_args() rejects it (matches the end-to-end exit-1 check above).
pre, post = d.split_skill_args(['audit', '$HARNESS_TEST_DIR', '--system-prompt', 'foo'])
assert pre == ['audit', '$HARNESS_TEST_DIR', '--system-prompt', 'foo'], f'unexpected split without --: {pre}'
assert post == [], f'expected no post-separator args without --, got: {post}'
ok, err = d.validate_args(pre)
assert not ok, 'pre-separator -- argument should be rejected by validate_args'

# Explicit '--' separator -> args after it are excluded from validate_args
# entirely (that omission in main()/cmd_run_skill is what makes the escape
# hatch work -- validate_args() itself is unchanged).
pre2, post2 = d.split_skill_args(['audit', '$HARNESS_TEST_DIR', '--', '--system-prompt', 'foo'])
assert pre2 == ['audit', '$HARNESS_TEST_DIR'], f'unexpected pre-separator split: {pre2}'
assert post2 == ['--system-prompt', 'foo'], f'unexpected post-separator split: {post2}'
ok2, err2 = d.validate_args(pre2)
assert ok2, f'pre-separator args (no -- prefix) should pass validate_args, got: {err2}'

# Sanity check: validate_args() itself still rejects '--'-prefixed args when
# called directly -- proving the escape hatch comes from dispatch not
# calling it on post-separator args, not from a behavior change in the
# validator.
ok3, err3 = d.validate_args(post2)
assert not ok3, 'sanity check failed: validate_args should still reject -- prefixed args'

print('PASS: split_skill_args/validate_args separator semantics verified')
\"" \
    0

# --- Detached execution tests (62-81) ---
# These tests verify the --detach flag, watcher lifecycle, jobs/result/logs
# commands, cleanup, and security properties of detached execution.

# Test 62: _generate_run_id produces valid YYYYMMDD-HHMMSS-6hex format
run_test 62 "_generate_run_id produces valid run ID format" \
    "python3 -c \"
import sys, re
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
run_id = d._generate_run_id()
assert re.match(r'^[0-9]{8}-[0-9]{6}-[0-9a-f]{6}\$', run_id), f'Invalid format: {run_id}'
# Generate a second to verify uniqueness
run_id2 = d._generate_run_id()
assert run_id != run_id2, 'Two run IDs should not be identical'
print(f'PASS: run_id format valid: {run_id}')
\"" \
    0

# Test 63: _validate_run_id rejects path traversal and accepts valid IDs
run_test 63 "_validate_run_id rejects path traversal" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
ok, _ = d._validate_run_id('../../../etc/passwd')
assert not ok, 'path traversal should be rejected'
ok2, _ = d._validate_run_id('foo/bar')
assert not ok2, 'slash in run ID should be rejected'
ok3, _ = d._validate_run_id('20260821-143052-a1b2c3')
assert ok3, 'valid run ID should pass'
print('PASS: traversal rejected, valid IDs accepted')
\"" \
    0

# Test 64: --detach is extracted from skill_args before validate_args runs
run_test 64 "--detach extracted before validate_args" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
skill_args = ['feature', '--detach']
detach = '--detach' in skill_args
assert detach, '--detach should be detected'
skill_args = [a for a in skill_args if a != '--detach']
assert '--detach' not in skill_args, '--detach should be removed'
pre, post = d.split_skill_args(skill_args)
ok, _ = d.validate_args(pre)
assert ok, 'pre-sep args should pass after --detach removal'
print('PASS: --detach extracted before validation')
\"" \
    0

# Test 65: --detach works with -- separator in various positions
run_test 65 "--detach with -- separator" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
# devkit architect ~/foo --detach -- --fast
skill_args = ['--detach', '--', '--fast']
detach = '--detach' in skill_args
skill_args = [a for a in skill_args if a != '--detach']
pre, post = d.split_skill_args(skill_args)
assert post == ['--fast'], f'unexpected post: {post}'
ok, _ = d.validate_args(pre)
assert ok, 'empty pre should pass'
# Also test: devkit architect ~/foo feature --detach -- --fast
skill_args2 = ['feature', '--detach', '--', '--fast']
detach2 = '--detach' in skill_args2
skill_args2 = [a for a in skill_args2 if a != '--detach']
pre2, post2 = d.split_skill_args(skill_args2)
assert pre2 == ['feature'], f'unexpected pre2: {pre2}'
assert post2 == ['--fast'], f'unexpected post2: {post2}'
print('PASS: --detach + separator works in all positions')
\"" \
    0

# Test 66: _spawn_detached creates run dir with initial meta.json (status: running)
run_test 66 "_spawn_detached creates run dir with running status" \
    "RUN_ID=\"${DETACH_RUNS_CLEANUP_PREFIX}create-\$(python3 -c 'import os; print(os.urandom(3).hex())')\" && \
     python3 -c \"
import sys, os, json
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
config = dict(d.FALLBACK_DEFAULTS)
config['claude_command'] = '$MOCK_CLAUDE'
config['claude_print_flag'] = '--print'
resolved = Path('$HARNESS_TEST_DIR').resolve()
d._spawn_detached('test', resolved, 'arg1', config, '\$RUN_ID')
run_dir = Path.home() / '.claude-devkit' / 'runs' / '\$RUN_ID'
assert run_dir.is_dir(), 'run dir should exist'
meta_path = run_dir / 'meta.json'
assert meta_path.exists(), 'meta.json should exist'
meta = json.loads(meta_path.read_text())
assert meta['run_id'] == '\$RUN_ID'
assert meta['skill'] == 'test'
assert meta['status'] == 'running'
assert meta['devkit_version'] == '0.2.0'
print('PASS: run dir created with running meta.json')
\"" \
    0

# Test 67: _spawn_watcher completes run and finalizes meta.json
run_test 67 "_spawn_watcher completes run with exit 0" \
    "RUN_ID=\"${DETACH_RUNS_CLEANUP_PREFIX}complete-\$(python3 -c 'import os; print(os.urandom(3).hex())')\" && \
     RUN_DIR=\"\$HOME/.claude-devkit/runs/\$RUN_ID\" && \
     mkdir -p \"\$RUN_DIR\" && chmod 700 \"\$RUN_DIR\" && \
     python3 -c \"
import json, os
meta = {'schema_version':'1.0.0','run_id':'\$RUN_ID','skill':'test','target':'/tmp',
        'project_name':'test','args':'','pid':None,'status':'running',
        'started_at':'2026-01-01T00:00:00Z','completed_at':None,
        'exit_code':None,'devkit_version':'0.2.0'}
fd = os.open('\$RUN_DIR/meta.json', os.O_WRONLY|os.O_CREAT|os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as f: json.dump(meta, f, indent=2)
\" && \
     python3 -c \"
import sys, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
d._spawn_watcher(Path('\$RUN_DIR'),
    [sys.executable, '-c', 'print(42)'],
    '/tmp', os.environ.copy())
\" && \
     TRIES=0 && while [ \$TRIES -lt 30 ]; do \
       python3 -c \"
import json
with open('\$RUN_DIR/meta.json') as f: m = json.load(f)
exit(0 if m.get('status') != 'running' else 1)
\" 2>/dev/null && break; sleep 0.2; TRIES=\$((TRIES+1)); done && \
     python3 -c \"
import json
with open('\$RUN_DIR/meta.json') as f: meta = json.load(f)
assert meta['status'] == 'completed', 'got %s' % meta['status']
assert meta['exit_code'] == 0, 'got exit %s' % meta['exit_code']
assert meta['pid'] is not None, 'pid should be set'
assert meta['completed_at'] is not None, 'completed_at should be set'
print('PASS: watcher completed with exit 0')
\"" \
    0

# Test 68: _spawn_watcher records failure for non-zero exit
run_test 68 "_spawn_watcher records failed status" \
    "RUN_ID=\"${DETACH_RUNS_CLEANUP_PREFIX}fail-\$(python3 -c 'import os; print(os.urandom(3).hex())')\" && \
     RUN_DIR=\"\$HOME/.claude-devkit/runs/\$RUN_ID\" && \
     mkdir -p \"\$RUN_DIR\" && chmod 700 \"\$RUN_DIR\" && \
     python3 -c \"
import json, os
meta = {'schema_version':'1.0.0','run_id':'\$RUN_ID','skill':'test','target':'/tmp',
        'project_name':'test','args':'','pid':None,'status':'running',
        'started_at':'2026-01-01T00:00:00Z','completed_at':None,
        'exit_code':None,'devkit_version':'0.2.0'}
fd = os.open('\$RUN_DIR/meta.json', os.O_WRONLY|os.O_CREAT|os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as f: json.dump(meta, f, indent=2)
\" && \
     python3 -c \"
import sys, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
d._spawn_watcher(Path('\$RUN_DIR'),
    [sys.executable, '-c', 'import sys; sys.exit(42)'],
    '/tmp', os.environ.copy())
\" && \
     TRIES=0 && while [ \$TRIES -lt 30 ]; do \
       python3 -c \"
import json
with open('\$RUN_DIR/meta.json') as f: m = json.load(f)
exit(0 if m.get('status') != 'running' else 1)
\" 2>/dev/null && break; sleep 0.2; TRIES=\$((TRIES+1)); done && \
     python3 -c \"
import json
with open('\$RUN_DIR/meta.json') as f: meta = json.load(f)
assert meta['status'] == 'failed', f'got {meta[\"status\"]}'
assert meta['exit_code'] == 42, f'got exit {meta[\"exit_code\"]}'
print('PASS: watcher records failed status with exit 42')
\"" \
    0

# Test 69: _spawn_watcher handles empty stdout (no result.json)
run_test 69 "_spawn_watcher handles empty stdout" \
    "RUN_ID=\"${DETACH_RUNS_CLEANUP_PREFIX}empty-\$(python3 -c 'import os; print(os.urandom(3).hex())')\" && \
     RUN_DIR=\"\$HOME/.claude-devkit/runs/\$RUN_ID\" && \
     mkdir -p \"\$RUN_DIR\" && chmod 700 \"\$RUN_DIR\" && \
     python3 -c \"
import json, os
meta = {'schema_version':'1.0.0','run_id':'\$RUN_ID','skill':'test','target':'/tmp',
        'project_name':'test','args':'','pid':None,'status':'running',
        'started_at':'2026-01-01T00:00:00Z','completed_at':None,
        'exit_code':None,'devkit_version':'0.2.0'}
fd = os.open('\$RUN_DIR/meta.json', os.O_WRONLY|os.O_CREAT|os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as f: json.dump(meta, f, indent=2)
\" && \
     python3 -c \"
import sys, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
d._spawn_watcher(Path('\$RUN_DIR'),
    [sys.executable, '-c', 'pass'],
    '/tmp', os.environ.copy())
\" && \
     TRIES=0 && while [ \$TRIES -lt 30 ]; do \
       python3 -c \"
import json
with open('\$RUN_DIR/meta.json') as f: m = json.load(f)
exit(0 if m.get('status') != 'running' else 1)
\" 2>/dev/null && break; sleep 0.2; TRIES=\$((TRIES+1)); done && \
     python3 -c \"
import json, os
with open('\$RUN_DIR/meta.json') as f: meta = json.load(f)
assert meta['status'] == 'completed', f'got {meta[\"status\"]}'
assert not os.path.exists('\$RUN_DIR/result.json'), 'result.json should not exist'
print('PASS: empty stdout handled, no result.json')
\"" \
    0

# Test 70: devkit jobs lists synthetic run entries
run_test 70 "devkit jobs lists synthetic run entries" \
    "JOBS_ID=\"${DETACH_RUNS_CLEANUP_PREFIX}jobs-\$(python3 -c 'import os; print(os.urandom(3).hex())')\" && \
     JOBS_DIR=\"\$HOME/.claude-devkit/runs/\$JOBS_ID\" && \
     mkdir -p \"\$JOBS_DIR\" && \
     echo '{\"schema_version\":\"1.0.0\",\"run_id\":\"'\$JOBS_ID'\",\"skill\":\"audit\",\"target\":\"/tmp\",\"project_name\":\"test-proj\",\"args\":\"\",\"pid\":null,\"status\":\"completed\",\"started_at\":\"2026-08-21T12:00:00Z\",\"completed_at\":\"2026-08-21T12:05:00Z\",\"exit_code\":0,\"devkit_version\":\"0.2.0\"}' > \"\$JOBS_DIR/meta.json\" && \
     python3 '$DEVKIT_CLI' jobs 2>/dev/null | grep -q \"\$JOBS_ID\"" \
    0

# Test 71: devkit jobs detects stale PID
run_test 71 "devkit jobs shows stale for dead PID" \
    "STALE_ID=\"${DETACH_RUNS_CLEANUP_PREFIX}stale-\$(python3 -c 'import os; print(os.urandom(3).hex())')\" && \
     STALE_DIR=\"\$HOME/.claude-devkit/runs/\$STALE_ID\" && \
     mkdir -p \"\$STALE_DIR\" && \
     echo '{\"schema_version\":\"1.0.0\",\"run_id\":\"'\$STALE_ID'\",\"skill\":\"audit\",\"target\":\"/tmp\",\"project_name\":\"test\",\"args\":\"\",\"pid\":99999999,\"status\":\"running\",\"started_at\":\"2026-08-21T12:00:00Z\",\"completed_at\":null,\"exit_code\":null,\"devkit_version\":\"0.2.0\"}' > \"\$STALE_DIR/meta.json\" && \
     python3 '$DEVKIT_CLI' jobs 2>/dev/null | grep -q 'stale'" \
    0

# Test 72: devkit jobs filters by target
run_test 72 "devkit jobs filters by target" \
    "FILTER_ID=\"${DETACH_RUNS_CLEANUP_PREFIX}filter-\$(python3 -c 'import os; print(os.urandom(3).hex())')\" && \
     FILTER_DIR=\"\$HOME/.claude-devkit/runs/\$FILTER_ID\" && \
     mkdir -p \"\$FILTER_DIR\" && \
     RESOLVED_TARGET=\$(python3 -c \"from pathlib import Path; print(Path('$HARNESS_TEST_DIR').resolve())\") && \
     python3 -c \"
import json, os
meta = {'schema_version':'1.0.0','run_id':'\$FILTER_ID','skill':'audit',
        'target':'\$RESOLVED_TARGET','project_name':'devkit-harness-test',
        'args':'','pid':None,'status':'completed',
        'started_at':'2026-08-21T12:00:00Z','completed_at':'2026-08-21T12:05:00Z',
        'exit_code':0,'devkit_version':'0.2.0'}
fd = os.open('\$FILTER_DIR/meta.json', os.O_WRONLY|os.O_CREAT|os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as f: json.dump(meta, f, indent=2)
\" && \
     python3 '$DEVKIT_CLI' jobs '$HARNESS_TEST_DIR' 2>/dev/null | grep -q \"\$FILTER_ID\"" \
    0

# Test 73: devkit result shows captured output from result.json
run_test 73 "devkit result shows output from result.json" \
    "RESULT_ID=\"${DETACH_RUNS_CLEANUP_PREFIX}result-\$(python3 -c 'import os; print(os.urandom(3).hex())')\" && \
     RESULT_DIR=\"\$HOME/.claude-devkit/runs/\$RESULT_ID\" && \
     mkdir -p \"\$RESULT_DIR\" && \
     echo '{\"result\":\"hello from test\"}' > \"\$RESULT_DIR/result.json\" && \
     python3 '$DEVKIT_CLI' result \"\$RESULT_ID\" 2>/dev/null | grep -q 'hello from test'" \
    0

# Test 74: devkit logs shows captured stderr
run_test 74 "devkit logs shows stderr content" \
    "LOGS_ID=\"${DETACH_RUNS_CLEANUP_PREFIX}logs-\$(python3 -c 'import os; print(os.urandom(3).hex())')\" && \
     LOGS_DIR=\"\$HOME/.claude-devkit/runs/\$LOGS_ID\" && \
     mkdir -p \"\$LOGS_DIR\" && \
     echo 'mock progress output' > \"\$LOGS_DIR/stderr.log\" && \
     python3 '$DEVKIT_CLI' logs \"\$LOGS_ID\" 2>/dev/null | grep -q 'mock progress output'" \
    0

# Test 75: devkit result with nonexistent run ID exits 1
run_test 75 "devkit result with nonexistent run ID exits 1" \
    "python3 '$DEVKIT_CLI' result nonexistent-run-id-99999" \
    1

# Test 76: devkit clean --days 0 removes old completed runs
run_test 76 "devkit clean --days 0 removes completed runs" \
    "CLEAN_ID=\"${DETACH_RUNS_CLEANUP_PREFIX}clean-\$(python3 -c 'import os; print(os.urandom(3).hex())')\" && \
     CLEAN_DIR=\"\$HOME/.claude-devkit/runs/\$CLEAN_ID\" && \
     mkdir -p \"\$CLEAN_DIR\" && \
     echo '{\"schema_version\":\"1.0.0\",\"run_id\":\"'\$CLEAN_ID'\",\"skill\":\"audit\",\"target\":\"/tmp\",\"project_name\":\"test\",\"args\":\"\",\"pid\":null,\"status\":\"completed\",\"started_at\":\"2026-08-21T12:00:00Z\",\"completed_at\":\"2026-08-21T12:05:00Z\",\"exit_code\":0,\"devkit_version\":\"0.2.0\"}' > \"\$CLEAN_DIR/meta.json\" && \
     python3 '$DEVKIT_CLI' clean --days 0 2>/dev/null | grep -q 'Cleaned' && \
     [ ! -d \"\$CLEAN_DIR\" ]" \
    0

# Test 77: devkit clean preserves running runs
run_test 77 "devkit clean preserves running runs" \
    "PRESERVE_ID=\"${DETACH_RUNS_CLEANUP_PREFIX}preserve-\$(python3 -c 'import os; print(os.urandom(3).hex())')\" && \
     PRESERVE_DIR=\"\$HOME/.claude-devkit/runs/\$PRESERVE_ID\" && \
     mkdir -p \"\$PRESERVE_DIR\" && \
     echo '{\"schema_version\":\"1.0.0\",\"run_id\":\"'\$PRESERVE_ID'\",\"skill\":\"audit\",\"target\":\"/tmp\",\"project_name\":\"test\",\"args\":\"\",\"pid\":'$$',\"status\":\"running\",\"started_at\":\"2026-08-21T12:00:00Z\",\"completed_at\":null,\"exit_code\":null,\"devkit_version\":\"0.2.0\"}' > \"\$PRESERVE_DIR/meta.json\" && \
     python3 '$DEVKIT_CLI' clean --days 0 2>/dev/null && \
     [ -d \"\$PRESERVE_DIR\" ]" \
    0

# Test 78: devkit clean treats dead-PID running as stale and removes it
run_test 78 "devkit clean removes stale (dead PID) running runs" \
    "DEAD_ID=\"${DETACH_RUNS_CLEANUP_PREFIX}dead-\$(python3 -c 'import os; print(os.urandom(3).hex())')\" && \
     DEAD_DIR=\"\$HOME/.claude-devkit/runs/\$DEAD_ID\" && \
     mkdir -p \"\$DEAD_DIR\" && \
     echo '{\"schema_version\":\"1.0.0\",\"run_id\":\"'\$DEAD_ID'\",\"skill\":\"audit\",\"target\":\"/tmp\",\"project_name\":\"test\",\"args\":\"\",\"pid\":99999999,\"status\":\"running\",\"started_at\":\"2026-08-21T12:00:00Z\",\"completed_at\":null,\"exit_code\":null,\"devkit_version\":\"0.2.0\"}' > \"\$DEAD_DIR/meta.json\" && \
     python3 '$DEVKIT_CLI' clean --days 0 2>/dev/null && \
     [ ! -d \"\$DEAD_DIR\" ]" \
    0

# Test 79: _spawn_detached creates run dir with 0o700 permissions
run_test 79 "run directory has 0o700 permissions" \
    "RUN_ID=\"${DETACH_RUNS_CLEANUP_PREFIX}perms-\$(python3 -c 'import os; print(os.urandom(3).hex())')\" && \
     python3 -c \"
import sys, os, stat
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
config = dict(d.FALLBACK_DEFAULTS)
config['claude_command'] = '$MOCK_CLAUDE'
config['claude_print_flag'] = '--print'
resolved = Path('$HARNESS_TEST_DIR').resolve()
d._spawn_detached('test', resolved, '', config, '\$RUN_ID')
run_dir = Path.home() / '.claude-devkit' / 'runs' / '\$RUN_ID'
mode = stat.S_IMODE(run_dir.stat().st_mode)
assert mode == 0o700, f'expected 0o700, got {oct(mode)}'
meta_mode = stat.S_IMODE((run_dir / 'meta.json').stat().st_mode)
assert meta_mode == 0o600, f'meta.json expected 0o600, got {oct(meta_mode)}'
print('PASS: directory 0o700, meta.json 0o600')
\"" \
    0

# Test 80: devkit result rejects path traversal in run ID
run_test 80 "devkit result rejects path traversal in run ID" \
    "python3 '$DEVKIT_CLI' result '../../../etc/passwd'" \
    1

# Test 81: no shell=True in _spawn_detached or _spawn_watcher
run_test 81 "no shell=True in spawn functions (code inspection)" \
    "! grep -A20 'def _spawn_watcher\|def _spawn_detached' '$REPO_DIR/scripts/devkit_cli.py' | grep -q 'shell=True'" \
    0

# Test 9: Cleanup
echo ""
echo -e "${BLUE}Test 9: Cleanup${RESET}"
rm -rf "$TEST_DIR" || true
rm -rf "$DEPLOY_DIR/smoke-coord" || true
rm -rf "$DEPLOY_DIR/smoke-pipe" || true
rm -f "$HARNESS_SYMLINK" || true
rm -rf "$HARNESS_TEST_DIR" || true
rm -rf "$HARNESS_NOTGIT_DIR" || true
rm -rf "$HARNESS_NONEXISTENT_DIR" || true
rm -rf "$HARNESS_REGISTRY_DIR" || true
rm -f "$MOCK_CLAUDE" || true
# Clean up detach test run directories
if [ -d "$HOME/.claude-devkit/runs" ]; then
    for d in "$HOME/.claude-devkit/runs/${DETACH_RUNS_CLEANUP_PREFIX}"*; do
        rm -rf "$d" 2>/dev/null || true
    done
fi
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
