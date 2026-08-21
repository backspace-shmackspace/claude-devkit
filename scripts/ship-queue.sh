#!/usr/bin/env bash
set -euo pipefail

# Sequential /ship runner — executes plans one at a time, ensuring a clean
# working tree between runs. Designed for unattended overnight execution.
#
# Usage:
#   bash scripts/ship-queue.sh <target-repo> <plan1.md> [plan2.md] ...
#
# Example:
#   bash scripts/ship-queue.sh ~/projects/claude-devkit \
#     .devkit/plans/plan1.md .devkit/plans/plan2.md
#
# Each plan runs via `devkit ship <target> <plan>`. If a run fails or
# leaves the tree dirty, the script stops — subsequent plans are skipped
# rather than risk a cascade of failures.

LOG_DIR=".devkit/plans/audit-logs"
mkdir -p "$LOG_DIR"
QUEUE_LOG="$LOG_DIR/ship-queue-$(date +%Y%m%d-%H%M%S).log"

log() { printf '[%s] %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$*" | tee -a "$QUEUE_LOG"; }

if [ $# -lt 2 ]; then
  echo "Usage: bash scripts/ship-queue.sh <target-repo> <plan1.md> [plan2.md] ..."
  exit 1
fi

TARGET="$1"
shift

TOTAL=$#
COMPLETED=0
FAILED=0

log "Ship queue started: $TOTAL plan(s)"
for plan in "$@"; do log "  - $plan"; done
log "---"

for plan in "$@"; do
  IDX=$((COMPLETED + FAILED + 1))
  log "[$IDX/$TOTAL] Starting: $plan"

  # Gate: working tree must be clean
  if [ -n "$(git -C "$TARGET" status --porcelain 2>/dev/null)" ]; then
    log "ABORT: Working tree is not clean. Skipping $plan and all remaining plans."
    log "Dirty files:"
    git -C "$TARGET" status --porcelain | tee -a "$QUEUE_LOG"
    FAILED=$((TOTAL - COMPLETED))
    break
  fi

  # Gate: plan file must exist and be approved (resolve relative to target)
  PLAN_PATH="$TARGET/$plan"
  if [ ! -f "$PLAN_PATH" ]; then
    log "SKIP: $plan does not exist."
    FAILED=$((FAILED + 1))
    continue
  fi
  if ! grep -q 'Status: APPROVED' "$PLAN_PATH" 2>/dev/null; then
    log "SKIP: $plan is not approved."
    FAILED=$((FAILED + 1))
    continue
  fi

  RUN_LOG="$LOG_DIR/ship-queue-run-${IDX}-$(date +%H%M%S).log"
  log "Executing: devkit ship $TARGET $plan"
  log "Run log: $RUN_LOG"

  # Run /ship via devkit (delegates to claude --print)
  set +e
  devkit ship "$TARGET" "$plan" > "$RUN_LOG" 2>&1
  EXIT_CODE=$?
  set -e

  if [ $EXIT_CODE -ne 0 ]; then
    log "FAILED (exit $EXIT_CODE): $plan — see $RUN_LOG"
    FAILED=$((FAILED + 1))
    # Check if tree is still clean enough to continue
    if [ -n "$(git -C "$TARGET" status --porcelain 2>/dev/null)" ]; then
      log "ABORT: Working tree left dirty after failure. Skipping remaining plans."
      FAILED=$((TOTAL - COMPLETED))
      break
    fi
    log "Working tree still clean — continuing to next plan."
    continue
  fi

  # Post-run: verify the tree is clean (ship should have committed)
  if [ -n "$(git -C "$TARGET" status --porcelain 2>/dev/null)" ]; then
    log "WARNING: /ship exited 0 but left uncommitted changes."
    log "Attempting auto-cleanup: stashing leftover changes."
    git -C "$TARGET" stash push -u -m "ship-queue: leftover from $plan" 2>&1 | tee -a "$QUEUE_LOG"
  fi

  COMPLETED=$((COMPLETED + 1))
  log "DONE [$COMPLETED/$TOTAL]: $plan"
  log "---"
done

log "========================================"
log "Ship queue finished"
log "  Completed: $COMPLETED / $TOTAL"
log "  Failed/Skipped: $FAILED"
log "  Log: $QUEUE_LOG"
log "========================================"

exit $FAILED
