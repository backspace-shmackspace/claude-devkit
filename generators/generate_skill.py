#!/usr/bin/env python3
"""
Generate Claude Code skill definitions from templates.

Usage:
    python generate_skill.py <skill-name> [options]

Examples:
    python generate_skill.py deploy-check --description "Verify deployment health"
    python generate_skill.py scan-deps --archetype scan --model sonnet
    python generate_skill.py my-skill --archetype coordinator --deploy
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Tuple

GENERATOR_VERSION = "1.0.0"

# Reserved skill names (existing production skills)
RESERVED_NAMES = {"dream", "ship", "audit", "sync"}

# Valid archetypes
ARCHETYPES = {"coordinator", "pipeline", "scan"}

# Valid models
MODELS = {"claude-opus-4-6", "claude-sonnet-4-5"}


class Colors:
    """ANSI color codes for terminal output."""
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RESET = '\033[0m'
    BOLD = '\033[1m'


def validate_skill_name(name: str) -> Tuple[bool, str]:
    """
    Validate skill name against all rules.
    Returns (is_valid, error_message).
    """
    # Min/max length
    if len(name) < 2:
        return False, "Skill name must be at least 2 characters"
    if len(name) > 30:
        return False, "Skill name must be 30 characters or fewer"

    # Alphanumeric + hyphen only
    if not re.match(r'^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$', name):
        return False, "Skill name must contain only lowercase letters, digits, and hyphens (no leading/trailing hyphens)"

    # Reserved names
    if name in RESERVED_NAMES:
        return False, f"'{name}' is a reserved skill name"

    return True, ""


def validate_description(desc: str) -> Tuple[bool, str]:
    """
    Validate description against all rules.
    Returns (is_valid, error_message).
    """
    # Max length
    if len(desc) > 200:
        return False, "Description must be 200 characters or fewer"

    # No newlines
    if '\n' in desc or '\r' in desc:
        return False, "Description must be a single line"

    # No YAML-breaking characters
    if desc.strip().startswith(':'):
        return False, "Description contains characters that would break YAML frontmatter"
    if '---' in desc:
        return False, "Description contains characters that would break YAML frontmatter"

    # No control characters (except space)
    for char in desc:
        if ord(char) < 32 and char not in (' ', '\t'):
            return False, "Description contains invalid control characters"

    return True, ""


def validate_target_dir(path: str) -> Tuple[bool, str]:
    """
    Validate target directory against all rules.
    Returns (is_valid, error_message).
    """
    try:
        # Resolve to absolute path
        resolved = Path(path).resolve()

        # Check if directory exists
        if not resolved.is_dir():
            return False, f"Target directory does not exist: {resolved}"

        # Check if writable
        if not os.access(resolved, os.W_OK):
            return False, f"Target directory is not writable: {resolved}"

        # Path traversal check - must be under ~/workspaces/, claude-devkit's own dir, or /tmp/
        home_workspaces = Path.home() / "workspaces"
        tmp = Path("/tmp").resolve()  # Resolve /tmp to handle /private/tmp on macOS
        # Allow the claude-devkit root (parent of generators/) wherever it lives
        devkit_root = Path(__file__).resolve().parent.parent

        allowed = False
        for allowed_parent in [home_workspaces, tmp, devkit_root]:
            try:
                resolved.relative_to(allowed_parent)
                allowed = True
                break
            except ValueError:
                pass

        if not allowed:
            return False, f"Target directory must be under ~/workspaces/, {devkit_root}, or /tmp/"

        return True, ""
    except Exception as e:
        return False, f"Invalid target directory: {e}"


def run_preflight_checks(target_dir: Path, deploy: bool) -> Tuple[bool, str]:
    """
    Run pre-flight checks on target directory.
    Returns (success, error_message).
    """
    # Check if skills directory can be created
    skills_dir = target_dir / "skills"
    try:
        skills_dir.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        return False, f"Cannot create skills directory: {e}"

    # If deploy flag is set, verify deploy.sh exists and is executable
    if deploy:
        deploy_script = target_dir / "deploy.sh"
        if not deploy_script.exists():
            return False, f"deploy.sh not found at {deploy_script}. Cannot use --deploy flag."
        if not os.access(deploy_script, os.X_OK):
            return False, f"deploy.sh exists but is not executable: {deploy_script}"

    return True, ""


def load_template(archetype: str, script_dir: Path) -> Tuple[bool, str, str]:
    """
    Load template file for the given archetype.
    Returns (success, content, error_message).
    """
    template_file = script_dir.parent / "templates" / f"skill-{archetype}.md.template"

    if not template_file.exists():
        return False, "", f"Template not found: {template_file}. Ensure claude-tools templates/ directory is intact."

    try:
        with open(template_file, 'r') as f:
            content = f.read()
        return True, content, ""
    except Exception as e:
        return False, "", f"Cannot read template: {template_file}. {e}"


def substitute_placeholders(template: str, **kwargs) -> str:
    """Substitute placeholders in template using safe .replace() calls."""
    result = template
    for key, value in kwargs.items():
        result = result.replace('{' + key + '}', str(value))
    return result


def atomic_write(target_path: Path, content: str) -> Tuple[bool, str]:
    """
    Write content to file atomically using temp file + rename.
    Returns (success, error_message).
    """
    # Ensure parent directory exists
    try:
        target_path.parent.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        return False, f"Cannot create directory: {target_path.parent}. {e}"

    # Write to temp file in same directory (ensures same filesystem for atomic rename)
    tmp_path = None
    try:
        fd, tmp_path = tempfile.mkstemp(
            dir=target_path.parent,
            prefix=".skill-",
            suffix=".tmp"
        )

        with os.fdopen(fd, 'w') as f:
            f.write(content)

        # Atomic rename
        os.replace(tmp_path, target_path)
        return True, ""

    except Exception as e:
        # Clean up temp file on failure
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
        return False, f"Cannot write to {target_path}. {e}"


def validate_generated_skill(skill_path: Path, script_dir: Path) -> Tuple[bool, str]:
    """
    Run validate_skill.py on the generated file.
    Returns (success, error_message).
    """
    validator = script_dir / "validate_skill.py"

    if not validator.exists():
        return False, "Validator not found or not executable."

    try:
        result = subprocess.run(
            [sys.executable, str(validator), str(skill_path)],
            capture_output=True,
            text=True,
            timeout=30
        )

        # Print validator output
        if result.stdout:
            print(result.stdout)

        if result.returncode != 0:
            # Validation failed
            return False, "Validation failed. See output above for details."

        return True, ""

    except subprocess.TimeoutExpired:
        return False, "Validator timed out."
    except Exception as e:
        return False, f"Cannot run validator: {e}"


def deploy_skill(skill_name: str, target_dir: Path) -> Tuple[bool, str]:
    """
    Run deploy.sh script to deploy the skill.
    Returns (success, error_message).
    """
    deploy_script = target_dir / "deploy.sh"

    try:
        result = subprocess.run(
            [str(deploy_script), skill_name],
            cwd=target_dir,
            capture_output=True,
            text=True,
            timeout=60
        )

        # Print deploy output
        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)

        if result.returncode != 0:
            return False, f"Deploy failed with exit code {result.returncode}. Generated file preserved for manual deployment."

        return True, ""

    except subprocess.TimeoutExpired:
        return False, "Deploy timed out. Generated file preserved for manual deployment."
    except Exception as e:
        return False, f"Cannot run deploy.sh: {e}"


def interactive_prompt(target_dir: Path) -> dict:
    """
    Prompt user for inputs interactively.
    Returns dict of parameters.
    """
    print(f"{Colors.BLUE}Skill Generator — Interactive Mode{Colors.RESET}")
    print()

    # Description
    description = input("Description (one-line summary): ").strip()

    # Archetype
    print()
    print("Archetype options:")
    print("  coordinator — Delegates to agents, parallel reviews, revision loops (like /architect)")
    print("  pipeline    — Sequential workflow with checkpoints (like /ship)")
    print("  scan        — Parallel scans, severity ratings, synthesis (like /audit)")
    archetype = input("Archetype [coordinator]: ").strip() or "coordinator"

    # Model
    print()
    model = input("Model [claude-opus-4-6]: ").strip() or "claude-opus-4-6"

    # Steps
    print()
    steps_str = input("Number of workflow steps [4]: ").strip() or "4"
    try:
        steps = int(steps_str)
    except ValueError:
        steps = 4

    return {
        "description": description,
        "archetype": archetype,
        "model": model,
        "steps": steps
    }


def generate_skill(
    skill_name: str,
    description: str,
    archetype: str,
    model: str,
    version: str,
    steps: int,
    target_dir: Path,
    deploy: bool,
    force: bool,
    script_dir: Path
) -> int:
    """
    Main generation function.
    Returns exit code (0 = success, 1 = error).
    """
    print(f"{Colors.BOLD}🛠️  Skill Generator v{GENERATOR_VERSION}{Colors.RESET}")
    print()

    # Validate inputs
    valid, error = validate_skill_name(skill_name)
    if not valid:
        print(f"{Colors.RED}❌ Error: {error}{Colors.RESET}", file=sys.stderr)
        return 2

    valid, error = validate_description(description)
    if not valid:
        print(f"{Colors.RED}❌ Error: {error}{Colors.RESET}", file=sys.stderr)
        return 2

    valid, error = validate_target_dir(str(target_dir))
    if not valid:
        print(f"{Colors.RED}❌ Error: {error}{Colors.RESET}", file=sys.stderr)
        return 2

    if archetype not in ARCHETYPES:
        print(f"{Colors.RED}❌ Error: Unknown archetype '{archetype}'. Must be one of: {', '.join(ARCHETYPES)}{Colors.RESET}", file=sys.stderr)
        return 2

    if model not in MODELS:
        print(f"{Colors.RED}❌ Error: Unknown model '{model}'. Must be one of: {', '.join(MODELS)}{Colors.RESET}", file=sys.stderr)
        return 2

    # Pre-flight checks
    print(f"Target directory: {target_dir}")
    print(f"Skill name: {skill_name}")
    print(f"Archetype: {archetype}")
    print()

    success, error = run_preflight_checks(target_dir, deploy)
    if not success:
        print(f"{Colors.RED}❌ Pre-flight check failed: {error}{Colors.RESET}", file=sys.stderr)
        return 2

    # Check if skill already exists
    skill_file = target_dir / "skills" / skill_name / "SKILL.md"
    if skill_file.exists() and not force:
        response = input(f"{Colors.YELLOW}⚠️  Warning: {skill_file} already exists. Overwrite? (y/N): {Colors.RESET}")
        if response.lower() != 'y':
            print("Aborted.")
            return 1

    # Load template
    print(f"Loading template for archetype: {archetype}...")
    success, template, error = load_template(archetype, script_dir)
    if not success:
        print(f"{Colors.RED}❌ {error}{Colors.RESET}", file=sys.stderr)
        return 1

    # Prepare substitution variables
    timestamp = datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
    substitutions = {
        "skill_name": skill_name,
        "description": description,
        "model": model,
        "version": version,
        "step_count": str(steps),
        "timestamp": timestamp,
        "generator_version": GENERATOR_VERSION,
        "archetype": archetype
    }

    # Substitute placeholders
    print(f"Generating skill...")
    content = substitute_placeholders(template, **substitutions)

    # Atomic write
    success, error = atomic_write(skill_file, content)
    if not success:
        print(f"{Colors.RED}❌ {error}{Colors.RESET}", file=sys.stderr)
        return 1

    print(f"{Colors.GREEN}✅ Generated: {skill_file}{Colors.RESET}")
    print()

    # Validate generated file
    print(f"Validating generated skill...")
    success, error = validate_generated_skill(skill_file, script_dir)
    if not success:
        # Remove generated file on validation failure
        try:
            skill_file.unlink()
            print(f"{Colors.RED}❌ {error}{Colors.RESET}", file=sys.stderr)
            print(f"{Colors.YELLOW}Generated file removed due to validation failure.{Colors.RESET}", file=sys.stderr)
        except OSError:
            print(f"{Colors.RED}❌ {error}{Colors.RESET}", file=sys.stderr)
        return 1

    print(f"{Colors.GREEN}✅ Validation passed{Colors.RESET}")
    print()

    # Deploy if requested
    if deploy:
        print(f"Deploying skill...")
        success, error = deploy_skill(skill_name, target_dir)
        if not success:
            print(f"{Colors.RED}❌ {error}{Colors.RESET}", file=sys.stderr)
            print(f"{Colors.YELLOW}Generated file preserved at: {skill_file}{Colors.RESET}")
            return 1

        print(f"{Colors.GREEN}✅ Deployed successfully{Colors.RESET}")
        print()

    # Print next steps
    print(f"{Colors.BOLD}Next steps:{Colors.RESET}")
    print(f"1. Customize the skill: {skill_file}")
    print(f"   - Replace [TODO: ...] placeholders with actual logic")
    print(f"   - Adjust prompts and tool declarations")
    print(f"   - Add project-specific validation")
    print(f"2. Test the skill manually")
    if not deploy:
        print(f"3. Deploy: cd {target_dir} && ./deploy.sh {skill_name}")
        print(f"4. Use the skill: /{skill_name} [arguments]")
    else:
        print(f"3. Use the skill: /{skill_name} [arguments]")
    print()
    print(f"Generated file contains metadata:")
    print(f"  - Generator version: {GENERATOR_VERSION}")
    print(f"  - Archetype: {archetype}")
    print(f"  - Timestamp: {timestamp}")
    print()
    print(f"{Colors.GREEN}Done! 🎉{Colors.RESET}")

    return 0


def main():
    parser = argparse.ArgumentParser(
        description='Generate Claude Code skill definitions from templates',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  %(prog)s deploy-check --description "Verify deployment health"
  %(prog)s scan-deps --archetype scan --model sonnet
  %(prog)s my-skill --archetype coordinator --deploy --force
  %(prog)s check-config  # Interactive mode (prompts for all inputs)
        '''
    )

    parser.add_argument(
        'skill_name',
        help='Name of the skill (lowercase, alphanumeric + hyphen)'
    )

    parser.add_argument(
        '--description', '-d',
        help='One-line skill description (required for non-interactive mode)'
    )

    parser.add_argument(
        '--archetype', '-a',
        choices=list(ARCHETYPES),
        default='coordinator',
        help='Workflow archetype (default: coordinator)'
    )

    parser.add_argument(
        '--model', '-m',
        choices=list(MODELS),
        default='claude-opus-4-6',
        help='Claude model (default: claude-opus-4-6)'
    )

    parser.add_argument(
        '--version', '-v',
        default='1.0.0',
        help='Skill version (default: 1.0.0)'
    )

    parser.add_argument(
        '--steps', '-s',
        type=int,
        default=4,
        help='Number of workflow steps (default: 4)'
    )

    parser.add_argument(
        '--target-dir', '-t',
        default=str(Path(__file__).resolve().parent.parent),
        help='Target directory containing skills/ (default: claude-devkit repo root)'
    )

    parser.add_argument(
        '--deploy',
        action='store_true',
        help='Run deploy.sh after generation'
    )

    parser.add_argument(
        '--force', '-f',
        action='store_true',
        help='Overwrite existing skill without prompting'
    )

    args = parser.parse_args()

    script_dir = Path(__file__).parent.resolve()
    target_dir = Path(args.target_dir).resolve()

    # Interactive mode if no description provided
    if not args.description:
        interactive_params = interactive_prompt(target_dir)
        description = interactive_params["description"]
        archetype = interactive_params.get("archetype", args.archetype)
        model = interactive_params.get("model", args.model)
        steps = interactive_params.get("steps", args.steps)
    else:
        description = args.description
        archetype = args.archetype
        model = args.model
        steps = args.steps

    return generate_skill(
        args.skill_name,
        description,
        archetype,
        model,
        args.version,
        steps,
        target_dir,
        args.deploy,
        args.force,
        script_dir
    )


if __name__ == '__main__':
    sys.exit(main())
