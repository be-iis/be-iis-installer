#!/bin/bash
set -e

echo "BE-IIS ========================================"
echo "BE-IIS HAT++ System Integration"
echo "BE-IIS ========================================"
echo ""

echo "BE-IIS [1/2] Scanning BE-IIS HAT++ EEPROMs..."

# Instance mapping
declare -A INSTANCE_MAP=(
    ["0-0050"]="I"
    ["0-0060"]="II"
    ["0-0070"]="III"
    ["0-0074"]="IV"
    ["0-0076"]="V"
)

for eep in \
    /sys/bus/i2c/devices/0-0050/eeprom \
    /sys/bus/i2c/devices/0-0060/eeprom \
    /sys/bus/i2c/devices/0-0070/eeprom \
    /sys/bus/i2c/devices/0-0074/eeprom \
    /sys/bus/i2c/devices/0-0076/eeprom
do
    if [ -e "$eep" ]; then

        addr="$(basename "$(dirname "$eep")")"
        inst="${INSTANCE_MAP[$addr]}"

        overlay="$(eepdump "$eep" 2>/dev/null | awk -F'"' '/^dt_blob /{print $2}')"

        if [ -n "$overlay" ]; then
            if [ "$inst" = "I" ]; then
                echo "BE-IIS Instance $inst ($addr): HAT detected → $overlay"
                echo "BE-IIS Instance $inst ($addr): Base instance (overlay handled by HAT+ autodetect)"
            else
                echo "BE-IIS Instance $inst ($addr): HAT detected → $overlay"
                echo "BE-IIS Instance $inst ($addr): Applying overlay..."
                dtoverlay "$overlay"
                echo "BE-IIS Instance $inst ($addr): Overlay applied"
            fi

        else
            echo "BE-IIS Instance $inst ($addr): EEPROM present, no overlay"
        fi
    fi
done

echo ""
echo "BE-IIS [2/2] Loading BE-IIS kernel modules..."

modules=(
    lan865x
    microchip_t1s
    oa_tc6
    adin1110
    ks8851
    mcp251xfd
    sc16is7xx
    sc16is7xx_i2c
)

for mod in "${modules[@]}"; do
    if modinfo "$mod" >/dev/null 2>&1; then
        echo "BE-IIS Loading module: $mod"
        modprobe "$mod" || true
    else
        echo "BE-IIS Module not available: $mod"
    fi
done

echo ""
echo "BE-IIS HAT++ system integration complete."