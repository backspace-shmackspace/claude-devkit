#!/usr/bin/env bash
# scripts/scanner-value-report.sh
#
# Scanner value cohort comparison -- analyzes /ship run_score events grouped by
# scanner_mode (tree-sitter-partial, regex-fallback, absent) and reports whether
# scanner mode correlates with better outcomes.
#
# Usage:
#   bash scripts/scanner-value-report.sh [--format md|json] [--audit-log-dir PATH]
#   bash scripts/scanner-value-report.sh --help
#
# Reads run_score events from plans/audit-logs/ship-*.jsonl ONLY.
# /architect logs are excluded (they have no run_score events).
# Pre-instrumentation run_score events (missing scanner_mode) default to "absent".
#
# Options:
#   --format md         Output as markdown report (default)
#   --format json       Output as structured JSON
#   --audit-log-dir P   Override audit log directory (default: ./plans/audit-logs)
#
# Output sections (markdown):
#   Caveat               Observational data warning (always shown)
#   Cohort Summary       Per-cohort means for all dimensions
#   Token Cost           Mean/median token cost per cohort
#   Statistical Assessment  Sample sizes, confidence tier, Cohen's d
#   Correlations         Directional findings with correlational framing
#
# Dependencies: python3
# NOT a dependency: jq
#
# Note: At L1 (advisory) maturity, audit logs are gitignored and ephemeral.
# For meaningful cross-session analysis, use L2 or L3 maturity.
# Note: This is observational data. Correlations do NOT imply causation.

set -uo pipefail

# --help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
scripts/scanner-value-report.sh -- Scanner cohort comparison report

Usage:
  bash scripts/scanner-value-report.sh [--format md|json] [--audit-log-dir PATH]
  bash scripts/scanner-value-report.sh --help

Options:
  --format md         Output as markdown report (default)
  --format json       Output as structured JSON
  --audit-log-dir P   Override audit log directory (default: ./plans/audit-logs)

Reads:
  run_score events from plans/audit-logs/ship-*.jsonl ONLY
  /architect logs are excluded (no run_score events in architect logs)
  Pre-instrumentation events (missing scanner_mode) default to scanner_mode "absent"

Output (markdown):
  Caveat               Observational data warning -- always shown
  Cohort Summary       Per-cohort means: efficiency, security, quality, composite, velocity
  Token Cost           Mean and median output_token_count per cohort
  Statistical Assessment  Sample sizes, confidence tier (INSUFFICIENT/PRELIMINARY/RELIABLE/HIGH_CONFIDENCE),
                           Cohen's d effect size between cohorts
  Correlations         Directional findings in correlational language (never causal)

Confidence tiers (read from configs/scanner-value-thresholds.json):
  INSUFFICIENT    < 5 total runs: no analysis possible
  PRELIMINARY     5-14 total, >= 3 per cohort: directional signals only
  RELIABLE        15-29 total, >= 8 per non-empty cohort: reportable effect sizes
  HIGH_CONFIDENCE 30+ total, >= 15 per non-empty cohort: strong evidence with trend

Data notes:
  - Scanner mode comes from run_score.scanner_mode (added by compute-run-score.sh)
  - Events without scanner_mode are treated as scanner_mode="absent"
  - Token cost comes from run_score.scanner_tokens (0 if absent)
  - Cohort comparison is observational, not experimental
  - Confounders include developer skill, project type, plan complexity

Exit codes:
  Always 0 -- never blocks caller. Errors go to stderr.

Dependencies: python3
NOT a dependency: jq
EOF
    exit 0
fi

# Parse arguments
FORMAT="md"
AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-./plans/audit-logs}"

while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        --format)
            FORMAT="${2:-md}"
            shift 2
            ;;
        --audit-log-dir)
            AUDIT_LOG_DIR="${2:-./plans/audit-logs}"
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

# Locate thresholds config relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THRESHOLDS_FILE="${SCRIPT_DIR}/../configs/scanner-value-thresholds.json"

# Run the analysis in python3
python3 - "$AUDIT_LOG_DIR" "$FORMAT" "$THRESHOLDS_FILE" <<'PYEOF'
import json
import sys
import os
import glob
import math
from datetime import datetime, timezone

