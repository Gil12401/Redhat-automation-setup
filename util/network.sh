#!/bin/bash

flush_all_nic_ip() {
    local nics=($(ls /sys/class/net | grep -v '^lo$'))

    for nic in "${nics[@]}"; do
        ip addr flush dev "$nic" 2>/dev/null
        log "IP flushed: $nic"
    done
}


# ==================================== ip & subnet calc =====================================
dec2bin() {
    local dec=$1
    echo "obase=2; ${dec}" | bc
}

get_prefix_from_subnet_bc() {
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

get_prefix_from_subnet_basic() {
    case "$1" in
        255.0.0.0) echo 8 ;;
        255.255.0.0) echo 16 ;;
        255.255.255.0) echo 24 ;;
        255.255.255.128) echo 25 ;;
        255.255.255.192) echo 26 ;;
        *) echo "[ERROR] 지원되지 않는 netmask" >&2; return 1 ;;
    esac

}

get_prefix_from_subnet() {
    local subnet=$1
    if ! command -v bc &> /dev/null; then
        get_prefix_from_subnet_basic "${subnet}"
    else
        get_prefix_from_subnet_bc "${subnet}"
    fi
}