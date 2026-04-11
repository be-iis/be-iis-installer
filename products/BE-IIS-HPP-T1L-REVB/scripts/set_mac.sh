#!/usr/bin/env bash

set -e

echo "[INFO] Searching for T1L interfaces..."

# --- Generate random locally administered MAC ---
gen_mac() {
    printf '02:%02x:%02x:%02x:%02x:%02x\n' \
        $((RANDOM%256)) $((RANDOM%256)) \
        $((RANDOM%256)) $((RANDOM%256)) \
        $((RANDOM%256))
}

# --- Check possible interfaces ---
for IFACE in beiis-t1l1 beiis-t1l2 beiis-t1l3; do
    if ip link show "$IFACE" > /dev/null 2>&1; then
        NEW_MAC=$(gen_mac)

        echo "[INFO] Found $IFACE"
        echo "[INFO] Assigning MAC: $NEW_MAC"

        sudo ip link set "$IFACE" down
        sudo ip link set "$IFACE" address "$NEW_MAC"
        sudo ip link set "$IFACE" up
    fi
done

echo "[INFO] Done."