#!/usr/bin/env bash
# resolve-project-dir.sh -- reusable shell function for resolving the
# per-project devkit artifact directory at runtime.
#
# Part of the zero-project-footprint design: devkit artifacts (plans,
# audit logs, archives, state) never live inside the target project. This
# script implements the three-tier resolution described in
# .devkit/plans/zero-project-footprint.md:
#
#   1. DEVKIT_PROJECT_DIR env var (set by the `devkit` CLI) -- primary path
#   2. Computed from CWD (project ID = <sanitized-basename>-<sha256[:12]>)
#      when a devkit installation is detected but the env var isn't set --
#      the fallback for skills invoked directly in a Claude Code session
#   3. Legacy `.devkit` in CWD (deprecated, emits a warning) -- only when
#      no devkit installation is detected at all
#
# Usage (source, don't execute):
#   source "${DEVKIT_SCRIPTS:-$HOME/.claude-devkit/scripts}/resolve-project-dir.sh"
#   PROJECT_DIR=$(resolve_devkit_project_dir) || {
#     echo "Failed to resolve project directory" >&2
#     exit 1
#   }
#
# The Python one-liner below receives the CWD via sys.argv (not shell
# string interpolation), so directory names containing quotes, spaces, or
# other shell metacharacters cannot inject code -- see plan Security
# Requirements: Elevation of Privilege / Tampering sections.

resolve_devkit_project_dir() {
  if [ -n "${DEVKIT_PROJECT_DIR:-}" ]; then
    echo "$DEVKIT_PROJECT_DIR"
    return 0
  fi

  if [ -n "${CLAUDE_DEVKIT:-}" ] || [ -d "$HOME/.claude-devkit" ]; then
    local cwd
    cwd="$(pwd -P)"

    local project_id
    project_id=$(python3 -c "
import hashlib, os, sys, re

cwd = os.path.realpath(sys.argv[1])
basename = os.path.basename(cwd)
if not basename:
    print('project-' + hashlib.sha256(cwd.encode()).hexdigest()[:12])
    sys.exit(0)

sanitized = re.sub(r'[^a-zA-Z0-9._-]', '-', basename)
sanitized = re.sub(r'-+', '-', sanitized).strip('-')[:64] or 'project'

canonical = cwd.lower() if sys.platform in ('darwin', 'win32') else cwd
hash_val = hashlib.sha256(canonical.encode()).hexdigest()[:12]
print(f'{sanitized}-{hash_val}')
" "$cwd") || {
      echo "ERROR: failed to compute project ID from CWD" >&2
      return 1
    }

    local result="$HOME/.claude-devkit/projects/$project_id"

    # Defense-in-depth: verify the computed path is actually under
    # ~/.claude-devkit/projects/ before handing it back to a caller that
    # may mkdir -p or write into it (see plan Tampering / Elevation of
    # Privilege sections).
    case "$result" in
      "$HOME/.claude-devkit/projects/"*) ;;
      *)
        echo "ERROR: resolved project dir is outside ~/.claude-devkit/projects/" >&2
        return 1
        ;;
    esac

    echo "$result"
    return 0
  fi

  # Tier 3: deprecated legacy fallback. No devkit installation detected at
  # all -- scheduled for removal in v0.5.0 or 6 months post-release,
  # whichever is later (see plan Non-Goals).
  echo "WARNING: devkit is not installed. Using deprecated .devkit/ fallback." >&2
  echo "Install devkit (see CLAUDE.md) or set DEVKIT_PROJECT_DIR to use centralized artifact storage." >&2
  echo ".devkit"
  return 0
}

# Self-check when executed directly (not sourced): print the resolved path.
# This also serves as a lightweight integrity smoke test -- if the function
# above has been tampered with in a way that breaks basic execution, running
# this file directly will surface the error immediately instead of failing
# silently inside a sourcing skill.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  resolve_devkit_project_dir
fi
