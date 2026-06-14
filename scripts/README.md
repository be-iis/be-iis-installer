# Scripts

Entry-point scripts for setup, installation, network configuration, SSH access, and development helpers.

This directory contains the main scripts used to prepare and install the BE-IIS software environment on Raspberry Pi and Linux systems.

## Directory Structure

* **bootstrap/**: Scripts for preparing the build or development environment.
* **dev/**: Development-related helper scripts and documentation.
* **install/**: Main installation scripts for BE-IIS components.
* **net/**: Network configuration helpers.
* **ssh/**: SSH setup helpers.
* **README.md**: Overview of this directory.

## Bootstrap Scripts

The **bootstrap/** directory contains scripts used to prepare the Raspberry Pi build environment.

* **prepare-rpi-build-env.sh**: Prepares a Raspberry Pi related build environment.

## Installation Scripts

The **install/** directory contains the main BE-IIS installation steps.

* **01_install_eepdump.sh**: Installs EEPROM dump support.
* **02_install-mods.sh**: Installs required kernel modules.
* **03_install-overlays.sh**: Installs device-tree overlays.
* **04_install_hatpp_service.sh**: Installs the HAT++ detection and service integration.
* **05_install-udev-rules.sh**: Installs udev rules for stable device naming.
* **06_I2C_VC_ena.sh**: Enables the required I2C interface configuration.
* **install-all.sh**: Runs the full installation sequence.

Typical usage:

```bash
cd scripts/install
sudo ./install-all.sh
```

## Network Scripts

The **net/** directory contains helper scripts and documentation for static network configuration.

* **set_static_ip.sh**: Configures a static IP address for a wired network interface.
* **set_static_ip.md**: Documentation for wired static IP setup.
* **set_wlan_static_ip.sh**: Configures a static IP address for a WLAN interface.
* **set_wlan_static_ip.md**: Documentation for WLAN static IP setup.

## SSH Scripts

The **ssh/** directory contains scripts for SSH access setup.

* **setup-pi-ssh-key.sh**: Installs or configures SSH key access for a Raspberry Pi.
* **README.md**: SSH setup documentation.

## Development Helpers

The **dev/** directory is reserved for development-related scripts and documentation.

## Notes

* Scripts are shell-based.
* Most installation scripts require root privileges.
* Run scripts from the repository root or from the documented directory.
* Product-specific scripts are located in the corresponding product folders under `products/`.
* Platform-specific integration files are located in `platform/`.
* Shared helper functions are located in `common/`.

