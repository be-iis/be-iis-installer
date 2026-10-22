#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/t1s_source_common.sh"

KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"
[[ -d "$KDIR" ]] || t1s_die "Kernel headers not found: $KDIR"

if modinfo lan865x >/dev/null 2>&1 && modinfo microchip_t1s >/dev/null 2>&1 && modinfo oa_tc6 >/dev/null 2>&1; then
    t1s_note "Running kernel already provides lan865x, microchip_t1s and oa_tc6."
    exit 0
fi

t1s_warn "LAN865x/OA-TC6 missing; using at least the S2500-required OA-TC6 feature baseline."
SRC="$(t1s_prepare_source "$REPO_ROOT" lan865x "$KVER")"
OUT="$REPO_ROOT/build/lan865x"
rm -rf "$OUT"; mkdir -p "$OUT/include/linux"

cp "$SRC/drivers/net/ethernet/microchip/lan865x/lan865x.c" "$OUT/"
cp "$SRC/drivers/net/phy/microchip_t1s.c" "$OUT/"
cp "$SRC/include/linux/oa_tc6.h" "$OUT/include/linux/"
cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6.c" "$OUT/oa_tc6_core.c"
cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6_ptp.c" "$OUT/" 2>/dev/null || true
cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6_tstamp.c" "$OUT/" 2>/dev/null || true
cp "$SRC/drivers/net/ethernet/oa_tc6/oa_tc6_std_def.h" "$OUT/" 2>/dev/null || true

cat > "$OUT/Makefile" <<'EOF'
obj-m := oa_tc6.o lan865x.o microchip_t1s.o
oa_tc6-y := oa_tc6_core.o
oa_tc6-y += $(if $(wildcard $(M)/oa_tc6_ptp.c),oa_tc6_ptp.o)
oa_tc6-y += $(if $(wildcard $(M)/oa_tc6_tstamp.c),oa_tc6_tstamp.o)
ccflags-y += -I$(M)/include
EOF

make -C "$KDIR" M="$OUT" modules || t1s_die "Build failed; update the Raspberry Pi kernel rather than mixing an older OA-TC6 API."
t1s_note "Built modules in $OUT"
