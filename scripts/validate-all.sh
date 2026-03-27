#!/usr/bin/env bash
# Validate all skills in claude-devkit
# Usage: ./scripts/validate-all.sh [--strict]
#
# Validates:
#   - All core skills in skills/*/SKILL.md
#   - All contrib skills in contrib/*/SKILL.md (if directory exists)
#
# Note: Agent templates are not validated here. They contain placeholder
# variables that require generation before validation.
#
# Exit codes:
#   0 = All validations passed
#   1 = One or more validations failed

set -euo pipefail
shopt -s nullglob  # Prevent glob from expanding to literal string when no matches

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATE_PY="$REPO_DIR/generators/validate_skill.py"
STRICT_FLAG="${1:-}"

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

validate_skill() {
    local skill_path="$1"
    local skill_name="$(basename "$(dirname "$skill_path")")"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    if python3 "$VALIDATE_PY" "$skill_path" $STRICT_FLAG > /dev/null 2>&1; then
        echo "  PASS: $skill_name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL: $skill_name"
        # Re-run with output visible so the user can see why it failed
        python3 "$VALIDATE_PY" "$skill_path" $STRICT_FLAG 2>&1 | sed 's/^/    /' || true
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo "Validating all claude-devkit skills..."
echo ""

# Core skills
echo "Core skills (skills/):"
for skill in "$REPO_DIR"/skills/*/SKILL.md; do
    validate_skill "$skill"
done

# Contrib skills
if [ -d "$REPO_DIR/contrib" ]; then
    echo ""
    echo "Contrib skills (contrib/):"
    for skill in "$REPO_DIR"/contrib/*/SKILL.md; do
        validate_skill "$skill"
    done
fi

# Summary
echo ""
echo "========================================"
echo "Validation Summary"
echo "========================================"
echo "Total:  $TOTAL_COUNT"
echo "Pass:   $PASS_COUNT"
echo "Fail:   $FAIL_COUNT"

if [ $FAIL_COUNT -eq 0 ]; then
    echo ""
    echo "All skills validated successfully."
    exit 0
else
    echo ""
    echo "Some skills failed validation."
    exit 1
fi
