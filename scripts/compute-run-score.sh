#!/usr/bin/env bash
# scripts/compute-run-score.sh
#
# Compute quantitative scores for a completed skill run.
#
# Usage:
#   bash scripts/compute-run-score.sh <audit-log-file>
#   bash scripts/compute-run-score.sh --help
#
# Input:
#   Path to a JSONL audit log file (must contain run_start event;
#   run_end is optional -- scoring works on partial logs)
#
# Output:
#   Partial event JSON suitable for passing to emit-audit-event.sh:
#   {"event_type":"run_score","dimensions":[...],"composite":0.78,"velocity_minutes":12.3}
#
# Exit codes:
#   0 = success (JSON written to stdout)
#   0 = any error (writes warning to stderr, outputs neutral-score JSON to stdout)
#       Never exits non-zero -- follows emit-audit-event.sh convention.
#
# Dependencies: python3
# NOT a dependency: jq (all computation is python3)

set -uo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# --help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
scripts/compute-run-score.sh -- Compute quantitative scores for a skill run

Usage:
  bash scripts/compute-run-score.sh <audit-log-file>
  bash scripts/compute-run-score.sh --help

Input:
  Path to a JSONL audit log file. Scoring works on partial logs (run_end
  is not required). Handles empty, incomplete, and malformed logs gracefully
  by returning neutral (0.5) scores for dimensions with no data.

Output (to stdout):
  Partial event JSON for emit-audit-event.sh:
  {"event_type":"run_score","dimensions":[...],"composite":0.78,"velocity_minutes":12.3}

Dimensions:
  efficiency  Derived from count of code_review verdict events.
              1 verdict = 0 revision rounds = 1.0
              2 verdicts = 1 revision round  = 0.6
              3 verdicts = 2 revision rounds = 0.2
              Formula: max(0.0, 1.0 - (count - 1) * 0.4)
              No code_review events: 0.5 (neutral)

  security    Derived from security_decision events.
              Start 1.0. BLOCKED: -0.3, PASS_WITH_NOTES: -0.1, floor 0.0.
              No security events: 0.5 (neutral)

  quality     Derived from verdict events (code_review + qa).
              Start 1.0. CR REVISION_NEEDED: -0.3, CR FAIL: -0.5.
              QA PASS_WITH_NOTES: -0.1, QA FAIL: -0.5, floor 0.0.
              No verdict events: 0.5 (neutral)

  velocity    Wall-clock duration in minutes (informational, not in composite).
              Computed from run_start.timestamp to current time.

Composite:
  Weighted sum of efficiency, security, quality (each weight 0.3333).
  Velocity is excluded from composite.

Exit codes:
  Always 0 -- follows emit-audit-event.sh convention. Errors go to stderr.

Dependencies: python3
NOT a dependency: jq
EOF
    exit 0
fi

LOG_FILE="${1:-}"

# Emit neutral scores and exit 0 (non-blocking fallback)
emit_neutral() {
    local reason="${1:-Unknown error}"
    echo "Warning: ${SCRIPT_NAME}: ${reason}. Emitting neutral scores." >&2
    python3 -c "
import json
neutral = {
    'event_type': 'run_score',
    'dimensions': [
        {'name': 'efficiency', 'score': 0.5, 'weight': 0.3333, 'details': 'Neutral (no data)'},
        {'name': 'security',   'score': 0.5, 'weight': 0.3333, 'details': 'Neutral (no data)'},
        {'name': 'quality',    'score': 0.5, 'weight': 0.3333, 'details': 'Neutral (no data)'}
    ],
    'composite': 0.5
}
print(json.dumps(neutral))
" 2>/dev/null || echo '{"event_type":"run_score","dimensions":[{"name":"efficiency","score":0.5,"weight":0.3333,"details":"Neutral (no data)"},{"name":"security","score":0.5,"weight":0.3333,"details":"Neutral (no data)"},{"name":"quality","score":0.5,"weight":0.3333,"details":"Neutral (no data)"}],"composite":0.5}'
    exit 0
}

# Validate argument
if [[ -z "$LOG_FILE" ]]; then
    emit_neutral "No audit log file specified"
fi

if [[ ! -f "$LOG_FILE" ]]; then
    emit_neutral "Audit log file not found: ${LOG_FILE}"
fi

# Run the scoring logic in python3
python3 - "$LOG_FILE" <<'PYEOF'
import json
import sys
from datetime import datetime, timezone

log_path = sys.argv[1]

