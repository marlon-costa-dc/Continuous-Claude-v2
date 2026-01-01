---
description: Search cross-session memory via claude-mem plugin
---

# Memory Search

Search observations, decisions, and context from previous sessions using the claude-mem plugin.

## Quick Commands (Daily Workflow)

### Start of Session - Load Context
```python
# Auto-load recent project context (recommended at session start)
mcp__plugin_claude-mem_claude-mem-search__get_recent_context(
    project="${PROJECT_NAME}",  # e.g., "flext", "my-app"
    limit=30,
    format="full"
)
```

### Before Implementing - Check Prior Work
```python
# Search what was done before on this topic
mcp__plugin_claude-mem_claude-mem-search__search(
    query="authentication refactoring",
    type="observations",
    limit=10,
    format="index"
)
```

### Before Decisions - Check Past Decisions
```python
# Find previous architectural decisions
mcp__plugin_claude-mem_claude-mem-search__decisions(
    query="database schema",
    limit=10
)
```

### Understanding Code - How It Works
```python
# Understand how a feature was implemented
mcp__plugin_claude-mem_claude-mem-search__how_it_works(
    query="error handling pattern"
)
```

### Recent Changes - What Changed
```python
# See recent modifications to a component
mcp__plugin_claude-mem_claude-mem-search__changes(
    query="api.py refactoring"
)
```

## 3-Layer Token-Efficient Workflow

### 1. Search (Index) - ~50 tokens/result

Start with index format to get IDs with minimal token usage:

```python
mcp__plugin_claude-mem_claude-mem-search__search(
    query="authentication flow",
    type="all",        # "all", "observations", "summaries", "prompts"
    limit=10,
    format="index"     # Returns IDs + titles only
)
```

### 2. Timeline (Context) - ~100 tokens/result

Get chronological context around specific results:

```python
mcp__plugin_claude-mem_claude-mem-search__timeline(
    project="my-project",
    limit=20
)
```

### 3. Get Full Details - ~500 tokens/result

Fetch full content only for filtered IDs:

```python
mcp__plugin_claude-mem_claude-mem-search__get_observations(
    ids=[123, 456]  # Use integer IDs from index search
)
```

## Integration with Development Workflow

### FLEXT Projects

```python
# At session start in FLEXT workspace
mcp__plugin_claude-mem_claude-mem-search__get_recent_context(
    project="flext",
    limit=30,
    format="full"
)

# Before modifying models.py, protocols.py, api.py
mcp__plugin_claude-mem_claude-mem-search__changes(
    query="models.py protocols.py"
)

# Before architectural changes
mcp__plugin_claude-mem_claude-mem-search__decisions(
    query="architecture layering"
)
```

### Debugging Workflow

```python
# Before debugging an issue
mcp__plugin_claude-mem_claude-mem-search__search(
    query="error fix authentication",
    type="observations"
)
```

### Implementation Workflow

```python
# Before implementing a feature
mcp__plugin_claude-mem_claude-mem-search__how_it_works(
    query="similar feature pattern"
)
```

## Common Query Patterns

| Need | Query |
|------|-------|
| Start session | `get_recent_context(project="X")` |
| How did we solve X? | `search(query="solve X", type="observations")` |
| What decisions about Y? | `decisions(query="Y")` |
| Recent changes? | `timeline(limit=10)` |
| How does Z work? | `how_it_works(query="Z")` |
| What changed in file? | `changes(query="filename")` |

## Search Types

- **all**: Search across observations, summaries, and prompts
- **observations**: Tool usage captures (PostToolUse) - most useful
- **summaries**: Session summaries (Stop hook)
- **prompts**: User prompts (UserPromptSubmit)

## Best Practices

1. **Session Start**: Always run `get_recent_context` at session start
2. **Before Implementation**: Check `how_it_works` and `decisions`
3. **Before Modifications**: Check `changes` for the file/component
4. **Use Index First**: Get IDs, then fetch full details only for relevant ones
5. **Combine with Ledger**: claude-mem for past sessions, continuity ledger for current

## Architecture Reference

claude-mem captures data automatically via hooks:

```
PostToolUse → save-hook.js → Worker API → SQLite + Chroma
Stop → summary-hook.js → Claude Agent SDK → Summary stored
SessionStart → context-hook.js → Injects previous context
UserPromptSubmit → user-message-hook.js → Captures prompts
```

## Local Data Locations

- Database: `~/.claude-mem/claude-mem.db`
- Vector DB: `~/.claude-mem/chroma/`
- Worker: http://localhost:37777
- Health check: http://localhost:37777/health

## Troubleshooting

| Issue | Check |
|-------|-------|
| No results | `curl http://localhost:37777/health` |
| Worker not running | `systemctl --user status claude-mem-worker` |
| Missing observations | Verify PostToolUse hook in settings.json |
| Empty summaries | Check Stop hook and Agent SDK config |
| Slow searches | Check ChromaDB disk space |
