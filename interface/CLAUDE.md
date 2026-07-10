# Global Claude Code Instructions

## Task Management and Delegation

1. **Proactively use subagents wherever possible**: ALWAYS delegate tasks to specialized agents when they match their capabilities. Do not attempt complex tasks directly when a specialized agent is available. Immediately identify and use the appropriate agent for:
   - `test-engineer` for testing and quality assurance
   - `quality-specialist` for security and performance optimization
   - `backend-developer` for Elixir/Phoenix/OTP development
   - `architect` for system design and architectural decisions
   - `api-specialist` for API development and documentation
   - `devops-engineer` for infrastructure and deployment
   - `data-engineer` for database and data architecture
   - `frontend-developer` for UI/UX development
   - `product-coordinator` for project management and documentation

2. **Spin off multiple subagents or subtasks where possible**: When facing multi-faceted problems, break them down and run multiple subagents in parallel to maximize efficiency. Use the Task tool with different subagent_type parameters to handle different aspects of complex problems simultaneously.

## Git Commit and Pull Request Requirements

3. **Always add reviewer declaration in commits and PRs**: When creating git commits or pull requests, always include a review declaration. Before creating any commit or PR, retrieve the user's name and email using:
   ```
   git config user.name
   git config user.email
   ```

   Then include the following declaration in the commit message or PR description:
   ```
   Reviewed-by: [Name from git config] <[Email from git config]>
   ```

   This declaration confirms that the user has reviewed and accepted the code changes. Include this after the main commit message but before the Claude Code attribution.

Example commit message format:
```
feat: Add new feature description

Detailed explanation of changes...

Reviewed-by: [Retrieved Name] <[Retrieved Email]>

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Code Search and Analysis Tools

4. **Use ast-grep for structural code searches**: When performing code analysis, searching for patterns, or understanding code structure, prefer `ast-grep` over text-based grep tools when appropriate. `ast-grep` understands syntax and provides more accurate results for:
   - Finding function/method definitions and calls
   - Searching for specific code patterns or structures
   - Language-aware refactoring operations
   - Complex structural queries that require understanding of code semantics

   Use `ast-grep` via the Bash tool for these structural searches, falling back to the Grep tool only for simple text-based searches or when language syntax understanding isn't needed.

## Two-Layer Intelligence Architecture

5. **Streamlined Intelligence System**: All agents operate using an efficient two-layer architecture for comprehensive code intelligence:

   **LAYER 1: SERENA SEMANTIC INTELLIGENCE**
   - Use Serena MCP for all code operations: `find_symbol`, `get_symbols_overview`, `search_for_pattern`, `find_referencing_symbols`
   - Maintain project memory with `write_memory`/`read_memory` for persistent knowledge
   - Extract precise code context before any analysis or modification
   - Map system dependencies and architectural relationships semantically

   **LAYER 2: SEQUENTIAL THINKING COMPLEX REASONING**
   - Automatically activate for problems requiring ≥3 steps or complex decision trees
   - Use for multi-faceted analysis, hypothesis development, and systematic solution synthesis
   - Essential for architectural decisions, security analysis, and performance optimization

6. **Streamlined Intelligence Workflows**: Use systematic patterns that leverage both layers:

   **Standard Intelligence Flow:**
   ```
   Serena (semantic context) → Sequential Thinking (complex reasoning) → Implementation
   ```

   **Complex Problem Solving:**
   ```
   Serena (context mapping) → Sequential Thinking (multi-hypothesis analysis) → Validated solution
   ```

## DRY (Don't Repeat Yourself) Principles

7. **Mandatory Code Reuse**: BEFORE generating any code, follow this strict process:

   **STEP 1: SEARCH FIRST**
   - Use Grep/Find/Serena tools to locate existing patterns
   - Identify reusable components, modules, or functions
   - Check for similar implementations that can be extended
   - Look for established conventions and follow them

   **STEP 2: REUSE ALWAYS**
   - Extend existing modules/functions rather than creating new ones
   - Import and use shared components
   - Follow established patterns in the codebase
   - Never duplicate business logic

   **STEP 3: EXTRACT COMMON PATTERNS**
   - If pattern appears 2+ times, extract to shared module
   - Create abstractions with parameters
   - Replace all instances with references
   - Document the shared pattern

   **STEP 4: GENERATE MINIMALLY**
   - Generate only truly unique new code
   - Reference all shared components
   - Maintain consistent coding style
   - Optimize imports and dependencies

8. **DRY Anti-Patterns to Avoid**:
   - ❌ Copy-paste code blocks
   - ❌ Duplicate business logic
   - ❌ Repeat configuration values
   - ❌ Create similar components
   - ❌ Write redundant tests
   - ❌ Duplicate error handling

9. **DRY Validation Checklist** - Before submitting code:
   - [ ] No duplicated functions
   - [ ] All constants extracted to configuration
   - [ ] Shared utilities created for common operations
   - [ ] Patterns documented in code comments
   - [ ] Imports optimized
   - [ ] Zero copy-paste code

## Complexity-Based Automatic Activation

10. **Sequential Thinking Triggers** - Automatically activate Sequential Thinking MCP when:

    **Task Complexity Thresholds:**
    - Step count: ≥ 3 distinct steps required
    - Decision points: ≥ 2 branching decisions
    - Stakeholder impact: ≥ 3 affected systems/teams
    - Time horizon: ≥ 1 week implementation
    - Rollback complexity: Manual intervention required

    **Problem Domain Triggers:**
    - **Architecture**: ≥ 5 interacting components or ≥ 3 external integrations
    - **Security**: Any OWASP Top 10 category or PII/sensitive data involved
    - **Performance**: ≥ 20% performance change expected or ≥ 2 bottlenecks identified
    - **Data Migration**: ≥ 1GB data or ≥ 3 services to migrate
    - **Bug Investigation**: ≥ 3 components involved or unknown root cause

    **Environmental Factors:**
    - **Production**: Lower thresholds for production issues
    - **Critical Systems**: Mandatory for core functionality changes
    - **Compliance**: Required for any regulatory standard involvement

## Additional Guidelines

- **MANDATORY**: Always check if a task matches any specialized agent before attempting it directly
- **SEMANTIC-FIRST APPROACH**: Always use Serena for code context before any analysis or modification
- **COMPLEXITY AWARENESS**: Automatically activate Sequential Thinking when complexity thresholds are met
- **DRY ENFORCEMENT**: Search and reuse before generating new code
- **PARALLEL EXECUTION**: Consider parallel execution of independent tasks using multiple agents
- **CODE QUALITY**: Always maintain code quality and follow project conventions
- **PROPER ATTRIBUTION**: Ensure all commits include proper attribution and review declaration
- **STRUCTURAL ANALYSIS**: Use ast-grep for syntax-aware code analysis when beneficial
