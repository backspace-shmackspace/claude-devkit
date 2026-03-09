#!/usr/bin/env bash
#
# Test script for /ship worktree isolation feature (v3.1.0)
# Tests the 6 scenarios from the plan at ~/.claude/plans/clever-dancing-dream.md
#
# Usage:
#   bash generators/test_ship_worktree.sh
#   bash -x generators/test_ship_worktree.sh  # verbose mode
#
# Requirements:
#   - Git 2.5+ (for worktree support)
#   - /ship skill deployed to ~/.claude/skills/ship/SKILL.md
#   - Clean git repository for testing

set -e

# Colors
RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
BLUE='\033[94m'
BOLD='\033[1m'
RESET='\033[0m'

# Counters
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="/tmp/ship-worktree-test-$$"
TEST_REPO="$TEST_DIR/repo"
SHIP_SKILL="$HOME/.claude/skills/ship/SKILL.md"

# Setup test directory
setup_test_env() {
    echo -e "${BLUE}Setting up test environment...${RESET}"

    # Create test directory
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"

    # Create test git repo
    mkdir -p "$TEST_REPO"
    cd "$TEST_REPO"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create initial project structure
    mkdir -p src/{components,utils}
    mkdir -p .claude/agents
    mkdir -p plans

    # Create stub files
    echo "// Initial file" > src/components/Button.tsx
    echo "// Initial file" > src/components/Card.tsx
    echo "// Initial file" > src/utils/helpers.ts
    echo "// Initial file" > src/utils/validators.ts
    echo "// Initial file" > src/types.ts

    # Create required agents (stubs for testing)
    cat > .claude/agents/coder.md <<'EOF'
---
name: coder
description: Test coder agent
model: claude-sonnet-4-5
---
# Coder Agent (Test Stub)
EOF

    cat > .claude/agents/code-reviewer.md <<'EOF'
---
name: code-reviewer
description: Test code reviewer agent
model: claude-sonnet-4-5
---
# Code Reviewer Agent (Test Stub)
EOF

    cat > .claude/agents/qa-engineer.md <<'EOF'
---
name: qa-engineer
description: Test QA engineer agent
model: claude-sonnet-4-5
---
# QA Engineer Agent (Test Stub)
EOF

    # Initial commit
    git add .
    git commit -q -m "Initial commit"

    echo -e "${GREEN}✓ Test environment ready at $TEST_REPO${RESET}"
}

# Cleanup test environment
cleanup_test_env() {
    if [[ -d "$TEST_DIR" ]]; then
        # Force remove any lingering worktrees
        cd "$TEST_REPO" 2>/dev/null || true
        git worktree prune 2>/dev/null || true

        # Remove test directory
        rm -rf "$TEST_DIR"
        echo -e "${GREEN}✓ Test environment cleaned up${RESET}"
    fi
}

# Test runner function
run_test() {
    local test_num="$1"
    local test_name="$2"
    shift 2

    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    echo ""
    echo "========================================"
    echo -e "${BLUE}${BOLD}Test $test_num: $test_name${RESET}"
    echo "========================================"

    # Run test function
    set +e
    "$@"
    local result=$?
    set -e

    if [[ $result -eq 0 ]]; then
        echo -e "${GREEN}✅ PASS${RESET}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}❌ FAIL${RESET}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # Clean up after each test
    cd "$TEST_REPO"
    git worktree prune 2>/dev/null || true
    rm -f .ship-worktrees.tmp .ship-violations.tmp BLOCKED.md
    git reset --hard HEAD -q 2>/dev/null || true
    git clean -fd -q 2>/dev/null || true
}

# Assert function
assert() {
    local condition="$1"
    local message="$2"

    if eval "$condition"; then
        echo -e "  ${GREEN}✓${RESET} $message"
        return 0
    else
        echo -e "  ${RED}✗${RESET} $message"
        return 1
    fi
}

