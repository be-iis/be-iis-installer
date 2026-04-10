#!/usr/bin/env bash

set -e

if [ -f /boot/firmware/config.txt ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
else
    CONFIG_FILE="/boot/config.txt"
fi

echo "[SETUP] Checking I2C VC (i2c_vc)"

# Check if parameter already exists
if grep -q "^dtparam=i2c_vc=on" "$CONFIG_FILE"; then
    echo "[INFO] i2c_vc already enabled"
else
    echo "[SETUP] Enabling i2c_vc in $CONFIG_FILE"
    echo "dtparam=i2c_vc=on" | sudo tee -a "$CONFIG_FILE"
    REBOOT_REQUIRED=1
fi

# Optional: ensure module is loaded (best effort)
if ! lsmod | grep -q i2c; then
    echo "[INFO] Loading i2c-dev module"
    sudo modprobe i2c-dev || true
fi

# Show current I2C buses
echo "[INFO] Available I2C buses:"
i2cdetect -l || true

# Final message
if [ "$REBOOT_REQUIRED" = "1" ]; then
    echo "[WARN] Reboot required for i2c_vc to take effect"
else
    echo "[INFO] No reboot required"
fi