# Purpose
udev directory for POSPE product-specific udev integration within the installer. Intended for rules, scripts, or helpers to manage device node naming, permissions, or hotplug operations.

# Files
- README.md: This documentation file.

# Usage
No udev rules or scripts included by default. Add product-specific udev rules (*.rules) or helper scripts as needed to support POSPE devices. Refer to platform/raspberry-pi-os/udev/rules.d for rule examples.

# Notes
- Ensure any added udev rules use unique names to avoid conflicts.
- Limit file types to: .rules, .sh, .md, and related helper files for device setup.
- Directory is required for custom POSPE device handling; leave empty if not used.
