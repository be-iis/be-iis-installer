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
HEADER_BASE="/usr/src/linux-headers-${KVER%%-rpi-*}-common-rpi/include/linux"
NETDEV_H="$KDIR/include/linux/netdevice.h"
PHY_H="$KDIR/include/linux/phy.h"

[[ -f "$NETDEV_H" ]] || NETDEV_H="$HEADER_BASE/netdevice.h"
[[ -f "$PHY_H" ]] || PHY_H="$HEADER_BASE/phy.h"

[[ -f "$NETDEV_H" ]] || t1s_die "Could not locate target netdevice.h"
[[ -f "$PHY_H" ]] || t1s_die "Could not locate target phy.h"

if ! grep -q 'ndo_set_rx_mode_async' "$NETDEV_H"; then
    t1s_warn "Target kernel has no ndo_set_rx_mode_async; adding legacy workqueue compatibility."
    python3 - "$OUT/adin1140.c" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

old_member = '''\tstruct delayed_work stats_work;\n'''
new_member = '''\tstruct delayed_work stats_work;
\tstruct work_struct rx_mode_work;
'''
if old_member not in s:
    raise SystemExit('Could not locate adin1140_priv work members')
s = s.replace(old_member, new_member, 1)

rx_start = s.index('static int adin1140_rx_mode(struct net_device *dev,')
rx_end = s.index('\nstatic void adin1140_stats_work', rx_start)
rx_func = s[rx_start:rx_end]

compat = r'''
/*
 * Older kernels only provide ndo_set_rx_mode(), which is called from an
 * atomic context where SPI transfers are not allowed to sleep. Defer the
 * hardware programming to a workqueue and take stable snapshots of the
 * address lists before accessing the MAC-PHY.
 */
struct adin1140_rx_snapshot {
	u8 uc[ADIN1140_MAC_FILT_AVAIL][ETH_ALEN];
	u8 mc[ADIN1140_MAC_FILT_AVAIL][ETH_ALEN];
	u8 uc_count;
	u8 mc_count;
	bool uc_overflow;
	bool mc_overflow;
	unsigned int flags;
};

static void adin1140_rx_mode_work(struct work_struct *work)
{
	struct adin1140_priv *priv =
		container_of(work, struct adin1140_priv, rx_mode_work);
	struct adin1140_rx_snapshot snap = {};
	struct net_device *dev = priv->netdev;
	struct netdev_hw_addr *ha;
	bool all_multi, promisc;
	u32 mac_addrs;
	u8 slot, i;
	int ret;

	/*
	 * The legacy address lists are protected by addr_list_lock. Copy only
	 * the small number of addresses the hardware can actually program, then
	 * release the spinlock before issuing any sleeping OA-TC6/SPI access.
	 */
	netif_addr_lock_bh(dev);
	snap.flags = dev->flags;

	netdev_for_each_uc_addr(ha, dev) {
		if (snap.uc_count < ADIN1140_MAC_FILT_AVAIL)
			ether_addr_copy(snap.uc[snap.uc_count++], ha->addr);
		else
			snap.uc_overflow = true;
	}

	netdev_for_each_mc_addr(ha, dev) {
		if (snap.mc_count < ADIN1140_MAC_FILT_AVAIL)
			ether_addr_copy(snap.mc[snap.mc_count++], ha->addr);
		else
			snap.mc_overflow = true;
	}
	netif_addr_unlock_bh(dev);

	mac_addrs = snap.uc_count;
	all_multi = false;
	promisc = false;

	if (snap.flags & IFF_PROMISC)
		promisc = true;
	else if (snap.flags & IFF_ALLMULTI)
		all_multi = true;
	else
		mac_addrs += snap.mc_count;

	if (snap.uc_overflow || snap.mc_overflow ||
	    mac_addrs > ADIN1140_MAC_FILT_AVAIL)
		promisc = true;

	ret = adin1140_promiscuous_mode(priv, promisc);
	if (ret)
		return;

	ret = adin1140_filter_all_multicast(priv, all_multi);
	if (ret)
		return;

	slot = ADIN1140_MAC_FILT_UC_SLOT + 1;
	if (!promisc) {
		for (i = 0; i < snap.uc_count; i++) {
			ret = adin1140_mac_filter_set(priv, snap.uc[i], NULL, slot++);
			if (ret)
				return;
		}

		if (!all_multi) {
			for (i = 0; i < snap.mc_count; i++) {
				ret = adin1140_mac_filter_set(priv, snap.mc[i], NULL,
							      slot++);
				if (ret)
					return;
			}
		}
	}

	for (i = slot; i < ADIN1140_MAC_FILT_MAX_SLOT; i++) {
		ret = adin1140_mac_filter_clear(priv, i);
		if (ret)
			return;
	}
}

static void adin1140_set_rx_mode_legacy(struct net_device *dev)
{
	struct adin1140_priv *priv = netdev_priv(dev);

	schedule_work(&priv->rx_mode_work);
}
'''

