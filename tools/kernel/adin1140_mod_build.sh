#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/t1s_source_common.sh"

KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"
TC6="$REPO_ROOT/build/oa_tc6"
OUT="$REPO_ROOT/build/adin1140"

[[ -d "$KDIR" ]] || t1s_die "Kernel headers not found: $KDIR"

if modinfo adin1140 >/dev/null 2>&1; then
    t1s_note "Running kernel already provides adin1140."
    exit 0
fi

t1s_ensure_tc6_build "$REPO_ROOT"

rm -rf "$OUT"
mkdir -p "$OUT"

t1s_note "Fetching ADIN1140 driver sources from $ADIN1140_BASE_COMMIT."
t1s_fetch_upstream_file "$ADIN1140_BASE_COMMIT"     "drivers/net/ethernet/adi/adin1140.c" "$OUT/adin1140.c" ||
    t1s_die "Could not fetch adin1140.c"
t1s_fetch_upstream_file "$ADIN1140_BASE_COMMIT"     "drivers/net/phy/adin1140-phy.c" "$OUT/adin1140-phy.c" ||
    t1s_die "Could not fetch adin1140-phy.c"

cp "$TC6/include/linux/oa_tc6.h" "$OUT/oa_tc6_local.h"
sed -i 's@#include <linux/oa_tc6.h>@#include "oa_tc6_local.h"@' "$OUT/adin1140.c"

# Backport compatibility for older Raspberry Pi kernels such as 6.12.
# Detect API features from the actual target headers instead of guessing from
# uname version numbers.
NETDEV_H="$KDIR/include/linux/netdevice.h"

if ! grep -q 'ndo_set_rx_mode_async' "$NETDEV_H"; then
    t1s_warn "Target kernel has no ndo_set_rx_mode_async; disabling runtime RX-filter updates."
    t1s_warn "Basic unicast/broadcast operation remains available; promisc/multicast filter changes are limited."
    sed -i '/^[[:space:]]*\.ndo_set_rx_mode_async[[:space:]]*=/d' "$OUT/adin1140.c"
    # Avoid an unused-static-function warning after removing the only callback.
    sed -i 's/^static int adin1140_rx_mode(/static __maybe_unused int adin1140_rx_mode(/' "$OUT/adin1140.c"
fi

if ! grep -q 'netns_immutable' "$NETDEV_H"; then
    t1s_warn "Target kernel has no netns_immutable field; omitting that assignment."
    sed -i '/^[[:space:]]*netdev->netns_immutable[[:space:]]*=/d' "$OUT/adin1140.c"
fi

cat > "$OUT/Makefile" <<'EOF'
obj-m := adin1140.o adin1140-phy.o
ccflags-y += -I$(M)
EOF

make -C "$KDIR" M="$OUT"     KBUILD_EXTRA_SYMBOLS="$TC6/Module.symvers"     modules || t1s_die "ADIN1140 build failed against shared OA-TC6 baseline"

[[ -f "$OUT/adin1140.ko" ]] || t1s_die "adin1140.ko was not created"
[[ -f "$OUT/adin1140-phy.ko" ]] || t1s_die "adin1140-phy.ko was not created"

t1s_note "Built ADIN1140 modules in $OUT"
