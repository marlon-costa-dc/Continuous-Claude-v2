---
name: firecrawl-scrape
description: Scrape web pages and extract content via Firecrawl MCP
allowed-tools: [Bash, Read]
---

# Firecrawl Scrape Skill

## When to Use

- Scrape content from any URL
- Extract structured data from web pages
- Search the web and get content

## Instructions

```bash
uv run python -m runtime.harness scripts/firecrawl_scrape.py \
    --url "https://example.com" \
    --format "markdown"
```

### Parameters

- `--url`: URL to scrape
- `--format`: Output format - `markdown`, `html`, `text` (default: markdown)
- `--search`: (alternative) Search query instead of direct URL

### Examples

```bash
# Scrape a page
uv run python -m runtime.harness scripts/firecrawl_scrape.py \
    --url "https://docs.python.org/3/library/asyncio.html"

# Search and scrape
uv run python -m runtime.harness scripts/firecrawl_scrape.py \
    --search "Python asyncio best practices 2024"
```

## MCP Server Required

Requires `firecrawl` server in mcp_config.json with FIRECRAWL_API_KEY.

## Local Fallback (No API Key)

If `FIRECRAWL_API_KEY` is not available, use **trafilatura** instead:

```bash
# Local web scraping via trafilatura (no API key needed)
uv run python scripts/web_scrape_local.py "https://example.com"

# With format options
uv run python scripts/web_scrape_local.py --url "https://docs.python.org" --format markdown
```

This provides:
- High-quality content extraction
- Boilerplate removal
- Markdown/text/XML output formats
- No cost, no API key required

For complex JS-heavy sites, Firecrawl may work better; trafilatura handles most static pages well.
