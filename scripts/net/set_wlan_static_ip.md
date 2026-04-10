# Set Static Wi-Fi IP using NetworkManager (nmcli)

## Overview

This guide shows how to assign a static IPv4 address to a Wi-Fi interface using `nmcli`.

Using a static IP for Wi-Fi is highly recommended for development and embedded systems.

---

## Why Static IP?

Many routers (e.g. Fritzbox) provide a DHCP range and a separate static IP range.

Using a static IP outside the DHCP pool ensures:

* the device is always reachable at the same address
* no dependency on DHCP
* easier SSH access and debugging
* predictable network behavior

Example:

* Router (DHCP): `192.168.178.20 – 200`
* Lower static range: `192.168.178.2 – 19`
* Upper static range: `192.168.178.201 – 254`

---

## Identify Wi-Fi Interface

```bash
nmcli device status
```

Example:

```bash
wlan0
```

---

## Create Wi-Fi Connection (if needed)

```bash
sudo nmcli con add type wifi ifname wlan0 con-name wlan0 ssid YOUR_SSID
```

---

## Set Wi-Fi Credentials

```bash
sudo nmcli con modify wlan0 wifi-sec.key-mgmt wpa-psk
sudo nmcli con modify wlan0 wifi-sec.psk YOUR_PASSWORD
```

---

## Set Static IP

```bash
sudo nmcli con modify wlan0 \
  ipv4.addresses 192.168.178.220/24 \
  ipv4.gateway 192.168.178.1 \
  ipv4.dns 192.168.178.1 \
  ipv4.method manual
```

---

## Wi-Fi Requirements

Before using Wi-Fi, the WLAN country must be set:

```bash
sudo raspi-config
```

Navigate to:

- 5 Localisation Options
- L4 WLAN Country

Set your region correctly.

---

Wi-Fi is blocked by default until a valid country is configured.

---

Verify:

```bash
rfkill list
nmcli device status
```

---

If Wi-Fi is still blocked:

```bash
sudo rfkill unblock wifi
```

## Activate Connection

```bash
sudo nmcli con up wlan0
```

---

## Verify Configuration

```bash
ip addr show wlan0
```

Expected output:

```bash
inet 192.168.178.10/24
```

---

## Summary (All Commands in One)

```bash
SSID="YOUR_SSID"
# PASS="YOUR_PASSWORD"
IP="192.168.178.220/24"
GW="192.168.178.1"
DNS="192.168.178.1"

read -s -p "WiFi Password: " PASS; echo
sudo nmcli con add type wifi ifname wlan0 con-name wlan0 ssid "$SSID" 2>/dev/null || true && \
sudo nmcli con modify wlan0 wifi-sec.key-mgmt wpa-psk && \
sudo nmcli con modify wlan0 wifi-sec.psk "$PASS" && \
sudo nmcli con modify wlan0 \
  ipv4.addresses "$IP" \
  ipv4.gateway "$GW" \
  ipv4.dns "$DNS" \
  ipv4.method manual && \
sudo nmcli con up wlan0

# Clear sensitive variables
unset PASS SSID
```

Alternatively, use the script located in the same directory:

[`set_wlan_static_ip.sh`](./set_wlan_static_ip.sh)

Example:
```bash
./set_wlan_static_ip.sh wlan0 MyWiFi 192.168.178.220/24 192.168.178.1 192.168.178.1
```

---

### Notes

* Credentials are stored only temporarily in shell variables
* `unset PASS` removes the password from the environment after use
* Avoid exporting (`export PASS=...`) to keep it out of child processes


---

## Notes

* Ensure the chosen IP is outside the DHCP range of your router
* Using static IPs simplifies device discovery in local networks
* Works with Fritzbox and most common routers

