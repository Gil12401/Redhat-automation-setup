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

# 공통 : /etc/sysconfig/network-scripts/ 하위 
target_path="/etc/sysconfig/network-scripts"

# -------------------------- CentOS7 이하 - ifcfg 설정 파일 -------------------

extract_reset_files() {
    declare -g extracted_reset_files
    declare -gA reset_file_map

    if [[ -z ${bondig_reset_tar} ]]; then
        error_exit "bonding_reset.tar.gz 파일을 찾을 수 없습니다."
    fi

    log "bonding_reset.tar.gz 압축 해제 중..."
    extracted_reset_files=($(tar -xvzf "${bondig_reset_tar}" -C "${RESOURCES_DIR}"))

    for file in "${extracted_reset_files[@]}"; do
        # ex: "master" -> ifcfg-master, "slave" -> ifcfg-slave
        key=$(echo "${file}" | cut -d '-' -f 2 | xargs)  
        reset_file_map["${key}"]="${file}"
    done
}

select_enable_nic() {
    # ex. nic_map["eth0"]="up" /  nic_map["eth1"]="down" /  nic_map["eth2"]="down"
    declare -gA nic_map
    declare -g options
    declare -g active_nic

    IFS=$'\n'
    local nic_rows=($(ip addr show | grep "<[^>]*>" | grep -v -E "LOOPBACK|MASTER"))
    IFS=${PRE_IFS}
   
    for nic in "${nic_rows[@]}"; do
        local nic_name=$(echo "${nic}" | cut -d " " -f 2 | tr -d ":")
        # log "nic_name : ${nic_name}"
        options+=("${nic_name}")
    done

    local cursor=0
    # Ascend Sorting
    options=($(sort_version_array options[@]))
    while :; do
        draw_menu "${cursor}" "Bonding 해제 이후 활성화할 NIC를 선택하세요 ( up )" "${options[@]}"

        read -rsn1 key
        if [[ "${key}" == $'\x1b' ]]; then 
            read -rsn2 -t 0.1 key2
            key+="${key2}"
        fi 

         case "${key}" in
            $'\x1b[A') cursor=$((cursor - 1)); [[ ${cursor} -lt 0 ]] && cursor=$((${#options[@]} - 1)) ;;
            $'\x1b[B') cursor=$((cursor + 1)); [[ ${cursor} -ge ${#options[@]} ]] && cursor=0 ;;

            "")
                # ex. nic_map["eth0"]="up" /  nic_map["eth1"]="down" /  nic_map["eth2"]="down"
                # log "selected nic : ${options[${cursor}]}"
                
                local options_length=${#options[@]}

                for ((i=0; i<options_length; i++)); do
                    if [[ ${i} -eq ${cursor} ]]; then
                        nic_map[${options[${i}]}]="up"
                        active_nic="${options[${i}]}"
                    else
                        nic_map[${options[${i}]}]="down"
                    fi
                done                

            break
            ;;
        esac
    done
}

# bonding 관련 ifcfg 파일 삭제 
remove_bonding_ifcfg() {
    local prefix="ifcfg-"

    IFS=$'\n'
    local member_rows=($(ip addr show | grep "<[^>]*>" | grep  -E "MASTER|SLAVE"))
    IFS=${PRE_IFS}

    # 1. ifcfg-bond0 / ifcfg-slave1 / ifcfg-slave2 삭제 
    # member : ex. eth0 / eth2 / bond0
    
    for member in "${member_rows[@]}"; do
        local member=$(echo "${member}" | cut -d " " -f 2 | tr -d ":")
        local ifcfg_file="${prefix}${member}"

        # log "member : ${member}"
        # log "ifcfg-file : ${ifcfg_file}"
        # log "${target_path}/${ifcfg-file}"

        if [[ -f ${target_path}/${ifcfg_file} ]]; then
            rm -v "${target_path}/${ifcfg_file}"
        else
            log "${target_path}/${ifcfg_file} 설정파일 없음."
        fi
    done
}

deactivate_bonding_interface() {
    local bonding_dev="bond0"

    if ip link show "${bonding_dev}" &> /dev/null; then
        log "${bonding_dev} 장치가 아직 존재합니다. 제거 시도 중..."

        # 1. bonding 장치 down
        ip link set "${bonding_dev}" down

        # 2. bonding 장치 삭제
        ip link delete "${bonding_dev}" type bond && log "${bonding_dev} 삭제 완료"
    else
        log "${bonding_dev} 장치가 존재하지 않습니다. 건너뜁니다."
    fi

    # 3. 커널에서 bonding 모듈 언로드
    if lsmod | grep -q '^bonding'; then
        log "bonding 커널 모듈 제거 시도 중..."
        modprobe -r bonding && log "bonding 모듈 제거 완료"
    else
        log "bonding 모듈이 이미 언로드 상태입니다."
    fi
}

read_nic_ip_info() {

    declare -gA nic_info_map
    declare -g ip_addr
    declare -g netmask
    declare -g gateway
    declare -g dns1

    while :; do
        echo ""
        echo "========================================="
        echo "   활성화 할 NIC의 IP 주소 입력   "
        echo " ('r' 입력하면 IP주소부터 다시 기입 가능.)"
        echo "========================================="
        read -rp "IPADDR: " ip_addr
        nic_info_map["IPADDR"]=${ip_addr}
        [[ "${ip_addr}" == "r" || "${ip_addr}" == "R" ]] && continue

        echo "========================================="
        echo "   Netmask (예: 255.255.255.0)   "
        echo " ('r' 입력하면 IP주소부터 다시 기입 가능.)"
        echo "========================================="
        read -rp "NETMASK: " netmask
        nic_info_map["NETMASK"]=${netmask}
        nic_info_map["PREFIX"]=$(get_prefix_from_subnet "${netmask}")
       
        [[ "${netmask}" == "r" || "${netmask}" == "R" ]] && continue

        echo "========================================="
        echo "   Gateway 입력                           "
        echo " ('r' 입력하면 IP주소부터 다시 기입 가능.)  "
        echo "========================================="
        read -rp "GATEWAY: " gateway
        nic_info_map["GATEWAY"]=${gateway}
      
        [[ "${gateway}" == "r" || "${gateway}" == "R" ]] && continue

        echo "========================================="
        echo "   DNS 서버 입력 (기본: 8.8.8.8)          "
        echo " ('r' 입력하면 IP주소부터 다시 기입 가능.)"
        echo "========================================="
        read -rp "DNS1 [공백 시, 8.8.8.8 사용 ]: " dns1
        
        [[ "${dns1}" == "r" || "${dns1}" == "R" ]] && continue
        [[ -z "${dns1}" ]] && dns1="8.8.8.8"
        nic_info_map["DNS1"]=${dns1}

        break
    done
}

generate_nic_ifcfg() {

    # nic_info_map for ifcfg-nic_up 
    read_nic_ip_info
    
    for nic in "${!nic_map[@]}"; do
        local state=${nic_map[${nic}]}
        # log "nic : ${nic}"
        # log "state : ${nic_map[${nic}]}"

        local output_file="${target_path}/ifcfg-${nic}"
        local reset_file=""

        # FIle 초기화 ( 비우기 )
        > "${output_file}"

        log "${output_file} 생성 중 ... " 

        case "${state}" in
            up)
                reset_file="${RESOURCES_DIR}/${reset_file_map["nic_up"]}"
                ;;

            down)
                reset_file="${RESOURCES_DIR}/${reset_file_map["nic_down"]}"
                ;;
        esac

        while IFS= read -r line; do
            local key=$(echo "${line}" | cut -d '=' -f 1)
            local value=$(echo "${line}" | cut -d '=' -f 2)

            case "${key}" in
            DEVICE)
                echo "${key}=${nic}" >> "${output_file}"
                ;;

            IPADDR|NETMASK|GATEWAY|DNS1)
                echo "${key}=${nic_info_map[${key}]}" >> "${output_file}"
                ;;

            *)
                echo "${line}" >> "${output_file}"
                ;;
            esac
            
        done < ${reset_file}
    done
}

