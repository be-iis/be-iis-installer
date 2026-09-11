# BE-IIS HPP SPE NOISE

FPGA-based noise generator and disturbance injection HAT++ for Raspberry Pi,
intended for 10BASE-T1S / 10BASE-T1L Single Pair Ethernet bring-up,
robustness testing and lab evaluation.

## Status

**Prototype / bring-up.** The analogue noise output works. I2C control is
currently under investigation and therefore the command register map below is
the proposed software interface, not yet a released protocol.

## Intended features

- FPGA-generated programmable noise and disturbance patterns
- I2C control from Raspberry Pi through the standard `i2c-dev` interface
- No custom Linux kernel driver required for basic control
- Optional non-volatile configuration storage for stand-alone operation
- Raspberry Pi HAT++ mechanical and stacking system

## Software

The board is intentionally modelled as a small userspace-controlled I2C
peripheral. The helper scripts use `/dev/i2c-1` and `i2ctransfer`.

```sh
sudo ./scripts/noise-i2c-scan.sh
sudo ./scripts/noise-status.sh
```

See [docs/I2C_INTERFACE.md](docs/I2C_INTERFACE.md) before assigning the final
I2C address and register map.

## Resources

- Datasheet: pending
- Schematic: pending
- FPGA bitstream: pending

## Company

Brechel Electronic  
Industrial Interface Systems  
https://www.be-iis.eu
