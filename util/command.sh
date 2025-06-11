#!/bin/bash

# Directory Path 
# source 되었을 때에도 command.sh가 있는 디렉토리 경로 /redhat-automation/util을 정확히 반환.
UTIL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTIL_BIN_DIR="${UTIL_SCRIPT_DIR}/../bin"

# ==================Functions assosiated with Linux Command or Wrapping =======================

determine_command_source() {
    local path=$1
    cd "${path}" || return 1

    # priority : 1. built-in command > 2. toybox command
    export PATH="${PATH}:${path}" 

    for cmd in $("${path}/toybox"); do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            ln -sf toybox "${cmd}"
        fi
    done
}

determine_command_source "${UTIL_BIN_DIR}"