# 1. Parse all events from the JSONL file
events = []
try:
    with open(log_path, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError as e:
                print(f"Warning: skipping malformed JSONL line {line_num}: {e}", file=sys.stderr)
                continue
except Exception as e:
    print(f"Warning: could not read log file: {e}", file=sys.stderr)
    # Output neutral scores
    neutral = {
        'event_type': 'run_score',
        'dimensions': [
            {'name': 'efficiency', 'score': 0.5, 'weight': 0.3333, 'details': 'Neutral (read error)'},
            {'name': 'security',   'score': 0.5, 'weight': 0.3333, 'details': 'Neutral (read error)'},
            {'name': 'quality',    'score': 0.5, 'weight': 0.3333, 'details': 'Neutral (read error)'}
        ],
        'composite': 0.5
    }
    print(json.dumps(neutral))
    sys.exit(0)

dimensions = []

# 2. Efficiency: count code_review verdict events to derive revision rounds.
# Step 4 emits one code_review verdict per pass. Step 5 re-runs Step 4 per
# revision round. So: 1 verdict = 0 rounds, 2 verdicts = 1 round, 3 = 2 rounds.
code_review_verdicts = [
    e for e in events
    if e.get('event_type') == 'verdict'
    and e.get('verdict_source') == 'code_review'
]
verdict_count = len(code_review_verdicts)

if verdict_count == 0:
    # No code review ran -> no revision data -> neutral
    efficiency_score = 0.5
    efficiency_details = "No code review events found (neutral)"
else:
    revision_count = verdict_count - 1  # first verdict is Step 4 initial pass, not a revision
    efficiency_score = max(0.0, 1.0 - revision_count * 0.4)
    efficiency_details = f"{revision_count} revision round(s) ({verdict_count} code_review verdict(s))"

dimensions.append({
    "name": "efficiency",
    "score": round(efficiency_score, 4),
    "weight": 0.3333,
    "details": efficiency_details
})

# 3. Security: score from security_decision events
security_events = [e for e in events if e.get('event_type') == 'security_decision']
if not security_events:
    security_score = 0.5  # Neutral: no security gates ran
    security_details = "No security gates ran (neutral)"
else:
    security_score = 1.0
    for se in security_events:
        gate_verdict = se.get('gate_verdict', '')
        if gate_verdict == 'BLOCKED':
            security_score -= 0.3
        elif gate_verdict == 'PASS_WITH_NOTES':
            security_score -= 0.1
    security_score = max(0.0, security_score)
    gate_summary = []
    for se in security_events:
        gate = se.get('gate', 'unknown')
        gv = se.get('gate_verdict', 'unknown')
        gate_summary.append(f"{gate}:{gv}")
    security_details = "; ".join(gate_summary)

dimensions.append({
    "name": "security",
    "score": round(security_score, 4),
    "weight": 0.3333,
    "details": security_details
})

# 4. Quality: score from verdict events (code_review + qa)
verdict_events = [e for e in events if e.get('event_type') == 'verdict']
cr_verdicts = [e for e in verdict_events if e.get('verdict_source') == 'code_review']
qa_verdicts = [e for e in verdict_events if e.get('verdict_source') == 'qa']

quality_score = 1.0
quality_parts = []

if cr_verdicts:
    # Use the first code review verdict (pre-revision quality signal).
    # Rationale: the first verdict reflects the coder's unrevised output.
    # Post-revision verdicts are captured by the efficiency dimension.
    first_cr = cr_verdicts[0]
    cr_verdict_val = first_cr.get('verdict', '')
    if cr_verdict_val == 'REVISION_NEEDED':
        quality_score -= 0.3
        quality_parts.append("code_review:REVISION_NEEDED")
    elif cr_verdict_val == 'FAIL':
        quality_score -= 0.5
        quality_parts.append("code_review:FAIL")
    else:
        quality_parts.append(f"code_review:{cr_verdict_val}")

if qa_verdicts:
    last_qa = qa_verdicts[-1]  # Final QA verdict (post-fix result)
    qa_verdict_val = last_qa.get('verdict', '')
    if qa_verdict_val == 'PASS_WITH_NOTES':
        quality_score -= 0.1
        quality_parts.append("qa:PASS_WITH_NOTES")
    elif qa_verdict_val == 'FAIL':
        quality_score -= 0.5
        quality_parts.append("qa:FAIL")
    else:
        quality_parts.append(f"qa:{qa_verdict_val}")

if not quality_parts:
    quality_score = 0.5  # Neutral
    quality_details = "No verdict events found (neutral)"
else:
    quality_score = max(0.0, quality_score)
    quality_details = "; ".join(quality_parts)

dimensions.append({
    "name": "quality",
    "score": round(quality_score, 4),
    "weight": 0.3333,
    "details": quality_details
})

# 5. Velocity (informational, not in composite)
# run_score is emitted BEFORE run_end, so we use current time as end marker.
run_starts = [e for e in events if e.get('event_type') == 'run_start']
run_ends = [e for e in events if e.get('event_type') == 'run_end']
velocity_minutes = None

if run_starts:
    start_ts = run_starts[0].get('timestamp')
    if run_ends:
        end_ts = run_ends[0].get('timestamp')
    else:
        # run_score is emitted before run_end -- use current time
        end_ts = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z')

    if start_ts and end_ts:
        try:
            def parse_ts(ts):
                return datetime.fromisoformat(ts.replace('Z', '+00:00'))
            t0 = parse_ts(start_ts)
            t1 = parse_ts(end_ts)
            velocity_minutes = round((t1 - t0).total_seconds() / 60, 1)
        except Exception as e:
            print(f"Warning: could not compute velocity: {e}", file=sys.stderr)

# 6. Composite: weighted sum of scored dimensions only (velocity has weight 0.0)
scored = [d for d in dimensions if d['weight'] > 0]
total_weight = sum(d['weight'] for d in scored)
if total_weight > 0:
    composite = sum(d['score'] * d['weight'] / total_weight for d in scored)
else:
    composite = 0.5
composite = round(composite, 4)

# 7. Output partial event JSON for emit-audit-event.sh
result = {
    "event_type": "run_score",
    "dimensions": dimensions,
    "composite": composite
}
if velocity_minutes is not None:
    result["velocity_minutes"] = velocity_minutes

print(json.dumps(result))
PYEOF

# Capture python3 exit code (set -uo pipefail may surface it)
PYTHON_EXIT=$?
if [[ $PYTHON_EXIT -ne 0 ]]; then
    emit_neutral "python3 scoring script exited with code ${PYTHON_EXIT}"
fi

exit 0
