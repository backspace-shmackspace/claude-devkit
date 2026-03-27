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
# 5 tests: coordinator lifecycle, validate-all, pipeline lifecycle, unit meta-test, cleanup

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

    set +e
    eval "$test_command" > /dev/null 2>&1
    actual_exit=$?
    set -e

    if [[ "$expected_exit" == "0" && $actual_exit -eq 0 ]]; then
        echo -e "${GREEN}  PASS${RESET}"
        PASS_COUNT=$((PASS_COUNT + 1))
    elif [[ "$expected_exit" != "0" && $actual_exit -ne 0 ]]; then
        echo -e "${GREEN}  PASS${RESET}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}  FAIL (expected exit $expected_exit, got $actual_exit)${RESET}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
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

# Test 5: Cleanup
echo ""
echo -e "${BLUE}Test 5: Cleanup${RESET}"
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
