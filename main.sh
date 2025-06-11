#!/bin/bash 

# Directory Path 
main() {
    local SCRIPT_DIR="$(dirname "$(realpath "$0")")" # /redhat-automation 
    local UTIL_DIR="${SCRIPT_DIR}/util"
    local BIN_DIR="${SCRIPT_DIR}/bin"

    # util functions
    source "${UTIL_DIR}/util_loader.sh"

    # Menu Options 
    cursor=0
    options=(
        "Local Repository Setup"
        "Bonding Setup"
        "Bonding Reset"
        "Todo 2."
        "Todo 3."
        "Exit"
    )

    handlers=(
        "run_config_localrepo"
        "run_config_bonding"
        "run_reset_bonding"
        "run_task2"
        "run_task3"
        "run_exit"
    )

    run_config_localrepo() {
        bash "${SCRIPT_DIR}/modules/config_localrepo.sh"
    }

    run_config_bonding() {
        bash "${SCRIPT_DIR}/modules/config_bonding.sh"
    }

    run_reset_bonding() {
        bash "${SCRIPT_DIR}/modules/reset_bonding.sh"
    }

    run_task2() {
        echo "[TODO] task2"
    }

    run_task3() {
        echo "[TODO] task3"
    }

    run_exit() {
        log "Exit Redhat-Automation Script"
        exit 0 
    }

    while true; do
        draw_menu "${cursor}" "Redhat-Based Automation Menu" "${options[@]}"

        key=$(read_key)

        case "${key}" in
            # upper arrow
            $'\x1b[A')
                cursor=$((cursor - 1))
                [[ ${cursor} -lt 0 ]] && cursor=$((${#options[@]} -1))
                ;;

            # lower arrow 
            $'\x1b[B')
                cursor=$((cursor + 1))
                [[ ${cursor} -ge ${#options[@]} ]] && cursor=0
                ;;

            # Enter
            "")
                ${handlers[${cursor}]}
                read -p "Press 'Enter' for continue..."
                ;;
        esac
    done
}

main "$@"
