# Raspberry Pi OS Platform Support

## Purpose
Provides platform-specific configuration, scripts, udev rules, and service files for deploying BE-IIS hardware interfaces on Raspberry Pi OS.

## Files
- `bin/apply-hat-overlays.sh`: Script to apply HAT device tree overlays.
- `systemd/be-iis-hatpp.service`: Systemd unit for managing the HAT peripheral processor service.
- `udev/rules.d/70-macphy-names.rules`: Udev rule for consistent network interface naming based on MACPHY devices.

## Usage
- Run `bin/apply-hat-overlays.sh` to enable hardware overlays for supported HATs.
- Install `systemd/be-iis-hatpp.service` into the systemd unit directory and enable as needed.
- Place `udev/rules.d/70-macphy-names.rules` into `/etc/udev/rules.d/` to activate persistent device names.

## Notes
- Scripts must be run with appropriate permissions.
- Refer to parent documentation for supported hardware and overlay details.
