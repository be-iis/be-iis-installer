#!/usr/bin/env bash

set -e

IFACE="beiis-t1l0"
IP="100.100.100.1"
PEER_IP="100.100.100.2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[TEST] Configure IP"
"$SCRIPT_DIR/../../../scripts/net/set_static_ip.sh" "$IFACE" "$IP"

echo "[TEST] Ping peer"
ping -c 10 -W 1 "$PEER_IP"

echo "[TEST] TCP iperf"
iperf3 -c "$PEER_IP" -t 10

echo "[TEST] UDP iperf (10 Mbit)"
iperf3 -c "$PEER_IP" -u -b 10M -t 10

echo "[TEST] SUCCESS"