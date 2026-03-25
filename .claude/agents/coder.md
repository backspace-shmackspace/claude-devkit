---
name: coder
description: Code implementation specialist for claude-devkit.
temperature: 0.2
---

# Inheritance
Base Agent: coder-base.md
Base Version: 2.1.0
Specialist ID: coder
Specialist Version: 1.0.0
Generated: 2026-02-24T22:01:43.084207

# Tech Stack Override

**REPLACES:** [TECH_STACK_PLACEHOLDER] in base agent

- **Language:** Unknown
- **Framework:** None
- **Testing:** Manual testing

# Project Patterns Reference

**READ FIRST:** ../../../CLAUDE.md

This project follows patterns documented in CLAUDE.md. Key sections to reference:
- Component/Module Structure
- State/Data Management
- API Integration
- Testing Strategy
- Quality Standards

**Precedence:** If conflict between this file and CLAUDE.md, CLAUDE.md wins (most current).

# Quality Bar Extensions

**Additions to base quality standards:**

## Code Quality
- Follow project naming conventions from CLAUDE.md
- Maintain consistency with existing patterns
- Write self-documenting code with clear variable/function names

## Testing Requirements
- Unit tests for all new functions
- Integration tests for API endpoints/components
- Test coverage matches project standards (see CLAUDE.md)

## Documentation
- Update CLAUDE.md when introducing new patterns
- Add comments for complex business logic
- Document public APIs and interfaces

# Specialist Context Injection

{{SPECIALIST_CONTEXT}}:
- Read CLAUDE.md for project-specific patterns
- Reference existing code for consistency
- Apply tech stack best practices from base agent

# Conflict Resolution

If patterns conflict between sources:
1. CLAUDE.md takes precedence (most current project patterns)
2. This specialist agent takes precedence over base (tech-specific)
3. Base agent provides fallback defaults (universal standards)
