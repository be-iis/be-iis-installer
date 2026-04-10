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

## Expected Results

- Network interface is successfully configured on both devices
- Link is established between both Raspberry Pis
- Ping is successful in both directions
- Round-trip time is below **1 ms**

## Pass Criteria

- Interface `beiis-t1s0` is up on both devices
- No packet loss during ping test
- Round-trip time < 1 ms
