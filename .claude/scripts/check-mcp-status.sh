#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# MCP Server Status Checker
# ═══════════════════════════════════════════════════════════════════════════════
#
# Check which MCP servers are available based on:
# 1. Required binaries installed
# 2. API keys configured in .env
# 3. Local plugins installed
#
# Usage: check-mcp-status.sh [--json]
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Colors
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    RED='\033[0;31m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    GREEN='' YELLOW='' RED='' CYAN='' NC=''
fi

ENV_FILE="${CLAUDE_ENV_FILE:-$HOME/.claude/.env}"
JSON_OUTPUT=false

[[ "${1:-}" == "--json" ]] && JSON_OUTPUT=true

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

check_env() {
    local var="$1"
    local value
    value=$(grep "^${var}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '[:space:]')
    [[ -n "$value" ]] && return 0 || return 1
}

check_cmd() {
    command -v "$1" &>/dev/null
}

check_path() {
    [[ -e "$1" ]]
}

print_status() {
    local name="$1"
    local status="$2"  # ready, disabled, missing
    local note="$3"

    if $JSON_OUTPUT; then
        echo "\"$name\": {\"status\": \"$status\", \"note\": \"$note\"}"
    else
        case "$status" in
            ready)    printf "${GREEN}✓${NC} %-20s %s\n" "$name" "$note" ;;
            disabled) printf "${YELLOW}○${NC} %-20s %s\n" "$name" "$note" ;;
            missing)  printf "${RED}✗${NC} %-20s %s\n" "$name" "$note" ;;
        esac
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

if ! $JSON_OUTPUT; then
    echo ""
    echo -e "${CYAN}MCP Server Status${NC}"
    echo "══════════════════════════════════════════════════════════════"
    echo ""
    echo -e "${CYAN}API-Dependent Servers:${NC}"
fi

$JSON_OUTPUT && echo "{"

# GitHub
if check_env "GITHUB_TOKEN" || check_env "GITHUB_PERSONAL_ACCESS_TOKEN"; then
    print_status "github" "ready" "Token configured"
else
    print_status "github" "disabled" "No GITHUB_TOKEN in .env"
fi

# Context7
if check_env "CONTEXT7_API_KEY"; then
    print_status "context7" "ready" "API key configured (higher rate limit)"
else
    print_status "context7" "ready" "Works without key (rate limited)"
fi

# Perplexity
if check_env "PERPLEXITY_API_KEY"; then
    print_status "perplexity" "ready" "API key configured"
else
    print_status "perplexity" "disabled" "No API key (use WebSearch builtin)"
fi

# Firecrawl
if check_env "FIRECRAWL_API_KEY"; then
    print_status "firecrawl" "ready" "API key configured"
else
    print_status "firecrawl" "disabled" "No API key (use trafilatura local)"
fi

# Morph
if check_env "MORPH_API_KEY"; then
    print_status "morph" "ready" "API key configured"
else
    print_status "morph" "disabled" "No API key (use Grep builtin)"
fi

# Nia
if check_env "NIA_API_KEY"; then
    print_status "nia" "ready" "API key configured"
else
    print_status "nia" "disabled" "No API key (use Context7)"
fi

if ! $JSON_OUTPUT; then
    echo ""
    echo -e "${CYAN}Local Servers (No API Key Required):${NC}"
fi

# Repomix
if check_path "$HOME/repomix/bin/repomix.cjs" || check_cmd repomix; then
    print_status "repomix" "ready" "Local installation"
else
    print_status "repomix" "missing" "Install: npm i -g repomix"
fi

# Claude-mem
if check_path "$HOME/.claude/plugins/marketplaces/thedotmack/claude-mem-search/dist/index.js"; then
    print_status "claude-mem" "ready" "Plugin installed"
else
    print_status "claude-mem" "missing" "Install: /plugin marketplace add thedotmack/claude-mem"
fi

# Qlty
if check_cmd qlty || check_path "$HOME/.qlty/bin/qlty"; then
    print_status "qlty" "ready" "Code quality toolkit"
else
    print_status "qlty" "missing" "Install: curl -fsSL https://qlty.sh/install.sh | bash"
fi

# Sequential Thinking (always available via npx)
if check_cmd npx; then
    print_status "sequential-thinking" "ready" "Via npx"
else
    print_status "sequential-thinking" "missing" "Install Node.js/npm"
fi

# AST-grep
if check_cmd sg || check_cmd ast-grep; then
    print_status "ast-grep" "ready" "AST-based search"
else
    print_status "ast-grep" "disabled" "Install: cargo install ast-grep"
fi

if ! $JSON_OUTPUT; then
    echo ""
    echo -e "${CYAN}System Dependencies:${NC}"
fi

# Node.js
if check_cmd node; then
    print_status "node" "ready" "$(node --version 2>/dev/null)"
else
    print_status "node" "missing" "Required for MCP servers"
fi

# Python
if check_cmd python3; then
    print_status "python3" "ready" "$(python3 --version 2>/dev/null)"
else
    print_status "python3" "missing" "Required for MCP runtime"
fi

# uv
if check_cmd uv; then
    print_status "uv" "ready" "$(uv --version 2>/dev/null)"
else
    print_status "uv" "missing" "Install: curl -LsSf https://astral.sh/uv/install.sh | sh"
fi

$JSON_OUTPUT && echo "}"

if ! $JSON_OUTPUT; then
    echo ""
    echo "Config file: $ENV_FILE"
    echo ""
fi