s = s[:rx_end] + compat + s[rx_end:]

old_op = '\t.ndo_set_rx_mode_async = adin1140_rx_mode,\n'
new_op = '\t.ndo_set_rx_mode = adin1140_set_rx_mode_legacy,\n'
if old_op not in s:
    raise SystemExit('Could not locate ndo_set_rx_mode_async assignment')
s = s.replace(old_op, new_op, 1)

old_init = '\tINIT_DELAYED_WORK(&priv->stats_work, adin1140_stats_work);\n'
new_init = '''\tINIT_DELAYED_WORK(&priv->stats_work, adin1140_stats_work);
\tINIT_WORK(&priv->rx_mode_work, adin1140_rx_mode_work);
'''
if old_init not in s:
    raise SystemExit('Could not locate ADIN1140 work initialization')
s = s.replace(old_init, new_init, 1)

old_close = '\tcancel_delayed_work_sync(&priv->stats_work);\n'
new_close = '''\tcancel_delayed_work_sync(&priv->stats_work);
\tcancel_work_sync(&priv->rx_mode_work);
'''
if old_close not in s:
    raise SystemExit('Could not locate ADIN1140 close work cancellation')
s = s.replace(old_close, new_close, 1)

# The upstream async implementation is not referenced on legacy kernels.
s = s.replace('static int adin1140_rx_mode(struct net_device *dev,',
              'static __maybe_unused int adin1140_rx_mode(struct net_device *dev,',
              1)

p.write_text(s)
PY
fi

if ! grep -q 'netns_immutable' "$NETDEV_H"; then
    t1s_warn "Target kernel has no netns_immutable field; omitting that assignment."
    sed -i '/^[[:space:]]*netdev->netns_immutable[[:space:]]*=/d' "$OUT/adin1140.c"
fi

# Linux 6.12 uses the older PHY loopback callback without a speed argument.
if ! grep -A3 'set_loopback' "$PHY_H" | grep -q 'int speed'; then
    t1s_warn "Target kernel uses legacy PHY set_loopback callback; applying compatibility signature."
    sed -i 's/static int adin1140_loopback(struct phy_device \*phydev, bool enable, int speed)/static int adin1140_loopback(struct phy_device *phydev, bool enable)/' "$OUT/adin1140-phy.c"
    sed -i '/^[[:space:]]*if (enable && speed)$/,+1d' "$OUT/adin1140-phy.c"
fi

# genphy_{read,write}_mmd_c45 were added with the ADIN1140 series. Older
# kernels already expose mdiobus_c45_read/write, so provide tiny local wrappers.
if ! grep -q 'genphy_read_mmd_c45' "$PHY_H"; then
    t1s_warn "Target kernel lacks genphy_*_mmd_c45 helpers; using local direct-C45 wrappers."
    python3 - "$OUT/adin1140-phy.c" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
marker = '#define ADIN1140_PCS_CTRL_LOOPBACK\tBIT(14)\n'
wrapper = r'''
#define ADIN1140_PCS_CTRL_LOOPBACK	BIT(14)

static int adin1140_read_mmd_c45(struct phy_device *phydev, int devnum,
                                 u16 regnum)
{
    return mdiobus_c45_read(phydev->mdio.bus, phydev->mdio.addr,
                            devnum, regnum);
}

static int adin1140_write_mmd_c45(struct phy_device *phydev, int devnum,
                                  u16 regnum, u16 val)
{
    return mdiobus_c45_write(phydev->mdio.bus, phydev->mdio.addr,
                             devnum, regnum, val);
}
'''
if marker not in s:
    raise SystemExit('Could not locate ADIN1140 PCS define for C45 compatibility patch')
s = s.replace(marker, wrapper, 1)
s = s.replace('.read_mmd = genphy_read_mmd_c45,',
              '.read_mmd = adin1140_read_mmd_c45,')
s = s.replace('.write_mmd = genphy_write_mmd_c45,',
              '.write_mmd = adin1140_write_mmd_c45,')
p.write_text(s)
PY
fi

cat > "$OUT/Makefile" <<'EOF'
obj-m := adin1140.o adin1140-phy.o
ccflags-y += -I$(M)
EOF

make -C "$KDIR" M="$OUT"     KBUILD_EXTRA_SYMBOLS="$TC6/Module.symvers"     modules || t1s_die "ADIN1140 build failed against shared OA-TC6 baseline"

[[ -f "$OUT/adin1140.ko" ]] || t1s_die "adin1140.ko was not created"
[[ -f "$OUT/adin1140-phy.ko" ]] || t1s_die "adin1140-phy.ko was not created"

t1s_note "Built ADIN1140 modules in $OUT"
