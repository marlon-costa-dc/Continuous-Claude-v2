---
description: Token-efficient codebase exploration using Repomix - USE FIRST for brownfield projects
---

# Codebase Explorer Skill

Token-efficient codebase exploration using Repomix CLI and MCP. Replaces RepoPrompt (which is macOS-only).

## When to Use

- Before planning features in an existing codebase
- Before debugging issues
- When you need to understand code structure without reading every file
- When user says "explore", "understand codebase", "how does X work"

## Quick Commands

### Overview
```bash
# Full tree + structure
repomix --output-show-tree --style markdown

# Token-efficient (compressed signatures ~70% reduction)
repomix --compress --style xml
```

### Filtered Exploration
```bash
# Specific directory
repomix --include "src/**/*.ts" --compress

# Multiple patterns
repomix --include "src/auth/**,middleware/**" --compress

# Export to file
repomix --include "src/" --output context.md
```

### MCP Tools (if available)
- `pack_codebase` - Pack local directory
- `grep_repomix_output` - Search in output
- `read_repomix_output` - Read specific section

## Workflow

1. **Get Overview**: `repomix --output-show-tree`
2. **Find Relevant**: `repomix --include "pattern" --compress`
3. **Deep Dive**: Use Read tool for specific files
4. **Export**: `repomix --output context.md`

## Fallbacks

If repomix not available:
1. `code2prompt` (Rust CLI): `code2prompt .`
2. Native Glob + Grep + Read

## Token Efficiency Rules

1. NEVER dump full files - use `--compress`
2. Use `--include` to filter relevant paths
3. Summarize findings - don't return raw output
4. Use Read tool only for specific sections needed

## Output
Create codebase-map at: `thoughts/handoffs/<session>/codebase-map.md`

## Notes

- Requires Repomix: `~/bin/repomix` or `node ~/repomix/bin/repomix.cjs`
- Alternative: `~/bin/code2prompt` (Rust)
- ~70% token reduction with --compress (Tree-sitter extraction)
