# Purpose
Provides cross-compilation scripts for selected kernel modules or drivers used in the installer project. Each subdirectory targets a specific hardware component.

# Directory Structure
- `adin1110/`: Build script for ADIN1110 Ethernet driver
- `ksz8851/`: Build script for KSZ8851 Ethernet driver
- `lan865x/`: Build script for LAN865x Ethernet driver
- `mcp251xfd/`: Build script for MCP251xFD CAN controller driver
- `sc15is7xx/`: Build script for SC16IS7xx UART bridge driver

# Files
- Each subdirectory contains a `build.sh` shell script for compiling the respective module.

# Usage
1. Enter the subdirectory for the relevant hardware component.
2. Run `./build.sh` to cross-compile the corresponding kernel module. Adjust environment variables as needed for target architecture and kernel sources.

# Notes
- The build scripts require appropriate cross-compilation toolchains and kernel headers for the target platform.
- Scripts are intended for use in automated build environments and may require adaptation for different host or target platforms.