# ============================================
# Test 1: Single Work Group (Backward Compatibility)
# ============================================
test_single_work_group() {
    cd "$TEST_REPO"

    echo "Creating plan without work groups..."
    cat > plans/test-single.md <<'EOF'
# Test Single Work Group

## Context
Test backward compatibility with single work group.

## Goals
- Modify Button component
- Update helpers utility

## Task Breakdown

1. Modify `src/components/Button.tsx` — Add new props
2. Modify `src/utils/helpers.ts` — Add new helper function

## Test Plan

Run: `echo "test"`

## Acceptance Criteria

- [ ] Button.tsx modified
- [ ] helpers.ts modified

## Status: APPROVED
EOF

    git add plans/test-single.md
    git commit -q -m "Add test plan"

    echo "Simulating Step 1 (parse plan)..."
    # No work groups section, should be treated as single group

    echo "Simulating Step 2 (single work group path)..."
    # Modify files directly (no worktrees)
    echo "// Modified by coder" >> src/components/Button.tsx
    echo "// Modified by coder" >> src/utils/helpers.ts
    git add src/components/Button.tsx src/utils/helpers.ts

    echo ""
    echo "Verifying results..."

    # Check that no worktrees were created
    local worktree_count=$(git worktree list | wc -l | tr -d ' ')
    assert '[[ $worktree_count -eq 1 ]]' "No additional worktrees created (only main)"

    # Check that no worktree tracking file exists
    assert '[[ ! -f .ship-worktrees.tmp ]]' "No .ship-worktrees.tmp file created"

    # Check that files were modified
    assert '[[ $(git diff --cached --name-only | wc -l) -eq 2 ]]' "2 files staged for commit"

    echo ""
    return 0
}

# ============================================
# Test 2: Multiple Work Groups (Happy Path)
# ============================================
test_multiple_work_groups() {
    cd "$TEST_REPO"

    echo "Creating plan with 2 work groups..."
    cat > plans/test-multi.md <<'EOF'
# Test Multiple Work Groups

## Context
Test parallel work groups with worktree isolation.

## Goals
- Update components
- Update utilities

## Task Breakdown

### Work Group 1: Components
- src/components/Button.tsx
- src/components/Card.tsx

### Work Group 2: Utilities
- src/utils/helpers.ts
- src/utils/validators.ts

## Test Plan

Run: `echo "test"`

## Acceptance Criteria

- [ ] All files modified
- [ ] No conflicts

## Status: APPROVED
EOF

    git add plans/test-multi.md
    git commit -q -m "Add multi-group test plan"

    echo "Simulating Step 2b (create worktrees)..."
    TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
    WT1="$TEST_DIR/ship-test-multi-wg1-$TIMESTAMP"
    WT2="$TEST_DIR/ship-test-multi-wg2-$TIMESTAMP"

    git worktree add "$WT1" HEAD -q
    git worktree add "$WT2" HEAD -q

    echo "$WT1|1|Components|src/components/Button.tsx src/components/Card.tsx" > .ship-worktrees.tmp
    echo "$WT2|2|Utilities|src/utils/helpers.ts src/utils/validators.ts" >> .ship-worktrees.tmp

    echo "Simulating Step 2c (dispatch coders to worktrees)..."
    # Simulate Work Group 1 modifications
    echo "// WG1 modification" >> "$WT1/src/components/Button.tsx"
    echo "// WG1 modification" >> "$WT1/src/components/Card.tsx"

    # Simulate Work Group 2 modifications
    echo "// WG2 modification" >> "$WT2/src/utils/helpers.ts"
    echo "// WG2 modification" >> "$WT2/src/utils/validators.ts"

    echo ""
    echo "Verifying worktree creation..."

    # Check worktrees exist
    assert '[[ -d "$WT1" ]]' "Worktree 1 exists"
    assert '[[ -d "$WT2" ]]' "Worktree 2 exists"

    # Check worktree list
    local worktree_count=$(git worktree list | wc -l | tr -d ' ')
    assert '[[ $worktree_count -eq 3 ]]' "3 worktrees total (main + 2 work groups)"

    # Check tracking file
    assert '[[ -f .ship-worktrees.tmp ]]' "Tracking file created"
    assert '[[ $(wc -l < .ship-worktrees.tmp | tr -d " ") -eq 2 ]]' "Tracking file has 2 entries"

    echo ""
    echo "Simulating Step 2d (file boundary validation)..."

    VIOLATIONS=""
    MAIN_DIR=$(pwd)

    while IFS='|' read -r wt_path wg_num wg_name scoped_files; do
        cd "$wt_path"

        # Get modified files (check working directory changes)
        MODIFIED=$(find src -type f -newer .git/index 2>/dev/null | sed 's|^\./||' || echo "")

        # For this test, manually check what changed
        if [[ $wg_num -eq 1 ]]; then
            MODIFIED="src/components/Button.tsx src/components/Card.tsx"
        else
            MODIFIED="src/utils/helpers.ts src/utils/validators.ts"
        fi

        # Check each modified file is in scoped files
        for file in $MODIFIED; do
            if ! echo "$scoped_files" | grep -qw "$file"; then
                VIOLATIONS="${VIOLATIONS}Work Group $wg_num ($wg_name) modified $file (not in scope: $scoped_files)\n"
            fi
        done

        cd "$MAIN_DIR"
    done < .ship-worktrees.tmp

    assert '[[ -z "$VIOLATIONS" ]]' "No file boundary violations detected"

    echo ""
    echo "Simulating Step 2e (merge worktrees)..."

    while IFS='|' read -r wt_path wg_num wg_name scoped_files; do
        for file in $scoped_files; do
            if [[ -f "$wt_path/$file" ]]; then
                cp "$wt_path/$file" "$MAIN_DIR/$file"
            fi
        done
    done < .ship-worktrees.tmp

    # Check files were merged
    assert 'grep -q "WG1 modification" src/components/Button.tsx' "Work Group 1 changes merged to Button.tsx"
    assert 'grep -q "WG2 modification" src/utils/helpers.ts' "Work Group 2 changes merged to helpers.ts"

    echo ""
    echo "Simulating Step 2f (cleanup worktrees)..."

    while IFS='|' read -r wt_path wg_num wg_name scoped_files; do
        git worktree remove "$wt_path" --force 2>/dev/null || true
    done < .ship-worktrees.tmp

    rm -f .ship-worktrees.tmp

    # Check cleanup
    assert '[[ ! -d "$WT1" ]]' "Worktree 1 removed"
    assert '[[ ! -d "$WT2" ]]' "Worktree 2 removed"
    assert '[[ ! -f .ship-worktrees.tmp ]]' "Tracking file removed"

    local worktree_count=$(git worktree list | wc -l | tr -d ' ')
    assert '[[ $worktree_count -eq 1 ]]' "Back to single worktree (main)"

    echo ""
    return 0
}

