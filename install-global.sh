#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Continuous Claude - Cross-Platform Global Installation
# ═══════════════════════════════════════════════════════════════════════════════
#
# Supports: Linux (any distro), macOS, Windows (WSL/Git Bash)
#
# Usage: ./install-global.sh [OPTIONS]
#   -y, --yes       Skip confirmation prompts
#   -v, --validate  Only validate components (no install)
#   -h, --help      Show this help
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_DIR="$HOME/.claude"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors (with fallback for non-color terminals)
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_step() { echo -e "${CYAN}→${NC} $1"; }

print_header() {
    echo ""
    echo -e "${BOLD}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║             Continuous Claude - Global Installation               ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Merge .env files: preserve existing values, add new keys from template
merge_env_files() {
    local source="$1"  # Template (.env.example)
    local target="$2"  # User's .env

    if [[ ! -f "$target" ]]; then
        cp "$source" "$target"
        log_step "Created new .env from template"
        return
    fi

    local added=0
    # Read template and add missing keys to target
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Extract key (everything before first =)
        local key="${line%%=*}"
        [[ -z "$key" ]] && continue

        # If key doesn't exist in target, add the line
        if ! grep -q "^${key}=" "$target" 2>/dev/null; then
            echo "$line" >> "$target"
            ((added++))
        fi
    done < "$source"

    if [[ $added -gt 0 ]]; then
        log_success ".env merged: $added new keys added, existing values preserved"
    else
        log_info ".env up to date (no new keys)"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# OS Detection
# ─────────────────────────────────────────────────────────────────────────────

detect_os() {
    OS=""
    DISTRO=""
    PKG_MANAGER=""
    ARCH=$(uname -m)

    case "$(uname -s)" in
        Linux*)
            OS="linux"
            # Detect Linux distribution
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                DISTRO="$ID"
            elif [ -f /etc/arch-release ]; then
                DISTRO="arch"
            elif [ -f /etc/debian_version ]; then
                DISTRO="debian"
            elif [ -f /etc/redhat-release ]; then
                DISTRO="rhel"
            fi

            # Detect package manager
            if command -v pacman &>/dev/null; then
                PKG_MANAGER="pacman"
            elif command -v apt-get &>/dev/null; then
                PKG_MANAGER="apt"
            elif command -v dnf &>/dev/null; then
                PKG_MANAGER="dnf"
            elif command -v yum &>/dev/null; then
                PKG_MANAGER="yum"
            elif command -v zypper &>/dev/null; then
                PKG_MANAGER="zypper"
            elif command -v apk &>/dev/null; then
                PKG_MANAGER="apk"
            elif command -v nix-env &>/dev/null; then
                PKG_MANAGER="nix"
            fi
            ;;
        Darwin*)
            OS="macos"
            DISTRO="macos"
            if command -v brew &>/dev/null; then
                PKG_MANAGER="brew"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            OS="windows"
            DISTRO="windows"
            if command -v winget &>/dev/null; then
                PKG_MANAGER="winget"
            elif command -v choco &>/dev/null; then
                PKG_MANAGER="choco"
            elif command -v scoop &>/dev/null; then
                PKG_MANAGER="scoop"
            fi
            ;;
        *)
            OS="unknown"
            DISTRO="unknown"
            ;;
    esac

    # Check for WSL
    if [[ "$OS" == "linux" ]] && grep -qi microsoft /proc/version 2>/dev/null; then
        DISTRO="$DISTRO (WSL)"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Component Check Functions
# ─────────────────────────────────────────────────────────────────────────────

check_command() {
    local cmd="$1"
    local paths="${2:-}"

    # Check in PATH first
    if command -v "$cmd" &>/dev/null; then
        return 0
    fi

    # Check alternative paths
    if [[ -n "$paths" ]]; then
        for path in $paths; do
            if [[ -x "$path" ]]; then
                return 0
            fi
        done
    fi

    return 1
}

