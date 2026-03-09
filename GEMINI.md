# GEMINI.md

## Project Overview

This project, `claude-devkit`, is a complete development toolkit for creating and managing skills for the Claude Code AI agent. The "code" in this project primarily consists of Markdown files that define "skills"—structured workflows that the Claude Code agent can execute.

The project provides:

*   **Skills:** Pre-built workflows for common development tasks like planning (`/dream`), implementation (`/ship`), security audits (`/audit`), and documentation synchronization (`/sync`).
*   **Generators:** Python scripts to scaffold new skills and agents from templates.
*   **Templates:** A set of standard templates for different types of skills and agents.
*   **Configuration:** JSON files that define patterns for skills and tech stacks.
*   **Deployment Scripts:** Shell scripts to install and deploy the skills to the Claude Code environment.

The core of the project is the `skills` directory, where each subdirectory represents a skill and contains a `SKILL.md` file. This file defines the skill's workflow, including its steps, the tools to use, and the logic for handling different scenarios.

## Building and Running

This project does not have a traditional build process. Instead, it uses a set of scripts to generate, validate, and deploy skills.

### Installation

To set up the `claude-devkit`, run the installation script:

```bash
./scripts/install.sh
```

This script sets up the necessary environment variables and aliases to use the generators and other tools.

### Deploying Skills

To deploy the skills to the Claude Code environment, run the deployment script:

```bash
./scripts/deploy.sh
```

You can also deploy a specific skill by providing its name as an argument:

```bash
./scripts/deploy.sh <skill-name>
```

### Running Tests

The project includes a test suite for the skill generator. To run the tests, execute the following command:

```bash
bash generators/test_skill_generator.sh
```

## Development Conventions

### Creating a New Skill

To create a new skill, use the `gen-skill` command (an alias for `python generators/generate_skill.py`):

```bash
gen-skill <skill-name> --description "A brief description of the skill"
```

This will generate a new `SKILL.md` file in the `skills/<skill-name>/` directory, based on a template. You can then customize the generated file to define the skill's workflow.

### Skill Structure

A skill is defined in a `SKILL.md` file, which has the following structure:

*   **Frontmatter:** Contains metadata about the skill, such as its name, description, and the model it uses.
*   **Workflow Steps:** A series of numbered steps that define the skill's workflow. Each step specifies the tool to use and the actions to perform.
*   **Conditional Logic:** Skills can include conditional logic to handle different scenarios, such as the presence of certain files or the output of a previous step.
*   **Parallel Execution:** Steps can be run in parallel to improve efficiency.
*   **Revision Loops:** Skills can include revision loops to iterate on a task until it meets certain criteria.

### Validation

Before deploying a new or modified skill, it's important to validate it using the `validate-skill` command (an alias for `python generators/validate_skill.py`):

```bash
validate-skill skills/<skill-name>/SKILL.md
```

This ensures that the skill's definition is well-formed and adheres to the project's conventions.
