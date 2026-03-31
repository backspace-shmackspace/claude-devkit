#!/usr/bin/env bash
# scripts/emit-audit-event.sh
#
# Standalone helper script for audit event emission in /ship, /architect, /audit skills.
#
# Usage:
#   bash scripts/emit-audit-event.sh <state-file> <partial-event-json>
#   bash scripts/emit-audit-event.sh --help
#
# Arguments:
#   state-file          Path to the per-run state JSON file created at run start
#   partial-event-json  JSON object with event-specific fields (event_type required)
#
# Example:
#   bash scripts/emit-audit-event.sh ".ship-audit-state-abc123.json" \
#     '{"event_type":"step_start","step":"step_1_read_plan","step_name":"Coordinator reads plan"}'
#
# The state file must contain:
#   run_id, audit_log, skill, skill_version, security_maturity, hmac_key
#
# Design:
#   - Reads ALL state from the state file (no shell variables persist across Bash tool calls)
#   - Derives sequence from wc -l of the log file (stateless)
#   - Uses python3 json.dumps() for RFC 8259 compliant escaping
#   - Computes HMAC-SHA256 chain at L3 (security_maturity=audited)
#   - Checks for symlinks before writing (symlink attack prevention)
#   - Exits 0 on ALL error paths (never blocks /ship)
#   - Merges caller's partial event JSON with common fields

set -euo pipefail

# --help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
scripts/emit-audit-event.sh -- Audit event emission helper for Claude Code skills

Usage:
  bash scripts/emit-audit-event.sh <state-file> <partial-event-json>
  bash scripts/emit-audit-event.sh --help

Arguments:
  state-file          Path to per-run JSON state file (created at run start)
  partial-event-json  JSON object with event-specific fields

State file format:
  {
    "run_id": "20260327-143052-a1b2c3",
    "audit_log": "./plans/audit-logs/ship-20260327-143052-a1b2c3.jsonl",
    "skill": "ship",
    "skill_version": "3.6.0",
    "security_maturity": "advisory",
    "hmac_key": ""
  }

At L3 (security_maturity=audited), hmac_key should be a 64-char hex string.

Example:
  bash scripts/emit-audit-event.sh ".ship-audit-state-abc123.json" \
    '{"event_type":"step_start","step":"step_0_preflight","step_name":"Pre-flight checks"}'

Output:
  Appends one JSONL line to the audit log. Always exits 0.
  Errors and warnings are written to stderr only.
EOF
    exit 0
fi

