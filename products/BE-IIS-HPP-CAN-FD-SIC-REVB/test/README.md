# Production Test

Production / delivery test for two BE-IIS HPP CAN FD SIC HATs.

The test runs between two Raspberry Pi systems with one HAT each.

# Files

- [`test.sh`](./test.sh)  
  Configures CAN-FD 8 MBit and starts the test.

# Usage

On the receiver side:

```sh
./test.sh -s
```

On the sender side:

```sh
./test.sh -c
```

# Test Setup

- Two Raspberry Pi systems
- Two BE-IIS HPP CAN FD SIC HATs
- CAN bus connected and terminated
- Scripts available in `../scripts`

# Notes

- CAN-FD data phase: 8 MBit/s
- Payload size: 64 byte
- ~3.5 MBit/s effective payload throughput is realistic
