#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/t1s_source_common.sh"

KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"
TC6="$REPO_ROOT/build/oa_tc6"
OUT="$REPO_ROOT/build/lan865x"

[[ -d "$KDIR" ]] || t1s_die "Kernel headers not found: $KDIR"

if modinfo lan865x >/dev/null 2>&1; then
    t1s_note "Running kernel already provides lan865x."
    exit 0
fi

t1s_ensure_tc6_build "$REPO_ROOT"
SRC="$(t1s_prepare_s2500_v8_minimal "$REPO_ROOT")"

rm -rf "$OUT"
mkdir -p "$OUT"

cp "$SRC/drivers/net/ethernet/microchip/lan865x/lan865x.c" "$OUT/"
cp "$SRC/drivers/net/phy/microchip_t1s.c" "$OUT/"
cp "$TC6/include/linux/oa_tc6.h" "$OUT/oa_tc6_local.h"

sed -i 's@#include <linux/oa_tc6.h>@#include "oa_tc6_local.h"@' "$OUT/lan865x.c"

cat > "$OUT/Makefile" <<'EOF'
obj-m := lan865x.o microchip_t1s.o
ccflags-y += -I$(M)
EOF

make -C "$KDIR" M="$OUT"     KBUILD_EXTRA_SYMBOLS="$TC6/Module.symvers"     modules || t1s_die "LAN865x build failed against shared OA-TC6 baseline"

[[ -f "$OUT/lan865x.ko" ]] || t1s_die "lan865x.ko was not created"
[[ -f "$OUT/microchip_t1s.ko" ]] || t1s_die "microchip_t1s.ko was not created"

t1s_note "Built LAN865x modules in $OUT"
