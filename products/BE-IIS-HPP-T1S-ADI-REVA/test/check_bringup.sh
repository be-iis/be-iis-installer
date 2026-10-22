#!/usr/bin/env bash
# Read-only ADIN1140 discovery and driver-binding inspection.
set -euo pipefail
echo "========== SYSTEM =========="
uname -a
echo "========== HAT EEPROM =========="
for key in product vendor product_id product_ver; do
    file="/proc/device-tree/hat/$key"
    if [[ -r "$file" ]]; then
        printf '%s: ' "$key"
        tr -d '\0' < "$file"
        printf '\n'
    fi
done
echo "========== HAT++ BOOT SERVICE =========="
journalctl -b -u be-iis-hatpp.service --no-pager -n 50 || true
echo "========== SPI DEVICES =========="
for dev in /sys/bus/spi/devices/*; do
    [[ -d "$dev" ]] || continue
    echo "-- ${dev##*/} --"
    [[ -r "$dev/modalias" ]] && cat "$dev/modalias"
    if [[ -L "$dev/driver" ]]; then
        echo "Driver: $(basename "$(readlink -f "$dev/driver")")"
    else
        echo "Driver: unbound"
    fi
    if [[ -r "$dev/of_node/compatible" ]]; then
        printf 'DT compatible: '
        tr '\0' ' ' < "$dev/of_node/compatible"
        printf '\n'
    fi
done
echo "========== MODULES =========="
for mod in oa_tc6 adin1140 adin1140-phy; do
    modinfo -k "$(uname -r)" -F filename "$mod" 2>&1 || true
done
lsmod | grep -E 'oa_tc6|adin1140' || true
echo "========== NETWORK =========="
ip -br link
echo "========== KERNEL LOG =========="
dmesg 2>/dev/null | grep -Ei 'adin1140|ad3306|oa.tc6|spi0' | tail -60 || true
