# Network Test Setup

## Hardware Preparation

- Use two Raspberry Pis
- Install BE-IIS T1L HAT on both devices

### Wiring

- Connect both devices in a point-to-point topology
- Ensure termination is enabled on both sides

---

## Software Setup

Run the provided test scripts on both Raspberry Pis.

See:
[`test_target1.sh`](./test_target1.sh)
[`test_target2.sh`](./test_target2.sh)

### Pi 1
./test_target1.sh

### Pi 2
./test_target2.sh

---

## Test 1: Interface Bring-up and Connectivity

### Expected Results

- Network interface is successfully configured on both devices
- Link is established between both Raspberry Pis
- Basic communication is possible

### Pass Criteria

- Interface `beiis-t1l0` is up on both devices
- IP address is correctly assigned
- Ping is successful in both directions
- No packet loss during ping test
- Round-trip time < 1 ms

---

## Test 2: Ping Latency Stability

### Expected Results

- Stable low-latency communication between both devices
- No packet loss under continuous ping

### Pass Criteria

- Continuous ping over defined duration
- 0% packet loss
- Round-trip time remains consistently < 1 ms
- No sporadic latency spikes

---

## Test 3: TCP Throughput

### Expected Results

- Reliable TCP communication between both devices
- Stable throughput without connection drops

### Pass Criteria

- iperf3 TCP test completes successfully
- No connection resets or errors
- Stable throughput during test duration

---

## Test 4: UDP Throughput and Packet Loss

### Expected Results

- UDP communication works across all configured data rates
- System handles increasing load until reaching physical or system limits

### Pass Criteria

- iperf3 UDP test completes successfully for all configured rates
- No packet loss at lower data rates is expected
- Gradual increase of packet loss at higher data rates is acceptable
- No test crashes or connection drops

---

## Test 5: Maximum Stable Throughput

### Expected Results

- Identification of maximum throughput without packet loss

### Pass Criteria

- Highest data rate with:
  - 0% packet loss
  - stable bitrate
- Result is reproducible across multiple test runs


