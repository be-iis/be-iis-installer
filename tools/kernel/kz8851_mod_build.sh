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

BUILD_DIR="$HOME/build-ksz8851"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

STEP="STEP3"
say "$STEP" "Downloading sources"

BASE_URL="https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.12.y/drivers/net/ethernet/micrel"

wget -q -O "$BUILD_DIR/ks8851_spi.c"    "$BASE_URL/ks8851_spi.c"
wget -q -O "$BUILD_DIR/ks8851_common.c" "$BASE_URL/ks8851_common.c"
wget -q -O "$BUILD_DIR/ks8851.h"        "$BASE_URL/ks8851.h"

STEP="STEP4"
say "$STEP" "Creating Makefile"

cat > "$BUILD_DIR/Makefile" <<'EOF'
obj-m := ks8851.o
ks8851-y := ks8851_spi.o ks8851_common.o

all:
	$(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	$(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
EOF

STEP="STEP5"
say "$STEP" "Building module"

make -C "$KDIR" M="$BUILD_DIR" modules

[ -f "$BUILD_DIR/ks8851.ko" ] || die "ks8851.ko was not created"

STEP="STEP6"
say "$STEP" "Installing module"

sudo install -D -m 644 "$BUILD_DIR/ks8851.ko" "/lib/modules/$KVER/updates/ks8851.ko"

sudo depmod "$KVER"

STEP="STEP7"
say "$STEP" "Done"
say "$STEP" "Try loading with:"
say "$STEP" "sudo modprobe ks8851_spi"
