#!/bin/bash
set -e

for eep in \
    /sys/bus/i2c/devices/0-0060/eeprom \
    /sys/bus/i2c/devices/0-0070/eeprom \
    /sys/bus/i2c/devices/0-0074/eeprom \
    /sys/bus/i2c/devices/0-0076/eeprom
do
    if [ -e "$eep" ]; then
        echo "Checking EEPROM: $eep"

        overlay="$(eepdump "$eep" 2>/dev/null | awk -F'"' '/^dt_blob /{print $2}')"

        if [ -n "$overlay" ]; then
            echo "  -> Applying overlay: $overlay"
            dtoverlay "$overlay"
        else
            echo "  -> No dt_blob found"
        fi
    fi
done


# =========================
# Load required kernel modules
# =========================

echo "Loading BE-IIS kernel modules..."

modules=(
    lan865x      # T1S
    microchip_t1s
    oa_tc6
    adin1110     # T1L
    ks8851       # Ethernet
    mcp251xfd    # CAN FD
    sc16is7xx    # UART
)

for mod in "${modules[@]}"; do
    if modinfo "$mod" >/dev/null 2>&1; then
        echo "  -> modprobe $mod"
        modprobe "$mod" || true
    else
        echo "  -> module not found: $mod"
    fi
done

echo "Done."