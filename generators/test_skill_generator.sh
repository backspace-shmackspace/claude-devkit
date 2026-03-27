#!/usr/bin/env bash
#
# Test script for skill generator
# Runs all 46 test cases from the plan
#
# Usage:
#   bash test_skill_generator.sh
#   bash -x test_skill_generator.sh  # verbose mode

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
VALIDATE_PY="$SCRIPT_DIR/validate_skill.py"
GENERATE_PY="$SCRIPT_DIR/generate_skill.py"
# Resolve claude-devkit root from script location (parent of generators/)
SKILLS_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="/tmp/sg-test"

# Clean up test directory at start
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Test runner function
run_test() {
    local test_num="$1"
    local test_name="$2"
    local test_command="$3"
    local expected_exit="$4"  # 0 or non-zero

    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    echo ""
    echo -e "${BLUE}Test $test_num: $test_name${RESET}"

    # Run command and capture exit code
    set +e
    eval "$test_command" > /dev/null 2>&1
    actual_exit=$?
    set -e

    # Check result
    if [[ "$expected_exit" == "0" && $actual_exit -eq 0 ]]; then
        echo -e "${GREEN}✅ PASS${RESET}"
        PASS_COUNT=$((PASS_COUNT + 1))
    elif [[ "$expected_exit" != "0" && $actual_exit -ne 0 ]]; then
        echo -e "${GREEN}✅ PASS${RESET}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}❌ FAIL (expected exit $expected_exit, got $actual_exit)${RESET}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Test 1: Validator help text
run_test 1 "Validator help text" \
    "python3 '$VALIDATE_PY' --help" \
    0

# Test 2: Generator help text
run_test 2 "Generator help text" \
    "python3 '$GENERATE_PY' --help" \
    0

# Test 3: Validate architect skill
if [[ -f "$SKILLS_DIR/skills/architect/SKILL.md" ]]; then
    run_test 3 "Validate architect skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/architect/SKILL.md'" \
        0
else
    echo -e "${YELLOW}⏭️  Test 3: SKIP (architect skill not found)${RESET}"
fi

# Test 4: Validate ship skill
if [[ -f "$SKILLS_DIR/skills/ship/SKILL.md" ]]; then
    run_test 4 "Validate ship skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/ship/SKILL.md'" \
        0
else
    echo -e "${YELLOW}⏭️  Test 4: SKIP (ship skill not found)${RESET}"
fi

# Test 5: Validate audit skill
if [[ -f "$SKILLS_DIR/skills/audit/SKILL.md" ]]; then
    run_test 5 "Validate audit skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/audit/SKILL.md'" \
        0
else
    echo -e "${YELLOW}⏭️  Test 5: SKIP (audit skill not found)${RESET}"
fi

# Test 6: Validate sync skill
if [[ -f "$SKILLS_DIR/skills/sync/SKILL.md" ]]; then
    run_test 6 "Validate sync skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/sync/SKILL.md'" \
        0
else
    echo -e "${YELLOW}⏭️  Test 6: SKIP (sync skill not found)${RESET}"
fi

# Test 7: Generate coordinator
run_test 7 "Generate coordinator" \
    "python3 '$GENERATE_PY' test-coord -d 'Test.' -a coordinator -t '$TEST_DIR' --force" \
    0

# Test 8: Generate pipeline
run_test 8 "Generate pipeline" \
    "python3 '$GENERATE_PY' test-pipe -d 'Test.' -a pipeline -t '$TEST_DIR' --force" \
    0

# Test 9: Generate scan
run_test 9 "Generate scan" \
    "python3 '$GENERATE_PY' test-scan -d 'Test.' -a scan -t '$TEST_DIR' --force" \
    0

# Test 10: Validate generated coordinator
if [[ -f "$TEST_DIR/skills/test-coord/SKILL.md" ]]; then
    run_test 10 "Validate generated coordinator" \
        "python3 '$VALIDATE_PY' '$TEST_DIR/skills/test-coord/SKILL.md'" \
        0
else
    echo -e "${RED}❌ Test 10: FAIL (coordinator not generated)${RESET}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
fi

# Test 11: Validate generated pipeline
if [[ -f "$TEST_DIR/skills/test-pipe/SKILL.md" ]]; then
    run_test 11 "Validate generated pipeline" \
        "python3 '$VALIDATE_PY' '$TEST_DIR/skills/test-pipe/SKILL.md'" \
        0
else
    echo -e "${RED}❌ Test 11: FAIL (pipeline not generated)${RESET}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
fi

# Test 12: Validate generated scan
if [[ -f "$TEST_DIR/skills/test-scan/SKILL.md" ]]; then
    run_test 12 "Validate generated scan" \
        "python3 '$VALIDATE_PY' '$TEST_DIR/skills/test-scan/SKILL.md'" \
        0
else
    echo -e "${RED}❌ Test 12: FAIL (scan not generated)${RESET}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
fi

# Test 13: Reject invalid name (uppercase)
run_test 13 "Reject invalid name (uppercase)" \
    "python3 '$GENERATE_PY' 'BadName' -d 'Test.' -t '$TEST_DIR'" \
    non-zero

# Test 14: Reject invalid name (reserved)
run_test 14 "Reject invalid name (reserved)" \
    "python3 '$GENERATE_PY' 'architect' -d 'Test.' -t '$TEST_DIR'" \
    non-zero

# Test 15: Reject invalid name (too long)
run_test 15 "Reject invalid name (too long)" \
    "python3 '$GENERATE_PY' 'this-name-is-way-too-long-for-a-skill-name' -d 'Test.' -t '$TEST_DIR'" \
    non-zero

# Test 16: Reject existing skill without --force
# First create a test skill
python3 "$GENERATE_PY" test-exist -d "Test." -t "$TEST_DIR" --force > /dev/null 2>&1
run_test 16 "Reject existing skill without --force" \
    "echo 'n' | python3 '$GENERATE_PY' test-exist -d 'Test.' -t '$TEST_DIR'" \
    non-zero

# Test 17: Validator JSON output
if [[ -f "$SKILLS_DIR/skills/architect/SKILL.md" ]]; then
    run_test 17 "Validator JSON output" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/architect/SKILL.md' --json | jq . > /dev/null" \
        0
else
    echo -e "${YELLOW}⏭️  Test 17: SKIP (architect skill not found)${RESET}"
fi

# Test 18: Validator detects missing frontmatter
echo "# Test skill without frontmatter" > "$TEST_DIR/test-no-fm.md"
run_test 18 "Validator detects missing frontmatter" \
    "python3 '$VALIDATE_PY' '$TEST_DIR/test-no-fm.md'" \
    non-zero

# Test 19: Validator detects malformed YAML frontmatter
cat > "$TEST_DIR/test-bad-yaml.md" <<'EOF'
---
description: Missing name field
model: opus
---
# /test Workflow
EOF
run_test 19 "Validator detects malformed YAML frontmatter" \
    "python3 '$VALIDATE_PY' '$TEST_DIR/test-bad-yaml.md'" \
    non-zero

# Test 20: Validator detects missing steps
cat > "$TEST_DIR/test-no-steps.md" <<'EOF'
---
name: test
description: Test
model: opus
---
# /test Workflow

## Inputs
- Test: $ARGUMENTS
EOF
run_test 20 "Validator detects missing steps" \
    "python3 '$VALIDATE_PY' '$TEST_DIR/test-no-steps.md'" \
    non-zero

# Test 21: Validator detects empty step
cat > "$TEST_DIR/test-empty-step.md" <<'EOF'
---
name: test
description: Test
model: opus
---
# /test Workflow

## Inputs
- Test: $ARGUMENTS

## Step 1 — First step

## Step 2 — Second step
Content here
EOF
run_test 21 "Validator detects empty step" \
    "python3 '$VALIDATE_PY' '$TEST_DIR/test-empty-step.md'" \
    non-zero

# Test 22: Validator detects missing Tool declaration
cat > "$TEST_DIR/test-no-tool.md" <<'EOF'
---
name: test
description: Test
model: opus
---
# /test Workflow

## Inputs
- Test: $ARGUMENTS

## Step 0 — First step
Do something without declaring a tool.
Content content content.

## Step 1 — Second step
Tool: Bash
More content.
EOF
run_test 22 "Validator detects missing Tool declaration" \
    "python3 '$VALIDATE_PY' '$TEST_DIR/test-no-tool.md'" \
    non-zero

# Test 23: Reject description with newlines
run_test 23 "Reject description with newlines" \
    "python3 '$GENERATE_PY' 'test-nl' -d \$'Line one\nLine two' -t '$TEST_DIR'" \
    non-zero

# Test 24: Reject path traversal in target-dir
run_test 24 "Reject path traversal in target-dir" \
    "python3 '$GENERATE_PY' 'test-trav' -d 'Test.' -t '/tmp/../../etc'" \
    non-zero

# Test 25: Generated skill contains metadata comment
if [[ -f "$TEST_DIR/skills/test-coord/SKILL.md" ]]; then
    if grep -q "Generated by claude-tools" "$TEST_DIR/skills/test-coord/SKILL.md"; then
        echo ""
        echo -e "${BLUE}Test 25: Generated skill contains metadata comment${RESET}"
        echo -e "${GREEN}✅ PASS${RESET}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo ""
        echo -e "${BLUE}Test 25: Generated skill contains metadata comment${RESET}"
        echo -e "${RED}❌ FAIL${RESET}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
else
    echo -e "${RED}❌ Test 25: FAIL (test-coord not found)${RESET}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
fi

# Test 27: Validate Reference skill (valid, without model field)
cat > "$TEST_DIR/test-ref-valid.md" <<'EOF'
---
name: test-reference
description: Test fixture for Reference archetype validation
version: 1.0.0
type: reference
attribution: "Test fixture"
---

# Test Reference Skill

## The Iron Law

Test principle content.

## When to Use

Test trigger conditions.
EOF
run_test 27 "Validate Reference skill (valid, no model)" \
    "python3 '$VALIDATE_PY' '$TEST_DIR/test-ref-valid.md'" \
    0

# Test 27b: Reference skill with optional model field also validates
cat > "$TEST_DIR/test-ref-with-model.md" <<'EOF'
---
name: test-reference-model
description: Test fixture for Reference archetype with model
version: 1.0.0
type: reference
attribution: "Test fixture"
model: claude-opus-4-6
---

# Test Reference Skill

## The Iron Law

Test principle content.
EOF
run_test "27b" "Validate Reference skill (valid, with model)" \
    "python3 '$VALIDATE_PY' '$TEST_DIR/test-ref-with-model.md'" \
    0

# Test 28: Reference skill missing attribution
cat > "$TEST_DIR/test-ref-no-attr.md" <<'EOF'
---
name: test-reference
description: Test fixture missing attribution
version: 1.0.0
type: reference
---

# Test Reference Skill

## The Iron Law

Test principle content.
EOF
run_test 28 "Reference skill missing attribution" \
    "python3 '$VALIDATE_PY' '$TEST_DIR/test-ref-no-attr.md'" \
    non-zero

# Test 29: Reference skill with empty body
cat > "$TEST_DIR/test-ref-empty.md" <<'EOF'
---
name: test-reference
description: Test fixture with empty body
version: 1.0.0
type: reference
attribution: "Test fixture"
---

EOF
run_test 29 "Reference skill with empty body" \
    "python3 '$VALIDATE_PY' '$TEST_DIR/test-ref-empty.md'" \
    non-zero

# Test 30: Reference skill without principle heading
cat > "$TEST_DIR/test-ref-no-principle.md" <<'EOF'
---
name: test-reference
description: Test fixture without principle heading
version: 1.0.0
type: reference
attribution: "Test fixture"
---

# Test Reference Skill

## Overview

Some content here.

## Details

More content.
EOF
run_test 30 "Reference skill without principle heading" \
    "python3 '$VALIDATE_PY' '$TEST_DIR/test-ref-no-principle.md'" \
    non-zero

# Test 31: Undeploy skill
DEPLOY_DIR_TEST="$HOME/.claude/skills"
mkdir -p "$DEPLOY_DIR_TEST/test-undeploy-skill"
echo "test" > "$DEPLOY_DIR_TEST/test-undeploy-skill/SKILL.md"
DEPLOY_SCRIPT="$(dirname "$SCRIPT_DIR")/scripts/deploy.sh"
run_test 31 "Undeploy skill" \
    "bash '$DEPLOY_SCRIPT' --undeploy test-undeploy-skill && [ ! -d '$DEPLOY_DIR_TEST/test-undeploy-skill' ]" \
    0

# Test 32: Undeploy nonexistent skill (idempotent)
run_test 32 "Undeploy nonexistent skill (idempotent)" \
    "bash '$DEPLOY_SCRIPT' --undeploy nonexistent-skill-xyz" \
    0

# --- Core skill validation (unconditional -- FAIL if missing) ---

# Test 34: Validate retro skill
run_test 34 "Validate retro skill" \
    "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/retro/SKILL.md'" \
    0

# Test 36: Validate receiving-code-review skill
run_test 36 "Validate receiving-code-review skill" \
    "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/receiving-code-review/SKILL.md'" \
    0

# Test 37: Validate verification-before-completion skill
run_test 37 "Validate verification-before-completion skill" \
    "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/verification-before-completion/SKILL.md'" \
    0

# Test 38: Validate secure-review skill
run_test 38 "Validate secure-review skill" \
    "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/secure-review/SKILL.md'" \
    0

# Test 39: Validate dependency-audit skill
run_test 39 "Validate dependency-audit skill" \
    "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/dependency-audit/SKILL.md'" \
    0

# Test 40: Validate secrets-scan skill
run_test 40 "Validate secrets-scan skill" \
    "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/secrets-scan/SKILL.md'" \
    0

# Test 41: Validate threat-model-gate skill
run_test 41 "Validate threat-model-gate skill" \
    "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/threat-model-gate/SKILL.md'" \
    0

# Test 42: Validate compliance-check skill
run_test 42 "Validate compliance-check skill" \
    "python3 '$VALIDATE_PY' '$SKILLS_DIR/skills/compliance-check/SKILL.md'" \
    0

# --- Contrib skill validation (conditional -- skip if not present) ---

# Test 43: Validate journal contrib skill (if exists)
if [[ -f "$SKILLS_DIR/contrib/journal/SKILL.md" ]]; then
    run_test 43 "Validate journal contrib skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/contrib/journal/SKILL.md'" \
        0
else
    echo -e "${YELLOW}  Test 43: SKIP (journal contrib skill not found)${RESET}"
fi

# Test 44: Validate journal-recall contrib skill (if exists)
if [[ -f "$SKILLS_DIR/contrib/journal-recall/SKILL.md" ]]; then
    run_test 44 "Validate journal-recall contrib skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/contrib/journal-recall/SKILL.md'" \
        0
else
    echo -e "${YELLOW}  Test 44: SKIP (journal-recall contrib skill not found)${RESET}"
fi

# Test 45: Validate journal-review contrib skill (if exists)
if [[ -f "$SKILLS_DIR/contrib/journal-review/SKILL.md" ]]; then
    run_test 45 "Validate journal-review contrib skill" \
        "python3 '$VALIDATE_PY' '$SKILLS_DIR/contrib/journal-review/SKILL.md'" \
        0
else
    echo -e "${YELLOW}  Test 45: SKIP (journal-review contrib skill not found)${RESET}"
fi

# Test 46: Cleanup
echo ""
echo -e "${BLUE}Test 46: Cleanup${RESET}"
rm -rf "$TEST_DIR"
if [[ ! -d "$TEST_DIR" ]]; then
    echo -e "${GREEN}✅ PASS${RESET}"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}❌ FAIL${RESET}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
TOTAL_COUNT=$((TOTAL_COUNT + 1))

# Summary
echo ""
echo "========================================"
echo -e "${BOLD}Test Summary${RESET}"
echo "========================================"
echo -e "Total:  $TOTAL_COUNT"
echo -e "${GREEN}Pass:   $PASS_COUNT${RESET}"
echo -e "${RED}Fail:   $FAIL_COUNT${RESET}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✅ All tests passed!${RESET}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${RESET}"
    exit 1
fi
