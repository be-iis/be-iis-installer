#!/usr/bin/env bash
set -euo pipefail
IFACE="${1:-vcan0}"
sudo modprobe vcan
if ! ip link show "$IFACE" >/dev/null 2>&1; then
    sudo ip link add "$IFACE" type vcan
fi
sudo ip link set "$IFACE" up
ip -details link show "$IFACE"
