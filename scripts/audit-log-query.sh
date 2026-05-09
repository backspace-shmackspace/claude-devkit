#!/usr/bin/env bash
# scripts/audit-log-query.sh
#
# Query utility for Claude Devkit audit logs (JSONL format).
# Requires: jq
#
# Usage:
#   ./scripts/audit-log-query.sh <command> [options]
#   ./scripts/audit-log-query.sh --help
#
# Commands:
#   summary <run_id>         Show run summary (outcome, steps, timestamps)
#   verdicts <run_id>        Show all verdict events for a run
#   security <run_id>        Show security decisions for a run
#   files <run_id>           Show all file modifications for a run
#   overrides [--all]        Show all security overrides across runs
#   timeline <run_id>        Show step-by-step timeline (duration computed from timestamp pairs)
#   verify-chain <run_id>    Verify L3 HMAC chain integrity
#   recent [N]               Show N most recent runs (default 10)
#   scores <run_id>          Show per-dimension scores for a run
#   trend [N] [--dimension name]  Show composite score trend for last N runs (default 10)

set -uo pipefail

AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-./plans/audit-logs}"

# --help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || -z "${1:-}" ]]; then
    cat <<'EOF'
scripts/audit-log-query.sh -- Query utility for Claude Devkit JSONL audit logs

Usage:
  ./scripts/audit-log-query.sh <command> [options]

Commands:
  summary <run_id>              Show run summary (skill, outcome, timestamps, step count)
  verdicts <run_id>             Show all verdict events for a run
  security <run_id>             Show all security_decision events for a run
  files <run_id>                Show all file_modification events for a run
  overrides [--all]             Show security overrides (recent run only, or --all runs)
  timeline <run_id>             Show step timeline with computed durations from timestamp pairs
  verify-chain <run_id>         Verify L3 HMAC chain integrity using .ship-audit-key-<run_id>
  recent [N]                    Show N most recent runs across all skills (default: 10)
  scores <run_id>               Show per-dimension scores for a scored run
  trend [N] [--dimension name]  Show composite score trend for last N runs (default: 10)

Environment:
  AUDIT_LOG_DIR            Directory containing .jsonl files (default: ./plans/audit-logs)

Options for verify-chain:
  --key <keyfile>          Path to HMAC key file (default: .ship-audit-key-<run_id>)

Examples:
  # Show summary for a specific run
  ./scripts/audit-log-query.sh summary 20260327-143052-a1b2c3

  # Show timeline with computed step durations
  ./scripts/audit-log-query.sh timeline 20260327-143052-a1b2c3

  # Verify L3 HMAC chain
  ./scripts/audit-log-query.sh verify-chain 20260327-143052-a1b2c3

  # Show 5 most recent runs
  ./scripts/audit-log-query.sh recent 5

  # Show all security overrides across all runs
  ./scripts/audit-log-query.sh overrides --all

  # Show per-dimension scores for a run
  ./scripts/audit-log-query.sh scores 20260327-143052-a1b2c3

  # Show composite score trend for last 10 runs
  ./scripts/audit-log-query.sh trend

  # Show efficiency trend for last 5 runs
  ./scripts/audit-log-query.sh trend 5 --dimension efficiency

Notes:
  - Requires jq for all commands
  - Requires openssl for verify-chain command
  - L1 logs are gitignored and ephemeral; L2/L3 logs are committed to git
  - Duration in timeline is computed from step_start/step_end timestamp pairs
  - Composite scores are most useful for trend analysis across runs
EOF
    exit 0
fi

# Check for jq dependency
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required for audit log queries." >&2
    echo "Install: brew install jq  (macOS) or  apt-get install jq  (Linux)" >&2
    exit 1
fi

COMMAND="${1:-}"
shift || true

