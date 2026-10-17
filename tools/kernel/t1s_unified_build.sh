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

# Linux 6.12 lacks the newer OA TC14 cable diagnostic helpers and
# generic Clause-45 PHY callbacks used by the upstream Microchip PHY.
PHY_H="$KDIR/include/linux/phy.h"
[[ -f "$PHY_H" ]] || PHY_H="/usr/src/linux-headers-${KVER%%-rpi-*}-common-rpi/include/linux/phy.h"
[[ -f "$PHY_H" ]] || t1s_die "Could not locate target kernel phy.h"

if ! grep -q 'genphy_c45_oatc14_get_sqi' "$PHY_H"; then
  t1s_warn "Target kernel lacks OATC14 diagnostics; disabling optional Microchip PHY callbacks."
  sed -i -E '/^[[:space:]]*\.(cable_test_start|cable_test_get_status|get_sqi|get_sqi_max)[[:space:]]*=[[:space:]]*genphy_c45_oatc14_/d' "$OUT/microchip_t1s.c"
fi

if ! grep -q 'genphy_read_mmd_c45' "$PHY_H"; then
  t1s_warn "Target kernel lacks generic direct-C45 PHY helpers; applying Microchip compatibility wrappers."
  python3 - "$OUT/microchip_t1s.c" <<'PY'
from pathlib import Path

path = Path(__import__("sys").argv[1])
src = path.read_text()
marker = "#include <linux/phy.h>"
callbacks = {
    "genphy_read_mmd_c45": "beiis_microchip_read_mmd_c45",
    "genphy_write_mmd_c45": "beiis_microchip_write_mmd_c45",
}
# Older source revisions may not reference either helper. Do not add
# unnecessary wrappers, and do not reject otherwise compatible sources.
needed = [original for original in callbacks if original in src]
if needed:
    if marker not in src:
        raise SystemExit("Missing linux/phy.h include in Microchip source")
    wrappers = """
/* Fallback for kernels lacking the direct Clause-45 PHY helpers. */
static int beiis_microchip_read_mmd_c45(struct phy_device *phydev,
                                        int devnum, u16 regnum)
{
    return mdiobus_c45_read(phydev->mdio.bus, phydev->mdio.addr,
                            devnum, regnum);
}

static int beiis_microchip_write_mmd_c45(struct phy_device *phydev,
                                         int devnum, u16 regnum, u16 val)
{
    return mdiobus_c45_write(phydev->mdio.bus, phydev->mdio.addr,
                             devnum, regnum, val);
}
"""
    src = src.replace(marker, marker + "\n" + wrappers, 1)
    import re
    for original in needed:
        src, count = re.subn(r"\b" + original + r"\b", callbacks[original], src)
        print(f"Replaced {count} references to {original}")
else:
    print("Microchip driver does not use direct-C45 helpers; no wrappers needed")
path.write_text(src)
PY
fi

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
