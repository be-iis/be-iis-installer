#!/usr/bin/env bash

set -e

IFACE="$1"
IP="$2"

if [ -z "$IFACE" ] || [ -z "$IP" ]; then
    echo "Usage: $0 <interface> <ip>"
    echo "Example: $0 beiis-t1s0 100.100.100.1"
    exit 1
fi

CON_NAME="$IFACE"

echo "[INFO] Configuring interface: $IFACE with IP: $IP"

# Create connection (ignore if exists)
sudo nmcli con add type ethernet ifname "$IFACE" con-name "$CON_NAME" 2>/dev/null || true

# Configure IP
sudo nmcli con modify "$CON_NAME" \
    ipv4.addresses "$IP/24" \
    ipv4.method manual \
    ipv4.ignore-auto-dns yes

# Bring interface up
sudo nmcli con up "$CON_NAME"

echo "[INFO] Done."