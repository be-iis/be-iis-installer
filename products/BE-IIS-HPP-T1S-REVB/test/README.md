# Network Test Setup

## Hardware Preparation

- Use two Raspberry Pis
- Install BE-IIS T1S HAT on both devices
- Set both HATs to **Instance Mode I**

### Wiring

- Connect both devices in a **point-to-point topology**
- Ensure **termination is enabled on both sides**

---

## Software Setup

Run the provided test scripts on both Raspberry Pis.

See:
[`test_target1.sh`](./test_target1.sh)  
[`test_target2.sh`](./test_target2.sh)

### Pi 1
```bash
./test_target1.sh
```

### Pi 2
```bash
./test_target2.sh
```

## Test 1: Interface Bring-up and Connectivity

### Expected Results

- Network interface is successfully configured on both devices
- Link is established between both Raspberry Pis
- Basic communication is possible
- PLCA is successfully configured on both devices

### Pass Criteria

- Interface `beiis-t1s0` is up on both devices
- IP address is correctly assigned
- Ping is successful in both directions
- No packet loss during ping test
- Round-trip time < 1 ms
- PLCA is enabled and correctly configured on both devices (verified via `ethtool --get-plca-cfg`)

---

## Test 2: Ping Latency Stability

### Expected Results

- Stable low-latency communication between both devices
- No packet loss under continuous ping

### Pass Criteria

- Continuous ping over defined duration (e.g. 30 seconds)
- 0% packet loss
- Round-trip time remains consistently < 1 ms
- No sporadic latency spikes

---

## Test 3: UDP Throughput and Packet Loss

### Expected Results

- UDP communication works across all configured data rates
- System handles increasing load until reaching physical or system limits

### Pass Criteria

- iperf3 UDP test completes successfully for all configured rates
- No packet loss at lower data rates (e.g. 1–8 Mbit/s)
- Gradual increase of packet loss at higher data rates is acceptable
- No test crashes or connection drops

---

## Test 4: Maximum Stable Throughput

### Expected Results

- Identification of maximum throughput without packet loss

### Pass Criteria

- Highest data rate with:
  - 0% packet loss
  - stable bitrate
- Result is reproducible across multiple test runs
