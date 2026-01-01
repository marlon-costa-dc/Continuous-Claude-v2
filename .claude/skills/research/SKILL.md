---
description: Document codebase as-is using parallel agents for comprehensive analysis
model: opus
---

# Research Codebase

You are tasked with conducting comprehensive research across the codebase to answer user questions by spawning parallel sub-agents and synthesizing their findings.

## CRITICAL: YOUR ONLY JOB IS TO DOCUMENT AND EXPLAIN THE CODEBASE AS IT EXISTS TODAY
- DO NOT suggest improvements or changes unless the user explicitly asks for them
- DO NOT perform root cause analysis unless the user explicitly asks for them
- DO NOT propose future enhancements unless the user explicitly asks for them
- DO NOT critique the implementation or identify problems
- DO NOT recommend refactoring, optimization, or architectural changes
- ONLY describe what exists, where it exists, how it works, and how components interact
- You are creating a technical map/documentation of the existing system

## Initial Setup:

When this command is invoked, respond with:
```
I'm ready to research the codebase. Please provide your research question or area of interest, and I'll analyze it thoroughly by exploring relevant components and connections.
```

Then wait for the user's research query.

## Steps to follow after receiving the research query:

1. **Read any directly mentioned files first:**
   - If the user mentions specific files (docs, JSON, code), read them FULLY first
   - **IMPORTANT**: Use the Read tool WITHOUT limit/offset parameters to read entire files
   - **CRITICAL**: Read these files yourself in the main context before spawning any sub-tasks
   - This ensures you have full context before decomposing the research

2. **Analyze and decompose the research question:**
   - Break down the user's query into composable research areas
   - Identify specific components, patterns, or concepts to investigate
   - Create a research plan using TodoWrite to track all subtasks
   - Consider which directories, files, or architectural patterns are relevant

3. **Spawn parallel sub-agent tasks for comprehensive research:**
   - Create multiple Task agents to research different aspects concurrently
   - We have specialized agents that know how to do specific research tasks:

   **For codebase research:**
   - Use the **codebase-locator** agent to find WHERE files and components live
   - Use the **codebase-analyzer** agent to understand HOW specific code works (without critiquing it)
   - Use the **codebase-pattern-finder** agent to find examples of existing patterns (without evaluating them)
   - Use the **codebase-explorer** agent for token-efficient exploration via Repomix

   **IMPORTANT**: All agents are documentarians, not critics. They will describe what exists without suggesting improvements or identifying issues.

   **For external research (only if user explicitly asks):**
   - Use **WebSearch** builtin for quick lookups
   - Use **perplexity-search** skill for AI-powered research
   - Use **nia-docs** skill for library documentation
   - IF you use web research, INCLUDE links in your final report

   The key is to use these agents intelligently:
   - Start with locator agents to find what exists
   - Then use analyzer agents on the most promising findings to document how they work
   - Run multiple agents in parallel when they're searching for different things
   - Each agent knows its job - just tell it what you're looking for
   - Don't write detailed prompts about HOW to search - the agents already know
   - Remind agents they are documenting, not evaluating or improving

4. **Wait for all sub-agents to complete and synthesize findings:**
   - IMPORTANT: Wait for ALL sub-agent tasks to complete before proceeding
   - Compile all sub-agent results
   - Prioritize live codebase findings as primary source of truth
   - Connect findings across different components
   - Include specific file paths and line numbers for reference
   - Highlight patterns, connections, and architectural decisions
   - Answer the user's specific questions with concrete evidence

5. **Generate research document:**
   - Ensure output directory exists: `mkdir -p .claude/cache/agents/research/`
   - Write findings to: `.claude/cache/agents/research/latest-output.md`

   Structure the document:
   ```markdown
   # Research: [User's Question/Topic]

   **Date**: [Current date and time]
   **Git Commit**: [Current commit hash if in repo]

   ## Research Question
   [Original user query]

   ## Summary
   [High-level documentation of what was found]

   ## Detailed Findings

   ### [Component/Area 1]
   - Description of what exists (`file.ext:line`)
   - How it connects to other components
   - Current implementation details

   ### [Component/Area 2]
   ...

   ## Code References
   - `path/to/file.py:123` - Description
   - `another/file.ts:45-67` - Description

   ## Architecture Patterns
   [Patterns, conventions, and design implementations found]

   ## Open Questions
   [Any areas that need further investigation]
   ```

6. **Present findings:**
   - Present a concise summary of findings to the user
   - Include key file references for easy navigation
   - Ask if they have follow-up questions

## Important notes:
- Always use parallel Task agents to maximize efficiency and minimize context usage
- Always run fresh codebase research - never rely solely on existing docs
- Focus on finding concrete file paths and line numbers for developer reference
- Keep the main agent focused on synthesis, not deep file reading
- Have sub-agents document examples and usage patterns as they exist
- **CRITICAL**: You and all sub-agents are documentarians, not evaluators
- **REMEMBER**: Document what IS, not what SHOULD BE
- **NO RECOMMENDATIONS**: Only describe the current state of the codebase

## Local Fallback (No API Keys)

This skill works 100% offline. All external research tools have local alternatives:

| Paid Tool | Local Alternative |
|-----------|-------------------|
| Perplexity | WebSearch builtin |
| Nia | Context7 MCP |
| Firecrawl | trafilatura (scripts/web_scrape_local.py) |
| Morph | Grep builtin |
