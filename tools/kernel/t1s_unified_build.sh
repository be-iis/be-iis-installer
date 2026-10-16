#!/usr/bin/env bash
# Build one coherent OA-TC6 stack for LAN865x, ADIN1140 and S2500.
# Build-only: never installs, loads or replaces kernel modules.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tools/kernel/t1s_source_common.sh"
KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"
OUT="$ROOT/build/t1s-unified"
[[ -d "$KDIR" ]] || t1s_die "Missing headers for $KVER"
for tool in make modinfo python3; do t1s_require "$tool"; done

# Reuse per-driver compatibility transforms, but compile all final modules
# together against ONE provider and ONE local header, not their separate ABI.
# The onsemi/ADI scripts may skip when their drivers are natively installed;
# in that case this builder deliberately requires explicit source preparation.
bash "$ROOT/tools/kernel/s2500_mod_build.sh"
bash "$ROOT/tools/kernel/adin1140_mod_build.sh"

S="$ROOT/build/s2500"
A="$ROOT/build/adin1140"
[[ -s "$S/s2500_main.c" && -s "$S/oa_tc6_core.c" && -s "$A/adin1140.c" ]] ||
  t1s_die "Required prepared S2500/ADI sources unavailable; refusing partial build"

# Microchip source must come from the pinned common baseline. Do not reuse
# the installed (potentially old) module or its Module.symvers.
SRC="$(t1s_prepare_source "$ROOT" lan865x "$KVER")"
[[ -f "$SRC/drivers/net/ethernet/microchip/lan865x/lan865x.c" ]] ||
  t1s_die "Missing LAN865x source"
[[ -f "$SRC/drivers/net/phy/microchip_t1s.c" ]] ||
  t1s_die "Missing Microchip PHY source"

rm -rf "$OUT"
mkdir -p "$OUT/include/linux"
cp "$S/include/linux/oa_tc6.h" "$OUT/include/linux/oa_tc6.h"
for f in oa_tc6_core.c oa_tc6_ptp.c oa_tc6_tstamp.c oa_tc6_std_def.h \
         oa_tc6_local.h s2500_main.c s2500_ethtool.c s2500_ptp.c \
         s2500_hw_def.h ncn26000.c mdio-open-alliance.h; do
  cp "$S/$f" "$OUT/$f"
done
for f in adin1140.c adin1140-phy.c; do cp "$A/$f" "$OUT/$f"; done
cp "$SRC/drivers/net/ethernet/microchip/lan865x/lan865x.c" "$OUT/lan865x.c"
cp "$SRC/drivers/net/phy/microchip_t1s.c" "$OUT/microchip_t1s.c"

# Force all drivers to the exact local header used by the single provider.
# Upstream code may use either include spelling.
for f in "$OUT"/*.c "$OUT"/*.h; do
  sed -i 's@#include <linux/oa_tc6.h>@#include "oa_tc6_local.h"@g' "$f"
done

cat > "$OUT/Makefile" <<'EOF'
obj-m := oa_tc6.o lan865x.o microchip_t1s.o adin1140.o adin1140-phy.o s2500.o ncn26000.o
oa_tc6-y := oa_tc6_core.o oa_tc6_ptp.o oa_tc6_tstamp.o
s2500-y := s2500_main.o s2500_ethtool.o s2500_ptp.o
ccflags-y += -I$(M)/include
EOF

make -C "$KDIR" M="$OUT" modules

python3 "$ROOT/scripts/check_t1s_stack.py" "$OUT"
printf 'Unified T1S stack built and checked (NOT installed): %s\n' "$OUT"
