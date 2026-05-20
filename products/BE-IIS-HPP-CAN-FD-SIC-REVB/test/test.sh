#!/usr/bin/env bash
set -euo pipefail

IFACE="beiis-can0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/../scripts"

usage() {
    echo "Usage: $0 -s | -c"
    echo
    echo "  -s   Server / receiver"
    echo "  -c   Client / sender"
    exit 1
}

MODE=""

while getopts "sc" opt; do
    case "$opt" in
        s) MODE="server" ;;
        c) MODE="client" ;;
        *) usage ;;
    esac
done

[ -n "$MODE" ] || usage

echo "[INFO] Configure CAN-FD 8 MBit"
"$SCRIPTS_DIR/config_8M_can.sh"

if [ "$MODE" = "server" ]; then
    echo "[INFO] Start receiver"
    "$SCRIPTS_DIR/canperf.py" rx -i "$IFACE"
fi

if [ "$MODE" = "client" ]; then
    echo "[INFO] Start sender"
    "$SCRIPTS_DIR/canperf.py" tx -i "$IFACE" --size 64 --time 10
fi
