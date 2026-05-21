# Purpose
Documentation for the UART product of the installer project. Provides information on functionality, usage, and integration with Raspberry Pi / Linux environments.

# Files
- `README.md`: This documentation file.

# Usage
Refer to surrounding directories for overlays, scripts, systemd, and udev integration related to UART hardware setup and automation. See:
- `../overlays` for device tree overlay sources
- `../scripts` for installation and configuration scripts
- `../systemd` for service integration
- `../udev` for device rule configuration

For general platform setup, refer to project-level documentation in `/docs` and component-specific READMEs in sibling directories.

# Notes
- Documentation here is specific to the UART variant; for implementation details or board support, see corresponding overlay and script directories.
- Ensure overlays and scripts are compatible with the target Raspberry Pi distribution.
