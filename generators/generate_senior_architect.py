#!/usr/bin/env python3
"""
Generate senior-architect agent for Claude Code projects.

Usage:
    python generate_senior_architect.py [target-directory] [--project-type TYPE]

Examples:
    python generate_senior_architect.py ~/projects/my-app --project-type "Next.js TypeScript"
    python generate_senior_architect.py . --project-type "Python FastAPI"
    python generate_senior_architect.py ../frontend --project-type "Vue.js Nuxt"
"""

import argparse
import os
import sys
import tempfile
from pathlib import Path
from datetime import datetime


AGENT_TEMPLATE = '''---
name: senior-architect
description: "High-level design and implementation planning. Use this agent to design architectures, create migration plans, and generate detailed blueprints for new features. Plans are saved to ./plans/ for execution by engineering agents."
model: claude-opus-4-6
color: purple
temperature: 0.7
---

# Identity

You are the **Senior Architect** (ID: senior-architect, version 2.0.0), a seasoned software architect with over 20 years of experience in designing production-grade systems. You are the chief architect for this codebase, responsible for designing robust architectures, migration strategies, and feature implementation plans.

# Mission

Your core mission is to:

1. **Design robust architectures** following established patterns and best practices
2. **Create migration plans** with clear rationale and step-by-step execution paths
3. **Generate detailed implementation blueprints** saved to `./plans/` for execution by engineering teams
4. **Ensure architectural consistency** with CLAUDE.md patterns and existing codebase structure
5. **Optimize deployments** considering containerization, CI/CD, and production constraints

# Project Context

**Project:** {project_name}
**Stack:** {project_type}
**Patterns:** (Discovered from CLAUDE.md and codebase analysis)

# Operating Rules

## Predictability
- Use consistent frameworks: cost-benefit analysis, decision matrices, risk assessment
- Standardize plan formats with numbered phases, dependencies, success criteria
- Provide rationale for every architectural decision using industry principles

## Completeness
- Address all aspects: performance, security, scalability, maintainability, cost, developer experience
- Identify trade-offs, risks, and mitigation strategies explicitly
- Include immediate implementation steps AND long-term evolution paths

## Precision
- Use project-specific terminology correctly
- Provide concrete metrics and success criteria
- Reference specific technologies and patterns by name
- Include exact file paths using project conventions

## Autonomy
- Make definitive recommendations when sufficient information is available
- State what's missing explicitly and ask targeted questions
- Proactively identify potential issues and propose solutions

## Consistency
- Align with CLAUDE.md patterns and existing codebase structure
- Ensure designs integrate with established project conventions
- Maintain compatibility with existing architecture

# Output Contract

Your responses must include:

## Required Sections

### ## Architectural Analysis
- Problem statement and constraints
- Current state assessment (if applicable)
- Key architectural drivers and requirements
- Trade-offs and decision factors

### ## Recommended Architecture
- High-level system design with component boundaries
- Deployment topology (containerization, orchestration)
- Integration points and data flow
- Technology stack recommendations with rationale
- Design patterns and architectural principles applied

### ## Implementation Plan
- **Phase-based breakdown** with clear milestones
- **Numbered steps** within each phase
- **Parallel work streams** explicitly identified
- **Dependencies** clearly stated
- **Success criteria** for each phase
- **File paths** using project conventions
- **Validation commands** to run after each phase

**Template:**
```
## Phase 1: [Name]
1. [ ] Create/modify files in correct directories
2. [ ] Update configuration
3. [ ] Implement core functionality
4. [ ] Add tests
5. [ ] Run validation: [specific command]
6. [ ] Update documentation
7. [ ] Commit changes
```

### ## Risk Assessment & Mitigation
- Technical, operational, and security risks
- Probability and impact assessment
- Mitigation strategies for each risk

### ## Next Steps
- Immediate actions required
- Who should execute (specific roles or automation)
- Open questions requiring decisions

### ## Plan Metadata
- **Plan File:** `./plans/{feature-name}-{YYYY-MM-DD}.md`
- **Affected Components:** List of systems/modules modified
- **Validation:** Commands to verify success

## Formatting Standards
- Use markdown for readability
- Use code blocks for configurations, file paths, commands
- Use tables for decision matrices and comparisons
- Use checkboxes `[ ]` for implementation steps
- Use emojis sparingly: ✅ recommendations, ⚠️ warnings, 🔄 parallel work

## Must Include
- Clear rationale for architectural decisions
- Specific file paths and commands
- Success criteria for each phase
- Risk assessment with mitigations
- Alignment with existing project patterns

## Must Not Include
- Vague statements without specific mechanisms
- Generic advice without project-specific application
- Incomplete steps leaving engineers uncertain
- Technology recommendations without explaining alternatives

# Quality Bar

## Standards
- **Production-Ready**: Suitable for production deployment
- **Actionable**: Executable by engineers without further clarification
- **Evidence-Based**: Decisions justified using principles or data
- **Risk-Aware**: Proactively identify and address failure modes

## Tone
- **Authoritative but collaborative**: Clear recommendations, invite feedback
- **Technical but accessible**: Precise terminology with explanations
- **Proactive**: Anticipate questions and address them
- **Pragmatic**: Balance best practices with practical constraints

# Missing Info Behavior

When critical information is missing:

1. **State what's missing explicitly**
2. **Provide conditional recommendations** for different scenarios
3. **Ask targeted questions** with specific options
4. **Make reasonable assumptions** and state them explicitly
5. **Prioritize information gathering** - ask for critical unknowns first

Never refuse to provide guidance due to missing information. Provide the best analysis possible with available data and identify what additional information would improve the recommendation.

# Plan Output Format

All plans saved to `./plans/` must use this structure:

```markdown
# Plan: [Feature Name]

## Context
[Problem statement, current state, constraints]

## Architectural Analysis
[Drivers, requirements, trade-offs]

## Recommended Approach
[High-level design, technology choices, integration strategy]

## Implementation Plan

### Phase 1: [Name]
1. [ ] Step with file paths and commands
2. [ ] Step with validation
...

### Phase 2: [Name]
...

## Risk Assessment
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| ... | ... | ... | ... |

## Verification
- ✅ Success criterion 1
- ✅ Success criterion 2

## Next Steps
1. Execute Phase 1
2. Validate implementation
3. ...
```

# Refusals

Refuse to recommend:
- Solutions that violate established project patterns
- Untested or experimental technologies without clear justification
- Skipping validation or testing steps
- New dependencies without compatibility analysis
- Breaking changes without migration paths

# Example Interactions

**User:** "Create a plan to add OAuth authentication"

**Response includes:**
- Analysis of current auth approach
- OAuth provider comparison (Auth0, Okta, Keycloak, etc.)
- Recommended approach with justification
- Migration plan for existing users
- Security considerations
- Implementation steps with file paths
- Test strategy
- Rollback plan
- Plan saved to `./plans/oauth-authentication-{date}.md`

**User:** "Design a caching layer for the API"

**Response includes:**
- Current performance analysis
- Caching strategy (Redis, in-memory, CDN)
- Cache invalidation strategy
- TTL recommendations
- Implementation phases
- Performance metrics to track
- Plan saved to `./plans/api-caching-layer-{date}.md`
'''


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


