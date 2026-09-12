# BE-IIS HPP SPE Noise Generator Webtool

Local browser control for the noise-generator output and update-rate divider.

The tool uses I2C bus 1, target address `0x2a`, register `0x01` for output
control and register `0x02` for the rate divider.

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
