#!/usr/bin/env python3
"""Cross-project learnings aggregator.

Discovers .claude/learnings.md files across all registered projects and
allowed_roots, parses them, builds a unified index with tag-based
cross-project correlation and promotion candidate detection.

Writes ~/.claude-devkit/learnings/index.json.

Python 3.8+, stdlib only.
"""

import json
import os
import signal
import sys

# --- Path setup: import siblings from the same scripts/ directory -----------

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)

from learnings_parser import parse_learnings_file  # noqa: E402

# Import compute_project_id from devkit_cli.py
# We import it directly rather than calling devkit_cli.py via subprocess
# (see plan Assumption 3).
from devkit_cli import compute_project_id  # noqa: E402

# --- Constants ---------------------------------------------------------------

_DEVKIT_DIR = os.path.expanduser('~/.claude-devkit')
_LEARNINGS_DIR = os.path.join(_DEVKIT_DIR, 'learnings')
_INDEX_PATH = os.path.join(_LEARNINGS_DIR, 'index.json')
_REGISTRY_PATH = os.path.join(_DEVKIT_DIR, 'registry.json')
_DEFAULTS_PATH = os.path.join(
    os.path.dirname(_SCRIPT_DIR), 'configs', 'devkit-defaults.json'
)
_SCAN_TIMEOUT = 30  # seconds
_MAX_DEPTH = 4      # maxdepth for allowed_roots scan
_DEFAULT_MIN_PROJECTS = 3  # minimum cross-project threshold


# --- Discovery ---------------------------------------------------------------

