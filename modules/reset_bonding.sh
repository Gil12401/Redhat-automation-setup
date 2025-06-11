#!/bin/bash
# ======================= [ Environment Setup ] ==========================

# IFS Backup
PRE_IFS=${IFS}

# Directory Path 
SCRIPT_DIR="$(dirname "$(realpath "$0")")"  # SCRIPT_DIR path : .../redhat-automation/modules
UTIL_DIR="${SCRIPT_DIR}/../util"
RESOURCES_DIR="${SCRIPT_DIR}/../resources"

# util functions
source "${UTIL_DIR}/util_loader.sh"

# required resources
bonding_reset_tar=$(find "${RESOURCES_DIR}" -name "bonding_reset.tar.gz" 2> /dev/null )

# 공통 : /etc/sysconfig/network-scripts/ 하위 
target_path="/etc/sysconfig/network-scripts"

# ======================= [ Function Definitions ] ==========================

# Redhat old version (6, 7) - ifcfg (config file)
extract_reset_files() {
    declare -A reset_files_map

    if [[ -z ${bonding_reset_tar} ]]; then
        error_exit "Cannot find a 'bonding_reset.tar.gz'"
    fi

    log "Unzip bonding_reset.tar.gz..." >&2
    extracted_reset_files=($(tar -xvzf "${bonding_reset_tar}" -C "${RESOURCES_DIR}"))

    # ex: "nic_up" -> ifcfg-nic_up, "nic_down" -> ifcfg-nic_down
    for file in "${extracted_reset_files[@]}"; do
        key=$(echo "${file}" | cut -d '-' -f 2 | xargs)  
        reset_files_map["${key}"]="${file}"
    done

    map_to_json "reset_files_map"
}

