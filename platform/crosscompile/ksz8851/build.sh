#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"


# Usage:
#   PI_VARIANT=pi5_64 ./build.sh
#   PI_VARIANT=pi5_32 ./build.sh
#   PI_VARIANT=pi4_64 ./build.sh
#   PI_VARIANT=pi4_32 ./build.sh
#   PI_VARIANT=pi3_64 ./build.sh
#   PI_VARIANT=pi3_32 ./build.sh
#   PI_VARIANT=zero2w_64 ./build.sh
#   PI_VARIANT=zero2w_32 ./build.sh
#   PI_VARIANT=zero_32 ./build.sh
#   PI_VARIANT=pi1_32 ./build.sh
#   PI_VARIANT=pi2_32 ./build.sh
PI_VARIANT="${PI_VARIANT:-pi4_64}"

case "$PI_VARIANT" in

# =============================================================
# 64-bit (arm64)
# =============================================================
pi5_64|pi4_64|pi400_64|cm4_64|pi3_64|zero2w_64)
    ARCH="arm64"
    CROSS_COMPILE="aarch64-linux-gnu-"
    KERNEL_DEFCONFIG="bcm2711_defconfig"
    KERNEL_BRANCH="${KERNEL_BRANCH:-rpi-6.12.y}"

    echo "Selected: 64-bit build (arm64)"
    ;;

# =============================================================
# 32-bit (armhf)
# =============================================================
pi5_32|pi4_32|pi3_32|zero2w_32|zero_32|pi2_32|pi1_32)
    ARCH="arm"
    CROSS_COMPILE="arm-linux-gnueabihf-"
    KERNEL_DEFCONFIG="bcmrpi_defconfig"
    KERNEL_BRANCH="${KERNEL_BRANCH:-rpi-6.12.y}"

    echo "Selected: 32-bit build (armhf)"
    ;;

# =============================================================
# Unknown
# =============================================================
*)
    echo "Error: Unknown PI_VARIANT: $PI_VARIANT"
    echo ""
    echo "Valid options:"
    echo "  pi5_64 pi5_32"
    echo "  pi4_64 pi4_32"
    echo "  pi3_64 pi3_32"
    echo "  zero2w_64 zero2w_32"
    echo "  zero_32 pi2_32 pi1_32"
    exit 1
    ;;
esac

echo "----------------------------------------"
echo "PI_VARIANT       = $PI_VARIANT"
echo "ARCH             = $ARCH"
echo "CROSS_COMPILE    = $CROSS_COMPILE"
echo "KERNEL_DEFCONFIG = $KERNEL_DEFCONFIG"
echo "----------------------------------------"




KERNEL_REPO="${KERNEL_REPO:-https://github.com/raspberrypi/linux.git}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

WORK_ROOT="$REPO_ROOT/build/ksz8851_cross_${ARCH}-${KERNEL_BRANCH}"
DOWNLOAD_DIR="$WORK_ROOT/downloads"
LINUX_SRC_DIR="$WORK_ROOT/src/linux"
MODULE_SRC_DIR="$WORK_ROOT/src/module"
MODULE_BUILD_DIR="$WORK_ROOT/build/module"
OUT_DIR="$WORK_ROOT/out"
LOG_DIR="$WORK_ROOT/logs"

die() {
    echo "Error: $*" >&2
    exit 1
}

say() {
    printf "%s: %s\n" "$1" "$2"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}




require_command git
require_command wget
require_command make
require_command bc
require_command flex
require_command bison
require_command "${CROSS_COMPILE}gcc"


mkdir -p \
    "$DOWNLOAD_DIR" \
    "$MODULE_SRC_DIR" \
    "$MODULE_BUILD_DIR" \
    "$OUT_DIR" \
    "$LOG_DIR"

#--------------------------------------------------------------#
#			Step 3					#
#		Fetsching Kernel Sources			#
#--------------------------------------------------------------#
    
 if [[ ! -d "$LINUX_SRC_DIR/.git" ]]; then
    git clone --depth 1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$LINUX_SRC_DIR"
else
    say "STEP3" "Kernel source already present: $LINUX_SRC_DIR"
fi

#--------------------------------------------------------------#
#			Step 4					#
#		Fetsching KSZ8851 Data				#
#--------------------------------------------------------------#
BASE_URL="https://raw.githubusercontent.com/raspberrypi/linux/${KERNEL_BRANCH}/drivers/net/ethernet/micrel"

wget -q -O "$MODULE_SRC_DIR/ks8851_spi.c"    "$BASE_URL/ks8851_spi.c"
wget -q -O "$MODULE_SRC_DIR/ks8851_common.c" "$BASE_URL/ks8851_common.c"
wget -q -O "$MODULE_SRC_DIR/ks8851.h"        "$BASE_URL/ks8851.h"


#--------------------------------------------------------------#
#			Step 5					#
#			Create Makefile				#
#--------------------------------------------------------------#
cat > "$MODULE_SRC_DIR/Makefile" <<'EOF'
obj-m := ks8851.o
ks8851-y := ks8851_spi.o ks8851_common.o
EOF

#--------------------------------------------------------------#
#			Step 6					#
#			Prepare					#
#--------------------------------------------------------------#
make -C "$LINUX_SRC_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" $KERNEL_DEFCONFIG
make -C "$LINUX_SRC_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" modules_prepare
make -C "$LINUX_SRC_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" modules

#--------------------------------------------------------------#
#			Step 7					#
#			build					#
#--------------------------------------------------------------#
rm -rf "$MODULE_BUILD_DIR"
mkdir -p "$MODULE_BUILD_DIR"
cp "$MODULE_SRC_DIR/"* "$MODULE_BUILD_DIR/"

make -C "$LINUX_SRC_DIR" \
    M="$MODULE_BUILD_DIR" \
    ARCH="$ARCH" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    modules
    
#--------------------------------------------------------------#
#			Step 8					#
#			postprocess				#
#--------------------------------------------------------------#
[[ -f "$MODULE_BUILD_DIR/ks8851.ko" ]] || die "ks8851.ko was not created"

cp "$MODULE_BUILD_DIR/ks8851.ko" \
   "$OUT_DIR/ks8851-${ARCH}-${KERNEL_BRANCH}.ko"
   
cp "$MODULE_BUILD_DIR/ks8851.ko" "$OUT_DIR/ks8851.ko"
