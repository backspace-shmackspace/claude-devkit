#!/usr/bin/env bash
#
# Bash wrapper for generate_skill.py
#
# Usage:
#   ./generate_skill.sh <name> [archetype] [target-dir]
#
# Examples:
#   ./generate_skill.sh deploy-check
#   ./generate_skill.sh scan-deps scan
#   ./generate_skill.sh my-skill coordinator ~/my-project

set -e

# Colors
RED='\033[91m'
GREEN='\033[92m'
BLUE='\033[94m'
YELLOW='\033[93m'
RESET='\033[0m'

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/generate_skill.py"

# Check if Python script exists
if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    echo -e "${RED}❌ Error: generate_skill.py not found at $PYTHON_SCRIPT${RESET}" >&2
    exit 1
fi

# Parse positional arguments
SKILL_NAME="${1:-}"
ARCHETYPE="${2:-coordinator}"
# Default to claude-devkit repo root (parent of generators/)
SCRIPT_DIR_GS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${3:-$(dirname "$SCRIPT_DIR_GS")}"

# Check if skill name provided
if [[ -z "$SKILL_NAME" ]]; then
    echo -e "${BLUE}Usage: $0 <skill-name> [archetype] [target-dir]${RESET}"
    echo ""
    echo "Examples:"
    echo "  $0 deploy-check"
    echo "  $0 scan-deps scan"
    echo "  $0 my-skill coordinator ~/my-project"
    echo ""
    echo "Archetypes: coordinator, pipeline, scan"
    echo ""
    exit 1
fi

# Call Python script
echo -e "${BLUE}Calling skill generator...${RESET}"
echo ""

python3 "$PYTHON_SCRIPT" "$SKILL_NAME" \
    --archetype "$ARCHETYPE" \
    --target-dir "$TARGET_DIR"

exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Skill generation complete${RESET}"
else
    echo ""
    echo -e "${RED}❌ Skill generation failed with exit code $exit_code${RESET}"
fi

exit $exit_code