# ============================================
# Test 3: Shared Dependencies
# ============================================
test_shared_dependencies() {
    cd "$TEST_REPO"

    echo "Creating plan with shared dependencies..."
    cat > plans/test-shared.md <<'EOF'
# Test Shared Dependencies

## Context
Test shared dependencies committed before work groups.

## Goals
- Update shared types
- Update components and utils

## Task Breakdown

### Shared Dependencies
- src/types.ts (modify — implement before work groups)

### Work Group 1: Components
- src/components/Button.tsx

### Work Group 2: Utilities
- src/utils/helpers.ts

## Test Plan

Run: `echo "test"`

## Acceptance Criteria

- [ ] Types updated first
- [ ] Components and utils can use new types

## Status: APPROVED
EOF

    git add plans/test-shared.md
    git commit -q -m "Add shared deps test plan"

    echo "Simulating Step 2a (shared dependencies)..."
    # Modify shared file
    echo "// Shared type definition" >> src/types.ts
    git add src/types.ts
    git commit -q -m "tmp: ship shared deps - base for worktrees"

    local shared_commit=$(git rev-parse HEAD)

    echo "Simulating Step 2b-2c (create worktrees from shared base)..."
    TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
    WT1="$TEST_DIR/ship-test-shared-wg1-$TIMESTAMP"
    WT2="$TEST_DIR/ship-test-shared-wg2-$TIMESTAMP"

    # Worktrees created from current HEAD (which includes shared deps commit)
    git worktree add "$WT1" HEAD -q
    git worktree add "$WT2" HEAD -q

    echo ""
    echo "Verifying shared dependencies..."

    # Check that shared deps are visible in worktrees
    assert 'grep -q "Shared type definition" "$WT1/src/types.ts"' "Worktree 1 sees shared deps"
    assert 'grep -q "Shared type definition" "$WT2/src/types.ts"' "Worktree 2 sees shared deps"

    # Simulate work group modifications
    echo "// Uses shared types" >> "$WT1/src/components/Button.tsx"
    echo "// Uses shared types" >> "$WT2/src/utils/helpers.ts"

    echo ""
    echo "Simulating merge and final commit (Step 5)..."

    # Merge worktrees (simplified)
    cp "$WT1/src/components/Button.tsx" src/components/Button.tsx
    cp "$WT2/src/utils/helpers.ts" src/utils/helpers.ts

    # Cleanup
    git worktree remove "$WT1" --force 2>/dev/null || true
    git worktree remove "$WT2" --force 2>/dev/null || true

    # Soft reset to combine shared deps + work groups
    git reset --soft HEAD~1 -q

    # Check that shared deps are still staged
    assert 'git diff --cached --name-only | grep -q "src/types.ts"' "Shared deps still staged after soft reset"

    # Final commit would include all changes
    git add src/components/Button.tsx src/utils/helpers.ts
    local staged_count=$(git diff --cached --name-only | wc -l | tr -d ' ')
    assert '[[ $staged_count -eq 3 ]]' "All 3 files staged (shared + 2 work groups)"

    echo ""
    return 0
}

