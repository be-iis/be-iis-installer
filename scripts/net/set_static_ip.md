# Set Static IP using NetworkManager (nmcli)

## Overview

This guide shows how to assign a static IPv4 address to a network interface using `nmcli`.

Example interface:

```
beiis-t1s0
```

Example network:

```
100.100.100.0/24
```

---

## Create Connection (if not existing)

```
sudo nmcli con add type ethernet ifname beiis-t1s0 con-name beiis-t1s0
```

---

## Set Static IP

```
sudo nmcli con modify beiis-t1s0 \
  ipv4.addresses 100.100.100.1/24 \
  ipv4.method manual \
  ipv4.ignore-auto-dns yes
```

---

## Activate Connection

```
sudo nmcli con up beiis-t1s0
```

---

## Verify Configuration

```
ip addr show beiis-t1s0
```

Expected output:

```
inet 100.100.100.1/24
```

---

## Notes

* `ipv4.method manual` requires an IP address to be set at the same time
* Always set multiple parameters in a single `nmcli modify` command to avoid intermediate errors
* For isolated networks (e.g. T1S), no gateway or DNS is required

---

## Optional: Clean Setup

Remove existing connection:

```
sudo nmcli con delete beiis-t1s0
```

---

## Use Case (BE-IIS)

Typical setup:

* Host (Raspberry Pi): `100.100.100.1`
* Devices: `100.100.100.2+`

This allows:

* deterministic communication
* UDP broadcast
* no DHCP dependency


## Summary (All Commands in One)

```bash
sudo nmcli con add type ethernet ifname beiis-t1s0 con-name beiis-t1s0 2>/dev/null || true && \
sudo nmcli con modify beiis-t1s0 \
  ipv4.addresses 100.100.100.1/24 \
  ipv4.method manual \
  ipv4.ignore-auto-dns yes && \
sudo nmcli con up beiis-t1s0
```

Alternatively, use the script located in the same directory:
[set_static_ip.sh](./set_static_ip.sh)


Example:
```bash
./set_static_ip.sh beiis-t1s0 100.100.100.1
```

### Notes

* The `con add` command is ignored if the connection already exists
* All IPv4 settings are applied in a single step (required by NetworkManager)
* This is safe to run multiple times

