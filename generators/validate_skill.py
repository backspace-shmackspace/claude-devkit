#!/usr/bin/env python3
"""
Validate Claude Code skill definitions against v2.0.0 architectural patterns.

Usage:
    python validate_skill.py <path-to-SKILL.md> [--strict] [--json]

Examples:
    python validate_skill.py skills/dream/SKILL.md
    python validate_skill.py ./skills/audit/SKILL.md --strict
    python validate_skill.py ./skills/ship/SKILL.md --json
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple, Any


class Colors:
    """ANSI color codes for terminal output."""
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RESET = '\033[0m'
    BOLD = '\033[1m'


def load_patterns(script_dir: Path) -> Dict[str, Any]:
    """Load pattern definitions from skill-patterns.json."""
    patterns_file = script_dir.parent / "configs" / "skill-patterns.json"
    if not patterns_file.exists():
        print(f"Error: Pattern definitions not found at {patterns_file}", file=sys.stderr)
        sys.exit(1)

    with open(patterns_file, 'r') as f:
        return json.load(f)


def parse_frontmatter(content: str) -> Tuple[Dict[str, str], str]:
    """
    Extract YAML frontmatter and body content.
    Returns (frontmatter_dict, body_content).
    """
    # Check for frontmatter delimiters
    if not content.startswith('---\n'):
        return {}, content

    # Find the closing ---
    lines = content.split('\n')
    end_idx = None
    for i in range(1, len(lines)):
        if lines[i] == '---':
            end_idx = i
            break

    if end_idx is None:
        return {}, content

    # Parse frontmatter (simple key: value format)
    frontmatter = {}
    for line in lines[1:end_idx]:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if ':' in line:
            key, value = line.split(':', 1)
            frontmatter[key.strip()] = value.strip().strip('"').strip("'")

    # Body is everything after the closing ---
    body = '\n'.join(lines[end_idx + 1:])
    return frontmatter, body


def validate_frontmatter(frontmatter: Dict[str, str], patterns_config: Dict, is_reference: bool = False) -> List[Dict]:
    """Validate YAML frontmatter against structural requirements."""
    issues = []

    if not frontmatter:
        issues.append({
            "severity": "error",
            "pattern": "Valid YAML Frontmatter",
            "message": "Skill must start with valid YAML frontmatter delimited by --- markers."
        })
        return issues

    # Check required fields (name and description always required)
    required_fields = ["name", "description"]
    for field in required_fields:
        if field not in frontmatter or not frontmatter[field]:
            issues.append({
                "severity": "error",
                "pattern": "Required Frontmatter Fields",
                "message": f"YAML frontmatter missing required field: '{field}'"
            })

    # model is required for executable skills only (not Reference skills)
    if not is_reference:
        if "model" not in frontmatter or not frontmatter["model"]:
            issues.append({
                "severity": "error",
                "pattern": "Required Frontmatter Fields",
                "message": "YAML frontmatter missing required field: 'model'"
            })

    # Validate model field value (if present, for any skill type)
    if "model" in frontmatter:
        valid_models = ["claude-opus-4-6", "claude-sonnet-4-5", "claude-haiku-4-0"]
        if frontmatter["model"] not in valid_models:
            issues.append({
                "severity": "warning",
                "pattern": "Model Selection",
                "message": f"Model '{frontmatter['model']}' may not be recognized. Valid values: {', '.join(valid_models)}"
            })

    # Validate type field (if present)
    if "type" in frontmatter:
        valid_types = ["pipeline", "coordinator", "scan", "reference"]
        if frontmatter["type"] not in valid_types:
            issues.append({
                "severity": "warning",
                "pattern": "Archetype Type",
                "message": f"Unknown type '{frontmatter['type']}'. Valid values: {', '.join(valid_types)}"
            })

    return issues


def validate_workflow_header(content: str, skill_name: str) -> List[Dict]:
    """Validate that workflow header matches skill name."""
    issues = []

    # Look for # /skill-name Workflow pattern
    pattern = rf'^# /{re.escape(skill_name)} Workflow'
    if not re.search(pattern, content, re.MULTILINE):
        issues.append({
            "severity": "error",
            "pattern": "Workflow Header",
            "message": f"Skill must have a '# /{skill_name} Workflow' header."
        })

    return issues


def find_steps(content: str) -> List[Tuple[int, str, str]]:
    """
    Find all step sections in the content.
    Returns list of (step_number, step_title, step_content).
    """
    steps = []

    # Find all step headers: ## Step N -- Title or ## Step N — Title
    step_pattern = r'^## Step (\d+)( —|--) (.+)$'
    lines = content.split('\n')

    for i, line in enumerate(lines):
        match = re.match(step_pattern, line)
        if match:
            step_num = int(match.group(1))
            step_title = match.group(3)

            # Find content until next step or end
            content_lines = []
            for j in range(i + 1, len(lines)):
                if re.match(r'^## Step \d+( —|--)', lines[j]):
                    break
                if re.match(r'^## ', lines[j]) and 'Step' not in lines[j]:
                    # Another section header, stop
                    break
                content_lines.append(lines[j])

            step_content = '\n'.join(content_lines)
            steps.append((step_num, step_title, step_content))

    return steps


def validate_steps(content: str, patterns_config: Dict) -> List[Dict]:
    """Validate step structure and numbering."""
    issues = []

    steps = find_steps(content)

    if len(steps) < 2:
        issues.append({
            "severity": "error",
            "pattern": "Minimum Steps",
            "message": f"Skill must have at least 2 numbered workflow steps. Found: {len(steps)}"
        })

    # Check step numbering is sequential
    expected_num = 0  # Can start with 0 or 1
    for i, (step_num, title, step_content) in enumerate(steps):
        if i == 0:
            expected_num = step_num
        else:
            if step_num != expected_num + 1:
                issues.append({
                    "severity": "warning",
                    "pattern": "Numbered Steps",
                    "message": f"Step numbering not sequential: expected {expected_num + 1}, got {step_num}"
                })
            expected_num = step_num

        # Check for empty steps
        if not step_content.strip():
            issues.append({
                "severity": "error",
                "pattern": "Non-Empty Steps",
                "message": f"Step {step_num} is empty. Every step must have content."
            })

    return issues


def validate_patterns(content: str, patterns_config: Dict) -> List[Dict]:
    """Validate content against all 10 v2.0.0 patterns."""
    issues = []

    for pattern_def in patterns_config.get("patterns", []):
        pattern_type = pattern_def["type"]
        rule = pattern_def["rule"]
        severity = pattern_def["severity"]

        if pattern_type == "keyword":
            if not re.search(rule, content, re.MULTILINE | re.IGNORECASE):
                issues.append({
                    "severity": severity,
                    "pattern": pattern_def["name"],
                    "message": pattern_def["message"]
                })

        elif pattern_type == "regex":
            if not re.search(rule, content, re.MULTILINE):
                issues.append({
                    "severity": severity,
                    "pattern": pattern_def["name"],
                    "message": pattern_def["message"]
                })

        elif pattern_type == "structural":
            # Structural patterns are handled separately
            pass

    # Validate tool declarations per step
    steps = find_steps(content)
    steps_without_tools = []
    for step_num, title, step_content in steps:
        if "Tool:" not in step_content:
            steps_without_tools.append(step_num)

    if steps_without_tools:
        issues.append({
            "severity": "warning",
            "pattern": "Tool Declarations",
            "message": f"Step(s) {', '.join(map(str, steps_without_tools))} missing 'Tool:' declaration. Coordinator/verdict steps may omit this."
        })

    return issues


def validate_inputs_section(content: str) -> List[Dict]:
    """Validate that ## Inputs section exists."""
    issues = []

    if not re.search(r'^## Inputs', content, re.MULTILINE):
        issues.append({
            "severity": "error",
            "pattern": "Scope Parameters",
            "message": "Skill must have an '## Inputs' section documenting what parameters it accepts."
        })

    return issues