select_enable_nic() {
    # ex. nic_map["eth0"]="up" /  nic_map["eth1"]="down" /  nic_map["eth2"]="down"
    declare -A enable_nic_map
    local cursor=0
    local pci_keys="name addr vendor device"

    IFS=$'\n'
    local nic_rows=($(ip addr show | grep "<[^>]*>" | grep -v -E "LOOPBACK|MASTER"))
    IFS=${PRE_IFS}
   
    for nic in "${nic_rows[@]}"; do
        local nic_name=$(echo "${nic}" | cut -d " " -f 2 | tr -d ":")
        local pci_json=$(get_pci_map_from_nic "${nic_name}")
        options+=("${pci_json}")
    done

    while :; do
        draw_table_menu "${cursor}" "Select an NIC for Activating after reset bonding ( ifup )" "${pci_keys}" "${options[@]}" >&2
        key=$(read_key)

         case "${key}" in
            $'\x1b[A') cursor=$((cursor - 1)); [[ ${cursor} -lt 0 ]] && cursor=$((${#options[@]} - 1)) ;;
            $'\x1b[B') cursor=$((cursor + 1)); [[ ${cursor} -ge ${#options[@]} ]] && cursor=0 ;;

            "")
                # nic_map["eth0"]="up" /  nic_map["eth1"]="down" /  nic_map["eth2"]="down"
                local selected_element="${options[${cursor}]}"
                local selected_nic=$(echo ${selected_element} | jq -r '.name')    
                local options_length=${#options[@]}
                           
                for ((i=0; i<options_length; i++)); do
                    nic_name=$(echo ${options[${i}]} | jq -r '.name')    
                    enable_nic_map[${nic_name}]="down" 
                done                

                active_nic="${selected_nic}"
                enable_nic_map[${selected_nic}]="up"
            break
            ;;
        esac
    done

    map_to_json "enable_nic_map"
}

# bonding 관련 ifcfg 파일 삭제 
remove_bonding_ifcfg() {
    local prefix="ifcfg-"

    IFS=$'\n'
    local member_rows=($(ip addr show | grep "<[^>]*>" | grep  -E "MASTER|SLAVE"))
    IFS=${PRE_IFS}

    # ifcfg-bond0 / ifcfg-slave1 / ifcfg-slave2 삭제 
    # member : ex. eth0 / eth2 / bond0
    
    for member in "${member_rows[@]}"; do
        local member=$(echo "${member}" | cut -d " " -f 2 | tr -d ":")
        local ifcfg_file="${prefix}${member}"

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

        # 1. bonding dev down
        ip link set "${bonding_dev}" down

        # 2. delete bonding dev
        ip link delete "${bonding_dev}" type bond && log "${bonding_dev} deleted complete."
    else
        log "${bonding_dev} does not exist. Skip this phase."
    fi

    # 3. unload bonding module from kernel 
    if lsmod | grep -q '^bonding'; then
        log "Trying to unload a bonding kernel module..."
        modprobe -r bonding && log "bonding module is unloaded succesfully."
    else
        log "bonding module is already unloaded."
    fi
}

read_nic_network_info() {

    declare -A nic_network_map

    while :; do
        eprint ""
        eprint "==========================================================="
        eprint "   Wrtie an IP Address to assign for enabled NIC   "
        eprint "   (Can write at first Step (IP Addr) if input 'r' or 'R')   "
        eprint "==========================================================="
        eprint "IPADDR: "
        read -r ip_addr

        [[ "${ip_addr}" == "r" || "${ip_addr}" == "R" ]] && continue
        [[ -z "${ip_addr}" ]] && ip_addr="192.168.211.20"
        nic_network_map["IPADDR"]=${ip_addr}

        eprint "==========================================================="
        eprint "   Netmask (example - 255.255.255.0)   "
        eprint "   (Can write at first Step (IP Addr) if input 'r' or 'R')   "
        eprint "==========================================================="
        eprint "NETMASK: "
        read -r netmask
        
        [[ "${netmask}" == "r" || "${netmask}" == "R" ]] && continue
        [[ -z "${netmask}" ]] && netmask="255.255.0.0"
        nic_network_map["NETMASK"]=${netmask}
        nic_network_map["PREFIX"]=$(get_prefix_from_subnet "${netmask}")

        eprint "==========================================================="
        eprint "   Gateway                            "
        eprint "   (Can write at first Step (IP Addr) if input 'r' or 'R')   "
        eprint "==========================================================="
        eprint "GATEWAY: " 
        read -r gateway
      
        [[ "${gateway}" == "r" || "${gateway}" == "R" ]] && continue
        [[ -z "${gateway}" ]] && gateway="192.168.222.1"
        nic_network_map["GATEWAY"]=${gateway}

        eprint "==========================================================="
        eprint "   DNS Server IP                         "
        eprint "   (Can write at first Step (IP Addr) if input 'r' or 'R')   "
        eprint "==========================================================="
        eprint "DNS1 [if the input is empty, it will be filled with 8.8.8.8]: "
        read -r dns1
        
        [[ "${dns1}" == "r" || "${dns1}" == "R" ]] && continue
        [[ -z "${dns1}" ]] && dns1="8.8.8.8"
        nic_network_map["DNS1"]=${dns1}
        break
    done

    map_to_json "nic_network_map"
}

generate_nic_ifcfg() {
    local reset_files_json=$1
    local enable_nic_json=$2
    nic_network_json=$(read_nic_network_info)

    local nic_up_file=$(echo "${reset_files_json}" | jq -r '.nic_up')
    local nic_down_file=$(echo "${reset_files_json}" | jq -r '.nic_down')

    IFS=$'\n'
    local nic_enable_keys=()
    local nic_enable_rows=$(ip addr show | grep "<[^>]*>" | grep -v -E "LOOPBACK|MASTER")
    IFS=${PRE_IFS}

    for row in "${nic_enable_rows[@]}"; do
        local nic_enable_key=$(echo "${row}" | cut -d " " -f 2 | tr -d ":")
        nic_enable_keys+=(${nic_enable_key})
    done

    local nic_network_keys=("NETMASK" "PREFIX" "GATEWAY" "IPADDR" "DNS1")

    declare -A enable_nic_map
    declare -A nic_network_map

    json_to_map "${enable_nic_json}" "enable_nic_map" "${nic_enable_keys[@]}"
    json_to_map "${nic_network_json}" "nic_network_map" "${nic_network_keys[@]}"

    for nic in "${!enable_nic_map[@]}"; do
        local state=${enable_nic_map[${nic}]}
        # log "nic : ${nic}"
        # log "state : ${nic_map[${nic}]}"

        local output_file="${target_path}/ifcfg-${nic}"
        local reset_file=""

        # Make ${output_file} empty
        > "${output_file}"

        log "Create ${output_file}... " 

        case "${state}" in
            up)
                # reset_file="${RESOURCES_DIR}/${reset_file_map["nic_up"]}"
                reset_file="${RESOURCES_DIR}/${nic_up_file}"
                ;;

            down)
                # reset_file="${RESOURCES_DIR}/${reset_file_map["nic_down"]}"
                reset_file="${RESOURCES_DIR}/${nic_down_file}"
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
                echo "${key}=${nic_network_map[${key}]}" >> "${output_file}"
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

    for nic in "${bonding_members[@]}"; do
        nmcli con del "${nic}"
    done
}

active_nic_nmcli() {
    local active_nic=$1
    mapfile -t nics < <(ls /sys/class/net | grep -v '^lo$')

    local nic_network_keys=("NETMASK" "PREFIX" "GATEWAY" "IPADDR" "DNS1")
    declare -A nic_network_map
    nic_network_json=$(read_nic_network_info)
    json_to_map "${nic_network_json}" "nic_network_map" "${nic_network_keys[@]}"

    # regenerate all NIC conns without Bonding 
    for nic in "${nics[@]}"; do
        nmcli con delete ${nic} 2>/dev/null || true
        nmcli con add type ethernet ifname ${nic} con-name ${nic}

        conn_name=$(nmcli -t -f NAME,DEVICE con show | grep ":${nic}$" | cut -d':' -f1)

        if [[ "${nic}" == "${active_nic}" ]]; then
            log "activate : ${conn_name} (${nic})"
            nmcli con modify "${conn_name}" \
            ipv4.addresses "${nic_network_map["IPADDR"]}/${nic_network_map["PREFIX"]}" \
            ipv4.gateway "${nic_network_map["GATEWAY"]}" \
            ipv4.dns "${nic_network_map["DNS1"]}" \
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

# ======================= [ Main Logic ] ==============================================

# nic_map["ethX"]="up" -> active_nic 
enable_nic_json=$(select_enable_nic)
active_nic=$(jq -r 'to_entries[] | select(.value == "up") | .key' <<< "${enable_nic_json}")

version_id=$(get_os_version)

if [[ ${version_id} -le 7 ]]; then
    # RHEL7 버전 이하 : ifcfg 설정 파일 ( NetworkManager OFF )

    reset_files_json=$(extract_reset_files)
    remove_bonding_ifcfg
    deactivate_bonding_interface
    generate_nic_ifcfg "${reset_files_json}" "${enable_nic_json}"
    flush_all_nic_ip
    rm -rv $(echo "${RESOURCES_DIR}/ifcfg-*")

    log "network restart."
    systemctl restart network 
else
    # RHEL8 버전 이상 : nmtui or nmcli ( NetworkManager )
    deactivate_bonding_nmcli
    flush_all_nic_ip
    active_nic_nmcli "${active_nic}"
fi

ip addr show
