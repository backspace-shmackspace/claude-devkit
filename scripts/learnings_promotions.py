#!/usr/bin/env python3
"""Promotion lifecycle tracker for cross-project learnings.

Manages the CANDIDATE -> PROPOSED -> APPROVED -> PROMOTED lifecycle
(with REJECTED branch) for learnings entries identified as promotion
candidates.

State is stored in ~/.claude-devkit/learnings/promotions.json.

Python 3.8+, stdlib only.
"""

import getpass
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone

# --- Constants ---------------------------------------------------------------

_DEVKIT_DIR = os.path.expanduser('~/.claude-devkit')
_LEARNINGS_DIR = os.path.join(_DEVKIT_DIR, 'learnings')
_PROMOTIONS_PATH = os.path.join(_LEARNINGS_DIR, 'promotions.json')

# M-S3: Strict promo-ID validation
_PROMO_ID_RE = re.compile(r'^promo-[0-9]{8}-[a-f0-9]{6}$')

# M-S7: Strict commit SHA validation
_COMMIT_SHA_RE = re.compile(r'^[a-f0-9]{7,40}$')

# Valid promotion types
_VALID_PROMOTION_TYPES = (
    'skill_rule',
    'coder_prompt',
    'reviewer_prompt',
    'hook_config',
    'validation_pattern',
    'learnings_template',
)

# Valid statuses
_VALID_STATUSES = ('CANDIDATE', 'PROPOSED', 'APPROVED', 'PROMOTED', 'REJECTED')

# E-2: Security-sensitive file patterns
_SECURITY_PATTERNS = (
    'secrets-scan',
    'secure-review',
    'dependency-audit',
    'threat-model',
    'security',
)


# --- State management -------------------------------------------------------

def _get_actor():
    """Get current actor identity for audit trail (R-1)."""
    try:
        return getpass.getuser()
    except Exception:
        return os.environ.get('USER', 'unknown')


def _now_iso():
    """Return current UTC time as ISO 8601 string."""
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def _generate_promo_id(entry_id):
    """Generate a unique promo-ID.

    Format: promo-YYYYMMDD-<hash[:6]>
    The hash includes entry_id + timestamp for uniqueness.
    """
    now = datetime.now(timezone.utc)
    date_part = now.strftime('%Y%m%d')
    unique = hashlib.sha256(
        f"{entry_id}-{now.isoformat()}".encode()
    ).hexdigest()[:6]
    return f"promo-{date_part}-{unique}"


