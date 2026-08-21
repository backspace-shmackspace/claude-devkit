#!/usr/bin/env python3
"""Deterministic parser for .claude/learnings.md files.

Converts learnings entries into structured JSON. Handles format variations
across projects: missing dates, missing severity, uppercase severity,
pre-title and post-title severity positioning.

Python 3.8+, stdlib only.
"""

import hashlib
import json
import os
import re
import sys

# --- Constants ---------------------------------------------------------------

MAX_FILE_SIZE = 1_048_576  # 1 MB (M-S6)

# Severity regex: case-insensitive, matches Critical/High/Medium/Low/Minor
_SEVERITY_RE = re.compile(
    r'\[(Critical|High|Medium|Low|Minor)\]', re.IGNORECASE
)

# Date regex: ISO date [YYYY-MM-DD]
_DATE_RE = re.compile(r'\[(\d{4}-\d{2}-\d{2})\]')

# Tag regex: #lowercase-hyphenated tags
_TAG_RE = re.compile(r'#[a-z][a-z0-9-]*')

# Seen-in regex: "Seen in: foo, bar, baz." -- stops at a #tag or end of line
_SEEN_IN_RE = re.compile(r'Seen in:\s*(.+?)\.?\s*(?=#[a-z]|$)', re.IGNORECASE)

# Entry start: line beginning with "- **"
_ENTRY_START_RE = re.compile(r'^- \*\*')

# Section header regex
_SECTION_H2_RE = re.compile(r'^## (.+)')
_SECTION_H3_RE = re.compile(r'^### (.+)')


# --- Parsing -----------------------------------------------------------------

def _normalize_title(title):
    """Normalize title for stable ID computation.

    Lowercase, strip date prefix and severity, collapse whitespace.
    """
    # Remove date brackets
    title = _DATE_RE.sub('', title)
    # Remove severity brackets
    title = _SEVERITY_RE.sub('', title)
    # Collapse whitespace
    title = ' '.join(title.lower().split())
    return title.strip()


def _compute_entry_id(title):
    """Compute stable entry ID from normalized title.

    Returns first 12 hex chars of SHA-256 hash.
    """
    normalized = _normalize_title(title)
    return hashlib.sha256(normalized.encode()).hexdigest()[:12]


def _extract_title(line):
    """Extract title text from between ** markers on the entry start line.

    Handles:
      - **[date] Title** [Severity] ...
      - **Title** [Severity] ...
      - **[date] [SEVERITY] Title** ...
      - **[date] Title** ...
    """
    # Find text between first ** and next **
    match = re.search(r'\*\*(.+?)\*\*', line)
    if not match:
        return line.strip()

    inner = match.group(1).strip()

    # Strip date prefix if present
    inner = _DATE_RE.sub('', inner).strip()

    # Strip severity prefix if present (for pre-title variant)
    inner = _SEVERITY_RE.sub('', inner).strip()

    return inner


def _extract_severity(entry_text):
    """Extract severity from entry text, case-insensitive.

    Handles both post-title and pre-title variants:
      - Post-title: - **[date] Title** [Severity]
      - Pre-title:  - **[date] [HIGH] Title**

    Returns canonical capitalization (e.g., "High") or None.
    """
    match = _SEVERITY_RE.search(entry_text)
    if not match:
        return None
    # Canonical capitalization: first letter upper, rest lower
    raw = match.group(1)
    return raw[0].upper() + raw[1:].lower()


def _extract_date(entry_text):
    """Extract ISO date from entry text. Returns date string or None."""
    match = _DATE_RE.search(entry_text)
    return match.group(1) if match else None


def _extract_tags(entry_text):
    """Extract all #tags from entry text. Returns sorted list."""
    tags = _TAG_RE.findall(entry_text)
    return sorted(set(tags))


def _extract_seen_in(entry_text):
    """Extract seen-in list from entry text.

    Parses "Seen in: foo, bar, baz." into ["foo", "bar", "baz"].
    Returns sorted list.
    """
    match = _SEEN_IN_RE.search(entry_text)
    if not match:
        return []
    raw = match.group(1)
    items = [item.strip() for item in raw.split(',')]
    # Filter empty items and deduplicate
    items = sorted(set(item for item in items if item))
    return items


