# Purpose
Udev in this directory is intended for device management and rule configuration for UART-based products. This supports correct creation, naming, and handling of UART device nodes on Linux systems, typically within the context of the BE-IIS installer.

# Files
- README.md: This documentation file.

# Usage
Place relevant udev rule files in this directory to define behavior for UART devices. Standard udev rules may handle permissions, symlink creation, or device event triggers.

# Notes
No udev rules or helper scripts currently exist in this directory. Add rules as needed using the `.rules` extension. Ensure rules match the hardware and system requirements of the UART product variant.