audit_log_dir = sys.argv[1]
output_format = sys.argv[2]
thresholds_file = sys.argv[3]
today = datetime.now(timezone.utc).strftime('%Y-%m-%d')

# ---------------------------------------------------------------------------
# Load confidence tier thresholds from config
# ---------------------------------------------------------------------------
def load_thresholds(path):
    """Load scanner-value-thresholds.json. Returns defaults on any error."""
    defaults = {
        "confidence_tiers": {
            "INSUFFICIENT": {"min_total_runs": 0, "max_total_runs": 4, "min_per_cohort": 0, "label": "Insufficient data"},
            "PRELIMINARY":  {"min_total_runs": 5, "max_total_runs": 14, "min_per_cohort": 3, "label": "Preliminary signal"},
            "RELIABLE":     {"min_total_runs": 15, "max_total_runs": 29, "min_per_cohort": 8, "label": "Reliable comparison"},
            "HIGH_CONFIDENCE": {"min_total_runs": 30, "min_per_cohort": 15, "label": "High confidence"},
        },
        "effect_size_thresholds": {"small": 0.10, "medium": 0.15, "large": 0.20},
    }
    try:
        with open(path, 'r') as f:
            data = json.load(f)
        return data
    except Exception as e:
        print(f"Warning: could not load thresholds from {path}: {e}. Using defaults.", file=sys.stderr)
        return defaults

thresholds = load_thresholds(thresholds_file)
confidence_tiers = thresholds.get("confidence_tiers", {})
effect_thresholds = thresholds.get("effect_size_thresholds", {"small": 0.10, "medium": 0.15, "large": 0.20})

# ---------------------------------------------------------------------------
# Collect run_score events from ship-*.jsonl only
# ---------------------------------------------------------------------------
score_events = []
ship_log_pattern = os.path.join(audit_log_dir, 'ship-*.jsonl')
log_files = sorted(glob.glob(ship_log_pattern))

# Check for L1 ephemeral notice
l1_notice = False
try:
    import subprocess
    if log_files:
        result = subprocess.run(
            ['git', 'check-ignore', '--quiet'] + log_files[:1],
            capture_output=True, cwd=os.getcwd()
        )
        if result.returncode == 0:
            l1_notice = True
except Exception:
    pass

if not log_files:
    # Check if there are any logs at all (might be wrong dir)
    all_logs = sorted(glob.glob(os.path.join(audit_log_dir, '*.jsonl')))
    if output_format == 'json':
        print(json.dumps({
            "error": "no_ship_logs",
            "message": f"No ship-*.jsonl files found in {audit_log_dir}/",
            "analyzed_runs": 0,
            "confidence_tier": "INSUFFICIENT",
        }, indent=2))
    else:
        print(f"Note: No ship-*.jsonl files found in {audit_log_dir}/")
        if all_logs:
            print(f"Note: Found {len(all_logs)} non-ship log file(s). This script analyzes /ship logs only.")
        print("Run /ship to generate scored runs first.")
        if l1_notice:
            print("")
            print("Note: L1 (advisory) logs are not committed to git. Data is limited to")
            print("logs still on disk. For cross-session analysis, use L2 or L3 maturity.")
    sys.exit(0)

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

# Sort by timestamp
def parse_ts(ts):
    try:
        return datetime.fromisoformat(ts.replace('Z', '+00:00'))
    except Exception:
        return datetime.min.replace(tzinfo=timezone.utc)

score_events.sort(key=lambda e: parse_ts(e.get('timestamp', '')))
num_runs = len(score_events)

# ---------------------------------------------------------------------------
# Assign scanner_mode: absent for pre-instrumentation events
# ---------------------------------------------------------------------------
VALID_MODES = ('tree-sitter-partial', 'regex-fallback', 'absent')

def get_scanner_mode(event):
    mode = event.get('scanner_mode', 'absent')
    if mode not in VALID_MODES:
        return 'absent'
    return mode

def get_scanner_tokens(event):
    try:
        return int(event.get('scanner_tokens', 0))
    except (TypeError, ValueError):
        return 0

