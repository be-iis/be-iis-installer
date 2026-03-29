#!/bin/sh

set -e

die() {
    printf "Error: %s\n" "$1" >&2
    exit 1
}

say() {
    step="$1"
    msg="$2"
    printf "%s: %s\n" "$step" "$msg"
}

require_command() {
    cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

detect_header_pkg() {
    kver="$1"

    case "$kver" in
        *rpi-2712*)
            printf "linux-headers-rpi-2712\n"
            ;;
        *rpi-v8*)
            printf "linux-headers-rpi-v8\n"
            ;;
        *rpi-v7l*)
            printf "linux-headers-rpi-v7l\n"
            ;;
        *rpi-v7*)
            printf "linux-headers-rpi-v7\n"
            ;;
        *rpi-v6*)
            printf "linux-headers-rpi-v6\n"
            ;;
        *)
            return 1
            ;;
    esac
}

build_tree_ready() {
    kdir="$1"

    [ -d "$kdir" ] || return 1
    [ -f "$kdir/Makefile" ] || return 1
    [ -f "$kdir/include/generated/autoconf.h" ] || return 1

    return 0
}

fix_dpkg_if_needed() {
    if dpkg --audit 2>/dev/null | grep -q .; then
        say "$STEP" "Detected unfinished package configuration, trying to repair it"
        sudo dpkg --configure -a || die "dpkg --configure -a failed"
    fi
}

STEP="STEP1"
say "$STEP" "Checking required tools"

require_command uname
require_command dpkg
require_command grep
require_command sudo

if ! command -v apt >/dev/null 2>&1; then
    die "This script currently supports only Raspberry Pi OS systems with apt."
fi

KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"

say "$STEP" "Running kernel: $KVER"
say "$STEP" "Kernel build directory: $KDIR"

STEP="STEP2"
say "$STEP" "Checking whether the build environment is already present"

if build_tree_ready "$KDIR"; then
    say "$STEP" "Kernel build environment already available"
else
    say "$STEP" "Kernel build environment missing"

    HEADER_PKG="$(detect_header_pkg "$KVER")" || die "Unsupported Raspberry Pi kernel flavour: $KVER"

    say "$STEP" "Detected header package: $HEADER_PKG"

    fix_dpkg_if_needed

    say "$STEP" "Updating package lists"
    sudo apt update

    say "$STEP" "Installing build tools and kernel headers"
    sudo apt install -y \
        build-essential \
        make \
        gcc \
        libc6-dev \
        pkg-config \
        wget \
        curl \
        bc \
        kmod \
        automake \
        autoconf \
        libtool \
        pkg-config \
        "$HEADER_PKG"

    if ! build_tree_ready "$KDIR"; then
        die "Kernel build environment is still incomplete after installation: $KDIR"
    fi
fi

STEP="STEP3"
say "$STEP" "Verifying final build environment"

say "$STEP" "Kernel build environment is ready"
say "$STEP" "You can now build external modules against:"
say "$STEP" "$KDIR"
