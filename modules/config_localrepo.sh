#!/bin/bash

#IFS Backup 
PRE_IFS=${IFS}

# Directory Path 
SCRIPT_DIR="$(dirname "$(realpath "$0")")" # SCRIPT_DIR path : .../init-setup/modules
UTIL_DIR="${SCRIPT_DIR}/../util"
RESOURCES_DIR="${SCRIPT_DIR}/../resources"

# util functions
source "${UTIL_DIR}/util_functions.sh"

# required resources
local_repo_tar=$(find "${RESOURCES_DIR}" -name "local_repo.tar.gz" 2> /dev/null )

select_iso_device_handler() {
    local option=$1
    local ref_name=$2
    local parsed_name

    parsed_name=$(echo "${option}" | cut -d '|' -f 1 | xargs)

      eval "$ref_name=\"\$parsed_name\""
}

# -------------------------- Extract local_repo.tar.gz --------------------------
extract_local_repo_files() {
    declare -gA local_repo_map

    if [[ -z ${local_repo_tar} ]]; then
        error_exit "Cannot find 'local_repo.tar.gz'"
    fi

    log "Unzip local_repo.tar.gz..."
    local extracted_files=($(tar -xvzf "${local_repo_tar}" -C "${RESOURCES_DIR}"))

    for value in "${extracted_files[@]}"; do
        local key=$(echo "${value}" | cut -d '_' -f 1)
        local_repo_map["${key}"]="$(realpath "${RESOURCES_DIR}/${value}")"
    done
}

select_repo_file() {
    local version_id="$1"
    if [[ ${version_id} -le 7 ]]; then
        echo "${local_repo_map["centOS7"]}"
    else
        echo "${local_repo_map["centOS8"]}"
    fi
}

