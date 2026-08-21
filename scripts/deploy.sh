#!/usr/bin/env bash
# Deploy skills from claude-devkit to ~/.claude/skills/
# Usage: ./scripts/deploy.sh [OPTIONS] [SKILL_NAME]
#   ./scripts/deploy.sh              # deploy all core skills
#   ./scripts/deploy.sh architect        # deploy one core skill
#   ./scripts/deploy.sh --contrib    # deploy all contrib skills
#   ./scripts/deploy.sh --contrib journal  # deploy one contrib skill
#   ./scripts/deploy.sh --all        # deploy core + contrib skills
#   ./scripts/deploy.sh --help       # show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$REPO_DIR/skills"
CONTRIB_DIR="$REPO_DIR/contrib"
DEPLOY_DIR="$HOME/.claude/skills"

# --- Helper script deployment (zero-project-footprint) ----------------------
# Skills reference these via $DEVKIT_SCRIPTS or $HOME/.claude-devkit/scripts/
# (absolute paths) instead of relative scripts/ paths, so they work without
# $CLAUDE_DEVKIT being set. Deployed alongside skills so the CLI and skills
# always ship from the same release (see plan "Atomic Deployment Requirement":
# CLI changes and skill updates must be deployed together, or skills can fall
# through to deprecated/mismatched path resolution).
HELPER_SCRIPTS_DIR="$HOME/.claude-devkit/scripts"
HELPER_SCRIPTS=(
    "emit-audit-event.sh"
    "compute-run-score.sh"
    "codebase-scanner.py"
    "score-reflector.sh"
    "scanner-value-report.sh"
    "audit-log-query.sh"
    "resolve-project-dir.sh"
)

sha256_of() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        echo "ERROR: no SHA-256 tool found (need sha256sum or shasum)" >&2
        return 1
    fi
}

# Deploys helper scripts to ~/.claude-devkit/scripts/ with 0o500 (read+exec,
# no write) permissions and records SHA-256 checksums in .checksums.json.
# Fails atomically: if any script is missing or fails to copy, everything
# copied during this invocation is rolled back and the function returns
# non-zero (deploy.sh then aborts under `set -euo pipefail`).
deploy_helper_scripts() {
    mkdir -p "$HELPER_SCRIPTS_DIR"
    chmod 700 "$HELPER_SCRIPTS_DIR"

    local deployed_files=()
    local checksums_tmp
    checksums_tmp="$(mktemp "${TMPDIR:-/tmp}/devkit-checksums.XXXXXX")" || {
        echo "ERROR: Cannot create temp file for checksums" >&2
        return 1
    }

    local first=1
    echo "{" > "$checksums_tmp"

    for script in "${HELPER_SCRIPTS[@]}"; do
        local src="$REPO_DIR/scripts/$script"
        if [ ! -f "$src" ]; then
            echo "ERROR: Helper script '$script' not found at $src" >&2
            rm -f "$checksums_tmp"
            for f in "${deployed_files[@]}"; do rm -f "$f"; done
            return 1
        fi

        local dst="$HELPER_SCRIPTS_DIR/$script"
        local dst_tmp
        dst_tmp="$(mktemp "$HELPER_SCRIPTS_DIR/.deploy.XXXXXX")" || {
            echo "ERROR: Cannot create temp file for $script" >&2
            rm -f "$checksums_tmp"
            for f in "${deployed_files[@]}"; do rm -f "$f"; done
            return 1
        }

        if ! cp "$src" "$dst_tmp"; then
            echo "ERROR: Failed to copy $script" >&2
            rm -f "$checksums_tmp" "$dst_tmp"
            for f in "${deployed_files[@]}"; do rm -f "$f"; done
            return 1
        fi

        local checksum
        if ! checksum="$(sha256_of "$dst_tmp")"; then
            rm -f "$checksums_tmp" "$dst_tmp"
            for f in "${deployed_files[@]}"; do rm -f "$f"; done
            return 1
        fi

        chmod 500 "$dst_tmp"
        mv -f "$dst_tmp" "$dst"
        deployed_files+=("$dst")

        if [ "$first" -eq 1 ]; then
            first=0
        else
            echo "," >> "$checksums_tmp"
        fi
        printf '  "%s": "%s"' "$script" "$checksum" >> "$checksums_tmp"
    done

    {
        echo ""
        echo "}"
    } >> "$checksums_tmp"

    chmod 600 "$checksums_tmp"
    mv -f "$checksums_tmp" "$HELPER_SCRIPTS_DIR/.checksums.json"

    echo "Deployed ${#HELPER_SCRIPTS[@]} helper script(s) to $HELPER_SCRIPTS_DIR (0o500, checksums recorded)"
}

