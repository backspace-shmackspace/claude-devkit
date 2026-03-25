# High-Level Plan: Generalize Devkit for Multi-LLM Support

This document outlines a high-level plan to evolve the `claude-devkit` into a model-agnostic `llm-devkit` capable of supporting both Claude and Gemini, with a flexible architecture for future expansion.

## 1. Goals

*   **Primary:** Extend the existing framework to support Google's Gemini models alongside Anthropic's Claude models.
*   **Secondary:** Rebrand the project to reflect its new model-agnostic nature (e.g., `llm-devkit`).
*   **Tertiary:** Establish a clear architectural pattern for adding new LLM providers in the future with minimal friction.

## 2. Proposed High-Level Implementation Phases

### Phase 1: Rebranding and Structural Adjustments

*   **Task:** Rename core project components to remove Claude-specific branding.
    *   Rename the repository from `claude-devkit` to `llm-devkit` (or a similar neutral name).
    *   Rename `CLAUDE.md` to a more generic name like `PROJECT_CONTEXT.md` or `FRAMEWORK.md`.
    *   Rename the `.claude/` directory used in projects to a generic name like `.agents/` or `.llm_config/`.
    *   Update all internal documentation, scripts, and comments to reflect the new naming scheme.

### Phase 2: Core Abstraction Layer for LLM Providers

*   **Task:** Decouple the skill execution engine from any specific LLM API.
    *   Introduce a generic `LLMProvider` interface or base class.
    *   Create concrete implementations: `ClaudeProvider` and `GeminiProvider`.
    *   Move model names and provider-specific details (e.g., API endpoints, authentication methods) from scripts into a dedicated, user-configurable file (e.g., `configs/providers.json`).

### Phase 3: Tooling and Skill Definition Updates

*   **Task:** Update the existing generators and `SKILL.md` format to be multi-LLM aware.
    *   Modify `generate_skill.py` and other generators to allow selecting a default LLM provider or model during scaffolding.
    *   Update the `SKILL.md` format to allow specifying a provider/model for each `Task` tool call (e.g., `model: gemini-1.5-pro`).
    *   Update `validate_skill.py` to recognize and validate the new provider-aware syntax.

### Phase 4: Testing and Documentation

*   **Task:** Ensure robustness and update all user-facing documentation.
    *   Develop a parallel set of tests to validate key skills (like `/dream` and `/ship`) using the Gemini provider.
    *   Update `GETTING_STARTED.md`, `README.md`, and all other documentation to explain the new multi-LLM architecture and how to configure/use different providers.

## 3. Key Risks & Feasibility Questions

*   **Execution Engine Dependency:** The biggest risk is the nature of the underlying "Claude Code CLI" that executes these skills. Is it extensible? Can we add a new "Gemini task" executor? A feasibility study is required to determine if this core component can be adapted or if it needs to be replaced.
*   **Behavioral Divergence:** Claude and Gemini may produce outputs with subtle structural differences for the same prompt. This could break the parsing logic within existing skills, requiring significant refactoring and prompt engineering to ensure consistent behavior across providers.

## 4. Next Steps

1.  **Feasibility Study:** Before committing to a full implementation, conduct a focused investigation into the "Claude Code CLI" to determine the viability of creating a parallel execution path for Gemini.
2.  **Prototype:** Develop a proof-of-concept with a single, simple skill that can successfully execute a task using both a Claude and a Gemini model.
