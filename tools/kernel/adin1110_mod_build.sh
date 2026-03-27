#!/bin/sh

set -e

die() {
    echo "Error: $1" >&2
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

STEP="STEP0"
say "$STEP" "Checking required tools"

require_command uname
require_command wget
require_command make
require_command gcc
require_command sudo

KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"

say "$STEP" "Running kernel: $KVER"
say "$STEP" "Kernel build directory: $KDIR"

STEP="STEP1"
say "$STEP" "Checking kernel compatibility"

case "$KVER" in
    6.1[2-9].*|6.[2-9]*)
        ;;
    *)
        die "Unsupported kernel version: $KVER (requires >= 6.12)"
        ;;
esac

[ -d "$KDIR" ] || die "Kernel build directory not found: $KDIR"
[ -f "$KDIR/include/generated/autoconf.h" ] || die "Missing autoconf.h in $KDIR"
[ -f "$KDIR/Makefile" ] || die "Missing kernel Makefile in $KDIR"

STEP="STEP2"
say "$STEP" "Preparing build directory"

BUILD_DIR="$HOME/build-adin1110"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

STEP="STEP3"
say "$STEP" "Downloading sources"

BASE_URL="https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.12.y/drivers/net/ethernet/adi"

wget -nv -O "$BUILD_DIR/adin1110.c" "$BASE_URL/adin1110.c"

STEP="STEP4"
say "$STEP" "Creating Makefile"

printf 'obj-m := adin1110.o\n\nall:\n\t$(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules\n\nclean:\n\t$(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean\n' > "$BUILD_DIR/Makefile"

STEP="STEP5"
say "$STEP" "Building module"

make -C "$KDIR" M="$BUILD_DIR" modules

[ -f "$BUILD_DIR/adin1110.ko" ] || die "adin1110.ko was not created"

STEP="STEP6"
say "$STEP" "Installing module"

sudo install -D -m 644 "$BUILD_DIR/adin1110.ko" "/lib/modules/$KVER/updates/adin1110.ko"
sudo depmod "$KVER"

STEP="STEP7"
say "$STEP" "Done"
say "$STEP" "Try loading with:"
say "$STEP" "sudo modprobe adin1110"
