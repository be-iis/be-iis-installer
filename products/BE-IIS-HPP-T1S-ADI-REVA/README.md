# BE-IIS-HPP-T1S-ADI-REVA

10BASE-T1S HAT++ integration for the Analog Devices ADIN1140 / AD3306 TC6 MAC-PHY.

- Linux MAC-PHY driver: `adin1140`
- PHY driver: `adin1140-phy`
- Device Tree: `adi,adin1140`, fallback `adi,ad3306`
- IRQ: active-low, level-triggered
- Overlay variants: HAT++ positions I, II and III

The product script first uses the running kernel driver when available. If it is absent, `tools/kernel/adin1140_mod_build.sh` prepares a coherent upstream OA-TC6 source set and builds the modules against the running kernel headers.

ADIN1110 remains the separate 10BASE-T1L path and is not changed by this product.
