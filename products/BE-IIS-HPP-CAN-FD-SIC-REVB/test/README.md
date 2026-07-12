# Production Test

Production and delivery test for two BE-IIS HPP CAN-FD-SIC HATs.

The test runs between two Raspberry Pi systems with one HAT installed on each system.

# Files

* [`test.sh`](./test.sh)
  Starts the CAN-FD transmission test as sender or receiver.

* [`../scripts/`](../scripts/)
  Contains the scripts for configuring the CAN interface and data rate.

Available configuration scripts include:

```text
canperf.py
config_1M_can.sh
config_5M_can.sh
config_7M_can.sh
config_8M_can.sh
config_classic_can.sh
README.md
```

# Test Setup

* Two Raspberry Pi systems
* Two BE-IIS HPP CAN-FD-SIC HATs
* CAN bus connected between both HATs
* CAN bus correctly terminated
* Configuration scripts available in `../scripts`

# Configuration

Before starting the test, the CAN interface must be configured on both the sender and the receiver.

Both systems must use the same CAN-FD configuration and data rate.

For an 8 Mbit/s CAN-FD data phase, run the following command on both Raspberry Pi systems:

```sh
../scripts/config_8M_can.sh
```

Other available configurations can be selected by using the corresponding script, for example:

```sh
../scripts/config_5M_can.sh
../scripts/config_7M_can.sh
```

# Usage

First, configure the CAN interface on both systems.

On the receiver side:

```sh
../scripts/config_8M_can.sh
./test.sh -s
```

On the sender side:

```sh
../scripts/config_8M_can.sh
./test.sh -c
```

Start the receiver before starting the sender.

# Notes

* CAN-FD data phase: 8 Mbit/s when using `config_8M_can.sh`
* Payload size: 64 bytes
* An effective payload throughput of approximately 3.5 Mbit/s is realistic
* Sender and receiver must use identical CAN settings

