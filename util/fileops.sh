#!/bin/bash 

UTIL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract_tar_files() {
    declare -A map
    local tar_gz_filepath=$1

    if [[ -z ${tar_gz_filepath} ]]; then
        error_exit "Cannot find '${tar_gz_filepath}'"
    fi

    log "Unzip ${tar_gz_filepath}... " >&2
    local extracted_files=($(tar -xvzf "${tar_gz_filepath}" -C "${UTIL_SCRIPT_DIR}/../resources"))

    for file in "${extracted_files[@]}"; do
        local key=$(echo "${file}" | cut -d '_' -f 1)
        map["${key}"]="$(realpath "${UTIL_SCRIPT_DIR}/../resources/${file}")"
    done

    map_to_json "map"
}

show_copy_progress() {
    # example ) show_copy_progress "/mnt" "/dvd" ( /mnt : src, /dvd : dst )
    local src_dir="$1"
    local dst_dir="$2"

    # 1. 전체 복사 대상 파일 수 계산 
    local total_files=$(find ${src_dir} -type f | wc -l)
    local count=0

    find ${src_dir} -type f | while read -r file; do
        # copy ( 상대 경로에 따른 하위 디렉터리 생성 )
        rel_path="${file#$src_dir/}"  
        mkdir -p "${dst_dir}/$(dirname "${rel_path}")"
        cp "${file}" "${dst_dir}/${rel_path}"

        # counting 
        ((count++))
        percent=$((100 * count / total_files))
        printf "\rProgress: %d%% (%d / %d)" "${percent}" "${count}" "${total_files}"
    done

    log "Copying Complete !" 
}