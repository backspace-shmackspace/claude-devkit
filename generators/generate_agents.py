#!/usr/bin/env python3
"""
Generate specialist agents for Claude Code projects.

This unified generator creates all agent types (coder, code-reviewer, qa-engineer,
security-analyst, senior-architect) with auto-detection and template substitution.

Usage:
    python generate_agents.py [target-directory] --type TYPE [--tech-stack STACK] [--force]

Examples:
    python generate_agents.py . --type coder
    python generate_agents.py . --type all
    python generate_agents.py ~/projects/my-app --type qa-engineer --tech-stack "Python FastAPI"
    python generate_agents.py . --type code-reviewer --force
"""

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple


# Agent type definitions
AGENT_TYPES = {
    "coder": {
        "base_agent": "coder-base.md",
        "base_version": "2.1.0",
        "description": "Code implementation specialist",
        "template_file": "coder-specialist.md.template",
        "temperature": 0.2,
    },
    "qa-engineer": {
        "base_agent": "qa-engineer-base.md",
        "base_version": "1.8.0",
        "description": "Testing and validation specialist",
        "template_file": "qa-engineer-specialist.md.template",
        "temperature": 0.1,
    },
    "code-reviewer": {
        "base_agent": None,  # Standalone, no inheritance
        "base_version": None,
        "description": "Code review for /ship skill (standalone)",
        "template_file": "code-reviewer-standalone.md.template",
        "temperature": 0.1,
    },
    "code-reviewer-specialist": {
        "base_agent": "code-reviewer-base.md",
        "base_version": "1.0.0",
        "description": "Security-focused code review specialist",
        "template_file": "code-reviewer-specialist.md.template",
        "temperature": 0.1,
    },
    "security-analyst": {
        "base_agent": "architect-base.md",
        "base_version": "1.5.0",
        "description": "Threat modeling and security planning specialist",
        "template_file": "security-analyst.md.template",
        "temperature": 0.1,
    },
    "senior-architect": {
        "base_agent": "architect-base.md",
        "base_version": "1.5.0",
        "description": "High-level design and implementation planning",
        "template_file": "senior-architect.md.template",
        "temperature": 0.7,
    }
}


