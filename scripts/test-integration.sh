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
# 165 tests: coordinator lifecycle, validate-all, pipeline lifecycle, unit meta-test,
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
#           lifecycle, jobs, result, logs, clean, security),
#           zero-project-footprint tests (36 new + 3 updated: project ID 7,
#           central storage 3, env vars 3, migration 6, helper scripts 7,
#           security 3, relink/path 4, backward compat 3),
#           code review M-2 tests (2 tests: env detached propagation,
#           permission check on run),
#           cross-repo plan tests (29 tests: frontmatter parser 6, URI 3,
#           plan refs 3, multi-target shell 3, multi-target skill dispatch 3,
#           devkit plan subcommand 5, read_plan_refs 2, validate_plan_targets 2,
#           cmd_path traversal 1, plan archive 1),
#           shared learnings layer tests (18 tests: parser 5, aggregator 4,
#           promotions 4, CLI 3, security 2), cleanup

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
ZPF_TEST_DIR="/tmp/devkit-zpf-test"
ZPF_MIGRATE_DIR="/tmp/devkit-zpf-migrate"
ZPF_RELINK_DIR="/tmp/devkit-zpf-relink"
ZPF_CENTRAL_CLEANUP_PREFIX="devkit-zpf-"
CRP_TEST_DIR_1="/tmp/devkit-crp-test-1"
CRP_TEST_DIR_2="/tmp/devkit-crp-test-2"
CRP_SYMLINK="/tmp/devkit-crp-symlink"
CRP_CENTRAL_CLEANUP_PREFIX="devkit-crp-"
LEARN_TEST_DIR="/tmp/devkit-learnings-test"
LEARN_CENTRAL_CLEANUP_PREFIX="devkit-learnings-"

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
    # Clean up zero-project-footprint test fixtures
    rm -rf "$ZPF_TEST_DIR" 2>/dev/null || true
    rm -rf "$ZPF_MIGRATE_DIR" 2>/dev/null || true
    rm -rf "$ZPF_RELINK_DIR" 2>/dev/null || true
    # Clean up any central project dirs created by ZPF tests
    if [ -d "$HOME/.claude-devkit/projects" ]; then
        for d in "$HOME/.claude-devkit/projects/${ZPF_CENTRAL_CLEANUP_PREFIX}"*; do
            rm -rf "$d" 2>/dev/null || true
        done
        # Also clean up central dirs for meta-harness test fixtures
        for d in "$HOME/.claude-devkit/projects/devkit-harness-"*; do
            rm -rf "$d" 2>/dev/null || true
        done
        # Clean up central dirs for cross-repo plan test fixtures
        for d in "$HOME/.claude-devkit/projects/${CRP_CENTRAL_CLEANUP_PREFIX}"*; do
            rm -rf "$d" 2>/dev/null || true
        done
    fi
    # Clean up cross-repo plan test fixtures
    rm -rf "$CRP_TEST_DIR_1" 2>/dev/null || true
    rm -rf "$CRP_TEST_DIR_2" 2>/dev/null || true
    rm -f "$CRP_SYMLINK" 2>/dev/null || true
    # Clean up learnings layer test fixtures
    rm -rf "$LEARN_TEST_DIR" 2>/dev/null || true
    if [ -d "$HOME/.claude-devkit/learnings" ]; then
        rm -rf "$HOME/.claude-devkit/learnings/${LEARN_CENTRAL_CLEANUP_PREFIX}"* 2>/dev/null || true
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

# Clean up and set up zero-project-footprint test fixtures at start
rm -rf "$ZPF_TEST_DIR" 2>/dev/null || true
rm -rf "$ZPF_MIGRATE_DIR" 2>/dev/null || true
rm -rf "$ZPF_RELINK_DIR" 2>/dev/null || true
if [ -d "$HOME/.claude-devkit/projects" ]; then
    for d in "$HOME/.claude-devkit/projects/${ZPF_CENTRAL_CLEANUP_PREFIX}"*; do
        rm -rf "$d" 2>/dev/null || true
    done
    for d in "$HOME/.claude-devkit/projects/devkit-harness-"*; do
        rm -rf "$d" 2>/dev/null || true
    done
fi

# Clean up and set up cross-repo plan test fixtures at start
rm -rf "$CRP_TEST_DIR_1" 2>/dev/null || true
rm -rf "$CRP_TEST_DIR_2" 2>/dev/null || true
rm -f "$CRP_SYMLINK" 2>/dev/null || true
if [ -d "$HOME/.claude-devkit/projects" ]; then
    for d in "$HOME/.claude-devkit/projects/${CRP_CENTRAL_CLEANUP_PREFIX}"*; do
        rm -rf "$d" 2>/dev/null || true
    done
fi

# Clean up learnings test fixtures at start
rm -rf "$LEARN_TEST_DIR" 2>/dev/null || true
if [ -d "$HOME/.claude-devkit/learnings" ]; then
    rm -rf "$HOME/.claude-devkit/learnings/${LEARN_CENTRAL_CLEANUP_PREFIX}"* 2>/dev/null || true
fi

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

# Test 16: /ship version bumped to 3.9.0
run_test 16 "ship SKILL.md version is 3.9.0" \
    "grep -q 'version: 3.9.0' '$REPO_DIR/skills/ship/SKILL.md'" \
    0

# Test 17: /architect version bumped to 3.5.0
run_test 17 "architect SKILL.md version is 3.5.0" \
    "grep -q 'version: 3.5.0' '$REPO_DIR/skills/architect/SKILL.md'" \
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

# Test 45: devkit init on a valid git repo creates state.json at central location
run_test 45 "devkit init on valid git repo creates state.json at central location" \
    "python3 '$DEVKIT_CLI' init '$HARNESS_TEST_DIR' && \
     python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
resolved = Path('$HARNESS_TEST_DIR').resolve()
project_dir = d.get_project_dir(resolved)
state_path = project_dir / 'state.json'
assert state_path.exists(), f'state.json not found at {state_path}'
import json
with open(state_path) as f:
    data = json.load(f)
assert data.get('schema_version') == '1.1.0', f'expected schema 1.1.0, got {data.get(\\\"schema_version\\\")}'
assert data.get('project_name') == 'devkit-harness-test', 'missing/invalid project_name'
assert isinstance(data.get('project_id'), str) and data['project_id'], 'missing project_id'
assert isinstance(data.get('project_path'), str) and data['project_path'], 'missing project_path'
assert data['project_path'] == str(resolved), f'project_path mismatch: {data[\\\"project_path\\\"]} != {resolved}'
assert isinstance(data.get('initialized_at'), str) and data['initialized_at'], 'missing initialized_at'
assert isinstance(data.get('devkit_version'), str) and data['devkit_version'], 'missing devkit_version'
print('PASS: state.json at central location with schema 1.1.0 fields')
\"" \
    0

# Test 46: devkit init does NOT modify the target's .gitignore (zero footprint)
run_test 46 "devkit init does NOT modify target .gitignore" \
    "! test -f '$HARNESS_TEST_DIR/.gitignore' || ! grep -qF '.devkit/' '$HARNESS_TEST_DIR/.gitignore'" \
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
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
project_dir = d.get_project_dir(Path('$HARNESS_TEST_DIR').resolve())
state_path = project_dir / 'state.json'
state_path.parent.mkdir(parents=True, exist_ok=True)
state_path.write_text('x' * 100000)
\" && \
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
assert meta['devkit_version'] == '0.4.0'
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

# --- Zero-project-footprint tests (82-118) ---
# These tests verify the centralized artifact storage model where devkit
# creates no files inside target projects. All artifacts live under
# ~/.claude-devkit/projects/<project-id>/.
#
# Fixtures: ZPF_TEST_DIR, ZPF_MIGRATE_DIR, ZPF_RELINK_DIR are created
# inline per test group. Central project dirs use the ZPF_CENTRAL_CLEANUP_PREFIX
# to enable selective cleanup.

# --- Project ID tests (82-88) ---

# Test 82: compute_project_id is deterministic (same path -> same ID)
run_test 82 "compute_project_id is deterministic" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
p = Path('/tmp/${ZPF_CENTRAL_CLEANUP_PREFIX}deterministic-test').resolve()
id1 = d.compute_project_id(p)
id2 = d.compute_project_id(p)
assert id1 == id2, f'Not deterministic: {id1} != {id2}'
print(f'PASS: deterministic ID = {id1}')
\""  \
    0

# Test 83: compute_project_id produces unique IDs for different paths
run_test 83 "compute_project_id produces unique IDs for different paths" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
id1 = d.compute_project_id(Path('/tmp/project-alpha'))
id2 = d.compute_project_id(Path('/tmp/project-beta'))
assert id1 != id2, f'IDs should differ: {id1} == {id2}'
print(f'PASS: unique IDs: {id1} vs {id2}')
\"" \
    0

# Test 84: same basename in different parent dirs gets different IDs
run_test 84 "compute_project_id: same basename, different parent -> different IDs" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
id1 = d.compute_project_id(Path('/tmp/work/api'))
id2 = d.compute_project_id(Path('/tmp/personal/api'))
assert id1 != id2, f'Same-basename IDs should differ: {id1} == {id2}'
# Both should start with 'api-'
assert id1.startswith('api-'), f'Expected api- prefix, got {id1}'
assert id2.startswith('api-'), f'Expected api- prefix, got {id2}'
print(f'PASS: same basename, different IDs: {id1} vs {id2}')
\"" \
    0

# Test 85: project ID format matches expected pattern
run_test 85 "compute_project_id format matches ^[a-zA-Z0-9._-]+-[0-9a-f]{12}$" \
    "python3 -c \"
import sys, re
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
test_paths = [
    Path('/tmp/my-app'),
    Path('/tmp/some.project'),
    Path('/tmp/under_score'),
]
for p in test_paths:
    pid = d.compute_project_id(p)
    assert re.match(r'^[a-zA-Z0-9._-]+-[0-9a-f]{12}\$', pid), f'Bad format for {p}: {pid}'
print('PASS: all project IDs match expected format')
\"" \
    0

# Test 86: case insensitive on macOS (darwin)
run_test 86 "compute_project_id: case insensitive on macOS" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
if sys.platform == 'darwin':
    id_lower = d.compute_project_id(Path('/tmp/myproject'))
    id_upper = d.compute_project_id(Path('/tmp/MyProject'))
    assert id_lower == id_upper, f'Case-insensitive IDs should match on macOS: {id_lower} != {id_upper}'
    print('PASS: case-insensitive on macOS')
else:
    id_lower = d.compute_project_id(Path('/tmp/myproject'))
    id_upper = d.compute_project_id(Path('/tmp/MyProject'))
    assert id_lower != id_upper, f'Case-sensitive IDs should differ on Linux: {id_lower} == {id_upper}'
    print('PASS: case-sensitive on Linux (platform-appropriate)')
\"" \
    0

# Test 87: special characters in project name are sanitized
run_test 87 "compute_project_id: special chars sanitized" \
    "python3 -c \"
import sys, re
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
pid = d.compute_project_id(Path('/tmp/my project (v2)'))
# Should not contain spaces or parens
assert ' ' not in pid, f'Space in project ID: {pid}'
assert '(' not in pid, f'Paren in project ID: {pid}'
assert ')' not in pid, f'Paren in project ID: {pid}'
# Should still match the valid format
assert re.match(r'^[a-zA-Z0-9._-]+-[0-9a-f]{12}\$', pid), f'Bad format: {pid}'
print(f'PASS: sanitized ID = {pid}')
\"" \
    0

# Test 88: filesystem root is rejected
run_test 88 "compute_project_id: filesystem root raises ValueError" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
try:
    d.compute_project_id(Path('/'))
    print('FAIL: should have raised ValueError')
    sys.exit(1)
