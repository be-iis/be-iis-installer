#!/usr/bin/env bash
set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }
say() { printf '%s: %s\n' "$1" "$2"; }

KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/machxo2-fpga-manager"
BASE_URL="https://raw.githubusercontent.com/torvalds/linux/v6.12/drivers/fpga"

[ -d "$KDIR" ] || die "Kernel build directory not found: $KDIR"
[ -f "$KDIR/include/linux/fpga/fpga-mgr.h" ] || die "Kernel headers lack FPGA manager API"

say STEP1 "Preparing $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

say STEP2 "Downloading Linux v6.12 FPGA manager sources"
wget -q -O "$BUILD_DIR/fpga-mgr.c" "$BASE_URL/fpga-mgr.c"
wget -q -O "$BUILD_DIR/machxo2-spi.c" "$BASE_URL/machxo2-spi.c"

printf 'obj-m := fpga-mgr.o machxo2-spi.o\n' > "$BUILD_DIR/Makefile"

say STEP3 "Building external modules"
make -C "$KDIR" M="$BUILD_DIR" modules

[ -f "$BUILD_DIR/fpga-mgr.ko" ] || die "fpga-mgr.ko was not created"
[ -f "$BUILD_DIR/machxo2-spi.ko" ] || die "machxo2-spi.ko was not created"

say STEP4 "Installing modules"
sudo install -D -m 644 "$BUILD_DIR/fpga-mgr.ko" "/lib/modules/$KVER/updates/fpga-mgr.ko"
sudo install -D -m 644 "$BUILD_DIR/machxo2-spi.ko" "/lib/modules/$KVER/updates/machxo2-spi.ko"
sudo depmod "$KVER"

say STEP5 "Done"
echo "Load with: sudo modprobe fpga-mgr && sudo modprobe machxo2-spi"
