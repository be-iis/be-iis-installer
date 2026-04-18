# Purpose
Cross-compilation script for LAN865x kernel module targeting Raspberry Pi or compatible ARM platforms.

# Files
- **build.sh**: Shell script to cross-compile the LAN865x driver/module using a specified toolchain.

# Usage
Execute `build.sh` to build the LAN865x kernel module. Ensure the ARM cross-compilation toolchain and necessary kernel headers are available and configured before running the script.

```sh
./build.sh
```

# Notes
- Edit `build.sh` to set correct paths for the kernel source and cross-toolchain as required by the environment.
- For kernel source preparation and toolchain setup, see documentation in `scripts/bootstrap/prepare-rpi-build-env.sh` and platform README files.
- No hardware-specific settings are defined in this directory; refer to LAN865x hardware/software documentation for further configuration.
