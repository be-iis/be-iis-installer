#!/bin/bash
set -e

for eep in \
    /sys/bus/i2c/devices/0-0060/eeprom \
    /sys/bus/i2c/devices/0-0070/eeprom \
    /sys/bus/i2c/devices/0-0074/eeprom \
    /sys/bus/i2c/devices/0-0076/eeprom
do
    if [ -e "$eep" ]; then
        overlay="$(eepdump "$eep" | awk -F'"' '/^dt_blob /{print $2}')"
        [ -n "$overlay" ] && dtoverlay "$overlay"
    fi
done