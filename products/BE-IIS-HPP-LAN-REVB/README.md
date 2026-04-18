# Purpose
Support directory for installing, configuring, and testing the BE-IIS-HPP-LAN-REVB product on Raspberry Pi/Linux systems within the be-iis-installer framework.

# Files
- `docs/`           : Product documentation.
- `examples/`       : Example setups and usage guidance.
- `files/`          : Supplementary files for deployment.
- `overlays/`       : Device tree overlays for hardware support.
- `scripts/`        : Automation and installation scripts; see `install.sh` for main install steps.
- `systemd/`        : Systemd unit files for service management.
- `test/`           : Test scripts for product validation.
- `udev/`           : Udev rules for device identification and handling.

# Usage
1. Review the documentation in `docs/` before installation.
2. Run `scripts/install.sh` to perform the product-specific setup.
3. For service integration, use files from `systemd/` and `udev/` as required by your deployment.
4. Use `test/test_target1.sh` and `test/test_target2.sh` to validate hardware/software integration after deployment.

# Notes
- Device tree overlays in `overlays/` must match the target hardware revision.
- Customization may be required based on specific Raspberry Pi models or deployment environments.
- Refer to example configurations in `examples/` for guidance.
- Ensure all dependencies and user permissions are met before executing scripts.
