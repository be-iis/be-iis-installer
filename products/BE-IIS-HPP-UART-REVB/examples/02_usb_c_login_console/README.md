# 02 – Login console on the isolated USB-C UART

Use the isolated USB-C UART as a serial Linux login console. This is useful for
commissioning and service when Ethernet, Wi-Fi, or HDMI are unavailable.

This example was verified with UART HAT instance IV:

```text
/dev/beiis-uart-iv-a -> ttySC0
```

The HAT-specific `beiis-uart-iv-a` symlink is ideal for applications. The
Linux getty must use the underlying kernel TTY, `ttySC0`.

## 1. Enable the serial login service on the Raspberry Pi

```bash
sudo systemctl enable --now serial-getty@ttySC0.service
```

Verify that it is running:

```bash
systemctl status serial-getty@ttySC0.service --no-pager
```

The service is enabled persistently and starts again after every boot.

## 2. Connect from a PC

Connect the HAT USB-C port to a separate PC with a USB data cable. On that PC,
open the enumerated USB serial device at 115200 baud:

```bash
picocom -b 115200 /dev/ttyUSB0
```

If needed, find the device on the PC:

```bash
ls -l /dev/ttyUSB* /dev/ttyACM*
```

Press Enter in `picocom`. The Raspberry Pi login prompt appears:

```text
pi5 login:
```

Log in with a normal Raspberry Pi user account.

To leave `picocom`, press `Ctrl+A`, then `Ctrl+X`.

## Disable the login console

```bash
sudo systemctl disable --now serial-getty@ttySC0.service
```

## Note about kernel boot messages

`serial-getty` provides a login console after the SC16IS752 UART driver has
loaded. It does not turn the UART into an early kernel console. On the tested
Raspberry Pi kernel, `ttySC0` is not registered in `/proc/consoles`; a
`console=ttySC0,115200` boot argument therefore has no effect.
