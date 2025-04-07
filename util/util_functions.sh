#!/bin/bash

# ========================== Logging ==========================

log() {
    echo -e "[INFO] $1"
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
    local target_file="$1"
    declare -gA map
    unset map

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