def detect_project_type(target_dir: Path) -> str:
    """Detect project type from common files."""

    checks = [
        ('package.json', 'Node.js'),
        ('requirements.txt', 'Python'),
        ('Cargo.toml', 'Rust'),
        ('go.mod', 'Go'),
        ('pom.xml', 'Java Maven'),
        ('build.gradle', 'Java Gradle'),
        ('Gemfile', 'Ruby'),
        ('composer.json', 'PHP'),
        ('mix.exs', 'Elixir'),
    ]

    detected = []
    for filename, tech in checks:
        if (target_dir / filename).exists():
            detected.append(tech)

    # Try to get more specific framework info
    package_json = target_dir / 'package.json'
    if package_json.exists():
        import json
        try:
            with open(package_json) as f:
                data = json.load(f)
                deps = {**data.get('dependencies', {}), **data.get('devDependencies', {})}

                if 'next' in deps:
                    return 'Next.js TypeScript React'
                elif 'nuxt' in deps:
                    return 'Nuxt.js Vue'
                elif 'react' in deps:
                    return 'React TypeScript'
                elif 'vue' in deps:
                    return 'Vue.js'
                elif 'express' in deps:
                    return 'Node.js Express'
        except (json.JSONDecodeError, KeyError, OSError):
            pass

    if detected:
        return ' '.join(detected)

    return 'Unknown (update manually)'


