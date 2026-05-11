# BE-IIS CAN / CAN-FD Test Scripts

This directory contains helper scripts for configuring and testing the CAN-FD interface of the BE-IIS CAN-FD-SIC HAT.

The setup was validated using:

- MCP2518FD CAN-FD controller
- TCAN1472 CAN-FD SIC transceiver
- Raspberry Pi
- Linux SocketCAN

Validated CAN-FD communication:

- Classic CAN: 1 MBit/s
- CAN-FD Data Phase: 5 MBit/s
- CAN-FD Data Phase: 7 MBit/s

---

# Files

| File | Description |
|---|---|
| `config_classic_can.sh` | Configure Classic CAN (1 MBit/s) |
| `config_1M_can.sh` | Configure CAN-FD with 1 MBit/s data phase |
| `config_5M_can.sh` | Configure CAN-FD with 5 MBit/s data phase |
| `config_7M_can.sh` | Configure CAN-FD with 7 MBit/s data phase |
| `test.py` | CAN / CAN-FD request-response test |

---

# Requirements

Install SocketCAN utilities:

```bash
sudo apt update
sudo apt install can-utils
```

---

# Script Permissions

Make scripts executable:

```bash
chmod +x *.sh
chmod +x test.py
```

---

# CAN Interface Configuration

Default interface:

```text
beiis-can0
```

Custom interface example:

```bash
./config_5M_can.sh can0
```

---

# Configure Classic CAN

```bash
./config_classic_can.sh
```

---

# Configure CAN-FD 1 MBit/s

```bash
./config_1M_can.sh
```

---

# Configure CAN-FD 5 MBit/s

```bash
./config_5M_can.sh
```

---

# Configure CAN-FD 7 MBit/s

```bash
./config_7M_can.sh
```

---

# CAN / CAN-FD Test

The test performs a request-response communication test between two devices.

## Start Server

On device 1:

```bash
./test.py -s
```

## Start Client

On device 2:

```bash
./test.py -c
```

The client automatically stops after 10 seconds.

---

# Classic CAN Test

Server:

```bash
./test.py -s
```

Client:

```bash
./test.py -c --classic
```

---

# Custom Test Duration

Example:

```bash
./test.py -c -t 30
```

---

# Custom Interface

Example:

```bash
./test.py -c -i can0
```

---

# Example Result

```text
=== CLIENT RESULT ===
Interface : beiis-can0
Mode      : CAN-FD
Duration  : 10.00 s
OK        : 10112
Lost      : 0
Frames/s  : 1011.1
Payload   : 0.518 MBit/s
```

---

# Notes

- Use proper CAN termination.
- Use short cables for high CAN-FD data rates.
- 7 MBit/s CAN-FD data phase was validated successfully.
- Higher data rates depend on topology, cable length and timing configuration.

---

© 2026 Brechel Electronic  
Industrial Interface Systems
