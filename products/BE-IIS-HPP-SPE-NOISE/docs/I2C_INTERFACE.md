# I2C control interface

The FPGA is a 7-bit I2C slave with a 16-bit big-endian register address and
16-bit big-endian data.

## Address straps

| A1 | A0 | Address |
|:-:|:-:|:--|
| 0 | 0 | 0x2a |
| 0 | 1 | 0x2b |
| 1 | 0 | 0x2c |
| 1 | 1 | 0x2d |

A0 is MachXO2 PL2A / package pin 1; A1 is PL2B / package pin 2.

## Registers

| Register | Name | Access | Value |
|---:|---|---|---|
| 0x0000 | CONTROL | R/W | generator select and output enable |
| 0x0001 | DIF_GAIN | R/W | centred software attenuation stage: 0=1x, 1=1/2, 2=1/4, 3=1/8, 4=1/16 |
| 0x0003 | REF_PWM | R/W | PWM reference, 0..1023 |
| 0x0004 | COMPONENT_ID | R | 0x4e47 ("NG") |
| 0x0005 | FIRMWARE_ID | R | 0x0002 |
| 0x0300 | DDS_CONTROL | R/W | DDS/FM enable |
| 0x0301..06 | DDS/FM | R/W | phase step, amplitude and FM settings |

Read a 16-bit value with a register-address write followed by a read:

```sh
sudo i2ctransfer -f -y 1 w2@0x2a 0x00 0x04 r2
sudo i2ctransfer -f -y 1 w2@0x2a 0x00 0x05 r2
```

## Kernel driver

At probe time the driver reads and validates `COMPONENT_ID` and reads
`FIRMWARE_ID`. The configuration attributes report the driver's shadow cache: default values
at probe time and each value only after its corresponding I2C write is ACKed.

```sh
cd /sys/bus/i2c/devices/1-002a
cat component_id firmware_id generator output_enable amplitude pwm_reference dds_enable fm_enable
```