# ---------------------------------------------------------------------------
# Determine confidence tier
# ---------------------------------------------------------------------------
def assign_confidence_tier(total_runs, cohort_counts):
    """
    Assign a confidence tier based on total runs and per-cohort minimum.
    cohort_counts: dict of mode -> count (non-empty cohorts only)
    Returns: (tier_name, tier_label, details_str)
    """
    non_empty_cohorts = {k: v for k, v in cohort_counts.items() if v > 0}
    num_non_empty = len(non_empty_cohorts)
    min_non_empty = min(non_empty_cohorts.values()) if non_empty_cohorts else 0

    # INSUFFICIENT
    insuf = confidence_tiers.get("INSUFFICIENT", {})
    if total_runs <= insuf.get("max_total_runs", 4):
        return "INSUFFICIENT", insuf.get("label", "Insufficient data"), ""

    # HIGH_CONFIDENCE
    hc = confidence_tiers.get("HIGH_CONFIDENCE", {})
    if total_runs >= hc.get("min_total_runs", 30) and min_non_empty >= hc.get("min_per_cohort", 15) and num_non_empty >= 2:
        return "HIGH_CONFIDENCE", hc.get("label", "High confidence"), ""

    # RELIABLE
    rel = confidence_tiers.get("RELIABLE", {})
    if total_runs >= rel.get("min_total_runs", 15) and min_non_empty >= rel.get("min_per_cohort", 8) and num_non_empty >= 2:
        return "RELIABLE", rel.get("label", "Reliable comparison"), ""

    # PRELIMINARY (default for 5+)
    prelim = confidence_tiers.get("PRELIMINARY", {})
    return "PRELIMINARY", prelim.get("label", "Preliminary signal"), ""

# ---------------------------------------------------------------------------
# Statistics helpers
# ---------------------------------------------------------------------------
def mean(vals):
    if not vals:
        return None
    return sum(vals) / len(vals)

def median(vals):
    if not vals:
        return None
    s = sorted(vals)
    n = len(s)
    mid = n // 2
    if n % 2 == 0:
        return (s[mid - 1] + s[mid]) / 2.0
    return float(s[mid])

def std_dev(vals):
    if len(vals) < 2:
        return 0.0
    m = mean(vals)
    variance = sum((v - m) ** 2 for v in vals) / (len(vals) - 1)
    return math.sqrt(variance)

def cohens_d(group_a, group_b):
    """
    Compute Cohen's d effect size between two groups.
    Returns None if either group is empty or pooled SD is 0.
    Edge cases:
      - Single element in either group: std_dev = 0, pooled SD uses the other group's SD.
      - Both single elements: SD = 0 for both, return None.
    """
    if not group_a or not group_b:
        return None
    mean_a = mean(group_a)
    mean_b = mean(group_b)
    n_a = len(group_a)
    n_b = len(group_b)
    sd_a = std_dev(group_a)
    sd_b = std_dev(group_b)
    # Pooled SD (Hedges' formula denominator)
    if n_a + n_b <= 2:
        # Both groups are size 1, cannot compute SD
        return None
    numerator = (n_a - 1) * sd_a**2 + (n_b - 1) * sd_b**2
    denominator = n_a + n_b - 2
    if denominator <= 0:
        return None
    pooled_sd = math.sqrt(numerator / denominator)
    if pooled_sd == 0.0:
        return None
    return (mean_a - mean_b) / pooled_sd

def label_effect_size(d):
    """Return a label for a Cohen's d value."""
    if d is None:
        return "N/A"
    abs_d = abs(d)
    large_thresh = effect_thresholds.get("large", 0.20)
    medium_thresh = effect_thresholds.get("medium", 0.15)
    small_thresh = effect_thresholds.get("small", 0.10)
    if abs_d >= large_thresh:
        return "LARGE"
    elif abs_d >= medium_thresh:
        return "MEDIUM"
    elif abs_d >= small_thresh:
        return "SMALL"
    else:
        return "NEGLIGIBLE"

# ---------------------------------------------------------------------------
# Extract per-dimension scores from run_score events
# ---------------------------------------------------------------------------
def get_dim_score(event, dim_name):
    for d in event.get('dimensions', []):
        if d.get('name') == dim_name:
            return d.get('score', 0.5)
    return None

def get_velocity(event):
    v = event.get('velocity_minutes', None)
    if v is None:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None

DIM_NAMES = ['efficiency', 'security', 'quality']

