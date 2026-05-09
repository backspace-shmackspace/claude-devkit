#!/usr/bin/env bash
# scripts/score-reflector.sh
#
# Deterministic score reflector -- analyzes score history and generates
# candidate learnings entries.
#
# Usage:
#   bash scripts/score-reflector.sh [--min-runs N] [--format md|json]
#   bash scripts/score-reflector.sh --help
#
# Reads all run_score events from plans/audit-logs/*.jsonl
# Computes per-dimension statistics and trends
# Outputs candidate learnings entries to stdout (never writes to .claude/learnings.md)
#
# Options:
#   --min-runs N    Minimum runs required for any analysis (default: 5)
#   --format md     Output as markdown learnings entries (default)
#   --format json   Output as structured JSON
#
# Analysis levels:
#   < min-runs:    "Insufficient data" message, exit 0
#   5-9 runs:      Summary statistics only (mean, min, max per dimension)
#   10+ runs:      Summary statistics + trend analysis (linear regression)
#
# Dependencies: python3
# NOT a dependency: jq
#
# Note: At L1 (advisory) maturity, audit logs are gitignored and ephemeral.
# Trend data is limited to logs still on disk. For meaningful cross-session
# trend analysis, use L2 or L3 maturity.

set -uo pipefail

# --help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
scripts/score-reflector.sh -- Deterministic score reflector for candidate learnings

Usage:
  bash scripts/score-reflector.sh [--min-runs N] [--format md|json]
  bash scripts/score-reflector.sh --help

Options:
  --min-runs N    Minimum scored runs required for analysis (default: 5)
  --format md     Output as markdown learnings entries (default)
  --format json   Output as structured JSON

Analysis levels:
  < min-runs:   "Insufficient data" message (exit 0)
  5-9 runs:     Summary statistics only: per-dimension mean, min, max
  10+ runs:     Summary statistics + linear regression trend detection

Trend detection (10+ runs only):
  Degrading dimensions: negative slope, magnitude > 0.05 per run
  Chronically low:      mean < 0.5 over 10+ runs
  High revision rate:   efficiency mean < 0.7
  Override frequency:   security overrides counted from security_decision events
  Composite drop:       composite mean of last 5 < previous 5 by > 0.1

