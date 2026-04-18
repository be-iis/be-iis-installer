# Purpose
Installer and build system for BE-IIS hardware platform on Raspberry Pi and Linux. Supports automated setup, overlays, scripts, product configurations, build helpers, and documentation.

# Files and Directories
- **assets/**: Static files and resources for installation and documentation.
- **common/**: Shared scripts and functions for installer components.
- **docs/**: Usage guides and technical documentation.
- **examples/**: Example configurations and setups for various supported hardware scenarios.
- **overlays/**: Device tree overlays for Raspberry Pi HATs and supported hardware; includes product- and protocol-specific overlays.
- **platform/**: Platform-specific installer assets, cross-compile scripts, OS integration, system service and udev rules.
- **products/**: Product-specific installer scripts, overlays, configuration files, and tests for supported BE-IIS hardware.
- **scripts/**: Setup, installation, network configuration, build environment preparation, and supporting automation.
- **tests/**: Test and validation frameworks, including integration, overlay, and smoke tests.
- **tools/**: Build and utility tools for EEPROM, kernel modules, overlays, images, and release packaging.
- **.gitignore**: Version control exclusions.
- **README.md**: Directory overview (this file).

# Usage
Refer to the `docs/` directory for flashing and configuration guides. Scripts in `scripts/` automate installation and setup. Use product-specific folders in `products/` for hardware-specific procedures and overlays in `overlays/` for device tree configuration.

# Notes
- Structure supports modular extension for new hardware products and protocols.
- Scripts are shell-based; system integration provided for Debian and Raspberry Pi OS.
- All script and systemd/udev files are located in their relevant platform/product subfolders.
- Extensive examples provided for field setup and network configuration.
