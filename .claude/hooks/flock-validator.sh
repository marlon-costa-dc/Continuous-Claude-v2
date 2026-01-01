#!/usr/bin/env bash
################################################################################
# Hook: FLOCK Protocol Validator
# Event: PreToolUse (Edit/Write)
# Exit codes:
#   0 = Pass (allow operation)
#   2 = Block (FLOCK violation - file locked by another agent)
#
# PURPOSE: Enforce FLOCK file coordination protocol
# - Prevents editing files with active FLOCK from other agents
# - Detects concurrent modification attempts
# - Shows clear error with lock owner information
#
# FLOCK PROTOCOL:
#   1. Check .token file for existing locks
#   2. Write lock: FLOCK_[AGENT_NAME]_[FILE]
#   3. Re-read file after lock
#   4. Make changes
#   5. Release lock: RELEASE_[AGENT_NAME]_[FILE]
#
# shellcheck shell=bash
################################################################################

set -euo pipefail

# Load shared libraries
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${HOOK_DIR}/lib"

# shellcheck source=lib/colors.sh
source "${LIB_DIR}/colors.sh"
# shellcheck source=lib/json_parser.sh
source "${LIB_DIR}/json_parser.sh"

# Configuration
FLOCK_TIMEOUT=1800  # 30 minutes in seconds

################################################################################
# MAIN VALIDATION LOGIC
################################################################################

# Only validate Edit/Write operations
is_file_modification_tool || exit 0

log_debug "FLOCK validator: Checking file locks for $(get_tool_name) operation..."

# Extract file path using shared parser
file_path="$(get_file_path)"

if [[ -z "$file_path" ]]; then
    log_debug "No file path detected, skipping FLOCK check"
    exit 0
fi

log_debug "Checking FLOCK status for: $file_path"

################################################################################
# FIND .token FILE
################################################################################

# Look for .token file in current and parent directories
token_file=""

# Search up to 5 levels up from current directory
for level in {0..5}; do
    search_path=""
    if [[ $level -eq 0 ]]; then
        search_path=".token"
    else
        search_path=$(printf '../%.0s' $(seq 1 $level)).token
    fi

    if [[ -f "$search_path" ]]; then
        token_file="$search_path"
        log_debug "Found .token file: $token_file"
        break
    fi
done

# If no .token file found, no coordination happening - allow operation
if [[ -z "$token_file" || ! -f "$token_file" ]]; then
    log_debug "No .token file found, no FLOCK coordination active"
    exit 0
fi

################################################################################
# CHECK FOR ACTIVE FLOCKS
################################################################################

# Extract just the filename from the path
filename=$(basename "$file_path")
log_debug "Checking for FLOCKs on file: $filename"

# Look for active FLOCK entries in .token file
# Pattern: FLOCK_[AGENT_NAME]_[FILE_PATH]
# Active if not followed by RELEASE

active_lock=""
lock_owner=""
lock_time=""

while IFS= read -r line; do
    # Skip empty lines and release markers
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^RELEASE_ ]] && continue

    # Check if this is a FLOCK entry for our file
    if [[ "$line" =~ ^FLOCK_[^_]*_.*${filename}$ ]]; then
        # Extract agent name from FLOCK_AGENT_NAME_FILE
        lock_owner=$(echo "$line" | sed -E 's/FLOCK_([^_]*)_.*/\1/')
        active_lock="$line"
        log_debug "Found active FLOCK: owner=$lock_owner"
        break
    fi
done < "$token_file"

################################################################################
# VIOLATION HANDLING
################################################################################

if [[ -n "$active_lock" ]]; then
    log_error "File is locked by another agent!"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "CRITICAL: FLOCK PROTOCOL VIOLATION"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "❌ VIOLATION: File is locked by another agent"
    echo "   File:     $file_path"
    echo "   Locked by: $lock_owner"
    echo "   Lock:     $active_lock"
    echo ""
    echo "WHY THIS MATTERS:"
    echo "  Modifying a file while another agent edits it causes:"
    echo "  • Merge conflicts (code corruption)"
    echo "  • Lost changes (one version overwrites the other)"
    echo "  • Test failures (inconsistent state)"
    echo "  • Data loss (unrecoverable changes)"
    echo ""
    echo "RULE (FLOCK PROTOCOL):"
    echo "  '🔴 NEVER modify a file with active flock from another agent'"
    echo "  '🔄 ALWAYS re-read file after lock is established'"
    echo "  '⚡ RELEASE immediately after changes complete'"
    echo ""
    echo "SPECIFIC OPTIONS:"
    echo ""
    echo "  Option A: WAIT for $lock_owner to finish (Recommended)"
    echo "    - Check status:  tail -f ${token_file}"
    echo "    - Watch for:     RELEASE_${lock_owner}_${filename}"
    echo "    - Then retry:    Rerun your operation"
    echo ""
    echo "  Option B: WORK on different file"
    echo "    - List locked files: grep FLOCK ${token_file}"
    echo "    - Find unlocked file in your plan"
    echo "    - Return to $filename when lock released"
    echo ""
    echo "  Option C: CONTACT other agent (if lock stale >30 min)"
    echo "    - Check lock time: grep -n \"FLOCK\" ${token_file}"
    echo "    - Ask: Is $lock_owner still working?"
    echo "    - If no response, escalate to user"
    echo ""
    echo "  Option D: ESCALATE to user (if uncertain)"
    echo "    - Describe: What you're trying to do"
    echo "    - Mention: Locked by $lock_owner on $filename"
    echo "    - Ask: Should I wait, work on something else, or force?"
    echo ""
    echo "ACTION REQUIRED:"
    echo "  ❌ DO NOT attempt to Edit/Write $filename right now"
    echo "  ❌ DO NOT work around the lock (creates merge conflicts)"
    echo "  ❌ DO NOT assume lock is stale without checking time"
    echo "  ✅ DO choose one option above (A-D)"
    echo "  ✅ DO wait for RELEASE marker in .token"
    echo "  ✅ DO ask user if unsure what to do"
    echo ""
    echo "CHECKING LOCK STATUS:"
    echo "  $ cat ${token_file}"
    echo "  # Will show: FLOCK_${lock_owner}_${filename}"
    echo "  # And later: RELEASE_${lock_owner}_${filename}"
    echo ""
    echo "REFERENCE:"
    echo "  • Documentation: CLAUDE.md (FLOCK PROTOCOL)"
    echo "  • Enforcement: .claude/hooks/flock-validator.sh"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    # Exit code 2 = Block operation
    exit 2
fi

log_debug "No active FLOCK on $filename - proceeding"
exit 0
