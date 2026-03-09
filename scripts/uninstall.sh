#!/usr/bin/env bash
# Uninstall claude-devkit from shell environment
# Removes PATH additions and aliases
# Works on Linux and macOS with both bash and zsh

set -euo pipefail

# Detect user's shell and return appropriate RC file(s)
detect_rc_files() {
    local rc_files=()

    # Check common RC files that might have claude-devkit installed
    for file in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
        if [ -f "$file" ] && grep -q "# claude-devkit PATH" "$file" 2>/dev/null; then
            rc_files+=("$file")
        fi
    done

    printf '%s\n' "${rc_files[@]}"
}

# Get RC files to clean
mapfile -t RC_FILES < <(detect_rc_files)

echo "Uninstalling claude-devkit..."

# Check if installed anywhere
if [ ${#RC_FILES[@]} -eq 0 ]; then
    echo "claude-devkit does not appear to be installed"
    echo "Nothing to uninstall."
    exit 0
fi

echo "Found claude-devkit in ${#RC_FILES[@]} file(s):"
for rc in "${RC_FILES[@]}"; do
    echo "  - $rc"
done
echo ""

CLEANED_FILES=()
BACKUP_FILES=()

# Process each RC file
for RC_FILE in "${RC_FILES[@]}"; do
    BACKUP_FILE="${RC_FILE}.claude-devkit-uninstall-backup-$(date +%Y%m%d-%H%M%S)"

    # Backup before modification
    cp "$RC_FILE" "$BACKUP_FILE"
    echo "Backed up $RC_FILE to $BACKUP_FILE"
    BACKUP_FILES+=("$BACKUP_FILE")

    # Create temporary file without claude-devkit section
    TEMP_FILE=$(mktemp)

    # Remove claude-devkit section (from "# claude-devkit PATH" to end of aliases)
    # Note: Pattern matches last alias (val-skill) to know when section ends
    awk '
    /# claude-devkit PATH/ {
        skip = 1
        next
    }
    skip && /^alias (val-skill|gen-agents)=/ {
        skip = 0
        next
    }
    !skip {
        print
    }
    ' "$RC_FILE" > "$TEMP_FILE"

    # Replace original file
    mv "$TEMP_FILE" "$RC_FILE"
    CLEANED_FILES+=("$RC_FILE")
    echo "✅ Cleaned $RC_FILE"
done

echo ""
echo "✅ Uninstallation complete!"
echo ""
if [ ${#CLEANED_FILES[@]} -gt 0 ]; then
    echo "Removed claude-devkit from:"
    for file in "${CLEANED_FILES[@]}"; do
        echo "  - $file"
    done
fi
echo ""
echo "Backups saved:"
for file in "${BACKUP_FILES[@]}"; do
    echo "  - $file"
done
echo ""
echo "To restore previous configuration, copy any backup over the current file."
echo ""
echo "To apply changes:"
echo "  1. Restart your terminal, or"
echo "  2. Run: source ~/.zshrc  (or source ~/.bashrc for bash)"
echo ""
