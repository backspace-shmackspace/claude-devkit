#!/bin/bash
# Test suite for agent generator and validator
# Tests: Generation, validation, auto-detection, error handling

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$PROJECT_ROOT/.test"
GENERATOR="$SCRIPT_DIR/generate_agents.py"
VALIDATOR="$SCRIPT_DIR/validate_agent.py"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Cleanup function
cleanup() {
    if [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

# Setup
setup() {
    cleanup
    mkdir -p "$TEST_DIR"
}

# Test utilities
assert_success() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $1"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $1"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_failure() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ $? -ne 0 ]; then
        echo -e "${GREEN}✓${NC} $1"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $1"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_file_exists() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$1" ]; then
        echo -e "${GREEN}✓${NC} File exists: $2"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} File missing: $2"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_contains() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q "$1" "$2"; then
        echo -e "${GREEN}✓${NC} Contains '$1': $(basename $2)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing '$1': $(basename $2)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test 1: Generator help text
test_generator_help() {
    echo ""
    echo "Test 1: Generator help text"
    python3 "$GENERATOR" --help > /dev/null
    assert_success "Generator displays help"
}

# Test 2: Validator help text
test_validator_help() {
    echo ""
    echo "Test 2: Validator help text"
    python3 "$VALIDATOR" --help > /dev/null
    assert_success "Validator displays help"
}

# Test 3: Generate coder agent for Python project
test_generate_coder_python() {
    echo ""
    echo "Test 3: Generate coder agent for Python project"

    # Create test Python project
    mkdir -p "$TEST_DIR/python-project"
    cat > "$TEST_DIR/python-project/pyproject.toml" << 'EOF'
[project]
name = "test-api"
dependencies = ["fastapi", "uvicorn"]
[project.optional-dependencies]
dev = ["pytest", "mypy"]
EOF

    # Generate agent
    python3 "$GENERATOR" "$TEST_DIR/python-project" --type coder --force > /dev/null 2>&1
    assert_success "Generate coder agent"

    # Check file exists
    assert_file_exists "$TEST_DIR/python-project/.claude/agents/coder-python.md" "coder-python.md"

    # Validate content
    if [ -f "$TEST_DIR/python-project/.claude/agents/coder-python.md" ]; then
        assert_contains "coder-base.md" "$TEST_DIR/python-project/.claude/agents/coder-python.md"
        assert_contains "CLAUDE.md" "$TEST_DIR/python-project/.claude/agents/coder-python.md"
    fi
}

# Test 4: Generate QA agent for Python project
test_generate_qa_python() {
    echo ""
    echo "Test 4: Generate QA engineer agent"

    mkdir -p "$TEST_DIR/qa-test"
    cat > "$TEST_DIR/qa-test/pyproject.toml" << 'EOF'
[project]
name = "test"
dependencies = ["pytest"]
EOF

    python3 "$GENERATOR" "$TEST_DIR/qa-test" --type qa-engineer --force > /dev/null 2>&1
    assert_success "Generate QA agent"

    assert_file_exists "$TEST_DIR/qa-test/.claude/agents/qa-engineer-python.md" "qa-engineer-python.md"
}

# Test 5: Generate code-reviewer (standalone)
test_generate_code_reviewer() {
    echo ""
    echo "Test 5: Generate code-reviewer (standalone)"

    mkdir -p "$TEST_DIR/reviewer-test"
    python3 "$GENERATOR" "$TEST_DIR/reviewer-test" --type code-reviewer --force > /dev/null 2>&1
    assert_success "Generate code-reviewer"

    assert_file_exists "$TEST_DIR/reviewer-test/.claude/agents/code-reviewer.md" "code-reviewer.md"

    # Should NOT have inheritance header
    if [ -f "$TEST_DIR/reviewer-test/.claude/agents/code-reviewer.md" ]; then
        if ! grep -q "# Inheritance" "$TEST_DIR/reviewer-test/.claude/agents/code-reviewer.md"; then
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Standalone agent (no inheritance header)"
        else
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Should not have inheritance header"
        fi
    fi
}

# Test 6: Generate security-analyst
test_generate_security_analyst() {
    echo ""
    echo "Test 6: Generate security-analyst"

    mkdir -p "$TEST_DIR/security-test"
    python3 "$GENERATOR" "$TEST_DIR/security-test" --type security-analyst --force > /dev/null 2>&1
    assert_success "Generate security-analyst"

    assert_file_exists "$TEST_DIR/security-test/.claude/agents/security-analyst.md" "security-analyst.md"

    if [ -f "$TEST_DIR/security-test/.claude/agents/security-analyst.md" ]; then
        assert_contains "architect-base.md" "$TEST_DIR/security-test/.claude/agents/security-analyst.md"
        assert_contains "STRIDE" "$TEST_DIR/security-test/.claude/agents/security-analyst.md"
    fi
}

