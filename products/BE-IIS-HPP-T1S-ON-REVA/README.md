# BE-IIS-HPP-T1S-ONSEMI-REVA

10BASE-T1S HAT++ integration for the onsemi S2500 / T30HM1TS2500 TC6 MAC-PHY.

- Linux driver: `s2500`
- Internal PHY support: `ncn26000`
- Device Tree: `onnn,s2500`
- IRQ: active-low, level-triggered
- Overlay variants: HAT++ positions I, II and III

If the running Raspberry Pi kernel does not yet contain S2500, `tools/kernel/s2500_mod_build.sh` warns and uses the upstream v8 S2500 series. The shared OA-TC6 baseline is also used by the LAN865x and ADIN1140 fallback paths so incompatible TC6 generations are not mixed.

## Rev A validation (2026-10-16)

**Status: BASIC BRING-UP PASSED.** Two onsemi S2500 HATs operated simultaneously on one Raspberry Pi (Debian 13, kernel `6.12.47+rpt-rpi-v8`). HAT++ detection, SPI driver binding, udev interface names, network namespaces, and bidirectional ICMP were demonstrated.

TCP reverse iperf3 reported **2.66 Mbit/s receiver** with 263 retransmissions. Loaded UDP tests showed significant packet loss; throughput and stability remain **not fully validated**. See [test/RESULTS.md](test/RESULTS.md).
