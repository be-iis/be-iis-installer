# Products

Product-specific installers, overlays, scripts, tests, and configuration files for BE-IIS hardware products.

Each product directory contains the files required to install, configure, test, and integrate a specific BE-IIS HAT++ board or add-on.

## BE-IIS-HAT++ Products

BE-IIS-HAT++ is a modular Raspberry Pi HAT+ compatible hardware system for industrial communication interfaces.

The product folders in this directory provide the software integration layer for the supported BE-IIS hardware modules.

Supported or prepared product directories include:

* **BE-IIS-HPP-CAN-FD-SIC-REVB**: CAN FD SIC industrial interface HAT++.
* **BE-IIS-HPP-LAN-REVB**: Isolated 10/100 Mbit/s Ethernet HAT++.
* **BE-IIS-HPP-MODBUS-REVB**: Dual RS-485 / Modbus industrial interface HAT++.
* **BE-IIS-HPP-T1L-REVB**: 10BASE-T1L Single Pair Ethernet HAT++.
* **BE-IIS-HPP-T1S-REVB**: 10BASE-T1S Single Pair Ethernet HAT++.
* **BE-IIS-HPP-UART-REVB**: Dual UART industrial interface HAT++.
* **BE-IIS-PoSPE**: Power over Single Pair Ethernet add-on board.

## Directory Structure

A typical product directory may contain:

* **docs/**: Product-specific documentation.
* **examples/**: Example configurations and usage examples.
* **files/**: Additional product files, patches, helper files, or static resources.
* **overlays/**: Device-tree overlay source files and compiled overlay files.
* **scripts/**: Product-specific installation or configuration scripts.
* **systemd/**: systemd service files, if required by the product.
* **udev/**: udev rules or helper scripts for stable device naming.
* **test/**: Product-specific test scripts and validation helpers.
* **README.md**: Product-specific overview.

Not every product uses every subdirectory. Empty or documentation-only folders are kept to provide a consistent structure across products.

## Device-Tree Overlays

Most Raspberry Pi based products use device-tree overlays.

The overlays are usually provided in two forms:

* **overlays/src/rpi/**: Source `.dts` files and Makefile.
* **overlays/build/rpi/**: Compiled `.dtbo` overlay files.

Several products provide different overlay variants for different HAT++ stack positions, for example:

* `*-I.dtbo`
* `*-II.dtbo`
* `*-III.dtbo`

## Ordering Products

BE-IIS products can be ordered or viewed here:

* BE-IIS product page: https://www.be-iis.eu/products/
* Digi-Key supplier page: https://www.digikey.com/en/supplier-centers/industrial-interface-solutions

## Notes

* This directory contains product-specific integration files.
* Common installer logic is located outside this directory.
* Platform-specific files are located in the `platform/` directory.
* Shared helper functions are located in the `common/` directory.
* Product directories are intended to be modular and extendable for future BE-IIS hardware.

