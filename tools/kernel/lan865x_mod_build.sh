#!/usr/bin/env bash
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

STEP="STEP1"
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

[ -d "$KDIR" ] || die "Kernel build directory not found: $KDIR"
[ -f "$KDIR/include/generated/autoconf.h" ] || die "Missing autoconf.h in $KDIR"
[ -f "$KDIR/Makefile" ] || die "Missing kernel Makefile in $KDIR"

STEP="STEP2"
say "$STEP" "Preparing build directory"

BUILD_DIR="${REPO_ROOT}/build/lan865x"
INCLUDE_DIR="$BUILD_DIR/include/linux"

rm -rf "$BUILD_DIR"
mkdir -p "$INCLUDE_DIR"

STEP="STEP3"
say "$STEP" "Downloading sources"

wget -q -O "$BUILD_DIR/lan865x.c" \
"https://raw.githubusercontent.com/raspberrypi/linux/refs/heads/rpi-6.13.y/drivers/net/ethernet/microchip/lan865x/lan865x.c"

wget -q -O "$BUILD_DIR/oa_tc6.c" \
"https://raw.githubusercontent.com/raspberrypi/linux/refs/heads/rpi-6.13.y/drivers/net/ethernet/oa_tc6.c"

wget -q -O "$INCLUDE_DIR/oa_tc6.h" \
"https://raw.githubusercontent.com/raspberrypi/linux/refs/heads/rpi-6.13.y/include/linux/oa_tc6.h"

wget -q -O $BUILD_DIR/microchip_t1s.c \
https://raw.githubusercontent.com/raspberrypi/linux/refs/heads/rpi-6.13.y/drivers/net/phy/microchip_t1s.c

STEP="STEP4"
say "$STEP" "Creating Makefile"

cat > "$BUILD_DIR/Makefile" <<'EOF'
obj-m := oa_tc6.o lan865x.o microchip_t1s.o

ccflags-y += -I$(PWD)/include

all:
	$(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	$(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
EOF

STEP="STEP5"
say "$STEP" "Building modules"

make -C "$KDIR" M="$BUILD_DIR" modules

[ -f "$BUILD_DIR/oa_tc6.ko" ] || die "oa_tc6.ko was not created"
[ -f "$BUILD_DIR/lan865x.ko" ] || die "lan865x.ko was not created"

STEP="STEP6"
say "$STEP" "Installing modules"

sudo install -D -m 644 "$BUILD_DIR/oa_tc6.ko" "/lib/modules/$KVER/updates/oa_tc6.ko"
sudo install -D -m 644 "$BUILD_DIR/lan865x.ko" "/lib/modules/$KVER/updates/lan865x.ko"
sudo install -D -m 644 "$BUILD_DIR/microchip_t1s.ko" "/lib/modules/$KVER/updates/microchip_t1s.ko"

sudo depmod "$KVER"

STEP="STEP7"
say "$STEP" "Done"
say "$STEP" "Try loading with:"
say "$STEP" "sudo modprobe oa_tc6"
say "$STEP" "sudo modprobe lan865x"
say "$STEP" "sudo modprobe microchip_t1s"
