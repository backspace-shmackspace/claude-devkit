#!/usr/bin/env bash
set -euo pipefail

# Complexity gate: runs radon against changed Python files.
# Fails if any function has cyclomatic complexity > 10 (grade D+).
# Usage: bash scripts/complexity-check.sh [base-ref]

BASE="${1:-HEAD~1}"
RADON="${HOME}/.claude-devkit/scanner-venv/bin/radon"

if [ ! -x "$RADON" ]; then
  echo "radon not installed. Run: ~/.claude-devkit/scanner-venv/bin/pip install radon"
  exit 1
fi

FILES=$(git diff --name-only --diff-filter=ACMR "$BASE" -- '*.py' 2>/dev/null || true)
if [ -z "$FILES" ]; then
  echo "No Python files changed."
  exit 0
fi

# Cyclomatic complexity: D (11-15), E (16-25), F (26+) = fail
BAD=$("$RADON" cc --min D --no-assert -s $FILES 2>/dev/null || true)
if [ -n "$BAD" ]; then
  echo "Cyclomatic complexity violations (score > 10):"
  echo "$BAD"
  exit 1
fi

echo "Complexity check passed. $(echo "$FILES" | wc -w | tr -d ' ') file(s) checked."
