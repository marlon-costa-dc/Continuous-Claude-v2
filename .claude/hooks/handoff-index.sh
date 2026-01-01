#!/bin/bash
# PostToolUse hook: Index handoffs and inject Braintrust IDs
# Matches: Write tool calls to thoughts/handoffs/**/*.md
set -e
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
run_hook_dev "handoff-index"
