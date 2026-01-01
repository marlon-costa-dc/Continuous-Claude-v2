#!/bin/bash
# Shared hook utilities - workspace-first, global-fallback
# Based on: sidpan1/Continuous-Claude-v2/claude/fix-session-hook-error-J2gYX
#
# This enables hooks to work in both project-local and global installations.
# Pattern: Try CLAUDE_PROJECT_DIR/.claude/hooks first, then ~/.claude/hooks

HOOKS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run a hook with workspace-first, global-fallback resolution
# Usage: run_hook <hook_name>
# Example: run_hook "session-start-continuity"
run_hook() {
    local hook_name="$1"

    # Try workspace first (project-local)
    if [[ -f "$HOOKS_SCRIPT_DIR/dist/${hook_name}.mjs" ]]; then
        cd "$HOOKS_SCRIPT_DIR" && cat | node "dist/${hook_name}.mjs"
    # Fallback to global (~/.claude/hooks)
    elif [[ -f "$HOME/.claude/hooks/dist/${hook_name}.mjs" ]]; then
        cd "$HOME/.claude/hooks" && cat | node "dist/${hook_name}.mjs"
    else
        # Silent continue if hook not found (don't break Claude)
        echo '{"result":"continue"}'
    fi
}

# Run a hook with TypeScript dev fallback (for development)
# Usage: run_hook_dev <hook_name>
run_hook_dev() {
    local hook_name="$1"

    # Try built version first
    if [[ -f "$HOOKS_SCRIPT_DIR/dist/${hook_name}.mjs" ]]; then
        cd "$HOOKS_SCRIPT_DIR" && cat | node "dist/${hook_name}.mjs"
    elif [[ -f "$HOME/.claude/hooks/dist/${hook_name}.mjs" ]]; then
        cd "$HOME/.claude/hooks" && cat | node "dist/${hook_name}.mjs"
    # Fallback to tsx for development
    elif [[ -f "$HOOKS_SCRIPT_DIR/src/${hook_name}.ts" ]]; then
        cd "$HOOKS_SCRIPT_DIR" && cat | npx tsx "src/${hook_name}.ts"
    elif [[ -f "$HOME/.claude/hooks/src/${hook_name}.ts" ]]; then
        cd "$HOME/.claude/hooks" && cat | npx tsx "src/${hook_name}.ts"
    else
        echo '{"result":"continue"}'
    fi
}
