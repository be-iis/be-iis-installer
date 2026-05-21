# Purpose

Prebuilt Raspberry Pi Device Tree overlays for BE-IIS HAT++ products.

This directory contains compiled `.dtbo` overlay files.

# Source Directory

Overlay source files are located in:

```text
../src/rpi/
```

# Build

To rebuild overlays from source:

```sh
cd ../src/rpi
make
```

Compiled overlays are automatically stored in this directory.

# Install

To compile and install overlays directly to the Raspberry Pi firmware directory:

```sh
cd ../src/rpi
sudo make install
```

Installed overlays are copied to:

```text
/boot/firmware/overlays/
```

# Clean

Remove all compiled overlays:

```sh
cd ../src/rpi
make clean
```

# Notes

- Files in this directory are generated automatically
- Do not edit `.dtbo` files manually
- Edit `.dts` source files in `../src/rpi/`
