#!/usr/bin/env bash
# Generate the final compatibility report after OA-TC6 and all MAC-PHY groups.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"
OUT="$ROOT/build/t1s-unified"
HEADER_BASE="/usr/src/linux-headers-${KVER%%-rpi-*}-common-rpi/include/linux"
PHY_H="$KDIR/include/linux/phy.h"
NETDEV_H="$KDIR/include/linux/netdevice.h"
[[ -f "$PHY_H" ]] || PHY_H="$HEADER_BASE/phy.h"
[[ -f "$NETDEV_H" ]] || NETDEV_H="$HEADER_BASE/netdevice.h"
[[ -f "$PHY_H" && -f "$NETDEV_H" ]] || { echo "ERROR: target kernel headers unavailable" >&2; exit 1; }

python3 "$ROOT/scripts/check_t1s_stack.py" "$OUT"

source_record() {
    local target record
    target="$1"
    record="$ROOT/build/t1s-source/source-${target}.env"
    if [[ -r "$record" ]]; then
        # Generated locally by t1s_source_common.sh with shell-quoted values.
        # shellcheck disable=SC1090
        source "$record"
        printf '  %s: %s (%s)\n' "$target" "$BASELINE" "$DETAIL"
    else
        printf '  %s: source provenance record unavailable\n' "$target"
    fi
}

REPORT="$OUT/compatibility-report.txt"
{
    printf 'BE-IIS unified T1S compatibility report\n'
    printf 'Kernel: %s\n\n' "$KVER"
    printf '[SOURCE] Driver baseline and provenance\n'
    source_record lan865x; source_record adin1140; source_record s2500
    printf '  Target ABI: Raspberry Pi kernel headers %s\n\n' "$KVER"
    printf '[INFO] OA-TC6 provider\n'
    printf '  oa_tc6.ko is built first as an independent module from the S2500 v8 source series.\n'
    printf '  ADIN1140, onsemi/NCN26000 and Microchip/LAN865x build against its Module.symvers.\n\n'
    printf '[COMPAT] LAN865x source API\n'
    printf '  Source expectation: legacy oa_tc6_init(spi, netdev).\n'
    printf '  Target implementation: oa_tc6_init(spi, netdev, NULL) for the S2500-v8 provider API.\n'
    printf '  Resulting function level: normal LAN865x network operation is retained.\n\n'
    if ! grep -q 'ndo_set_rx_mode_async' "$NETDEV_H"; then
        printf '[COMPAT] ADIN1140 and S2500 receive filter updates\n'
        printf '  Workqueue compatibility replaces the newer asynchronous netdev callback.\n'
        printf '  Resulting function level: filters are retained; updates take a short moment.\n\n'
    fi
    if ! grep -q 'genphy_read_mmd_c45' "$PHY_H"; then
        printf '[COMPAT] Direct Clause-45 MDIO access\n'
        printf '  Local mdiobus_c45 read/write wrappers replace the newer generic helpers.\n'
        printf '  Resulting function level: equivalent register access.\n\n'
    fi
    if ! grep -q 'genphy_loopback_fixed_speed' "$PHY_H"; then
        printf '[COMPAT] NCN26000 PHY loopback callback\n'
        printf '  Generic genphy_loopback replaces the fixed-speed helper.\n'
        printf '  Resulting function level: normal networking retained; validate specialised loopback tests.\n\n'
    fi
    if ! grep -q 'genphy_c45_oatc14_get_sqi' "$PHY_H"; then
        printf '[RESTRICTED] OATC14 cable diagnostics and Signal Quality Indicator\n'
        printf '  Affected: Microchip LAN865x PHY and onsemi NCN26000 PHY.\n'
        printf '  Unavailable: ethtool cable-test callbacks and SQI/SQI-max reporting.\n'
        printf '  Normal 10BASE-T1S network operation is unaffected.\n'
    else
        printf '[PASS] OATC14 diagnostics and SQI callbacks are available from the target kernel.\n'
    fi
} > "$REPORT"
cat "$REPORT"
