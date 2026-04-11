# BE-IIS Field Switch Example

This example consists of three setup documents:

- [setup_rsp2.md](setup_rsp2.md)  
  Setup for **RSP2** (Raspberry Pi 2B)

- [setup_rspz.md](setup_rspz.md)  
  Setup for **RSPZ** (Raspberry Pi Zero 2 W)

- [network_setup_rsp2_bridge.md](network_setup_rsp2_bridge.md)  
  Bridge and network setup for **RSP2**

---

## Recommended order

1. Prepare and install **RSP2**
2. Prepare and install **RSPZ**
3. Apply the **network bridge setup on RSP2**

---

## Purpose

Together, these three documents describe a complete BE-IIS field switch example with:

- Raspberry Pi based multi-interface networking
- 10BASE-T1S
- 10BASE-T1L
- standard Ethernet
- Linux bridge configuration
- PoSPE-based power distribution

---

## Notes

- `setup_rsp2.md` configures the main bridge node
- `setup_rspz.md` configures the secondary node
- `network_setup_rsp2_bridge.md` connects the interfaces into one Layer-2 network