# ---------------------------------------------------------------------------
# Group events by scanner_mode
# ---------------------------------------------------------------------------
cohorts = {mode: [] for mode in VALID_MODES}
for event in score_events:
    mode = get_scanner_mode(event)
    cohorts[mode].append(event)

cohort_counts = {mode: len(events) for mode, events in cohorts.items()}

# ---------------------------------------------------------------------------
# INSUFFICIENT data path
# ---------------------------------------------------------------------------
if num_runs < confidence_tiers.get("INSUFFICIENT", {}).get("max_total_runs", 4) + 1:
    if output_format == 'json':
        print(json.dumps({
            "analyzed_runs": num_runs,
            "confidence_tier": "INSUFFICIENT",
            "message": f"Insufficient data: {num_runs} /ship run(s) found, need at least 5.",
            "cohort_counts": cohort_counts,
        }, indent=2))
    else:
        if l1_notice:
            print("Note: L1 (advisory) logs are not committed to git. Data is limited to")
            print("logs still on disk. For cross-session analysis, use L2 or L3 maturity.")
            print("")
        print(f"Insufficient data: {num_runs} /ship scored run(s) found, need at least 5.")
        prelim_min = confidence_tiers.get("PRELIMINARY", {}).get("min_total_runs", 5)
        print(f"Run /ship at least {prelim_min - num_runs} more time(s) to enable scanner cohort analysis.")
    sys.exit(0)

# ---------------------------------------------------------------------------
# Compute per-cohort statistics
# ---------------------------------------------------------------------------
def cohort_stats(events):
    """Compute per-dimension means and token stats for a cohort."""
    if not events:
        return None
    stats = {'n': len(events)}
    for dim in DIM_NAMES:
        scores = [get_dim_score(e, dim) for e in events]
        scores = [s for s in scores if s is not None]
        stats[dim] = mean(scores)
    composites = [e.get('composite', None) for e in events]
    composites = [c for c in composites if c is not None]
    stats['composite'] = mean(composites)
    velocities = [get_velocity(e) for e in events]
    velocities = [v for v in velocities if v is not None]
    stats['velocity'] = mean(velocities)
    tokens = [get_scanner_tokens(e) for e in events]
    stats['mean_tokens'] = mean(tokens)
    stats['median_tokens'] = median(tokens)
    return stats

cohort_stats_map = {}
for mode in VALID_MODES:
    events = cohorts[mode]
    if events:
        cohort_stats_map[mode] = cohort_stats(events)

# Assign confidence tier
tier_name, tier_label, _ = assign_confidence_tier(num_runs, cohort_counts)

# ---------------------------------------------------------------------------
# Compute Cohen's d: tree-sitter-partial vs absent (primary comparison)
# Also compute tree-sitter-partial vs regex-fallback and regex-fallback vs absent
# ---------------------------------------------------------------------------
def composite_scores_for(mode):
    events = cohorts[mode]
    vals = [e.get('composite') for e in events]
    return [v for v in vals if v is not None]

def dim_scores_for(mode, dim):
    events = cohorts[mode]
    vals = [get_dim_score(e, dim) for e in events]
    return [v for v in vals if v is not None]

# Pairwise comparisons (composite)
comparisons = [
    ('tree-sitter-partial', 'absent'),
    ('tree-sitter-partial', 'regex-fallback'),
    ('regex-fallback', 'absent'),
]

effect_sizes = {}
for (a, b) in comparisons:
    ga = composite_scores_for(a)
    gb = composite_scores_for(b)
    d = cohens_d(ga, gb)
    effect_sizes[(a, b)] = d

# Per-dimension pairwise for primary comparison (ts-partial vs absent)
dim_effect_sizes = {}
for dim in DIM_NAMES + ['composite']:
    if dim == 'composite':
        ga = composite_scores_for('tree-sitter-partial')
        gb = composite_scores_for('absent')
    else:
        ga = dim_scores_for('tree-sitter-partial', dim)
        gb = dim_scores_for('absent', dim)
    d = cohens_d(ga, gb)
    dim_effect_sizes[dim] = d

# ---------------------------------------------------------------------------
# Build correlations list (correlational language, never causal)
# ---------------------------------------------------------------------------
correlations = []

def fmt(v):
    if v is None:
        return "N/A"
    return f"{v:.2f}"

