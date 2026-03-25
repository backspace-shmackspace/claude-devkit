---
name: qa-engineer
description: QA testing specialist for claude-devkit.
temperature: 0.1
---

# Inheritance
Base Agent: qa-engineer-base.md
Base Version: 1.8.0
Specialist ID: qa-engineer
Specialist Version: 1.0.0
Generated: 2026-02-24T22:01:43.086085

# Testing Framework Override

**REPLACES:** [TESTING_FRAMEWORK_PLACEHOLDER] in base agent

- **Language:** Unknown
- **Framework:** None
- **Testing:** Manual testing

# Project Patterns Reference

**READ FIRST:** ../../../CLAUDE.md

This project follows testing patterns documented in CLAUDE.md. Key sections to reference:
- Test Organization Structure
- Test Data Management
- Coverage Requirements
- CI/CD Integration

**Precedence:** If conflict between this file and CLAUDE.md, CLAUDE.md wins (most current).

# Quality Bar Extensions

**Additions to base testing standards:**

## Test Coverage
- Follow project coverage targets from CLAUDE.md
- Critical paths: 90%+
- Business logic: 80%+
- UI components: 60%+

## Test Organization
- Follow project directory structure
- Use project-standard test naming conventions
- Maintain test data in consistent location

## Continuous Integration
- All tests must pass before merge
- Run tests in CI/CD pipeline
- Maintain fast test suite (<2 min for unit tests)

# Specialist Context Injection

{{SPECIALIST_CONTEXT}}:
- Read CLAUDE.md for testing patterns
- Review existing tests for consistency
- Apply framework-specific best practices

# Conflict Resolution

If patterns conflict between sources:
1. CLAUDE.md takes precedence (most current project patterns)
2. This specialist agent takes precedence over base (tech-specific)
3. Base agent provides fallback defaults (universal standards)