def detect_tech_stack(target_dir: Path) -> Dict[str, any]:
    """
    Detect project tech stack from common files.
    Returns dict with detected language, framework, tools, and suggestions.
    """
    result = {
        "language": None,
        "framework": None,
        "security_tools": [],
        "test_framework": None,
        "is_security_focused": False,
        "is_frontend": False,
        "suggested_agents": []
    }

    # Check for Python
    pyproject_toml = target_dir / "pyproject.toml"
    requirements_txt = target_dir / "requirements.txt"

    if pyproject_toml.exists() or requirements_txt.exists():
        result["language"] = "Python"

        # Parse pyproject.toml for details
        if pyproject_toml.exists():
            try:
                # Try tomli for Python <3.11, tomllib for Python 3.11+
                try:
                    import tomllib
                except ImportError:
                    try:
                        import tomli as tomllib
                    except ImportError:
                        # Fall back to simple text parsing
                        tomllib = None

                if tomllib:
                    with open(pyproject_toml, 'rb') as f:
                        data = tomllib.load(f)
                else:
                    # Simple text parsing fallback
                    with open(pyproject_toml, 'r') as f:
                        text = f.read()
                        data = {'project': {'dependencies': [], 'optional-dependencies': {}}}
                        # Extract basic info from text
                        if 'fastapi' in text.lower():
                            data['project']['dependencies'].append('fastapi')
                        if 'flask' in text.lower():
                            data['project']['dependencies'].append('flask')
                        if 'bandit' in text.lower():
                            data['project']['dependencies'].append('bandit')
                        if 'safety' in text.lower():
                            data['project']['dependencies'].append('safety')
                        if 'pytest' in text.lower():
                            data['project']['dependencies'].append('pytest')

                    # Check dependencies
                    deps = []
                    if 'project' in data and 'dependencies' in data['project']:
                        deps.extend(data['project']['dependencies'])
                    if 'project' in data and 'optional-dependencies' in data['project']:
                        for group in data['project']['optional-dependencies'].values():
                            deps.extend(group)

                    deps_str = ' '.join(deps).lower()

                    # Detect framework
                    if 'fastapi' in deps_str:
                        result["framework"] = "FastAPI"
                    elif 'flask' in deps_str:
                        result["framework"] = "Flask"
                    elif 'django' in deps_str:
                        result["framework"] = "Django"

                    # Detect security tools
                    if 'bandit' in deps_str:
                        result["security_tools"].append("bandit")
                    if 'safety' in deps_str:
                        result["security_tools"].append("safety")

                    # Detect test framework
                    if 'pytest' in deps_str:
                        result["test_framework"] = "pytest"

                    result["is_security_focused"] = len(result["security_tools"]) > 0

            except Exception:
                pass  # Ignore parse errors, use defaults

    # Check for TypeScript/JavaScript
    package_json = target_dir / "package.json"
    if package_json.exists():
        result["language"] = "TypeScript" if (target_dir / "tsconfig.json").exists() else "JavaScript"

        try:
            with open(package_json) as f:
                data = json.load(f)
                deps = {**data.get('dependencies', {}), **data.get('devDependencies', {})}

                # Detect framework
                if 'next' in deps:
                    result["framework"] = "Next.js"
                    result["is_frontend"] = True
                elif 'astro' in deps:
                    result["framework"] = "Astro"
                    result["is_frontend"] = True
                elif 'react' in deps:
                    result["framework"] = "React"
                    result["is_frontend"] = True
                elif 'vue' in deps:
                    result["framework"] = "Vue"
                    result["is_frontend"] = True

                # Detect test framework
                if 'vitest' in deps:
                    result["test_framework"] = "Vitest"
                elif 'jest' in deps:
                    result["test_framework"] = "Jest"
                elif '@playwright/test' in deps:
                    result["test_framework"] = "Playwright"

        except Exception:
            pass

    # Generate agent suggestions
    if result["is_security_focused"]:
        result["suggested_agents"] = ["coder-security", "qa-security", "code-reviewer", "security-analyst"]
    elif result["is_frontend"]:
        result["suggested_agents"] = ["coder-frontend", "qa-frontend", "code-reviewer"]
    elif result["language"] == "Python":
        result["suggested_agents"] = ["coder-python", "qa-python", "code-reviewer"]
    elif result["language"] in ["TypeScript", "JavaScript"]:
        result["suggested_agents"] = ["coder-typescript", "qa-frontend", "code-reviewer"]
    else:
        result["suggested_agents"] = ["coder", "qa-engineer", "code-reviewer"]

    return result


def get_agent_variant(agent_type: str, tech_stack: Dict) -> str:
    """
    Determine agent variant based on tech stack.
    Returns variant suffix (e.g., 'security', 'frontend', 'python').
    """
    if agent_type == "coder":
        if tech_stack["is_security_focused"]:
            return "security"
        elif tech_stack["is_frontend"]:
            return "frontend"
        elif tech_stack["language"] == "Python":
            return "python"
        elif tech_stack["language"] in ["TypeScript", "JavaScript"]:
            return "typescript"
    elif agent_type == "qa-engineer":
        if tech_stack["is_security_focused"]:
            return "security"
        elif tech_stack["is_frontend"]:
            return "frontend"
        elif tech_stack["language"] == "Python":
            return "python"

    return ""  # No variant, use base name


def load_template(template_name: str) -> str:
    """Load agent template from templates/agents/ directory."""
    script_dir = Path(__file__).parent
    template_path = script_dir.parent / "templates" / "agents" / template_name

    if not template_path.exists():
        raise FileNotFoundError(f"Template not found: {template_path}")

    with open(template_path, 'r') as f:
        return f.read()


def load_tech_stack_config(language: str, framework: str = None) -> Dict:
    """Load tech stack configuration from configs/tech-stack-definitions/."""
    script_dir = Path(__file__).parent
    configs_dir = script_dir.parent / "configs" / "tech-stack-definitions"

    # Try framework-specific config first
    if framework:
        config_file = configs_dir / f"{framework.lower().replace('.', '').replace(' ', '')}.json"
        if config_file.exists():
            with open(config_file, 'r') as f:
                return json.load(f)

    # Fall back to language config
    if language:
        config_file = configs_dir / f"{language.lower()}.json"
        if config_file.exists():
            with open(config_file, 'r') as f:
                return json.load(f)

    # Return minimal defaults
    return {
        "language": language or "Unknown",
        "framework": framework or "None",
        "testing": "Manual testing",
        "tools": []
    }