Data sources:
  Reads all run_score events from plans/audit-logs/*.jsonl
  Output is to stdout only -- never writes to .claude/learnings.md
  Human reviews and copies relevant entries to learnings.md

Note: At L1 (advisory) maturity, audit logs are gitignored and ephemeral.
Trend data is limited to logs still on disk. For cross-session analysis,
use L2 or L3 maturity (logs are committed to git).

Exit codes:
  Always 0 -- never blocks caller. Errors go to stderr.

Dependencies: python3
NOT a dependency: jq
EOF
    exit 0
fi

# Parse arguments
MIN_RUNS=5
FORMAT="md"
AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-./plans/audit-logs}"

while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        --min-runs)
            MIN_RUNS="${2:-5}"
            shift 2
            ;;
        --format)
            FORMAT="${2:-md}"
            shift 2
            ;;
        --help|-h)
            # Already handled above
            exit 0
            ;;
        *)
            echo "Warning: Unknown argument '${1}'. Ignoring." >&2
            shift
            ;;
    esac
done

# Validate format
if [[ "$FORMAT" != "md" && "$FORMAT" != "json" ]]; then
    echo "Warning: Unknown format '${FORMAT}'. Defaulting to 'md'." >&2
    FORMAT="md"
fi

# Run the reflector in python3
python3 - "$AUDIT_LOG_DIR" "$MIN_RUNS" "$FORMAT" <<'PYEOF'
import json
import sys
import os
import glob
from datetime import datetime, timezone

audit_log_dir = sys.argv[1]
min_runs = int(sys.argv[2])
output_format = sys.argv[3]
today = datetime.now(timezone.utc).strftime('%Y-%m-%d')

# --- Collect all run_score events across all JSONL files ---
score_events = []
log_files = sorted(glob.glob(os.path.join(audit_log_dir, '*.jsonl')))

if not log_files:
    print(f"Note: No audit log files found in {audit_log_dir}/")
    print("Run /ship to generate scored runs first.")
    sys.exit(0)

# Check if any logs are gitignored (L1 ephemeral limitation notice)
l1_notice = False
try:
    import subprocess
    result = subprocess.run(
        ['git', 'check-ignore', '--quiet'] + log_files[:1],
        capture_output=True, cwd=os.getcwd()
    )
    if result.returncode == 0:
        l1_notice = True
except Exception:
    pass

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
    except Exception as e:
        print(f"Warning: could not read {log_file}: {e}", file=sys.stderr)
        continue

# Also collect security_decision events for override counting
all_security_decisions = []
for log_file in log_files:
    try:
        with open(log_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                    if event.get('event_type') == 'security_decision':
                        event['_log_file'] = log_file
                        all_security_decisions.append(event)
                except json.JSONDecodeError:
                    continue
    except Exception:
        continue

# Sort score events by timestamp
def parse_ts(ts):
    try:
        return datetime.fromisoformat(ts.replace('Z', '+00:00'))
    except Exception:
        return datetime.min.replace(tzinfo=timezone.utc)

score_events.sort(key=lambda e: parse_ts(e.get('timestamp', '')))

num_runs = len(score_events)

# --- Insufficient data path ---
if num_runs < min_runs:
    print(f"Insufficient data: {num_runs} scored run(s) found, need at least {min_runs}.")
    print(f"Run /ship at least {min_runs - num_runs} more time(s) to enable score analysis.")
    if l1_notice:
        print("")
        print("Note: L1 (advisory) logs are not committed to git. Trend data is limited to")
        print("logs still on disk. For cross-session analysis, use L2 or L3 maturity.")
    sys.exit(0)

# --- Extract dimension scores ---
def get_dim_scores(events, dim_name):
    """Extract list of scores for a named dimension across events."""
    scores = []
    for e in events:
        for d in e.get('dimensions', []):
            if d.get('name') == dim_name:
                scores.append(d.get('score', 0.5))
                break
    return scores

def get_composite_scores(events):
    return [e.get('composite', 0.5) for e in events]

# Dimensions to analyze (excluding velocity which has weight 0)
dim_names = ['efficiency', 'security', 'quality']

dim_data = {}
for dim in dim_names:
    scores = get_dim_scores(score_events, dim)
    dim_data[dim] = {
        'scores': scores,
        'mean': sum(scores) / len(scores) if scores else 0.5,
        'min': min(scores) if scores else 0.5,
        'max': max(scores) if scores else 0.5,
    }

composite_scores = get_composite_scores(score_events)
composite_data = {
    'scores': composite_scores,
    'mean': sum(composite_scores) / len(composite_scores) if composite_scores else 0.5,
    'min': min(composite_scores) if composite_scores else 0.5,
    'max': max(composite_scores) if composite_scores else 0.5,
}

# --- Linear regression (for 10+ runs) ---
def linear_regression(values):
    """Returns (slope, intercept) for a list of values (x = index 0..n-1)."""
    n = len(values)
    if n < 2:
        return 0.0, values[0] if values else 0.5
    x_mean = (n - 1) / 2.0
    y_mean = sum(values) / n
    numerator = sum((i - x_mean) * (v - y_mean) for i, v in enumerate(values))
    denominator = sum((i - x_mean) ** 2 for i in range(n))
    if denominator == 0:
        return 0.0, y_mean
    slope = numerator / denominator
    intercept = y_mean - slope * x_mean
    return slope, intercept

# Count override runs
override_runs = set()
for sd in all_security_decisions:
    if sd.get('action') == 'override':
        override_runs.add(sd.get('_log_file', ''))
override_count = len(override_runs)

# Revision loop rate (efficiency: how many runs had at least one revision round)
revision_runs = 0
for e in score_events:
    for d in e.get('dimensions', []):
        if d.get('name') == 'efficiency':
            # A revision round occurred if score < 1.0 and score != 0.5 (neutral)
            s = d.get('score', 0.5)
            if s < 1.0 and s != 0.5:
                revision_runs += 1
            break

# --- Format output ---

if output_format == 'json':
    output = {
        'analyzed_runs': num_runs,
        'date': today,
        'l1_notice': l1_notice,
        'dimensions': {},
        'composite': composite_data,
        'override_count': override_count,
        'revision_runs': revision_runs,
    }
    for dim in dim_names:
        d = dim_data[dim].copy()
        d['mean'] = round(d['mean'], 3)
        d['min'] = round(d['min'], 3)
        d['max'] = round(d['max'], 3)
        if num_runs >= 10:
            slope, _ = linear_regression(d['scores'])
            d['trend_slope'] = round(slope, 4)
        output['dimensions'][dim] = d
    print(json.dumps(output, indent=2))
    sys.exit(0)

# --- Markdown output ---

if l1_notice:
    print("Note: L1 (advisory) logs are not committed to git. Trend data is limited to")
    print("logs still on disk. For meaningful cross-session analysis, use L2 or L3 maturity.")
    print("")

if num_runs < 10:
    # Summary statistics only (5-9 runs)
    print(f"## Score Summary ({num_runs} runs analyzed)")
    print("")
    print("Note: Trend analysis requires 10+ runs. Showing summary statistics only.")
    print("")
    print(f"| {'Dimension':<10} | {'Mean':>6} | {'Min':>6} | {'Max':>6} |")
    print(f"|{'-'*12}|{'-'*8}|{'-'*8}|{'-'*8}|")
    for dim in dim_names:
        d = dim_data[dim]
        print(f"| {dim:<10} | {d['mean']:>6.3f} | {d['min']:>6.3f} | {d['max']:>6.3f} |")
    c = composite_data
    print(f"| {'composite':<10} | {c['mean']:>6.3f} | {c['min']:>6.3f} | {c['max']:>6.3f} |")
    print("")

    # Identify lowest dimension
    lowest_dim = min(dim_names, key=lambda d: dim_data[d]['mean'])
    lowest_mean = dim_data[lowest_dim]['mean']
    print(f"Lowest dimension: {lowest_dim} (mean {lowest_mean:.3f}).", end="")
    if lowest_dim == 'efficiency':
        pct = round(revision_runs / num_runs * 100)
        print(f" {revision_runs}/{num_runs} runs entered the revision loop.")
    else:
        print("")

    if override_count > 0:
        pct = round(override_count / num_runs * 100)
        print(f"Security overrides used in {override_count}/{num_runs} runs ({pct}%).")

else:
    # Full analysis: summary + trends (10+ runs)
    print(f"## Candidate Learnings from Score Analysis ({num_runs} runs analyzed)")
    print("")

    # Summary table
    print(f"### Summary Statistics")
    print("")
    print(f"| {'Dimension':<10} | {'Mean':>6} | {'Min':>6} | {'Max':>6} | {'Trend (slope/run)':>18} |")
    print(f"|{'-'*12}|{'-'*8}|{'-'*8}|{'-'*8}|{'-'*20}|")
    slopes = {}
    for dim in dim_names:
        d = dim_data[dim]
        slope, _ = linear_regression(d['scores'])
        slopes[dim] = slope
        trend_str = f"{slope:+.4f}"
        print(f"| {dim:<10} | {d['mean']:>6.3f} | {d['min']:>6.3f} | {d['max']:>6.3f} | {trend_str:>18} |")
    c = composite_data
    c_slope, _ = linear_regression(c['scores'])
    print(f"| {'composite':<10} | {c['mean']:>6.3f} | {c['min']:>6.3f} | {c['max']:>6.3f} | {c_slope:>+18.4f} |")
    print("")

    # Candidate learnings
    findings = []

    # Efficiency: high revision rate
    eff_mean = dim_data['efficiency']['mean']
    if eff_mean < 0.7:
        revision_pct = round(revision_runs / num_runs * 100)
        eff_slope = slopes['efficiency']
        first_score = dim_data['efficiency']['scores'][0]
        last_score = dim_data['efficiency']['scores'][-1]
        trend_note = ""
        if abs(eff_slope) > 0.05:
            direction = "downward" if eff_slope < 0 else "upward"
            trend_note = f" Efficiency score trending {direction} ({first_score:.2f} -> {last_score:.2f} over {num_runs} runs, slope {eff_slope:+.3f}/run)."
        findings.append({
            'section': 'Coder Patterns > Missed by coders, caught by reviewers',
            'text': (
                f"**[{today}] Revision loop rate is high ({revision_pct}%)** [Medium] -- "
                f"{revision_runs}/{num_runs} runs required at least one revision round."
                f"{trend_note} Common: code review REVISION_NEEDED on first pass. "
                f"Consider: are plan acceptance criteria clear enough for coders to self-verify before review?"
                f"\n  #coder #efficiency #revision-loop ({today})"
            )
        })

    # Security: declining trend
    sec_slope = slopes['security']
    sec_mean = dim_data['security']['mean']
    if sec_slope < -0.05 or sec_mean < 0.5:
        first_score = dim_data['security']['scores'][0]
        last_score = dim_data['security']['scores'][-1]
        override_pct = round(override_count / num_runs * 100) if num_runs > 0 else 0
        severity = "High" if sec_mean < 0.5 else "Medium"
        text = f"**[{today}] Security score is "
        if sec_slope < -0.05:
            text += f"declining** [{severity}] -- Security dimension trending downward ({first_score:.2f} -> {last_score:.2f}, slope {sec_slope:+.3f}/run)."
        else:
            text += f"chronically low** [{severity}] -- Mean security score {sec_mean:.3f} across {num_runs} runs."
        if override_count > 0:
            text += f" --security-override used in {override_count}/{num_runs} runs ({override_pct}%)."
        text += " Review whether security gate findings are actionable or represent false positives that should be tuned."
        text += f"\n  #security #trend ({today})"
        findings.append({
            'section': 'Security Patterns',
            'text': text
        })
    elif override_count > 0 and override_count >= num_runs // 4:
        override_pct = round(override_count / num_runs * 100)
        findings.append({
            'section': 'Security Patterns',
            'text': (
                f"**[{today}] Security override usage is notable** [Medium] -- "
                f"{override_count}/{num_runs} runs ({override_pct}%) used --security-override. "
                f"Review whether secure-review findings are actionable or represent false positives that should be tuned."
                f"\n  #security #override ({today})"
            )
        })

    # Quality: declining trend or chronically low
    qual_slope = slopes['quality']
    qual_mean = dim_data['quality']['mean']
    if qual_slope < -0.05 or qual_mean < 0.5:
        first_score = dim_data['quality']['scores'][0]
        last_score = dim_data['quality']['scores'][-1]
        severity = "High" if qual_mean < 0.5 else "Medium"
        text = f"**[{today}] Quality score is "
        if qual_slope < -0.05:
            text += f"declining** [{severity}] -- Quality dimension trending downward ({first_score:.2f} -> {last_score:.2f}, slope {qual_slope:+.3f}/run)."
        else:
            text += f"chronically low** [{severity}] -- Mean quality score {qual_mean:.3f} across {num_runs} runs."
        text += " Consider reviewing coder agent prompts, plan acceptance criteria, or test coverage."
        text += f"\n  #quality #trend ({today})"
        findings.append({
            'section': 'QA Patterns > Coverage gaps',
            'text': text
        })

    # Composite drop: last 5 vs previous 5
    if num_runs >= 10 and len(composite_scores) >= 10:
        last5 = composite_scores[-5:]
        prev5 = composite_scores[-10:-5]
        last5_mean = sum(last5) / 5
        prev5_mean = sum(prev5) / 5
        if prev5_mean - last5_mean > 0.1:
            findings.append({
                'section': 'Coder Patterns > Missed by coders, caught by reviewers',
                'text': (
                    f"**[{today}] Overall quality declining** [High] -- "
                    f"Composite score mean of last 5 runs ({last5_mean:.3f}) is more than 0.1 below "
                    f"previous 5 runs ({prev5_mean:.3f}). "
                    f"Review recent changes to codebase, security posture, or plan quality."
                    f"\n  #composite #quality #trend ({today})"
                )
            })

    if not findings:
        print("No significant patterns detected.")
        print("")
        print(f"All dimension means are above 0.5 and no trend slopes exceed 0.05/run.")
        print(f"Continue current practices. Re-run score-reflector.sh after more /ship runs.")
    else:
        # Group findings by section
        sections = {}
        for f in findings:
            sec = f['section']
            if sec not in sections:
                sections[sec] = []
            sections[sec].append(f['text'])

        for section, texts in sections.items():
            print(f"### {section}")
            print("")
            for text in texts:
                print(f"- {text}")
            print("")

print(f"(Composite scores are most useful for trend analysis across runs.)")
PYEOF

PYTHON_EXIT=$?
if [[ $PYTHON_EXIT -ne 0 ]]; then
    echo "Warning: score-reflector.sh: python3 exited with code ${PYTHON_EXIT}" >&2
fi

exit 0
