# BE-IIS Installer

Installer and build system for the **BE-IIS hardware platform** on Raspberry Pi and Linux.

BE-IIS provides industrial interface hardware for embedded Linux systems.
The installer supports automated setup, device-tree overlays, scripts, product configurations, build helpers, and documentation.

## BE-IIS-HAT++

**BE-IIS-HAT++** is a modular Raspberry Pi HAT+ compatible hardware system for industrial communication interfaces.

It is designed to build scalable Linux-based gateways, bridges, field switches, converters, and diagnostic systems.
Multiple HAT++ boards can be combined in a structured way, allowing different industrial interfaces to be used together.

Typical interfaces include:

* CAN FD / CAN FD SIC
* 10BASE-T1S Single Pair Ethernet
* 10BASE-T1L Single Pair Ethernet
* RS-485 / Modbus
* UART
* Additional Linux-based industrial interfaces

The goal is to make industrial Linux hardware setup reproducible, documented, and easy to deploy.

## Links

* Website: https://www.be-iis.eu
* Digi-Key Supplier Page: https://www.digikey.com/en/supplier-centers/industrial-interface-solutions

## Purpose

This repository provides the installer and build system for BE-IIS hardware products.

It includes:

* automated installation scripts
* Raspberry Pi and Linux setup helpers
* device-tree overlays
* kernel module build helpers
* udev and systemd integration
* product-specific configuration files
* tests and validation tools
* documentation and examples

## Files and Directories

* **common/**: Shared scripts and functions for installer components.
* **docs/**: Usage guides and technical documentation.
* **examples/**: Example configurations and setups for supported hardware scenarios.
* **platform/**: Platform-specific installer assets, cross-compile scripts, OS integration, systemd services, and udev rules.
* **products/**: Product-specific installer scripts, overlays, configuration files, and tests for supported BE-IIS hardware.
* **scripts/**: Setup, installation, network configuration, build environment preparation, and supporting automation.
* **tests/**: Test and validation frameworks, including integration, overlay, and smoke tests.
* **tools/**: Build and utility tools for EEPROM, kernel modules, overlays, images, and release packaging.
* **.gitignore**: Version control exclusions.
* **README.md**: Directory overview.

## Usage

Refer to the **docs/** directory for flashing and configuration guides.

Use scripts in **scripts/** for installation and setup.

Use product-specific folders in **products/** for hardware-specific procedures, overlays, and configuration files.

## Notes

* The structure supports modular extension for new hardware products and protocols.
* Scripts are shell-based.
* System integration is provided for Debian and Raspberry Pi OS.
* systemd and udev files are located in the relevant platform or product folders.
* Examples are provided for field setup and network configuration.
* The project is intended for Raspberry Pi and general Linux-based industrial systems.

