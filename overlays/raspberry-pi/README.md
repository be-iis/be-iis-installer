# Purpose
Device tree overlay collection for Raspberry Pi hardware modules as part of the be-iis-installer. Each subdirectory corresponds to a supported HAT/expansion board variant.

# Structure
- One subdirectory per supported interface or HAT (CAN, LAN, LIN, MODBUS, MULTI, POSPE, T1L, T1S, UART).
- Each subdirectory typically contains:
  - `docs/`: Documentation
  - `src/`: Device tree source (.dts) files for different hardware revisions/variants
  - `tests/`: Test or validation assets
  - `README.md` describing specifics for the module

# Usage
- Overlays are intended for integration with Raspberry Pi OS device tree support.
- Refer to individual subdirectory README files and source overlay (.dts) files for configuration and application procedure.
- For end-to-end instructions, see the main installer documentation and scripts in `platform/raspberry-pi-os/`.

# Notes
- Only the directory structure and referencing metadata are present here. No overlay binaries (.dtbo) in this directory.
- See main installer or module documentation for compatibility and build details.
