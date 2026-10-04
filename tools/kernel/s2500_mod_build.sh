#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/t1s_source_common.sh"

KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"
TC6="$REPO_ROOT/build/oa_tc6"
OUT="$REPO_ROOT/build/s2500"

[[ -d "$KDIR" ]] || t1s_die "Kernel headers not found: $KDIR"

# Skip the external build when the running kernel already provides the
# driver. FORCE_BUILD=1 is intended for development and compatibility tests.
if modinfo s2500 >/dev/null 2>&1 && [[ "${FORCE_BUILD:-0}" != "1" ]]; then
    t1s_note "Running kernel already provides s2500."
    t1s_note "Use FORCE_BUILD=1 to build the external S2500 module anyway."
    exit 0
fi

if [[ "${FORCE_BUILD:-0}" == "1" ]]; then
    t1s_note "FORCE_BUILD=1: building external S2500 module even if the kernel provides one."
fi

t1s_ensure_tc6_build "$REPO_ROOT"
SRC="$(t1s_prepare_s2500_v8_minimal "$REPO_ROOT")"

rm -rf "$OUT"
mkdir -p "$OUT"

cp "$SRC/drivers/net/ethernet/onsemi/s2500/s2500_main.c" "$OUT/"
cp "$SRC/drivers/net/ethernet/onsemi/s2500/s2500_ethtool.c" "$OUT/"
cp "$SRC/drivers/net/ethernet/onsemi/s2500/s2500_ptp.c" "$OUT/"
cp "$SRC/drivers/net/ethernet/onsemi/s2500/s2500_hw_def.h" "$OUT/"
cp "$SRC/drivers/net/phy/ncn26000.c" "$OUT/"

# ncn26000.c uses the OPEN Alliance PHY register definitions as a local
# driver header. Fetch it from the same pinned upstream baseline.
t1s_fetch_upstream_file "$S2500_BASE_COMMIT" \
    "drivers/net/phy/mdio-open-alliance.h" "$OUT/mdio-open-alliance.h" ||
    t1s_die "Could not fetch mdio-open-alliance.h"

cp "$TC6/include/linux/oa_tc6.h" "$OUT/oa_tc6_local.h"

# Every S2500 translation unit reaches OA-TC6 through s2500_hw_def.h. Rewrite
# all copied sources and headers so an older kernel header can never leak into
# the external build.
for src in "$OUT"/s2500_main.c "$OUT"/s2500_ethtool.c "$OUT"/s2500_ptp.c "$OUT"/s2500_hw_def.h; do
    sed -i 's@#include <linux/oa_tc6.h>@#include "oa_tc6_local.h"@' "$src"
done

HEADER_BASE="/usr/src/linux-headers-${KVER%%-rpi-*}-common-rpi/include/linux"
NETDEV_H="$KDIR/include/linux/netdevice.h"
[[ -f "$NETDEV_H" ]] || NETDEV_H="$HEADER_BASE/netdevice.h"
[[ -f "$NETDEV_H" ]] || t1s_die "Could not locate target netdevice.h"

if ! grep -q 'ndo_set_rx_mode_async' "$NETDEV_H"; then
    t1s_warn "Target kernel has no ndo_set_rx_mode_async; adding legacy workqueue compatibility."
    python3 - "$OUT/s2500_main.c" "$OUT/s2500_hw_def.h" <<'PY'
from pathlib import Path
import sys

main = Path(sys.argv[1])
hdr = Path(sys.argv[2])
s = main.read_text()
h = hdr.read_text()

# Store a bounded multicast snapshot in private state. The legacy NDO runs
# under the netdev address lock and cannot perform sleeping SPI transfers.
member_marker = "	struct oa_tc6 *tc6;\n"
member_patch = """	struct oa_tc6 *tc6;
	struct work_struct rx_mode_work;
	spinlock_t rx_mode_lock;
	unsigned int rx_mode_flags;
	u8 rx_mode_mc_count;
	bool rx_mode_mc_overflow;
	u8 rx_mode_mc[S2500_N_MCAST_FILTERS][ETH_ALEN];
"""
if member_marker not in h:
    raise SystemExit("Could not locate S2500 private-state insertion point")
