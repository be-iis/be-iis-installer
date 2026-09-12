# BE-IIS HPP SPE Noise Generator Webtool

Local browser control for the noise-generator kernel driver.

It uses the driver's sysfs interface at `/sys/bus/i2c/devices/1-002a` and
therefore does not access I2C directly. The page controls generator selection,
output enable, amplitude, PWM reference, DDS and FM.

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