# --- Helper: find log file for a run_id ---
find_log() {
    local run_id="$1"
    # Search all skills: ship-*, architect-*, audit-*
    local log_file
    log_file=$(ls -1 "${AUDIT_LOG_DIR}/"*"-${run_id}.jsonl" 2>/dev/null | head -1)
    if [[ -z "$log_file" ]]; then
        echo "Error: No audit log found for run_id '${run_id}' in ${AUDIT_LOG_DIR}/" >&2
        echo "Available logs:" >&2
        ls -1 "${AUDIT_LOG_DIR}/"*.jsonl 2>/dev/null | head -10 >&2 || echo "  (none)" >&2
        return 1
    fi
    echo "$log_file"
}

# --- Helper: ISO 8601 to unix seconds (requires python3 or date) ---
iso_to_epoch() {
    local ts="$1"
    python3 -c "
import datetime
ts = '${ts}'.replace('Z', '+00:00')
try:
    dt = datetime.datetime.fromisoformat(ts)
    print(int(dt.timestamp()))
except Exception:
    print(0)
" 2>/dev/null || echo "0"
}

# --- summary ---
cmd_summary() {
    local run_id="${1:-}"
    if [[ -z "$run_id" ]]; then
        echo "Usage: $0 summary <run_id>" >&2
        exit 1
    fi

    local log_file
    log_file=$(find_log "$run_id") || exit 1

    echo "=== Audit Run Summary ==="
    echo "Log file: $log_file"
    echo ""

    # Extract run_start
    local run_start
    run_start=$(grep '"event_type":"run_start"' "$log_file" | head -1)
    if [[ -n "$run_start" ]]; then
        echo "--- Run Start ---"
        echo "$run_start" | jq '{
            skill: .skill,
            skill_version: .skill_version,
            security_maturity: .security_maturity,
            plan_file: .plan_file,
            security_override_active: .security_override_active,
            timestamp: .timestamp
        }'
    else
        echo "WARNING: No run_start event found (log may be incomplete)"
    fi

    # Extract run_end
    local run_end
    run_end=$(grep '"event_type":"run_end"' "$log_file" | tail -1)
    if [[ -n "$run_end" ]]; then
        echo ""
        echo "--- Run End ---"
        echo "$run_end" | jq '{
            outcome: .outcome,
            steps_completed: .steps_completed,
            revision_rounds: .revision_rounds,
            commit_sha: .commit_sha,
            timestamp: .timestamp
        }'
    else
        echo "WARNING: No run_end event found (run may not have completed)"
    fi

    # Event counts
    echo ""
    echo "--- Event Counts ---"
    local total step_starts verdicts security_decisions file_mods errors
    total=$(wc -l < "$log_file" | tr -d ' ')
    step_starts=$(grep -c '"event_type":"step_start"' "$log_file" 2>/dev/null || echo 0)
    verdicts=$(grep -c '"event_type":"verdict"' "$log_file" 2>/dev/null || echo 0)
    security_decisions=$(grep -c '"event_type":"security_decision"' "$log_file" 2>/dev/null || echo 0)
    file_mods=$(grep -c '"event_type":"file_modification"' "$log_file" 2>/dev/null || echo 0)
    errors=$(grep -c '"event_type":"error"' "$log_file" 2>/dev/null || echo 0)
    echo "Total events:       $total"
    echo "Steps executed:     $step_starts"
    echo "Verdict gates:      $verdicts"
    echo "Security decisions: $security_decisions"
    echo "File modifications: $file_mods"
    echo "Errors:             $errors"
}

# --- verdicts ---
cmd_verdicts() {
    local run_id="${1:-}"
    if [[ -z "$run_id" ]]; then
        echo "Usage: $0 verdicts <run_id>" >&2
        exit 1
    fi

    local log_file
    log_file=$(find_log "$run_id") || exit 1

    echo "=== Verdict Events for run ${run_id} ==="
    echo ""
    grep '"event_type":"verdict"' "$log_file" | jq -r '[.timestamp, .step, .verdict, .verdict_source, (.artifact // "")] | @tsv' | \
        awk 'BEGIN{printf "%-25s %-30s %-20s %-20s %s\n","TIMESTAMP","STEP","VERDICT","SOURCE","ARTIFACT"}
             {printf "%-25s %-30s %-20s %-20s %s\n",$1,$2,$3,$4,$5}' || \
        grep '"event_type":"verdict"' "$log_file" | jq '.'
}

