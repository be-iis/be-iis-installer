# Unified 10BASE-T1S driver build (experimental)

This prototype builds **one** OA-TC6 provider plus LAN865x, ADIN1140 and S2500 MAC-PHY drivers and their required PHY dependencies in one external kernel module build. It does **not** install or load any kernel modules.

## Usage

```sh
bash tools/kernel/t1s_unified_build.sh
python3 scripts/check_t1s_stack.py build/t1s-unified
```

The script uses the existing onsemi v8 patch series and the existing ADI kernel-compatibility transformations, and obtains the Microchip source through `t1s_source_common.sh`. Linux 6.12 header compatibility is the initial target. Required sources are taken from the existing repository source resolver, not an assumed Linux 7.2 kernel version.

**IMPORTANT:** The separate legacy builds are run to generate compatible driver source files; their independently built `.ko` files are discarded. Only the final unified build output is intended as a matched set.

The final compiler may expose additional LAN865x or ADI incompatibilities; those must be fixed and retested before any install path is enabled. Compilation and symbol CRC matching alone do not prove functional SPI/PHY behavior.

## Safety

- No `sudo`, `depmod`, `modprobe`, `insmod` or copying into `/lib/modules`.
- Never overwrite a working Microchip OA-TC6 module while it is in use.
- No installation command is provided yet; separate staging, backup, reboot and rollback must be implemented and tested before deployment.
- A native-driver shortcut must verify both module availability and the OA-TC6 ABI; kernel version alone is not sufficient.

## Validation

The validator checks that seven expected `.ko` artifacts exist and that every OA-TC6 symbol referenced by the three MAC-PHY drivers matches the CRC in the unified `Module.symvers`. On the target Pi, follow with SPI binding, PHY detection and Ethernet link tests once a safe install workflow exists.
