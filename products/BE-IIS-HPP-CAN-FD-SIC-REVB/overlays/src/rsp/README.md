# Purpose

Device Tree overlays for BE-IIS HPP CAN boards on Raspberry Pi.

# Files

- `BE-IIS-HPP-CAN-SIC-I.dts`
- `BE-IIS-HPP-CAN-SIC-II.dts`
- `BE-IIS-HPP-CAN-SIC-III.dts`

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

Build output:

```text
be-iis-installer/build/overlay/rpi/<OVERLAY_NAME>/
```

# Usage

Auto-detect by BE-IIS-HAT++ or manual setup.

Enable overlay in:

```text
/boot/firmware/config.txt
```

Example:

```ini
dtoverlay=BE-IIS-HPP-CAN-SIC-I
```

Reboot:

```sh
sudo reboot
```

# Kernel Documentation

https://www.kernel.org/doc/Documentation/devicetree/bindings/net/can/microchip%2Cmcp251xfd.yaml

# Notes

- Use `IRQ_TYPE_LEVEL_LOW`
- `IRQ_TYPE_EDGE_FALLING` does not work reliably
- For Raspberry Pi 5 / RP1, stable IRQ handling may require:

```dts
pinctrl-names = "default";
pinctrl-0 = <&be_iis_shared_irq_pins>;
```
