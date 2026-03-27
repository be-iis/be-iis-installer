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

BUILD_DIR="$HOME/build-mcp251xfd"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

STEP="STEP3"
say "$STEP" "Downloading sources"

BASE_URL="https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.12.y/drivers/net/can/spi/mcp251xfd"

for f in \
    mcp251xfd-core.c \
    mcp251xfd-chip-fifo.c \
    mcp251xfd-crc16.c \
    mcp251xfd-dump.c \
    mcp251xfd-dump.h \
    mcp251xfd-ethtool.c \
    mcp251xfd-ram.c \
    mcp251xfd-regmap.c \
    mcp251xfd-regmap.h \
    mcp251xfd-ring.c \
    mcp251xfd-rx.c \
    mcp251xfd-tef.c \
    mcp251xfd-timestamp.c \
    mcp251xfd-tx.c \
    mcp251xfd.h
do
    wget -nv -O "$BUILD_DIR/$f" "$BASE_URL/$f"
done

STEP="STEP4"
say "$STEP" "Creating Makefile"

cat > "$BUILD_DIR/Makefile" <<'EOF'
obj-m := mcp251xfd.o

mcp251xfd-y := \
    mcp251xfd-core.o \
    mcp251xfd-chip-fifo.o \
    mcp251xfd-crc16.o \
    mcp251xfd-dump.o \
    mcp251xfd-ethtool.o \
    mcp251xfd-ram.o \
    mcp251xfd-regmap.o \
    mcp251xfd-ring.o \
    mcp251xfd-rx.o \
    mcp251xfd-tef.o \
    mcp251xfd-timestamp.o \
    mcp251xfd-tx.o

all:
    $(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
    $(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
EOF

STEP="STEP5"
say "$STEP" "Building module"

make -C "$KDIR" M="$BUILD_DIR" modules

[ -f "$BUILD_DIR/mcp251xfd.ko" ] || die "mcp251xfd.ko was not created"

STEP="STEP6"
say "$STEP" "Installing module"

sudo install -D -m 644 "$BUILD_DIR/mcp251xfd.ko" "/lib/modules/$KVER/updates/mcp251xfd.ko"
sudo depmod "$KVER"

STEP="STEP7"
say "$STEP" "Done"
say "$STEP" "Try loading with:"
say "$STEP" "sudo modprobe mcp251xfd"