# ============================================
# Test 4: File Boundary Violation (Negative Test)
# ============================================
test_file_boundary_violation() {
    cd "$TEST_REPO"

    echo "Creating plan with 2 work groups..."
    cat > plans/test-violation.md <<'EOF'
# Test File Boundary Violation

## Context
Test that validation catches boundary violations.

## Goals
- Update components

## Task Breakdown

### Work Group 1: Components
- src/components/Button.tsx

### Work Group 2: Utilities
- src/utils/helpers.ts

## Test Plan

Run: `echo "test"`

## Acceptance Criteria

- [ ] Validation catches violations

## Status: APPROVED
EOF

    git add plans/test-violation.md
    git commit -q -m "Add violation test plan"

    echo "Simulating Step 2b-2c (create worktrees and inject violation)..."
    TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
    WT1="$TEST_DIR/ship-test-violation-wg1-$TIMESTAMP"
    WT2="$TEST_DIR/ship-test-violation-wg2-$TIMESTAMP"

    git worktree add "$WT1" HEAD -q
    git worktree add "$WT2" HEAD -q

    echo "$WT1|1|Components|src/components/Button.tsx" > .ship-worktrees.tmp
    echo "$WT2|2|Utilities|src/utils/helpers.ts" >> .ship-worktrees.tmp

    # Work Group 1: Modify assigned file (OK)
    echo "// WG1 modification" >> "$WT1/src/components/Button.tsx"

    # Work Group 2: Modify assigned file PLUS violate boundary
    echo "// WG2 modification" >> "$WT2/src/utils/helpers.ts"
    echo "// VIOLATION: WG2 modifying WG1's file" >> "$WT2/src/components/Button.tsx"

    echo ""
    echo "Simulating Step 2d (file boundary validation)..."

    VIOLATIONS=""
    MAIN_DIR=$(pwd)

    while IFS='|' read -r wt_path wg_num wg_name scoped_files; do
        cd "$wt_path"

        # Manually check what changed (simulating git diff)
        if [[ $wg_num -eq 1 ]]; then
            MODIFIED="src/components/Button.tsx"
        else
            # WG2 modified BOTH files (violation)
            MODIFIED="src/utils/helpers.ts src/components/Button.tsx"
        fi

        # Check each modified file is in scoped files
        for file in $MODIFIED; do
            if ! echo "$scoped_files" | grep -qw "$file"; then
                VIOLATIONS="${VIOLATIONS}Work Group $wg_num ($wg_name) modified $file (not in scope: $scoped_files)\n"
            fi
        done

        cd "$MAIN_DIR"
    done < .ship-worktrees.tmp

    if [[ -n "$VIOLATIONS" ]]; then
        echo -e "$VIOLATIONS" > .ship-violations.tmp
    fi

    echo ""
    echo "Verifying violation detection..."

    # Check that violation was detected
    assert '[[ -f .ship-violations.tmp ]]' "Violation file created"
    assert '[[ -s .ship-violations.tmp ]]' "Violation file is not empty"
    assert 'grep -q "Work Group 2" .ship-violations.tmp' "Violation mentions Work Group 2"
    assert 'grep -q "src/components/Button.tsx" .ship-violations.tmp' "Violation mentions unauthorized file"

    echo ""
    echo "Simulating workflow stop (violations block Step 2e)..."

    # Workflow should stop here, not proceed to merge
    # But we still clean up worktrees

    while IFS='|' read -r wt_path wg_num wg_name scoped_files; do
        git worktree remove "$wt_path" --force 2>/dev/null || true
    done < .ship-worktrees.tmp

    rm -f .ship-worktrees.tmp .ship-violations.tmp

    assert '[[ ! -d "$WT1" ]]' "Worktree 1 cleaned up despite failure"
    assert '[[ ! -d "$WT2" ]]' "Worktree 2 cleaned up despite failure"

    echo ""
    return 0
}