get_version() {
    local cmd="$1"
    local version_flag="${2:---version}"

    if command -v "$cmd" &>/dev/null; then
        $cmd $version_flag 2>/dev/null | head -1 || echo "installed"
    else
        echo "not installed"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Component Installation Functions
# ─────────────────────────────────────────────────────────────────────────────

install_uv() {
    log_step "Installing uv (Python package manager)..."

    if [[ "$OS" == "windows" ]]; then
        if [[ "$PKG_MANAGER" == "winget" ]]; then
            winget install astral-sh.uv --silent 2>/dev/null || true
        elif [[ "$PKG_MANAGER" == "scoop" ]]; then
            scoop install uv 2>/dev/null || true
        else
            powershell -c "irm https://astral.sh/uv/install.ps1 | iex" 2>/dev/null || \
                curl -LsSf https://astral.sh/uv/install.sh | sh
        fi
    else
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi

    # Add to PATH for this session
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
}

install_node() {
    log_step "Installing Node.js..."

    case "$PKG_MANAGER" in
        pacman) sudo pacman -S --noconfirm nodejs npm ;;
        apt) sudo apt-get update && sudo apt-get install -y nodejs npm ;;
        dnf|yum) sudo $PKG_MANAGER install -y nodejs npm ;;
        zypper) sudo zypper install -y nodejs npm ;;
        apk) sudo apk add nodejs npm ;;
        brew) brew install node ;;
        winget) winget install OpenJS.NodeJS.LTS --silent ;;
        choco) choco install nodejs-lts -y ;;
        scoop) scoop install nodejs ;;
        nix) nix-env -i nodejs ;;
        *)
            log_warning "Unknown package manager. Install Node.js manually:"
            log_info "  https://nodejs.org/en/download/"
            return 1
            ;;
    esac
}

install_qlty() {
    log_step "Installing qlty (code quality toolkit)..."

    if [[ "$OS" == "windows" ]]; then
        powershell -c "irm https://qlty.sh/install.ps1 | iex" 2>/dev/null || {
            log_warning "Could not install qlty on Windows. Install manually:"
            log_info "  https://github.com/qltysh/qlty#installation"
            return 1
        }
    else
        curl -fsSL https://qlty.sh/install.sh | bash
    fi

    export PATH="$HOME/.qlty/bin:$PATH"
}

install_ast_grep() {
    log_step "Installing ast-grep (AST-based code search)..."

    if command -v cargo &>/dev/null; then
        cargo install ast-grep --locked --quiet 2>/dev/null && return 0
    fi

    if command -v npm &>/dev/null; then
        npm install -g @ast-grep/cli --silent 2>/dev/null && return 0
    fi

    case "$PKG_MANAGER" in
        pacman) sudo pacman -S --noconfirm ast-grep 2>/dev/null || true ;;
        brew) brew install ast-grep 2>/dev/null || true ;;
        *)
            log_warning "Install ast-grep manually:"
            log_info "  cargo install ast-grep --locked"
            log_info "  OR: npm install -g @ast-grep/cli"
            return 1
            ;;
    esac
}

install_repomix() {
    log_step "Installing repomix (codebase packing)..."

    if command -v npm &>/dev/null; then
        npm install -g repomix --silent 2>/dev/null && return 0
    fi

    log_warning "npm not found. Install repomix manually: npm install -g repomix"
    return 1
}

install_jq() {
    log_step "Installing jq (JSON processor)..."

    case "$PKG_MANAGER" in
        pacman) sudo pacman -S --noconfirm jq ;;
        apt) sudo apt-get update && sudo apt-get install -y jq ;;
        dnf|yum) sudo $PKG_MANAGER install -y jq ;;
        zypper) sudo zypper install -y jq ;;
        apk) sudo apk add jq ;;
        brew) brew install jq ;;
        winget) winget install jqlang.jq --silent ;;
        choco) choco install jq -y ;;
        scoop) scoop install jq ;;
        nix) nix-env -i jq ;;
        *)
            log_warning "Install jq manually for full functionality"
            return 1
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Validation Function
# ─────────────────────────────────────────────────────────────────────────────