# Validate arguments
if [[ $# -lt 2 ]]; then
    echo "Error: Missing arguments. Usage: $0 <state-file> <partial-event-json>" >&2
    echo "Run '$0 --help' for full usage." >&2
    exit 0  # Exit 0 always -- never block /ship
fi

STATE_FILE="$1"
PARTIAL_JSON="$2"

# --- Read state file ---
if [[ ! -f "$STATE_FILE" ]]; then
    echo "Warning: State file not found: $STATE_FILE. Audit event dropped." >&2
    exit 0
fi

# Parse state using python3 for reliability
# Pass STATE_FILE and field as sys.argv to avoid shell injection via string interpolation
read_state_field() {
    local field="$1"
    python3 - "$STATE_FILE" "$field" <<'PYEOF' 2>/dev/null || echo ""
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(d.get(sys.argv[2], ''), end='')
except Exception as e:
    sys.stderr.write('Warning: Could not parse state file: ' + str(e) + '\n')
    print('', end='')
PYEOF
}

RUN_ID=$(read_state_field "run_id")
AUDIT_LOG=$(read_state_field "audit_log")
SKILL=$(read_state_field "skill")
SKILL_VERSION=$(read_state_field "skill_version")
SECURITY_MATURITY=$(read_state_field "security_maturity")
HMAC_KEY=$(read_state_field "hmac_key")

# Validate required fields
if [[ -z "$RUN_ID" || -z "$AUDIT_LOG" ]]; then
    echo "Warning: State file missing required fields (run_id, audit_log). Audit event dropped." >&2
    exit 0
fi

# --- Ensure log directory exists ---
LOG_DIR=$(dirname "$AUDIT_LOG")
mkdir -p "$LOG_DIR" 2>/dev/null || true

# --- Symlink check (prevent symlink attack on predictable path) ---
if [[ -L "$AUDIT_LOG" ]]; then
    echo "Warning: Audit log path '$AUDIT_LOG' is a symlink. Refusing to write." >&2
    exit 0
fi

# --- Derive sequence counter from log file line count (stateless) ---
if [ -f "$AUDIT_LOG" ]; then
  SEQUENCE=$(( $(wc -l < "$AUDIT_LOG" | tr -d ' ') + 1 ))
else
  SEQUENCE=1
fi

# --- Generate timestamp ---
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

# --- JSON string escaping via python3 json.dumps ---
# Returns the escaped string (without surrounding quotes)
_escape() {
    local val="$1"
    python3 -c "
import json, sys
val = sys.argv[1]
# json.dumps produces \"value\" -- strip the surrounding quotes
escaped = json.dumps(val)[1:-1]
print(escaped, end='')
" "$val" 2>/dev/null || printf '%s' "$val"
}

# Escape common fields
RUN_ID_ESC=$(_escape "$RUN_ID")
SKILL_ESC=$(_escape "$SKILL")
SKILL_VERSION_ESC=$(_escape "$SKILL_VERSION")
SECURITY_MATURITY_ESC=$(_escape "$SECURITY_MATURITY")
TIMESTAMP_ESC=$(_escape "$TIMESTAMP")

# --- Build the complete event JSON ---
# Strategy: use python3 to merge common fields with the caller's partial event JSON
# This ensures correct JSON construction regardless of the partial event content.

FULL_EVENT=$(python3 -c "
import json, sys

# Parse the caller's partial event
try:
    partial = json.loads(sys.argv[1])
except json.JSONDecodeError as e:
    # If partial is not valid JSON, wrap it minimally
    sys.stderr.write('Warning: partial event JSON is invalid: ' + str(e) + '\n')
    partial = {}

# Common fields (override partial if key conflicts -- common fields are authoritative)
common = {
    'run_id': '${RUN_ID_ESC}',
    'timestamp': '${TIMESTAMP_ESC}',
    'skill': '${SKILL_ESC}',
    'skill_version': '${SKILL_VERSION_ESC}',
    'security_maturity': '${SECURITY_MATURITY_ESC}',
    'sequence': ${SEQUENCE}
}

# Merge: start with partial, then overlay common fields
merged = {**partial, **common}

# Output compact JSON (no trailing newline from json.dumps)
print(json.dumps(merged, separators=(',', ':')), end='')
" "$PARTIAL_JSON" 2>/dev/null)

# If python3 merging failed, fall back to minimal event
if [[ -z "$FULL_EVENT" ]]; then
    FULL_EVENT="{\"run_id\":\"${RUN_ID_ESC}\",\"timestamp\":\"${TIMESTAMP_ESC}\",\"skill\":\"${SKILL_ESC}\",\"skill_version\":\"${SKILL_VERSION_ESC}\",\"security_maturity\":\"${SECURITY_MATURITY_ESC}\",\"sequence\":${SEQUENCE},\"event_type\":\"unknown\",\"error\":\"event_construction_failed\"}"
fi

# --- L3: compute HMAC chain ---
if [[ -n "$HMAC_KEY" ]]; then
    # Read previous HMAC from last line of log file
    # Guard with file existence check to avoid pipefail-under-missing-file producing "genesisgenesis"
    if [[ -f "$AUDIT_LOG" ]]; then
        PREV_HMAC=$(tail -1 "$AUDIT_LOG" | python3 -c "
import json, sys
try:
    line = sys.stdin.read().strip()
    if line:
        event = json.loads(line)
        print(event.get('hmac', 'genesis'), end='')
    else:
        print('genesis', end='')
except Exception:
    print('genesis', end='')
" 2>/dev/null)
        [[ -z "$PREV_HMAC" ]] && PREV_HMAC="genesis"
    else
        PREV_HMAC="genesis"
    fi

    # Compute HMAC-SHA256(event_json + prev_hmac, key)
    HMAC=$(printf '%s' "${FULL_EVENT}${PREV_HMAC}" | openssl dgst -sha256 -hmac "$HMAC_KEY" 2>/dev/null | awk '{print $NF}')

    if [[ -n "$HMAC" ]]; then
        # Insert hmac field into event using python3
        FULL_EVENT=$(python3 -c "
import json, sys
event = json.loads(sys.argv[1])
event['hmac'] = sys.argv[2]
print(json.dumps(event, separators=(',', ':')), end='')
" "$FULL_EVENT" "$HMAC" 2>/dev/null || echo "$FULL_EVENT")
    else
        echo "Warning: HMAC computation failed (openssl unavailable?). L3 hmac field will be empty." >&2
        # Insert empty hmac field
        FULL_EVENT=$(python3 -c "
import json, sys
event = json.loads(sys.argv[1])
event['hmac'] = ''
print(json.dumps(event, separators=(',', ':')), end='')
" "$FULL_EVENT" 2>/dev/null || echo "$FULL_EVENT")
    fi
fi

# --- Append event to log file ---
printf '%s\n' "$FULL_EVENT" >> "$AUDIT_LOG" 2>/dev/null || {
    echo "Warning: Could not write to audit log '$AUDIT_LOG'. Disk full or permissions issue." >&2
}

# Always exit 0 -- never block /ship
exit 0
