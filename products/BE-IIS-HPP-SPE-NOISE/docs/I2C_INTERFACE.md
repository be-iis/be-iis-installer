# Proposed I2C control interface

## Recommended architecture

Use the FPGA as a standard **7-bit I2C slave** and access it through Linux
`i2c-dev`. This is the smallest and most transparent solution: no Device Tree
overlay and no kernel driver are needed to read or write the control registers.

The Raspberry Pi is the only I2C master. The FPGA must implement open-drain
SDA behaviour (never drive a logic high), acknowledge its exact 7-bit address,
and be released from reset before the first START condition.

## Provisional register map

| Register | Name | Access | Meaning |
|---:|---|---|---|
| `0x00` | `DEVICE_ID` | R | fixed value `0x4E` (`N`) |
| `0x01` | `VERSION` | R | FPGA interface version |
| `0x02` | `CONTROL` | R/W | bit 0: output enable; bit 1: generator enable |
| `0x03` | `MODE` | R/W | noise / pattern selection |
| `0x04..0x05` | `AMPLITUDE` | R/W | unsigned amplitude word |
| `0x06..0x07` | `SEED` | R/W | pseudo-random seed |
| `0x08` | `STATUS` | R | lock, fault and active flags |

The final slave address should be documented after confirming the FPGA address
decoder. `0x2A` is reserved here only as a test placeholder.

## Probe sequence

```sh
# Scan only the expected address first; this avoids confusing unrelated HATs.
sudo i2cdetect -y 1 0x2a 0x2a

# Read DEVICE_ID from register 0x00.
sudo i2ctransfer -f -y 1 w1@0x2a 0x00 r1

# Read interface version from register 0x01.
sudo i2ctransfer -f -y 1 w1@0x2a 0x01 r1
```

## EEPROM option

An I2C EEPROM is useful only for persistent defaults, a serial number,
calibration values or a Raspberry Pi HAT EEPROM. It is **not** a replacement
for the FPGA I2C slave when parameters must change while the generator is
running. A good later design can contain both: FPGA registers for live control
and EEPROM for boot defaults.
