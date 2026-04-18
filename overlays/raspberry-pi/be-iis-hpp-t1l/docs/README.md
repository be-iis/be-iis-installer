# Purpose
This directory contains documentation related to the BE-IIS-HPP-T1L hardware overlay for Raspberry Pi. It provides information on device tree overlays, integration, and usage within the installer framework.

# Files
- README.md: Documentation overview for this directory.

# Usage
Refer to the overlay source files in `../src` for device tree overlay definitions (.dts) specific to BE-IIS-HPP-T1L variants. For integration with Raspberry Pi OS, see system-level scripts and service files provided in the installer root and platform directories.

# Notes
- Overlay files in `../src` correspond to different hardware variants (I, II, III) of the BE-IIS-HPP-T1L.
- Requires compatible Raspberry Pi OS and appropriate overlay application procedure.
- For build or deployment details, see installer documentation and supporting scripts under `/platform/raspberry-pi-os` and `/scripts/install`.