# --- security ---
cmd_security() {
    local run_id="${1:-}"
    if [[ -z "$run_id" ]]; then
        echo "Usage: $0 security <run_id>" >&2
        exit 1
    fi

    local log_file
    log_file=$(find_log "$run_id") || exit 1

    local count
    count=$(grep -c '"event_type":"security_decision"' "$log_file" 2>/dev/null || echo 0)
    echo "=== Security Decisions for run ${run_id} (${count} events) ==="
    echo ""

    if [[ "$count" -eq 0 ]]; then
        echo "(No security_decision events found -- security gates may not have run)"
        return
    fi

    grep '"event_type":"security_decision"' "$log_file" | jq '{
        timestamp: .timestamp,
        step: .step,
        gate: .gate,
        gate_verdict: .gate_verdict,
        action: .action,
        effective_verdict: .effective_verdict,
        override_reason: .override_reason
    }'
}

# --- files ---
cmd_files() {
    local run_id="${1:-}"
    if [[ -z "$run_id" ]]; then
        echo "Usage: $0 files <run_id>" >&2
        exit 1
    fi

    local log_file
    log_file=$(find_log "$run_id") || exit 1

    echo "=== File Modifications for run ${run_id} ==="
    echo ""

    local count
    count=$(grep -c '"event_type":"file_modification"' "$log_file" 2>/dev/null || echo 0)
    if [[ "$count" -eq 0 ]]; then
        echo "(No file_modification events found)"
        return
    fi

    grep '"event_type":"file_modification"' "$log_file" | jq -r '"Work Group " + (.work_group // "?" | tostring) + ": " + (.work_group_name // "Unknown"), (.files_modified // [] | .[] | "  - " + .)'
}

# --- overrides ---
cmd_overrides() {
    local all_flag="${1:-}"
    echo "=== Security Overrides ==="
    echo ""

    local pattern
    if [[ "$all_flag" == "--all" ]]; then
        pattern="${AUDIT_LOG_DIR}/*.jsonl"
    else
        # Most recent log only
        pattern=$(ls -t "${AUDIT_LOG_DIR}/"*.jsonl 2>/dev/null | head -1)
        if [[ -z "$pattern" ]]; then
            echo "(No audit logs found in ${AUDIT_LOG_DIR}/)"
            return
        fi
        echo "(Showing most recent run. Use --all for all runs.)"
        echo ""
    fi

    local found=0
    # shellcheck disable=SC2086
    for log_file in $pattern; do
        [[ -f "$log_file" ]] || continue
        local overrides
        overrides=$(grep '"event_type":"security_decision"' "$log_file" | jq -r 'select(.action == "override") | [.timestamp, .gate, .gate_verdict, (.override_reason // "(no reason)")] | @tsv' 2>/dev/null || true)
        if [[ -n "$overrides" ]]; then
            echo "File: $log_file"
            echo "$overrides" | awk 'BEGIN{printf "  %-25s %-20s %-10s %s\n","TIMESTAMP","GATE","VERDICT","OVERRIDE_REASON"}
                                      {printf "  %-25s %-20s %-10s %s\n",$1,$2,$3,$4}'
            echo ""
            found=$((found + 1))
        fi
    done

    if [[ "$found" -eq 0 ]]; then
        echo "(No security overrides found)"
    fi
}

