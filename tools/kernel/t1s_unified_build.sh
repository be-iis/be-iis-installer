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

# Linux v7.2's LAN865x source predates the OA-TC6 init callback argument
# used by the unified S2500 provider. Adapt only that old source form.
python3 - "$OUT/lan865x.c" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
src = path.read_text()
old_call = "oa_tc6_init(spi, netdev);"
if old_call in src:
    init_work = "\tINIT_WORK(&priv->multicast_work, lan865x_multicast_work_handler);"
    if init_work not in src:
        raise SystemExit("Missing LAN865x probe initialization marker")
    src = src.replace(
        init_work,
        init_work + "\n\n\tnetdev->netdev_ops = &lan865x_netdev_ops;",
        1,
    )
    src = src.replace(old_call, "oa_tc6_init(spi, netdev, NULL);", 1)
    assignment = "\tnetdev->netdev_ops = &lan865x_netdev_ops;\n"
    first = src.find(assignment)
    duplicate = src.find(assignment, first + len(assignment))
    if duplicate >= 0:
        src = src[:duplicate] + src[duplicate + len(assignment):]
    print("Adapted legacy LAN865x source to the unified OA-TC6 init API")
else:
    print("LAN865x source already uses the unified OA-TC6 init API")
path.write_text(src)
PY

# Linux 6.12 lacks the newer OA TC14 cable diagnostic helpers and
# generic Clause-45 PHY callbacks used by the upstream Microchip PHY.
HEADER_BASE="/usr/src/linux-headers-${KVER%%-rpi-*}-common-rpi/include/linux"
PHY_H="$KDIR/include/linux/phy.h"
NETDEV_H="$KDIR/include/linux/netdevice.h"
[[ -f "$PHY_H" ]] || PHY_H="$HEADER_BASE/phy.h"
[[ -f "$NETDEV_H" ]] || NETDEV_H="$HEADER_BASE/netdevice.h"
[[ -f "$PHY_H" ]] || t1s_die "Could not locate target kernel phy.h"
[[ -f "$NETDEV_H" ]] || t1s_die "Could not locate target kernel netdevice.h"

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

REPORT="$OUT/compatibility-report.txt"
{
    printf 'BE-IIS unified T1S compatibility report\n'
    printf 'Kernel: %s\n\n' "$KVER"
    printf '[INFO] OA-TC6 provider\n'
    printf '  One local OA-TC6 provider is used by LAN865x, ADIN1140 and S2500.\n'
    printf '  This avoids mixing incompatible OA-TC6 module ABIs.\n\n'

    printf '[COMPAT] LAN865x source API\n'
    printf '  Legacy LAN865x source is adapted to the current oa_tc6_init() signature.\n'
    printf '  Impact: no feature restriction; the added callback argument is NULL.\n\n'

    if ! grep -q 'ndo_set_rx_mode_async' "$NETDEV_H"; then
        printf '[COMPAT] ADIN1140 and S2500 receive filter updates\n'
        printf '  Target kernel lacks ndo_set_rx_mode_async; multicast/promiscuous filter updates run in a workqueue.\n'
        printf '  Impact: no filter feature is removed, but updates are asynchronous and may take a short moment.\n\n'
    fi

    if ! grep -q 'netns_immutable' "$NETDEV_H"; then
        printf '[COMPAT] ADIN1140 network-namespace declaration\n'
        printf '  Target kernel lacks netns_immutable; that metadata assignment is omitted.\n'
        printf '  Impact: no effect for normal Raspberry Pi networking.\n\n'
    fi

    if ! grep -A3 'set_loopback' "$PHY_H" | grep -q 'int speed'; then
        printf '[COMPAT] ADIN1140 PHY loopback callback\n'
        printf '  Target kernel uses the legacy loopback callback without a speed argument.\n'
        printf '  Impact: no expected effect for fixed-rate 10BASE-T1S; loopback is retained.\n\n'
    fi

    if ! grep -q 'genphy_read_mmd_c45' "$PHY_H"; then
        printf '[COMPAT] Direct Clause-45 MDIO access\n'
        printf '  ADIN1140, NCN26000 and Microchip PHY drivers use local mdiobus_c45 read/write wrappers.\n'
        printf '  Impact: equivalent register access; no known normal-operation restriction.\n\n'
    fi

    if ! grep -q 'phy_id_compare_model' "$PHY_H"; then
        printf '[COMPAT] NCN26000 PHY identification\n'
        printf '  Target kernel uses a legacy model-mask comparison.\n'
        printf '  Impact: no expected restriction for the NCN26000.\n\n'
    fi

    if ! grep -q 'genphy_loopback_fixed_speed' "$PHY_H"; then
        printf '[COMPAT] NCN26000 PHY loopback callback\n'
        printf '  Target kernel uses generic genphy_loopback instead of the fixed-speed helper.\n'
        printf '  Impact: normal networking is unaffected; specialised loopback validation should be checked on target hardware.\n\n'
    fi

    if ! grep -q 'genphy_c45_oatc14_get_sqi' "$PHY_H"; then
        printf '[RESTRICTED] OATC14 cable diagnostics and Signal Quality Indicator\n'
        printf '  Target kernel lacks the generic OATC14 helpers.\n'
        printf '  Affected: Microchip LAN865x PHY and onsemi NCN26000 PHY.\n'
        printf '  Unavailable: ethtool cable-test callbacks and SQI/SQI-max reporting.\n'
        printf '  Normal 10BASE-T1S network operation is unaffected.\n'
    else
        printf '[OK] OATC14 diagnostics and SQI callbacks are available from the target kernel.\n'
    fi
} > "$REPORT"

printf '\n'
cat "$REPORT"
printf '\nCompatibility report written to: %s\n' "$REPORT"
printf 'Unified T1S stack built and checked (NOT installed): %s\n' "$OUT"
