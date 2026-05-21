# Purpose

Raspberry Pi Device Tree overlays for BE-IIS HAT++ products.

This directory contains:

- overlay source files
- compiled overlay binaries
- Raspberry Pi overlay build system

# Directory Structure

```text
overlays/
├── README.md
├── src/
│   └── rpi/
│       ├── *.dts
│       ├── Makefile
│       └── README.md
└── build/
    └── rpi/
        ├── *.dtbo
        └── README.md
```

# Source Files

Overlay source files:

```text
src/rpi/*.dts
```

See:

```text
src/rpi/README.md
```

# Build Output

Compiled overlays:

```text
build/rpi/*.dtbo
```

See:

```text
build/rpi/README.md
```

# Build

Build overlays:

```sh
cd src/rpi
make
```

# Install

Compile and install overlays to Raspberry Pi firmware:

```sh
cd src/rpi
sudo make install
```

Installed overlays are copied to:

```text
/boot/firmware/overlays/
```

# Clean

Remove all compiled overlays:

```sh
cd src/rpi
make clean
```

# Usage

Enable overlays in:

```text
/boot/firmware/config.txt
```

Example:

```ini
dtoverlay=BE-IIS-HPP-T1L-I
```

Reboot the system:

```sh
sudo reboot
```

# Notes

- Overlay source files are located in `src/rpi/`
- Compiled `.dtbo` files are generated into `build/rpi/`
- Do not edit generated `.dtbo` files manually
- Raspberry Pi 5 / RP1 systems may require explicit pinctrl configuration