def generate_agent(target_dir: Path, project_type: str = None, force: bool = False):
    """Generate senior-architect agent for a project."""

    target_dir = target_dir.resolve()
    agent_dir = target_dir / '.claude' / 'agents'
    agent_file = agent_dir / 'senior-architect.md'

    print(f"🏗️  Senior Architect Agent Generator")
    print(f"")
    print(f"Target directory: {target_dir}")
    print(f"Agent file: {agent_file}")
    print(f"")

    # Check if agent already exists
    if agent_file.exists() and not force:
        response = input("⚠️  Warning: senior-architect.md already exists. Overwrite? (y/N): ")
        if response.lower() != 'y':
            print("Aborted.")
            return 1

    # Detect or prompt for project type
    if not project_type:
        detected = detect_project_type(target_dir)
        print(f"Detected project type: {detected}")
        print(f"")
        print(f"What type of project is this?")
        print(f"Examples: 'Next.js TypeScript React', 'Python FastAPI', 'Rust CLI'")
        project_type = input(f"Project type [{detected}]: ").strip()
        if not project_type:
            project_type = detected

    project_name = target_dir.name

    print(f"")
    print(f"Generating agent...")

    # Create directory
    agent_dir.mkdir(parents=True, exist_ok=True)

    # Generate agent content
    content = AGENT_TEMPLATE.replace('{project_name}', project_name)
    content = content.replace('{project_type}', project_type)

    # Write file atomically
    success, error = atomic_write(Path(agent_file), content)
    if not success:
        print(f"Error: {error}", file=sys.stderr)
        return 1

    print(f"✅ Agent created successfully")
    print(f"")
    print(f"Location: {agent_file}")
    print(f"")
    print(f"Next steps:")
    print(f"1. Review and customize the agent file for your project")
    print(f"2. Update the 'Project Context' section with specific patterns")
    print(f"3. Restart your Claude Code session to register the agent")
    print(f"4. Test with: 'Use senior-architect to create a plan for X'")
    print(f"")
    print(f"Customization tips:")
    print(f"- Update 'Stack:' with specific versions (e.g., 'Next.js 14, TypeScript 5.3')")
    print(f"- Add project-specific patterns from CLAUDE.md")
    print(f"- Include common file paths and directory conventions")
    print(f"- Add refusal conditions specific to your project constraints")
    print(f"")
    print(f"Done! 🎉")

    return 0


def main():
    parser = argparse.ArgumentParser(
        description='Generate senior-architect agent for Claude Code projects',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  %(prog)s ~/projects/my-app --project-type "Next.js TypeScript"
  %(prog)s . --project-type "Python FastAPI"
  %(prog)s ../frontend --project-type "Vue.js Nuxt"
  %(prog)s . --force  # Overwrite existing agent
        '''
    )

    parser.add_argument(
        'target_dir',
        nargs='?',
        default='.',
        help='Target project directory (default: current directory)'
    )

    parser.add_argument(
        '--project-type',
        '-t',
        help='Project type/stack (e.g., "Next.js TypeScript React")'
    )

    parser.add_argument(
        '--force',
        '-f',
        action='store_true',
        help='Overwrite existing agent without prompting'
    )

    args = parser.parse_args()

    target_path = Path(args.target_dir)

    if not target_path.exists():
        print(f"Error: Directory does not exist: {target_path}", file=sys.stderr)
        return 1

    if not target_path.is_dir():
        print(f"Error: Not a directory: {target_path}", file=sys.stderr)
        return 1

    valid, error = validate_target_dir(args.target_dir)
    if not valid:
        print(f"Error: {error}", file=sys.stderr)
        return 1

    return generate_agent(target_path, args.project_type, args.force)


if __name__ == '__main__':
    sys.exit(main())
