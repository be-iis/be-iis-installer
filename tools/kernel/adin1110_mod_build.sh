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

BUILD_DIR="${REPO_ROOT}/build/adin1110"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

STEP="STEP3"
say "$STEP" "Downloading sources"

KMAJOR="$(echo "$KVER" | cut -d. -f1)"
KMINOR="$(echo "$KVER" | cut -d. -f2)"
KBRANCH="rpi-${KMAJOR}.${KMINOR}.y"

BASE_URL="https://raw.githubusercontent.com/raspberrypi/linux/${KBRANCH}/drivers/net/ethernet/adi"

say "$STEP" "Using Raspberry Pi kernel branch: $KBRANCH"

wget -nv -O "$BUILD_DIR/adin1110.c" "$BASE_URL/adin1110.c"

STEP="STEP3b"

if grep -q '^CONFIG_NET_SWITCHDEV=y' "$KDIR/.config"; then
    say "$STEP" "CONFIG_NET_SWITCHDEV enabled, no compatibility patch needed"
else
    say "$STEP" "Applying compatibility patch for kernels without CONFIG_NET_SWITCHDEV"

    sed -i '/offload_fwd_mark = port_priv->priv->forwarding;/c\
#ifdef CONFIG_NET_SWITCHDEV\
\t\t\trxb->offload_fwd_mark = port_priv->priv->forwarding;\
#endif' "$BUILD_DIR/adin1110.c"
fi

STEP="STEP3c"
say "$STEP" "Applying BE-IIS random MAC fallback patch"

PATCH_FILE="${REPO_ROOT}/products/BE-IIS-HPP-T1L-REVB/files/adin1110-random-mac-fallback.patch"

if [ -f "$PATCH_FILE" ]; then
    if patch -d "$BUILD_DIR" -p0 --forward --dry-run < "$PATCH_FILE" >/dev/null 2>&1; then
        patch -d "$BUILD_DIR" -p0 --forward < "$PATCH_FILE"
        say "$STEP" "Patch applied: $PATCH_FILE"
    else
        say "$STEP" "WARNING: Patch could not be applied, continuing without random MAC fallback"
    fi
else
    say "$STEP" "WARNING: Patch file not found: $PATCH_FILE"
fi

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