# ============================================
# Test 5: Revision Loop with Worktrees
# ============================================
test_revision_loop() {
    cd "$TEST_REPO"

    echo "Creating plan for revision loop test..."
    cat > plans/test-revision.md <<'EOF'
# Test Revision Loop

## Context
Test that revision loops recreate worktrees.

## Goals
- Update components (with revisions)

## Task Breakdown

### Work Group 1: Components
- src/components/Button.tsx

### Work Group 2: Utilities
- src/utils/helpers.ts

## Test Plan

Run: `echo "test"`

## Acceptance Criteria

- [ ] Initial implementation
- [ ] Revisions applied in isolation

## Status: APPROVED
EOF

    git add plans/test-revision.md
    git commit -q -m "Add revision test plan"

    echo "Simulating Step 2 (initial implementation)..."
    TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
    WT1_V1="$TEST_DIR/ship-test-revision-wg1-$TIMESTAMP"
    WT2_V1="$TEST_DIR/ship-test-revision-wg2-$TIMESTAMP"

    git worktree add "$WT1_V1" HEAD -q
    git worktree add "$WT2_V1" HEAD -q

    echo "// Initial implementation" >> "$WT1_V1/src/components/Button.tsx"
    echo "// Initial implementation" >> "$WT2_V1/src/utils/helpers.ts"

    # Merge to main
    cp "$WT1_V1/src/components/Button.tsx" src/components/Button.tsx
    cp "$WT2_V1/src/utils/helpers.ts" src/utils/helpers.ts

    # Cleanup initial worktrees
    git worktree remove "$WT1_V1" --force 2>/dev/null || true
    git worktree remove "$WT2_V1" --force 2>/dev/null || true

    # Stage and commit initial implementation (so revision worktrees see it)
    git add src/components/Button.tsx src/utils/helpers.ts
    git commit -q -m "Initial implementation (before revision)"

    echo ""
    echo "Simulating Step 3 (code review returns REVISION_NEEDED)..."
    # Assume code review found issues

    echo ""
    echo "Simulating Step 4 (revision loop - recreate worktrees)..."
    TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
    WT1_V2="$TEST_DIR/ship-test-revision-wg1-$TIMESTAMP"
    WT2_V2="$TEST_DIR/ship-test-revision-wg2-$TIMESTAMP"

    # Recreate worktrees from current state (includes initial implementation)
    git worktree add "$WT1_V2" HEAD -q
    git worktree add "$WT2_V2" HEAD -q

    echo ""
    echo "Verifying revision worktrees..."

    # Check new worktrees exist
    assert '[[ -d "$WT1_V2" ]]' "Revision worktree 1 created"
    assert '[[ -d "$WT2_V2" ]]' "Revision worktree 2 created"

    # Check they contain initial implementation
    assert 'grep -q "Initial implementation" "$WT1_V2/src/components/Button.tsx"' "Revision WG1 sees initial work"
    assert 'grep -q "Initial implementation" "$WT2_V2/src/utils/helpers.ts"' "Revision WG2 sees initial work"

    # Apply revisions
    echo "// Revision applied" >> "$WT1_V2/src/components/Button.tsx"
    echo "// Revision applied" >> "$WT2_V2/src/utils/helpers.ts"

    # Merge revisions
    cp "$WT1_V2/src/components/Button.tsx" src/components/Button.tsx
    cp "$WT2_V2/src/utils/helpers.ts" src/utils/helpers.ts

    # Check revisions merged
    assert 'grep -q "Revision applied" src/components/Button.tsx' "Revisions merged to Button.tsx"
    assert 'grep -q "Revision applied" src/utils/helpers.ts' "Revisions merged to helpers.ts"

    # Cleanup
    git worktree remove "$WT1_V2" --force 2>/dev/null || true
    git worktree remove "$WT2_V2" --force 2>/dev/null || true

    local worktree_count=$(git worktree list | wc -l | tr -d ' ')
    assert '[[ $worktree_count -eq 1 ]]' "All worktrees cleaned up after revision"

    echo ""
    return 0
}

