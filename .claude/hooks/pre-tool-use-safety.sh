#!/usr/bin/env bash
################################################################################
# Hook: PreToolUse Safety Validator (Python)
# Event: PreToolUse
# Exit codes:
#   0 = Pass (allow operation)
#   1 = Warning (violations but allowed)
#   2 = Block (dangerous operation)
#
# PURPOSE: Security-first validation
# - Blocks dangerous Bash commands (rm, git reset --hard, etc.)
# - Validates Python files with change-aware linting
# - Creates backups for rollback capability
#
# shellcheck shell=bash
################################################################################

set -e

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pipe stdin to Python hook
cat | python3 "${HOOK_DIR}/python/pre_tool_use.py"
