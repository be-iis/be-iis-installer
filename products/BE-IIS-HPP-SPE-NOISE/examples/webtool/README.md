# BE-IIS HPP SPE Noise Generator Webtool

Local browser control for every BE-IIS HPP SPE Noise Generator detected by the
`beiis-hpp-spe-noise` kernel driver.  The webtool uses sysfs only; it does not
access I²C directly.

At start, it discovers all bound devices.  One device is selected directly; if
several boards are installed, the page displays a device drop-down with I²C
address and HAT++ instance.

## Controls

- **Hardware gain** is the 10-bit `pwm_reference` value (0…1023). It sets the
  analog DAC reference and is represented by the six front-panel LEDs.
- **Software gain** is the discrete `amplitude` stage (0…4): 1×, 1/2, 1/4,
  1/8, or 1/16. It attenuates around the DAC midpoint.
- Generator, output enable, DDS, and FM are controlled per selected device.

The matching FPGA image and kernel module must support the discrete
software-gain definition.

## Firmware update

The firmware selector lists all `.bin` raw NVCM images in the product
`firmware/` directory. Firmware programming is intentionally available only
for **HAT++ instance I**, because only this instance owns SPI0 CE0 and the
MachXO2 FPGA manager.

Firmware update is disabled by default because the service is reachable on the
local network and NVCM programming is a persistent operation. Start the tool
deliberately with:

```sh
sudo python3 noise_webtool.py --enable-firmware-update
```

The update button becomes visible only when the selected device is instance I.
Keep JTAG available as a recovery path when testing new images.

## Start manually

```sh
make run
```

Open <http://PI-IP:8080> from a device on the same local network.

## Start at boot

```sh
make enable
```

The system service installs the tool in
`/opt/be-iis/BE-IIS-HPP-SPE-NOISE/examples/webtool`. It runs as root because
sysfs writes and the optional FPGA manager programming require it. Stop and
disable it with `make disable`.
