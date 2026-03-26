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

    mkdir -p "$dst"
    cp "$src/SKILL.md" "$dst/SKILL.md"
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

    mkdir -p "$dst"
    cp "$src/SKILL.md" "$dst/SKILL.md"
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
Usage: deploy.sh [OPTIONS] [SKILL_NAME]

Options:
  (no args)                       Deploy all core skills from skills/
  <name>                          Deploy one core skill from skills/
  --contrib                       Deploy all contrib skills from contrib/
  --contrib <name>                Deploy one contrib skill from contrib/
  --all                           Deploy all core and contrib skills
  --undeploy <name>               Remove ~/.claude/skills/<name>/ (triggers permission prompt)
  --undeploy --contrib <name>     Remove ~/.claude/skills/<name>/ (same target, contrib context)
  --help, -h                      Show this help message

Examples:
  ./scripts/deploy.sh              # deploy all core skills
  ./scripts/deploy.sh architect        # deploy architect skill
  ./scripts/deploy.sh --contrib    # deploy all contrib skills
  ./scripts/deploy.sh --contrib journal  # deploy journal skill
  ./scripts/deploy.sh --all        # deploy everything
  ./scripts/deploy.sh --undeploy architect   # remove deployed architect skill
EOF
}

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
