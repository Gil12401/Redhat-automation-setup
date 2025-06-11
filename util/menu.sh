#!/bin/bash

read_key() {
    local k
    IFS= read -rsn1 k
    if [[ "$k" == $'\x1b' ]]; then
        local rest
        IFS= read -rsn1 -t 0.05 r1 && rest="$r1"
        IFS= read -rsn1 -t 0.05 r2 && rest="$rest$r2"
        k="$k$rest"
    fi
    echo "$k"
}

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
            echo -e "   ${options[$i]}"
        fi
    done
}

draw_table_menu() {
    local cursor=$1
    local menu_name=$2
    local key_order=$3
    shift 3

    local options=("$@")
    declare -A map
    IFS=' ' read -ra keys <<< "${key_order}"

    local output_buffer=""
    output_buffer+="=========== ${menu_name} ===========\n"

    for i in "${!options[@]}"; do
        declare -A map=()
        local json="${options[i]}"
        json_to_map "${json}" "map" "${keys[@]}"

        if [[ "${i}" -eq "${cursor}" ]]; then
            output_buffer+=" → \033[1;36m"
        else
            output_buffer+=""
        fi

        for key in "${keys[@]}"; do
            local value=${map[${key}]}
            output_buffer+="${key}: ${value}\n"
        done

        if [[ "${i}" -eq "${cursor}" ]]; then
            output_buffer+="\033[0m"
        fi

        output_buffer+="\n"
    done

    clear
    printf "%b" "${output_buffer}"
}