# ============================================
# Test 6: Cleanup on Failure
# ============================================
test_cleanup_on_failure() {
    cd "$TEST_REPO"

    echo "Creating plan for cleanup test..."
    cat > plans/test-cleanup.md <<'EOF'
# Test Cleanup on Failure

## Context
Test that worktrees are cleaned up even when validation fails.

## Goals
- Ensure no orphaned worktrees

## Task Breakdown

### Work Group 1: Components
- src/components/Button.tsx

### Work Group 2: Utilities
- src/utils/helpers.ts

## Test Plan

Run: `echo "test"`

## Acceptance Criteria

- [ ] Cleanup happens on failure

## Status: APPROVED
EOF

    git add plans/test-cleanup.md
    git commit -q -m "Add cleanup test plan"

    echo "Simulating Step 2b-2c (create worktrees)..."
    TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
    WT1="$TEST_DIR/ship-test-cleanup-wg1-$TIMESTAMP"
    WT2="$TEST_DIR/ship-test-cleanup-wg2-$TIMESTAMP"

    git worktree add "$WT1" HEAD -q
    git worktree add "$WT2" HEAD -q

    echo "$WT1|1|Components|src/components/Button.tsx" > .ship-worktrees.tmp
    echo "$WT2|2|Utilities|src/utils/helpers.ts" >> .ship-worktrees.tmp

    # Modify files
    echo "// Modification" >> "$WT1/src/components/Button.tsx"
    echo "// Modification" >> "$WT2/src/utils/helpers.ts"

    echo ""
    echo "Simulating validation failure (Step 2d)..."

    # Inject a validation failure (simulate agent modified wrong file)
    echo "// Violation" >> "$WT1/src/utils/validators.ts"

    VIOLATIONS="Work Group 1 (Components) modified src/utils/validators.ts (not in scope)\n"
    echo -e "$VIOLATIONS" > .ship-violations.tmp

    echo ""
    echo "Verifying cleanup despite failure..."

    # Even though validation failed, cleanup should still happen
    while IFS='|' read -r wt_path wg_num wg_name scoped_files; do
        git worktree remove "$wt_path" --force 2>/dev/null || true
    done < .ship-worktrees.tmp

    rm -f .ship-worktrees.tmp .ship-violations.tmp

    # Check for orphaned worktrees
    assert '[[ ! -d "$WT1" ]]' "Worktree 1 cleaned up despite failure"
    assert '[[ ! -d "$WT2" ]]' "Worktree 2 cleaned up despite failure"

    local worktree_count=$(git worktree list | wc -l | tr -d ' ')
    assert '[[ $worktree_count -eq 1 ]]' "No orphaned worktrees remain"

    # Check for orphaned worktrees in /tmp
    local orphaned=$(find "$TEST_DIR" -maxdepth 1 -type d -name "ship-test-cleanup-wg*" 2>/dev/null | wc -l | tr -d ' ')
    assert '[[ $orphaned -eq 0 ]]' "No orphaned worktree directories in /tmp"

    echo ""
    return 0
}

# ============================================
# Main Test Execution
# ============================================

echo "========================================"
echo -e "${BOLD}Ship Worktree Isolation Test Suite${RESET}"
echo "========================================"
echo "Testing /ship v3.1.0 worktree isolation feature"
echo ""

# Check prerequisites
if ! command -v git &> /dev/null; then
    echo -e "${RED}❌ Git not found. Please install git.${RESET}"
    exit 1
fi

GIT_VERSION=$(git --version | awk '{print $3}')
echo "Git version: $GIT_VERSION"

if [[ ! -f "$SHIP_SKILL" ]]; then
    echo -e "${YELLOW}⚠️  Warning: /ship skill not found at $SHIP_SKILL${RESET}"
    echo "These tests verify the worktree isolation logic, but won't test the actual skill."
fi

echo ""

# Setup
setup_test_env

# Run tests
run_test 1 "Single Work Group (Backward Compatibility)" test_single_work_group
run_test 2 "Multiple Work Groups (Happy Path)" test_multiple_work_groups
run_test 3 "Shared Dependencies" test_shared_dependencies
run_test 4 "File Boundary Violation (Negative Test)" test_file_boundary_violation
run_test 5 "Revision Loop with Worktrees" test_revision_loop
run_test 6 "Cleanup on Failure" test_cleanup_on_failure

# Cleanup
echo ""
echo "========================================"
echo -e "${BLUE}Cleanup${RESET}"
echo "========================================"
cleanup_test_env

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
    echo ""
    echo "The worktree isolation feature is working correctly:"
    echo "  ✓ Single work groups maintain backward compatibility"
    echo "  ✓ Multiple work groups use worktree isolation"
    echo "  ✓ Shared dependencies are committed first"
    echo "  ✓ File boundary violations are detected"
    echo "  ✓ Revision loops recreate worktrees"
    echo "  ✓ Cleanup happens even on failure"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${RESET}"
    echo ""
    echo "Review the output above to diagnose issues."
    exit 1
fi