def parse_learnings_file(filepath, source_project=None,
                         source_project_display=None):
    """Parse a learnings.md file into structured entries.

    Args:
        filepath: Path to the learnings.md file.
        source_project: Optional project ID (from compute_project_id).
        source_project_display: Optional human-readable project name.

    Returns:
        (entries, warnings) tuple where entries is a list of dicts and
        warnings is a list of warning strings. Never raises on parse errors.
    """
    entries = []
    warnings = []

    filepath = os.path.abspath(filepath)

    if not os.path.isfile(filepath):
        return [], [f"File not found: {filepath}"]

    # M-S6: Size limit guard
    try:
        file_size = os.path.getsize(filepath)
    except OSError as e:
        return [], [f"Cannot stat file: {e}"]

    if file_size > MAX_FILE_SIZE:
        return [], [
            f"File exceeds size limit ({file_size} > {MAX_FILE_SIZE}): "
            f"{filepath}"
        ]

    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except (OSError, UnicodeDecodeError) as e:
        return [], [f"Cannot read file: {e}"]

    # M-S5: Store paths relative to $HOME
    home = os.path.expanduser('~')
    if filepath.startswith(home + os.sep):
        source_file = filepath[len(home) + 1:]
    else:
        source_file = filepath

    # Track section hierarchy
    current_h2 = None
    current_h3 = None

    # Track current entry being built
    current_entry_lines = []
    current_entry_start_line = None

    def _finalize_entry(entry_lines):
        """Process accumulated entry lines into a structured entry."""
        if not entry_lines:
            return None

        entry_text = '\n'.join(entry_lines)
        first_line = entry_lines[0]

        title = _extract_title(first_line)
        if not title:
            warnings.append(
                f"Empty title in entry near line {current_entry_start_line}"
            )
            return None

        entry_id = _compute_entry_id(title)
        severity = _extract_severity(entry_text)
        date = _extract_date(entry_text)
        tags = _extract_tags(entry_text)
        seen_in = _extract_seen_in(entry_text)

        # Build section path
        section_parts = []
        if current_h2:
            section_parts.append(current_h2)
        if current_h3:
            section_parts.append(current_h3)
        section = ' > '.join(section_parts) if section_parts else ''

        entry = {
            'id': entry_id,
            'title': title,
            'severity': severity,
            'date': date,
            'section': section,
            'tags': tags,
            'seen_in': seen_in,
            'raw_text': entry_text,
            'source_file': source_file,
        }

        if source_project is not None:
            entry['source_project'] = source_project
        if source_project_display is not None:
            entry['source_project_display'] = source_project_display

        return entry

    for line_num, line in enumerate(lines, start=1):
        stripped = line.rstrip('\n')

        # Track section headers
        h2_match = _SECTION_H2_RE.match(stripped)
        if h2_match:
            # Finalize any in-progress entry before section change
            entry = _finalize_entry(current_entry_lines)
            if entry:
                entries.append(entry)
            current_entry_lines = []
            current_h2 = h2_match.group(1).strip()
            current_h3 = None
            continue

        h3_match = _SECTION_H3_RE.match(stripped)
        if h3_match:
            # Finalize any in-progress entry before section change
            entry = _finalize_entry(current_entry_lines)
            if entry:
                entries.append(entry)
            current_entry_lines = []
            current_h3 = h3_match.group(1).strip()
            continue

        # Detect entry boundaries
        if _ENTRY_START_RE.match(stripped):
            # Finalize previous entry
            entry = _finalize_entry(current_entry_lines)
            if entry:
                entries.append(entry)
            current_entry_lines = [stripped]
            current_entry_start_line = line_num
            continue

        # Continuation lines: append to current entry
        if current_entry_lines:
            # Continuation: indented or non-empty, non-header, non-entry-start
            if stripped.strip():
                current_entry_lines.append(stripped)
            else:
                # Empty line could end an entry or be within a multi-paragraph
                # entry. We keep accumulating -- the next entry start or
                # section header will finalize.
                pass

    # Finalize last entry
    entry = _finalize_entry(current_entry_lines)
    if entry:
        entries.append(entry)

    return entries, warnings


# --- CLI interface -----------------------------------------------------------

def _format_summary(entries, warnings):
    """Format entries as a human-readable summary."""
    lines = []
    lines.append(f"Parsed {len(entries)} entries")
    if warnings:
        lines.append(f"Warnings: {len(warnings)}")
        for w in warnings:
            lines.append(f"  - {w}")
    lines.append('')

    # Group by section
    sections = {}
    for entry in entries:
        sec = entry.get('section', '') or '(no section)'
        sections.setdefault(sec, []).append(entry)

    for sec, sec_entries in sections.items():
        lines.append(f"## {sec}")
        for entry in sec_entries:
            sev = f" [{entry['severity']}]" if entry['severity'] else ''
            date = f"[{entry['date']}] " if entry['date'] else ''
            tags = ' '.join(entry['tags']) if entry['tags'] else ''
            lines.append(f"  - {date}{entry['title']}{sev} {tags}")
        lines.append('')

    return '\n'.join(lines)


def main():
    """CLI entry point.

    Usage: python3 learnings_parser.py <path> [--format json|summary]
    """
    args = sys.argv[1:]

    if not args or args[0] in ('-h', '--help'):
        print(
            "Usage: python3 learnings_parser.py <path> "
            "[--format json|summary]",
            file=sys.stderr
        )
        print(
            "\nParse a .claude/learnings.md file into structured entries.",
            file=sys.stderr
        )
        print("\nOptions:", file=sys.stderr)
        print(
            "  --format json     Output JSON (default)",
            file=sys.stderr
        )
        print(
            "  --format summary  Output human-readable summary",
            file=sys.stderr
        )
        sys.exit(0 if args else 2)

    filepath = args[0]
    fmt = 'json'

    i = 1
    while i < len(args):
        if args[i] == '--format' and i + 1 < len(args):
            fmt = args[i + 1]
            if fmt not in ('json', 'summary'):
                print(
                    f"Error: unknown format '{fmt}'. "
                    "Use 'json' or 'summary'.",
                    file=sys.stderr
                )
                sys.exit(2)
            i += 2
        else:
            print(f"Error: unknown argument '{args[i]}'", file=sys.stderr)
            sys.exit(2)

    if not os.path.exists(filepath):
        print(f"Error: file not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    entries, warnings = parse_learnings_file(filepath)

    if fmt == 'json':
        output = {
            'entries': entries,
            'warnings': warnings,
            'entry_count': len(entries),
            'warning_count': len(warnings),
        }
        print(json.dumps(output, indent=2))
    else:
        print(_format_summary(entries, warnings))

    sys.exit(0)


if __name__ == '__main__':
    main()
