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
| 0x0000 | CONTROL | W | generator select and output enable |
| 0x0001..02 | Reserved | — | former digital gains; ignored by firmware 0x0003 |
| 0x0003 | REF_PWM | W | PWM reference, 0..1023 |
| 0x0004 | COMPONENT_ID | R | 0x4e47 ("NG") |
| 0x0005 | FIRMWARE_ID | R | 0x0003 (gain removed) |
| 0x0300 | DDS_CONTROL | W | DDS/FM enable |
| 0x0301 | DDS_STEP_HI | W | phase step bits 23:16 in low byte |
| 0x0302 | DDS_STEP_LO | W | phase step bits 15:0 |
| 0x0303 | Reserved | — | former DDS amplitude; ignored by firmware 0x0003 |
| 0x0304 | FM_STEP_HI | W | LFO phase step bits 23:16 in low byte |
| 0x0305 | FM_STEP_LO | W | LFO phase step bits 15:0 |
| 0x0306 | FM_DEVIATION | W | signed low-byte triangle deviation coefficient |

Unbind the kernel driver before using raw transfers. Only the ID registers
currently return meaningful readback; other reads return zero.

Read a 16-bit value with a register-address write followed by a read:

```sh
sudo i2ctransfer -y 1 w2@0x2a 0x00 0x04 r2
sudo i2ctransfer -y 1 w2@0x2a 0x00 0x05 r2
```

## Kernel driver

At probe time the driver reads and validates `COMPONENT_ID` and reads
`FIRMWARE_ID`. The configuration attributes report the driver's shadow cache: default values
at probe time and each value only after its corresponding I2C write is ACKed.

```sh
cd /sys/bus/i2c/devices/1-002a
cat component_id firmware_id generator output_enable pwm_reference dds_enable fm_enable dds_frequency_hz fm_frequency_hz
```

Set frequencies through sysfs (integer Hz):

```sh
echo 2000000 > dds_frequency_hz
echo 1000 > fm_frequency_hz
```

The driver calculates `round(hz * 2^24 / 32000000)`, pauses DDS, writes both
16-bit step registers under its mutex, then restores the previous run state.
When DDS is selected and output is enabled, it also mutes and restores the
output. A failed transfer returns an error without restarting a partial update.
Readback uses the cached step, converted to the nearest whole Hz; for example,
1000 Hz yields step 524 (999.451 Hz nominal, reported as 999).
The numerical input limit is 15,999,998 Hz; usable analogue bandwidth is lower
and also depends on FM deviation. FM depth is unaffected by the rate control.
