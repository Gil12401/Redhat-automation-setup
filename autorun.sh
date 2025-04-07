#!/bin/bash 

# autorun.sh 실행 디렉토리 : /init-setup

# ex. autorun.sh path : /mnt/init-setup/autorun.sh 
# -> SCRIPT_DIR path : /mnt/init-setup 

# Directory Path 
SCRIPT_DIR="$(dirname "$(realpath "$0")")" 
UTIL_DIR="${SCRIPT_DIR}/util"
main_script="${SCRIPT_DIR}/main.sh"

# util functions
source "${UTIL_DIR}/util_functions.sh"

# 실행 권한 확인 
if [[ ! -x "${main_script}" ]]; then
    error_exit "main.sh 실행 권한이 없습니다."
fi

log "init-setup 실행 시작"
bash "${main_script}"