h = h.replace(member_marker, member_patch, 1)

func_start = s.index("static int s2500_set_rx_mode(struct net_device *ndev,")
func_end = s.index("\nstatic int s2500_set_mac_address", func_start)

compat = r'''
static int s2500_set_multicast_snapshot(struct s2500_info *priv,
                                        unsigned int rx_flags,
                                        const u8 mc[][ETH_ALEN],
                                        u8 mc_count, bool mc_overflow)
{
	u8 mms = OA_TC6_MAC_MMS1;
	int i, ret = 0;
	u16 addr;
	u32 val;

	if ((rx_flags & IFF_ALLMULTI) || mc_overflow ||
	    mc_count > S2500_N_MCAST_FILTERS) {
		ret = s2500_mac_ctrl_modify_bits(priv, S2500_MAC_CTRL_MCSF, true);
		if (ret)
			return ret;

		addr = S2500_REG_MAC_ADDRMASKL(1);
		ret = oa_tc6_write_register_mms(priv->tc6, mms, addr, 0);
		if (ret)
			return ret;

		addr = S2500_REG_MAC_ADDRMASKH(1);
		ret = oa_tc6_write_register_mms(priv->tc6, mms, addr, 0x100);
		if (ret)
			return ret;

		addr = S2500_REG_MAC_ADDRFILTL(1);
		ret = oa_tc6_write_register_mms(priv->tc6, mms, addr, 0);
		if (ret)
			return ret;

		val = S2500_MAC_ADDRFILT_ENABLE | 0x00000100;
		addr = S2500_REG_MAC_ADDRFILTH(1);
		return oa_tc6_write_register_mms(priv->tc6, mms, addr, val);
	}

	if (mc_count == 0) {
		ret = s2500_mac_ctrl_modify_bits(priv, S2500_MAC_CTRL_MCSF, false);
		if (ret)
			return ret;

		for (i = 1; i <= S2500_N_MCAST_FILTERS; i++) {
			addr = S2500_REG_MAC_ADDRFILTH(i);
			ret = oa_tc6_write_register_mms(priv->tc6, mms, addr, 0);
			if (ret)
				return ret;
		}
		return 0;
	}

	ret = s2500_mac_ctrl_modify_bits(priv, S2500_MAC_CTRL_MCSF, true);
	if (ret)
		return ret;

	for (i = 1; i <= S2500_N_MCAST_FILTERS; i++) {
		addr = S2500_REG_MAC_ADDRFILTH(i);
		ret = oa_tc6_write_register_mms(priv->tc6, mms, addr, 0);
		if (ret)
			return ret;
	}

	for (i = 0; i < mc_count; i++) {
		int slot = i + 1;
		u32 addrh = S2500_MAC_ADDRFILT_ENABLE |
			    get_unaligned_be16(mc[i]);
		u32 addrl = get_unaligned_be32(&mc[i][2]);

		addr = S2500_REG_MAC_ADDRFILTH(slot);
		ret = oa_tc6_write_register_mms(priv->tc6, mms, addr, addrh);
		if (ret)
			return ret;

		addr = S2500_REG_MAC_ADDRFILTL(slot);
		ret = oa_tc6_write_register_mms(priv->tc6, mms, addr, addrl);
		if (ret)
			return ret;

		addr = S2500_REG_MAC_ADDRMASKL(slot);
		ret = oa_tc6_write_register_mms(priv->tc6, mms, addr, 0xffffffff);
		if (ret)
			return ret;

		addr = S2500_REG_MAC_ADDRMASKH(slot);
		ret = oa_tc6_write_register_mms(priv->tc6, mms, addr, 0xffff);
		if (ret)
			return ret;
	}

	return 0;
}

static void s2500_rx_mode_work(struct work_struct *work)
{
	struct s2500_info *priv =
		container_of(work, struct s2500_info, rx_mode_work);
	u8 mc[S2500_N_MCAST_FILTERS][ETH_ALEN];
	unsigned long irq_flags;
	unsigned int rx_flags;
	bool overflow;
	u8 count;

	spin_lock_irqsave(&priv->rx_mode_lock, irq_flags);
	rx_flags = priv->rx_mode_flags;
	count = priv->rx_mode_mc_count;
	overflow = priv->rx_mode_mc_overflow;
	memcpy(mc, priv->rx_mode_mc, sizeof(mc));
	spin_unlock_irqrestore(&priv->rx_mode_lock, irq_flags);

	if (s2500_set_promiscuous_mode(priv, rx_flags))
		return;

	s2500_set_multicast_snapshot(priv, rx_flags, mc, count, overflow);
}

static void s2500_set_rx_mode_legacy(struct net_device *ndev)
{
	struct s2500_info *priv = netdev_priv(ndev);
	struct netdev_hw_addr *ha;
	unsigned long irq_flags;
	u8 count = 0;
	bool overflow = false;

	/*
	 * ndo_set_rx_mode() on legacy kernels may run in atomic context.
	 * Snapshot the address list while it is protected and defer all OA-TC6
	 * register accesses to the workqueue.
	 */
	spin_lock_irqsave(&priv->rx_mode_lock, irq_flags);
	priv->rx_mode_flags = ndev->flags;

	netdev_for_each_mc_addr(ha, ndev) {
		if (count < S2500_N_MCAST_FILTERS)
			ether_addr_copy(priv->rx_mode_mc[count++], ha->addr);
		else
			overflow = true;
	}

	priv->rx_mode_mc_count = count;
	priv->rx_mode_mc_overflow = overflow;
	spin_unlock_irqrestore(&priv->rx_mode_lock, irq_flags);

	schedule_work(&priv->rx_mode_work);
}
'''

