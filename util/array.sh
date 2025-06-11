#!/bin/bash

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