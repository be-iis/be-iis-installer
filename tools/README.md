# Tools

Helper tools for EEPROM handling, ethtool builds, kernel module builds, and device-tree overlay support.

This directory contains utility tools used by the BE-IIS installer and development workflow.

## Directory Structure

* **eeprom/**: Tools and documentation related to HAT EEPROM handling.
* **ethtool/**: Build files and documentation for ethtool support.
* **kernel/**: Kernel module build helper scripts.
* **overlay/**: Device-tree overlay helper documentation.
* **README.md**: Overview of this directory.

## EEPROM Tools

The **eeprom/** directory contains documentation and helper files for working with Raspberry Pi HAT EEPROM data.

This is used for product identification, HAT++ detection, and hardware-specific configuration.

## ethtool Tools

The **ethtool/** directory contains files for building ethtool on the target system.

* **build-ethtool-on-target.md**: Documentation for building ethtool directly on the target.
* **Makefile**: Build helper for ethtool.

This can be useful for network diagnostics and Single Pair Ethernet features such as PLCA configuration.

## Kernel Module Build Tools

The **kernel/** directory contains helper scripts for building required Linux kernel modules.

Available module build helpers:

* **adin1110_mod_build.sh**: Builds the ADIN1110 10BASE-T1L driver module.
* **ksz8851_mod_build.sh**: Builds the KSZ8851 Ethernet driver module.
* **lan865x_mod_build.sh**: Builds the LAN865x 10BASE-T1S driver module.
* **mcp251xfd_mod_build.sh**: Builds the MCP251xFD CAN-FD driver module.
* **sc16is7xx_mod_build.sh**: Builds the SC16IS7xx UART driver module.
* **README.md**: Kernel module build documentation.

These scripts are intended for BE-IIS hardware bring-up, driver testing, and installation support.

## Overlay Tools

The **overlay/** directory contains documentation for device-tree overlay handling.

Device-tree overlays are used to enable and configure BE-IIS HAT++ hardware on Raspberry Pi systems.

## Notes

* These tools are mainly intended for development, testing, and installation support.
* Product-specific files are located in `products/`.
* Platform-specific files are located in `platform/`.
* Main installation scripts are located in `scripts/install/`.
* Some tools may require root privileges or matching Linux kernel headers.

