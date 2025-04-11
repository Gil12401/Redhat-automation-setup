#!/bin/bash

# IFS Backup
PRE_IFS=${IFS}

# Directory Path 
SCRIPT_DIR="$(dirname "$(realpath "$0")")" # SCRIPT_DIR path : .../init-setup/modules
UTIL_DIR="${SCRIPT_DIR}/../util"
RESOURCES_DIR="${SCRIPT_DIR}/../resources"

# util functions
source "${UTIL_DIR}/util_functions.sh"

# required resources
bondig_reset_tar=$(find "${RESOURCES_DIR}" -name "bonding_reset.tar.gz" 2> /dev/null )


# -------------------------- Main --------------------------

# 공통 : /etc/sysconfig/network-scripts/ 하위 

# 1. ifcfg 설정파일 원복  
# -1.ifcfg-bond0 / ifcfg-slave1 / ifcfg-slave2 삭제 
# -2.ifcfg_bak/ 하위 ifcfg-nic1 ifcfg-nic2 부모 디렉토리로 이동. 없다면 템플릿으로부터 ip입력받고 생성 

# 2. 존재하는 모든 ifcfg-nic 설정파일들에 대해서 같은 대역의 설정 파일 중 하나만 up 되도록 ( BOOTPROTO=yes ) 방어 로직 구현 

# 3. systemctl restart network  

