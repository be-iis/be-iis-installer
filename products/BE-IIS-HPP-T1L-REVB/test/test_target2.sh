#!/usr/bin/env bash

set -e

IFACE="beiis-t1l0"
IP="100.100.100.2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[TEST] Configure IP"
"$SCRIPT_DIR/../../../scripts/net/set_static_ip.sh" "$IFACE" "$IP"

echo "[TEST] Start iperf3 server"
iperf3 -s