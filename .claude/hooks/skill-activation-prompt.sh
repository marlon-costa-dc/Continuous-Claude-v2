#!/bin/bash
set -e
# Pass PPID to Node so it can find the correct context file
export CLAUDE_PPID="$PPID"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
run_hook "skill-activation-prompt"