def _load_promotions():
    """Load promotions state. Returns dict with schema."""
    if not os.path.isfile(_PROMOTIONS_PATH):
        return {
            'schema_version': '1.0.0',
            'updated_at': _now_iso(),
            'promotions': [],
        }
    try:
        with open(_PROMOTIONS_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
        if not isinstance(data, dict) or 'promotions' not in data:
            return {
                'schema_version': '1.0.0',
                'updated_at': _now_iso(),
                'promotions': [],
            }
        return data
    except (json.JSONDecodeError, OSError):
        return {
            'schema_version': '1.0.0',
            'updated_at': _now_iso(),
            'promotions': [],
        }


def _save_promotions(data):
    """Save promotions state atomically.

    TB2: Directory 0o700, file 0o600.
    """
    data['updated_at'] = _now_iso()
    _atomic_write_json(_PROMOTIONS_PATH, data)


def _atomic_write_json(path, data):
    """Write JSON data atomically using temp file + os.replace()."""
    parent = os.path.dirname(path)
    os.makedirs(parent, mode=0o700, exist_ok=True)

    tmp_path = path + '.tmp'
    try:
        with open(tmp_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2)
            f.write('\n')
        os.replace(tmp_path, path)
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
    except OSError:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def _is_security_sensitive(target_file):
    """Check if a target file is security-sensitive (E-2).

    Returns True if the file path matches any security-related pattern.
    """
    if not target_file:
        return False
    target_lower = target_file.lower()
    return any(pattern in target_lower for pattern in _SECURITY_PATTERNS)


def _find_promotion(data, promo_id):
    """Find a promotion entry by promo-ID. Returns (index, entry) or None."""
    for i, entry in enumerate(data['promotions']):
        if entry.get('id') == promo_id:
            return i, entry
    return None


# --- Commands ----------------------------------------------------------------

def cmd_propose(args):
    """Propose a promotion for an entry.

    Usage: propose <entry-id> --type <type> --target <file> --description <desc>
           [--tag <tag>] [--source-projects <p1,p2,...>]
    """
    if len(args) < 1:
        print(
            "Usage: propose <entry-id> --type <type> --target <file> "
            "--description <desc>",
            file=sys.stderr
        )
        return 2

    entry_id = args[0]
    promo_type = None
    target_file = None
    description = None
    title = None
    source_tags = []
    source_projects = []

    i = 1
    while i < len(args):
        if args[i] == '--type' and i + 1 < len(args):
            promo_type = args[i + 1]
            i += 2
        elif args[i] == '--target' and i + 1 < len(args):
            target_file = args[i + 1]
            i += 2
        elif args[i] == '--description' and i + 1 < len(args):
            description = args[i + 1]
            i += 2
        elif args[i] == '--title' and i + 1 < len(args):
            title = args[i + 1]
            i += 2
        elif args[i] == '--tag' and i + 1 < len(args):
            source_tags.append(args[i + 1])
            i += 2
        elif args[i] == '--source-projects' and i + 1 < len(args):
            source_projects = [
                p.strip() for p in args[i + 1].split(',') if p.strip()
            ]
            i += 2
        else:
            print(f"Error: unknown argument '{args[i]}'", file=sys.stderr)
            return 2

    if not promo_type:
        print("Error: --type is required", file=sys.stderr)
        return 2
    if promo_type not in _VALID_PROMOTION_TYPES:
        print(
            f"Error: invalid promotion type '{promo_type}'. "
            f"Valid types: {', '.join(_VALID_PROMOTION_TYPES)}",
            file=sys.stderr
        )
        return 2
    if not target_file:
        print("Error: --target is required", file=sys.stderr)
        return 2
    if not description:
        print("Error: --description is required", file=sys.stderr)
        return 2

    data = _load_promotions()

    # Check for duplicate entry_id (skip already-tracked entries)
    for existing in data['promotions']:
        if existing.get('entry_id') == entry_id:
            print(
                f"Entry {entry_id} already tracked as {existing['id']} "
                f"(status: {existing['status']})",
                file=sys.stderr
            )
            return 0  # Not an error -- plan says "skip entries already in"

    promo_id = _generate_promo_id(entry_id)
    actor = _get_actor()

    promotion = {
        'id': promo_id,
        'entry_id': entry_id,
        'title': title or entry_id,
        'status': 'PROPOSED',
        'proposed_at': _now_iso(),
        'proposed_by': actor,
        'approved_at': None,
        'approved_by': None,
        'promoted_at': None,
        'promoted_by': None,
        'rejected_at': None,
        'rejected_by': None,
        'reject_reason': None,
        'promotion_type': promo_type,
        'target_file': target_file,
        'target_description': description,
        'commit_sha': None,
        'source_projects': source_projects,
        'source_tags': source_tags,
        'security_sensitive': _is_security_sensitive(target_file),
    }

    data['promotions'].append(promotion)
    _save_promotions(data)

    sec_flag = ' [SECURITY-SENSITIVE]' if promotion['security_sensitive'] else ''
    print(f"Proposed: {promo_id}{sec_flag}")
    print(f"  Entry: {entry_id}")
    print(f"  Type: {promo_type}")
    print(f"  Target: {target_file}")
    print(f"  By: {actor}")
    return 0


def cmd_approve(args):
    """Approve a proposed promotion.

    Usage: approve <promo-id>
    """
    if len(args) < 1:
        print("Usage: approve <promo-id>", file=sys.stderr)
        return 2

    promo_id = args[0]

    # M-S3: Validate promo-ID
    if not _PROMO_ID_RE.match(promo_id):
        print(
            f"Error: invalid promo-ID format '{promo_id}'. "
            "Expected: promo-YYYYMMDD-hex6",
            file=sys.stderr
        )
        return 1

    data = _load_promotions()
    result = _find_promotion(data, promo_id)
    if result is None:
        print(f"Error: promotion not found: {promo_id}", file=sys.stderr)
        return 1

    idx, promotion = result

    if promotion['status'] != 'PROPOSED':
        print(
            f"Error: cannot approve -- current status is "
            f"{promotion['status']} (expected PROPOSED)",
            file=sys.stderr
        )
        return 1

    actor = _get_actor()
    promotion['status'] = 'APPROVED'
    promotion['approved_at'] = _now_iso()
    promotion['approved_by'] = actor
    data['promotions'][idx] = promotion
    _save_promotions(data)

    print(f"Approved: {promo_id}")
    print(f"  By: {actor}")
    print("  Next: implement the change, then run:")
    print(
        f"  python3 scripts/learnings_promotions.py promote "
        f"{promo_id} --commit <sha>"
    )
    return 0


def cmd_promote(args):
    """Mark an approved promotion as promoted with commit SHA.

    Usage: promote <promo-id> --commit <sha>
    """
    if len(args) < 1:
        print("Usage: promote <promo-id> --commit <sha>", file=sys.stderr)
        return 2

    promo_id = args[0]
    commit_sha = None

    i = 1
    while i < len(args):
        if args[i] == '--commit' and i + 1 < len(args):
            commit_sha = args[i + 1]
            i += 2
        else:
            print(f"Error: unknown argument '{args[i]}'", file=sys.stderr)
            return 2

    if not commit_sha:
        print("Error: --commit is required", file=sys.stderr)
        return 2

    # M-S3: Validate promo-ID
    if not _PROMO_ID_RE.match(promo_id):
        print(
            f"Error: invalid promo-ID format '{promo_id}'. "
            "Expected: promo-YYYYMMDD-hex6",
            file=sys.stderr
        )
        return 1

    # M-S7: Validate commit SHA
    if not _COMMIT_SHA_RE.match(commit_sha):
        print(
            f"Error: invalid commit SHA '{commit_sha}'. "
            "Expected: 7-40 hex characters",
            file=sys.stderr
        )
        return 1

    data = _load_promotions()
    result = _find_promotion(data, promo_id)
    if result is None:
        print(f"Error: promotion not found: {promo_id}", file=sys.stderr)
        return 1

    idx, promotion = result

    if promotion['status'] != 'APPROVED':
        print(
            f"Error: cannot promote -- current status is "
            f"{promotion['status']} (expected APPROVED)",
            file=sys.stderr
        )
        return 1

    actor = _get_actor()
    promotion['status'] = 'PROMOTED'
    promotion['promoted_at'] = _now_iso()
    promotion['promoted_by'] = actor
    promotion['commit_sha'] = commit_sha
    data['promotions'][idx] = promotion
    _save_promotions(data)

    print(f"Promoted: {promo_id}")
    print(f"  Commit: {commit_sha}")
    print(f"  By: {actor}")
    return 0


def cmd_reject(args):
    """Reject a proposed or approved promotion.

    Usage: reject <promo-id> --reason <reason>
    """
    if len(args) < 1:
        print("Usage: reject <promo-id> --reason <reason>", file=sys.stderr)
        return 2

    promo_id = args[0]
    reason = None

    i = 1
    while i < len(args):
        if args[i] == '--reason' and i + 1 < len(args):
            reason = args[i + 1]
            i += 2
        else:
            print(f"Error: unknown argument '{args[i]}'", file=sys.stderr)
            return 2

    if not reason:
        print("Error: --reason is required", file=sys.stderr)
        return 2

    # M-S3: Validate promo-ID
    if not _PROMO_ID_RE.match(promo_id):
        print(
            f"Error: invalid promo-ID format '{promo_id}'. "
            "Expected: promo-YYYYMMDD-hex6",
            file=sys.stderr
        )
        return 1

    data = _load_promotions()
    result = _find_promotion(data, promo_id)
    if result is None:
        print(f"Error: promotion not found: {promo_id}", file=sys.stderr)
        return 1

    idx, promotion = result

    if promotion['status'] not in ('PROPOSED', 'APPROVED'):
        print(
            f"Error: cannot reject -- current status is "
            f"{promotion['status']} (expected PROPOSED or APPROVED)",
            file=sys.stderr
        )
        return 1

    actor = _get_actor()
    promotion['status'] = 'REJECTED'
    promotion['rejected_at'] = _now_iso()
    promotion['rejected_by'] = actor
    promotion['reject_reason'] = reason
    data['promotions'][idx] = promotion
    _save_promotions(data)

    print(f"Rejected: {promo_id}")
    print(f"  Reason: {reason}")
    print(f"  By: {actor}")
    return 0


def cmd_list(args):
    """List all promotions, optionally filtered by status.

    Usage: list [--status PROPOSED|APPROVED|PROMOTED|REJECTED]
    """
    status_filter = None

    i = 0
    while i < len(args):
        if args[i] == '--status' and i + 1 < len(args):
            status_filter = args[i + 1].upper()
            if status_filter not in _VALID_STATUSES:
                print(
                    f"Error: invalid status '{status_filter}'. "
                    f"Valid: {', '.join(_VALID_STATUSES)}",
                    file=sys.stderr
                )
                return 2
            i += 2
        else:
            print(f"Error: unknown argument '{args[i]}'", file=sys.stderr)
            return 2

    data = _load_promotions()
    promotions = data.get('promotions', [])

    if status_filter:
        promotions = [
            p for p in promotions if p.get('status') == status_filter
        ]

    if not promotions:
        status_msg = f" with status {status_filter}" if status_filter else ""
        print(f"No promotions found{status_msg}.")
        return 0

    for p in promotions:
        sec = ' [SEC]' if p.get('security_sensitive') else ''
        print(f"[{p['status']}] {p['id']}{sec}")
        print(f"  Title: {p.get('title', 'N/A')}")
        print(f"  Type: {p.get('promotion_type', 'N/A')}")
        print(f"  Target: {p.get('target_file', 'N/A')}")
        if p.get('proposed_by'):
            print(f"  Proposed by: {p['proposed_by']} at {p['proposed_at']}")
        if p.get('approved_by'):
            print(f"  Approved by: {p['approved_by']} at {p['approved_at']}")
        if p.get('promoted_by'):
            print(
                f"  Promoted by: {p['promoted_by']} at {p['promoted_at']}"
                f" (commit: {p.get('commit_sha', 'N/A')})"
            )
        if p.get('rejected_by'):
            print(
                f"  Rejected by: {p['rejected_by']} at {p['rejected_at']}"
                f" (reason: {p.get('reject_reason', 'N/A')})"
            )
        print()

    print(f"Total: {len(promotions)} promotion(s)")
    return 0


# --- Main entry point --------------------------------------------------------

def main():
    """CLI entry point.

    Usage: python3 learnings_promotions.py <command> [args...]

    Commands:
      propose <entry-id> --type <type> --target <file> --description <desc>
      approve <promo-id>
      promote <promo-id> --commit <sha>
      reject  <promo-id> --reason <reason>
      list    [--status STATUS]
    """
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        print(
            "Usage: python3 learnings_promotions.py <command> [args...]",
            file=sys.stderr
        )
        print("\nCommands:", file=sys.stderr)
        print(
            "  propose <entry-id> --type <type> --target <file> "
            "--description <desc>",
            file=sys.stderr
        )
        print("  approve <promo-id>", file=sys.stderr)
        print("  promote <promo-id> --commit <sha>", file=sys.stderr)
        print("  reject  <promo-id> --reason <reason>", file=sys.stderr)
        print("  list    [--status STATUS]", file=sys.stderr)
        sys.exit(0 if len(sys.argv) > 1 else 2)

    command = sys.argv[1]
    cmd_args = sys.argv[2:]

    dispatch = {
        'propose': cmd_propose,
        'approve': cmd_approve,
        'promote': cmd_promote,
        'reject': cmd_reject,
        'list': cmd_list,
    }

    if command not in dispatch:
        print(f"Error: unknown command '{command}'", file=sys.stderr)
        print(
            f"Valid commands: {', '.join(dispatch.keys())}",
            file=sys.stderr
        )
        sys.exit(2)

    exit_code = dispatch[command](cmd_args)
    sys.exit(exit_code)


if __name__ == '__main__':
    main()
