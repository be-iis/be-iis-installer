# BE-IIS-HPP-T1S-ONSEMI-REVA

10BASE-T1S HAT++ integration for the onsemi S2500 / T30HM1TS2500 TC6 MAC-PHY.

- Linux driver: `s2500`
- Internal PHY support: `ncn26000`
- Device Tree: `onnn,s2500`
- IRQ: active-low, level-triggered
- Overlay variants: HAT++ positions I, II and III

If the running Raspberry Pi kernel does not yet contain S2500, `tools/kernel/s2500_mod_build.sh` warns and uses the upstream v8 S2500 series. The shared OA-TC6 baseline is also used by the LAN865x and ADIN1140 fallback paths so incompatible TC6 generations are not mixed.