# Primary: tree-sitter-partial vs absent
ts_stats = cohort_stats_map.get('tree-sitter-partial')
absent_stats = cohort_stats_map.get('absent')
regex_stats = cohort_stats_map.get('regex-fallback')

if ts_stats and absent_stats:
    for dim in DIM_NAMES:
        ts_val = ts_stats.get(dim)
        ab_val = absent_stats.get(dim)
        if ts_val is not None and ab_val is not None:
            diff = ts_val - ab_val
            if abs(diff) >= effect_thresholds.get("small", 0.10):
                direction = "higher" if diff > 0 else "lower"
                ts_n = cohort_counts['tree-sitter-partial']
                ab_n = cohort_counts['absent']
                correlations.append(
                    f"[Correlation] tree-sitter-partial runs have {direction} mean {dim} "
                    f"({fmt(ts_val)} vs {fmt(ab_val)}) than absent runs "
                    f"(n={ts_n} vs n={ab_n})."
                )

if ts_stats and regex_stats:
    for dim in DIM_NAMES:
        ts_val = ts_stats.get(dim)
        rx_val = regex_stats.get(dim)
        if ts_val is not None and rx_val is not None:
            diff = ts_val - rx_val
            if abs(diff) >= effect_thresholds.get("small", 0.10):
                direction = "higher" if diff > 0 else "lower"
                ts_n = cohort_counts['tree-sitter-partial']
                rx_n = cohort_counts['regex-fallback']
                correlations.append(
                    f"[Correlation] tree-sitter-partial runs have {direction} mean {dim} "
                    f"({fmt(ts_val)} vs {fmt(rx_val)}) than regex-fallback runs "
                    f"(n={ts_n} vs n={rx_n})."
                )

# Velocity comparisons (lower velocity = faster)
if ts_stats and absent_stats:
    ts_vel = ts_stats.get('velocity')
    ab_vel = absent_stats.get('velocity')
    if ts_vel is not None and ab_vel is not None:
        diff = ts_vel - ab_vel
        if abs(diff) >= 2.0:  # 2+ minute difference is notable
            direction = "lower" if diff < 0 else "higher"
            correlations.append(
                f"[Correlation] tree-sitter-partial runs have {direction} mean velocity "
                f"({fmt(ts_vel)} min vs {fmt(ab_vel)} min) than absent runs."
            )

# Caution note
non_empty_cohort_count = sum(1 for c in VALID_MODES if cohort_counts[c] > 0)
if tier_name in ("INSUFFICIENT", "PRELIMINARY"):
    correlations.append(
        f"[Caution] Small sample sizes -- correlations are directional, not conclusive. "
        f"Multiple confounders (developer skill, codebase type, plan complexity) are not controlled for."
    )
elif tier_name == "RELIABLE":
    correlations.append(
        f"[Caution] Effect sizes are reportable at RELIABLE tier, but confounders "
        f"(developer skill, project type, plan complexity, time/learning effects) are not controlled. "
        f"This is observational data, not a randomized experiment."
    )

# Variance check
if non_empty_cohort_count < 2:
    correlations.append(
        f"[Caution] Insufficient cohort variance -- only 1 scanner mode present in data. "
        f"Cohort comparison requires at least 2 modes with runs. "
        f"Consider enabling/disabling the scanner venv to create natural variation."
    )

# ---------------------------------------------------------------------------
# Run recommendations
# ---------------------------------------------------------------------------
def compute_recommendations(tier_name, cohort_counts, num_runs):
    recs = []
    rel = confidence_tiers.get("RELIABLE", {})
    hc = confidence_tiers.get("HIGH_CONFIDENCE", {})
    rel_min_total = rel.get("min_total_runs", 15)
    rel_min_per = rel.get("min_per_cohort", 8)
    hc_min_total = hc.get("min_total_runs", 30)
    hc_min_per = hc.get("min_per_cohort", 15)

    if tier_name in ("INSUFFICIENT", "PRELIMINARY"):
        runs_needed = max(0, rel_min_total - num_runs)
        if runs_needed > 0:
            recs.append(f"{runs_needed} more /ship runs needed to reach RELIABLE tier.")
        for mode in ('tree-sitter-partial', 'regex-fallback'):
            n = cohort_counts.get(mode, 0)
            if n < rel_min_per:
                recs.append(f"{rel_min_per - n} more {mode} runs needed for RELIABLE per-cohort threshold.")
    elif tier_name == "RELIABLE":
        runs_needed = max(0, hc_min_total - num_runs)
        if runs_needed > 0:
            recs.append(f"{runs_needed} more /ship runs needed to reach HIGH_CONFIDENCE tier.")
        for mode in ('tree-sitter-partial', 'regex-fallback'):
            n = cohort_counts.get(mode, 0)
            if n < hc_min_per:
                recs.append(f"{hc_min_per - n} more {mode} runs needed for HIGH_CONFIDENCE per-cohort threshold.")
    return recs

