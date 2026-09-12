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
say STEP1 "Preparing $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

say STEP2 "Downloading Linux v6.12 FPGA framework sources"
mkdir -p "$BUILD_DIR/include/linux/fpga"
for source in fpga-mgr fpga-bridge fpga-region of-fpga-region machxo2-spi; do
  wget -q -O "$BUILD_DIR/$source.c" "$BASE_URL/$source.c"
done
for header in fpga-mgr fpga-bridge fpga-region; do
  wget -q -O "$BUILD_DIR/include/linux/fpga/$header.h" \
    "https://raw.githubusercontent.com/torvalds/linux/v6.12/include/linux/fpga/$header.h"
done

printf 'ccflags-y := -I$(src)/include\nobj-m := fpga-mgr.o fpga-bridge.o fpga-region.o of-fpga-region.o machxo2-spi.o\n' > "$BUILD_DIR/Makefile"

say STEP3 "Building external modules"
make -C "$KDIR" M="$BUILD_DIR" modules

for module in fpga-mgr fpga-bridge fpga-region of-fpga-region machxo2-spi; do
  [ -f "$BUILD_DIR/$module.ko" ] || die "$module.ko was not created"
done

say STEP4 "Installing modules"
for module in fpga-mgr fpga-bridge fpga-region of-fpga-region machxo2-spi; do
  sudo install -D -m 644 "$BUILD_DIR/$module.ko" "/lib/modules/$KVER/updates/$module.ko"
done
sudo depmod "$KVER"

say STEP5 "Done"
echo "Load with: sudo modprobe of-fpga-region && sudo modprobe machxo2-spi"
