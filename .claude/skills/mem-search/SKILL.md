---
description: Search cross-session memory via claude-mem plugin
---

# Memory Search

Search observations, decisions, and context from previous sessions using the claude-mem plugin.

## Prerequisites

Install claude-mem plugin first:

```bash
/plugin marketplace add thedotmack/claude-mem
/plugin install claude-mem
```

## 3-Layer Token-Efficient Workflow

### 1. Search (Index) - ~50 tokens/result

Start with index format to get IDs with minimal token usage:

```python
mcp__plugin_claude-mem_mcp-search__search(
    query="authentication flow",
    type="all",        # "all", "observation", "summary", "prompt"
    limit=10,
    format="index"     # Returns IDs + titles only
)
```

### 2. Timeline (Context) - ~100 tokens/result

Get chronological context around specific results:

```python
mcp__plugin_claude-mem_mcp-search__timeline(
    project="my-project",
    limit=20
)
```

### 3. Get Full Details - ~500 tokens/result

Fetch full content only for filtered IDs:

```python
mcp__plugin_claude-mem_mcp-search__get_observations(
    ids=["obs-123", "obs-456"]
)
```

## Common Query Patterns

| Need | Query |
|------|-------|
| How did we solve X before? | `search(query="solve X", type="observation")` |
| What decisions about Y? | `search(query="Y decision", type="all")` |
| Recent changes? | `timeline(limit=10)` |
| Specific session context? | `search(query="session-name")` |
| Bug fixes? | `search(query="fix bug", type="observation")` |

## Search Types

- **all**: Search across observations, summaries, and prompts
- **observation**: Tool usage captures (PostToolUse)
- **summary**: Session summaries (Stop hook)
- **prompt**: User prompts (UserPromptSubmit)

## Best Practices

1. **Start with index format** - Get IDs first, then fetch details
2. **Use type filters** - Narrow down to observation/summary/prompt
3. **Check timeline first** - For recent context without specific query
4. **Combine with ledger** - claude-mem for past sessions, ledger for current

## Architecture Reference

claude-mem captures data automatically via hooks:

```
PostToolUse → save-hook.js → Worker API → SQLite + Chroma
Stop → summary-hook.js → Claude Agent SDK → Summary stored
SessionStart → context-hook.js → Injects previous context
```

## Local Data Locations

- Database: `~/.claude-mem/claude-mem.db`
- Vector DB: `~/.claude-mem/chroma/`
- Worker: http://localhost:37777
- Health check: http://localhost:37777/health

## Troubleshooting

- **No results**: Ensure claude-mem plugin is installed and worker is running
- **Worker not running**: Check `curl http://localhost:37777/health`
- **Missing observations**: Verify PostToolUse hook is registered
- **Empty summaries**: Check Stop hook and Claude Agent SDK configuration