# --- timeline ---
cmd_timeline() {
    local run_id="${1:-}"
    if [[ -z "$run_id" ]]; then
        echo "Usage: $0 timeline <run_id>" >&2
        exit 1
    fi

    local log_file
    log_file=$(find_log "$run_id") || exit 1

    echo "=== Step Timeline for run ${run_id} ==="
    echo "(Duration computed from step_start/step_end timestamp pairs)"
    echo ""

    # Use python3 to compute durations from timestamp pairs
    python3 -c "
import json
import datetime
import sys

log_file = '${log_file}'

# Read all events
events = []
with open(log_file) as f:
    for line in f:
        line = line.strip()
        if line:
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                pass

# Build step_start/step_end pairs
starts = {}
for e in events:
    if e.get('event_type') == 'step_start' and 'step' in e:
        starts[e['step']] = e['timestamp']

# Print timeline
print(f'{'STEP':<35} {'START':<25} {'END':<25} {'DURATION':>10}')
print('-' * 100)

for e in events:
    if e.get('event_type') == 'step_end' and 'step' in e:
        step = e['step']
        end_ts = e['timestamp']
        start_ts = starts.get(step)
        step_name = e.get('step_name', '')

        if start_ts:
            try:
                def parse_ts(ts):
                    return datetime.datetime.fromisoformat(ts.replace('Z', '+00:00'))
                start_dt = parse_ts(start_ts)
                end_dt = parse_ts(end_ts)
                duration_sec = (end_dt - start_dt).total_seconds()
                if duration_sec < 60:
                    duration_str = f'{duration_sec:.1f}s'
                else:
                    duration_str = f'{duration_sec/60:.1f}m'
            except Exception:
                duration_str = '?'
        else:
            start_ts = '(no start event)'
            duration_str = '?'

        label = step if not step_name else f'{step} ({step_name})'
        if len(label) > 34:
            label = label[:31] + '...'
        print(f'{label:<35} {start_ts:<25} {end_ts:<25} {duration_str:>10}')
" 2>/dev/null || {
        echo "Error computing timeline. Check that log file contains step_start/step_end pairs." >&2
        grep '"event_type":"step_start"\|"event_type":"step_end"' "$log_file" | jq '{event_type, step, timestamp}'
    }
}

