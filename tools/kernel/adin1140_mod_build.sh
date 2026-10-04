#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/t1s_source_common.sh"

KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"
[[ -d "$KDIR" ]] || t1s_die "Kernel headers not found: $KDIR"

if modinfo adin1140 >/dev/null 2>&1; then
    t1s_note "Running kernel already provides adin1140."
    exit 0
fi

t1s_warn "adin1140 missing; fetching a compatible upstream T1S source set."
SRC="$(t1s_prepare_source "$REPO_ROOT" adin1140 "$KVER")"
OUT="$REPO_ROOT/build/adin1140"
rm -rf "$OUT"; mkdir -p "$OUT/include/linux"

cp "$SRC/drivers/net/ethernet/adi/adin1140.c" "$OUT/"
cp "$SRC/drivers/net/phy/adin1140-phy.c" "$OUT/"
cp "$SRC/include/linux/oa_tc6.h" "$OUT/oa_tc6_local.h"
if [[ -f "$SRC/drivers/net/ethernet/oa_tc6.c" ]]; then
    cp "$SRC/drivers/net/ethernet/oa_tc6.c" "$OUT/oa_tc6_core.c"
else
    cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6.c" "$OUT/oa_tc6_core.c"
    cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6_ptp.c" "$OUT/" 2>/dev/null || true
    cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6_tstamp.c" "$OUT/" 2>/dev/null || true
    cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6_std_def.h" "$OUT/" 2>/dev/null || true
fi

# The running 6.12 kernel can already contain an older <linux/oa_tc6.h>.
# Force this out-of-tree source set to use the header from the same upstream
# revision as oa_tc6.c/adin1140.c, otherwise the OA-TC6 API is mixed.
sed -i 's@#include <linux/oa_tc6.h>@#include "oa_tc6_local.h"@' \
    "$OUT/oa_tc6_core.c" "$OUT/adin1140.c"

cat > "$OUT/Makefile" <<'EOF'
obj-m := oa_tc6.o adin1140.o adin1140-phy.o
oa_tc6-y := oa_tc6_core.o
oa_tc6-y += $(if $(wildcard $(M)/oa_tc6_ptp.c),oa_tc6_ptp.o)
oa_tc6-y += $(if $(wildcard $(M)/oa_tc6_tstamp.c),oa_tc6_tstamp.o)
ccflags-y += -I$(M)
EOF

make -C "$KDIR" M="$OUT" modules || t1s_die "Build failed; update the Raspberry Pi kernel rather than mixing an older OA-TC6 API."
t1s_note "Built modules in $OUT"
