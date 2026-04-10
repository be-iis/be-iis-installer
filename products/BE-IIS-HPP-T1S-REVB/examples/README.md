# BE-IIS T1S – Command Reference

Collection of commonly used commands for 10BASE-T1S bring-up and testing.

---

## PLCA Configuration

### Set PLCA (example: 8 nodes)

#### Pi 1
```bash
sudo ethtool --set-plca-cfg beiis-t1s0 enable on node-id 0 node-cnt 8
```

#### Pi 2
```bash
sudo ethtool --set-plca-cfg beiis-t1s0 enable on node-id 1 node-cnt 8
```


## Get PLCA configuration
```bash
sudo ethtool --get-plca-cfg beiis-t1s0
```


## IPERF3

### Install
```bash
sudo apt update
sudo apt install -y iperf3
```
---

## TCP Test

### Server (Pi 2)
```bash
iperf3 -s
```

### Client (Pi 1)
```bash
iperf3 -c 100.100.100.2 -t 10
```

Parameters:
- -c : target IP
- -t : test duration in seconds

---

## TCP Reverse Test

### Server (Pi 2)
```bash
iperf3 -s
```

### Client (Pi 1)
```bash
iperf3 -c 100.100.100.2 -t 10 -R
```

Parameters:
- -R : reverse direction (server → client)

---

## UDP Test

### Server (Pi 2)
```bash
iperf3 -s
```

### Client (Pi 1)
```bash
iperf3 -c 100.100.100.2 -u -b 10M -t 10
```

Parameters:
- -u : UDP mode
- -b : bandwidth (e.g. 1M, 5M, 10M)
- -t : test duration

---

## UDP Rate Sweep (Recommended)
```bash
for rate in 1 2 3 4 5 6 7 8 9 10; do
    echo "Rate: ${rate} Mbit/s"
    iperf3 -c 100.100.100.2 -u -b ${rate}M -t 10
done
```

---

## Notes

- Run server first, then client
- Use point-to-point connection
- Termination must be enabled on both sides
- PLCA can be enabled for deterministic behavior
- UDP tests show packet loss at higher data rates