# --- verify-chain ---
cmd_verify_chain() {
    local run_id="${1:-}"
    local key_arg="${2:-}"
    local key_file_arg="${3:-}"

    if [[ -z "$run_id" ]]; then
        echo "Usage: $0 verify-chain <run_id> [--key <keyfile>]" >&2
        exit 1
    fi

    local log_file
    log_file=$(find_log "$run_id") || exit 1

    # Determine key file
    local key_file
    if [[ "$key_arg" == "--key" && -n "$key_file_arg" ]]; then
        key_file="$key_file_arg"
    else
        # Auto-discover key file: check common prefixes
        local skill
        skill=$(basename "$log_file" | sed 's/-[0-9]\{8\}.*//')
        key_file=".${skill}-audit-key-${run_id}"
        if [[ ! -f "$key_file" ]]; then
            key_file=".ship-audit-key-${run_id}"
        fi
    fi

    echo "=== HMAC Chain Verification for run ${run_id} ==="
    echo "Log file: $log_file"
    echo "Key file: $key_file"
    echo ""

    if [[ ! -f "$key_file" ]]; then
        echo "ERROR: Key file not found: $key_file"
        echo "Verification is not possible (key may have been deleted or this is not an L3 run)."
        echo ""
        echo "Check if this run used L3 (audited) security maturity:"
        grep '"event_type":"run_start"' "$log_file" | jq '.security_maturity'
        exit 1
    fi

    if ! command -v openssl >/dev/null 2>&1; then
        echo "ERROR: openssl is required for HMAC chain verification." >&2
        exit 1
    fi

    local hmac_key
    hmac_key=$(cat "$key_file")

    if [[ -z "$hmac_key" ]]; then
        echo "ERROR: Key file is empty: $key_file"
        exit 1
    fi

    echo "Replaying HMAC chain..."
    echo ""

    python3 -c "
import json
import subprocess
import sys

log_file = '${log_file}'
hmac_key = '${hmac_key}'

events = []
with open(log_file) as f:
    for line in f:
        line = line.strip()
        if line:
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError as e:
                print(f'WARNING: Invalid JSON on line {len(events)+1}: {e}')
                events.append(None)

if not events:
    print('ERROR: No events found in log file.')
    sys.exit(1)

prev_hmac = 'genesis'
errors = 0
warnings = 0

for i, event in enumerate(events):
    seq = i + 1
    if event is None:
        print(f'  [{seq:3d}] SKIP (invalid JSON)')
        warnings += 1
        continue

    stored_hmac = event.get('hmac', '')
    if not stored_hmac:
        print(f'  [{seq:3d}] {event.get(\"event_type\",\"?\"):<20} SKIP (no hmac field -- not L3)')
        warnings += 1
        prev_hmac = 'genesis'  # Reset chain for non-L3 events
        continue

    # Recompute: remove hmac field from event copy, serialize, then compute
    event_copy = {k: v for k, v in event.items() if k != 'hmac'}
    event_json = json.dumps(event_copy, separators=(',', ':'))

    # Compute HMAC-SHA256(event_json + prev_hmac, key)
    try:
        result = subprocess.run(
            ['openssl', 'dgst', '-sha256', '-hmac', hmac_key],
            input=(event_json + prev_hmac).encode(),
            capture_output=True
        )
        computed = result.stdout.decode().strip().split()[-1]
    except Exception as e:
        print(f'  [{seq:3d}] {event.get(\"event_type\",\"?\"):<20} ERROR computing HMAC: {e}')
        errors += 1
        continue

    if computed == stored_hmac:
        print(f'  [{seq:3d}] {event.get(\"event_type\",\"?\"):<20} OK  {stored_hmac[:16]}...')
        prev_hmac = stored_hmac
    else:
        print(f'  [{seq:3d}] {event.get(\"event_type\",\"?\"):<20} MISMATCH!')
        print(f'        stored:   {stored_hmac}')
        print(f'        computed: {computed}')
        errors += 1
        # Update prev_hmac to continue chain verification from this point
        prev_hmac = stored_hmac

print()
if errors == 0 and warnings == 0:
    print(f'Chain verification: PASS ({len(events)} events verified)')
    sys.exit(0)
elif errors == 0:
    print(f'Chain verification: PASS with warnings ({len(events)} events, {warnings} skipped)')
    sys.exit(0)
else:
    print(f'Chain verification: FAIL ({errors} HMAC mismatches, {warnings} warnings)')
    sys.exit(1)
" 2>/dev/null || {
        echo "Error running chain verification." >&2
        exit 1
    }
}

# --- recent ---
cmd_recent() {
    local n="${1:-10}"
    echo "=== ${n} Most Recent Audit Runs ==="
    echo ""

    # List all JSONL files, sort by modification time
    local logs
    logs=$(ls -t "${AUDIT_LOG_DIR}/"*.jsonl 2>/dev/null | head -"$n")

    if [[ -z "$logs" ]]; then
        echo "(No audit logs found in ${AUDIT_LOG_DIR}/)"
        echo "Logs are created by /ship, /architect, and /audit skill runs."
        return
    fi

    printf "%-35s %-25s %-12s %-10s %s\n" "RUN_ID" "TIMESTAMP" "SKILL" "OUTCOME" "PLAN"
    echo "$(printf '%0.s-' {1..100})"

    while IFS= read -r log_file; do
        [[ -f "$log_file" ]] || continue
        local run_start run_end skill outcome plan ts run_id
        run_start=$(grep '"event_type":"run_start"' "$log_file" 2>/dev/null | head -1)
        run_end=$(grep '"event_type":"run_end"' "$log_file" 2>/dev/null | tail -1)

        if [[ -n "$run_start" ]]; then
            run_id=$(echo "$run_start" | jq -r '.run_id // "unknown"')
            skill=$(echo "$run_start" | jq -r '.skill // "unknown"')
            ts=$(echo "$run_start" | jq -r '.timestamp // "unknown"')
            plan=$(echo "$run_start" | jq -r '.plan_file // ""')
        else
            run_id=$(basename "$log_file" .jsonl)
            skill="unknown"
            ts="unknown"
            plan=""
        fi

        if [[ -n "$run_end" ]]; then
            outcome=$(echo "$run_end" | jq -r '.outcome // "incomplete"')
        else
            outcome="incomplete"
        fi

        printf "%-35s %-25s %-12s %-10s %s\n" "$run_id" "$ts" "$skill" "$outcome" "$plan"
    done <<< "$logs"
}

