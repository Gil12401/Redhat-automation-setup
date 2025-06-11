#!/bin/bash

log() {
    echo -e "[INFO $(date +'%F %T')] $1"
}

eprint() {
    echo "$1" >&2
}

error_exit() {
    echo -e "[ERROR] $1"
    exit 1
}