recommendations = compute_recommendations(tier_name, cohort_counts, num_runs)

# ---------------------------------------------------------------------------
# JSON output
# ---------------------------------------------------------------------------
if output_format == 'json':
    cohort_output = {}
    for mode in VALID_MODES:
        s = cohort_stats_map.get(mode)
        if s:
            cohort_output[mode] = {
                'n': s['n'],
                'efficiency': round(s['efficiency'], 3) if s.get('efficiency') is not None else None,
                'security': round(s['security'], 3) if s.get('security') is not None else None,
                'quality': round(s['quality'], 3) if s.get('quality') is not None else None,
                'composite': round(s['composite'], 3) if s.get('composite') is not None else None,
                'velocity_mean': round(s['velocity'], 2) if s.get('velocity') is not None else None,
                'mean_tokens': round(s['mean_tokens'], 0) if s.get('mean_tokens') is not None else None,
                'median_tokens': round(s['median_tokens'], 0) if s.get('median_tokens') is not None else None,
            }
        else:
            cohort_output[mode] = {'n': 0}

    effect_output = {}
    for (a, b), d in effect_sizes.items():
        key = f"{a}_vs_{b}"
        effect_output[key] = {
            'cohens_d': round(d, 3) if d is not None else None,
            'label': label_effect_size(d),
        }

    output = {
        'date': today,
        'analyzed_runs': num_runs,
        'confidence_tier': tier_name,
        'confidence_label': tier_label,
        'l1_notice': l1_notice,
        'cohort_counts': cohort_counts,
        'cohorts': cohort_output,
        'effect_sizes': effect_output,
        'correlations': correlations,
        'recommendations': recommendations,
    }
    print(json.dumps(output, indent=2))
    sys.exit(0)

# ---------------------------------------------------------------------------
# Markdown output
# ---------------------------------------------------------------------------

if l1_notice:
    print("Note: L1 (advisory) logs are not committed to git. Data is limited to")
    print("logs still on disk. For meaningful cross-session analysis, use L2 or L3 maturity.")
    print("")

print(f"## Scanner Value Report ({num_runs} /ship runs analyzed)")
print("")

# Caveat -- always shown
print("### Caveat")
print("")
print("This is observational data, not a randomized experiment. Correlations below")
print("do NOT imply causation. Confounders (developer skill, project type, plan")
print("complexity, time/learning effects) may explain observed differences.")
print("See Statistical Assessment for confidence tier and sample size context.")
print("")

# Cohort Summary table
print("### Cohort Summary")
print("")
header = f"| {'Cohort':<21} | {'Runs':>4} | {'Efficiency':>10} | {'Security':>8} | {'Quality':>7} | {'Composite':>9} | {'Velocity (min)':>14} |"
sep    = f"|{'-'*23}|{'-'*6}|{'-'*12}|{'-'*10}|{'-'*9}|{'-'*11}|{'-'*16}|"
print(header)
print(sep)
for mode in VALID_MODES:
    s = cohort_stats_map.get(mode)
    if s:
        n = s['n']
        eff = f"{s['efficiency']:.2f}" if s.get('efficiency') is not None else "N/A"
        sec = f"{s['security']:.2f}" if s.get('security') is not None else "N/A"
        qual = f"{s['quality']:.2f}" if s.get('quality') is not None else "N/A"
        comp = f"{s['composite']:.2f}" if s.get('composite') is not None else "N/A"
        vel = f"{s['velocity']:.1f}" if s.get('velocity') is not None else "N/A"
        print(f"| {mode:<21} | {n:>4} | {eff:>10} | {sec:>8} | {qual:>7} | {comp:>9} | {vel:>14} |")
    else:
        print(f"| {mode:<21} | {'0':>4} | {'N/A':>10} | {'N/A':>8} | {'N/A':>7} | {'N/A':>9} | {'N/A':>14} |")