# -------------------------- RHEL 8버전 이상 - nmcli 설정 -------------------

wait_until_nmcli_con_down() {
   
    # result is empty : bond0 nmcli con down compele
    while :; do
        local result=$(ip -d link show bond0 | grep -oP 'slave \K\S+')
        if [[ -z "${result}" ]]; then
            log "bon0 : nmcli con down complete !" 
            break
        else
            log "not yet, Sleep 1sec."
            sleep 1
        fi
    done
}

deactivate_bonding_nmcli() {
    log "nmcli bonding reset"
    local bonding_members

    mapfile -t bonding_members < <(nmcli -t -f NAME,TYPE connection show | grep '^bond0' | cut -d':' -f1)

    nmcli con down bond0
    wait_until_nmcli_con_down

    for con in "${bonding_members[@]}"; do
        nmcli con del "${con}"
    done
}

active_nic_nmcli () {
    read_nic_ip_info
    nmcli con modify "${active_nic}" \
        ipv4.addresses "${nic_info_map["IPADDR"]}/${nic_info_map["PREFIX"]}" \
        ipv4.gateway "${nic_info_map["GATEWAY"]}" \
        ipv4.dns "${nic_info_map["DNS1"]}" \
        ipv4.method manual \
        connection.autoconnect yes

    # NIC 목록
    mapfile -t nics < <(ls /sys/class/net | grep -v '^lo$')

    for nic in "${nics[@]}"; do
        # 연결 이름 조회
        local conn_name
        conn_name=$(nmcli -t -f NAME,DEVICE con show | grep ":${nic}$" | cut -d':' -f1)

        if [[ "${nic}" == "${active_nic}" ]]; then
            log "활성화: ${conn_name} (${nic})"
            nmcli con up "${conn_name}"
        elif [[ -n "${conn_name}" ]]; then
            log "비활성화: ${conn_name} (${nic})"
            nmcli con down "${conn_name}"
        fi
    done
}

# -------------------------- Main --------------------------

select_enable_nic   # ← 여기서 ACTIVE_NIC or nic_map["ethX"]="up" 결정

version_id=$(get_os_version)

if [[ ${version_id} -le 7 ]]; then
    # RHEL7 버전 이하 : ifcfg 설저파일 ( NetworkManager OFF )
    extract_reset_files
    remove_bonding_ifcfg
    deactivate_bonding_interface
    generate_nic_ifcfg
    flush_all_nic_ip

    log "network 재시작"
    systemctl restart network 

    ip addr show
else
    # RHEL8 버전 이상 : nmtui or nmcli ( NetworkManager )
    deactivate_bonding_nmcli
    flush_all_nic_ip
    active_nic_nmcli
fi