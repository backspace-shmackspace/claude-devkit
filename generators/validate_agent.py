#!/usr/bin/env python3
"""
Validate Claude Code specialist agents against inheritance and structure requirements.

Usage:
    python validate_agent.py <path-to-agent.md> [--strict] [--json]

Examples:
    python validate_agent.py .claude/agents/coder-security.md
    python validate_agent.py .claude/agents/*.md
    python validate_agent.py .claude/agents/code-reviewer.md --json
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Any


class Colors:
    """ANSI color codes for terminal output."""
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RESET = '\033[0m'
    BOLD = '\033[1m'


def parse_agent_header(content: str) -> Dict[str, str]:
    """
    Parse agent header section.
    Returns dict with: base_agent, base_version, specialist_id, specialist_version.
    """
    header = {}

    # Look for Inheritance or Identity section
    is_standalone = '# Identity' in content.split('\n')[0:10]

    if is_standalone:
        # Standalone agent (like code-reviewer)
        header['is_standalone'] = True

        # Extract Agent ID
        match = re.search(r'^Agent ID:\s*(.+)$', content, re.MULTILINE)
        if match:
            header['agent_id'] = match.group(1).strip()

        # Extract Version
        match = re.search(r'^Version:\s*(.+)$', content, re.MULTILINE)
        if match:
            header['version'] = match.group(1).strip()

        return header

    # Specialist agent with inheritance
    header['is_standalone'] = False

    patterns = {
        'base_agent': r'^Base Agent:\s*(.+)$',
        'base_version': r'^Base Version:\s*(.+)$',
        'specialist_id': r'^Specialist ID:\s*(.+)$',
        'specialist_version': r'^Specialist Version:\s*(.+)$'
    }

    for key, pattern in patterns.items():
        match = re.search(pattern, content, re.MULTILINE)
        if match:
            header[key] = match.group(1).strip()

    return header


def validate_inheritance_header(content: str, filename: str) -> List[Dict]:
    """Validate inheritance header for specialist agents."""
    issues = []

    header = parse_agent_header(content)

    # Check if standalone
    if header.get('is_standalone'):
        # Standalone agents don't need inheritance header
        return issues

    # Check for Inheritance header
    if not re.search(r'^# Inheritance', content, re.MULTILINE):
        issues.append({
            "severity": "error",
            "pattern": "Inheritance Header",
            "message": "Specialist agent must have '# Inheritance' header."
        })
        return issues

    # Check required fields
    required_fields = ['base_agent', 'base_version', 'specialist_id', 'specialist_version']
    for field in required_fields:
        if field not in header:
            issues.append({
                "severity": "error",
                "pattern": "Inheritance Fields",
                "message": f"Missing required field: '{field}'"
            })

    # Validate specialist_id matches filename
    if 'specialist_id' in header:
        expected_filename = f"{header['specialist_id']}.md"
        if filename != expected_filename:
            issues.append({
                "severity": "warning",
                "pattern": "Filename Match",
                "message": f"Specialist ID '{header['specialist_id']}' doesn't match filename '{filename}'. Expected: {expected_filename}"
            })

    # Validate base_version format (should be semantic version)
    if 'base_version' in header:
        if not re.match(r'^\d+\.\d+\.\d+$', header['base_version']):
            issues.append({
                "severity": "warning",
                "pattern": "Version Format",
                "message": f"Base version '{header['base_version']}' should be semantic version (e.g., '2.1.0')"
            })

    return issues


def validate_tech_stack_override(content: str) -> List[Dict]:
    """Validate Tech Stack Override section."""
    issues = []

    header = parse_agent_header(content)

    # Skip for standalone agents
    if header.get('is_standalone'):
        return issues

    # Check for Tech Stack Override or Testing Framework Override section
    has_override = (
        re.search(r'^# Tech Stack Override', content, re.MULTILINE) or
        re.search(r'^# Testing Framework Override', content, re.MULTILINE) or
        re.search(r'^# Review Dimensions Override', content, re.MULTILINE) or
        re.search(r'^# Architecture Patterns Override', content, re.MULTILINE)
    )

    if not has_override:
        issues.append({
            "severity": "error",
            "pattern": "Tech Stack Override",
            "message": "Specialist agent must have an override section (Tech Stack, Testing Framework, Review Dimensions, etc.)"
        })

    # Check for REPLACES keyword
    if not re.search(r'\*\*REPLACES:\*\*', content):
        issues.append({
            "severity": "warning",
            "pattern": "REPLACES Keyword",
            "message": "Override section should include '**REPLACES:**' to indicate which placeholder it replaces."
        })

    return issues


def validate_claude_md_reference(content: str) -> List[Dict]:
    """Validate CLAUDE.md reference."""
    issues = []

    # Check for Project Patterns Reference section
    if not re.search(r'^# Project Patterns Reference', content, re.MULTILINE):
        issues.append({
            "severity": "error",
            "pattern": "CLAUDE.md Reference",
            "message": "Agent must have '# Project Patterns Reference' section."
        })

    # Check for READ FIRST directive
    if not re.search(r'\*\*READ FIRST:\*\*.*CLAUDE\.md', content):
        issues.append({
            "severity": "error",
            "pattern": "READ FIRST Directive",
            "message": "Agent must include '**READ FIRST:** ../../../CLAUDE.md' or similar."
        })

    # Validate path format
    claude_md_refs = re.findall(r'\.\.\/.*CLAUDE\.md', content)
    valid_paths = ['../../../CLAUDE.md', '../../CLAUDE.md', '../CLAUDE.md']

    for ref in claude_md_refs:
        if ref not in valid_paths:
            issues.append({
                "severity": "warning",
                "pattern": "CLAUDE.md Path",
                "message": f"CLAUDE.md reference uses non-standard path: '{ref}'. Typical path is '../../../CLAUDE.md'"
            })

    return issues


def validate_no_base_duplication(content: str, header: Dict) -> List[Dict]:
    """Check for duplicated content from base agent."""
    issues = []

    # Skip for standalone agents
    if header.get('is_standalone'):
        return issues

    # Look for suspicious patterns that suggest copy/paste from base
    # Note: Allow [PLACEHOLDER] in REPLACES comments, only flag if used as actual content
    suspicious_patterns = [
        (r'^(?!.*REPLACES:).*\[TECH_STACK_PLACEHOLDER\]', "Contains placeholder from base agent (should be replaced)"),
        (r'^(?!.*REPLACES:).*\[PROJECT_PATTERNS_PLACEHOLDER\]', "Contains placeholder from base agent (should be replaced)"),
        (r'^(?!.*REPLACES:).*\[TESTING_FRAMEWORK_PLACEHOLDER\]', "Contains placeholder from base agent (should be replaced)"),
        (r'Type: Base Archetype', "Contains 'Type: Base Archetype' (should be 'Type: Specialist')"),
    ]

    for pattern, message in suspicious_patterns:
        if re.search(pattern, content):
            issues.append({
                "severity": "error",
                "pattern": "Base Content Duplication",
                "message": message
            })

    # Check for excessive content (>500 lines suggests full base copy)
    line_count = len(content.split('\n'))
    if line_count > 500:
        issues.append({
            "severity": "warning",
            "pattern": "Content Length",
            "message": f"Agent has {line_count} lines. Specialist agents should be concise (<200 lines typically). Check for duplicated base content."
        })

    return issues


def validate_conflict_resolution(content: str) -> List[Dict]:
    """Validate conflict resolution section."""
    issues = []

    if not re.search(r'^# Conflict Resolution', content, re.MULTILINE):
        issues.append({
            "severity": "warning",
            "pattern": "Conflict Resolution",
            "message": "Agent should have '# Conflict Resolution' section explaining precedence."
        })

    return issues


def format_human_readable(agent_path: Path, header: Dict, issues: List[Dict], strict: bool) -> str:
    """Format validation results as human-readable output."""
    output = []

    # Header
    output.append(f"{Colors.BOLD}Agent Validation Report{Colors.RESET}")
    output.append(f"File: {agent_path}")

    if header.get('is_standalone'):
        output.append(f"Type: Standalone Agent")
        if header.get('agent_id'):
            output.append(f"Agent: {header['agent_id']} (v{header.get('version', 'unknown')})")
    else:
        if header.get('specialist_id'):
            output.append(f"Agent: {header['specialist_id']} (v{header.get('specialist_version', 'unknown')})")
        if header.get('base_agent'):
            output.append(f"Inherits: {header['base_agent']} (v{header.get('base_version', 'unknown')})")

    output.append("")

    # Separate errors and warnings
    errors = [i for i in issues if i["severity"] == "error"]
    warnings = [i for i in issues if i["severity"] == "warning"]

    # Display errors
    if errors:
        output.append(f"{Colors.RED}✗ Errors ({len(errors)}):{Colors.RESET}")
        for issue in errors:
            output.append(f"  • {Colors.RED}{issue['pattern']}{Colors.RESET}: {issue['message']}")
        output.append("")

    # Display warnings
    if warnings and (strict or not errors):
        output.append(f"{Colors.YELLOW}⚠ Warnings ({len(warnings)}):{Colors.RESET}")
        for issue in warnings:
            output.append(f"  • {Colors.YELLOW}{issue['pattern']}{Colors.RESET}: {issue['message']}")
        output.append("")

    # Verdict
    if errors or (strict and warnings):
        output.append(f"{Colors.RED}✗ FAIL{Colors.RESET}")
        if errors:
            output.append(f"  {len(errors)} error(s) must be fixed.")
        if strict and warnings:
            output.append(f"  {len(warnings)} warning(s) must be addressed (--strict mode).")
    elif warnings:
        output.append(f"{Colors.YELLOW}✓ PASS (with warnings){Colors.RESET}")
        output.append(f"  {len(warnings)} optional improvement(s) suggested.")
    else:
        output.append(f"{Colors.GREEN}✓ PASS{Colors.RESET}")
        output.append("  Agent structure validated successfully.")

    return '\n'.join(output)


def format_json(agent_path: Path, header: Dict, issues: List[Dict], strict: bool) -> str:
    """Format validation results as JSON."""
    errors = [i for i in issues if i["severity"] == "error"]
    warnings = [i for i in issues if i["severity"] == "warning"]

    passed = len(errors) == 0 and (not strict or len(warnings) == 0)

    result = {
        "agent_path": str(agent_path),
        "agent_type": "standalone" if header.get('is_standalone') else "specialist",
        "agent_id": header.get('agent_id') or header.get('specialist_id', 'unknown'),
        "base_agent": header.get('base_agent'),
        "base_version": header.get('base_version'),
        "passed": passed,
        "errors": errors,
        "warnings": warnings,
        "summary": {
            "error_count": len(errors),
            "warning_count": len(warnings),
            "verdict": "PASS" if passed else "FAIL"
        }
    }

    return json.dumps(result, indent=2)


def main():
    parser = argparse.ArgumentParser(
        description="Validate Claude Code specialist agents."
    )
    parser.add_argument(
        "agent_path",
        type=Path,
        nargs='+',
        help="Path to agent .md file(s)"
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail on warnings (not just errors)"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output JSON instead of human-readable report"
    )

    args = parser.parse_args()

    all_passed = True

    for agent_path in args.agent_path:
        if not agent_path.exists():
            print(f"Error: Agent file not found: {agent_path}", file=sys.stderr)
            all_passed = False
            continue

        # Read agent file
        with open(agent_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # Parse header
        header = parse_agent_header(content)

        # Run all validations
        issues = []
        issues.extend(validate_inheritance_header(content, agent_path.name))
        issues.extend(validate_tech_stack_override(content))
        issues.extend(validate_claude_md_reference(content))
        issues.extend(validate_no_base_duplication(content, header))
        issues.extend(validate_conflict_resolution(content))

        # Output results
        if args.json:
            print(format_json(agent_path, header, issues, args.strict))
        else:
            print(format_human_readable(agent_path, header, issues, args.strict))
            if len(args.agent_path) > 1:
                print("")  # Separator between multiple files

        # Track overall pass/fail
        errors = [i for i in issues if i["severity"] == "error"]
        warnings = [i for i in issues if i["severity"] == "warning"]

        if errors or (args.strict and warnings):
            all_passed = False

    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
