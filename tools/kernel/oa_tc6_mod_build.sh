#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/t1s_source_common.sh"

KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"
OUT="$REPO_ROOT/build/oa_tc6"

[[ -d "$KDIR" ]] || t1s_die "Kernel headers not found: $KDIR"

rm -rf "$OUT"
mkdir -p "$OUT/include/linux"

# Prefer the target kernel's own OA-TC6 implementation when it already
# provides the modern API required by the pinned T1S vendor drivers.
if [[ "${FORCE_TC6_BACKPORT:-0}" != "1" ]] &&
   t1s_native_tc6_is_usable "$KDIR" "$KVER"; then
    NATIVE_HEADER="$(t1s_find_kernel_header "$KDIR" "$KVER" oa_tc6.h)"
    cp "$NATIVE_HEADER" "$OUT/include/linux/oa_tc6.h"
    printf '%s\n' "$KVER" > "$OUT/.kernel-release"
    touch "$OUT/.native"

    t1s_note "Using native OA-TC6 from kernel $KVER."
    t1s_note "No external OA-TC6 module will be built."
    exit 0
fi

if [[ "${FORCE_TC6_BACKPORT:-0}" == "1" ]]; then
    t1s_note "FORCE_TC6_BACKPORT=1: building the pinned external OA-TC6 backport."
else
    t1s_note "Native OA-TC6 is missing or too old; building the pinned external backport."
fi

SRC="$(t1s_prepare_s2500_v8_minimal "$REPO_ROOT")"

cp "$SRC/include/linux/oa_tc6.h" "$OUT/include/linux/oa_tc6.h"
cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6.c" "$OUT/oa_tc6_core.c"
cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6_ptp.c" "$OUT/"
cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6_tstamp.c" "$OUT/"
cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6_std_def.h" "$OUT/"

# A 6.12 kernel may already ship an older <linux/oa_tc6.h>. Force all common
# OA-TC6 sources to use the local header from the same source baseline.
cp "$OUT/include/linux/oa_tc6.h" "$OUT/oa_tc6_local.h"
for src in "$OUT"/oa_tc6_core.c "$OUT"/oa_tc6_ptp.c "$OUT"/oa_tc6_tstamp.c; do
    sed -i 's@#include <linux/oa_tc6.h>@#include "oa_tc6_local.h"@' "$src"
done

cat > "$OUT/Makefile" <<'EOF'
obj-m := oa_tc6.o
oa_tc6-y := oa_tc6_core.o oa_tc6_ptp.o oa_tc6_tstamp.o
ccflags-y += -I$(M)
EOF

make -C "$KDIR" M="$OUT" modules ||
    t1s_die "OA-TC6 build failed against kernel $KVER"

[[ -f "$OUT/oa_tc6.ko" ]] || t1s_die "oa_tc6.ko was not created"
[[ -f "$OUT/Module.symvers" ]] || t1s_die "OA-TC6 Module.symvers was not created"

printf '%s\n' "$KVER" > "$OUT/.kernel-release"
touch "$OUT/.external"

t1s_note "Built external OA-TC6 backport:"
t1s_note "  $OUT/oa_tc6.ko"
t1s_note "Vendor T1S drivers can now build against:"
t1s_note "  $OUT/include/linux/oa_tc6.h"
t1s_note "  $OUT/Module.symvers"
