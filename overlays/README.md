# Purpose
This directory contains device tree overlays and related configuration used in the be-iis-installer project for hardware enablement, primarily targeting Raspberry Pi and compatible platforms.

# Structure
- `archive/`           : Obsolete or legacy overlays, retained for reference.
- `common/`            : Shared overlays and resources.
- `experimental/`      : Overlays under development or testing.
- `raspberry-pi/`      : Main overlays for supported BE-IIS HAT and peripheral boards, organized by interface (e.g., CAN, LAN, LIN, MODBUS, MULTI, POSPE, T1L, T1S, UART).

# Usage
Select the relevant overlay subdirectory for your hardware. Each hardware overlay typically provides:
- Source device tree files (`*.dts`) in a `src/` folder
- Platform-specific README documentation
- Associated test and documentation resources

Integration steps depend on the corresponding platform guides (see `docs/` in repository root, and each overlay's documentation). Overlays can be compiled and applied using Raspberry Pi OS tools or the provided installer scripts.

# Notes
- Only documented and tested overlays in `raspberry-pi/` are recommended for production.
- Multiple hardware variants are organized with separate subfolders and device tree sources.
- Use `experimental/` for early access or custom overlay development.
- Helper scripts and additional integration tools are located in repository `scripts/` and `platform/` as referenced per-overlay.
