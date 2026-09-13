# BE-IIS HPP SPE Noise Generator Webtool

Local browser control for the noise-generator kernel driver.

It uses the driver's sysfs interface at `/sys/bus/i2c/devices/1-002a` and
therefore does not access I²C directly.

## Gain controls

- **Hardware gain** is the 10-bit `pwm_reference` value (0…1023).  It sets
  the analog DAC reference and is displayed by the six front-panel LEDs.
- **Software gain** is the discrete `amplitude` stage (0…4): 1×, 1/2,
  1/4, 1/8 or 1/16.  It attenuates the waveform about its DAC midpoint and
  therefore preserves the DC reference.

The FPGA image and kernel module must support the discrete software-gain
definition before using this version of the webtool.

## Start manually

```sh
make run
```

Open <http://PI-IP:8080> from a device on the same local network.

## Start at boot

```sh
make enable
```

The system service installs the tool in `/opt/be-iis/BE-IIS-HPP-SPE-NOISE/examples/webtool`.
It runs as user `pi`. Stop and disable it with `make disable`.