def validate_reference_skill(frontmatter: Dict[str, str], body: str, patterns_config: Dict) -> List[Dict]:
    """
    Validate Reference archetype skills.

    Reference skills are behavioral discipline documents (Iron Laws, principles, gates)
    rather than executable workflows. They lack numbered steps, tool declarations,
    verdict gates, and inputs sections. This function checks Reference-specific
    requirements instead.
    """
    issues = []

    # Check required frontmatter fields specific to Reference skills
    # (name and description are already checked by validate_frontmatter)
    ref_required = ["version", "type", "attribution"]
    for field in ref_required:
        if field not in frontmatter or not frontmatter[field]:
            issues.append({
                "severity": "error",
                "pattern": "Reference Frontmatter",
                "message": f"Reference skill missing required field: '{field}'"
            })

    # Check body is non-empty
    if not body.strip():
        issues.append({
            "severity": "error",
            "pattern": "Reference Body",
            "message": "Reference skill body must not be empty. Expected behavioral discipline content."
        })
        return issues  # No point checking headings if body is empty

    # Check for core principle heading
    # Load patterns from config, with fallback defaults
    ref_config = patterns_config.get("archetypes", {}).get("reference", {})
    core_patterns = ref_config.get("core_principle_patterns",
                                   ["Iron Law", "Core Principle", "Fundamental Rule", "The Gate"])

    # Search all headings for any pattern match (case-insensitive substring)
    headings = re.findall(r'^#{1,6}\s+(.+)$', body, re.MULTILINE)
    found_principle = False
    for heading in headings:
        for pattern in core_patterns:
            if pattern.lower() in heading.lower():
                found_principle = True
                break
        if found_principle:
            break

    if not found_principle:
        issues.append({
            "severity": "error",
            "pattern": "Core Principle Heading",
            "message": f"Reference skill must have at least one heading containing: {', '.join(core_patterns)}"
        })

    return issues


