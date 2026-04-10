#!/usr/bin/env bash

set -e

IFACE="beiis-lan0"
IP="100.100.100.1"
PEER_IP="100.100.100.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[TEST] Configure static IP on $IFACE"
"$SCRIPT_DIR/../../../scripts/net/set_static_ip.sh" "$IFACE" "$IP"

if ! command -v iperf3 >/dev/null 2>&1; then
    echo "[SETUP] Installing iperf3"
    sudo apt update
    sudo apt install -y iperf3
fi

echo "[TEST] Ping peer ($PEER_IP)"
ping -c 10 -W 1 "$PEER_IP"

echo "[TEST] Run TCP iperf3"
iperf3 -c "$PEER_IP" -t 10

echo "[TEST] Run UDP iperf3"
for rate in 5 10 15 16 17 18 19 20; do
    echo "[TEST] UDP rate: ${rate} Mbit/s"
    iperf3 -c "$PEER_IP" -u -b "${rate}M" -t 10
done

echo "[TEST] SUCCESS"