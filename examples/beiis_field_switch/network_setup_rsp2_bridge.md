# 🌐 Network Setup: Field Switch (RSP2)

## 🔌 Power Architecture

- RSPZ is powered via PoSPE over 10BASE-T1L (25V)
- RSPZ forwards power over T1L to RSP2
- RSP2 is additionally connected to a router via Ethernet (eth0)

---

## 🌉 Bridge Configuration on RSP2

Goal:
Combine all interfaces into a single Layer-2 network (Field Switch behavior)

Interfaces:
- eth0           → Uplink (Router)
- beiis-t1l1     → T1L
- beiis-t1s0     → T1S

---

## ⚠️ Important

During setup, network connection will be temporarily lost!

---

## ⚙️ Step-by-Step

### 1. Prepare T1L Interface (set stable MAC)

```bash
sudo ip link set beiis-t1l1 down
sudo ip link set beiis-t1l1 address 02:00:00:00:01:01
sudo ip link set beiis-t1l1 up
```

---

### 2. Create Bridge

```bash
sudo ip link add br0 type bridge
sudo ip link set br0 up
```

---

### 3. Add Interfaces to Bridge

```bash
sudo ip link set eth0 master br0
sudo ip link set beiis-t1l1 master br0
sudo ip link set beiis-t1s0 master br0
```

---

### 4. Move IP Address (critical step)

```bash
sudo ip addr flush dev eth0
sudo ip addr add 192.168.178.52/24 dev br0
```

---

## 🔄 Reconnect

After this step:
- reconnect via `ssh <user>@192.168.178.52`
- or via hostname if mDNS is active

---

## 🔎 Result

- All interfaces are bridged (Layer 2 switch behavior)
- Router sees all connected nodes behind one port
- Traffic is transparently forwarded between:
  - Ethernet (eth0)
  - 10BASE-T1L
  - 10BASE-T1S

---

## 💡 Key Takeaway

A Raspberry Pi acts as a multi-interface industrial Ethernet switch —
bridging standard Ethernet, 10BASE-T1L and 10BASE-T1S in one system.
