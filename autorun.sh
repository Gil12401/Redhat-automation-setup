#!/bin/bash 

# autorun.sh 실행 디렉토리 : /redhat-automation

# ex. autorun.sh path : /mnt/redhat-automation/autorun.sh 
# -> SCRIPT_DIR path : /mnt/redhat-automation 

# Directory Path 
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
main_script="${SCRIPT_DIR}/main.sh"
source "${SCRIPT_DIR}/util/util_loader.sh"

# Check a permission (execute -> chmod +x)
if [[ ! -x "${main_script}" ]]; then
    error_exit "Permission Denided : main.sh "
fi

bash "${main_script}"