def format_human_readable(skill_path: Path, frontmatter: Dict, issues: List[Dict], strict: bool) -> str:
    """Format validation results as human-readable output."""
    output = []

    # Header
    output.append(f"{Colors.BOLD}Skill Validation Report{Colors.RESET}")
    output.append(f"File: {skill_path}")
    if frontmatter.get("name"):
        output.append(f"Skill: {frontmatter['name']} (v{frontmatter.get('version', 'unversioned')})")
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
        output.append("  All v2.0.0 patterns validated successfully.")

    return '\n'.join(output)


def format_json(skill_path: Path, frontmatter: Dict, issues: List[Dict], strict: bool) -> str:
    """Format validation results as JSON."""
    errors = [i for i in issues if i["severity"] == "error"]
    warnings = [i for i in issues if i["severity"] == "warning"]

    passed = len(errors) == 0 and (not strict or len(warnings) == 0)

    result = {
        "skill_path": str(skill_path),
        "skill_name": frontmatter.get("name", "unknown"),
        "skill_version": frontmatter.get("version", "unversioned"),
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
        description="Validate Claude Code skill definitions against v2.0.0 patterns."
    )
    parser.add_argument(
        "skill_path",
        type=Path,
        help="Path to SKILL.md file or skill directory"
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

    # Resolve skill path
    skill_path = args.skill_path
    if skill_path.is_dir():
        skill_path = skill_path / "SKILL.md"

    if not skill_path.exists():
        print(f"Error: Skill file not found: {skill_path}", file=sys.stderr)
        sys.exit(1)

    # Load pattern definitions
    script_dir = Path(__file__).parent
    patterns_config = load_patterns(script_dir)

    # Read skill file
    with open(skill_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Parse frontmatter
    frontmatter, body = parse_frontmatter(content)

    # Detect archetype from frontmatter
    skill_type = frontmatter.get("type", None)
    is_reference = (skill_type == "reference")

    # Run all validations
    issues = []
    issues.extend(validate_frontmatter(frontmatter, patterns_config, is_reference=is_reference))

    if is_reference:
        # Reference-specific validation.
        # NOTE: Do not call validate_workflow_header, validate_inputs_section,
        # validate_steps, or validate_patterns for Reference skills. These check
        # for numbered steps, tool declarations, verdict gates, and other
        # executable-workflow patterns that Reference skills intentionally lack.
        issues.extend(validate_reference_skill(frontmatter, body, patterns_config))
    else:
        # Standard skill validation (existing behavior, unchanged)
        if frontmatter.get("name"):
            issues.extend(validate_workflow_header(content, frontmatter["name"]))

        issues.extend(validate_inputs_section(content))
        issues.extend(validate_steps(content, patterns_config))
        issues.extend(validate_patterns(content, patterns_config))

    # Output results
    if args.json:
        print(format_json(skill_path, frontmatter, issues, args.strict))
    else:
        print(format_human_readable(skill_path, frontmatter, issues, args.strict))

    # Exit code
    errors = [i for i in issues if i["severity"] == "error"]
    warnings = [i for i in issues if i["severity"] == "warning"]

    if errors or (args.strict and warnings):
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
