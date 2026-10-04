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

# Skip the external build when the running kernel already provides the
# driver. FORCE_BUILD=1 is intended for development and compatibility tests.
if modinfo lan865x >/dev/null 2>&1 && [[ "${FORCE_BUILD:-0}" != "1" ]]; then
    t1s_note "Running kernel already provides lan865x."
    t1s_note "Use FORCE_BUILD=1 to build the external LAN865x module anyway."
    exit 0
fi

if [[ "${FORCE_BUILD:-0}" == "1" ]]; then
    t1s_note "FORCE_BUILD=1: building external LAN865x module even if the kernel provides one."
fi

t1s_ensure_tc6_build "$REPO_ROOT"

rm -rf "$OUT"
mkdir -p "$OUT"

# Keep the Microchip driver source independent from the onsemi patch tree.
# Use the same upstream base commit as the shared OA-TC6/S2500 baseline.
t1s_note "Fetching LAN865x sources from $S2500_BASE_COMMIT."
t1s_fetch_upstream_file "$S2500_BASE_COMMIT" \
    "drivers/net/ethernet/microchip/lan865x/lan865x.c" "$OUT/lan865x.c" ||
    t1s_die "Could not fetch lan865x.c"
t1s_fetch_upstream_file "$S2500_BASE_COMMIT" \
    "drivers/net/phy/microchip_t1s.c" "$OUT/microchip_t1s.c" ||
    t1s_die "Could not fetch microchip_t1s.c"

cp "$TC6/include/linux/oa_tc6.h" "$OUT/oa_tc6_local.h"
sed -i 's@#include <linux/oa_tc6.h>@#include "oa_tc6_local.h"@' "$OUT/lan865x.c"

# Older kernels may lack the generic direct Clause 45 helpers introduced in
# 2026. Detect the target PHY API and provide local wrappers only when needed.
HEADER_BASE="/usr/src/linux-headers-${KVER%%-rpi-*}-common-rpi/include/linux"
PHY_H="$KDIR/include/linux/phy.h"
[[ -f "$PHY_H" ]] || PHY_H="$HEADER_BASE/phy.h"
[[ -f "$PHY_H" ]] || t1s_die "Could not locate target phy.h"

if ! grep -q 'genphy_read_mmd_c45' "$PHY_H"; then
    t1s_warn "Target kernel lacks genphy_*_mmd_c45 helpers; using local direct-C45 wrappers."
    python3 - "$OUT/microchip_t1s.c" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
marker = '#define LAN867X_REG_STS2 0x0019\\n'
wrapper = r'''#define LAN867X_REG_STS2 0x0019

static int microchip_t1s_read_mmd_c45(struct phy_device *phydev, int devnum,
                                      u16 regnum)
{
    return mdiobus_c45_read(phydev->mdio.bus, phydev->mdio.addr,
                            devnum, regnum);
}

static int microchip_t1s_write_mmd_c45(struct phy_device *phydev, int devnum,
                                       u16 regnum, u16 val)
{
    return mdiobus_c45_write(phydev->mdio.bus, phydev->mdio.addr,
                             devnum, regnum, val);
}
'''
if marker not in s:
    raise SystemExit('Could not locate Microchip PHY insertion point')
s = s.replace(marker, wrapper, 1)
s = s.replace('.read_mmd           = genphy_read_mmd_c45,',
              '.read_mmd           = microchip_t1s_read_mmd_c45,')
s = s.replace('.write_mmd          = genphy_write_mmd_c45,',
              '.write_mmd          = microchip_t1s_write_mmd_c45,')
p.write_text(s)
PY
fi

cat > "$OUT/Makefile" <<'EOF'
obj-m := lan865x.o microchip_t1s.o
ccflags-y += -I$(M)
EOF

make -C "$KDIR" M="$OUT"     KBUILD_EXTRA_SYMBOLS="$TC6/Module.symvers"     modules || t1s_die "LAN865x build failed against shared OA-TC6 baseline"

[[ -f "$OUT/lan865x.ko" ]] || t1s_die "lan865x.ko was not created"
[[ -f "$OUT/microchip_t1s.ko" ]] || t1s_die "microchip_t1s.ko was not created"

t1s_note "Built LAN865x modules in $OUT"
