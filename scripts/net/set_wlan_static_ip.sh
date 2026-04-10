#!/usr/bin/env bash

set -e

IFACE="$1"
SSID="$2"
IP="$3"
GW="$4"
DNS="$5"

if [ -z "$IFACE" ] || [ -z "$SSID" ] || [ -z "$IP" ]; then
    echo "Usage: $0 <interface> <ssid> <ip> [gateway] [dns]"
    echo "Example: $0 wlan0 MyWiFi 192.168.178.220/24 192.168.178.1 192.168.178.1"
    exit 1
fi

CON_NAME="$IFACE"

read -s -p "WiFi Password: " PASS
echo

echo "[INFO] Configuring WiFi: $IFACE ($SSID)"

# Create connection (ignore if exists)
sudo nmcli con add type wifi ifname "$IFACE" con-name "$CON_NAME" ssid "$SSID" 2>/dev/null || true

# Security
sudo nmcli con modify "$CON_NAME" wifi-sec.key-mgmt wpa-psk
sudo nmcli con modify "$CON_NAME" wifi-sec.psk "$PASS"

# IP config
sudo nmcli con modify "$CON_NAME" ipv4.method manual
sudo nmcli con modify "$CON_NAME" ipv4.addresses "$IP"

[ -n "$GW" ] && sudo nmcli con modify "$CON_NAME" ipv4.gateway "$GW"
[ -n "$DNS" ] && sudo nmcli con modify "$CON_NAME" ipv4.dns "$DNS"

# Bring up
sudo nmcli con up "$CON_NAME"

# Clear sensitive data
unset PASS SSID

echo "[INFO] Done."