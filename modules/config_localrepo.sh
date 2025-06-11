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
local_repo_tar=$(find "${RESOURCES_DIR}" -name "local_repo.tar.gz" 2> /dev/null)

# ======================= [ Function Definitions ] ==========================
extract_local_repo_files() {
    declare -A local_repo_map

    if [[ -z ${local_repo_tar} ]]; then
        error_exit "Cannot find a file 'local_repo.tar.gz'"
    fi

    log "Unzip local_repo.tar.gz... " >&2
    local extracted_files=($(tar -xvzf "${local_repo_tar}" -C "${RESOURCES_DIR}"))

    # TODO ) "centOS7" -> "old_Version" "centOS8" -> "new_Version" 
    
    # "centOS7" -> centOS7_local.repo, "centOS8" -> centOS8_local.repo
    for file in "${extracted_files[@]}"; do
        local key=$(echo "${file}" | cut -d '_' -f 1)
        local_repo_map["${key}"]="$(realpath "${RESOURCES_DIR}/${file}")"
    done

    map_to_json "local_repo_map"
}

select_repo_file() {
    declare -A local_repo_map 

    local version_id="$1"
    local local_repo_json="$2"
    local json_keys=($(echo "${local_repo_json}" | jq -r 'keys[]'))

    json_to_map "${local_repo_json}" "local_repo_map" "${json_keys[@]}"

    if [[ ${version_id} -le 7 ]]; then
        echo "${local_repo_map["centOS7"]}"
    else
        echo "${local_repo_map["centOS8"]}"
    fi
}

select_iso_device() {
    declare -A device_map

    local options=() 
    local cursor=0

    log "Search type of iso9660 File System ( CD-ROM )"
    local mount_point="/mnt"
    local selected_dev=""

    mapfile -t found_devices < <(blkid | grep 'iso9660' | cut -d: -f1)

    if [[ ${#found_devices[@]} -eq 0 ]]; then
        echo "[ERROR] Couldn't find a device, type iso9660."
        exit 1
    fi

    for dev in "${found_devices[@]}"; do
        umount "${mount_point}" &>/dev/null
        mount "${dev}" "${mount_point}" &>/dev/null
        local ret=$?

        if [[ ${ret} -eq 0 ]]; then
            if [[ -f "${mount_point}/.treeinfo" ]]; then
                name=$(sed -n "/^\[general\]/,/^\[/p" "${mount_point}/.treeinfo" \
                      | sed "1d;/^\[/q" | grep name | cut -d "=" -f 2 | xargs)
                device_map["dev"]="${dev}"
                device_map["name"]="${name}"
                options+=("$(map_to_json device_map)")
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

    local key_order="dev name"
    while true; do 
        draw_table_menu "${cursor}" "Select a device for mounting at /mnt" "${key_order}" "${options[@]}"

        key=$(read_key)

        case "${key}" in
            $'\x1b[A') cursor=$((cursor - 1)); [[ ${cursor} -lt 0 ]] && cursor=$((${#options[@]} -1)) ;;
            $'\x1b[B') cursor=$((cursor + 1)); [[ ${cursor} -ge ${#options[@]} ]] && cursor=0 ;;

            "") 
            selected_dev=$(echo "${options[${cursor}]}" | jq -r '.dev')
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

copy_mounted_files() {
    read -p "Write the name of Directory for copying from /mnt: " dirname
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

build_baseurl_map() {
    declare -A baseurl_map
    local value_tails=$(find "$1" -type d -name "Packages")

    for value_tail in ${value_tails}; do
        local key=""
        local value_tail=$(echo "${value_tail}" | sed "s/Packages.*//")

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
        
        # ex ) "AppStream": "/dvd/AppStream/"
        baseurl_map["${key}"]="${value_tail}"
    done

    map_to_json "baseurl_map"
}

generate_local_repo() {
    local repo_template="$1"
    local baseurl_json="$2"
    local tmp_file="/tmp/tmp_local.repo"
    touch "${tmp_file}"
    chmod 777 "${tmp_file}"

    baseurl_json=$(jq 'with_entries(.value |= "baseurl=file://" + .)' <<< ${baseurl_json})
   
    local cur_key=""
    while IFS= read -r line; do
        if [[ "${line}" =~ ^\[.*\]$ ]]; then
            cur_key=$(echo "${line}" | cut -d "-" -f 2 | tr -d "[-]")
            log "Current section ( Key ) : ${cur_key}"
        fi

        [[ "${line}" == *baseurl* ]] && \
            line=$(jq -r --arg k "${cur_key}" '.[$k]' <<< "${baseurl_json}") 
        
        echo "${line}" >> "${tmp_file}"

    done < "${repo_template}"

    cp -f "${tmp_file}" /etc/yum.repos.d/local.repo
    rm -f "${tmp_file}"
}

# ======================= [ Main Logic ] ==========================
log "Local Repository Automation Setup..."

local_repo_json=$(extract_local_repo_files)
version_id=$(get_os_version)
log "Current OS Version: $(cat /etc/redhat-release)"

local_repo_file=$(select_repo_file "${version_id}" "${local_repo_json}")
[[ -z "${local_repo_file}" ]] && error_exit "Cannot find any proper local_repo file."
[[ ! -f "${local_repo_file}" ]] && error_exit "${local_repo_file} does not exist."

log "local_repo_file : ${local_repo_file}"

select_iso_device
copy_mounted_files
backup_repo_files
baseurl_json=$(build_baseurl_map "${dirpath}" "${local_repo_file}")
generate_local_repo "${local_repo_file}" "${baseurl_json}"

rm -rv $(echo "${RESOURCES_DIR}/centOS*")

echo "====================== Repolist Result ============================="
yum repolist