def generate_agent_content(
    agent_type: str,
    tech_stack: Dict,
    project_name: str,
    override_stack: Optional[str] = None
) -> Tuple[str, str]:
    """
    Generate agent content from template.
    Returns (filename, content).
    """
    agent_def = AGENT_TYPES[agent_type]

    # Load template
    template = load_template(agent_def["template_file"])

    # Determine variant and filename
    variant = get_agent_variant(agent_type, tech_stack)
    if variant:
        filename = f"{agent_type}-{variant}.md"
        specialist_id = f"{agent_type}-{variant}"
    else:
        filename = f"{agent_type}.md"
        specialist_id = agent_type

    # Load tech stack config
    tech_config = load_tech_stack_config(
        tech_stack["language"],
        tech_stack["framework"]
    )

    # Build tech stack content string
    if override_stack:
        tech_stack_content = override_stack
    else:
        tech_stack_parts = []
        if tech_config.get("language"):
            tech_stack_parts.append(f"- **Language:** {tech_config['language']}")
        if tech_config.get("framework"):
            tech_stack_parts.append(f"- **Framework:** {tech_config['framework']}")
        if tech_config.get("testing"):
            tech_stack_parts.append(f"- **Testing:** {tech_config['testing']}")
        if tech_config.get("tools"):
            tech_stack_parts.append(f"- **Tools:** {', '.join(tech_config['tools'])}")

        tech_stack_content = '\n'.join(tech_stack_parts)

    # Template substitutions
    project_type = tech_stack.get("framework") or tech_stack.get("language") or "General"
    base_agent = agent_def.get("base_agent") or "N/A"
    base_version = agent_def.get("base_version") or "N/A"

    content = template.replace('{project_name}', project_name)
    content = content.replace('{project_type}', project_type)
    content = content.replace('{specialist_id}', specialist_id)
    content = content.replace('{base_agent}', base_agent)
    content = content.replace('{base_version}', base_version)
    content = content.replace('{tech_stack_content}', tech_stack_content)
    content = content.replace('{timestamp}', datetime.now().isoformat())
    content = content.replace('{temperature}', str(agent_def.get('temperature', 0.3)))

    return filename, content


def validate_target_dir(path: str) -> tuple:
    """Validate target directory is within allowed boundaries."""
    try:
        resolved = Path(path).resolve()
        if not resolved.is_dir():
            return False, f"Target directory does not exist: {resolved}"
        if not os.access(resolved, os.W_OK):
            return False, f"Target directory is not writable: {resolved}"
        home_workspaces = Path.home() / "workspaces"
        tmp = Path("/tmp").resolve()
        devkit_root = Path(__file__).resolve().parent.parent
        for allowed_parent in [home_workspaces, tmp, devkit_root]:
            try:
                resolved.relative_to(allowed_parent)
                return True, ""
            except ValueError:
                pass
        return False, f"Target directory must be under ~/workspaces/, {devkit_root}, or /tmp/"
    except Exception as e:
        return False, f"Invalid target directory: {e}"


def atomic_write(target_path: Path, content: str) -> tuple:
    """Write content to file atomically using temp file + rename."""
    try:
        target_path.parent.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        return False, f"Cannot create directory: {target_path.parent}. {e}"
    tmp_path = None
    try:
        fd, tmp_path = tempfile.mkstemp(
            dir=target_path.parent, prefix=".agent-", suffix=".tmp"
        )
        with os.fdopen(fd, 'w') as f:
            f.write(content)
        os.replace(tmp_path, target_path)
        return True, ""
    except Exception as e:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
        return False, f"Cannot write to {target_path}. {e}"


