# Memory Search Rule

When you need to recall past decisions, changes, or context from previous sessions:

## Before Re-Implementing Solutions

1. **First**: Use `mcp__plugin_claude-mem_claude-mem-search__search` with index format
2. **Then**: Review IDs and call `get_observations` for relevant details
3. **Consider**: Timeline for chronological context

## When to Search Memory

- Before implementing a feature that might have been done before
- When debugging issues that may have been solved previously
- When asked "how did we do X?"
- When making architectural decisions

## Search Pattern

```python
# Step 1: Index search (50 tokens/result)
search(query="relevant terms", format="index")

# Step 2: Get details only for relevant IDs (500 tokens/result)
get_observations(ids=["filtered-ids"])
```

## Do NOT

- Re-implement solutions without checking memory first
- Assume previous context is lost across sessions
- Skip memory search when user asks about past work
