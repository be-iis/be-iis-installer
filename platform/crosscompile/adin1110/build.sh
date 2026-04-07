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

MODULE_NAME="adin1110"
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
require_command "${CROSS_COMPILE}gcc"

mkdir -p \
    "$DOWNLOAD_DIR" \
    "$MODULE_SRC_DIR" \
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
# Step 2: Fetch ADIN1110 source
#--------------------------------------------------------------#
say "STEP2" "Fetching ADIN1110 source"

BASE_URL="https://raw.githubusercontent.com/raspberrypi/linux/${KERNEL_BRANCH}/drivers/net/ethernet/adi"

wget -q -O "$MODULE_SRC_DIR/adin1110.c" "$BASE_URL/adin1110.c"

#--------------------------------------------------------------#
# Step 3: Apply compatibility patch
#--------------------------------------------------------------#
say "STEP3" "Applying compatibility patch for kernels without CONFIG_NET_SWITCHDEV"

sed -i '/offload_fwd_mark = port_priv->priv->forwarding;/c\
#ifdef CONFIG_NET_SWITCHDEV\
\t\t\trxb->offload_fwd_mark = port_priv->priv->forwarding;\
#endif' "$MODULE_SRC_DIR/adin1110.c"

#--------------------------------------------------------------#
# Step 4: Create module Makefile
#--------------------------------------------------------------#
say "STEP4" "Creating module Makefile"

cat > "$MODULE_SRC_DIR/Makefile" <<'EOF'
obj-m := adin1110.o
EOF

#--------------------------------------------------------------#
# Step 5: Prepare kernel tree
#--------------------------------------------------------------#
say "STEP5" "Preparing kernel tree"

make -C "$LINUX_SRC_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" $KERNEL_DEFCONFIG
make -C "$LINUX_SRC_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" modules_prepare
make -C "$LINUX_SRC_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" modules

KVER="$(make -s -C "$LINUX_SRC_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" kernelrelease)"
TARGET_DIR="$ARTEFACT_DIR/$ARCH/$KVER"

say "STEP5" "Kernel release: $KVER"
say "STEP5" "Target artefact dir: $TARGET_DIR"

#--------------------------------------------------------------#
# Step 6: Build module
#--------------------------------------------------------------#
say "STEP6" "Building module"

rm -rf "$MODULE_BUILD_DIR"
mkdir -p "$MODULE_BUILD_DIR"
cp "$MODULE_SRC_DIR/"* "$MODULE_BUILD_DIR/"

make -C "$LINUX_SRC_DIR" \
    M="$MODULE_BUILD_DIR" \
    ARCH="$ARCH" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    modules

#--------------------------------------------------------------#
# Step 7: Postprocess
#--------------------------------------------------------------#
say "STEP7" "Postprocessing artefacts"

[[ -f "$MODULE_BUILD_DIR/${MODULE_NAME}.ko" ]] || die "${MODULE_NAME}.ko was not created"

mkdir -p "$TARGET_DIR"
mkdir -p "$MODULE_OUT_DIR"

cp "$MODULE_BUILD_DIR/${MODULE_NAME}.ko" \
   "$TARGET_DIR/${MODULE_NAME}.ko"

cp "$MODULE_BUILD_DIR/${MODULE_NAME}.ko" \
   "$MODULE_OUT_DIR/${MODULE_NAME}-${ARCH}-${KERNEL_BRANCH}.ko"

say "STEP7" "Created:"
say "STEP7" "  $TARGET_DIR/${MODULE_NAME}.ko"
say "STEP7" "  $MODULE_OUT_DIR/${MODULE_NAME}-${ARCH}-${KERNEL_BRANCH}.ko"

say "STEP7" "Done"