def generate_agents(
    target_dir: Path,
    agent_types: List[str],
    tech_stack_override: Optional[str] = None,
    force: bool = False
) -> int:
    """
    Generate one or more specialist agents.
    Returns 0 on success, 1 on error.
    """
    target_dir = target_dir.resolve()
    agent_dir = target_dir / '.claude' / 'agents'

    print(f"🤖 Specialist Agent Generator")
    print(f"")
    print(f"Target directory: {target_dir}")
    print(f"Agent directory: {agent_dir}")
    print(f"")

    # Auto-detect tech stack
    print("🔍 Auto-detecting tech stack...")
    tech_stack = detect_tech_stack(target_dir)

    if tech_stack["language"]:
        print(f"  Language: {tech_stack['language']}")
    if tech_stack["framework"]:
        print(f"  Framework: {tech_stack['framework']}")
    if tech_stack["security_tools"]:
        print(f"  Security Tools: {', '.join(tech_stack['security_tools'])}")
    if tech_stack["test_framework"]:
        print(f"  Test Framework: {tech_stack['test_framework']}")
    print(f"")

    # Show suggestions
    if tech_stack["suggested_agents"] and not tech_stack_override:
        print(f"💡 Suggested agents: {', '.join(tech_stack['suggested_agents'])}")
        print(f"")

    # Create agent directory
    agent_dir.mkdir(parents=True, exist_ok=True)

    project_name = target_dir.name
    generated = []
    skipped = []

    for agent_type in agent_types:
        if agent_type not in AGENT_TYPES:
            print(f"⚠️  Unknown agent type: {agent_type}")
            continue

        # Generate content
        filename, content = generate_agent_content(
            agent_type,
            tech_stack,
            project_name,
            tech_stack_override
        )

        agent_file = agent_dir / filename

        # Check if exists
        if agent_file.exists() and not force:
            response = input(f"⚠️  Warning: {filename} already exists. Overwrite? (y/N): ")
            if response.lower() != 'y':
                skipped.append(filename)
                continue

        # Write file atomically
        success, error = atomic_write(agent_file, content)
        if not success:
            print(f"Error: {error}", file=sys.stderr)
            continue

        generated.append(filename)
        print(f"✅ Generated: {filename}")

    print(f"")
    print(f"Summary:")
    print(f"  Generated: {len(generated)} agent(s)")
    if skipped:
        print(f"  Skipped: {len(skipped)} agent(s)")
    print(f"")

    if generated:
        print(f"Next steps:")
        print(f"1. Review and customize generated agents in {agent_dir}")
        print(f"2. Update CLAUDE.md with agent routing instructions")
        print(f"3. Validate agents: validate-agent {agent_dir}/*.md")
        print(f"4. Restart Claude Code to register agents")
        print(f"")
        print(f"Done! 🎉")

    return 0


def main():
    parser = argparse.ArgumentParser(
        description='Generate specialist agents for Claude Code projects',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  %(prog)s . --type coder
  %(prog)s . --type all
  %(prog)s ~/projects/my-app --type qa-engineer --tech-stack "Python FastAPI"
  %(prog)s . --type code-reviewer --force

Available agent types:
  coder              - Code implementation specialist
  qa-engineer        - Testing and validation specialist
  code-reviewer      - Code review (standalone, for /ship)
  security-analyst   - Threat modeling and security planning
  senior-architect   - High-level design and planning
  all                - Generate all agent types
        '''
    )

    parser.add_argument(
        'target_dir',
        nargs='?',
        default='.',
        help='Target project directory (default: current directory)'
    )

    parser.add_argument(
        '--type', '-t',
        required=True,
        help='Agent type to generate (coder, qa-engineer, code-reviewer, security-analyst, senior-architect, all)'
    )

    parser.add_argument(
        '--tech-stack', '-s',
        help='Override tech stack (e.g., "Python FastAPI")'
    )

    parser.add_argument(
        '--force', '-f',
        action='store_true',
        help='Overwrite existing agents without prompting'
    )

    args = parser.parse_args()

    # Validate target directory
    target_path = Path(args.target_dir)
    if not target_path.exists():
        print(f"❌ Error: Directory does not exist: {target_path}", file=sys.stderr)
        return 1

    if not target_path.is_dir():
        print(f"❌ Error: Not a directory: {target_path}", file=sys.stderr)
        return 1

    valid, error = validate_target_dir(args.target_dir)
    if not valid:
        print(f"Error: {error}", file=sys.stderr)
        return 1

    # Parse agent types
    if args.type == "all":
        agent_types = list(AGENT_TYPES.keys())
    else:
        agent_types = [args.type]

    return generate_agents(target_path, agent_types, args.tech_stack, args.force)


if __name__ == '__main__':
    sys.exit(main())
