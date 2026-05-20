# BE-IIS HPP CAN FD SIC Scripts

Utility scripts for testing and configuring the BE-IIS HPP CAN FD SIC board.

# Files

- [`canperf.py`](./canperf.py)  
  CAN / CAN-FD TX and RX performance test tool.

- [`config_classic_can.sh`](./config_classic_can.sh)  
  Configure Classic CAN.

- [`config_1M_can.sh`](./config_1M_can.sh)  
  Configure 1 MBit CAN.

- [`config_5M_can.sh`](./config_5M_can.sh)  
  Configure CAN-FD with 5 MBit data phase.

- [`config_7M_can.sh`](./config_7M_can.sh)  
  Configure CAN-FD with 7 MBit data phase.

- [`config_8M_can.sh`](./config_8M_can.sh)  
  Configure CAN-FD with 8 MBit data phase.

- [`test.py`](./test.py)  
  Simple CAN communication test.

# Examples

Configure CAN-FD 5 MBit:

```sh
./config_5M_can.sh
```

CAN-FD TX test:

```sh
./canperf.py tx -i beiis-can0 --size 64 --time 10
```

CAN-FD RX test:

```sh
./canperf.py rx -i beiis-can0
```

Classic CAN test:

```sh
./config_classic_can.sh
./canperf.py tx -i beiis-can0 --classic --size 8 --time 10
```

CAN-FD test using can-utils:

```sh
cangen beiis-can0 -g 0 -L 64 -f -b
```

Receive with:

```sh
candump beiis-can0
```

# Notes

- CAN-FD uses MTU 72
- Classic CAN uses MTU 16
- `can-utils` is recommended for additional testing
- ~3.5 MBit/s effective CAN-FD payload throughput is realistic on Raspberry Pi with MCP2518FD over SPI