validate_skill_name() {
    local skill="$1"
    if [[ "$skill" == */* ]] || [[ "$skill" == *..* ]] || [[ "$skill" == -* ]]; then
        echo "ERROR: Invalid skill name: '$skill' (must not contain '/', '..', or start with '-')" >&2
        return 1
    fi
    return 0
}

deploy_skill() {
    local skill="$1"
    validate_skill_name "$skill" || return 1
    local src="$SKILLS_DIR/$skill"
    local dst="$DEPLOY_DIR/$skill"

    if [ ! -d "$src" ]; then
        echo "ERROR: Skill '$skill' not found in $src" >&2
        return 1
    fi

    if [ "$VALIDATE" -eq 1 ]; then
        if ! python3 "$REPO_DIR/generators/validate_skill.py" "$src/SKILL.md"; then
            echo "ERROR: Validation failed for '$skill'. Skipping deployment." >&2
            echo "  Run: python3 generators/validate_skill.py $src/SKILL.md" >&2
            return 1
        fi
    fi

    mkdir -p "$dst"
    cp "$src/SKILL.md" "$dst/SKILL.md"
    if [ -d "$src/reference" ]; then
        rm -rf "$dst/reference"
        cp -r "$src/reference" "$dst/reference"
    fi
    echo "Deployed: $skill"
}

deploy_contrib_skill() {
    local skill="$1"
    validate_skill_name "$skill" || return 1
    local src="$CONTRIB_DIR/$skill"
    local dst="$DEPLOY_DIR/$skill"

    if [ ! -d "$src" ]; then
        echo "ERROR: Contrib skill '$skill' not found in $src" >&2
        return 1
    fi

    if [ "$VALIDATE" -eq 1 ]; then
        if ! python3 "$REPO_DIR/generators/validate_skill.py" "$src/SKILL.md"; then
            echo "ERROR: Validation failed for '$skill'. Skipping deployment." >&2
            echo "  Run: python3 generators/validate_skill.py $src/SKILL.md" >&2
            return 1
        fi
    fi

    mkdir -p "$dst"
    cp "$src/SKILL.md" "$dst/SKILL.md"
    if [ -d "$src/reference" ]; then
        rm -rf "$dst/reference"
        cp -r "$src/reference" "$dst/reference"
    fi
    echo "Deployed (contrib): $skill"
}

undeploy_skill() {
    local skill="$1"
    validate_skill_name "$skill" || return 1

    local target="$DEPLOY_DIR/$skill"

    if [ ! -d "$target" ]; then
        echo "WARN: Skill '$skill' not found at $target (already undeployed?)" >&2
        return 0
    fi

    # NOTE: rm -rf is not in the Claude Code global allowlist (~/.claude/settings.json)
    # and will trigger an interactive permission prompt. This is expected behavior.
    rm -rf "$target"
    echo "Undeployed: $skill (removed $target)"
}

deploy_all_core() {
    if [ ! -d "$SKILLS_DIR" ]; then
        echo "ERROR: Skills directory not found at $SKILLS_DIR" >&2
        echo "Note: claude-devkit may not have a skills/ directory yet." >&2
        exit 1
    fi

    local deployed=0
    for skill_dir in "$SKILLS_DIR"/*/; do
        if [ -d "$skill_dir" ]; then
            skill="$(basename "$skill_dir")"
            deploy_skill "$skill"
            deployed=$((deployed + 1))
        fi
    done

    if [ $deployed -eq 0 ]; then
        echo "No skills found in $SKILLS_DIR"
        exit 1
    fi

    echo "All core skills deployed to $DEPLOY_DIR"
}

deploy_all_contrib() {
    if [ ! -d "$CONTRIB_DIR" ]; then
        echo "No contrib directory found at $CONTRIB_DIR" >&2
        return 0
    fi

    local deployed=0
    for skill_dir in "$CONTRIB_DIR"/*/; do
        if [ -d "$skill_dir" ] && [ -f "$skill_dir/SKILL.md" ]; then
            skill="$(basename "$skill_dir")"
            deploy_contrib_skill "$skill"
            deployed=$((deployed + 1))
        fi
    done

    if [ $deployed -eq 0 ]; then
        echo "No contrib skills found in $CONTRIB_DIR"
        return 0
    fi

    echo "All contrib skills deployed to $DEPLOY_DIR"
}

show_help() {
    cat <<EOF
Usage: deploy.sh [--validate] [OPTIONS] [SKILL_NAME]

Options:
  (no args)                       Deploy all core skills from skills/
  <name>                          Deploy one core skill from skills/
  --contrib                       Deploy all contrib skills from contrib/
  --contrib <name>                Deploy one contrib skill from contrib/
  --all                           Deploy all core and contrib skills
  --validate                      Validate each skill before deploying (blocks on failure)
  --undeploy <name>               Remove ~/.claude/skills/<name>/ (triggers permission prompt)
  --undeploy --contrib <name>     Remove ~/.claude/skills/<name>/ (same target, contrib context)
  --help, -h                      Show this help message

Examples:
  ./scripts/deploy.sh              # deploy all core skills
  ./scripts/deploy.sh architect        # deploy architect skill
  ./scripts/deploy.sh --contrib    # deploy all contrib skills
  ./scripts/deploy.sh --contrib journal  # deploy journal skill
  ./scripts/deploy.sh --all        # deploy everything
  ./scripts/deploy.sh --validate                    # validate + deploy all core skills
  ./scripts/deploy.sh --validate architect          # validate + deploy one core skill
  ./scripts/deploy.sh --validate --all              # validate + deploy core + contrib
  ./scripts/deploy.sh --validate --contrib          # validate + deploy all contrib
  ./scripts/deploy.sh --validate --contrib journal  # validate + deploy one contrib skill
  ./scripts/deploy.sh --undeploy architect   # remove deployed architect skill
EOF
}

# Pre-processing loop: extract --validate before the case statement
VALIDATE=0
ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--validate" ]; then
        VALIDATE=1
    else
        ARGS+=("$arg")
    fi
done
set -- "${ARGS[@]}"

# Deploy helper scripts alongside skills for every action that actually
# installs or refreshes something (skip --help and --undeploy, which don't
# touch skill content). This is the "atomic deployment" enforcement from the
# plan: the CLI-facing helper scripts and the skills that depend on them
# (ship, architect, audit, etc.) are kept in lockstep on every deploy run.
case "${1:-}" in
    --help|-h|--undeploy)
        ;;
    *)
        deploy_helper_scripts || exit 1
        ;;
esac

# Argument parsing
case "${1:-}" in
    --contrib)
        if [ $# -ge 2 ]; then
            # Reject flags passed as skill names
            if [[ "${2:-}" == -* ]]; then
                echo "ERROR: Invalid skill name: $2" >&2
                exit 1
            fi
            deploy_contrib_skill "$2"
        else
            deploy_all_contrib
        fi
        ;;
    --all)
        deploy_all_core
        deploy_all_contrib
        ;;
    --undeploy)
        if [ $# -lt 2 ]; then
            echo "ERROR: --undeploy requires a skill name" >&2
            echo "Usage: deploy.sh --undeploy <skill-name>" >&2
            echo "       deploy.sh --undeploy --contrib <skill-name>" >&2
            exit 1
        fi
        if [[ "$2" == "--contrib" ]]; then
            if [ $# -lt 3 ]; then
                echo "ERROR: --undeploy --contrib requires a skill name" >&2
                exit 1
            fi
            undeploy_skill "$3"
        else
            undeploy_skill "$2"
        fi
        ;;
    --help|-h)
        show_help
        exit 0
        ;;
    "")
        deploy_all_core
        ;;
    -*)
        echo "ERROR: Unknown flag: $1" >&2
        echo "Run './scripts/deploy.sh --help' for usage." >&2
        exit 1
        ;;
    *)
        deploy_skill "$1"
        ;;
esac
