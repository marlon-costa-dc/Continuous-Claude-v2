# Scripts - CLI-Based MCP Workflows

**Purpose:** Agent-agnostic, reusable Python scripts with CLI arguments for MCP tool orchestration.

> **Runs 100% Offline** - All scripts have local alternatives that work without API keys.

---

## What Are Scripts?

**Scripts** are CLI-based Python workflows that:
- Accept parameters via command-line arguments (argparse)
- Orchestrate MCP tool calls
- Return structured results
- Work with ANY AI agent (not just Claude Code)

**NOT to be confused with:**
- **Skills** = Claude Code's native format (.claude/skills/ with SKILL.md)

---

## Example Scripts

**This directory contains MCP workflow scripts:**

### firecrawl_scrape.py
- Web scraping pattern
- CLI: `--url` (required)
- Requires: `FIRECRAWL_API_KEY`
- **Local Alternative:** `web_scrape_local.py` (uses trafilatura, no API key)

### web_scrape_local.py (NEW)
- Local web scraping using trafilatura
- CLI: `<url>` (positional), `--format`, `--links`, `--images`
- **No API key required**

### multi_tool_pipeline.py
- Multi-tool chaining pattern (git analysis)
- CLI: `--repo-path` (default: "."), `--max-commits` (default: 10)
- Works without API keys (uses git server)

### Other scripts
See `ls scripts/` for all available workflows. **All paid services have local alternatives:**

| Script | Paid Service | Local Alternative |
|--------|--------------|-------------------|
| `perplexity_search.py` | Perplexity API | WebSearch builtin |
| `firecrawl_scrape.py` | Firecrawl API | `web_scrape_local.py` |
| `morph_search.py` | Morph API | Grep builtin |
| `nia_docs.py` | Nia API | Context7 MCP |

---

## Usage

**Execute scripts with CLI arguments:**

```bash
# Web scraping (requires FIRECRAWL_API_KEY)
uv run python -m runtime.harness scripts/firecrawl_scrape.py \
    --url "https://example.com"

# Multi-tool pipeline (works without API keys)
uv run python -m runtime.harness scripts/multi_tool_pipeline.py \
    --repo-path "." \
    --max-commits 5
```

**Key:** Parameters via CLI args - edit scripts freely to fix bugs or improve logic

---

## Scripts vs Skills

### Scripts (This Directory)

**What:** CLI-based Python workflows
**Where:** `./scripts/`
**Format:** Python with argparse
**Discovery:** Manual (ls, cat)
**For:** Any AI agent
**Efficiency:** 99.6% token reduction with CLI args

### Skills (Claude Code Native)

**What:** SKILL.md directories
**Where:** `.claude/skills/`
**Format:** YAML + markdown
**Discovery:** Auto (Claude Code scans)
**For:** Claude Code only
**Efficiency:** Native progressive disclosure

**Relationship:** Skills reference scripts for execution

---

## Creating Custom Scripts

Follow the template pattern:

```python
"""
SCRIPT: Your Script Name
DESCRIPTION: What it does
CLI ARGUMENTS:
    --param    Description
USAGE:
    uv run python -m runtime.harness scripts/your_script.py --param "value"
"""

import argparse
import asyncio
import sys

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--param", required=True)
    args_to_parse = [arg for arg in sys.argv[1:] if not arg.endswith(".py")]
    return parser.parse_args(args_to_parse)

async def main():
    args = parse_args()
    # Your MCP orchestration logic
    return result

asyncio.run(main())
```

---

## Documentation

- **SCRIPTS.md** - Complete framework documentation
- **This README** - Quick start
- **../.claude/skills/** - Claude Code Skills that reference these scripts
- **../docs/** - Complete project documentation

---

**Remember:** Scripts = Agent-agnostic CLI workflows. Skills = Claude Code native format.