# Keep the upstream async implementation in the source, but mark it unused on
# legacy kernels and add the compatibility implementation directly after it.
original = s[func_start:func_end]
original = original.replace("static int s2500_set_rx_mode(",
                            "static __maybe_unused int s2500_set_rx_mode(", 1)
s = s[:func_start] + original + compat + s[func_end:]

old_op = "	.ndo_set_rx_mode_async = s2500_set_rx_mode,\n"
new_op = "	.ndo_set_rx_mode       = s2500_set_rx_mode_legacy,\n"
if old_op not in s:
    raise SystemExit("Could not locate S2500 async RX-mode callback")
s = s.replace(old_op, new_op, 1)

init_marker = "	mutex_init(&priv->ptp_adj_lock);\n"
init_patch = """	mutex_init(&priv->ptp_adj_lock);
	spin_lock_init(&priv->rx_mode_lock);
	INIT_WORK(&priv->rx_mode_work, s2500_rx_mode_work);
"""
if init_marker not in s:
    raise SystemExit("Could not locate S2500 work initialization point")
s = s.replace(init_marker, init_patch, 1)

# Cancel compatibility work before the device-private state can disappear.
remove_marker = "	unregister_netdev(ndev);\n"
if remove_marker in s:
    s = s.replace(remove_marker,
                  "	cancel_work_sync(&priv->rx_mode_work);\n" + remove_marker,
                  1)

main.write_text(s)
hdr.write_text(h)
PY
fi

cat > "$OUT/Makefile" <<'EOF'
obj-m := s2500.o ncn26000.o
s2500-y := s2500_main.o s2500_ethtool.o s2500_ptp.o
ccflags-y += -I$(M)
EOF

TC6_MAKE_ARGS=()
if [[ -f "$TC6/.external" ]]; then
    TC6_MAKE_ARGS+=(KBUILD_EXTRA_SYMBOLS="$TC6/Module.symvers")
fi

make -C "$KDIR" M="$OUT" "${TC6_MAKE_ARGS[@]}" modules ||
    t1s_die "S2500 build failed against shared OA-TC6 baseline"

[[ -f "$OUT/s2500.ko" ]] || t1s_die "s2500.ko was not created"
[[ -f "$OUT/ncn26000.ko" ]] || t1s_die "ncn26000.ko was not created"

t1s_note "Built S2500 modules in $OUT"
