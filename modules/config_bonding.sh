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
bondig_config_tar=$(find "${RESOURCES_DIR}" -name "bonding_config.tar.gz" 2> /dev/null )

# ======================= [ Function Definitions ] ==========================
select_bonding_members() {
    declare -A bonding_map

    IFS=$'\n'
    local nic_rows=($(ip addr show | grep "<[^>]*>" | grep -v -E "LOOPBACK|MASTER|SLAVE"))
    IFS=${PRE_IFS}
    
    local roles=("primary" "secondary")
    local options=()
    local cursor=0
    local pci_keys="name addr vendor device"

    for nic in "${nic_rows[@]}"; do
        local nic_name=$(echo "${nic}" | cut -d " " -f 2 | tr -d ":")
        local pci_json=$(get_pci_map_from_nic "${nic_name}")
        options+=("${pci_json}")
    done

    # Select Primary -> Secondary Slave for Bonding 
    local index=0
    while :; do
        [[ ${index} -eq ${#roles[@]} ]] && break
        
        local cur_role="${roles[${index}]}"
        draw_table_menu "${cursor}" "Select a Bonding Member : ${cur_role} (Back : ← )" "${pci_keys}" "${options[@]}" >&2
        key=$(read_key)
        
        case "${key}" in
            $'\x1b[A') cursor=$((cursor - 1)); [[ ${cursor} -lt 0 ]] && cursor=$((${#options[@]} - 1)) ;;
            $'\x1b[B') cursor=$((cursor + 1)); [[ ${cursor} -ge ${#options[@]} ]] && cursor=0 ;;
            # ← Key : Back to prev menu 
            $'\x1b[D')  
                if [[ ${index} -gt 0 ]]; then
                    ((index--))
                    nic_name="${bonding_map[${roles[${index}]}]}"
                    pci_json=$(get_pci_map_from_nic "${nic_name}")
                    options+=("${pci_json}")
                    unset bonding_map["${roles[${index}]}"]
                    cursor=0
                fi
            ;;

            "")
                # selected_nic : ens18, ens19 ...
                ((index++))
                local selected_element="${options[${cursor}]}"
                local selected_nic=$(echo ${selected_element} | jq -r '.name')
                remove_from_array_inplace "options" "${selected_element}"                
                bonding_map["${cur_role}"]="${selected_nic}"
                cursor=0
            ;;
        esac
    done

    map_to_json "bonding_map"
}

select_bonding_mode() {
    
    local bonding_json=$1
    local mode
    local mode_num
    local modes=("active-backup" "802.3ad" "alb")

    declare -A bonding_modes_map=(
        ["active-backup"]="1"
        ["802.3ad"]="4"
        ["alb"]="6"
    )

    local cursor=0
    while :; do
        draw_menu "${cursor}" "Select a Bonding Mode" "${modes[@]}" >&2
        echo "(active-backup - 1,  802.3ad - 4 (Todo), alb - 6 (Todo))" >&2
        key=$(read_key)
       
        case "${key}" in
            $'\x1b[A') cursor=$((cursor - 1)); [[ ${cursor} -lt 0 ]] && cursor=$((${#modes[@]} - 1)) ;;
            $'\x1b[B') cursor=$((cursor + 1)); [[ ${cursor} -ge ${#modes[@]} ]] && cursor=0 ;;
            "")
                mode="${modes[${cursor}]}"
                mode_num="${bonding_modes_map[${mode}]}"
                bonding_json=$(echo "${bonding_json}" | jq --arg key "mode" --arg value "${mode}" '. + {($key): $value}')
                bonding_json=$(echo "${bonding_json}" | jq --arg key "mode_num" --arg value "${mode_num}" '. + {($key): $value}')
                break
                ;;
        esac
    done
    echo "${bonding_json}"
}

read_bond_network_info() {

    declare -A bond_network_map

    while :; do
        eprint "" 
        eprint "===========================================================" 
        eprint "   Wrtie an IP Address to assign for Bond0   " 
        eprint "   (Can write at first Step (IP Addr) if input 'r' or 'R')   " 
        eprint "===========================================================" 
        eprint "IPADDR: " 
        read -r ip_addr
        # read -rp "IPADDR: " ip_addr
        
        [[ "${ip_addr}" == "r" || "${ip_addr}" == "R" ]] && continue
        [[ -z "${ip_addr}" ]] && ip_addr="192.168.211.20"
        bond_network_map["IPADDR"]=${ip_addr}

        eprint "===========================================================" 
        eprint "   Netmask (example - 255.255.255.0)   " 
        eprint "   (Can write at first Step (IP Addr) if input 'r' or 'R')   " 
        eprint "===========================================================" 
        # read -rp "NETMASK: " netmask
        eprint "NETMASK: " 
        read -r netmask
        
        [[ "${netmask}" == "r" || "${netmask}" == "R" ]] && continue
        [[ -z "${netmask}" ]] && netmask="255.255.0.0"
        bond_network_map["NETMASK"]=${netmask}

        eprint "===========================================================" 
        eprint "   Gateway                            " 
        eprint "   (Can write at first Step (IP Addr) if input 'r' or 'R')   " 
        eprint "===========================================================" 
        # read -rp "GATEWAY: " gateway
        eprint "GATEWAY: " 
        read -r gateway

        [[ "${gateway}" == "r" || "${gateway}" == "R" ]] && continue
        [[ -z "${gateway}" ]] && gateway="192.168.222.1"
        bond_network_map["GATEWAY"]=${gateway}

        eprint "===========================================================" 
        eprint "   DNS Server IP                             " 
        eprint "   (Can write at first Step (IP Addr) if input 'r' or 'R')   " 
        eprint "===========================================================" 
        eprint "DNS1 [if the input is empty, it will be filled with 8.8.8.8]: " 
        # read -rp "DNS1 [if the input is empty, it will be filled with 8.8.8.8]: " dns1
        read -r dns1
       
        [[ "${dns1}" == "r" || "${dns1}" == "R" ]] && continue
        [[ -z "${dns1}" ]] && dns1="8.8.8.8"
        bond_network_map["DNS1"]=${dns1}
        break
    done

    map_to_json "bond_network_map"
}

# Redhat Old version (6, 7) - ifcfg (config file)
extract_bonding_files() {
    declare -A bonding_files_map 

    if [[ -z ${bondig_config_tar} ]]; then
        error_exit "Cannot find a file 'bonding_config.tar.gz'"
    fi

    log "Unzip bonding_config.tar.gz... " >&2
    local extracted_bonding_files=($(tar -xvzf "${bondig_config_tar}" -C "${RESOURCES_DIR}"))

    # "master" -> ifcfg-master, "slave" -> ifcfg-slave
    for file in "${extracted_bonding_files[@]}"; do
        key=$(echo "${file}" | cut -d '-' -f 2 | xargs)  
        bonding_files_map["${key}"]="${file}"
    done

    map_to_json "bonding_files_map"
}

clean_ifcfg_files() {
    local path="/etc/sysconfig/network-scripts"
    local bonding_json=$1
    local bonding_json_keys=("primary" "secondary")

    declare -A bonding_map

    json_to_map "${bonding_json}" "bonding_map" "${bonding_json_keys[@]}"

    # bonding SLAVE NIC lists -> bonding_map["primary"] / bonding_map["secondary"]
    local bonding_nics=()
    for role in "${bonding_json_keys[@]}"; do
        bonding_nics+=("${bonding_map[${role}]}")
    done

    # /etc/sysconfig/network-scripts/ifcfg-* 
    for file in ${path}/ifcfg-*; do
        local filename=$(basename "${file}")
        local nic_name="${filename#ifcfg-}"

        # loopback 제외
        [[ "${nic_name}" == "lo" ]] && continue

        if [[ " ${bonding_nics[*]} " =~ " ${nic_name} " ]]; then
            log "Not Delete: ${file} (bonding member NIC)"
        else
            log "Delete: ${file} (Not a bonding member NIC)"
            rm -f "${file}"
        fi
    done
}

# "master" -> ifcfg-master, "slave" -> ifcfg-slave
generate_bonding_ifcfg_slaves() {
    local bonding_slave_file=$1
    local bonding_json=$2
    local bonding_json_keys=("primary" "secondary")

    declare -A bonding_map

    json_to_map "${bonding_json}" "bonding_map" "${bonding_json_keys[@]}"

    local template_path="${RESOURCES_DIR}/${bonding_slave_file}"
    local target_path="/etc/sysconfig/network-scripts"

    if [[ ! -f "${template_path}" ]]; then
        error_exit "Cannot find a template file ( Slave ): ${template_path}"
    fi

    for role in "${bonding_json_keys[@]}"; do
        local nic="${bonding_map[${role}]}"
        local output_file="${target_path}/ifcfg-${nic}"

        log "Create a bonding slave file : ${output_file}"

        # FIle Initializing ( Make empty state ) 
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

        log "Created ${output_file} Successfully."
        cat ${output_file}
    done
}

generate_bonding_ifcfg_master() {
    local bonding_master_file=$1
    local bonding_json=$2
    local bond_network_json=$3
    local bonding_json_keys=("primary" "secondary" "mode" "mode_num")
    local bond_network_keys=("NETMASK" "GATEWAY" "IPADDR" "DNS1")

    declare -A bonding_map
    declare -A bond_network_map

    json_to_map "${bonding_json}" "bonding_map" "${bonding_json_keys[@]}"
    json_to_map "${bond_network_json}" "bond_network_map" "${bond_network_keys[@]}"

    local template_path="${RESOURCES_DIR}/${bonding_master_file}"
    local target_path="/etc/sysconfig/network-scripts"

    if [[ ! -f "${template_path}" ]]; then
        error_exit "Cannot find a template file ( Master ): ${template_path}"
    fi

    local output_file="${target_path}/ifcfg-bond0"

    log "Create a bonding master file: ${output_file}"

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
                # echo "[DEBUG] ${key}=${bond_network_map[${key}]}"
                echo "${key}=${bond_network_map[${key}]}" >> "${output_file}"
                ;;

            # BONDING_OPTS="mode=1 miimon=100 use_carrier=0 primary=eth0"
            BONDING_OPTS)
                value=$(echo "${line}" | cut -d '=' -f2- | sed 's/^"//; s/"$//')
                value=$(echo "${value}" | sed "s/mode=[0-9]\+/mode=${bonding_map["mode_num"]}/")
                value=$(echo "${value}" | sed "s/primary=[a-zA-Z0-9]\+/primary=${bonding_map["primary"]}/")
                echo "${key}=\"${value}\"" >> "${output_file}"  # 다시 따옴표 감싸기
                ;;

            *)
                echo "${line}" >> "${output_file}"
                ;;
        esac
    done < "${template_path}"
    log "Created ${output_file} Successfully."
    cat ${output_file}
}

# -------------------------- RHEL 8버전 이상 - nmcli 설정 -------------------

configure_bonding_nmcli() {
    local bonding_json="$1" # primary secondary mode mode_num
    local bond_network_json="$2" # netmask gateway ipaddr dns1 
    local bonding_json_keys=("primary" "secondary" "mode" "mode_num")
    local bond_network_keys=("NETMASK" "GATEWAY" "IPADDR" "DNS1")

    declare -A bonding_map
    declare -A bond_network_map

    json_to_map "${bonding_json}" "bonding_map" "${bonding_json_keys[@]}"
    json_to_map "${bond_network_json}" "bond_network_map" "${bond_network_keys[@]}"

    # 1. NetworkManager 확인 및 활성화
    if ! systemctl is-active --quiet NetworkManager; then
        log "NetworkManager activate"
        systemctl enable --now NetworkManager
    fi

    # 2. bonding master 생성
    log "bonding master 생성: bond0 (mode=${bonding_map["mode"]})"
    nmcli connection add type bond ifname bond0 mode "${bonding_map["mode"]}" con-name bond0

    # 3. bonding 세부 옵션 설정
    nmcli connection modify bond0 +bond.options "miimon=100"
    nmcli connection modify bond0 +bond.options "primary=${bonding_map["primary"]}"
    nmcli connection modify bond0 connection.autoconnect-slaves 1

    # 4. slave NIC 연결
    local index=1
    for role in primary secondary; do
        local nic="${bonding_map[${role}]}"
        nmcli connection add type ethernet slave-type bond con-name "bond0-p${index}" ifname "${nic}" master bond0
        log "Completed SLave Connection: ${nic} → bond0-p${index}"
        ((index++))
    done
        
    # 5. prefix 변환 (netmask → CIDR)
    local ip="${bond_network_map["IPADDR"]}"
    local netmask="${bond_network_map["NETMASK"]}"
    local prefix=$(get_prefix_from_subnet "${netmask}")
    local gateway="${bond_network_map["GATEWAY"]}"
    local dns="${bond_network_map["DNS1"]}"

    log "input ip : ${ip}"
    log "input netmask : ${netmask}"
    log "input prefix : ${prefix}"
    log "input gateway : ${gateway}"
    log "input dns : ${dns}"

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
    sleep 3
    local bond_dev="bond0"
    local bond_info="/proc/net/bonding/${bond_dev}"

    if [[ -f "${bond_info}" ]]; then
        echo ""
        echo "==========================================="
        echo "     Result :  (${bond_dev})"
        echo "==========================================="
        cat "${bond_info}"
    else
        echo "[ERROR] Cannot find ${bond_info} File. Need to check a bonding config manually."
    fi
}

# ======================= [ Main Logic ] ==========================

# 1. NIC 선택
bonding_json=$(select_bonding_members)

# 2. Bonding mode 선택 
bonding_json=$(select_bonding_mode "${bonding_json}")

log "Primary : $(echo "${bonding_json}" | jq -r '.primary')"
log "Secondary : $(echo "${bonding_json}" | jq -r '.secondary')"
log "Bonding mode : $(echo "${bonding_json}" | jq -r '.mode')"
log "Bonding mode number : $(echo "${bonding_json}" | jq -r '.mode_num')"
sleep 2

# 3. Load Bonding module  ( Bonding 모듈 존재하지 않을 경우 )
bonding=$(echo $(lsmod | grep 'bonding'))
[[ ${#bonding[@]} -eq 0 ]] && modprobe --first-time bonding

version_id=$(get_os_version)
bond_network_json=$(read_bond_network_info)
flush_all_nic_ip

if [[ ${version_id} -le 7 ]]; then
    # RHEL7 버전 이하 : ifcfg 설정파일 ( NetworkManager OFF )
  
    systemctl stop NetworkManager
    
    bonding_files_json=$(extract_bonding_files)
    bonding_slave_file=$(echo "${bonding_files_json}" | jq -r '.slave')
    bonding_master_file=$(echo "${bonding_files_json}" | jq -r '.master')

    clean_ifcfg_files "${bonding_json}"
    generate_bonding_ifcfg_slaves "${bonding_slave_file}" "${bonding_json}"
    generate_bonding_ifcfg_master "${bonding_master_file}" "${bonding_json}" "${bond_network_json}"
  
    systemctl restart network
else
    # RHEL8 버전 이상 : NetworkManager ( nmtui or nmcli )
    configure_bonding_nmcli "${bonding_json}" "${bond_network_json}"
fi

rm -rv $(echo "${RESOURCES_DIR}/ifcfg-master")
rm -rv $(echo "${RESOURCES_DIR}/ifcfg-slave")

show_bonding_status