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
- Six buttons adjust hardware gain by **−100, −10, −1, +1, +10, +100**,
  clamped to 0…1023. Rapid clicks are queued in order.
- **DDS carrier frequency** and **FM modulation frequency** are entered in Hz
  and applied separately. The driver programs their 24-bit phase steps.
  Resolution is nominally 1.90735 Hz; status shows the realizable frequency
  rounded to whole Hz. FM depth is unchanged.
- Digital/software gain has been removed, including its sysfs attribute.
- Generator, output enable, DDS, and FM are controlled per selected device.

Rebuild/install and reload the updated `beiis-hpp-spe-noise` kernel module,
then restart the webtool service. Frequency controls use `dds_frequency_hz`
and `fm_frequency_hz`. With an older module they are disabled with an update
hint; the other controls remain usable. FPGA firmware `0x0003` removes digital
gain; frequency registers already exist in `0x0002`. This change does not
include a newly built FPGA binary.

The driver pauses DDS while writing both halves of a frequency step and
briefly disables the output if DDS is selected and active. On success it
restores the prior enable state. An I²C error is reported; after an interrupted
update DDS/output may remain disabled. Retry the frequency write, then
explicitly re-enable the desired controls after resolving the error.

Frequency input range is 0…15,999,998 Hz (nominally below Nyquist). This is a
numerical limit, not a guarantee of analogue bandwidth or sine quality.
Carrier plus FM deviation must remain in the usable output band. Zero DDS
frequency holds the carrier phase when FM is off; it does not mute the output.

The driver reports cached, acknowledged settings because current FPGA
configuration registers do not support readback. Rebinding assumes power-up
defaults; do not use raw I²C writes or reflash the board behind the bound driver.

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
