#!/bin/bash

# Absolute Path of the Directory which has loader.sh
# /redhat-automation/util
UTIL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sh_files=("${UTIL_SCRIPT_DIR}"/*.sh)

# Source load with higher priority script ( command.sh )
source "${UTIL_SCRIPT_DIR}/command.sh"

# Load other .sh files except command.sh 
for file in "${sh_files[@]}"; do
    [[ "$(basename "${file}")" == "util_loader.sh" ]] && continue
    [[ "$(basename "${file}")" == "command.sh" ]] && continue
    [[ -f "${file}" ]] && source "${file}"
done