# Test 7: Generate all agents
test_generate_all() {
    echo ""
    echo "Test 7: Generate all agents"

    mkdir -p "$TEST_DIR/all-test"
    cat > "$TEST_DIR/all-test/package.json" << 'EOF'
{
  "name": "test",
  "dependencies": {
    "next": "14.0.0",
    "react": "18.0.0"
  }
}
EOF

    python3 "$GENERATOR" "$TEST_DIR/all-test" --type all --force > /dev/null 2>&1
    assert_success "Generate all agents"

    # Should create at least 5 agents
    AGENT_COUNT=$(find "$TEST_DIR/all-test/.claude/agents" -name "*.md" 2>/dev/null | wc -l)
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$AGENT_COUNT" -ge 5 ]; then
        echo -e "${GREEN}✓${NC} Generated $AGENT_COUNT agents"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Only generated $AGENT_COUNT agents (expected >= 5)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test 8: Validate valid coder agent
test_validate_valid_coder() {
    echo ""
    echo "Test 8: Validate valid coder agent"

    mkdir -p "$TEST_DIR/validate-test"
    python3 "$GENERATOR" "$TEST_DIR/validate-test" --type coder --force > /dev/null 2>&1

    python3 "$VALIDATOR" "$TEST_DIR/validate-test/.claude/agents/"*.md > /dev/null 2>&1
    assert_success "Validation passes for generated agent"
}

# Test 9: Validate standalone code-reviewer
test_validate_standalone() {
    echo ""
    echo "Test 9: Validate standalone code-reviewer"

    mkdir -p "$TEST_DIR/validate-standalone"
    python3 "$GENERATOR" "$TEST_DIR/validate-standalone" --type code-reviewer --force > /dev/null 2>&1

    python3 "$VALIDATOR" "$TEST_DIR/validate-standalone/.claude/agents/code-reviewer.md" > /dev/null 2>&1
    assert_success "Validation passes for standalone agent"
}

# Test 10: Validate invalid agent (missing inheritance)
test_validate_invalid() {
    echo ""
    echo "Test 10: Validate invalid agent"

    mkdir -p "$TEST_DIR/invalid-test/.claude/agents"
    cat > "$TEST_DIR/invalid-test/.claude/agents/broken.md" << 'EOF'
# Broken Agent
This is missing required sections.
EOF

    python3 "$VALIDATOR" "$TEST_DIR/invalid-test/.claude/agents/broken.md" > /dev/null 2>&1
    assert_failure "Validation fails for invalid agent"
}

# Test 11: Auto-detection for TypeScript project
test_autodetect_typescript() {
    echo ""
    echo "Test 11: Auto-detect TypeScript project"

    mkdir -p "$TEST_DIR/ts-test"
    cat > "$TEST_DIR/ts-test/package.json" << 'EOF'
{
  "name": "test",
  "dependencies": {
    "react": "18.0.0",
    "typescript": "5.0.0"
  }
}
EOF
    cat > "$TEST_DIR/ts-test/tsconfig.json" << 'EOF'
{}
EOF

    python3 "$GENERATOR" "$TEST_DIR/ts-test" --type coder --force > /dev/null 2>&1
    assert_success "Generate for TypeScript project"

    # Should create typescript variant
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$TEST_DIR/ts-test/.claude/agents/coder-typescript.md" ] || [ -f "$TEST_DIR/ts-test/.claude/agents/coder-frontend.md" ]; then
        echo -e "${GREEN}✓${NC} Created TypeScript/frontend variant"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Did not create TypeScript variant"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test 12: Security-focused detection
test_autodetect_security() {
    echo ""
    echo "Test 12: Auto-detect security-focused project"

    mkdir -p "$TEST_DIR/sec-test"
    cat > "$TEST_DIR/sec-test/pyproject.toml" << 'EOF'
[project]
name = "secure-api"
dependencies = ["fastapi", "bandit", "safety"]
EOF

    python3 "$GENERATOR" "$TEST_DIR/sec-test" --type coder --force > /dev/null 2>&1
    assert_success "Generate for security project"

    assert_file_exists "$TEST_DIR/sec-test/.claude/agents/coder-security.md" "coder-security.md"
}

# Test 13: JSON output from validator
test_validator_json() {
    echo ""
    echo "Test 13: Validator JSON output"

    mkdir -p "$TEST_DIR/json-test"
    python3 "$GENERATOR" "$TEST_DIR/json-test" --type coder --force > /dev/null 2>&1

    OUTPUT=$(python3 "$VALIDATOR" "$TEST_DIR/json-test/.claude/agents/"*.md --json 2>&1)
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$OUTPUT" | python3 -m json.tool > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Validator outputs valid JSON"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Validator JSON output invalid"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test 14: Tech stack override
test_tech_stack_override() {
    echo ""
    echo "Test 14: Tech stack override"

    mkdir -p "$TEST_DIR/override-test"
    python3 "$GENERATOR" "$TEST_DIR/override-test" --type coder --tech-stack "Custom Stack" --force > /dev/null 2>&1
    assert_success "Generate with tech stack override"
}

# Test 15: Force overwrite
test_force_overwrite() {
    echo ""
    echo "Test 15: Force overwrite existing agent"

    mkdir -p "$TEST_DIR/force-test/.claude/agents"
    echo "existing" > "$TEST_DIR/force-test/.claude/agents/coder.md"

    python3 "$GENERATOR" "$TEST_DIR/force-test" --type coder --force > /dev/null 2>&1
    assert_success "Force overwrite"

    # Should have new content
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! grep -q "existing" "$TEST_DIR/force-test/.claude/agents/"*.md 2>/dev/null; then
        echo -e "${GREEN}✓${NC} File was overwritten"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} File was not overwritten"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Run all tests
echo "═══════════════════════════════════════════════════════════"
echo "Agent Generator & Validator Test Suite"
echo "═══════════════════════════════════════════════════════════"

setup

test_generator_help
test_validator_help
test_generate_coder_python
test_generate_qa_python
test_generate_code_reviewer
test_generate_security_analyst
test_generate_all
test_validate_valid_coder
test_validate_standalone
test_validate_invalid
test_autodetect_typescript
test_autodetect_security
test_validator_json
test_tech_stack_override
test_force_overwrite

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "Test Summary"
echo "═══════════════════════════════════════════════════════════"
echo "Tests run: $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
else
    echo -e "Tests failed: ${GREEN}$TESTS_FAILED${NC}"
fi
echo ""

# Cleanup
cleanup

# Exit with appropriate code
if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
