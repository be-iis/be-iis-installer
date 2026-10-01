#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/t1s_source_common.sh"

KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"
[[ -d "$KDIR" ]] || t1s_die "Kernel headers not found: $KDIR"

if modinfo s2500 >/dev/null 2>&1; then
    t1s_note "Running kernel already provides s2500."
    exit 0
fi

t1s_warn "S2500 missing; fetching the upstream S2500 v8 source set."
SRC="$(t1s_prepare_source "$REPO_ROOT" s2500 "$KVER")"
OUT="$REPO_ROOT/build/s2500"
rm -rf "$OUT"; mkdir -p "$OUT/include/linux"

cp "$SRC/include/linux/oa_tc6.h" "$OUT/include/linux/"
cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6.c" "$OUT/oa_tc6_core.c"
cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6_ptp.c" "$OUT/"
cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6_tstamp.c" "$OUT/"
cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6_std_def.h" "$OUT/"
cp "$SRC/drivers/net/ethernet/onsemi/s2500/s2500_main.c" "$OUT/"
cp "$SRC/drivers/net/ethernet/onsemi/s2500/s2500_ethtool.c" "$OUT/"
cp "$SRC/drivers/net/ethernet/onsemi/s2500/s2500_ptp.c" "$OUT/"
cp "$SRC/drivers/net/ethernet/onsemi/s2500/s2500_hw_def.h" "$OUT/"
cp "$SRC/drivers/net/phy/ncn26000.c" "$OUT/"

cat > "$OUT/Makefile" <<'EOF'
obj-m := oa_tc6.o s2500.o ncn26000.o
oa_tc6-y := oa_tc6_core.o oa_tc6_ptp.o oa_tc6_tstamp.o
s2500-y := s2500_main.o s2500_ethtool.o s2500_ptp.o
ccflags-y += -I$(M)/include
EOF

make -C "$KDIR" M="$OUT" modules || t1s_die "Build failed; update the Raspberry Pi kernel rather than mixing an older OA-TC6 API."
t1s_note "Built modules in $OUT"
