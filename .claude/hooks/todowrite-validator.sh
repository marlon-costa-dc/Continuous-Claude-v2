#!/usr/bin/env bash
################################################################################
# Hook: TodoWrite Sequential Phase Validator
# Event: PreToolUse (TodoWrite)
# Exit codes:
#   0 = Pass (allow operation)
#   2 = Block (sequential phase violation)
#
# PURPOSE: Enforce sequential phase execution in TodoWrite
# - Prevents skipping phases (e.g., Phase 1→2→5 is FORBIDDEN)
# - Ensures Phase 1→2→3→4→5 sequential execution only
# - Blocks any non-sequential phase sequences
#
# shellcheck shell=bash
################################################################################

# Note: set -euo pipefail is not used here to allow proper exit code handling

# Load shared libraries
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${HOOK_DIR}/lib"

# shellcheck source=lib/colors.sh
source "${LIB_DIR}/colors.sh"
# shellcheck source=lib/json_parser.sh
source "${LIB_DIR}/json_parser.sh"

################################################################################
# MAIN VALIDATION LOGIC
################################################################################

# Only validate TodoWrite tool operations
is_todowrite_tool || exit 0

log_debug "TodoWrite validator: Checking phase sequence..."

# Extract phase numbers from todos
todos_json="${CLAUDE_TOOL_INPUT:-}"

if [[ -z "$todos_json" ]]; then
    log_debug "No todo input, skipping validation"
    exit 0
fi

# Extract all "Phase X" content items from todos
# Use a temporary variable to capture output before mapfile
phase_content=$(echo "$todos_json" | jq -r '.todos[] | .content // empty' 2>/dev/null || true)

if [[ -z "$phase_content" ]]; then
    log_debug "No content extracted from todos, skipping validation"
    exit 0
fi

# Extract just the phase numbers
phases=()
while IFS= read -r phase_num; do
    if [[ -n "$phase_num" ]]; then
        phases+=("$phase_num")
    fi
done < <(echo "$phase_content" | grep -oP 'Phase \K\d+' | sort -n)

log_debug "Found phases: ${phases[*]:-none}"

# If no phases found, allow the operation
if [[ ${#phases[@]} -eq 0 ]]; then
    log_debug "No phases detected in todos, allowing operation"
    exit 0
fi

################################################################################
# SEQUENTIAL VALIDATION
################################################################################

# Check if phases are sequential: 1, 2, 3, 4, 5, etc.
# Starting from 1, each phase should increment by exactly 1

local_prev=0
has_gap=false
gap_info=""

for phase in "${phases[@]}"; do
    expected=$((local_prev + 1))

    if [[ $phase -ne $expected ]]; then
        # Gap detected (e.g., jump from 2 to 5)
        has_gap=true
        gap_info="Phase $local_prev → Phase $phase (expected Phase $expected)"
        break
    fi

    local_prev=$phase
done

################################################################################
# VIOLATION HANDLING
################################################################################

if [[ "$has_gap" == true ]]; then
    log_error "Plan execution skip detected!"
    log_error "Sequential phases required but found: ${phases[*]}"
    log_error "Gap: $gap_info"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "CRITICAL: PLAN EXECUTION PROTOCOL VIOLATION"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "❌ VIOLATION: Phase sequence is not sequential"
    echo "   Detected:   $(echo "${phases[*]}" | tr ' ' '→')"
    echo "   Required:   Sequential 1→2→3→...→N"
    echo "   Problem:    $gap_info"
    echo ""
    echo "RULE (Plan Execution Protocol):"
    echo "  'When a plan is approved, it MUST be executed following these rules:'"
    echo "  '1. ❌ NEVER skip phases - If plan has 5 steps, execute ALL 5 steps'"
    echo "  '2. ✅ ALWAYS follow sequence - Phase 1 → Phase 2 → Phase 3 → ... → Report'"
    echo ""
    echo "WHY THIS MATTERS:"
    echo "  Skipping phases means skipping WORK. Previous sessions show this happens:"
    echo "  User says: 'wait, there's much more to do'"
    echo "  Root cause: Phases were skipped, work was never done"
    echo ""
    echo "SPECIFIC REMEDIATION:"
    echo "  The TodoWrite update is BLOCKED until phases are sequential."
    echo ""
    echo "  Option 1: Complete Phase $(($local_prev + 1)) before moving to Phase $phase"
    echo "    - Return to implementation work"
    echo "    - Complete all substeps of Phase $(($local_prev + 1))"
    echo "    - Test and validate before updating TodoWrite"
    echo ""
    echo "  Option 2: Context running low during long phase?"
    echo "    - STOP and save current progress"
    echo "    - Document: 'Completed Phase $local_prev (80%), next: Phase $(($local_prev + 1)) step X'"
    echo "    - Continue in new session without jumping ahead"
    echo ""
    echo "  Option 3: Hit a blocker during Phase $(($local_prev + 1))?"
    echo "    - DO NOT skip to next phase"
    echo "    - Ask user for help: 'Phase $(($local_prev + 1)) blocked by X. Options: A, B, C?'"
    echo "    - Wait for user decision before proceeding"
    echo ""
    echo "ACTION REQUIRED:"
    echo "  ❌ DO NOT update TodoWrite with phase skipping"
    echo "  ❌ DO NOT claim completion and move to next phase"
    echo "  ✅ DO execute phases sequentially (Phase $(($local_prev + 1)) must come next)"
    echo "  ✅ DO report blockers instead of skipping phases"
    echo ""
    echo "REFERENCE:"
    echo "  • Documentation: CLAUDE.md (Plan Execution Protocol section)"
    echo "  • Enforcement: .claude/hooks/todowrite-validator.sh"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    # Exit code 2 = Block operation
    exit 2
fi

log_debug "Phase sequence valid: ${phases[*]:-none}"
exit 0
