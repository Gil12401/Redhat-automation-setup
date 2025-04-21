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
        error_exit "Cannot find a 'bonding_reset.tar.gz'"
    fi

    log "Unzip bonding_reset.tar.gz..."
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
        draw_menu "${cursor}" "Select an NIC for enable after reset bonding ( up )" "${options[@]}"

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
            log "${target_path}/${ifcfg_file} does not exist."
        fi
    done
}

deactivate_bonding_interface() {
    local bonding_dev="bond0"

    if ip link show "${bonding_dev}" &> /dev/null; then
        log "${bonding_dev} still exists. Trying to delete now."

        # 1. bonding 장치 down
        ip link set "${bonding_dev}" down

        # 2. bonding 장치 삭제
        ip link delete "${bonding_dev}" type bond && log "${bonding_dev} deleted complete."
    else
        log "${bonding_dev} does not exist. Skip this phase."
    fi

    # 3. 커널에서 bonding 모듈 언로드
    if lsmod | grep -q '^bonding'; then
        log "Trying to unload a bonding kernel module..."
        modprobe -r bonding && log "bonding module is unloaded succesfully."
    else
        log "bonding module is already unloaded."
    fi
}

read_nic_ip_info() {

    declare -gA nic_info_map
    declare -g ip_addr
    declare -g netmask
    declare -g gateway
    declare -g dns1

    while :; do
        echo "==================================================="
        echo "   Wrtie an IP Address to assign for enabled NIC   "
        echo "   (Can write from first (IP Addr) if input 'r' or 'R')   "
        echo "==================================================="
        read -rp "IPADDR: " ip_addr

        [[ "${ip_addr}" == "r" || "${ip_addr}" == "R" ]] && continue
        [[ -z "${ip_addr}" ]] && ip_addr="192.168.211.20"
        nic_info_map["IPADDR"]=${ip_addr}

         echo "==================================================="
        echo "   Netmask (example - 255.255.255.0)   "
        echo "   (Can write from first (IP Addr) if input 'r' or 'R')   "
         echo "==================================================="
        read -rp "NETMASK: " netmask
        
        [[ "${netmask}" == "r" || "${netmask}" == "R" ]] && continue
        [[ -z "${netmask}" ]] && netmask="255.255.0.0"
        nic_info_map["NETMASK"]=${netmask}
        nic_info_map["PREFIX"]=$(get_prefix_from_subnet "${netmask}")

        echo "==================================================="
        echo "   Gateway                            "
        echo "   (Can write from first (IP Addr) if input 'r' or 'R')   "
        echo "==================================================="
        read -rp "GATEWAY: " gateway
      
        [[ "${gateway}" == "r" || "${gateway}" == "R" ]] && continue
        [[ -z "${gateway}" ]] && gateway="192.168.222.1"
        nic_info_map["GATEWAY"]=${gateway}

        echo "==================================================="
        echo "   DNS Server IP                         "
        echo "   (Can write from first (IP Addr) if input 'r' or 'R')   "
         echo "==================================================="
        read -rp "DNS1 [if the input is empty, it will be filled with 8.8.8.8]: " dns1
        
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

        log "Create ${output_file}... " 

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
            log "bond0 : nmcli con down complete !" 
            break
        else
            log "func <wait_until_nmcli_con_down> not yet, Sleep 1sec."
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

active_nic_nmcli() {

    # NIC list
    mapfile -t nics < <(ls /sys/class/net | grep -v '^lo$')

    read_nic_ip_info

    # regenerate all NIC conns without Bonding 
    for nic in "${nics[@]}"; do
        nmcli con delete ${nic} 2>/dev/null || true
        nmcli con add type ethernet ifname ${nic} con-name ${nic}

        conn_name=$(nmcli -t -f NAME,DEVICE con show | grep ":${nic}$" | cut -d':' -f1)

        if [[ "${nic}" == "${active_nic}" ]]; then
            log "activate : ${conn_name} (${nic})"
            nmcli con modify "${conn_name}" \
            ipv4.addresses "${nic_info_map["IPADDR"]}/${nic_info_map["PREFIX"]}" \
            ipv4.gateway "${nic_info_map["GATEWAY"]}" \
            ipv4.dns "${nic_info_map["DNS1"]}" \
            ipv4.method manual \
            connection.autoconnect yes
            nmcli con up "${conn_name}"
        else 
            log "deactivate : ${conn_name} (${nic})"
            nmcli con modify "${conn_name}" connection.autoconnect no
            nmcli con down "${conn_name}"
        fi
    done
}

# -------------------------- Main --------------------------

# active_nic, nic_map["ethX"]="up" 결정
select_enable_nic   

version_id=$(get_os_version)

if [[ ${version_id} -le 7 ]]; then
    # RHEL7 버전 이하 : ifcfg 설저파일 ( NetworkManager OFF )
    extract_reset_files
    remove_bonding_ifcfg
    deactivate_bonding_interface
    generate_nic_ifcfg
    flush_all_nic_ip

    log "network restart."
    systemctl restart network 

    ip addr show
else
    # RHEL8 버전 이상 : nmtui or nmcli ( NetworkManager )
    deactivate_bonding_nmcli
    flush_all_nic_ip
    active_nic_nmcli
fi

rm -rv $(echo "${RESOURCES_DIR}/ifcfg-*")