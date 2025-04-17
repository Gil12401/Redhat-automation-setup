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
bondig_config_tar=$(find "${RESOURCES_DIR}" -name "bonding_config.tar.gz" 2> /dev/null )

select_bonding_members() {
    declare -gA bonding_map

    IFS=$'\n'
    local nic_rows=($(ip addr show | grep "<[^>]*>" | grep -v -E "LOOPBACK|MASTER|SLAVE"))
    IFS=${PRE_IFS}

    local roles=("primary" "secondary")
    local options=()
    local cursor=0

    for row in "${nic_rows[@]}"; do
        local nic_name=$(echo "${row}" | cut -d " " -f 2 | tr -d ":")
        options+=("${nic_name}")
    done

    local index=0
    while :; do
        [[ ${index} -eq ${#roles[@]} ]] && break

        # Ascend Sorting
        options=($(sort_version_array options[@]))

        local cur_role="${roles[${index}]}"
        draw_menu "${cursor}" "Bonding 대상 선택 : ${cur_role} (뒤로가기 : ← )" "${options[@]}"

        read -rsn1 key
        if [[ "${key}" == $'\x1b' ]]; then 
            read -rsn2 -t 0.1 key2
            key+="${key2}"
        fi 

        case "${key}" in
            $'\x1b[A') cursor=$((cursor - 1)); [[ ${cursor} -lt 0 ]] && cursor=$((${#options[@]} - 1)) ;;
            $'\x1b[B') cursor=$((cursor + 1)); [[ ${cursor} -ge ${#options[@]} ]] && cursor=0 ;;
            $'\x1b[D')  
                # ← 방향키로 뒤로가기
                if [[ ${index} -gt 0 ]]; then
                    ((index--))
                    options+=("${bonding_map[${roles[${index}]}]}")
                    unset bonding_map["${roles[${index}]}"]
                    cursor=0
                fi
            ;;

            "")
                local selected_nic="${options[${cursor}]}"

                bonding_map["${cur_role}"]="${selected_nic}"
                remove_from_array_inplace "options" "${selected_nic}"
                log "[DEBUG] 선택된 ${cur_role} NIC : ${selected_nic}"
                ((index++))
                sleep 0.5
                cursor=0
            ;;
        esac
    done
}

select_bonding_mode() {
    
    declare -g bonding_mode
    declare -g bonding_mode_num

    local modes=("active-backup" "802.3ad" "alb")

    declare -gA bonding_modes_map=(
        ["active-backup"]="1"
        ["802.3ad"]="4"
        ["alb"]="6"
    )

    local cursor=0
    draw_menu "${cursor}" "Bonding Mode 선택 (지원 모드: 1, 4, 6)" "${modes[@]}"

    while :; do
        read -rsn1 key
        if [[ "${key}" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key2
            key+="${key2}"
        fi

        case "${key}" in
            $'\x1b[A') cursor=$((cursor - 1)); [[ ${cursor} -lt 0 ]] && cursor=$((${#modes[@]} - 1)) ;;
            $'\x1b[B') cursor=$((cursor + 1)); [[ ${cursor} -ge ${#modes[@]} ]] && cursor=0 ;;
            "")
                bonding_mode="${modes[${cursor}]}"
                bonding_mode_num="${bonding_modes_map[${bonding_mode}]}"
                log "선택된 Bonding Mode : ${bonding_mode} (mode=${bonding_mode_num})"
                break
                ;;
        esac

        draw_menu "${cursor}" "Bonding Mode 선택 (지원 모드: 1, 4, 6)" "${modes[@]}"
    done
}

read_bonding_ip_info() {

    declare -gA bonding_info_map
    # declare -g ip_addr
    # declare -g netmask
    # eclare -g gateway
    # declare -g dns1

    while :; do
        echo ""
        echo "========================================="
        echo "   Bonding Master에 할당할 IP 주소 입력   "
        echo " ('r' 입력하면 IP주소부터 다시 기입 가능.)"
        echo "========================================="
        read -rp "IPADDR: " ip_addr
        bonding_info_map["IPADDR"]=${ip_addr}
        [[ "${ip_addr}" == "r" || "${ip_addr}" == "R" ]] && continue

        echo "========================================="
        echo "   Netmask (예: 255.255.255.0)   "
        echo " ('r' 입력하면 IP주소부터 다시 기입 가능.)"
        echo "========================================="
        read -rp "NETMASK: " netmask
        bonding_info_map["NETMASK"]=${netmask}
        [[ "${netmask}" == "r" || "${netmask}" == "R" ]] && continue

        echo "========================================="
        echo "   Gateway 입력                           "
        echo " ('r' 입력하면 IP주소부터 다시 기입 가능.)"
        echo "========================================="
        read -rp "GATEWAY: " gateway
        bonding_info_map["GATEWAY"]=${gateway}
      
        [[ "${gateway}" == "r" || "${gateway}" == "R" ]] && continue

        echo "========================================="
        echo "   DNS 서버 입력 (기본: 8.8.8.8)          "
        echo " ('r' 입력하면 IP주소부터 다시 기입 가능.)"
        echo "========================================="
        read -rp "DNS1 [공백 시, 8.8.8.8 사용 ]: " dns1
       
        [[ "${dns1}" == "r" || "${dns1}" == "R" ]] && continue
        [[ -z "${dns1}" ]] && dns1="8.8.8.8"
        bonding_info_map["DNS1"]=${dns1}

        break
    done
}

# -------------------------- CentOS7 이하 - ifcfg 설정 파일 -------------------
extract_bonding_files() {
    declare -g extracted_bonding_files
    declare -gA bonding_file_map

    if [[ -z ${bondig_config_tar} ]]; then
        error_exit "bonding_config.tar.gz 파일을 찾을 수 없습니다."
    fi

    log "bonding_config.tar.gz 압축 해제 중..."
    extracted_bonding_files=($(tar -xvzf "${bondig_config_tar}" -C "${RESOURCES_DIR}"))

    for file in "${extracted_bonding_files[@]}"; do
        # ex: "master" -> ifcfg-master, "slave" -> ifcfg-slave
        key=$(echo "${file}" | cut -d '-' -f 2 | xargs)  
        bonding_file_map["${key}"]="${file}"
    done
}

clean_ifcfg_files() {
    local path="/etc/sysconfig/network-scripts"

    # bonding 대상 NIC 목록
    local bonding_nics=()
    for role in primary secondary; do
        bonding_nics+=("${bonding_map[$role]}")
    done

    for file in ${path}/ifcfg-*; do
        local filename=$(basename "$file")
        local nic_name="${filename#ifcfg-}"

        # loopback 제외
        [[ "${nic_name}" == "lo" ]] && continue

        if [[ " ${bonding_nics[*]} " =~ " ${nic_name} " ]]; then
            log "유지됨: ${file} (bonding 대상 NIC)"
        else
            log "삭제됨: ${file} (bonding 구성과 무관)"
            rm -f "$file"
        fi
    done
}

generate_bonding_ifcfg_slaves() {
    local template_path="${RESOURCES_DIR}/${bonding_file_map["slave"]}"
    local target_path="/etc/sysconfig/network-scripts"

    if [[ ! -f "${template_path}" ]]; then
        error_exit "슬레이브 템플릿 파일을 찾을 수 없습니다: ${template_path}"
    fi

    for role in primary secondary; do
        local nic="${bonding_map[${role}]}"
        local output_file="${target_path}/ifcfg-${nic}"

        log "bonding 슬레이브 파일 생성 중: ${output_file}"

        # FIle 초기화 ( 비우기 )
        > "${output_file}" 

        while IFS= read -r line; do
            local key=$(echo "${line}" | cut -d '=' -f 1)
            local value=$(echo "${line}" | cut -d '=' -f 2)

            case "${key}" in
                DEVICE|NAME)
                    echo "${key}=${nic}" >> "${output_file}"
                    ;;
                MASTER)
                    echo "${key}=bond0" >> "${output_file}"
                    ;;
                *)
                    echo "${line}" >> "${output_file}"
                    ;;
            esac
        done < "${template_path}"

        log "${output_file} : 생성 완료: "
        cat ${output_file}
    done
}

generate_bonding_ifcfg_master() {
    local template_path="${RESOURCES_DIR}/${bonding_file_map["master"]}"
    local target_path="/etc/sysconfig/network-scripts"

    if [[ ! -f "${template_path}" ]]; then
        error_exit "슬레이브 템플릿 파일을 찾을 수 없습니다: ${template_path}"
    fi

    local output_file="${target_path}/ifcfg-bond0"

    log "bonding 슬레이브 파일 생성 중: ${output_file}"

    # FIle 초기화 ( 비우기 )
    > "${output_file}"

    while IFS= read -r line; do
        local key=$(echo "${line}" | cut -d '=' -f 1)
        local value=$(echo "${line}" | cut -d '=' -f 2)

        case "${key}" in
            DEVICE)
                echo "${key}=bond0" >> "${output_file}"
                ;;

            IPADDR|NETMASK|GATEWAY|DNS1)
                echo "[DEBUG] ${key}=${bonding_info_map[${key}]}"
                echo "${key}=${bonding_info_map[${key}]}" >> "${output_file}"
                ;;

            # BONDING_OPTS="mode=1 miimon=100 use_carrier=0 primary=eth0"
            BONDING_OPTS)
                value=$(echo "${line}" | cut -d '=' -f2- | sed 's/^"//; s/"$//')
                value=$(echo "${value}" | sed "s/mode=[0-9]\+/mode=${bonding_mode_num}/")
                value=$(echo "${value}" | sed "s/primary=[a-zA-Z0-9]\+/primary=${bonding_map["primary"]}/")
                echo "${key}=\"${value}\"" >> "${output_file}"  # 다시 따옴표 감싸기
                ;;

            *)
                echo "${line}" >> "${output_file}"
                ;;
        esac
    done < "${template_path}"
    log "${output_file} : 생성 완료: "
    cat ${output_file}
}

# -------------------------- RHEL 8버전 이상 - nmcli 설정 -------------------

configure_bonding_nmcli() {
    # 1. NetworkManager 확인 및 활성화
    if ! systemctl is-active --quiet NetworkManager; then
        log "NetworkManager 활성화 중..."
        systemctl enable --now NetworkManager
    fi

    # 2. bonding master 생성
    log "bonding master 생성: bond0 (mode=${bonding_mode})"
    nmcli connection add type bond ifname bond0 mode "${bonding_mode}" con-name bond0

    # 3. bonding 세부 옵션 설정
    nmcli connection modify bond0 +bond.options "miimon=100"
    nmcli connection modify bond0 +bond.options "primary=${bonding_map["primary"]}"
    nmcli connection modify bond0 connection.autoconnect-slaves 1

    # 4. slave NIC 연결
    local index=1
    for role in primary secondary; do
        local nic="${bonding_map[${role}]}"
        nmcli connection add type ethernet slave-type bond con-name "bond0-p${index}" ifname "${nic}" master bond0
        log "Slave 연결 완료: ${nic} → bond0-p${index}"
        ((index++))
    done
        
    # 5. prefix 변환 (netmask → CIDR)
    local ip="${bonding_info_map["IPADDR"]}"
    local netmask="${bonding_info_map["NETMASK"]}"
    local prefix=$(get_prefix_from_subnet "${netmask}")
    local gateway="${bonding_info_map["GATEWAY"]}"
    local dns="${bonding_info_map["DNS1"]}"

    # 6. bonding master에 IP/GW 설정
    nmcli connection modify bond0 ipv4.addresses "${ip}/${prefix}"
    nmcli connection modify bond0 ipv4.gateway "${gateway}"
    nmcli connection modify bond0 ipv4.dns "${dns}"
    nmcli connection modify bond0 ipv4.method manual

    # 7. bonding 활성화
    nmcli connection up bond0
}


# -------------------------- 모든 버전 공통 : Bonding 구성 확인 -------------------

show_bonding_status() {
    local bond_dev="bond0"
    local bond_info="/proc/net/bonding/${bond_dev}"

    if [[ -f "${bond_info}" ]]; then
        echo ""
        echo "==========================================="
        echo "     Bonding 상태 (${bond_dev}) 확인 결과"
        echo "==========================================="
        cat "${bond_info}"
    else
        echo "[ERROR] ${bond_info} 파일을 찾을 수 없습니다. bonding이 정상적으로 구성되지 않았을 수 있습니다."
    fi
}

# -------------------------- Main --------------------------

# 1. NIC 선택
select_bonding_members

# 2. Bonding mode 선택 
select_bonding_mode

log "Primary : ${bonding_map["primary"]}"
log "Secondary : ${bonding_map["secondary"]}"

log "Bonding mode : ${bonding_mode}"
log "Bonding mode number : ${bonding_mode_num}"

# 3. Bonding module 적재 ( Bonding 모듈 존재하지 않을 경우 )
bonding=$(echo $(lsmod | grep 'bonding'))

if [[ ${#bonding[@]} -eq "" ]]; then
    modprobe --first-time bonding
fi

version_id=$(get_os_version)
read_bonding_ip_info
flush_all_nic_ip

if [[ ${version_id} -le 7 ]]; then
    # RHEL7 버전 이하 : ifcfg 설정파일 ( NetworkManager OFF )
  
    systemctl stop NetworkManager
    
    extract_bonding_files
    clean_ifcfg_files
    generate_bonding_ifcfg_slaves
    generate_bonding_ifcfg_master
  
    systemctl restart network
    
else
    # RHEL8 버전 이상 : nmtui or nmcli ( NetworkManager )
    configure_bonding_nmcli
fi

show_bonding_status#!/bin/bash

# IFS Backup
PRE_IFS=${IFS}

# Directory Path 
SCRIPT_DIR="$(dirname "$(realpath "$0")")" # SCRIPT_DIR path : .../init-setup/modules
UTIL_DIR="${SCRIPT_DIR}/../util"
RESOURCES_DIR="${SCRIPT_DIR}/../resources"

# util functions
source "${UTIL_DIR}/util_functions.sh"

# required resources
bondig_config_tar=$(find "${RESOURCES_DIR}" -name "bonding_config.tar.gz" 2> /dev/null )

select_bonding_members() {
    declare -gA bonding_map

    IFS=$'\n'
    local nic_rows=($(ip addr show | grep "<[^>]*>" | grep -v -E "LOOPBACK|MASTER|SLAVE"))
    IFS=${PRE_IFS}

    local roles=("primary" "secondary")
    local options=()
    local cursor=0

    for row in "${nic_rows[@]}"; do
        local nic_name=$(echo "${row}" | cut -d " " -f 2 | tr -d ":")
        options+=("${nic_name}")
    done

    local index=0
    while :; do
        [[ ${index} -eq ${#roles[@]} ]] && break

        # Ascend Sorting
        options=($(sort_version_array options[@]))

        local cur_role="${roles[${index}]}"
        draw_menu "${cursor}" "Bonding 대상 선택 : ${cur_role} (뒤로가기 : ← )" "${options[@]}"

        read -rsn1 key
        if [[ "${key}" == $'\x1b' ]]; then 
            read -rsn2 -t 0.1 key2
            key+="${key2}"
        fi 

        case "${key}" in
            $'\x1b[A') cursor=$((cursor - 1)); [[ ${cursor} -lt 0 ]] && cursor=$((${#options[@]} - 1)) ;;
            $'\x1b[B') cursor=$((cursor + 1)); [[ ${cursor} -ge ${#options[@]} ]] && cursor=0 ;;
            $'\x1b[D')  
                # ← 방향키로 뒤로가기
                if [[ ${index} -gt 0 ]]; then
                    ((index--))
                    options+=("${bonding_map[${roles[${index}]}]}")
                    unset bonding_map["${roles[${index}]}"]
                    cursor=0
                fi
            ;;

            "")
                local selected_nic="${options[${cursor}]}"

                bonding_map["${cur_role}"]="${selected_nic}"
                remove_from_array_inplace "options" "${selected_nic}"
                log "[DEBUG] 선택된 ${cur_role} NIC : ${selected_nic}"
                ((index++))
                sleep 0.5
                cursor=0
            ;;
        esac
    done
}

select_bonding_mode() {
    
    declare -g bonding_mode
    declare -g bonding_mode_num

    local modes=("active-backup" "802.3ad" "alb")

    declare -gA bonding_modes_map=(
        ["active-backup"]="1"
        ["802.3ad"]="4"
        ["alb"]="6"
    )

    local cursor=0
    draw_menu "${cursor}" "Bonding Mode 선택 (지원 모드: 1, 4, 6)" "${modes[@]}"

    while :; do
        read -rsn1 key
        if [[ "${key}" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key2
            key+="${key2}"
        fi

        case "${key}" in
            $'\x1b[A') cursor=$((cursor - 1)); [[ ${cursor} -lt 0 ]] && cursor=$((${#modes[@]} - 1)) ;;
            $'\x1b[B') cursor=$((cursor + 1)); [[ ${cursor} -ge ${#modes[@]} ]] && cursor=0 ;;
            "")
                bonding_mode="${modes[${cursor}]}"
                bonding_mode_num="${bonding_modes_map[${bonding_mode}]}"
                log "선택된 Bonding Mode : ${bonding_mode} (mode=${bonding_mode_num})"
                break
                ;;
        esac

        draw_menu "${cursor}" "Bonding Mode 선택 (지원 모드: 1, 4, 6)" "${modes[@]}"
    done
}

read_bonding_ip_info() {

    declare -gA bonding_info_map
    # declare -g ip_addr
    # declare -g netmask
    # eclare -g gateway
    # declare -g dns1

    while :; do
        echo ""
        echo "========================================="
        echo "   Bonding Master에 할당할 IP 주소 입력   "
        echo " ('r' 입력하면 IP주소부터 다시 기입 가능.)"
        echo "========================================="
        read -rp "IPADDR: " ip_addr
        bonding_info_map["IPADDR"]=${ip_addr}
        [[ "${ip_addr}" == "r" || "${ip_addr}" == "R" ]] && continue

        echo "========================================="
        echo "   Netmask (예: 255.255.255.0)   "
        echo " ('r' 입력하면 IP주소부터 다시 기입 가능.)"
        echo "========================================="
        read -rp "NETMASK: " netmask
        bonding_info_map["NETMASK"]=${netmask}
        [[ "${netmask}" == "r" || "${netmask}" == "R" ]] && continue

        echo "========================================="
        echo "   Gateway 입력                           "
        echo " ('r' 입력하면 IP주소부터 다시 기입 가능.)"
        echo "========================================="
        read -rp "GATEWAY: " gateway
        bonding_info_map["GATEWAY"]=${gateway}
      
        [[ "${gateway}" == "r" || "${gateway}" == "R" ]] && continue

        echo "========================================="
        echo "   DNS 서버 입력 (기본: 8.8.8.8)          "
        echo " ('r' 입력하면 IP주소부터 다시 기입 가능.)"
        echo "========================================="
        read -rp "DNS1 [공백 시, 8.8.8.8 사용 ]: " dns1
       
        [[ "${dns1}" == "r" || "${dns1}" == "R" ]] && continue
        [[ -z "${dns1}" ]] && dns1="8.8.8.8"
        bonding_info_map["DNS1"]=${dns1}

        break
    done
}

# -------------------------- CentOS7 이하 - ifcfg 설정 파일 -------------------
extract_bonding_files() {
    declare -g extracted_bonding_files
    declare -gA bonding_file_map

    if [[ -z ${bondig_config_tar} ]]; then
        error_exit "bonding_config.tar.gz 파일을 찾을 수 없습니다."
    fi

    log "bonding_config.tar.gz 압축 해제 중..."
    extracted_bonding_files=($(tar -xvzf "${bondig_config_tar}" -C "${RESOURCES_DIR}"))

    for file in "${extracted_bonding_files[@]}"; do
        # ex: "master" -> ifcfg-master, "slave" -> ifcfg-slave
        key=$(echo "${file}" | cut -d '-' -f 2 | xargs)  
        bonding_file_map["${key}"]="${file}"
    done
}

clean_ifcfg_files() {
    local path="/etc/sysconfig/network-scripts"

    # bonding 대상 NIC 목록
    local bonding_nics=()
    for role in primary secondary; do
        bonding_nics+=("${bonding_map[$role]}")
    done

    for file in ${path}/ifcfg-*; do
        local filename=$(basename "$file")
        local nic_name="${filename#ifcfg-}"

        # loopback 제외
        [[ "${nic_name}" == "lo" ]] && continue

        if [[ " ${bonding_nics[*]} " =~ " ${nic_name} " ]]; then
            log "유지됨: ${file} (bonding 대상 NIC)"
        else
            log "삭제됨: ${file} (bonding 구성과 무관)"
            rm -f "$file"
        fi
    done
}

generate_bonding_ifcfg_slaves() {
    local template_path="${RESOURCES_DIR}/${bonding_file_map["slave"]}"
    local target_path="/etc/sysconfig/network-scripts"

    if [[ ! -f "${template_path}" ]]; then
        error_exit "슬레이브 템플릿 파일을 찾을 수 없습니다: ${template_path}"
    fi

    for role in primary secondary; do
        local nic="${bonding_map[${role}]}"
        local output_file="${target_path}/ifcfg-${nic}"

        log "bonding 슬레이브 파일 생성 중: ${output_file}"

        # FIle 초기화 ( 비우기 )
        > "${output_file}" 

        while IFS= read -r line; do
            local key=$(echo "${line}" | cut -d '=' -f 1)
            local value=$(echo "${line}" | cut -d '=' -f 2)

            case "${key}" in
                DEVICE|NAME)
                    echo "${key}=${nic}" >> "${output_file}"
                    ;;
                MASTER)
                    echo "${key}=bond0" >> "${output_file}"
                    ;;
                *)
                    echo "${line}" >> "${output_file}"
                    ;;
            esac
        done < "${template_path}"

        log "${output_file} : 생성 완료: "
        cat ${output_file}
    done
}

generate_bonding_ifcfg_master() {
    local template_path="${RESOURCES_DIR}/${bonding_file_map["master"]}"
    local target_path="/etc/sysconfig/network-scripts"

    if [[ ! -f "${template_path}" ]]; then
        error_exit "슬레이브 템플릿 파일을 찾을 수 없습니다: ${template_path}"
    fi

    local output_file="${target_path}/ifcfg-bond0"

    log "bonding 슬레이브 파일 생성 중: ${output_file}"

    # FIle 초기화 ( 비우기 )
    > "${output_file}"

    while IFS= read -r line; do
        local key=$(echo "${line}" | cut -d '=' -f 1)
        local value=$(echo "${line}" | cut -d '=' -f 2)

        case "${key}" in
            DEVICE)
                echo "${key}=bond0" >> "${output_file}"
                ;;

            IPADDR|NETMASK|GATEWAY|DNS1)
                echo "[DEBUG] ${key}=${bonding_info_map[${key}]}"
                echo "${key}=${bonding_info_map[${key}]}" >> "${output_file}"
                ;;

            # BONDING_OPTS="mode=1 miimon=100 use_carrier=0 primary=eth0"
            BONDING_OPTS)
                value=$(echo "${line}" | cut -d '=' -f2- | sed 's/^"//; s/"$//')
                value=$(echo "${value}" | sed "s/mode=[0-9]\+/mode=${bonding_mode_num}/")
                value=$(echo "${value}" | sed "s/primary=[a-zA-Z0-9]\+/primary=${bonding_map["primary"]}/")
                echo "${key}=\"${value}\"" >> "${output_file}"  # 다시 따옴표 감싸기
                ;;

            *)
                echo "${line}" >> "${output_file}"
                ;;
        esac
    done < "${template_path}"
    log "${output_file} : 생성 완료: "
    cat ${output_file}
}

# -------------------------- RHEL 8버전 이상 - nmcli 설정 -------------------

configure_bonding_nmcli() {
    # 1. NetworkManager 확인 및 활성화
    if ! systemctl is-active --quiet NetworkManager; then
        log "NetworkManager 활성화 중..."
        systemctl enable --now NetworkManager
    fi

    # 2. bonding master 생성
    log "bonding master 생성: bond0 (mode=${bonding_mode})"
    nmcli connection add type bond ifname bond0 mode "${bonding_mode}" con-name bond0

    # 3. bonding 세부 옵션 설정
    nmcli connection modify bond0 +bond.options "miimon=100"
    nmcli connection modify bond0 +bond.options "primary=${bonding_map["primary"]}"
    nmcli connection modify bond0 connection.autoconnect-slaves 1

    # 4. slave NIC 연결
    local index=1
    for role in primary secondary; do
        local nic="${bonding_map[${role}]}"
        nmcli connection add type ethernet slave-type bond con-name "bond0-p${index}" ifname "${nic}" master bond0
        log "Slave 연결 완료: ${nic} → bond0-p${index}"
        ((index++))
    done
        
    # 5. prefix 변환 (netmask → CIDR)
    local ip="${bonding_info_map["IPADDR"]}"
    local netmask="${bonding_info_map["NETMASK"]}"
    local prefix=$(get_prefix_from_subnet "${netmask}")
    local gateway="${bonding_info_map["GATEWAY"]}"
    local dns="${bonding_info_map["DNS1"]}"

    # 6. bonding master에 IP/GW 설정
    nmcli connection modify bond0 ipv4.addresses "${ip}/${prefix}"
    nmcli connection modify bond0 ipv4.gateway "${gateway}"
    nmcli connection modify bond0 ipv4.dns "${dns}"
    nmcli connection modify bond0 ipv4.method manual

    # 7. bonding 활성화
    nmcli connection up bond0
}


# -------------------------- 모든 버전 공통 : Bonding 구성 확인 -------------------

show_bonding_status() {
    local bond_dev="bond0"
    local bond_info="/proc/net/bonding/${bond_dev}"

    if [[ -f "${bond_info}" ]]; then
        echo ""
        echo "==========================================="
        echo "     Bonding 상태 (${bond_dev}) 확인 결과"
        echo "==========================================="
        cat "${bond_info}"
    else
        echo "[ERROR] ${bond_info} 파일을 찾을 수 없습니다. bonding이 정상적으로 구성되지 않았을 수 있습니다."
    fi
}

# -------------------------- Main --------------------------

# 1. NIC 선택
select_bonding_members

# 2. Bonding mode 선택 
select_bonding_mode

log "Primary : ${bonding_map["primary"]}"
log "Secondary : ${bonding_map["secondary"]}"

log "Bonding mode : ${bonding_mode}"
log "Bonding mode number : ${bonding_mode_num}"

# 3. Bonding module 적재 ( Bonding 모듈 존재하지 않을 경우 )
bonding=$(echo $(lsmod | grep 'bonding'))

if [[ ${#bonding[@]} -eq "" ]]; then
    modprobe --first-time bonding
fi

version_id=$(get_os_version)
read_bonding_ip_info
flush_all_nic_ip

if [[ ${version_id} -le 7 ]]; then
    # RHEL7 버전 이하 : ifcfg 설정파일 ( NetworkManager OFF )
  
    systemctl stop NetworkManager
    
    extract_bonding_files
    clean_ifcfg_files
    generate_bonding_ifcfg_slaves
    generate_bonding_ifcfg_master
  
    systemctl restart network
    
else
    # RHEL8 버전 이상 : nmtui or nmcli ( NetworkManager )
    configure_bonding_nmcli
fi

show_bonding_status