#!/bin/bash

# Static variables 
readonly HEX='[0-9a-f]'
readonly NUM='[0-9]'
readonly PCI_REGEX="^${HEX}{4}:${HEX}{2}:${HEX}{2}\.${NUM}$"
readonly PCI_SHORT_REGEX="${HEX}{2}:${HEX}{2}\.${NUM}$"
readonly VENDOR_DEVICE_REGEX='\[[0-9a-f]{4}:[0-9a-f]{4}\]'

# JSON Format <-> MAP ( Assosiative array )
# map_to_json() {
#     local -n map=$1
#     for key in "${!map[@]}"; do
#         printf '%s=%s\n' "${key}" "${map[${key}]}"
#     done | jq -Rn '
#          [inputs | split("=")] |
#          map({(.[0]): .[1]}) | 
#          add
#     '
# }

map_to_json() {
    local map_name="$1"
    declare -A map

    # eval로 외부 배열의 값을 local map 배열에 복사
    eval "for key in \"\${!${map_name}[@]}\"; do
        map[\"\$key\"]=\"\${${map_name}[\$key]}\"
    done"

    # 이후는 기존 방식 그대로 사용
    for key in "${!map[@]}"; do
        printf '%s=%s\n' "${key}" "${map[$key]}"
    done | jq -Rn '
        [inputs | split("=")] |
        map({(.[0]): .[1]}) |
        add
    '
}

json_to_map() {
    local json="$1"
    local map_name="$2"
    shift 2
    local json_keys=("$@")

    for key in "${json_keys[@]}"; do
        value=$(echo "${json}" | jq -r --arg k "${key}" '.[$k]')
        eval "$map_name[\"\$key\"]=\"\$value\""
    done
}

parse_kv_file() {
    unset map
    local target_file="$1"
    declare -gA map
   
    # kv -> key=value ( 키=값 ) 형식의 라인들만 필터링
    mapfile -t lines < <(grep '=' "${target_file}")

    for line in "${lines[@]}"; do
        # 빈 줄, 주석 제외
        [[ -z "${line}" || "${line}" == \#* ]] && continue

        IFS='=' read -r key value <<< "${line}"
        local value="${value//\"/}"  # 따옴표 제거
        # shellcheck disable=SC2034
        map["${key}"]="${value}"
    done
}

get_os_version() {
    parse_kv_file /etc/os-release || error_exit "Failed Loading an OS Version" # 버전 정보 로드 실패
    version_id=$(printf "%.0f" "${map["VERSION_ID"]}")
    echo "${version_id}"
}

get_pci_map_from_nic() {
    declare -A pci_map
    local nic=$1
    local pci_path=$(realpath /sys/class/net/${nic}/device)

    UTIL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PCI_IDS_PATH="${UTIL_SCRIPT_DIR}/../resources/pci.ids"
   
    IFS='/' read -ra pci_candidates <<< "${pci_path}"

    # /sys/devices/pci0000:00/0000:00:12.0/virtio1 
    # PCI 주소 형식만 Filtering ( 0000:00:12.0 )
    # Domain Part 제외 : 0000:00:12.0 -> 00:12.0
 
    # 1. 해당 PCI device 시스템 내 주소 
    for candidate in "${pci_candidates[@]}"; do
        if [[ ${candidate} =~ ${PCI_REGEX} ]]; then
            candidate=$(echo "${candidate}" | sed 's/^0000://')
            pci_map["addr"]=${candidate} 
            break
        fi
    done
    
    # 2. vendor_id:devicd_id 
    lspci_result=$(lspci -nn | grep "${pci_map["addr"]}")

    if [[ ${lspci_result} =~ ${VENDOR_DEVICE_REGEX} ]]; then
        vendor_device_id=${BASH_REMATCH[0]}
        vendor_device_id=$(echo "${vendor_device_id}" | tr -d "[]")
    fi

    # vendor_device_id=$(echo "${lspci_result}" | rev | cut -d " " -f 1 | rev | tr -d "[]")
    # echo "[DEBUG] vendor_device_id : ${vendor_device_id}"
    vendor_id=$(echo "${vendor_device_id}" | cut -d ":" -f 1)
    device_id=$(echo "${vendor_device_id}" | cut -d ":" -f 2)
    
    # Vendor Name & Device Name at pci.ids 
    # pci_map["vendor"] / pci_map["device"]
 
    read -r result < <(
        awk -v v_id="${vendor_id}" -v d_id="${device_id}" '
            BEGIN { vendor_found = 0 }

            # 1. Vendor Section 
            # Line의 시작이 들여쓰기 없이 Vendor ID 이면서 첫 필드가 Vendor ID
            $1 == v_id && $0 ~ ("^" v_id "[[:space:]]") {
                vendor_name = substr($0, index($0, $2));
                vendor_found = 1;
                next;
            }

            # Device line (1 indented with tab)
            vendor_found == 1 && d_id == $1 {
                # print "DEBUG: Line:", NR, " | $1:", $1, " | $0:", $0
                device_name = substr($0, index($0, $2));
                print vendor_name":"device_name;
                next;
            }

            # Next vendor Section, stop searching
            vendor_found == 1 && $0 ~ /^[0-9a-fA-F]{4}[[:space:]]/ {
                # print "Other Vendor section... Exit";
                exit;
            }
        ' "${PCI_IDS_PATH}"
    ) # read -r vendor_name device_name
    
    vendor_name=$(echo ${result} | cut -d ":" -f 1)
    device_name=$(echo ${result} | cut -d ":" -f 2)
    
    pci_map["name"]=${nic}
    pci_map["vendor"]=${vendor_name} 
    pci_map["device"]=${device_name} 
    
    map_to_json pci_map
}