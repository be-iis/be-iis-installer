# Purpose
This directory contains udev rules for Raspberry Pi OS used in the be-iis-installer to provide predictable device naming and configuration for hardware interfaces.

# Files
- `rules.d/70-macphy-names.rules`: udev rule to assign persistent names to specific MACPHY devices based on device attributes.

# Usage
Copy the rules file to `/etc/udev/rules.d/` on the target system. Reload udev rules or reboot for the changes to take effect.

# Notes
- Ensure appropriate permissions to modify udev rules on the target system.
- The rules may need adjustment for other hardware variants.