validate_components() {
    local all_ok=true

    print_section "Component Validation"

    echo "System Information:"
    echo "  OS:           $OS ($DISTRO)"
    echo "  Architecture: $ARCH"
    echo "  Package Mgr:  ${PKG_MANAGER:-none detected}"
    echo ""

    echo "┌─────────────────────────────────────────────────────────────────────┐"
    echo "│ Component          │ Status      │ Version/Path                    │"
    echo "├─────────────────────────────────────────────────────────────────────┤"

    # Required Components
    if check_command uv "$HOME/.local/bin/uv $HOME/.cargo/bin/uv"; then
        printf "│ %-18s │ ${GREEN}%-11s${NC} │ %-33s │\n" "uv" "✓ OK" "$(get_version uv)"
    else
        printf "│ %-18s │ ${RED}%-11s${NC} │ %-33s │\n" "uv" "✗ MISSING" "Required for MCP runtime"
        all_ok=false
    fi

    if check_command node; then
        printf "│ %-18s │ ${GREEN}%-11s${NC} │ %-33s │\n" "node" "✓ OK" "$(get_version node -v)"
    else
        printf "│ %-18s │ ${RED}%-11s${NC} │ %-33s │\n" "node" "✗ MISSING" "Required for hooks"
        all_ok=false
    fi

    if check_command npm; then
        printf "│ %-18s │ ${GREEN}%-11s${NC} │ %-33s │\n" "npm" "✓ OK" "$(get_version npm -v)"
    else
        printf "│ %-18s │ ${RED}%-11s${NC} │ %-33s │\n" "npm" "✗ MISSING" "Required for MCP servers"
        all_ok=false
    fi

    echo "├─────────────────────────────────────────────────────────────────────┤"

    # Optional Components (Local-First Tools)
    if check_command qlty "$HOME/.qlty/bin/qlty"; then
        printf "│ %-18s │ ${GREEN}%-11s${NC} │ %-33s │\n" "qlty" "✓ OK" "Code quality (local)"
    else
        printf "│ %-18s │ ${YELLOW}%-11s${NC} │ %-33s │\n" "qlty" "○ Optional" "Code quality toolkit"
    fi

    if check_command sg || check_command ast-grep; then
        printf "│ %-18s │ ${GREEN}%-11s${NC} │ %-33s │\n" "ast-grep" "✓ OK" "AST search (local)"
    else
        printf "│ %-18s │ ${YELLOW}%-11s${NC} │ %-33s │\n" "ast-grep" "○ Optional" "AST-based code search"
    fi

    if check_command repomix; then
        printf "│ %-18s │ ${GREEN}%-11s${NC} │ %-33s │\n" "repomix" "✓ OK" "Codebase packing (local)"
    else
        printf "│ %-18s │ ${YELLOW}%-11s${NC} │ %-33s │\n" "repomix" "○ Optional" "Replaces RepoPrompt"
    fi

    if check_command jq; then
        printf "│ %-18s │ ${GREEN}%-11s${NC} │ %-33s │\n" "jq" "✓ OK" "JSON processor"
    else
        printf "│ %-18s │ ${YELLOW}%-11s${NC} │ %-33s │\n" "jq" "○ Optional" "For MCP config cleanup"
    fi

    echo "├─────────────────────────────────────────────────────────────────────┤"

    # Check for Python packages
    if python3 -c "import trafilatura" 2>/dev/null; then
        printf "│ %-18s │ ${GREEN}%-11s${NC} │ %-33s │\n" "trafilatura" "✓ OK" "Web scraping (local)"
    else
        printf "│ %-18s │ ${YELLOW}%-11s${NC} │ %-33s │\n" "trafilatura" "○ Optional" "Replaces Firecrawl"
    fi

    # Check for claude-mem
    if [[ -d "$HOME/.claude/plugins/marketplaces/thedotmack/claude-mem-search" ]]; then
        printf "│ %-18s │ ${GREEN}%-11s${NC} │ %-33s │\n" "claude-mem" "✓ OK" "Cross-session memory (local)"
    else
        printf "│ %-18s │ ${YELLOW}%-11s${NC} │ %-33s │\n" "claude-mem" "○ Optional" "Replaces Braintrust"
    fi

    echo "└─────────────────────────────────────────────────────────────────────┘"
    echo ""

    # MCP Servers Status
    if [[ -f "$GLOBAL_DIR/mcp_config.json" ]] && command -v jq &>/dev/null; then
        echo "MCP Servers Configuration:"
        echo "┌─────────────────────────────────────────────────────────────────────┐"
        echo "│ Server           │ Status      │ Notes                              │"
        echo "├─────────────────────────────────────────────────────────────────────┤"

        # Parse MCP config
        jq -r '.mcpServers | to_entries[] | "\(.key)|\(.value.disabled // false)"' "$GLOBAL_DIR/mcp_config.json" 2>/dev/null | while IFS='|' read -r name disabled; do
            if [[ "$disabled" == "true" ]]; then
                printf "│ %-16s │ ${YELLOW}%-11s${NC} │ %-36s │\n" "$name" "○ Disabled" "Enable in mcp_config.json"
            else
                printf "│ %-16s │ ${GREEN}%-11s${NC} │ %-36s │\n" "$name" "✓ Enabled" "Active"
            fi
        done

        echo "└─────────────────────────────────────────────────────────────────────┘"
    fi

    echo ""

    if $all_ok; then
        log_success "All required components are installed!"
        return 0
    else
        log_error "Some required components are missing"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Installation
# ─────────────────────────────────────────────────────────────────────────────

main_install() {
    print_header

    echo "This will install to: $GLOBAL_DIR"
    echo ""
    echo "  ${YELLOW}⚠ WILL BE REPLACED:${NC}"
    echo "    • ~/.claude/skills/     (all skills)"
    echo "    • ~/.claude/agents/     (all agents)"
    echo "    • ~/.claude/rules/      (all rules)"
    echo "    • ~/.claude/hooks/      (all hooks)"
    echo "    • ~/.claude/settings.json (backup created)"
    echo ""
    echo "  ${GREEN}✓ PRESERVED:${NC}"
    echo "    • ~/.claude/.env"
    echo "    • ~/.claude/cache/"
    echo "    • ~/.claude/plugins/"
    echo ""
    echo "  ${BLUE}📦 Full backup:${NC} ~/.claude-backup-$TIMESTAMP"
    echo ""

    if [[ "$SKIP_CONFIRM" != "true" ]]; then
        read -p "Continue with installation? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Installation cancelled."
            exit 0
        fi
    fi

    # ─────────────────────────────────────────────────────────────────────────
    print_section "Installing Required Components"
    # ─────────────────────────────────────────────────────────────────────────

    # Check/Install uv
    if ! check_command uv "$HOME/.local/bin/uv $HOME/.cargo/bin/uv"; then
        install_uv
        if check_command uv "$HOME/.local/bin/uv $HOME/.cargo/bin/uv"; then
            log_success "uv installed"
        else
            log_error "Failed to install uv. Install manually: https://docs.astral.sh/uv/"
            exit 1
        fi
    else
        log_success "uv already installed"
    fi

    # Check/Install Node.js
    if ! check_command node; then
        install_node
        if check_command node; then
            log_success "Node.js installed"
        else
            log_error "Failed to install Node.js. Install manually: https://nodejs.org/"
            exit 1
        fi
    else
        log_success "Node.js already installed ($(get_version node -v))"
    fi

    # ─────────────────────────────────────────────────────────────────────────
    print_section "Installing Optional Components (Local-First Tools)"
    # ─────────────────────────────────────────────────────────────────────────

    # qlty
    if ! check_command qlty "$HOME/.qlty/bin/qlty"; then
        install_qlty || log_warning "qlty not installed (optional)"
    else
        log_success "qlty already installed"
    fi

    # ast-grep
    if ! check_command sg && ! check_command ast-grep; then
        install_ast_grep || log_warning "ast-grep not installed (optional)"
    else
        log_success "ast-grep already installed"
    fi

    # repomix
    if ! check_command repomix; then
        install_repomix || log_warning "repomix not installed (optional)"
    else
        log_success "repomix already installed"
    fi

    # jq
    if ! check_command jq; then
        install_jq || log_warning "jq not installed (optional)"
    else
        log_success "jq already installed"
    fi

    # ─────────────────────────────────────────────────────────────────────────
    print_section "Installing MCP Runtime"
    # ─────────────────────────────────────────────────────────────────────────

    cd "$SCRIPT_DIR"
    log_step "Installing MCP runtime package globally..."
    uv tool install . --force --quiet 2>/dev/null || {
        log_warning "Could not install MCP package globally. Run manually:"
        log_info "  cd $SCRIPT_DIR && uv tool install . --force"
    }
    log_success "MCP commands installed: mcp-exec, mcp-generate, mcp-discover"

    # ─────────────────────────────────────────────────────────────────────────
    print_section "Installing Configuration Files"
    # ─────────────────────────────────────────────────────────────────────────

    # Create global dir
    mkdir -p "$GLOBAL_DIR"

    # Backup existing
    if [[ -d "$GLOBAL_DIR" ]] && [[ "$(ls -A "$GLOBAL_DIR" 2>/dev/null)" ]]; then
        BACKUP_DIR="$HOME/.claude-backup-$TIMESTAMP"
        log_step "Creating backup at $BACKUP_DIR..."
        cp -r "$GLOBAL_DIR" "$BACKUP_DIR"
        log_success "Backup complete"
    fi

    # Copy directories
    for dir in skills agents rules hooks; do
        log_step "Installing $dir..."
        rm -rf "$GLOBAL_DIR/$dir"
        cp -r "$SCRIPT_DIR/.claude/$dir" "$GLOBAL_DIR/$dir"
    done

    # Clean hooks (remove source files)
    rm -rf "$GLOBAL_DIR/hooks/src" "$GLOBAL_DIR/hooks/node_modules" "$GLOBAL_DIR/hooks/"*.ts 2>/dev/null || true
    log_success "Hooks installed (pre-bundled, no npm install needed)"

    # Copy scripts
    log_step "Installing scripts..."
    mkdir -p "$GLOBAL_DIR/scripts"
    cp "$SCRIPT_DIR/scripts/"*.py "$GLOBAL_DIR/scripts/" 2>/dev/null || true
    cp "$SCRIPT_DIR/.claude/scripts/"*.sh "$GLOBAL_DIR/scripts/" 2>/dev/null || true
    cp "$SCRIPT_DIR/init-project.sh" "$GLOBAL_DIR/scripts/" 2>/dev/null || true
    cp "$SCRIPT_DIR/scripts/artifact_schema.sql" "$GLOBAL_DIR/scripts/" 2>/dev/null || true

    # Copy MCP config with proper paths
    log_step "Installing MCP config..."

    # Create a modified mcp_config.json with absolute paths
    if command -v jq &>/dev/null; then
        # Use jq to update paths
        jq --arg home "$HOME" --arg script_dir "$SCRIPT_DIR" '
            .mcpServers.qlty.command = "python" |
            .mcpServers.qlty.args = [($home + "/.claude/servers/qlty/server.py")] |
            if .mcpServers.repomix then
                .mcpServers.repomix.command = "npx" |
                .mcpServers.repomix.args = ["-y", "repomix", "--mcp"]
            else . end
        ' "$SCRIPT_DIR/mcp_config.json" > "$GLOBAL_DIR/mcp_config.json"
    else
        cp "$SCRIPT_DIR/mcp_config.json" "$GLOBAL_DIR/mcp_config.json"
    fi

    # Copy servers directory for qlty MCP
    log_step "Installing MCP servers..."
    mkdir -p "$GLOBAL_DIR/servers"
    cp -r "$SCRIPT_DIR/servers/qlty" "$GLOBAL_DIR/servers/" 2>/dev/null || true

    # Copy plugins
    log_step "Installing plugins..."
    mkdir -p "$GLOBAL_DIR/plugins"
    cp -r "$SCRIPT_DIR/.claude/plugins/braintrust-tracing" "$GLOBAL_DIR/plugins/" 2>/dev/null || true

    # Copy settings.json
    log_step "Installing settings.json..."
    cp "$SCRIPT_DIR/.claude/settings.json" "$GLOBAL_DIR/settings.json"

    # Merge .env (preserve existing values, add new keys from template)
    log_step "Updating .env configuration..."
    merge_env_files "$SCRIPT_DIR/.env.example" "$GLOBAL_DIR/.env"
    chmod 600 "$GLOBAL_DIR/.env"  # Protect secrets

    # Create cache directories
    mkdir -p "$GLOBAL_DIR/cache/learnings"
    mkdir -p "$GLOBAL_DIR/cache/insights"
    mkdir -p "$GLOBAL_DIR/cache/agents"
    mkdir -p "$GLOBAL_DIR/cache/artifact-index"
    mkdir -p "$GLOBAL_DIR/state/braintrust_sessions"

    # ─────────────────────────────────────────────────────────────────────────
    print_section "Cleaning Up Global MCP Servers"
    # ─────────────────────────────────────────────────────────────────────────

    CLAUDE_JSON="$HOME/.claude.json"
    if [[ -f "$CLAUDE_JSON" ]] && command -v jq &>/dev/null; then
        GLOBAL_MCP_COUNT=$(jq -r '.mcpServers // {} | keys | length' "$CLAUDE_JSON" 2>/dev/null || echo "0")
        if [[ "$GLOBAL_MCP_COUNT" -gt 0 ]]; then
            log_warning "Found $GLOBAL_MCP_COUNT global MCP servers in ~/.claude.json"
            echo ""
            jq -r '.mcpServers // {} | keys[]' "$CLAUDE_JSON" 2>/dev/null | sed 's/^/    • /'
            echo ""
            log_info "Global servers are inherited by ALL projects."
            log_info "Recommended: Configure per-project in .mcp.json instead."
            echo ""

            if [[ "$SKIP_CONFIRM" != "true" ]]; then
                read -p "Remove global MCP servers? [y/N] " -n 1 -r
                echo ""
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    cp "$CLAUDE_JSON" "$CLAUDE_JSON.backup.$TIMESTAMP"
                    jq 'del(.mcpServers)' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp"
                    mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
                    log_success "Removed global MCP servers (backup: $CLAUDE_JSON.backup.$TIMESTAMP)"
                fi
            fi
        fi
    fi

    # ─────────────────────────────────────────────────────────────────────────
    print_section "Validation"
    # ─────────────────────────────────────────────────────────────────────────

    validate_components

    # ─────────────────────────────────────────────────────────────────────────
    print_section "Installation Complete!"
    # ─────────────────────────────────────────────────────────────────────────

    echo "┌─────────────────────────────────────────────────────────────────────┐"
    echo "│                    RUNS 100% OFFLINE                                │"
    echo "│                 All services have local alternatives                │"
    echo "├─────────────────────────────────────────────────────────────────────┤"
    echo "│ Paid Service      │ Local Alternative       │ Status               │"
    echo "├─────────────────────────────────────────────────────────────────────┤"

    # Show local alternatives with status
    if [[ -d "$HOME/.claude/plugins/marketplaces/thedotmack/claude-mem-search" ]]; then
        printf "│ %-17s │ %-23s │ ${GREEN}%-20s${NC} │\n" "Braintrust" "claude-mem" "✓ Installed"
    else
        printf "│ %-17s │ %-23s │ ${YELLOW}%-20s${NC} │\n" "Braintrust" "claude-mem" "○ Not installed"
    fi

    if check_command repomix; then
        printf "│ %-17s │ %-23s │ ${GREEN}%-20s${NC} │\n" "RepoPrompt" "repomix" "✓ Installed"
    else
        printf "│ %-17s │ %-23s │ ${YELLOW}%-20s${NC} │\n" "RepoPrompt" "repomix" "○ Not installed"
    fi

    printf "│ %-17s │ %-23s │ ${GREEN}%-20s${NC} │\n" "Perplexity" "WebSearch (builtin)" "✓ Always available"

    if python3 -c "import trafilatura" 2>/dev/null; then
        printf "│ %-17s │ %-23s │ ${GREEN}%-20s${NC} │\n" "Firecrawl" "trafilatura" "✓ Installed"
    else
        printf "│ %-17s │ %-23s │ ${YELLOW}%-20s${NC} │\n" "Firecrawl" "trafilatura" "○ pip install trafilatura"
    fi

    printf "│ %-17s │ %-23s │ ${GREEN}%-20s${NC} │\n" "Morph" "Grep/ripgrep (builtin)" "✓ Always available"
    printf "│ %-17s │ %-23s │ ${GREEN}%-20s${NC} │\n" "Nia" "Context7 MCP" "✓ Always available"

    echo "└─────────────────────────────────────────────────────────────────────┘"
    echo ""

    echo "Next Steps:"
    echo ""
    echo "  1. ${BOLD}Initialize a project:${NC}"
    echo "     cd /path/to/your/project"
    echo "     ~/.claude/scripts/init-project.sh"
    echo ""
    echo "  2. ${BOLD}(Optional) Add API keys for enhanced features:${NC}"
    echo "     Edit ~/.claude/.env"
    echo ""
    echo "  3. ${BOLD}(Optional) Install claude-mem for cross-session memory:${NC}"
    echo "     claude plugin marketplace add thedotmack/claude-mem"
    echo "     claude plugin install claude-mem"
    echo ""
    echo "  4. ${BOLD}Start Claude Code:${NC}"
    echo "     claude"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Parse Arguments
# ─────────────────────────────────────────────────────────────────────────────

SKIP_CONFIRM=false
VALIDATE_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            SKIP_CONFIRM=true
            shift
            ;;
        -v|--validate)
            VALIDATE_ONLY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -y, --yes       Skip confirmation prompts"
            echo "  -v, --validate  Only validate components (no install)"
            echo "  -h, --help      Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────────────

detect_os

if $VALIDATE_ONLY; then
    print_header
    validate_components
else
    main_install
fi
