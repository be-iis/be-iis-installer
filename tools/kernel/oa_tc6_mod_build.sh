#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/t1s_source_common.sh"

KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"
OUT="$REPO_ROOT/build/oa_tc6"

[[ -d "$KDIR" ]] || t1s_die "Kernel headers not found: $KDIR"

# If the running kernel already contains a sufficiently new OA-TC6 framework,
# use it directly. Otherwise build the common BE-IIS backport once.
if modinfo oa_tc6 >/dev/null 2>&1 &&
   grep -q 'oa_tc6_read_register_mms' "$KDIR/include/linux/oa_tc6.h" 2>/dev/null &&
   grep -q 'OA_TC6_BROKEN_PHY' "$KDIR/include/linux/oa_tc6.h" 2>/dev/null; then
    t1s_note "Running kernel already provides the required OA-TC6 API."
    exit 0
fi

t1s_warn "Kernel OA-TC6 is missing or too old."
t1s_warn "Building one shared OA-TC6 backport for all BE-IIS T1S drivers."

SRC="$(t1s_prepare_s2500_v8_minimal "$REPO_ROOT")"

rm -rf "$OUT"
mkdir -p "$OUT/include/linux"

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

t1s_note "Built shared OA-TC6 module:"
t1s_note "  $OUT/oa_tc6.ko"
t1s_note "Vendor T1S drivers can now build against:"
t1s_note "  $OUT/include/linux/oa_tc6.h"
t1s_note "  $OUT/Module.symvers"
