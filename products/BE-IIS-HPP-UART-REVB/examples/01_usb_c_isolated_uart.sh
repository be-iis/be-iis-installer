#!/usr/bin/env bash
# Verify transmission over the BE-IIS-HPP-UART isolated USB-C UART.
#
# Connect the HAT USB-C connector to a PC, then open the enumerated serial
# device on that PC at 115200 baud (for example: picocom -b 115200 /dev/ttyUSB0).

set -euo pipefail

device="${1:-/dev/beiis-uart-iv-a}"
baudrate="${BAUDRATE:-115200}"

if [[ ! -c "$device" ]]; then
    echo "UART device not found: $device" >&2
    echo "Example: $0 /dev/beiis-uart-iv-a" >&2
    exit 1
fi

stty -F "$device" "$baudrate" raw -echo -ixon -ixoff

message="Hello from the Raspberry Pi via the isolated USB-C UART"
printf '%s\r\n' "$message" > "$device"

echo "Sent at $baudrate baud via $device:"
echo "  $message"
echo
echo "Open the USB serial port on the connected PC, for example:"
echo "  picocom -b $baudrate /dev/ttyUSB0"