# --- scores ---
cmd_scores() {
    local run_id="${1:-}"
    if [[ -z "$run_id" ]]; then
        echo "Usage: $0 scores <run_id>" >&2
        exit 1
    fi

    local log_file
    log_file=$(find_log "$run_id") || exit 1

    echo "=== Run Scores for run ${run_id} ==="
    echo ""

    # Check if this log is gitignored (L1 ephemeral limitation notice)
    if git check-ignore --quiet "$log_file" 2>/dev/null; then
        echo "Note: L1 (advisory) logs are not committed to git. Trend data is limited to logs still on disk."
        echo ""
    fi

    # Extract run_score event
    local score_event
    score_event=$(grep '"event_type":"run_score"' "$log_file" 2>/dev/null | tail -1)

    if [[ -z "$score_event" ]]; then
        echo "(No run_score event found in this log.)"
        echo "Scores are emitted by /ship v3.8.0+ on the PASS path."
        echo "This run may predate scoring support or use an earlier skill version."
        return
    fi

    # Use python3 to format the score data
    python3 -c "
import json
import sys

event_json = '''${score_event}'''
try:
    event = json.loads(event_json)
except Exception as e:
    print(f'Error parsing run_score event: {e}', file=sys.stderr)
    sys.exit(1)

dims = event.get('dimensions', [])
composite = event.get('composite', 'N/A')
velocity = event.get('velocity_minutes')

print(f\"{'Dimension':<12} {'Score':>6} {'Weight':>7}  Details\")
print('-' * 80)
for d in dims:
    name = d.get('name', '?')
    score = d.get('score', 0.5)
    weight = d.get('weight', 0.0)
    details = d.get('details', '')
    weight_str = f'{weight:.4f}' if weight > 0 else '(info)'
    print(f\"{name:<12} {score:>6.4f} {weight_str:>7}  {details}\")

print('')
print(f'Composite score: {composite:.4f}')
if velocity is not None:
    print(f'Velocity:        {velocity:.1f} minutes (informational, not in composite)')
print('')
print('Composite scores are most useful for trend analysis across runs.')
" 2>/dev/null || {
        echo "Error formatting score data. Raw event:" >&2
        echo "$score_event" | jq '.'
    }
}

# --- trend ---
cmd_trend() {
    # Parse trend arguments: [N] [--dimension name]
    local n=10
    local dimension=""

    while [[ $# -gt 0 ]]; do
        case "${1:-}" in
            --dimension)
                dimension="${2:-}"
                shift 2
                ;;
            [0-9]*)
                n="$1"
                shift
                ;;
            *)
                echo "Warning: Unknown argument '${1}' for trend command. Ignoring." >&2
                shift
                ;;
        esac
    done

    echo "=== Score Trend (last ${n} scored runs${dimension:+, dimension: $dimension}) ==="
    echo ""

    # Check if logs are gitignored (L1 ephemeral limitation notice)
    local sample_log
    sample_log=$(ls -t "${AUDIT_LOG_DIR}/"*.jsonl 2>/dev/null | head -1)
    if [[ -n "$sample_log" ]] && git check-ignore --quiet "$sample_log" 2>/dev/null; then
        echo "Note: L1 (advisory) logs are not committed to git. Trend data is limited to logs still on disk."
        echo ""
    fi

    # Use python3 to aggregate run_score events across all JSONL files
    python3 -c "
import json
import os
import glob
import sys
from datetime import datetime, timezone

audit_log_dir = '${AUDIT_LOG_DIR}'
n = int('${n}')
dimension = '${dimension}'

# Collect all run_score events
score_events = []
log_files = sorted(glob.glob(os.path.join(audit_log_dir, '*.jsonl')))

for log_file in log_files:
    try:
        with open(log_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                    if event.get('event_type') == 'run_score':
                        event['_log_file'] = log_file
                        score_events.append(event)
                except json.JSONDecodeError:
                    continue
    except Exception:
        continue

if not score_events:
    print('No score data found.')
    print('Scores are emitted by /ship v3.8.0+ on the PASS path.')
    sys.exit(0)

# Sort by timestamp and take last N
def parse_ts(ts):
    try:
        return datetime.fromisoformat(ts.replace('Z', '+00:00'))
    except Exception:
        return datetime.min.replace(tzinfo=timezone.utc)

score_events.sort(key=lambda e: parse_ts(e.get('timestamp', '')))
recent = score_events[-n:]

if not dimension:
    # Show composite trend table
    print(f\"{'Run ID':<30} {'Timestamp':<25} {'Composite':>10} {'Efficiency':>11} {'Security':>10} {'Quality':>8}\")
    print('-' * 100)
    for e in recent:
        run_id = e.get('run_id', 'unknown')
        ts = e.get('timestamp', 'unknown')
        composite = e.get('composite', 0.5)
        dims = {d['name']: d['score'] for d in e.get('dimensions', [])}
        eff = dims.get('efficiency', 'N/A')
        sec = dims.get('security', 'N/A')
        qual = dims.get('quality', 'N/A')
        eff_str = f'{eff:.4f}' if isinstance(eff, float) else str(eff)
        sec_str = f'{sec:.4f}' if isinstance(sec, float) else str(sec)
        qual_str = f'{qual:.4f}' if isinstance(qual, float) else str(qual)
        print(f\"{run_id:<30} {ts:<25} {composite:>10.4f} {eff_str:>11} {sec_str:>10} {qual_str:>8}\")

    if len(recent) >= 2:
        composites = [e.get('composite', 0.5) for e in recent]
        mean_c = sum(composites) / len(composites)
        first = composites[0]
        last = composites[-1]
        print('')
        print(f'Mean composite: {mean_c:.4f}  |  First: {first:.4f}  |  Last: {last:.4f}  |  Delta: {last - first:+.4f}')
else:
    # Show single-dimension trend
    print(f\"{'Run ID':<30} {'Timestamp':<25} {dimension:>12}\")
    print('-' * 72)
    scores = []
    for e in recent:
        run_id = e.get('run_id', 'unknown')
        ts = e.get('timestamp', 'unknown')
        dim_score = None
        for d in e.get('dimensions', []):
            if d.get('name') == dimension:
                dim_score = d.get('score')
                break
        score_str = f'{dim_score:.4f}' if dim_score is not None else 'N/A'
        print(f\"{run_id:<30} {ts:<25} {score_str:>12}\")
        if dim_score is not None:
            scores.append(dim_score)

    if scores:
        mean_s = sum(scores) / len(scores)
        print('')
        print(f'Mean {dimension}: {mean_s:.4f}  |  Min: {min(scores):.4f}  |  Max: {max(scores):.4f}')

print('')
print('Composite scores are most useful for trend analysis across runs.')
" 2>/dev/null || {
        echo "Error computing score trend." >&2
    }
}

# --- Dispatch ---
case "$COMMAND" in
    summary)
        cmd_summary "${1:-}"
        ;;
    verdicts)
        cmd_verdicts "${1:-}"
        ;;
    security)
        cmd_security "${1:-}"
        ;;
    files)
        cmd_files "${1:-}"
        ;;
    overrides)
        cmd_overrides "${1:-}"
        ;;
    timeline)
        cmd_timeline "${1:-}"
        ;;
    verify-chain)
        cmd_verify_chain "${1:-}" "${2:-}" "${3:-}"
        ;;
    recent)
        cmd_recent "${1:-10}"
        ;;
    scores)
        cmd_scores "${1:-}"
        ;;
    trend)
        cmd_trend "$@"
        ;;
    *)
        echo "Error: Unknown command '${COMMAND}'" >&2
        echo "Run '$0 --help' for usage." >&2
        exit 1
        ;;
esac
