#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Initialize a project for Continuous Claude
# ═══════════════════════════════════════════════════════════════════════════════
#
# Usage:
#   init-project.sh [OPTIONS]
#
# Options:
#   --mode fresh     Create new thoughts/ directory (standalone project)
#   --mode monorepo  Link to parent's thoughts/ directory (monorepo)
#   --mode ask       Interactive prompt (default)
#   --quiet          Non-interactive (auto-detect: monorepo if parent found, else fresh)
#   --help           Show this help
#
# Examples:
#   cd /path/to/project && ~/.claude/scripts/init-project.sh
#   init-project.sh --mode fresh
#   init-project.sh --quiet              # Auto-detect mode
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"
MODE="ask"
QUIET=false
PARENT_DIR=""

# Colors (with fallback for non-color terminals)
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    CYAN=''
    NC=''
fi

log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_step() { echo -e "${CYAN}→${NC} $1"; }

# ─────────────────────────────────────────────────────────────────────────────
# Parse Arguments
# ─────────────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        --help|-h)
            echo "Usage: init-project.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --mode fresh     Create new thoughts/ directory"
            echo "  --mode monorepo  Link to parent's thoughts/ directory"
            echo "  --mode ask       Interactive prompt (default)"
            echo "  --quiet          Non-interactive (auto-detect mode)"
            echo "  --help           Show this help"
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
# Monorepo Detection
# ─────────────────────────────────────────────────────────────────────────────

detect_monorepo() {
    local dir="$PROJECT_DIR"
    while [[ "$dir" != "/" ]]; do
        dir="$(dirname "$dir")"
        if [[ -d "$dir/thoughts" ]]; then
            echo "$dir"
            return 0
        fi
    done
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Mode Selection
# ─────────────────────────────────────────────────────────────────────────────

if [[ "$MODE" == "ask" ]]; then
    if $QUIET; then
        # Quiet mode: auto-detect
        if PARENT_DIR=$(detect_monorepo); then
            MODE="monorepo"
        else
            MODE="fresh"
        fi
    else
        # Interactive mode
        if PARENT_DIR=$(detect_monorepo); then
            echo ""
            echo "┌─────────────────────────────────────────────────────────────┐"
            echo "│  Continuous Claude - Project Initialization                 │"
            echo "└─────────────────────────────────────────────────────────────┘"
            echo ""
            echo "Project: $PROJECT_DIR"
            echo ""
            echo -e "${YELLOW}Found parent project with thoughts/ at:${NC}"
            echo "  $PARENT_DIR"
            echo ""
            echo "  1) Fresh install (create new thoughts/ in this project)"
            echo "  2) Monorepo mode (symlink to parent's thoughts/)"
            echo ""
            read -p "Choose [1/2, default=1]: " choice
            case $choice in
                2) MODE="monorepo" ;;
                *) MODE="fresh" ;;
            esac
        else
            MODE="fresh"
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Initialization
# ─────────────────────────────────────────────────────────────────────────────

if ! $QUIET; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  Continuous Claude - Project Initialization                 │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    echo "Project: $PROJECT_DIR"
    echo "Mode: $MODE"
    echo ""
fi

# Create .claude/cache directory (always local)
mkdir -p "$PROJECT_DIR/.claude/cache/artifact-index"

if [[ "$MODE" == "monorepo" ]]; then
    # ─────────────────────────────────────────────────────────────────────
    # Monorepo Mode: Create symlinks
    # ─────────────────────────────────────────────────────────────────────

    if [[ -z "$PARENT_DIR" ]]; then
        PARENT_DIR=$(detect_monorepo) || {
            log_warning "No parent project with thoughts/ found. Falling back to fresh mode."
            MODE="fresh"
        }
    fi

    if [[ "$MODE" == "monorepo" ]]; then
        log_step "Setting up monorepo mode..."

        # Remove existing thoughts/ if it's not already a symlink
        if [[ -d "$PROJECT_DIR/thoughts" && ! -L "$PROJECT_DIR/thoughts" ]]; then
            log_warning "Existing thoughts/ directory found. Backing up to thoughts.bak"
            mv "$PROJECT_DIR/thoughts" "$PROJECT_DIR/thoughts.bak"
        fi

        # Create symlink
        ln -sf "$PARENT_DIR/thoughts" "$PROJECT_DIR/thoughts"
        log_success "Linked thoughts/ → $PARENT_DIR/thoughts"
    fi
