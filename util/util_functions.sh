#!/bin/bash

# ========================== Logging ==========================

log() {
    echo -e "[INFO $(date +'%F %T')] $1"
}

error_exit() {
    echo -e "[ERROR] $1"
    exit 1
}

# ========================== Drawing Menu ==========================

draw_menu() {
    local cursor=$1
    local menu_name=$2

    shift 2  # $3부터 하나의 배열로 간주. 
    local options=("$@")  # 배열 복사. 배열 내 값을 변경할 필요도 없음. 
    local options_length=${#options[@]}

    clear
    echo "=========== ${menu_name} ==========="
    for ((i=0; i<options_length; i++)); do
        if [[ "$i" -eq "$cursor" ]]; then
            echo -e " → \033[1;36m${options[$i]}\033[0m"
        else
            echo "   ${options[$i]}"
        fi
    done
}

# ========================== Get Bash Version ==========================
get_bash_major() {
    major="${BASH_VERSINFO[0]}"
}

get_bash_minor() {
    minor="${BASH_VERSINFO[1]}"
}

# ========================== Parsing ==========================

# 첫번째 argument ( $1 ) 의 결과 ( 특정파일에 대한 cat명령어 ) 를 key-value 연관 배열에 담음.
# 파일을 한줄씩 읽어들이면서 key-value 연관 배열에 담음

parse_kv_file() {
    unset map
    local target_file="$1"
    declare -gA map
   
    # 키=값 형식의 라인들만 필터링
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
    parse_kv_file /etc/os-release || error_exit "버전 정보 로드 실패"
    version_id=$(printf "%.0f" "${map["VERSION_ID"]}")
    echo "${version_id}"
}

# =============================== Array ================================

# 배열에서 특정 값을 제거하는 함수 (원본 배열 직접 수정)
# 사용법: remove_from_array_inplace "배열이름" "제거할_값"
remove_from_array_inplace() {
    local arr_name="$1"
    local target="$2"
    local result=()

    eval "local original=(\"\${${arr_name}[@]}\")"

    for item in "${original[@]}"; do
        if [[ "$item" != "$target" ]]; then
            result+=("$item")
        fi
    done

    eval "${arr_name}=(\"\${result[@]}\")"
}

# usage: sort_version_array array[@]
# 배열 안의 문자열을 버전식 오름차순 정렬 (예: ens1 < ens10 < ens100)
sort_version_array() {
    local input=("${!1}")
    local sorted=($(printf "%s\n" "${input[@]}" | sort -V))
    echo "${sorted[@]}"
}

#==================== Bonding ===============================
flush_all_nic_ip() {
    local nics=($(ls /sys/class/net | grep -v '^lo$'))

    for nic in "${nics[@]}"; do
        ip addr flush dev "$nic"
        log "IP flushed: $nic"
    done
}

dec2bin() {
    local dec=$1
    echo "obase=2; ${dec}" | bc
}

get_prefix_from_subnet() {
    PRE_IFS=${IFS}

    local prefix_num=0
    local subnet=$1
    IFS="." read -r -a subnet_array <<< "${subnet}"
    IFS=${PRE_IFS}

    for octet in "${subnet_array[@]}"; do
        local bin_num=$(dec2bin "${octet}")
        bin_num_arr=($(echo "${bin_num}" | grep -o .))

        for bit in "${bin_num_arr[@]}"; do
            if [[ ${bit} -eq 1 ]]; then
                ((prefix_num++))
            fi
        done

    done

    echo "${prefix_num}"
}