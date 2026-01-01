#!/bin/bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
run_hook "session-end-cleanup"
