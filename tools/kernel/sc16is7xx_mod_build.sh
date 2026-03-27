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

BUILD_DIR="$HOME/build-sc16is752"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

STEP="STEP3"
say "$STEP" "Downloading sources"

BASE_URL="https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.12.y/drivers/tty/serial"

wget -q -O "$BUILD_DIR/sc16is7xx.c"     "$BASE_URL/sc16is7xx.c"
wget -q -O "$BUILD_DIR/sc16is7xx_spi.c" "$BASE_URL/sc16is7xx_spi.c"
wget -q -O "$BUILD_DIR/sc16is7xx.h"     "$BASE_URL/sc16is7xx.h"

STEP="STEP4"
say "$STEP" "Creating Makefile"

cat > "$BUILD_DIR/Makefile" <<'EOF'
obj-m := sc16is7xx.o sc16is7xx_spi.o

all:
    $(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
    $(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
EOF

STEP="STEP5"
say "$STEP" "Building modules"

make -C "$KDIR" M="$BUILD_DIR" modules

[ -f "$BUILD_DIR/sc16is7xx.ko" ] || die "sc16is7xx.ko was not created"
[ -f "$BUILD_DIR/sc16is7xx_spi.ko" ] || die "sc16is7xx_spi.ko was not created"

STEP="STEP6"
say "$STEP" "Installing modules"

sudo install -D -m 644 "$BUILD_DIR/sc16is7xx.ko" "/lib/modules/$KVER/updates/sc16is7xx.ko"
sudo install -D -m 644 "$BUILD_DIR/sc16is7xx_spi.ko" "/lib/modules/$KVER/updates/sc16is7xx_spi.ko"

sudo depmod "$KVER"

STEP="STEP7"
say "$STEP" "Done"
say "$STEP" "Try loading with:"
say "$STEP" "sudo modprobe sc16is7xx"
say "$STEP" "sudo modprobe sc16is7xx_spi"