# -------------------------- ISO 장치 선택 --------------------------
select_iso_device() {
    declare -gA device_map

    # /dev/sr1 | LoremIpsum : DUMMY option
    local options=() 
    local cursor=0

    log "Search type of iso9660 Filesystem ( CD-ROM )"
    local mount_point="/mnt"
    local selected_dev=""

    mapfile -t found_devices < <(blkid | grep 'iso9660' | cut -d: -f1)

    if [[ ${#found_devices[@]} -eq 0 ]]; then
        echo "[ERROR] Couldn't find a device, type iso9660."
        exit 1
    fi

    for dev in "${found_devices[@]}"; do
        # echo "[DEBUG] Trying mount a device: ${dev}"
        umount "${mount_point}" &>/dev/null
        mount "${dev}" "${mount_point}" &>/dev/null
        local ret=$?

        if [[ ${ret} -eq 0 ]]; then
            if [[ -f "${mount_point}/.treeinfo" ]]; then
                name=$(sed -n "/^\[general\]/,/^\[/p" "${mount_point}/.treeinfo" \
                      | sed "1d;/^\[/q" | grep name | cut -d "=" -f 2 | xargs)
                options+=("${dev} | ${name}")
                # shellcheck disable=SC2034
                device_map["${dev}"]="${name}"
            else
                echo "[DEBUG]'.treeinfo' does not exist in this dev"
            fi
        else
            echo "[DEBUG] -> Mount Failed: ${dev}"
        fi

        umount "${mount_point}" &>/dev/null
    done

    if [[ ${#options[@]} -eq 0 ]]; then
        echo "[ERROR] Cannot find an iso device has '.treeinfo'."
        exit 1
    fi

    while true; do 
        draw_menu "${cursor}" "Select a device for mounting at /mnt" "${options[@]}"

        read -rsn1 key
        if [[ ${key} == $'\x1b' ]]; then 
            read -rsn2 -t 0.1 key2
            key+="${key2}"
        fi 

        case "${key}" in
            $'\x1b[A') cursor=$((cursor - 1)); [[ ${cursor} -lt 0 ]] && cursor=$((${#options[@]} -1)) ;;
            $'\x1b[B') cursor=$((cursor + 1)); [[ ${cursor} -ge ${#options[@]} ]] && cursor=0 ;;

            "") 
            # log "Selected Device : ${options[${cursor}]}"
            select_iso_device_handler "${options[${cursor}]}" selected_dev
            break 
            ;;
        esac
    done

    log "Selected Device: ${selected_dev}"
    umount "${mount_point}" &>/dev/null
    # || echo "[DEBUG] dev is not mounted yet."
    mount | grep "${selected_dev}" 
    mount "${selected_dev}" "${mount_point}"
    ret=$?

    if [[ ${ret} -eq 0 ]]; then
        true
    else
        error_exit "${selected_dev} Mount Failed. (exit code: ${ret})"
    fi

    log "${selected_dev} is mounted at ${mount_point}."
}

# -------------------------- 디렉토리 복사 --------------------------
copy_mounted_files() {
    read -p "Write the name of Directory for copying to /mnt: " dirname
    dirpath="/${dirname}"

    log "Create ${dirpath}, Copying contents from /mnt."
    mkdir -p "${dirpath}"

    # if [[ -n $(yum list installed | grep 'rsync') ]]
    if command -v rsync >/dev/null 2>&1; then
        rsync -ah --info=progress2 /mnt/ "${dirpath}/" || error_exit "Failed Copy."
    else
        show_copy_progress "/mnt" "${dirpath}"
    fi 
}

# -------------------------- .repo 백업 --------------------------
backup_repo_files() {
    log "Backup all files under /etc/yum.repos.d/... ( /etc/yum.repos.d/bak) "
    cd /etc/yum.repos.d/
    mkdir -p bak

    shopt -s nullglob
    local repo_files=(*.repo)
    if [[ ${#repo_files[@]} -gt 0 ]]; then
        mv "${repo_files[@]}" bak/
    else
        log ".repo file does not exist"
    fi
    shopt -u nullglob
}

# -------------------------- baseurl 경로 설정 --------------------------
build_baseurl_map() {
    declare -gA baseurl_map
    local value_head="file://"
    local value_tails=$(find "$1" -type d -name "Packages")

    for value_tail in ${value_tails}; do
        local key=""
        local value_tail=$(echo "${value_tail}" | sed "s/Packages.*//")
        local value="baseurl=${value_head}${value_tail}"

        local IFS="/"
        for word in ${value_tail}; do
            [[ ${word} == "Packages" ]] && break
            key="${word}"
        done
        IFS=${PRE_IFS}

        if [[ "${key}" != *"AppStream"* && "${key}" != *"BaseOS"* ]]; then
            section=$(grep "^\[.*\]$" "$2")
            key=$(echo "${section}" | cut -d "-" -f 2 | tr -d "[-]")
        fi

        baseurl_map["${key}"]="${value}"
    done
}

# -------------------------- local.repo 생성 --------------------------
generate_local_repo() {
    local repo_template="$1"
    local tmp_file="/tmp/tmp_local.repo"
    touch "${tmp_file}"
    chmod 777 "${tmp_file}"

    local cur_key=""
    while IFS= read -r line; do
        if [[ "${line}" =~ ^\[.*\]$ ]]; then
            cur_key=$(echo "${line}" | cut -d "-" -f 2 | tr -d "[-]")
            log "Current section ( Key ) : ${cur_key}"
        fi

        if [[ "${line}" == *baseurl* ]]; then
            echo "${baseurl_map[${cur_key}]}" >> "${tmp_file}"
        else
            echo "${line}" >> "${tmp_file}"
        fi
    done < "${repo_template}"

    cp -f "${tmp_file}" /etc/yum.repos.d/local.repo
    rm -f "${tmp_file}"
}

# -------------------------- Main --------------------------
log "Local Repository Automation Setup..."

extract_local_repo_files
version_id=$(get_os_version)
log "Current OS Version: $(cat /etc/redhat-release)"

local_repo_file=$(select_repo_file "${version_id}")
[[ -z "${local_repo_file}" ]] && error_exit "Cannot find any proper local_repo file."
[[ ! -f "${local_repo_file}" ]] && error_exit "${local_repo_file} does not exist."
sleep 1

select_iso_device
copy_mounted_files
backup_repo_files
build_baseurl_map "${dirpath}" "${local_repo_file}"
generate_local_repo "${local_repo_file}"

rm -rv $(echo "${RESOURCES_DIR}/centOS*")

log "yum repolist Result:"
yum repolist