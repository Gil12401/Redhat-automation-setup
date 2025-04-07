#!/bin/bash 

# Directory Path 
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
UTIL_DIR="${SCRIPT_DIR}/util"

# util functions
source "${UTIL_DIR}/util_functions.sh"

# Menu Options 
cursor=0
options=(
    "Local Repository 설정"
    "Bonding 설정"
    "작업 예정 1."
    "작업 예정 2."
    "작업 예정 3."
    "종료"
)

handlers=(
    "run_config_localrepo"
    "run_config_bonding"
    "run_task1"
    "run_task2"
    "run_task3"
    "run_exit"
)

run_config_localrepo() {
    bash "${SCRIPT_DIR}/modules/config_localrepo.sh"
}

run_config_bonding() {
  echo "[TODO] bonding.sh 실행 예정"
}

run_task1() {
  echo "[TODO] task1 실행 예정"
}

run_task2() {
  echo "[TODO] task2 실행 예정"
}

run_task3() {
  echo "[TODO] task3 실행 예정"
}

run_exit() {
    log "init-setup을 종료합니다."
    exit 0 
}

while true; do
    draw_menu "${cursor}" "Redhat 계열 init-setup 자동화 메뉴" "${options[@]}"

    read -rsn1 key
    if [[ ${key} == $'\x1b' ]]; then 
        read -rsn2 -t 0.1 key2
        key+="${key2}"

    fi 

    case "${key}" in
        # 위쪽 화살표 
        $'\x1b[A')
            cursor=$((cursor - 1))
            [[ ${cursor} -lt 0 ]] && cursor=$((${#options[@]} -1))
            ;;

        # 아래쪽 화살표 
        $'\x1b[B')
            cursor=$((cursor + 1))
            [[ ${cursor} -ge ${#options[@]} ]] && cursor=0
            ;;

        # Enter
        "")
            ${handlers[${cursor}]}
            read -p "계속하려면 Enter 키를 누르세요..."
            ;;
    esac
done