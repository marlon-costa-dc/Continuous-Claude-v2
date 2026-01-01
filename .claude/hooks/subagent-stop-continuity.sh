#!/bin/bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
run_hook "subagent-stop-continuity"