print("")

# Token Cost table
print("### Token Cost")
print("")
tok_header = f"| {'Cohort':<21} | {'Mean Tokens':>11} | {'Median Tokens':>13} |"
tok_sep    = f"|{'-'*23}|{'-'*13}|{'-'*15}|"
print(tok_header)
print(tok_sep)
for mode in ('tree-sitter-partial', 'regex-fallback'):
    s = cohort_stats_map.get(mode)
    if s:
        mt = f"{s['mean_tokens']:.0f}" if s.get('mean_tokens') is not None else "N/A"
        mdt = f"{s['median_tokens']:.0f}" if s.get('median_tokens') is not None else "N/A"
        print(f"| {mode:<21} | {mt:>11} | {mdt:>13} |")
    else:
        print(f"| {mode:<21} | {'N/A':>11} | {'N/A':>13} |")
# absent cohort: token data is always 0 (scanner not invoked)
ab_s = cohort_stats_map.get('absent')
if ab_s:
    print(f"| {'absent':<21} | {'0 (no scanner)':>11} | {'0 (no scanner)':>13} |")
else:
    print(f"| {'absent':<21} | {'N/A':>11} | {'N/A':>13} |")
print("")
print("Note: Token counts are approximate (1 token ~= 4 characters). For comparative purposes only.")
print("")

# Statistical Assessment
print("### Statistical Assessment")
print("")
counts_str = ", ".join(f"{m}={cohort_counts[m]}" for m in VALID_MODES)
print(f"- Sample sizes: {counts_str}")
print(f"- Confidence level: **{tier_name}** ({tier_label})")

# Effect sizes
primary_d = effect_sizes.get(('tree-sitter-partial', 'absent'))
if primary_d is not None:
    ts_n = cohort_counts['tree-sitter-partial']
    ab_n = cohort_counts['absent']
    ts_comp = cohort_stats_map.get('tree-sitter-partial', {}).get('composite')
    ab_comp = cohort_stats_map.get('absent', {}).get('composite')
    diff_str = f"{(ts_comp - ab_comp):+.2f}" if (ts_comp is not None and ab_comp is not None) else "N/A"
    print(f"- Effect size (composite, tree-sitter-partial vs absent): {diff_str} ({label_effect_size(primary_d)}, d={primary_d:.2f})")
else:
    print(f"- Effect size (composite, tree-sitter-partial vs absent): N/A (one or both cohorts empty)")

ts_rx_d = effect_sizes.get(('tree-sitter-partial', 'regex-fallback'))
if ts_rx_d is not None:
    ts_comp = cohort_stats_map.get('tree-sitter-partial', {}).get('composite')
    rx_comp = cohort_stats_map.get('regex-fallback', {}).get('composite')
    diff_str = f"{(ts_comp - rx_comp):+.2f}" if (ts_comp is not None and rx_comp is not None) else "N/A"
    print(f"- Effect size (composite, tree-sitter-partial vs regex-fallback): {diff_str} ({label_effect_size(ts_rx_d)}, d={ts_rx_d:.2f})")
else:
    print(f"- Effect size (composite, tree-sitter-partial vs regex-fallback): N/A (one or both cohorts empty)")

if recommendations:
    print("- Recommendation:")
    for rec in recommendations:
        print(f"  - {rec}")
print("")

# Correlations
print("### Correlations")
print("")
if correlations:
    for c in correlations:
        print(f"- {c}")
else:
    print("- No notable correlations detected (all dimension differences below small threshold).")
print("")
print("Correlational framing: all findings above describe associations in the data, not")
print("causal relationships. Scanner mode is not randomly assigned. See Caveat above.")

sys.exit(0)
PYEOF

PYTHON_EXIT=$?
if [[ $PYTHON_EXIT -ne 0 ]]; then
    echo "Warning: scanner-value-report.sh: python3 exited with code ${PYTHON_EXIT}" >&2
fi

exit 0