fi

if [[ "$MODE" == "fresh" ]]; then
    # ─────────────────────────────────────────────────────────────────────
    # Fresh Mode: Create directories
    # ─────────────────────────────────────────────────────────────────────

    log_step "Creating directory structure..."
    mkdir -p "$PROJECT_DIR/thoughts/ledgers"
    mkdir -p "$PROJECT_DIR/thoughts/shared/handoffs"
    mkdir -p "$PROJECT_DIR/thoughts/shared/plans"
    log_success "Created thoughts/ directory structure"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Initialize Artifact Index Database
# ─────────────────────────────────────────────────────────────────────────────

log_step "Initializing Artifact Index database..."
DB_PATH="$PROJECT_DIR/.claude/cache/artifact-index/context.db"

if [[ -f "$DB_PATH" ]]; then
    log_success "Database already exists, skipping (brownfield project)"
elif [[ -f "$SCRIPT_DIR/artifact_schema.sql" ]]; then
    # Schema is in same directory as this script (global install)
    sqlite3 "$DB_PATH" < "$SCRIPT_DIR/artifact_schema.sql"
    log_success "Database created at .claude/cache/artifact-index/context.db"
elif [[ -f "$SCRIPT_DIR/../scripts/artifact_schema.sql" ]]; then
    # Running from repo root
    sqlite3 "$DB_PATH" < "$SCRIPT_DIR/../scripts/artifact_schema.sql"
    log_success "Database created at .claude/cache/artifact-index/context.db"
elif [[ -f "$HOME/.claude/scripts/artifact_schema.sql" ]]; then
    # Global install location
    sqlite3 "$DB_PATH" < "$HOME/.claude/scripts/artifact_schema.sql"
    log_success "Database created at .claude/cache/artifact-index/context.db"
else
    log_warning "Schema not found - database not created"
    log_warning "Run manually: sqlite3 .claude/cache/artifact-index/context.db < scripts/artifact_schema.sql"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Check for existing MCP config
# ─────────────────────────────────────────────────────────────────────────────

if [[ -f "$PROJECT_DIR/.mcp.json" ]]; then
    if ! $QUIET; then
        echo ""
        log_warning "Found existing .mcp.json in this project."
        echo "   Claude Code will use PROJECT MCP servers, not your global config."
        echo ""
        read -p "Rename to .mcp.json.bak to use global MCP config instead? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            mv "$PROJECT_DIR/.mcp.json" "$PROJECT_DIR/.mcp.json.bak"
            log_success "Renamed to .mcp.json.bak (global MCP config will be used)"
        else
            log_step "Keeping .mcp.json (project MCP servers will be active)"
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Update .gitignore
# ─────────────────────────────────────────────────────────────────────────────

if [[ -f "$PROJECT_DIR/.gitignore" ]]; then
    if ! grep -q ".claude/cache/" "$PROJECT_DIR/.gitignore" 2>/dev/null; then
        echo "" >> "$PROJECT_DIR/.gitignore"
        echo "# Continuous Claude cache (local only)" >> "$PROJECT_DIR/.gitignore"
        echo ".claude/cache/" >> "$PROJECT_DIR/.gitignore"
        log_success "Added .claude/cache/ to .gitignore"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

if ! $QUIET; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Project initialized! ($MODE mode)"
    echo ""

    if [[ "$MODE" == "monorepo" ]]; then
        echo "  thoughts/ → $PARENT_DIR/thoughts (symlink)"
    else
        echo "  thoughts/"
        echo "  ├── ledgers/           ← Continuity ledgers (git tracked)"
        echo "  └── shared/"
        echo "      ├── handoffs/      ← Session handoffs (git tracked)"
        echo "      └── plans/         ← Implementation plans (git tracked)"
    fi
    echo ""
    echo "  .claude/"
    echo "  └── cache/"
    echo "      └── artifact-index/"
    echo "          └── context.db ← Search index (gitignored)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Next steps:"
    echo "  1. Start Claude Code in this project"
    echo "  2. Use /continuity_ledger to create your first ledger"
    echo "  3. Hooks will now work fully!"
    echo ""
fi
