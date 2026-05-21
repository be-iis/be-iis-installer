# Purpose

Device Tree overlays for BE-IIS HAT++ products on Raspberry Pi.

# Files

All `.dts` files in this directory are compiled into Raspberry Pi Device Tree overlays.

# Build

Build all overlays:

```sh
make
```

Install overlays:

```sh
sudo make install
```

Clean build files:

```sh
make clean
```

List available overlays:

```sh
make list
```

# Build Output

Compiled overlays are stored in:

```text
../../build/rpi/
```

Example:

```text
../../build/rpi/BE-IIS-HPP-T1L-I.dtbo
```

# Installation

Installed overlays are copied to:

```text
/boot/firmware/overlays/
```

# Usage

Overlays can be:

* auto-detected by the BE-IIS HAT++ system
* enabled manually in Raspberry Pi firmware configuration

Edit:

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

* Use `IRQ_TYPE_LEVEL_LOW` for reliable interrupt handling
* `IRQ_TYPE_EDGE_FALLING` may not work reliably on all Raspberry Pi platforms
* Raspberry Pi 5 / RP1 systems may require explicit pinctrl configuration:

```dts
pinctrl-names = "default";
pinctrl-0 = <&be_iis_shared_irq_pins>;
```

# Kernel Documentation

Linux Device Tree bindings:

```text
Documentation/devicetree/bindings/
```

