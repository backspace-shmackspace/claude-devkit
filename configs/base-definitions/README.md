# Base Definitions

Shared configuration snippets and base definitions for Claude Code projects.

## Purpose

This directory contains reusable configuration fragments that can be:
- Copied into project CLAUDE.md files
- Referenced by generators
- Shared across multiple projects
- Version controlled for consistency

## Structure

```
base-definitions/
├── README.md                 # This file
├── agent-archetypes.md       # Standard agent personality templates
├── development-rules.md      # Common development workflows
├── tech-stacks/              # Stack-specific patterns
│   ├── nextjs.md
│   ├── python-fastapi.md
│   ├── rust-cli.md
│   └── ...
└── patterns/                 # Architectural patterns
    ├── monorepo.md
    ├── microservices.md
    └── ...
```

## Usage

### Copy Entire Definition

```bash
# Add to project CLAUDE.md
cat ~/workspaces/claude-tools/configs/base-definitions/tech-stacks/nextjs.md >> CLAUDE.md
```

### Extract Sections

```bash
# Get just the development rules
sed -n '/## Development Rules/,/## Next Section/p' \
  ~/workspaces/claude-tools/configs/base-definitions/development-rules.md \
  >> CLAUDE.md
```

### Reference in Templates

```python
# In generator script
with open('~/workspaces/claude-tools/configs/base-definitions/tech-stacks/nextjs.md') as f:
    stack_rules = f.read()
```

## Planned Definitions

### agent-archetypes.md
Standard agent personalities:
- **Architect**: Design and planning
- **Engineer**: Implementation
- **Reviewer**: Code quality
- **Librarian**: Documentation
- **Auditor**: Security and performance

### development-rules.md
Common workflows:
- Git commit conventions
- Testing requirements
- Documentation standards
- Code review process

### Tech Stack Patterns

**nextjs.md:**
- App Router patterns
- Server vs Client Components
- API routes structure
- Middleware conventions

**python-fastapi.md:**
- Async handler patterns
- Pydantic models
- Alembic migrations
- Testing with pytest

**rust-cli.md:**
- Clap argument parsing
- Error handling patterns
- Config file management
- Cross-compilation

## Contributing

When adding new base definitions:

1. **Keep them modular** - Each file should be self-contained
2. **Use clear headings** - Makes extraction easier
3. **Include examples** - Show don't tell
4. **Version control** - Track changes over time
5. **Document context** - Explain when to use each pattern

## Example: Creating a New Definition

```bash
cd ~/workspaces/claude-tools/configs/base-definitions/tech-stacks

cat > golang-api.md << 'EOF'
# Go API Development Patterns

## Project Structure
- cmd/ - Application entry points
- internal/ - Private application code
- pkg/ - Public libraries
- api/ - OpenAPI/gRPC definitions

## Common Patterns
- Use context.Context for cancellation
- Structured logging with slog
- Graceful shutdown with signal handling
- Health checks at /health

## Testing
- Table-driven tests
- Test fixtures in testdata/
- Integration tests with testcontainers
- Mock interfaces with mockgen

## Dependencies
- Chi for routing (lightweight)
- sqlx for database (vs ORM)
- Viper for configuration
- Wire for dependency injection
EOF
```

## Integration with Generators

Generators can reference these definitions:

```python
# In generate_senior_architect.py
def load_stack_patterns(stack_type):
    """Load relevant stack patterns from base definitions."""
    patterns_dir = Path.home() / 'workspaces/claude-tools/configs/base-definitions/tech-stacks'

    # Map stack types to definition files
    stack_map = {
        'Next.js': patterns_dir / 'nextjs.md',
        'FastAPI': patterns_dir / 'python-fastapi.md',
        'Go': patterns_dir / 'golang-api.md',
    }

    for key, path in stack_map.items():
        if key.lower() in stack_type.lower() and path.exists():
            return path.read_text()

    return ""
```

## Syncing with Projects

When base definitions change, update projects:

```bash
# Find all projects using a definition
grep -r "Base: nextjs.md" ~/projects/*/CLAUDE.md

# Update them
for project in $(grep -l "Base: nextjs.md" ~/projects/*/CLAUDE.md); do
    project_dir=$(dirname "$project")
    echo "Updating $project_dir"
    # ... update logic
done
```

## Version Management

Track definition versions in frontmatter:

```markdown
---
definition: nextjs-patterns
version: 1.2.0
last_updated: 2026-02-08
---

# Next.js Development Patterns
...
```

Then projects can reference specific versions:
```markdown
# CLAUDE.md
This project uses: nextjs-patterns@1.2.0
```

---

**Note:** This directory is currently empty. Add base definitions as patterns emerge across your projects.
