#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[TEST] Configure static IP on beiis-t1s0"
"$SCRIPT_DIR/../../scripts/net/set_static_ip.sh" beiis-t1s0 100.100.100.1

echo "[TEST] Ping peer (100.100.100.2)"
ping -c 5 -W 1 100.100.100.2

echo "[TEST] SUCCESS"