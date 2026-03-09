#!/usr/bin/env bash
# Install claude-devkit tools and generators
# Adds generators to PATH and creates convenient aliases
# Works on Linux and macOS with both bash and zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATORS_DIR="$REPO_DIR/generators"

# Detect Python command (python3 on macOS, python on some Linux)
if command -v python3 &>/dev/null; then
    PYTHON_CMD="python3"
elif command -v python &>/dev/null; then
    PYTHON_CMD="python"
else
    echo "ERROR: Python not found. Please install Python 3."
    exit 1
fi

# Detect user's shell and return appropriate RC file(s)
detect_rc_files() {
    local rc_files=()

    # Detect user's default shell
    local user_shell="${SHELL:-}"
    if [ -z "$user_shell" ]; then
        # Fallback: get from /etc/passwd
        user_shell=$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || echo "")
    fi

    # Determine which RC files to update
    case "$user_shell" in
        */zsh)
            # macOS default since Catalina
            [ -f "$HOME/.zshrc" ] && rc_files+=("$HOME/.zshrc")
            ;;
        */bash)
            # Linux default, older macOS
            if [ -f "$HOME/.bash_profile" ]; then
                rc_files+=("$HOME/.bash_profile")
            elif [ -f "$HOME/.bashrc" ]; then
                rc_files+=("$HOME/.bashrc")
            fi
            ;;
        *)
            # Unknown shell - update both if they exist
            [ -f "$HOME/.zshrc" ] && rc_files+=("$HOME/.zshrc")
            [ -f "$HOME/.bashrc" ] && rc_files+=("$HOME/.bashrc")
            [ -f "$HOME/.bash_profile" ] && rc_files+=("$HOME/.bash_profile")
            ;;
    esac

    # If no RC files found, create one based on shell
    if [ ${#rc_files[@]} -eq 0 ]; then
        case "$user_shell" in
            */zsh)
                rc_files+=("$HOME/.zshrc")
                ;;
            */bash)
                rc_files+=("$HOME/.bashrc")
                ;;
            *)
                rc_files+=("$HOME/.profile")
                ;;
        esac
    fi

    printf '%s\n' "${rc_files[@]}"
}

# Get RC files to update
mapfile -t RC_FILES < <(detect_rc_files)

echo "Installing claude-devkit..."
echo "Detected shell: ${SHELL:-unknown}"
echo "Detected Python: $PYTHON_CMD"
echo "Will update ${#RC_FILES[@]} RC file(s):"
for rc in "${RC_FILES[@]}"; do
    echo "  - $rc"
done
echo ""

# Process each RC file
UPDATED_FILES=()
BACKUP_FILES=()

for RC_FILE in "${RC_FILES[@]}"; do
    # Create backup
    BACKUP_FILE="${RC_FILE}.claude-devkit-backup-$(date +%Y%m%d-%H%M%S)"

    if [ -f "$RC_FILE" ]; then
        cp "$RC_FILE" "$BACKUP_FILE"
        echo "Backed up $RC_FILE to $BACKUP_FILE"
        BACKUP_FILES+=("$BACKUP_FILE")
    else
        # Create new file
        touch "$RC_FILE"
        echo "Created new file: $RC_FILE"
    fi

    # Check if already installed
    if grep -q "# claude-devkit PATH" "$RC_FILE" 2>/dev/null; then
        echo "WARNING: claude-devkit appears to already be installed in $RC_FILE"
        echo "Skipping $RC_FILE (already configured)"
        continue
    fi

    # Add to PATH and create aliases
    cat >> "$RC_FILE" << EOF

# claude-devkit PATH
export PATH="\$PATH:$GENERATORS_DIR"

# claude-devkit aliases
alias generate-skill="$PYTHON_CMD $GENERATORS_DIR/generate_skill.py"
alias generate-agent="$PYTHON_CMD $GENERATORS_DIR/generate_senior_architect.py"
alias generate-agents="$PYTHON_CMD $GENERATORS_DIR/generate_agents.py"
alias validate-skill="$PYTHON_CMD $GENERATORS_DIR/validate_skill.py"
alias gen-skill="$PYTHON_CMD $GENERATORS_DIR/generate_skill.py"
alias gen-agent="$PYTHON_CMD $GENERATORS_DIR/generate_senior_architect.py"
alias gen-agents="$PYTHON_CMD $GENERATORS_DIR/generate_agents.py"
alias val-skill="$PYTHON_CMD $GENERATORS_DIR/validate_skill.py"
EOF

    UPDATED_FILES+=("$RC_FILE")
    echo "✅ Updated $RC_FILE"
done

echo ""
echo "✅ Installation complete!"
echo ""
if [ ${#UPDATED_FILES[@]} -gt 0 ]; then
    echo "Updated files:"
    for file in "${UPDATED_FILES[@]}"; do
        echo "  - $file"
    done
fi
if [ ${#BACKUP_FILES[@]} -gt 0 ]; then
    echo ""
    echo "Backups created:"
    for file in "${BACKUP_FILES[@]}"; do
        echo "  - $file"
    done
fi
echo ""
echo "To activate changes, either:"
echo "  1. Restart your terminal"
if [ ${#UPDATED_FILES[@]} -eq 1 ]; then
    echo "  2. Run: source ${UPDATED_FILES[0]}"
else
    echo "  2. Run: source ~/.zshrc  (or source ~/.bashrc for bash)"
fi
echo ""
echo "Available commands:"
echo "  generate-skill (gen-skill)     - Create new Claude Code skills"
echo "  generate-agent (gen-agent)     - Create single senior architect agent"
echo "  generate-agents (gen-agents)   - Create full agent team (auto-detect stack)"
echo "  validate-skill (val-skill)     - Validate skill definitions"
echo ""
echo "Generator scripts are also available directly in PATH:"
echo "  generate_skill.py"
echo "  generate_senior_architect.py"
echo "  generate_agents.py"
echo "  validate_skill.py"
echo ""
echo "Usage examples:"
echo "  generate-skill my-skill --description 'Does something cool'"
echo "  generate-agent . --project-type 'Next.js TypeScript'"
echo "  generate-agents . --type all    # Auto-detect and create full team"
echo "  validate-skill ../claude-devkit/skills/my-skill/SKILL.md"
echo ""