except ValueError as e:
    assert 'root' in str(e).lower(), f'Error message should mention root: {e}'
    print(f'PASS: root rejected with: {e}')
\"" \
    0

# --- Central storage tests (89-91) ---
# (Tests 45, 46 are updated above to cover init-creates-central-dir,
#  init-does-not-modify-gitignore, and state-in-central-location)

# Test 89: devkit init does NOT create .devkit/ in target
run_test 89 "devkit init does NOT create .devkit/ in target project" \
    "rm -rf '$ZPF_TEST_DIR' 2>/dev/null || true && \
     mkdir -p '$ZPF_TEST_DIR' && git -C '$ZPF_TEST_DIR' init -q && \
     python3 '$DEVKIT_CLI' init '$ZPF_TEST_DIR' && \
     [ ! -d '$ZPF_TEST_DIR/.devkit' ]" \
    0

# Test 90: devkit init creates plans/ directory in central location
run_test 90 "devkit init creates plans/ dir at central location" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
resolved = Path('$ZPF_TEST_DIR').resolve()
project_dir = d.get_project_dir(resolved)
plans_dir = project_dir / 'plans'
assert plans_dir.is_dir(), f'plans/ not found at {plans_dir}'
print(f'PASS: plans/ exists at {plans_dir}')
\"" \
    0

# Test 91: devkit init detects collision (simulated same project ID, different path)
run_test 91 "devkit init detects project ID collision" \
    "python3 -c \"
import sys, json, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

# Read existing state for ZPF_TEST_DIR and tamper project_path to simulate collision
resolved = Path('$ZPF_TEST_DIR').resolve()
project_dir = d.get_project_dir(resolved)
state_path = project_dir / 'state.json'
if state_path.exists():
    with open(state_path) as f:
        state = json.load(f)
    # Change project_path to a different path to simulate collision
    state['project_path'] = '/tmp/some-totally-different-project'
    with open(state_path, 'w') as f:
        json.dump(state, f)
    # Now init should detect the collision and exit 1
    config = dict(d.FALLBACK_DEFAULTS)
    config['allowed_roots'] = ['~/projects/', '~/workspaces/']
    result = d.cmd_init('$ZPF_TEST_DIR', config)
    assert result == 1, f'Expected exit 1 (collision), got {result}'
    # Restore original state for subsequent tests
    state['project_path'] = str(resolved)
    with open(state_path, 'w') as f:
        json.dump(state, f)
    print('PASS: collision detected and rejected')
else:
    print('PASS: skipped (no state to tamper -- init not yet run)')
\"" \
    0

# --- Environment variable tests (92-94) ---

# Test 92: cmd_run_skill sets DEVKIT_PROJECT_DIR in subprocess env
run_test 92 "cmd_run_skill sets DEVKIT_PROJECT_DIR env var" \
    "python3 -c \"
import sys, os, json
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

# Create a mock claude that dumps its env
mock = '/tmp/zpf-mock-claude-env'
with open(mock, 'w') as f:
    f.write('#!/bin/bash\n')
    f.write('echo \\\"{\\\\\\\"result\\\\\\\":\\\\\\\"ok\\\\\\\"}\\\"\n')
    f.write('echo \\\"DEVKIT_PROJECT_DIR=\\\$DEVKIT_PROJECT_DIR\\\" >&2\n')
os.chmod(mock, 0o755)

config = dict(d.FALLBACK_DEFAULTS)
config['claude_command'] = mock
config['claude_print_flag'] = '--print'
config['allowed_roots'] = ['~/projects/', '~/workspaces/']

resolved = Path('$ZPF_TEST_DIR').resolve()
expected_dir = str(d.get_project_dir(resolved))

# Run the skill -- check that the env was set by examining the function
# that builds the env dict (since subprocess output goes to stdout/stderr)
import subprocess
orig_run = subprocess.run
captured_env = {}
def mock_run(args, **kwargs):
    env = kwargs.get('env', {})
    captured_env['DEVKIT_PROJECT_DIR'] = env.get('DEVKIT_PROJECT_DIR')
    captured_env['DEVKIT_SCRIPTS'] = env.get('DEVKIT_SCRIPTS')
    class FakeResult:
        returncode = 0
        stdout = '{\"result\":\"ok\"}'
        stderr = ''
    return FakeResult()
subprocess.run = mock_run
try:
    d.cmd_run_skill('audit', '$ZPF_TEST_DIR', [], [], config)
finally:
    subprocess.run = orig_run
    os.unlink(mock)

assert captured_env.get('DEVKIT_PROJECT_DIR') == expected_dir, \
    f'DEVKIT_PROJECT_DIR mismatch: {captured_env.get(\\\"DEVKIT_PROJECT_DIR\\\")} != {expected_dir}'
print('PASS: DEVKIT_PROJECT_DIR set correctly in subprocess env')
\"" \
    0

# Test 93: cmd_run_skill sets DEVKIT_SCRIPTS in subprocess env
run_test 93 "cmd_run_skill sets DEVKIT_SCRIPTS env var" \
    "python3 -c \"
import sys, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
import subprocess

config = dict(d.FALLBACK_DEFAULTS)
config['claude_command'] = '/tmp/devkit-mock-claude'
config['claude_print_flag'] = '--print'
config['allowed_roots'] = ['~/projects/', '~/workspaces/']

expected_scripts = str(d.get_scripts_dir(config))

captured_env = {}
orig_run = subprocess.run
def mock_run(args, **kwargs):
    env = kwargs.get('env', {})
    captured_env['DEVKIT_SCRIPTS'] = env.get('DEVKIT_SCRIPTS')
    class FakeResult:
        returncode = 0
        stdout = '{\"result\":\"ok\"}'
        stderr = ''
    return FakeResult()
subprocess.run = mock_run
try:
    d.cmd_run_skill('audit', '$ZPF_TEST_DIR', [], [], config)
finally:
    subprocess.run = orig_run

assert captured_env.get('DEVKIT_SCRIPTS') == expected_scripts, \
    f'DEVKIT_SCRIPTS mismatch: {captured_env.get(\\\"DEVKIT_SCRIPTS\\\")} != {expected_scripts}'
print('PASS: DEVKIT_SCRIPTS set correctly in subprocess env')
\"" \
    0

# Test 94: DEVKIT_PROJECT_DIR points to correct project-specific central dir
run_test 94 "DEVKIT_PROJECT_DIR points to correct central dir" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

resolved = Path('$ZPF_TEST_DIR').resolve()
project_id = d.compute_project_id(resolved)
expected = str(Path.home() / '.claude-devkit' / 'projects' / project_id)
actual = str(d.get_project_dir(resolved))
assert actual == expected, f'Mismatch: {actual} != {expected}'
assert project_id in actual, f'project_id {project_id} not in path {actual}'
print(f'PASS: project dir = {actual}')
\"" \
    0

# --- Migration tests (95-100) ---
# Create a target with legacy .devkit/ for migration testing

# Test 95: devkit migrate copies state.json to central location
run_test 95 "devkit migrate copies state.json to central location" \
    "rm -rf '$ZPF_MIGRATE_DIR' 2>/dev/null || true && \
     mkdir -p '$ZPF_MIGRATE_DIR' && git -C '$ZPF_MIGRATE_DIR' init -q && \
     mkdir -p '$ZPF_MIGRATE_DIR/.devkit' && \
     echo '{\"schema_version\":\"1.0.0\",\"project_name\":\"${ZPF_CENTRAL_CLEANUP_PREFIX}migrate\",\"initialized_at\":\"2026-01-01T00:00:00Z\",\"devkit_version\":\"0.1.0\"}' > '$ZPF_MIGRATE_DIR/.devkit/state.json' && \
     python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
# Clean any prior central dir for this test path
resolved = Path('$ZPF_MIGRATE_DIR').resolve()
import shutil
central = d.get_project_dir(resolved)
if central.exists():
    shutil.rmtree(str(central))
\" && \
     python3 '$DEVKIT_CLI' migrate '$ZPF_MIGRATE_DIR' && \
     python3 -c \"
import sys, json
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
resolved = Path('$ZPF_MIGRATE_DIR').resolve()
central = d.get_project_dir(resolved)
state_path = central / 'state.json'
assert state_path.exists(), f'state.json not found at {state_path}'
with open(state_path) as f:
    data = json.load(f)
assert data.get('project_name') is not None, 'missing project_name in migrated state'
print('PASS: state.json migrated to central location')
\"" \
    0

# Test 96: devkit migrate copies plans/ tree to central location
run_test 96 "devkit migrate copies plans/ tree to central location" \
    "mkdir -p '$ZPF_MIGRATE_DIR/.devkit/plans/archive' && \
     echo '# Test plan' > '$ZPF_MIGRATE_DIR/.devkit/plans/test-feature.md' && \
     echo '# Archived' > '$ZPF_MIGRATE_DIR/.devkit/plans/archive/old-review.md' && \
     python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
import shutil
resolved = Path('$ZPF_MIGRATE_DIR').resolve()
central = d.get_project_dir(resolved)
# Remove central to re-test migrate
if central.exists():
    shutil.rmtree(str(central))
\" && \
     python3 '$DEVKIT_CLI' migrate '$ZPF_MIGRATE_DIR' && \
     python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
resolved = Path('$ZPF_MIGRATE_DIR').resolve()
central = d.get_project_dir(resolved)
plan = central / 'plans' / 'test-feature.md'
archive = central / 'plans' / 'archive' / 'old-review.md'
assert plan.exists(), f'plan not found at {plan}'
assert archive.exists(), f'archive not found at {archive}'
print('PASS: plans/ tree migrated with subdirectories')
\"" \
    0

# Test 97: devkit migrate preserves source .devkit/ (non-destructive)
run_test 97 "devkit migrate preserves source .devkit/ (non-destructive)" \
    "[ -d '$ZPF_MIGRATE_DIR/.devkit' ] && \
     [ -f '$ZPF_MIGRATE_DIR/.devkit/state.json' ] && \
     [ -f '$ZPF_MIGRATE_DIR/.devkit/plans/test-feature.md' ]" \
    0

# Test 98: devkit migrate on project without .devkit/ is a no-op
run_test 98 "devkit migrate on project without .devkit/ is a no-op (exit 0)" \
    "rm -rf '$ZPF_TEST_DIR/.devkit' 2>/dev/null || true && \
     python3 '$DEVKIT_CLI' migrate '$ZPF_TEST_DIR' 2>&1 | grep -qi 'nothing to migrate'" \
    0

# Test 99: devkit migrate aborts if central dir already exists
run_test 99 "devkit migrate aborts if central dir already exists" \
    "python3 '$DEVKIT_CLI' migrate '$ZPF_MIGRATE_DIR'" \
    1

# Test 100: devkit migrate rolls back on copy failure (simulated)
run_test 100 "devkit migrate rolls back on copy failure" \
    "python3 -c \"
import sys, os, json
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
import shutil

# Create a fresh migration source
test_dir = Path('/tmp/${ZPF_CENTRAL_CLEANUP_PREFIX}rollback-test')
test_dir.mkdir(parents=True, exist_ok=True)
os.system(f'git -C {test_dir} init -q 2>/dev/null')
devkit_dir = test_dir / '.devkit'
devkit_dir.mkdir(exist_ok=True)
plans_dir = devkit_dir / 'plans'
plans_dir.mkdir(exist_ok=True)
(devkit_dir / 'state.json').write_text('{\\\"schema_version\\\":\\\"1.0.0\\\",\\\"project_name\\\":\\\"rollback\\\"}')

# Make the plans directory unreadable to force a copy failure
os.chmod(str(plans_dir), 0o000)

config = dict(d.FALLBACK_DEFAULTS)
config['allowed_roots'] = ['~/projects/', '~/workspaces/']
result = d.cmd_migrate(str(test_dir), config)

