# 03 – Raspberry Pi boot console via USB-C UART

Use the Raspberry Pi's native UART as a boot console through the isolated USB-C
service port of the BE-IIS-HPP-UART.

This example was verified on a Raspberry Pi 5. It provides boot messages much
earlier than the SC16IS752 UART bridge.

## 1. Select the Raspberry Pi UART path

Set the HAT++ ID to **6**. In this configuration, the HAT++ UART bridge is
disabled and the Raspberry Pi UART is connected to the isolated USB-C service
port.

## 2. Enable the Pi 5 UART

In `/boot/firmware/config.txt`, add these two separate lines:

```text
enable_uart=1
dtoverlay=uart0
```

In the single existing line in `/boot/firmware/cmdline.txt`, ensure this
kernel console argument is present:

```text
console=serial0,115200
```

Do not add `console=ttySC0,115200` for this example; the SC16IS752 HAT UART
is not used.

## 3. Open the PC terminal and reboot

On the connected PC, open the USB serial device before rebooting the Pi:

```bash
picocom --noreset --noinit -b 115200 /dev/ttyUSB0
```

Then reboot the Raspberry Pi:

```bash
sudo reboot
```

The PC terminal displays Raspberry Pi kernel boot messages immediately during
startup. This verifies the native Pi boot UART path through the isolated USB-C
connection.

To leave `picocom`, press `Ctrl+A`, then `Ctrl+X`.
