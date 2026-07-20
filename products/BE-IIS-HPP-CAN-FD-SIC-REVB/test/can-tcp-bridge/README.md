# CAN TCP Bridge — v0.1

Two Linux systems run the same Python program:

```text
CAN A <-> can_tcp_bridge.py ===== TCP ===== can_tcp_bridge.py <-> CAN B
```

The CAN interfaces must already be configured and up. The bridge does not set
bitrate, sample point, CAN FD data bitrate, termination, or restart policy.

## Current behavior

- Bidirectional Classical CAN and CAN FD transport
- One persistent TCP connection
- Same binary and same arguments on both sides
- Automatic TCP role: lower IPv4 address is server, higher address is client
- Bounded buffering and automatic reconnect
- Frames remain pending until the peer reports a CAN TX result and are resent after reconnect
- 128-bit frame identity (`boot_id + sequence`) and duplicate suppression
- SocketCAN transmission confirmations returned to the originating bridge
- Frames injected by the bridge are not reflected back over TCP
- Optimistic local ACK behavior: the local CAN controller is active normally

The bridge cannot decide in Python whether to set the ACK bit for one individual
CAN frame. In normal controller mode, valid local frames are ACKed by the CAN
hardware. The remote TX result is therefore diagnostic/state information and
cannot revoke a local ACK already sent.

## Start on two systems

Example addresses:

- Side A: `192.168.10.10`, peer `192.168.10.20`, CAN `can0`
- Side B: `192.168.10.20`, peer `192.168.10.10`, CAN `can0`

Side A:

```bash
./can_tcp_bridge.py 192.168.10.20 can0
```

Side B:

```bash
./can_tcp_bridge.py 192.168.10.10 can0
```

The lower IP automatically listens; the higher IP connects. TCP port `29536` is
used by default.

## Local test with two vcan interfaces

Install `can-utils`, then:

```bash
sudo modprobe vcan
sudo ip link add vcan0 type vcan
sudo ip link add vcan1 type vcan
sudo ip link set vcan0 up
sudo ip link set vcan1 up
```

Terminal 1:

```bash
./can_tcp_bridge.py 127.0.0.1 vcan0 --role server
```

Terminal 2:

```bash
./can_tcp_bridge.py 127.0.0.1 vcan1 --role client
```

Terminal 3:

```bash
candump vcan1
```

Terminal 4:

```bash
cansend vcan0 123#DEADBEEF
```

The frame should appear on `vcan1` exactly once.

## Tests

```bash
python3 -m unittest -v test_can_tcp_bridge.py
```

## Important limitations of v0.1

- Trusted network only: no authentication or encryption yet.
- TCP reconnect ambiguity is handled by duplicate suppression while the process
  remains running; restarting a peer creates a new boot ID.
- A SocketCAN `MSG_CONFIRM` means successful local transmission confirmation as
  provided by the driver/SocketCAN echo path. The program reports timeout if no
  confirmation arrives within five seconds.
- Frames queued while TCP is unavailable consume RAM up to `--queue`; newer
  frames are dropped after the limit is reached.
