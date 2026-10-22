# BE-IIS-HPP-T1S-ADI-REVA

10BASE-T1S HAT++ integration for the Analog Devices ADIN1140 / AD3306 TC6 MAC-PHY.

- Linux MAC-PHY driver: `adin1140`
- PHY driver: `adin1140-phy`
- Device Tree: `adi,adin1140`, fallback `adi,ad3306`
- IRQ: active-low, level-triggered
- Overlay variants: HAT++ positions I, II and III

The product script first uses the running kernel driver when available. If it is absent, `tools/kernel/adin1140_mod_build.sh` prepares a coherent upstream OA-TC6 source set and builds the modules against the running kernel headers.

ADIN1110 remains the separate 10BASE-T1L path and is not changed by this product.

## Rev A validation (2026-10-17)

**Status: Successfully tested on hardware.**

- Raspberry Pi 2: Linux 6.12.47; Raspberry Pi 3: Linux 6.18.34 (Debian 13).
- HAT+ EEPROM identification and automatic Device Tree overlay loading confirmed.
- ADIN1140 successfully bound to the Linux SPI driver, with PHY link up at 10 Mbit/s.
- Persistent network interface `beiis-t1s-adi0` confirmed on both systems.
- Ethernet communication between the two Raspberry Pis confirmed.
- Measured throughput: approximately **7 Mbit/s** (user-reported iperf3 result).
- Shared OA-TC6 driver stack built successfully for both kernel versions.

Long-duration stability, packet-loss statistics and detailed TCP retransmission counts have not yet been recorded.
