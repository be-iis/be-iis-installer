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
echo "KERNEL_BRANCH    = $KERNEL_BRANCH"
echo "----------------------------------------"

MODULE_NAME="lan865x"
KERNEL_REPO="${KERNEL_REPO:-https://github.com/raspberrypi/linux.git}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"


DOWNLOAD_DIR="$REPO_ROOT/build/downloads"
LINUX_SRC_DIR="$REPO_ROOT/build/linux/$KERNEL_BRANCH"

MODULE_ROOT="$REPO_ROOT/build/modules/$MODULE_NAME"
MODULE_SRC_DIR="$MODULE_ROOT/src"
MODULE_BUILD_DIR="$MODULE_ROOT/build/${ARCH}-${KERNEL_BRANCH}"
MODULE_OUT_DIR="$MODULE_ROOT/out/${ARCH}-${KERNEL_BRANCH}"
MODULE_LOG_DIR="$MODULE_ROOT/logs/${ARCH}-${KERNEL_BRANCH}"

ARTEFACT_DIR="$REPO_ROOT/artefacts"


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

say "STEP0" "Checking required tools"

require_command git
require_command wget
require_command make
require_command bc
require_command flex
require_command bison
require_command sed
require_command find
require_command "${CROSS_COMPILE}gcc"

mkdir -p \
    "$DOWNLOAD_DIR" \
    "$MODULE_SRC_DIR/include/linux" \
    "$MODULE_BUILD_DIR" \
    "$MODULE_OUT_DIR" \
    "$MODULE_LOG_DIR"

#--------------------------------------------------------------#
# Step 1: Fetch kernel sources
#--------------------------------------------------------------#
say "STEP1" "Fetching kernel sources"

if [[ ! -d "$LINUX_SRC_DIR/.git" ]]; then
    git clone --depth 1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$LINUX_SRC_DIR"
else
    say "STEP1" "Kernel source already present: $LINUX_SRC_DIR"
fi

#--------------------------------------------------------------#
# Step 2: Fetch LAN865x / OA-TC6 / T1S sources
#--------------------------------------------------------------#
say "STEP2" "Fetching module sources"

KERNEL_BRANCH_NUM="${KERNEL_BRANCH#rpi-}"
KERNEL_BRANCH_NUM="${KERNEL_BRANCH_NUM%.y}"

verlte() {
    [ "$1" = "$2" ] && return 0
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}

if verlte "$KERNEL_BRANCH_NUM" "6.13"; then
    LAN865X_BRANCH="rpi-6.13.y"
else
    LAN865X_BRANCH="$KERNEL_BRANCH"
fi

BASE_URL_DRV="https://raw.githubusercontent.com/raspberrypi/linux/refs/heads/${LAN865X_BRANCH}/drivers/net"
BASE_URL_INC="https://raw.githubusercontent.com/raspberrypi/linux/refs/heads/${LAN865X_BRANCH}/include/linux"

wget -q -O "$MODULE_SRC_DIR/lan865x.c" \
    "$BASE_URL_DRV/ethernet/microchip/lan865x/lan865x.c"

wget -q -O "$MODULE_SRC_DIR/oa_tc6.c" \
    "$BASE_URL_DRV/ethernet/oa_tc6.c"

wget -q -O "$MODULE_SRC_DIR/include/linux/oa_tc6.h" \
    "$BASE_URL_INC/oa_tc6.h"

wget -q -O "$MODULE_SRC_DIR/microchip_t1s.c" \
    "$BASE_URL_DRV/phy/microchip_t1s.c"

#--------------------------------------------------------------#
# Step 3: Create module Makefile
#--------------------------------------------------------------#
say "STEP3" "Creating module Makefile"

cat > "$MODULE_SRC_DIR/Makefile" <<'EOF'
obj-m := oa_tc6.o lan865x.o microchip_t1s.o

ccflags-y += -I$(M)/include
EOF

#--------------------------------------------------------------#
# Step 4: Prepare kernel tree
#--------------------------------------------------------------#
say "STEP4" "Preparing kernel tree"

make -C "$LINUX_SRC_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" "$KERNEL_DEFCONFIG"
make -C "$LINUX_SRC_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" modules_prepare
make -C "$LINUX_SRC_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" modules

KVER="$(make -s -C "$LINUX_SRC_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" kernelrelease)"
TARGET_DIR="$ARTEFACT_DIR/$ARCH/$KVER"

say "STEP4" "Kernel release: $KVER"
say "STEP4" "Target artefact dir: $TARGET_DIR"

#--------------------------------------------------------------#
# Step 5: Build modules
#--------------------------------------------------------------#
say "STEP5" "Building modules"

rm -rf "$MODULE_BUILD_DIR"
mkdir -p "$MODULE_BUILD_DIR/include/linux"

cp "$MODULE_SRC_DIR/lan865x.c" "$MODULE_BUILD_DIR/"
cp "$MODULE_SRC_DIR/oa_tc6.c" "$MODULE_BUILD_DIR/"
cp "$MODULE_SRC_DIR/microchip_t1s.c" "$MODULE_BUILD_DIR/"
cp "$MODULE_SRC_DIR/Makefile" "$MODULE_BUILD_DIR/"
cp "$MODULE_SRC_DIR/include/linux/oa_tc6.h" "$MODULE_BUILD_DIR/include/linux/"

make -C "$LINUX_SRC_DIR" \
    M="$MODULE_BUILD_DIR" \
    ARCH="$ARCH" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    modules

#--------------------------------------------------------------#
# Step 6: Postprocess
#--------------------------------------------------------------#
say "STEP6" "Postprocessing artefacts"

mkdir -p "$TARGET_DIR"
mkdir -p "$MODULE_OUT_DIR"

mapfile -t KO_FILES < <(find "$MODULE_BUILD_DIR" -maxdepth 1 -type f -name '*.ko' | sort)

[[ "${#KO_FILES[@]}" -gt 0 ]] || die "No .ko files were created"

say "STEP6" "Found ${#KO_FILES[@]} module(s):"

for ko in "${KO_FILES[@]}"; do
    ko_name="$(basename "$ko")"
    ko_base="${ko_name%.ko}"

    say "STEP6" "  $ko_name"

    cp "$ko" "$TARGET_DIR/$ko_name"
    cp "$ko" "$MODULE_OUT_DIR/${ko_base}-${ARCH}-${KERNEL_BRANCH}.ko"
done

say "STEP6" "Created artefacts in:"
say "STEP6" "  $TARGET_DIR"
say "STEP6" "  $MODULE_OUT_DIR"

say "STEP7" "Done"
say "STEP7" "Modules built:"
for ko in "${KO_FILES[@]}"; do
    say "STEP7" "  $(basename "$ko")"
done