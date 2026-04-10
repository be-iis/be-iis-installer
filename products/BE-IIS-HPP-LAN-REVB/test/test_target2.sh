#!/usr/bin/env bash

set -e

IFACE="beiis-lan0"
IP="100.100.100.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[TEST] Configure static IP on $IFACE"
"$SCRIPT_DIR/../../../scripts/net/set_static_ip.sh" "$IFACE" "$IP"

if ! command -v iperf3 >/dev/null 2>&1; then
    echo "[SETUP] Installing iperf3"
    sudo apt update
    sudo apt install -y iperf3
fi

echo "[TEST] Ping peer (100.100.100.1)"
ping -c 10 -W 1 100.100.100.1 || true

echo "[TEST] Start iperf3 server"
iperf3 -s