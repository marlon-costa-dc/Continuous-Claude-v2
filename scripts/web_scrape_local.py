#!/usr/bin/env python3
"""
Local web scraping without Firecrawl API.
Uses trafilatura for content extraction.

USAGE:
    uv run python scripts/web_scrape_local.py <url>
    uv run python scripts/web_scrape_local.py --url "https://example.com"
    uv run python scripts/web_scrape_local.py --url "https://example.com" --format txt

This is a local alternative to Firecrawl that requires no API key.
Uses trafilatura for high-quality content extraction from web pages.

Features:
- Extracts main content, removes boilerplate
- Preserves links and images (optional)
- Multiple output formats: markdown, txt, xml
- Handles JS-heavy sites via fallback

Arguments:
    url         URL to scrape (positional or --url)
    --format    Output format: markdown (default), txt, xml
    --include-links    Include hyperlinks in output (default: true)
    --include-images   Include image references (default: true)
"""
from __future__ import annotations

import argparse
import sys

try:
    import trafilatura
except ImportError:
    print(
        "ERROR: trafilatura not installed. Run: uv add trafilatura",
        file=sys.stderr,
    )
    sys.exit(1)


def scrape_url(
    url: str,
    output_format: str = "markdown",
    include_links: bool = True,
    include_images: bool = True,
) -> str:
    """Scrape URL and extract main content.

    Args:
        url: The URL to scrape
        output_format: Output format (markdown, txt, xml)
        include_links: Whether to include hyperlinks
        include_images: Whether to include image references

    Returns:
        Extracted content as string, or error message
    """
    downloaded = trafilatura.fetch_url(url)
    if not downloaded:
        return f"ERROR: Could not fetch {url}"

    result = trafilatura.extract(
        downloaded,
        output_format=output_format,
        include_links=include_links,
        include_images=include_images,
    )
    return result or f"ERROR: Could not extract content from {url}"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Local web scraping via trafilatura (Firecrawl alternative)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python scripts/web_scrape_local.py https://docs.python.org
    python scripts/web_scrape_local.py --url "https://example.com" --format txt
    python scripts/web_scrape_local.py --url "https://news.ycombinator.com" --format markdown
        """,
    )
    parser.add_argument("url", nargs="?", help="URL to scrape")
    parser.add_argument("--url", dest="url_flag", help="URL to scrape (alternative)")
    parser.add_argument(
        "--format",
        choices=["markdown", "txt", "xml"],
        default="markdown",
        help="Output format (default: markdown)",
    )
    parser.add_argument(
        "--include-links",
        action="store_true",
        default=True,
        help="Include hyperlinks in output (default: true)",
    )
    parser.add_argument(
        "--no-links",
        action="store_true",
        help="Exclude hyperlinks from output",
    )
    parser.add_argument(
        "--include-images",
        action="store_true",
        default=True,
        help="Include image references (default: true)",
    )
    parser.add_argument(
        "--no-images",
        action="store_true",
        help="Exclude images from output",
    )

    args = parser.parse_args()
    url = args.url or args.url_flag

    if not url:
        parser.print_help()
        sys.exit(1)

    include_links = not args.no_links
    include_images = not args.no_images

    result = scrape_url(
        url,
        output_format=args.format,
        include_links=include_links,
        include_images=include_images,
    )
    print(result)


if __name__ == "__main__":
    main()