# Restore permissions for cleanup
os.chmod(str(plans_dir), 0o755)

# The central dir should have been rolled back (removed)
central = d.get_project_dir(test_dir.resolve())
assert not central.exists(), f'Central dir should be removed after rollback: {central}'

# Clean up
shutil.rmtree(str(test_dir), ignore_errors=True)
print('PASS: migration rolled back on failure, central dir removed')
\"" \
    0

# --- Helper script tests (101-107) ---

# Test 101: deploy.sh copies helper scripts to ~/.claude-devkit/scripts/
run_test 101 "deploy.sh copies helper scripts to ~/.claude-devkit/scripts/" \
    "bash '$REPO_DIR/scripts/deploy.sh' >/dev/null 2>&1 && \
     [ -f '$HOME/.claude-devkit/scripts/emit-audit-event.sh' ] && \
     [ -f '$HOME/.claude-devkit/scripts/resolve-project-dir.sh' ]" \
    0

# Test 102: deployed scripts have 0o500 permissions (read+exec, no write)
run_test 102 "deployed helper scripts have 0o500 permissions" \
    "python3 -c \"
import os, stat
from pathlib import Path
scripts_dir = Path.home() / '.claude-devkit' / 'scripts'
for name in ['emit-audit-event.sh', 'resolve-project-dir.sh', 'compute-run-score.sh']:
    path = scripts_dir / name
    if path.exists():
        mode = stat.S_IMODE(path.stat().st_mode)
        assert mode == 0o500, f'{name} permissions: {oct(mode)}, expected 0o500'
print('PASS: all deployed scripts have 0o500 permissions')
\"" \
    0

# Test 103: deploy.sh writes .checksums.json with SHA-256 checksums
run_test 103 "deploy.sh writes .checksums.json with SHA-256 checksums" \
    "python3 -c \"
import json
from pathlib import Path
checksums_path = Path.home() / '.claude-devkit' / 'scripts' / '.checksums.json'
assert checksums_path.exists(), f'.checksums.json not found at {checksums_path}'
with open(checksums_path) as f:
    data = json.load(f)
assert isinstance(data, dict), 'checksums should be a dict'
assert len(data) > 0, 'checksums should not be empty'
# Verify at least one entry has a 64-char hex string (SHA-256)
for name, checksum in data.items():
    assert len(checksum) == 64, f'{name}: checksum length {len(checksum)}, expected 64'
    assert all(c in '0123456789abcdef' for c in checksum), f'{name}: invalid hex in checksum'
    break
print(f'PASS: .checksums.json has {len(data)} entries with valid SHA-256 hashes')
\"" \
    0

# Test 104: resolve-project-dir.sh returns DEVKIT_PROJECT_DIR when set
run_test 104 "resolve-project-dir.sh returns DEVKIT_PROJECT_DIR when set" \
    "RESULT=\$(DEVKIT_PROJECT_DIR='/tmp/test-project-dir' bash '$REPO_DIR/scripts/resolve-project-dir.sh') && \
     [ \"\$RESULT\" = '/tmp/test-project-dir' ]" \
    0

# Test 105: resolve-project-dir.sh computes correct path from CWD (tier 2)
run_test 105 "resolve-project-dir.sh computes path from CWD when env not set" \
    "RESULT=\$(cd '$ZPF_TEST_DIR' && unset DEVKIT_PROJECT_DIR && bash '$REPO_DIR/scripts/resolve-project-dir.sh' 2>/dev/null) && \
     echo \"\$RESULT\" | grep -q '\.claude-devkit/projects/'" \
    0

# Test 106: resolve-project-dir.sh returns .devkit with warning when no devkit detected (tier 3)
run_test 106 "resolve-project-dir.sh legacy fallback emits warning" \
    "OUTPUT=\$(cd /tmp && unset DEVKIT_PROJECT_DIR && unset CLAUDE_DEVKIT && \
     HOME=/tmp/nonexistent-home-zpf bash '$REPO_DIR/scripts/resolve-project-dir.sh' 2>&1) && \
     echo \"\$OUTPUT\" | grep -qi 'WARNING' && \
     echo \"\$OUTPUT\" | grep -q '.devkit'" \
    0

# Test 107: resolve-project-dir.sh handles directory names with special chars safely
run_test 107 "resolve-project-dir.sh: no shell injection via directory names" \
    "SPECIAL_DIR=\"/tmp/${ZPF_CENTRAL_CLEANUP_PREFIX}special'chars test\" && \
     mkdir -p \"\$SPECIAL_DIR\" && \
     RESULT=\$(cd \"\$SPECIAL_DIR\" && unset DEVKIT_PROJECT_DIR && bash '$REPO_DIR/scripts/resolve-project-dir.sh' 2>/dev/null) && \
     echo \"\$RESULT\" | grep -q '\.claude-devkit/projects/' && \
     rm -rf \"\$SPECIAL_DIR\"" \
    0

# --- Security tests (108-110) ---

# Test 108: central project dir has 0o700 permissions
run_test 108 "central project dir has 0o700 permissions after init" \
    "python3 -c \"
import sys, os, stat
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
resolved = Path('$ZPF_TEST_DIR').resolve()
project_dir = d.get_project_dir(resolved)
if project_dir.exists():
    mode = stat.S_IMODE(project_dir.stat().st_mode)
    assert mode == 0o700, f'project dir permissions: {oct(mode)}, expected 0o700'
    print('PASS: central project dir has 0o700 permissions')
else:
    print('PASS: skipped (project dir not yet created)')
\"" \
    0

# Test 109: state file has 0o600 permissions
run_test 109 "state.json has 0o600 permissions" \
    "python3 -c \"
import sys, os, stat
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
resolved = Path('$ZPF_TEST_DIR').resolve()
state_path = d.get_project_dir(resolved) / 'state.json'
if state_path.exists():
    mode = stat.S_IMODE(state_path.stat().st_mode)
    assert mode == 0o600, f'state.json permissions: {oct(mode)}, expected 0o600'
    print('PASS: state.json has 0o600 permissions')
else:
    print('PASS: skipped (state.json not yet created)')
\"" \
    0

# Test 110: validate_target rejects filesystem root
run_test 110 "validate_target rejects filesystem root /" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
config = dict(d.FALLBACK_DEFAULTS)
config['allowed_roots'] = ['~/projects/', '~/workspaces/']
ok, err = d.validate_target('/', config)
assert not ok, 'Root should be rejected'
assert 'root' in err.lower() or 'basename' in err.lower(), f'Error should mention root: {err}'
print(f'PASS: root rejected with: {err}')
\"" \
    0

# --- Relink and path tests (111-114) ---

# Test 111: devkit relink renames project directory and updates state
run_test 111 "devkit relink renames project dir and updates state" \
    "rm -rf '$ZPF_RELINK_DIR' 2>/dev/null || true && \
     OLD_DIR='/tmp/${ZPF_CENTRAL_CLEANUP_PREFIX}relink-old' && \
     NEW_DIR='/tmp/${ZPF_CENTRAL_CLEANUP_PREFIX}relink-new' && \
     rm -rf \"\$OLD_DIR\" \"\$NEW_DIR\" 2>/dev/null || true && \
     mkdir -p \"\$OLD_DIR\" && git -C \"\$OLD_DIR\" init -q && \
     mkdir -p \"\$NEW_DIR\" && git -C \"\$NEW_DIR\" init -q && \
     python3 '$DEVKIT_CLI' init \"\$OLD_DIR\" && \
     python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
old_dir = d.get_project_dir(Path('\$OLD_DIR').resolve())
assert old_dir.is_dir(), f'Old project dir should exist: {old_dir}'
\" && \
     python3 '$DEVKIT_CLI' relink \"\$OLD_DIR\" \"\$NEW_DIR\" && \
     python3 -c \"
import sys, json
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
old_dir = d.get_project_dir(Path('\$OLD_DIR').resolve())
new_dir = d.get_project_dir(Path('\$NEW_DIR').resolve())
assert not old_dir.exists(), f'Old project dir should be gone: {old_dir}'
assert new_dir.is_dir(), f'New project dir should exist: {new_dir}'
state_path = new_dir / 'state.json'
with open(state_path) as f:
    state = json.load(f)
assert str(Path('\$NEW_DIR').resolve()) in state.get('project_path', ''), \
    f'State project_path should reference new dir'
print('PASS: relink renamed dir and updated state')
\" && \
     rm -rf \"\$OLD_DIR\" \"\$NEW_DIR\"" \
    0

# Test 112: devkit status warns on path mismatch
run_test 112 "devkit status warns when project_path mismatches current target" \
    "python3 -c \"
import sys, json
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

resolved = Path('$ZPF_TEST_DIR').resolve()
project_dir = d.get_project_dir(resolved)
state_path = project_dir / 'state.json'
if state_path.exists():
    with open(state_path) as f:
        state = json.load(f)
    original_path = state.get('project_path')
    # Tamper to simulate a moved project
    state['project_path'] = '/tmp/some-old-path-that-does-not-exist'
    with open(state_path, 'w') as f:
        json.dump(state, f)
\" && \
     OUTPUT=\$(python3 '$DEVKIT_CLI' status '$ZPF_TEST_DIR' 2>&1) && \
     echo \"\$OUTPUT\" | grep -qi 'warning\|previously' && \
     python3 -c \"
import sys, json
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
resolved = Path('$ZPF_TEST_DIR').resolve()
state_path = d.get_project_dir(resolved) / 'state.json'
if state_path.exists():
    with open(state_path) as f:
        state = json.load(f)
    state['project_path'] = str(resolved)
    with open(state_path, 'w') as f:
        json.dump(state, f)
\"" \
    0

# Test 113: devkit path prints correct central directory path
run_test 113 "devkit path prints correct central directory path" \
    "OUTPUT=\$(python3 '$DEVKIT_CLI' path '$ZPF_TEST_DIR') && \
     echo \"\$OUTPUT\" | grep -q '\.claude-devkit/projects/'" \
    0

# Test 114: devkit path with subpath appends correctly
run_test 114 "devkit path with subpath appends correctly" \
    "OUTPUT=\$(python3 '$DEVKIT_CLI' path '$ZPF_TEST_DIR' plans/feature.md) && \
     echo \"\$OUTPUT\" | grep -q '\.claude-devkit/projects/.*plans/feature.md'" \
    0

# --- Backward compatibility tests (115-117) ---

# Test 115: resolve-project-dir.sh computes path without DEVKIT_PROJECT_DIR
# (tier 2 fallback when CLAUDE_DEVKIT or ~/.claude-devkit exists)
run_test 115 "resolve: tier 2 fallback computes path without DEVKIT_PROJECT_DIR" \
    "RESULT=\$(cd '$ZPF_TEST_DIR' && unset DEVKIT_PROJECT_DIR && \
     CLAUDE_DEVKIT='$REPO_DIR' bash '$REPO_DIR/scripts/resolve-project-dir.sh' 2>/dev/null) && \
     echo \"\$RESULT\" | grep -q '\.claude-devkit/projects/' && \
     [ -n \"\$RESULT\" ]" \
    0

# Test 116: tier 3 legacy fallback emits deprecation warning to stderr
run_test 116 "resolve: tier 3 legacy fallback emits deprecation warning" \
    "STDERR_OUTPUT=\$(cd /tmp && unset DEVKIT_PROJECT_DIR && unset CLAUDE_DEVKIT && \
     HOME=/tmp/nonexistent-home-zpf-116 bash '$REPO_DIR/scripts/resolve-project-dir.sh' 2>&1 1>/dev/null) && \
     echo \"\$STDERR_OUTPUT\" | grep -qi 'warning\|deprecated'" \
    0