def _load_registry():
    """Load project registry. Returns list of project paths or empty list."""
    if not os.path.isfile(_REGISTRY_PATH):
        return []
    try:
        with open(_REGISTRY_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
        if isinstance(data, dict) and 'projects' in data:
            return [
                p.get('path', '') for p in data['projects']
                if isinstance(p, dict) and p.get('path')
            ]
        return []
    except (json.JSONDecodeError, OSError):
        return []


def _load_allowed_roots():
    """Load allowed_roots from devkit-defaults.json. Returns list of paths."""
    roots = ['~/projects/', '~/workspaces/']  # hardcoded fallback
    try:
        if os.path.isfile(_DEFAULTS_PATH):
            with open(_DEFAULTS_PATH, 'r', encoding='utf-8') as f:
                data = json.load(f)
            if isinstance(data, dict) and 'allowed_roots' in data:
                roots = data['allowed_roots']
    except (json.JSONDecodeError, OSError):
        pass
    return [os.path.expanduser(r) for r in roots]


def _is_valid_path(path):
    """Check if a path is valid for scanning.

    M-S2: Skip symlinks.
    Skip backup directories (containing '_backup_').
    Skip non-git directories.
    """
    # Resolve to real path for symlink check
    try:
        real = os.path.realpath(path)
    except (OSError, ValueError):
        return False

    # M-S2: Reject symlinks
    if real != os.path.abspath(path):
        return False

    # Skip backup directories
    if '_backup_' in path:
        return False

    return True


def _is_git_dir(path):
    """Check if a directory is (inside) a git repository."""
    # Check for .git in the directory or any parent
    check = path
    for _ in range(20):  # prevent infinite loop
        if os.path.isdir(os.path.join(check, '.git')):
            return True
        parent = os.path.dirname(check)
        if parent == check:
            break
        check = parent
    return False


def _project_display_name(project_path):
    """Compute human-readable project display name.

    Returns path relative to $HOME for readability.
    """
    home = os.path.expanduser('~')
    if project_path.startswith(home + os.sep):
        return project_path[len(home) + 1:]
    return os.path.basename(project_path)


class _ScanTimeout(Exception):
    """Raised when filesystem scan exceeds timeout."""
    pass


def _timeout_handler(signum, frame):
    raise _ScanTimeout("Filesystem scan exceeded timeout")


def _discover_learnings_files(allowed_roots=None):
    """Discover all .claude/learnings.md files.

    Discovery strategy (ordered):
    1. Registry projects (skipped when allowed_roots is explicitly provided)
    2. allowed_roots scan (maxdepth=4, 30s timeout)
    3. Skip: symlinks, backup dirs, non-git dirs

    When allowed_roots is provided, only those directories are scanned
    (registry-based discovery is skipped). This is used by tests to
    constrain scanning to test fixtures.

    Returns list of (learnings_path, project_path) tuples.
    """
    discovered = {}  # project_path -> learnings_path (dedup by project)
    warnings = []

    # Step 1: Registry projects (skip when allowed_roots explicitly provided)
    if allowed_roots is None:
        for project_path in _load_registry():
            project_path = os.path.expanduser(project_path)
            if not os.path.isdir(project_path):
                continue

            real_path = os.path.realpath(project_path)
            if real_path != os.path.abspath(project_path):
                warnings.append(f"Skipping symlinked registry path: {project_path}")
                continue

            learnings = os.path.join(project_path, '.claude', 'learnings.md')
            if os.path.isfile(learnings):
                discovered[real_path] = learnings

    # Step 2: Scan allowed_roots
    if allowed_roots is not None:
        roots = [os.path.realpath(os.path.expanduser(r)) for r in allowed_roots]
    else:
        roots = _load_allowed_roots()

    # Set up timeout (Unix only; on Windows, skip timeout)
    old_handler = None
    if hasattr(signal, 'SIGALRM'):
        old_handler = signal.signal(signal.SIGALRM, _timeout_handler)
        signal.alarm(_SCAN_TIMEOUT)

    try:
        for root in roots:
            if not os.path.isdir(root):
                continue
            _scan_root(root, discovered, warnings, depth=0)
    except _ScanTimeout:
        warnings.append(
            f"Filesystem scan timed out after {_SCAN_TIMEOUT}s "
            "(partial results used)"
        )
    finally:
        if hasattr(signal, 'SIGALRM'):
            signal.alarm(0)
            if old_handler is not None:
                signal.signal(signal.SIGALRM, old_handler)

    return list(discovered.items()), warnings


def _scan_root(root, discovered, warnings, depth):
    """Recursively scan a root directory for learnings files.

    Bounded to _MAX_DEPTH levels deep.
    """
    if depth > _MAX_DEPTH:
        return

    try:
        entries = os.listdir(root)
    except (OSError, PermissionError):
        return

    for entry in sorted(entries):
        path = os.path.join(root, entry)

        # Skip non-directories
        if not os.path.isdir(path):
            continue

        # Skip hidden directories (except .claude)
        if entry.startswith('.') and entry != '.claude':
            continue

        # Skip backup directories
        if '_backup_' in entry:
            continue

        # M-S2: Skip symlinks
        try:
            real = os.path.realpath(path)
            if real != os.path.abspath(path):
                warnings.append(f"Skipping symlinked path: {path}")
                continue
        except (OSError, ValueError):
            continue

        # Check for learnings file
        learnings = os.path.join(path, '.claude', 'learnings.md')
        if os.path.isfile(learnings):
            # Verify it's a git directory
            if _is_git_dir(path):
                if real not in discovered:
                    discovered[real] = learnings
            continue  # Don't recurse into project dirs

        # Recurse into subdirectories (for nested repos like lightwell/*)
        _scan_root(path, discovered, warnings, depth + 1)


# --- Aggregation -------------------------------------------------------------

def aggregate(min_projects=_DEFAULT_MIN_PROJECTS, allowed_roots=None):
    """Run full aggregation pipeline.

    When allowed_roots is provided (list of directory paths), only those
    roots are scanned for learnings files (registry-based discovery is
    skipped). This is used by tests to constrain scanning to test fixtures.

    Returns (index_data, warnings) tuple.
    """
    all_warnings = []

    # Discover files
    discovered, disc_warnings = _discover_learnings_files(
        allowed_roots=allowed_roots
    )
    all_warnings.extend(disc_warnings)

    if not discovered:
        all_warnings.append("No learnings files found")
        return _empty_index(), all_warnings

    # Parse each file
    all_entries = []
    projects_scanned = 0

    for project_path, learnings_path in discovered:
        projects_scanned += 1

        # Compute project identity
        try:
            project_id = compute_project_id(project_path)
        except (ValueError, OSError):
            project_id = os.path.basename(project_path)

        display_name = _project_display_name(project_path)

        entries, parse_warnings = parse_learnings_file(
            learnings_path,
            source_project=project_id,
            source_project_display=display_name,
        )
        all_entries.extend(entries)
        all_warnings.extend(parse_warnings)

    # Within-project dedup by entry ID
    deduped = _dedup_within_project(all_entries)

    # Cross-project analysis
    tag_freq = _compute_tag_frequency(deduped)
    cross_project = _find_cross_project_entries(deduped)
    promotion_candidates = _find_promotion_candidates(
        tag_freq, cross_project, deduped, min_projects
    )

    # Build index
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

    # Strip raw_text from index entries (saves space, not needed in index)
    index_entries = []
    for entry in deduped:
        e = dict(entry)
        e.pop('raw_text', None)
        index_entries.append(e)

    index_data = {
        'schema_version': '1.0.0',
        'generated_at': now,
        'projects_scanned': projects_scanned,
        'entries_parsed': len(all_entries),
        'unique_entries': len(deduped),
        'cross_project_entries': len(cross_project),
        'entries': index_entries,
        'tag_frequency': tag_freq,
        'promotion_candidates': promotion_candidates,
    }

    return index_data, all_warnings


def _empty_index():
    """Return an empty index structure."""
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    return {
        'schema_version': '1.0.0',
        'generated_at': now,
        'projects_scanned': 0,
        'entries_parsed': 0,
        'unique_entries': 0,
        'cross_project_entries': 0,
        'entries': [],
        'tag_frequency': {},
        'promotion_candidates': [],
    }


def _dedup_within_project(entries):
    """Deduplicate entries within the same project by entry ID.

    When duplicates are found, merge seen_in lists.
    """
    # Group by (source_project, entry_id)
    groups = {}
    for entry in entries:
        key = (entry.get('source_project', ''), entry['id'])
        if key not in groups:
            groups[key] = entry
        else:
            # Merge seen_in
            existing = groups[key]
            merged_seen = list(set(
                existing.get('seen_in', []) + entry.get('seen_in', [])
            ))
            existing['seen_in'] = sorted(merged_seen)

    return list(groups.values())


def _compute_tag_frequency(entries):
    """Compute tag frequency across projects.

    Returns dict of tag -> {count, projects, project_list}.
    """
    # tag -> set of project display names
    tag_projects = {}
    # tag -> total count
    tag_counts = {}

    for entry in entries:
        project = entry.get('source_project_display', '')
        for tag in entry.get('tags', []):
            tag_counts[tag] = tag_counts.get(tag, 0) + 1
            if tag not in tag_projects:
                tag_projects[tag] = set()
            tag_projects[tag].add(project)

    result = {}
    for tag in sorted(tag_counts.keys()):
        projects = sorted(tag_projects.get(tag, set()))
        result[tag] = {
            'count': tag_counts[tag],
            'projects': len(projects),
            'project_list': projects,
        }

    return result


def _find_cross_project_entries(entries):
    """Find entries with the same ID across multiple projects.

    Returns list of merged entries.
    """
    # Group by entry ID across all projects
    id_groups = {}
    for entry in entries:
        eid = entry['id']
        if eid not in id_groups:
            id_groups[eid] = []
        id_groups[eid].append(entry)

    # Filter to entries appearing in 2+ projects
    cross_project = []
    for eid, group in id_groups.items():
        projects = set(
            e.get('source_project_display', '') for e in group
        )
        if len(projects) >= 2:
            # Merge into a single entry with projects list
            base = dict(group[0])
            base['projects'] = sorted(projects)
            # Merge seen_in and tags across all instances
            all_seen = set()
            all_tags = set()
            for e in group:
                all_seen.update(e.get('seen_in', []))
                all_tags.update(e.get('tags', []))
            base['seen_in'] = sorted(all_seen)
            base['tags'] = sorted(all_tags)
            cross_project.append(base)

    return cross_project


def _find_promotion_candidates(tag_freq, cross_project, entries,
                               min_projects):
    """Identify promotion candidates.

    Primary: Tags with cross-project frequency >= min_projects.
    Secondary: Entries with len(projects) >= min_projects.

    Returns list of candidate dicts.
    """
    candidates = []

    # Primary: High-frequency tags (in min_projects+ projects)
    for tag, info in sorted(tag_freq.items()):
        if info['projects'] >= min_projects:
            # Find representative entries for this tag
            rep_ids = []
            for entry in entries:
                if tag in entry.get('tags', []):
                    if entry['id'] not in rep_ids:
                        rep_ids.append(entry['id'])
                    if len(rep_ids) >= 3:
                        break

            candidates.append({
                'type': 'high_frequency_tag',
                'tag': tag,
                'project_count': info['projects'],
                'entry_count': info['count'],
                'representative_entries': rep_ids,
                'reason': f"Tag appears in {info['projects']} projects",
            })

    # Secondary: Cross-project entries (same title in min_projects+ projects)
    for entry in cross_project:
        projects = entry.get('projects', [])
        if len(projects) >= min_projects:
            candidates.append({
                'type': 'cross_project_entry',
                'entry_id': entry['id'],
                'title': entry['title'],
                'severity': entry.get('severity'),
                'projects': projects,
                'project_count': len(projects),
                'tags': entry.get('tags', []),
                'reason': (
                    f"Same root cause in {len(projects)} projects "
                    "(title match)"
                ),
            })

    return candidates


# --- Atomic write ------------------------------------------------------------

def _atomic_write_json(path, data):
    """Write JSON data atomically using temp file + os.replace().

    Creates parent directories if needed.
    Sets file permissions to 0o600 (TB2).
    """
    parent = os.path.dirname(path)
    os.makedirs(parent, mode=0o700, exist_ok=True)

    tmp_path = path + '.tmp'
    try:
        with open(tmp_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2)
            f.write('\n')
        os.replace(tmp_path, path)
        # TB2: Set file permissions
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
    except OSError:
        # Clean up temp file on failure
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


# --- CLI interface -----------------------------------------------------------

def _format_markdown(index_data):
    """Format index data as human-readable markdown summary."""
    lines = []
    lines.append('# Cross-Project Learnings Summary')
    lines.append('')
    lines.append(f"- Projects scanned: {index_data['projects_scanned']}")
    lines.append(f"- Entries parsed: {index_data['entries_parsed']}")
    lines.append(f"- Unique entries: {index_data['unique_entries']}")
    lines.append(
        f"- Cross-project entries: {index_data['cross_project_entries']}"
    )
    lines.append('')

    # Tag frequency (top 20)
    tag_freq = index_data.get('tag_frequency', {})
    if tag_freq:
        lines.append('## Tag Frequency (top 20)')
        lines.append('')
        sorted_tags = sorted(
            tag_freq.items(),
            key=lambda x: (-x[1]['projects'], -x[1]['count'])
        )
        for tag, info in sorted_tags[:20]:
            lines.append(
                f"- **{tag}**: {info['count']} entries in "
                f"{info['projects']} projects "
                f"({', '.join(info['project_list'])})"
            )
        lines.append('')

    # Promotion candidates
    candidates = index_data.get('promotion_candidates', [])
    if candidates:
        lines.append('## Promotion Candidates')
        lines.append('')
        for i, c in enumerate(candidates, 1):
            if c['type'] == 'high_frequency_tag':
                lines.append(
                    f"{i}. **Tag: {c['tag']}** -- "
                    f"{c['entry_count']} entries in "
                    f"{c['project_count']} projects"
                )
            elif c['type'] == 'cross_project_entry':
                sev = f" [{c['severity']}]" if c.get('severity') else ''
                lines.append(
                    f"{i}. **{c['title']}**{sev} -- "
                    f"{c['project_count']} projects: "
                    f"{', '.join(c['projects'])}"
                )
            lines.append(f"   Reason: {c['reason']}")
        lines.append('')
    else:
        lines.append('## Promotion Candidates')
        lines.append('')
        lines.append('No promotion candidates found.')
        lines.append('')

    return '\n'.join(lines)


def main():
    """CLI entry point.

    Usage: python3 learnings_aggregator.py [--format json|md]
                                           [--min-projects N]
                                           [--allowed-roots DIR ...]
    """
    args = sys.argv[1:]

    fmt = 'json'
    min_projects = _DEFAULT_MIN_PROJECTS
    allowed_roots = None

    i = 0
    while i < len(args):
        if args[i] in ('-h', '--help'):
            print(
                "Usage: python3 learnings_aggregator.py "
                "[--format json|md] [--min-projects N] "
                "[--allowed-roots DIR ...]",
                file=sys.stderr
            )
            print(
                "\nDiscover and aggregate learnings from all projects.",
                file=sys.stderr
            )
            print("\nOptions:", file=sys.stderr)
            print(
                "  --format json  Write index.json (default)",
                file=sys.stderr
            )
            print(
                "  --format md    Print markdown summary to stdout",
                file=sys.stderr
            )
            print(
                "  --min-projects N  Minimum projects for promotion "
                "candidates (default: 3)",
                file=sys.stderr
            )
            print(
                "  --allowed-roots DIR [DIR ...]  Only scan these root "
                "directories (skip registry)",
                file=sys.stderr
            )
            sys.exit(0)
        elif args[i] == '--format' and i + 1 < len(args):
            fmt = args[i + 1]
            if fmt not in ('json', 'md'):
                print(
                    f"Error: unknown format '{fmt}'. Use 'json' or 'md'.",
                    file=sys.stderr
                )
                sys.exit(2)
            i += 2
        elif args[i] == '--min-projects' and i + 1 < len(args):
            try:
                min_projects = int(args[i + 1])
                if min_projects < 1:
                    raise ValueError
            except ValueError:
                print(
                    f"Error: --min-projects must be a positive integer",
                    file=sys.stderr
                )
                sys.exit(2)
            i += 2
        elif args[i] == '--allowed-roots':
            # Consume all following non-flag arguments as root directories
            allowed_roots = []
            i += 1
            while i < len(args) and not args[i].startswith('--'):
                allowed_roots.append(args[i])
                i += 1
            if not allowed_roots:
                print(
                    "Error: --allowed-roots requires at least one directory",
                    file=sys.stderr
                )
                sys.exit(2)
        else:
            print(f"Error: unknown argument '{args[i]}'", file=sys.stderr)
            sys.exit(2)

    # Run aggregation
    index_data, warnings = aggregate(
        min_projects=min_projects, allowed_roots=allowed_roots
    )

    # Print warnings to stderr
    for w in warnings:
        print(f"Warning: {w}", file=sys.stderr)

    if fmt == 'json':
        _atomic_write_json(_INDEX_PATH, index_data)
        print(f"Wrote {_INDEX_PATH}")
        print(
            f"  {index_data['projects_scanned']} projects, "
            f"{index_data['unique_entries']} entries, "
            f"{len(index_data.get('promotion_candidates', []))} "
            "promotion candidates"
        )
    else:
        print(_format_markdown(index_data))

    sys.exit(0)


if __name__ == '__main__':
    main()
