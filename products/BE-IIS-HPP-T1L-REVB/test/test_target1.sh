#!/usr/bin/env bash

set -e

IFACE="beiis-t1l0"
IP="10.10.10.1"
PEER_IP="10.10.10.2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Generate random locally administered MAC ---
RAND_MAC=$(printf '02:%02x:%02x:%02x:%02x:%02x\n' \
  $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) \
  $((RANDOM%256)) $((RANDOM%256)))

echo "[TEST] Set random MAC: $RAND_MAC"
sudo ip link set "$IFACE" down
sudo ip link set "$IFACE" address "$RAND_MAC"
sudo ip link set "$IFACE" up

echo "[TEST] Configure IP"
"$SCRIPT_DIR/../../../scripts/net/set_static_ip.sh" "$IFACE" "$IP"

echo "[TEST] Ping peer"
ping -c 10 -W 1 "$PEER_IP"

echo "[TEST] TCP iperf"
iperf3 -c "$PEER_IP" -t 10

echo "[TEST] UDP iperf (10 Mbit)"
iperf3 -c "$PEER_IP" -u -b 10M -t 10

echo "[TEST] SUCCESS"