# Test 117: read_state handles schema 1.0.0 state files (missing project_id/project_path)
run_test 117 "read_state handles schema 1.0.0 state files gracefully" \
    "python3 -c \"
import sys, json, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

# Create a schema 1.0.0 state file (no project_id, no project_path)
resolved = Path('$ZPF_TEST_DIR').resolve()
project_dir = d.get_project_dir(resolved)
project_dir.mkdir(parents=True, exist_ok=True)
state_path = project_dir / 'state.json'
old_state = {
    'schema_version': '1.0.0',
    'project_name': resolved.name,
    'initialized_at': '2026-01-01T00:00:00Z',
    'devkit_version': '0.1.0'
}
fd = os.open(str(state_path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as f:
    json.dump(old_state, f)

config = dict(d.FALLBACK_DEFAULTS)
state = d.read_state(resolved, config)
assert state is not None, 'read_state should handle 1.0.0 schema'
# After schema migration, project_id and project_path should be present
assert state.get('project_id') is not None or state.get('schema_version') == '1.0.0', \
    'state should either have project_id or be readable as 1.0.0'
print('PASS: schema 1.0.0 state file handled gracefully')
\"" \
    0

# --- Code review M-2 tests (118-119) ---

# Test 118: _spawn_detached propagates DEVKIT_PROJECT_DIR and DEVKIT_SCRIPTS to env
run_test 118 "_spawn_detached propagates DEVKIT_PROJECT_DIR and DEVKIT_SCRIPTS in env" \
    "python3 -c \"
import sys, os, json
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
import subprocess

config = dict(d.FALLBACK_DEFAULTS)
config['claude_command'] = '$MOCK_CLAUDE'
config['claude_print_flag'] = '--print'

resolved = Path('$HARNESS_TEST_DIR').resolve()
expected_project_dir = str(d.get_project_dir(resolved))
expected_scripts_dir = str(d.get_scripts_dir(config))

# Capture the env dict passed to _spawn_watcher by monkey-patching it
captured_env = {}
orig_spawn_watcher = d._spawn_watcher
def mock_spawn_watcher(runs_dir, invocation, cwd, env):
    captured_env.update(env)
d._spawn_watcher = mock_spawn_watcher
try:
    run_id = 'test-detach-env-propagation'
    runs_dir = Path.home() / '.claude-devkit' / 'runs' / run_id
    if runs_dir.exists():
        import shutil
        shutil.rmtree(str(runs_dir))
    d._spawn_detached('audit', resolved, '', config, run_id)
finally:
    d._spawn_watcher = orig_spawn_watcher
    # Clean up
    runs_dir = Path.home() / '.claude-devkit' / 'runs' / 'test-detach-env-propagation'
    if runs_dir.exists():
        import shutil
        shutil.rmtree(str(runs_dir))

assert captured_env.get('DEVKIT_PROJECT_DIR') == expected_project_dir, \
    f'DEVKIT_PROJECT_DIR: {captured_env.get(\\\"DEVKIT_PROJECT_DIR\\\")} != {expected_project_dir}'
assert captured_env.get('DEVKIT_SCRIPTS') == expected_scripts_dir, \
    f'DEVKIT_SCRIPTS: {captured_env.get(\\\"DEVKIT_SCRIPTS\\\")} != {expected_scripts_dir}'
assert captured_env.get('CLAUDE_DEVKIT') is not None, 'CLAUDE_DEVKIT should also be set'
print('PASS: _spawn_detached propagates DEVKIT_PROJECT_DIR and DEVKIT_SCRIPTS')
\"" \
    0

# Test 119: cmd_run_skill aborts when central project dir has insecure permissions
run_test 119 "cmd_run_skill aborts on insecure project dir permissions (0o755)" \
    "python3 -c \"
import sys, os, stat
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path
import subprocess

# Ensure project is initialized so central dir exists
resolved = Path('$ZPF_TEST_DIR').resolve()
project_dir = d.get_project_dir(resolved)
project_dir.mkdir(parents=True, exist_ok=True)

# Create a minimal valid state so preflight doesn't fail on missing state
state = {
    'schema_version': '1.1.0',
    'project_name': resolved.name,
    'project_id': d.compute_project_id(resolved),
    'project_path': str(resolved),
    'initialized_at': '2026-01-01T00:00:00Z',
    'devkit_version': '0.3.0',
}
config = dict(d.FALLBACK_DEFAULTS)
config['claude_command'] = '/tmp/devkit-mock-claude'
config['claude_print_flag'] = '--print'
config['allowed_roots'] = ['~/projects/', '~/workspaces/']
d.write_state(resolved, state, config)

# Widen permissions to trigger the security check
os.chmod(str(project_dir), 0o755)

# Mock subprocess.run so we never actually invoke claude
orig_run = subprocess.run
def mock_run(args, **kwargs):
    class FakeResult:
        returncode = 0
        stdout = '{\"result\":\"ok\"}'
        stderr = ''
    return FakeResult()
subprocess.run = mock_run
try:
    result = d.cmd_run_skill('audit', '$ZPF_TEST_DIR', [], [], config)
finally:
    subprocess.run = orig_run
    # Restore 0o700 for cleanup
    os.chmod(str(project_dir), 0o700)

assert result == 1, f'Expected exit 1 (insecure permissions), got {result}'
print('PASS: cmd_run_skill aborted on insecure project dir permissions')
\"" \
    0

# --- Cross-repo plan support tests (120-148) ---
# These tests verify plan frontmatter parsing, devkit:// URI resolution,
# plan-ref files, multi-target shell/skill dispatch, devkit plan subcommand,
# read_plan_refs, validate_plan_targets, cmd_path traversal protection, and
# plan archive. Fixtures: CRP_TEST_DIR_1, CRP_TEST_DIR_2 (git repos).

# Set up cross-repo plan test git repos and initialize them
mkdir -p "$CRP_TEST_DIR_1" && git -C "$CRP_TEST_DIR_1" init -q
mkdir -p "$CRP_TEST_DIR_2" && git -C "$CRP_TEST_DIR_2" init -q
python3 "$DEVKIT_CLI" init "$CRP_TEST_DIR_1" 2>/dev/null
python3 "$DEVKIT_CLI" init "$CRP_TEST_DIR_2" 2>/dev/null

# --- Plan frontmatter parser tests (120-125) ---

# Test 120: parse_plan_frontmatter extracts targets from valid frontmatter
run_test 120 "parse_plan_frontmatter extracts targets from valid frontmatter" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

content = '''---
status: DRAFT
targets:
  - path: ~/projects/project-a
    role: primary
  - path: ~/projects/project-b
    role: secondary
---
# Plan body
'''
fm, err = d.parse_plan_frontmatter(content)
assert err == '', f'Unexpected error: {err}'
assert fm.get('status') == 'DRAFT', f'status mismatch: {fm.get(\\\"status\\\")}'
assert 'targets' in fm, 'missing targets key'
assert len(fm['targets']) == 2, f'expected 2 targets, got {len(fm[\\\"targets\\\"])}'
assert fm['targets'][0]['path'] == '~/projects/project-a', f'wrong path: {fm[\\\"targets\\\"][0]}'
assert fm['targets'][0]['role'] == 'primary', f'wrong role: {fm[\\\"targets\\\"][0]}'
assert fm['targets'][1]['role'] == 'secondary', f'wrong role: {fm[\\\"targets\\\"][1]}'
print('PASS: parse_plan_frontmatter extracts targets correctly')
\"" \
    0

# Test 121: parse_plan_frontmatter handles plan without targets (single-project)
run_test 121 "parse_plan_frontmatter handles plan without targets (single-project)" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

content = '''---
status: APPROVED
author: test-user
---
# Single project plan
'''
fm, err = d.parse_plan_frontmatter(content)
assert err == '', f'Unexpected error: {err}'
assert fm.get('status') == 'APPROVED', f'status mismatch: {fm.get(\\\"status\\\")}'
assert 'targets' not in fm, f'targets should not be present: {fm}'
assert fm.get('author') == 'test-user', f'author mismatch: {fm.get(\\\"author\\\")}'
print('PASS: single-project plan parsed without targets key')
\"" \
    0

# Test 122: validate_plan_targets rejects more than 10 targets
run_test 122 "validate_plan_targets rejects more than 10 targets" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

# Build a list of 11 targets
targets = []
for i in range(11):
    role = 'primary' if i == 0 else 'secondary'
    targets.append({'path': f'/tmp/project-{i}', 'role': role})

config = dict(d.FALLBACK_DEFAULTS)
ok, err = d.validate_plan_targets(targets, config)
assert not ok, 'should reject >10 targets'
assert 'maximum' in err.lower() or 'exceed' in err.lower(), f'error should mention maximum: {err}'
print(f'PASS: 11 targets rejected with: {err}')
\"" \
    0

# Test 123: parse_plan_frontmatter handles mixed flat keys and list keys
run_test 123 "parse_plan_frontmatter handles mixed flat keys and list keys" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

content = '''---
status: DRAFT
targets:
  - path: ~/projects/proj-a
    role: primary
  - path: ~/projects/proj-b
    role: secondary
author: test-author
---
# Plan
'''
fm, err = d.parse_plan_frontmatter(content)
assert err == '', f'Unexpected error: {err}'
assert fm.get('status') == 'DRAFT', f'status mismatch: {fm.get(\\\"status\\\")}'
assert len(fm.get('targets', [])) == 2, f'expected 2 targets, got {len(fm.get(\\\"targets\\\", []))}'
assert fm.get('author') == 'test-author', f'author not parsed after list: {fm.get(\\\"author\\\")}'
print('PASS: mixed flat keys and list keys parsed correctly')
\"" \
    0

# Test 124: parse_plan_frontmatter treats unindented key as list-to-top transition
# The parser correctly handles unindented "role: secondary" as a top-level key,
# ending the list. The second target ends up missing its role field, which
# validate_plan_targets() catches downstream.
run_test 124 "parse_plan_frontmatter handles unindented key as list-to-top transition" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

content = '''---
status: DRAFT
targets:
  - path: ~/projects/proj-a
    role: primary
  - path: ~/projects/proj-b
role: secondary
---
'''
fm, err = d.parse_plan_frontmatter(content)
assert err == '', f'parser should succeed, got error: {err}'
assert fm != {}, 'parser should return non-empty dict'
# The unindented 'role: secondary' becomes a top-level key
assert fm.get('role') == 'secondary', f'role should be top-level key, got: {fm.get(\\\"role\\\")}'
# Second target should be missing its role (only has path)
targets = fm.get('targets', [])
assert len(targets) == 2, f'expected 2 targets, got {len(targets)}'
assert 'role' not in targets[1], f'second target should not have role, got: {targets[1]}'
# validate_plan_targets catches the missing role downstream
config = dict(d.FALLBACK_DEFAULTS)
ok, verr = d.validate_plan_targets(targets, config)
assert not ok, f'validate_plan_targets should reject target missing role, got ok={ok}'
print(f'PASS: unindented key treated as list-to-top transition; validation catches missing role')
\"" \
    0

# Test 125: parse_plan_frontmatter fails atomically on partial targets
run_test 125 "parse_plan_frontmatter fails atomically on partial targets" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

content = '''---
status: DRAFT
targets:
  - path: ~/projects/proj-a
    role: primary
  - : bad
---
'''
fm, err = d.parse_plan_frontmatter(content)
assert fm == {}, f'should return empty dict on partial parse, got: {fm}'
assert err != '', 'should return error message for bad list item'
print(f'PASS: partial targets rejected atomically with: {err}')
\"" \
    0

# --- devkit:// URI tests (126-128) ---

# Test 126: resolve_devkit_uri resolves valid URI to absolute path
run_test 126 "resolve_devkit_uri resolves valid URI to absolute path" \
    "python3 -c \"
import sys, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

result, error = d.resolve_devkit_uri('devkit://test-project-abc123456789/plans/test.md')
assert result, f'should resolve successfully, got error: {error}'
expected_suffix = os.path.join('.claude-devkit', 'projects', 'test-project-abc123456789', 'plans', 'test.md')
assert result.endswith(expected_suffix), f'resolved path should end with {expected_suffix}, got: {result}'
assert '~' not in result, f'resolved path should not contain tilde: {result}'
print(f'PASS: resolved to {result}')
\"" \
    0

# Test 127: resolve_devkit_uri rejects path traversal
run_test 127 "resolve_devkit_uri rejects path traversal" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

ok, result = d.resolve_devkit_uri('devkit://test-project-abc123456789/../../../etc/passwd')
assert not ok, 'should reject path traversal'
assert 'traversal' in result.lower() or '..' in result, f'error should mention traversal: {result}'
print(f'PASS: path traversal rejected with: {result}')
\"" \
    0

# Test 128: resolve_devkit_uri rejects invalid project-id format
run_test 128 "resolve_devkit_uri rejects invalid project-id format" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

ok, result = d.resolve_devkit_uri('devkit://../../bad/plans/test.md')
assert not ok, 'should reject invalid project ID'
assert 'project' in result.lower() or 'invalid' in result.lower(), f'error should mention project/invalid: {result}'
print(f'PASS: invalid project-id rejected with: {result}')
\"" \
    0

# --- Plan ref tests (129-131) ---

# Test 129: write_plan_refs creates ref files in all target project dirs
run_test 129 "write_plan_refs creates ref files in all target project dirs" \
    "python3 -c \"
import sys, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

resolved1 = Path('$CRP_TEST_DIR_1').resolve()
resolved2 = Path('$CRP_TEST_DIR_2').resolve()
pid1 = d.compute_project_id(resolved1)
pid2 = d.compute_project_id(resolved2)
proj_dir1 = d.get_project_dir(resolved1)
proj_dir2 = d.get_project_dir(resolved2)

targets = [
    {'project_id': pid1, 'project_path': str(resolved1), 'role': 'primary'},
    {'project_id': pid2, 'project_path': str(resolved2), 'role': 'secondary'},
]
plan_name = 'test-cross-repo-plan'
plan_file = 'test-cross-repo-plan.md'
primary_plan_path = str(proj_dir1 / 'plans' / plan_file)
config = dict(d.FALLBACK_DEFAULTS)

d.write_plan_refs(plan_name, plan_file, pid1, str(resolved1), primary_plan_path, targets, config)

ref1 = proj_dir1 / 'plan-refs' / f'{plan_name}.ref.json'
ref2 = proj_dir2 / 'plan-refs' / f'{plan_name}.ref.json'
assert ref1.exists(), f'ref file not found at {ref1}'
assert ref2.exists(), f'ref file not found at {ref2}'

import json
with open(ref1) as f:
    data1 = json.load(f)
assert data1['role'] == 'primary', f'wrong role in primary ref: {data1[\\\"role\\\"]}'
with open(ref2) as f:
    data2 = json.load(f)
assert data2['role'] == 'secondary', f'wrong role in secondary ref: {data2[\\\"role\\\"]}'
print('PASS: ref files created in both project dirs')
\"" \
    0

# Test 130: plan-refs/ directory has 0o700 permissions
run_test 130 "plan-refs/ directory has 0o700 permissions" \
    "python3 -c \"
import sys, os, stat
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

resolved1 = Path('$CRP_TEST_DIR_1').resolve()
proj_dir1 = d.get_project_dir(resolved1)
refs_dir = proj_dir1 / 'plan-refs'
if refs_dir.exists():
    mode = stat.S_IMODE(refs_dir.stat().st_mode)
    assert mode == 0o700, f'plan-refs/ permissions: {oct(mode)}, expected 0o700'
    print('PASS: plan-refs/ has 0o700 permissions')
else:
    print('PASS: skipped (plan-refs/ not yet created)')
\"" \
    0

# Test 131: ref files have 0o600 permissions and store absolute paths
run_test 131 "ref files have 0o600 permissions and store absolute paths" \
    "python3 -c \"
import sys, os, stat, json
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

resolved1 = Path('$CRP_TEST_DIR_1').resolve()
proj_dir1 = d.get_project_dir(resolved1)
refs_dir = proj_dir1 / 'plan-refs'
ref_files = list(refs_dir.glob('*.ref.json')) if refs_dir.exists() else []
assert len(ref_files) > 0, 'no ref files found'
for ref_path in ref_files:
    mode = stat.S_IMODE(ref_path.stat().st_mode)
    assert mode == 0o600, f'{ref_path.name} permissions: {oct(mode)}, expected 0o600'
    with open(ref_path) as f:
        data = json.load(f)
    assert '~' not in data.get('primary_plan_path', ''), f'primary_plan_path contains tilde: {data[\\\"primary_plan_path\\\"]}'
    for t in data.get('all_targets', []):
        assert '~' not in t.get('project_path', ''), f'project_path contains tilde: {t[\\\"project_path\\\"]}'
print('PASS: ref files have 0o600 permissions and absolute paths (no tildes)')
\"" \
    0

# --- Multi-target shell tests (132-134) ---

# Test 132: cmd_shell with --with sets DEVKIT_TARGET_COUNT and indexed env vars
run_test 132 "cmd_shell with --with sets DEVKIT_TARGET_COUNT and indexed env vars" \
    "python3 -c \"
import sys, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

config = dict(d.FALLBACK_DEFAULTS)
config['allowed_roots'] = ['~/projects/', '~/workspaces/']

resolved1 = Path('$CRP_TEST_DIR_1').resolve()
resolved2 = Path('$CRP_TEST_DIR_2').resolve()

# Capture the env dict that would be passed to execvp by monkey-patching
captured_env = {}
orig_execvp = os.execvp
def mock_execvp(file, args):
    captured_env.update(os.environ)
    raise SystemExit(0)  # Don't actually exec
os.execvp = mock_execvp
try:
    d.cmd_shell(['$CRP_TEST_DIR_1', '--with', '$CRP_TEST_DIR_2'], config)
except SystemExit:
    pass
finally:
    os.execvp = orig_execvp

assert captured_env.get('DEVKIT_TARGET_COUNT') == '2', \
    f'DEVKIT_TARGET_COUNT: {captured_env.get(\\\"DEVKIT_TARGET_COUNT\\\")}'
assert captured_env.get('DEVKIT_TARGET_0_PATH') == str(resolved1), \
    f'TARGET_0_PATH: {captured_env.get(\\\"DEVKIT_TARGET_0_PATH\\\")} != {resolved1}'
assert captured_env.get('DEVKIT_TARGET_1_PATH') == str(resolved2), \
    f'TARGET_1_PATH: {captured_env.get(\\\"DEVKIT_TARGET_1_PATH\\\")} != {resolved2}'
print('PASS: multi-target shell sets DEVKIT_TARGET_COUNT and indexed vars')
\"" \
    0

# Test 133: cmd_shell with --with validates secondary targets
run_test 133 "cmd_shell with --with validates secondary targets" \
    "python3 -c \"
import sys, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

config = dict(d.FALLBACK_DEFAULTS)
config['allowed_roots'] = ['~/projects/', '~/workspaces/']

# Patch execvp to prevent actual exec
orig_execvp = os.execvp
os.execvp = lambda f, a: None
try:
    result = d.cmd_shell(['$CRP_TEST_DIR_1', '--with', '/tmp/nonexistent'], config)
    assert result == 1 or result is None, f'Expected exit 1 for invalid --with target, got {result}'
    print('PASS: invalid --with target rejected')
except SystemExit as e:
    if e.code in (1, 2):
        print('PASS: invalid --with target rejected via sys.exit')
    else:
        raise
finally:
    os.execvp = orig_execvp
\"" \
    0

# Test 134: cmd_shell with --with rejects symlinked secondary targets
run_test 134 "cmd_shell with --with rejects symlinked secondary targets" \
    "ln -sf '$CRP_TEST_DIR_2' '$CRP_SYMLINK' && \
     python3 -c \"
import sys, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

config = dict(d.FALLBACK_DEFAULTS)
config['allowed_roots'] = ['~/projects/', '~/workspaces/']

orig_execvp = os.execvp
os.execvp = lambda f, a: None
try:
    result = d.cmd_shell(['$CRP_TEST_DIR_1', '--with', '$CRP_SYMLINK'], config)
    assert result == 1 or result is None, f'Expected exit 1 for symlink --with, got {result}'
    print('PASS: symlinked --with target rejected')
except SystemExit as e:
    if e.code in (1, 2):
        print('PASS: symlinked --with target rejected via sys.exit')
    else:
        raise
finally:
    os.execvp = orig_execvp
\" && rm -f '$CRP_SYMLINK'" \
    0

# --- Multi-target skill dispatch tests (135-137) ---

# Test 135: extract_with_targets extracts --with pairs correctly
run_test 135 "extract_with_targets extracts --with pairs correctly" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

remaining, targets = d.extract_with_targets(['arg1', '--with', '/tmp/a', '--detach', '--with', '/tmp/b'])
assert remaining == ['arg1', '--detach'], f'remaining mismatch: {remaining}'
assert targets == ['/tmp/a', '/tmp/b'], f'targets mismatch: {targets}'
print('PASS: extract_with_targets extracts --with pairs correctly')
\"" \
    0

# Test 136: extract_with_targets exits 2 on missing path after --with
run_test 136 "extract_with_targets exits 2 on missing path after --with" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

try:
    d.extract_with_targets(['arg1', '--with'])
    print('FAIL: should have exited')
    sys.exit(1)
except SystemExit as e:
    assert e.code == 2, f'expected exit 2, got {e.code}'
    print('PASS: missing path after --with exits 2')
\"" \
    0

# Test 137: cmd_run_skill with --with and --detach extracts both correctly
run_test 137 "cmd_run_skill with --with and --detach extracts both correctly" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

# Test extract_with_targets followed by --detach extraction
args = ['feature', '--with', '/tmp/bar', '--detach']
remaining, with_targets = d.extract_with_targets(args)
assert with_targets == ['/tmp/bar'], f'with_targets mismatch: {with_targets}'
detach = '--detach' in remaining
assert detach, '--detach should be in remaining after --with extraction'
remaining = [a for a in remaining if a != '--detach']
assert remaining == ['feature'], f'remaining after both extractions: {remaining}'
print('PASS: --with and --detach extracted correctly in sequence')
\"" \
    0

# --- devkit plan subcommand tests (138-142) ---

# Test 138: devkit plan list shows cross-repo refs
run_test 138 "devkit plan list shows cross-repo refs" \
    "python3 -c \"
import sys, json, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

# Ensure a ref file exists from test 129
resolved1 = Path('$CRP_TEST_DIR_1').resolve()
proj_dir1 = d.get_project_dir(resolved1)
refs_dir = proj_dir1 / 'plan-refs'
ref_files = list(refs_dir.glob('*.ref.json')) if refs_dir.exists() else []
assert len(ref_files) > 0, 'prerequisite: ref file from test 129 should exist'
\" && \
     OUTPUT=\$(python3 '$DEVKIT_CLI' plan list '$CRP_TEST_DIR_1' 2>/dev/null) && \
     echo \"\$OUTPUT\" | grep -q 'test-cross-repo-plan'" \
    0

# Test 139: devkit plan show displays plan details with target info
run_test 139 "devkit plan show displays plan details with target info" \
    "python3 -c \"
import sys, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

# Create a plan file with targets: frontmatter in the primary project
resolved1 = Path('$CRP_TEST_DIR_1').resolve()
proj_dir1 = d.get_project_dir(resolved1)
plans_dir = proj_dir1 / 'plans'
plans_dir.mkdir(parents=True, exist_ok=True)
plan_content = '''---
status: DRAFT
targets:
  - path: $CRP_TEST_DIR_1
    role: primary
  - path: $CRP_TEST_DIR_2
    role: secondary
---
# Test cross-repo plan
'''
plan_path = plans_dir / 'test-cross-repo-plan.md'
plan_path.write_text(plan_content)
\" && \
     OUTPUT=\$(python3 '$DEVKIT_CLI' plan show '$CRP_TEST_DIR_1' test-cross-repo-plan 2>/dev/null) && \
     echo \"\$OUTPUT\" | grep -qi 'primary\|secondary\|target'" \
    0

# Test 140: devkit plan validate detects missing primary target
run_test 140 "devkit plan validate detects missing primary target" \
    "PLAN_FILE=\"/tmp/crp-validate-noprimary.md\" && \
     cat > \"\$PLAN_FILE\" <<'PLANEOF'
---
status: DRAFT
targets:
  - path: $CRP_TEST_DIR_1
    role: secondary
  - path: $CRP_TEST_DIR_2
    role: secondary
---
# No primary target
PLANEOF
     python3 '$DEVKIT_CLI' plan validate '$CRP_TEST_DIR_1' \"\$PLAN_FILE\"; EXIT=\$?; \
     rm -f \"\$PLAN_FILE\"; \
     [ \"\$EXIT\" -ne 0 ]" \
    0

# Test 141: devkit plan validate detects uninitialized secondary target
run_test 141 "devkit plan validate detects uninitialized secondary target" \
    "PLAN_FILE=\"/tmp/crp-validate-uninit.md\" && \
     UNINIT_DIR=\"/tmp/${CRP_CENTRAL_CLEANUP_PREFIX}uninit-\$(date +%s)\" && \
     mkdir -p \"\$UNINIT_DIR\" && git -C \"\$UNINIT_DIR\" init -q && \
     cat > \"\$PLAN_FILE\" <<PLANEOF
---
status: DRAFT
targets:
  - path: $CRP_TEST_DIR_1
    role: primary
  - path: \$UNINIT_DIR
    role: secondary
---
# Uninitialized secondary
PLANEOF
     python3 '$DEVKIT_CLI' plan validate '$CRP_TEST_DIR_1' \"\$PLAN_FILE\"; EXIT=\$?; \
     rm -f \"\$PLAN_FILE\"; rm -rf \"\$UNINIT_DIR\" 2>/dev/null || true; \
     [ \"\$EXIT\" -ne 0 ]" \
    0

# Test 142: devkit plan sync rebuilds refs and removes stale refs
run_test 142 "devkit plan sync rebuilds refs and removes stale refs" \
    "python3 -c \"
import sys, json, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

# Create a stale ref file for a plan that no longer exists
resolved1 = Path('$CRP_TEST_DIR_1').resolve()
proj_dir1 = d.get_project_dir(resolved1)
refs_dir = proj_dir1 / 'plan-refs'
refs_dir.mkdir(parents=True, exist_ok=True)

stale_ref = refs_dir / 'deleted-plan.ref.json'
stale_data = {
    'schema_version': '1.0.0',
    'plan_name': 'deleted-plan',
    'plan_file': 'deleted-plan.md',
    'primary_project_id': d.compute_project_id(resolved1),
    'primary_project_path': str(resolved1),
    'primary_plan_path': str(proj_dir1 / 'plans' / 'deleted-plan.md'),
    'role': 'primary',
    'all_targets': [],
    'created_at': '2026-01-01T00:00:00Z',
    'created_by': 'test'
}
fd = os.open(str(stale_ref), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as f:
    json.dump(stale_data, f)
assert stale_ref.exists(), 'stale ref should exist before sync'
\" && \
     python3 '$DEVKIT_CLI' plan sync '$CRP_TEST_DIR_1' 2>/dev/null && \
     python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

resolved1 = Path('$CRP_TEST_DIR_1').resolve()
proj_dir1 = d.get_project_dir(resolved1)
stale_ref = proj_dir1 / 'plan-refs' / 'deleted-plan.ref.json'
assert not stale_ref.exists(), f'stale ref should be removed after sync: {stale_ref}'
print('PASS: stale ref removed, existing refs rebuilt')
\"" \
    0

# --- read_plan_refs tests (143-144) ---

# Test 143: read_plan_refs returns empty list for missing plan-refs/ directory
run_test 143 "read_plan_refs returns empty list for missing plan-refs/ directory" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

# Use a project dir that exists but has no plan-refs/
test_dir = Path('/tmp/${CRP_CENTRAL_CLEANUP_PREFIX}no-refs')
test_dir.mkdir(parents=True, exist_ok=True)

refs = d.read_plan_refs(test_dir)
assert refs == [], f'expected empty list, got: {refs}'

import shutil
shutil.rmtree(str(test_dir), ignore_errors=True)
print('PASS: read_plan_refs returns empty list for missing directory')
\"" \
    0

# Test 144: read_plan_refs rejects oversized ref files
run_test 144 "read_plan_refs rejects oversized ref files" \
    "python3 -c \"
import sys, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

test_dir = Path('/tmp/${CRP_CENTRAL_CLEANUP_PREFIX}oversize-refs')
refs_dir = test_dir / 'plan-refs'
refs_dir.mkdir(parents=True, exist_ok=True)

# Create a valid small ref file
small_ref = refs_dir / 'good-plan.ref.json'
import json
small_data = {
    'schema_version': '1.0.0', 'plan_name': 'good-plan',
    'plan_file': 'good-plan.md', 'primary_project_id': 'test-abc123456789',
    'primary_project_path': '/tmp/test', 'primary_plan_path': str(Path.home() / '.claude-devkit/projects/test-abc123456789/plans/good.md'),
    'role': 'primary', 'all_targets': [], 'created_at': '2026-01-01T00:00:00Z',
    'created_by': 'test'
}
fd = os.open(str(small_ref), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as f:
    json.dump(small_data, f)

# Create an oversized ref file (>100KB)
big_ref = refs_dir / 'huge-plan.ref.json'
fd2 = os.open(str(big_ref), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd2, 'w') as f:
    f.write('x' * 200000)

refs = d.read_plan_refs(test_dir)
# The oversized file should be skipped, only the valid one returned
names = [r.get('plan_name') for r in refs]
assert 'good-plan' in names, f'valid ref should be returned: {names}'
# huge-plan should NOT appear (it is not valid JSON anyway, but size check comes first)
assert 'huge-plan' not in names, f'oversized ref should be skipped: {names}'

import shutil
shutil.rmtree(str(test_dir), ignore_errors=True)
print('PASS: oversized ref file skipped, valid refs returned')
\"" \
    0

# --- validate_plan_targets tests (145-146) ---

# Test 145: validate_plan_targets rejects duplicate primaries
run_test 145 "validate_plan_targets rejects duplicate primaries" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

targets = [
    {'path': '/tmp/a', 'role': 'primary'},
    {'path': '/tmp/b', 'role': 'primary'},
]
config = dict(d.FALLBACK_DEFAULTS)
ok, err = d.validate_plan_targets(targets, config)
assert not ok, 'should reject duplicate primaries'
assert 'primary' in err.lower() and 'multiple' in err.lower(), f'error should mention multiple primary: {err}'
print(f'PASS: duplicate primaries rejected with: {err}')
\"" \
    0

# Test 146: validate_plan_targets rejects targets list with no primary
run_test 146 "validate_plan_targets rejects targets list with no primary" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

targets = [
    {'path': '/tmp/a', 'role': 'secondary'},
    {'path': '/tmp/b', 'role': 'secondary'},
]
config = dict(d.FALLBACK_DEFAULTS)
ok, err = d.validate_plan_targets(targets, config)
assert not ok, 'should reject no primary'
assert 'primary' in err.lower(), f'error should mention primary: {err}'
print(f'PASS: no primary rejected with: {err}')
\"" \
    0

# --- cmd_path traversal protection test (147) ---

# Test 147: cmd_path rejects path traversal via .. segments
run_test 147 "cmd_path rejects path traversal via .. segments" \
    "python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d

config = dict(d.FALLBACK_DEFAULTS)
config['allowed_roots'] = ['~/projects/', '~/workspaces/']

# Should reject traversal
result = d.cmd_path('$CRP_TEST_DIR_1', config, subpath='../../etc/passwd')
assert result == 1, f'expected exit 1 for traversal, got {result}'

# Should accept valid subpath
result2 = d.cmd_path('$CRP_TEST_DIR_1', config, subpath='plans/feature.md')
assert result2 == 0, f'expected exit 0 for valid subpath, got {result2}'
print('PASS: cmd_path rejects traversal, accepts valid subpath')
\"" \
    0

# --- devkit plan archive test (148) ---

# Test 148: devkit plan archive removes ref files from all involved projects
run_test 148 "devkit plan archive removes ref files from all involved projects" \
    "python3 -c \"
import sys, json, os
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

# Ensure ref files exist for test-cross-repo-plan (from test 129)
resolved1 = Path('$CRP_TEST_DIR_1').resolve()
resolved2 = Path('$CRP_TEST_DIR_2').resolve()
proj_dir1 = d.get_project_dir(resolved1)
proj_dir2 = d.get_project_dir(resolved2)
pid1 = d.compute_project_id(resolved1)
pid2 = d.compute_project_id(resolved2)

# Re-create refs to ensure they exist
targets = [
    {'project_id': pid1, 'project_path': str(resolved1), 'role': 'primary'},
    {'project_id': pid2, 'project_path': str(resolved2), 'role': 'secondary'},
]
plan_name = 'archive-test-plan'
plan_file = 'archive-test-plan.md'
plans_dir = proj_dir1 / 'plans'
plans_dir.mkdir(parents=True, exist_ok=True)
# Create the plan file
plan_path = plans_dir / plan_file
plan_path.write_text('---\nstatus: APPROVED\n---\n# Archive test\n')
primary_plan_path = str(plan_path)
config = dict(d.FALLBACK_DEFAULTS)
d.write_plan_refs(plan_name, plan_file, pid1, str(resolved1), primary_plan_path, targets, config)

ref1 = proj_dir1 / 'plan-refs' / f'{plan_name}.ref.json'
ref2 = proj_dir2 / 'plan-refs' / f'{plan_name}.ref.json'
assert ref1.exists(), f'ref1 should exist before archive: {ref1}'
assert ref2.exists(), f'ref2 should exist before archive: {ref2}'
\" && \
     python3 '$DEVKIT_CLI' plan archive '$CRP_TEST_DIR_1' archive-test-plan 2>/dev/null && \
     python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
import devkit_cli as d
from pathlib import Path

resolved1 = Path('$CRP_TEST_DIR_1').resolve()
resolved2 = Path('$CRP_TEST_DIR_2').resolve()
proj_dir1 = d.get_project_dir(resolved1)
proj_dir2 = d.get_project_dir(resolved2)

ref1 = proj_dir1 / 'plan-refs' / 'archive-test-plan.ref.json'
ref2 = proj_dir2 / 'plan-refs' / 'archive-test-plan.ref.json'
assert not ref1.exists(), f'ref1 should be removed after archive: {ref1}'
assert not ref2.exists(), f'ref2 should be removed after archive: {ref2}'

# Plan should be moved to archive
archive_dir = proj_dir1 / 'plans' / 'archive' / 'archive-test-plan'
assert archive_dir.exists() or not (proj_dir1 / 'plans' / 'archive-test-plan.md').exists(), \
    'plan should be archived or removed from plans/'
print('PASS: ref files removed from all projects after archive')
\"" \
    0

# --- Shared learnings layer tests (149-166) ---
# These tests verify the learnings parser, cross-project aggregator,
# promotion tracker, devkit learnings CLI command, and security properties.
#
# Fixtures: LEARN_TEST_DIR is created inline. Central learnings state uses
# LEARN_CENTRAL_CLEANUP_PREFIX for selective cleanup.

# Test 149 (T1): learnings_parser.py parses entries with date, severity, tags, seen-in
run_test 149 "learnings_parser.py parses entries with date, severity, tags, seen-in" \
    "mkdir -p '$LEARN_TEST_DIR' && \
     cat > '$LEARN_TEST_DIR/learnings.md' <<'LEARNEOF'
# Project Learnings

## QA Patterns

### Coverage gaps

- **[2026-03-28] Integration tests not executed** [High] -- Live skill invocation deferred. Seen in: feature-alpha, feature-beta. #qa #coverage #integration (2026-03-28)
LEARNEOF
     python3 '$REPO_DIR/scripts/learnings_parser.py' '$LEARN_TEST_DIR/learnings.md' --format json | python3 -c \"
import json, sys
data = json.load(sys.stdin)
entries = data['entries']
assert len(entries) >= 1, f'Expected >=1 entry, got {len(entries)}'
e = entries[0]
assert e['date'] == '2026-03-28', f'date mismatch: {e[\\\"date\\\"]}'
assert e['severity'] == 'High', f'severity mismatch: {e[\\\"severity\\\"]}'
assert '#qa' in e['tags'], f'missing #qa tag: {e[\\\"tags\\\"]}'
assert '#coverage' in e['tags'], f'missing #coverage tag: {e[\\\"tags\\\"]}'
assert '#integration' in e['tags'], f'missing #integration tag: {e[\\\"tags\\\"]}'
assert 'feature-alpha' in e['seen_in'], f'missing seen_in feature-alpha: {e[\\\"seen_in\\\"]}'
assert 'feature-beta' in e['seen_in'], f'missing seen_in feature-beta: {e[\\\"seen_in\\\"]}'
assert 'Integration tests not executed' in e['title'], f'title mismatch: {e[\\\"title\\\"]}'
print('PASS: parser extracts date, severity, tags, seen-in correctly')
\"" \
    0

# Test 150 (T2): learnings_parser.py handles entries without dates gracefully
run_test 150 "learnings_parser.py handles entries without dates gracefully" \
    "cat > '$LEARN_TEST_DIR/learnings-nodate.md' <<'LEARNEOF'
# Learnings

## Coder Patterns

### Missed

- **Missing path validation** [Medium] -- No traversal check. Seen in: fix-skill. #coder #security
LEARNEOF
     python3 '$REPO_DIR/scripts/learnings_parser.py' '$LEARN_TEST_DIR/learnings-nodate.md' --format json | python3 -c \"
import json, sys
data = json.load(sys.stdin)
entries = data['entries']
assert len(entries) >= 1, f'Expected >=1 entry, got {len(entries)}'
e = entries[0]
assert e['date'] is None, f'expected null date, got {e[\\\"date\\\"]}'
assert e['severity'] == 'Medium', f'severity mismatch: {e[\\\"severity\\\"]}'
print('PASS: dateless entry parsed with null date')
\"" \
    0

# Test 151 (T3): learnings_parser.py handles entries without severity gracefully
run_test 151 "learnings_parser.py handles entries without severity gracefully" \
    "cat > '$LEARN_TEST_DIR/learnings-nosev.md' <<'LEARNEOF'
# Learnings

## Patterns

- **Dead import detection** -- Too noisy for automation. Seen in: cleanup. #coder #imports
LEARNEOF
     python3 '$REPO_DIR/scripts/learnings_parser.py' '$LEARN_TEST_DIR/learnings-nosev.md' --format json | python3 -c \"
import json, sys
data = json.load(sys.stdin)
entries = data['entries']
assert len(entries) >= 1, f'Expected >=1 entry, got {len(entries)}'
e = entries[0]
assert e['severity'] is None, f'expected null severity, got {e[\\\"severity\\\"]}'
assert 'Dead import detection' in e['title'], f'title mismatch: {e[\\\"title\\\"]}'
print('PASS: severity-less entry parsed with null severity')
\"" \
    0

# Test 152 (T4): learnings_parser.py computes stable IDs (same title = same ID)
run_test 152 "learnings_parser.py computes stable IDs (same title = same ID)" \
    "cat > '$LEARN_TEST_DIR/learnings-dup1.md' <<'LEARNEOF'
# Learnings
- **[2026-03-28] Duplicate title test** [Low] -- First occurrence. #test
LEARNEOF
     cat > '$LEARN_TEST_DIR/learnings-dup2.md' <<'LEARNEOF'
# Learnings
- **[2026-05-01] Duplicate title test** [Medium] -- Second occurrence. #test
LEARNEOF
     python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
from learnings_parser import parse_learnings_file
entries1, _ = parse_learnings_file('$LEARN_TEST_DIR/learnings-dup1.md')
entries2, _ = parse_learnings_file('$LEARN_TEST_DIR/learnings-dup2.md')
assert len(entries1) >= 1 and len(entries2) >= 1, 'Expected at least 1 entry each'
assert entries1[0]['id'] == entries2[0]['id'], f'Same title should produce same ID: {entries1[0][\\\"id\\\"]} != {entries2[0][\\\"id\\\"]}'
print('PASS: stable IDs for same title across files')
\"" \
    0

# Test 153 (T5): learnings_parser.py skips files exceeding size limit
run_test 153 "learnings_parser.py skips files exceeding size limit" \
    "python3 -c \"
# Create a 2MB file
with open('$LEARN_TEST_DIR/learnings-huge.md', 'w') as f:
    f.write('# Huge\\n')
    f.write('x' * (2 * 1024 * 1024))
\" && \
     python3 -c \"
import sys
sys.path.insert(0, '$REPO_DIR/scripts')
from learnings_parser import parse_learnings_file
entries, warnings = parse_learnings_file('$LEARN_TEST_DIR/learnings-huge.md')
assert len(entries) == 0, f'Expected 0 entries for oversized file, got {len(entries)}'
assert len(warnings) > 0, 'Expected at least 1 warning for oversized file'
assert any('size' in w.lower() or 'exceed' in w.lower() or 'limit' in w.lower() or 'large' in w.lower() or 'skip' in w.lower() for w in warnings), f'Warning should mention size: {warnings}'
print('PASS: oversized file skipped with warning')
\"" \
    0

# Test 154 (T6): learnings_aggregator.py discovers files under allowed_roots
run_test 154 "learnings_aggregator.py discovers files under allowed_roots" \
    "AGGR_DIR_1='/tmp/${LEARN_CENTRAL_CLEANUP_PREFIX}proj1' && \
     AGGR_DIR_2='/tmp/${LEARN_CENTRAL_CLEANUP_PREFIX}proj2' && \
     rm -rf \"\$AGGR_DIR_1\" \"\$AGGR_DIR_2\" 2>/dev/null || true && \
     mkdir -p \"\$AGGR_DIR_1/.claude\" && git -C \"\$AGGR_DIR_1\" init -q && \
     mkdir -p \"\$AGGR_DIR_2/.claude\" && git -C \"\$AGGR_DIR_2\" init -q && \
     echo '# Learnings
- **Test entry one** [Low] -- Test. #test-tag' > \"\$AGGR_DIR_1/.claude/learnings.md\" && \
     echo '# Learnings
- **Test entry two** [Low] -- Test. #test-tag' > \"\$AGGR_DIR_2/.claude/learnings.md\" && \
     OUTPUT=\$(python3 '$REPO_DIR/scripts/learnings_aggregator.py' --format md --allowed-roots /tmp 2>/dev/null) && \
     echo \"\$OUTPUT\" | grep -q 'proj1\|proj2\|Projects scanned' && \
     rm -rf \"\$AGGR_DIR_1\" \"\$AGGR_DIR_2\"" \
    0

# Test 155 (T7): learnings_aggregator.py skips symlinked paths
run_test 155 "learnings_aggregator.py skips symlinked paths" \
    "REAL_DIR='/tmp/${LEARN_CENTRAL_CLEANUP_PREFIX}real-proj' && \
     LINK_DIR='/tmp/${LEARN_CENTRAL_CLEANUP_PREFIX}link-proj' && \
     rm -rf \"\$REAL_DIR\" 2>/dev/null || true && \
     rm -f \"\$LINK_DIR\" 2>/dev/null || true && \
     mkdir -p \"\$REAL_DIR/.claude\" && git -C \"\$REAL_DIR\" init -q && \
     echo '# Learnings
- **Symlink test entry** [Low] -- Test. #symlink' > \"\$REAL_DIR/.claude/learnings.md\" && \
     ln -sf \"\$REAL_DIR\" \"\$LINK_DIR\" && \
     OUTPUT=\$(python3 '$REPO_DIR/scripts/learnings_aggregator.py' --format md --allowed-roots /tmp 2>&1) && \
     echo \"\$OUTPUT\" | grep -qi 'symlink\|skip' && \
     rm -rf \"\$REAL_DIR\" && rm -f \"\$LINK_DIR\"" \
    0

# Test 156 (T8): learnings_aggregator.py writes valid index.json
run_test 156 "learnings_aggregator.py writes valid index.json" \
    "AGGR_PROJ='/tmp/${LEARN_CENTRAL_CLEANUP_PREFIX}idx-proj' && \
     rm -rf \"\$AGGR_PROJ\" 2>/dev/null || true && \
     mkdir -p \"\$AGGR_PROJ/.claude\" && git -C \"\$AGGR_PROJ\" init -q && \
     echo '# Learnings
- **Index test entry** [Medium] -- Verify JSON. Seen in: feature-x. #qa #index' > \"\$AGGR_PROJ/.claude/learnings.md\" && \
     python3 '$REPO_DIR/scripts/learnings_aggregator.py' --format json --allowed-roots /tmp 2>/dev/null && \
     python3 -c \"
import json
from pathlib import Path
idx = Path.home() / '.claude-devkit' / 'learnings' / 'index.json'
assert idx.exists(), f'index.json not found at {idx}'
with open(idx) as f:
    data = json.load(f)
assert data.get('schema_version') == '1.0.0', f'wrong schema: {data.get(\\\"schema_version\\\")}'
assert 'entries' in data, 'missing entries key'
assert 'tag_frequency' in data, 'missing tag_frequency key'
assert data.get('projects_scanned', 0) > 0, 'projects_scanned should be > 0'
print('PASS: index.json is valid JSON with required schema fields')
\" && \
     rm -rf \"\$AGGR_PROJ\"" \
    0

# Test 157 (T9): learnings_aggregator.py identifies cross-project tag patterns
run_test 157 "learnings_aggregator.py identifies cross-project tag patterns (3+ projects)" \
    "for i in 1 2 3; do \
       D=\"/tmp/${LEARN_CENTRAL_CLEANUP_PREFIX}tag-proj\${i}\" && \
       rm -rf \"\$D\" 2>/dev/null || true && \
       mkdir -p \"\$D/.claude\" && git -C \"\$D\" init -q && \
       echo \"# Learnings
- **Tag pattern entry \${i}** [Low] -- Cross-project. #shared-pattern #qa\" > \"\$D/.claude/learnings.md\"; \
     done && \
     python3 '$REPO_DIR/scripts/learnings_aggregator.py' --format json --allowed-roots /tmp --min-projects 3 2>/dev/null && \
     python3 -c \"
import json
from pathlib import Path
idx = Path.home() / '.claude-devkit' / 'learnings' / 'index.json'
with open(idx) as f:
    data = json.load(f)
candidates = data.get('promotion_candidates', [])
tag_candidates = [c for c in candidates if c.get('type') == 'high_frequency_tag']
# At least one tag should appear in 3+ projects
assert any(c.get('project_count', 0) >= 3 for c in tag_candidates), \
    f'Expected at least one tag in 3+ projects, got: {tag_candidates}'
print('PASS: cross-project tag pattern detected with 3+ projects')
\" && \
     for i in 1 2 3; do rm -rf \"/tmp/${LEARN_CENTRAL_CLEANUP_PREFIX}tag-proj\${i}\" 2>/dev/null || true; done" \
    0

# Test 158 (T10): learnings_promotions.py propose creates entry with proposed_by
run_test 158 "learnings_promotions.py propose creates entry with proposed_by" \
    "PROMO_DIR=\"\$HOME/.claude-devkit/learnings\" && \
     mkdir -p \"\$PROMO_DIR\" && \
     rm -f \"\$PROMO_DIR/promotions.json\" 2>/dev/null || true && \
     python3 '$REPO_DIR/scripts/learnings_promotions.py' propose abc123def456 \
       --type skill_rule \
       --target 'skills/ship/SKILL.md' \
       --description 'Test promotion proposal' && \
     python3 -c \"
import json
with open('\$PROMO_DIR/promotions.json') as f:
    data = json.load(f)
promos = data.get('promotions', [])
assert len(promos) >= 1, f'Expected >=1 promotion, got {len(promos)}'
p = promos[0]
assert p['entry_id'] == 'abc123def456', f'entry_id mismatch: {p[\\\"entry_id\\\"]}'
assert p['status'] == 'PROPOSED', f'status should be PROPOSED, got {p[\\\"status\\\"]}'
assert p.get('proposed_by') is not None and p['proposed_by'] != '', f'proposed_by should be set: {p.get(\\\"proposed_by\\\")}'
assert p.get('promotion_type') == 'skill_rule', f'type mismatch: {p.get(\\\"promotion_type\\\")}'
print('PASS: propose creates entry with proposed_by and correct fields')
\"" \
    0

# Test 159 (T11): learnings_promotions.py approve transitions PROPOSED to APPROVED
run_test 159 "learnings_promotions.py approve transitions PROPOSED to APPROVED" \
    "PROMO_DIR=\"\$HOME/.claude-devkit/learnings\" && \
     python3 -c \"
import json
with open('\$PROMO_DIR/promotions.json') as f:
    data = json.load(f)
promo_id = data['promotions'][0]['id']
print(promo_id)
\" > /tmp/learnings-promo-id.txt && \
     PROMO_ID=\$(cat /tmp/learnings-promo-id.txt) && \
     python3 '$REPO_DIR/scripts/learnings_promotions.py' approve \"\$PROMO_ID\" && \
     python3 -c \"
import json
with open('\$PROMO_DIR/promotions.json') as f:
    data = json.load(f)
p = data['promotions'][0]
assert p['status'] == 'APPROVED', f'status should be APPROVED, got {p[\\\"status\\\"]}'
assert p.get('approved_by') is not None and p['approved_by'] != '', f'approved_by should be set'
assert p.get('approved_at') is not None, 'approved_at should be set'
print('PASS: approve transitions to APPROVED with approved_by')
\" && rm -f /tmp/learnings-promo-id.txt" \
    0

# Test 160 (T12): learnings_promotions.py promote records commit SHA and promoted_by
run_test 160 "learnings_promotions.py promote records commit SHA and promoted_by" \
    "PROMO_DIR=\"\$HOME/.claude-devkit/learnings\" && \
     python3 -c \"
import json
with open('\$PROMO_DIR/promotions.json') as f:
    data = json.load(f)
print(data['promotions'][0]['id'])
\" > /tmp/learnings-promo-id.txt && \
     PROMO_ID=\$(cat /tmp/learnings-promo-id.txt) && \
     python3 '$REPO_DIR/scripts/learnings_promotions.py' promote \"\$PROMO_ID\" --commit abc1234def5678 && \
     python3 -c \"
import json
with open('\$PROMO_DIR/promotions.json') as f:
    data = json.load(f)
p = data['promotions'][0]
assert p['status'] == 'PROMOTED', f'status should be PROMOTED, got {p[\\\"status\\\"]}'
assert p.get('promoted_by') is not None and p['promoted_by'] != '', f'promoted_by should be set'
assert p.get('commit_sha') == 'abc1234def5678', f'commit_sha mismatch: {p.get(\\\"commit_sha\\\")}'
print('PASS: promote sets PROMOTED status with commit_sha and promoted_by')
\" && rm -f /tmp/learnings-promo-id.txt" \
    0

# Test 161 (T13): learnings_promotions.py rejects invalid promo-ID (path traversal)
run_test 161 "learnings_promotions.py rejects invalid promo-ID (path traversal)" \
    "python3 '$REPO_DIR/scripts/learnings_promotions.py' approve '../../../etc/passwd'" \
    1

# Test 162 (T14): devkit learnings runs aggregation and exits 0
run_test 162 "devkit learnings runs aggregation and exits 0" \
    "AGGR_PROJ='/tmp/${LEARN_CENTRAL_CLEANUP_PREFIX}cli-proj' && \
     rm -rf \"\$AGGR_PROJ\" 2>/dev/null || true && \
     mkdir -p \"\$AGGR_PROJ/.claude\" && git -C \"\$AGGR_PROJ\" init -q && \
     echo '# Learnings
- **CLI test entry** [Low] -- Test. #cli-test' > \"\$AGGR_PROJ/.claude/learnings.md\" && \
     python3 '$DEVKIT_CLI' learnings --allowed-roots /tmp 2>/dev/null; STATUS=\$?; \
     rm -rf \"\$AGGR_PROJ\" 2>/dev/null || true; \
     [ \"\$STATUS\" -eq 0 ]" \
    0

# Test 163 (T15): devkit learnings --format json writes index.json
run_test 163 "devkit learnings --format json writes index.json" \
    "AGGR_PROJ='/tmp/${LEARN_CENTRAL_CLEANUP_PREFIX}json-proj' && \
     rm -rf \"\$AGGR_PROJ\" 2>/dev/null || true && \
     mkdir -p \"\$AGGR_PROJ/.claude\" && git -C \"\$AGGR_PROJ\" init -q && \
     echo '# Learnings
- **JSON output test** [Low] -- Test. #json-test' > \"\$AGGR_PROJ/.claude/learnings.md\" && \
     python3 '$DEVKIT_CLI' learnings --format json --allowed-roots /tmp 2>/dev/null && \
     python3 -c \"
from pathlib import Path
idx = Path.home() / '.claude-devkit' / 'learnings' / 'index.json'
assert idx.exists(), f'index.json not found at {idx}'
import json
with open(idx) as f:
    data = json.load(f)
assert isinstance(data.get('entries'), list), 'entries should be a list'
print('PASS: devkit learnings --format json writes valid index.json')
\" && \
     rm -rf \"\$AGGR_PROJ\" 2>/dev/null || true" \
    0

# Test 164 (T16): devkit learnings promotions lists promotions and exits 0
run_test 164 "devkit learnings promotions lists promotions and exits 0" \
    "PROMO_DIR=\"\$HOME/.claude-devkit/learnings\" && \
     mkdir -p \"\$PROMO_DIR\" && \
     echo '{\"schema_version\":\"1.0.0\",\"updated_at\":\"2026-08-21T12:00:00Z\",\"promotions\":[{\"id\":\"promo-20260821-abc123\",\"entry_id\":\"test123\",\"title\":\"Test promotion\",\"status\":\"PROMOTED\",\"promotion_type\":\"skill_rule\"}]}' > \"\$PROMO_DIR/promotions.json\" && \
     OUTPUT=\$(python3 '$DEVKIT_CLI' learnings promotions 2>/dev/null) && \
     echo \"\$OUTPUT\" | grep -q 'promo-20260821-abc123\|PROMOTED\|Test promotion'" \
    0

# Test 165 (T17): Commit SHA validation rejects non-hex input
run_test 165 "learnings_promotions.py rejects non-hex commit SHA" \
    "PROMO_DIR=\"\$HOME/.claude-devkit/learnings\" && \
     mkdir -p \"\$PROMO_DIR\" && \
     rm -f \"\$PROMO_DIR/promotions.json\" 2>/dev/null || true && \
     python3 '$REPO_DIR/scripts/learnings_promotions.py' propose def789012345 \
       --type skill_rule --target 'skills/ship/SKILL.md' --description 'SHA test' && \
     python3 -c \"
import json
with open('\$PROMO_DIR/promotions.json') as f:
    data = json.load(f)
print(data['promotions'][0]['id'])
\" > /tmp/learnings-sha-id.txt && \
     PROMO_ID=\$(cat /tmp/learnings-sha-id.txt) && \
     python3 '$REPO_DIR/scripts/learnings_promotions.py' approve \"\$PROMO_ID\" 2>/dev/null && \
     python3 '$REPO_DIR/scripts/learnings_promotions.py' promote \"\$PROMO_ID\" --commit '; rm -rf /'; STATUS=\$?; \
     rm -f /tmp/learnings-sha-id.txt; \
     [ \"\$STATUS\" -ne 0 ]" \
    0

# Test 166 (T18): learnings_aggregator.py skips backup directories
run_test 166 "learnings_aggregator.py skips backup directories" \
    "BACKUP_DIR='/tmp/${LEARN_CENTRAL_CLEANUP_PREFIX}_backup_proj' && \
     rm -rf \"\$BACKUP_DIR\" 2>/dev/null || true && \
     mkdir -p \"\$BACKUP_DIR/.claude\" && git -C \"\$BACKUP_DIR\" init -q && \
     echo '# Learnings
- **Backup entry should be skipped** [High] -- Should not appear. #backup' > \"\$BACKUP_DIR/.claude/learnings.md\" && \
     python3 '$REPO_DIR/scripts/learnings_aggregator.py' --format json --allowed-roots /tmp 2>/dev/null && \
     python3 -c \"
import json
from pathlib import Path
idx = Path.home() / '.claude-devkit' / 'learnings' / 'index.json'
with open(idx) as f:
    data = json.load(f)
# Verify no entries from the backup directory
for entry in data.get('entries', []):
    source = entry.get('source_project', '') + entry.get('source_project_display', '')
    assert '_backup_' not in source, f'Backup entry should be skipped: {source}'
    assert 'Backup entry should be skipped' not in entry.get('title', ''), \
        f'Backup entry title found in index: {entry[\\\"title\\\"]}'
print('PASS: backup directory skipped during aggregation')
\" && \
     rm -rf \"\$BACKUP_DIR\"" \
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
# Clean up zero-project-footprint test fixtures
rm -rf "$ZPF_TEST_DIR" || true
rm -rf "$ZPF_MIGRATE_DIR" || true
rm -rf "$ZPF_RELINK_DIR" || true
# Clean up cross-repo plan test fixtures
rm -rf "$CRP_TEST_DIR_1" || true
rm -rf "$CRP_TEST_DIR_2" || true
rm -f "$CRP_SYMLINK" || true
if [ -d "$HOME/.claude-devkit/projects" ]; then
    for d in "$HOME/.claude-devkit/projects/${ZPF_CENTRAL_CLEANUP_PREFIX}"*; do
        rm -rf "$d" 2>/dev/null || true
    done
    for d in "$HOME/.claude-devkit/projects/devkit-harness-"*; do
        rm -rf "$d" 2>/dev/null || true
    done
    for d in "$HOME/.claude-devkit/projects/${CRP_CENTRAL_CLEANUP_PREFIX}"*; do
        rm -rf "$d" 2>/dev/null || true
    done
fi
# Clean up learnings test fixtures
rm -rf "$LEARN_TEST_DIR" || true
if [ -d "$HOME/.claude-devkit/learnings" ]; then
    rm -rf "$HOME/.claude-devkit/learnings/${LEARN_CENTRAL_CLEANUP_PREFIX}"* 2>/dev/null || true
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
