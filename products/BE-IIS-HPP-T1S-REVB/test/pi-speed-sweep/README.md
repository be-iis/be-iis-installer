# 10BASE-T1S SPI Clock Throughput Sweep

This test measures the received 10BASE-T1S UDP throughput while reducing the
LAN865x SPI clock in 1 MHz steps.

The test is intended for two Raspberry Pis equipped with BE-IIS-HPP-T1S-REVB
HATs. One Raspberry Pi acts as the receiver and controls the complete test. The
second Raspberry Pi acts as the sender and is controlled over SSH.

## Test objective

For every configured SPI clock, the test:

1. sends a 10 Mbit/s UDP stream with `iperf3`;
2. records the receiver-side throughput, packet loss and jitter in a CSV file;
3. reduces `spi-max-frequency` in the Raspberry Pi Device Tree overlay by
   1 MHz;
4. rebuilds and installs the overlay;
5. requests a reboot before the next measurement.

The script measures the SPI clock requested by the Device Tree. The actual SCLK
frequency may be rounded by the Raspberry Pi SPI controller to a supported clock
divider.

## Files

```text
spi-speed-sweep/
├── README.md
└── t1s_spi_sweep.sh
```

The result file is generated locally and should normally not be committed:

```text
t1s_spi_sweep.csv
```

## Test setup

```text
                     Management network
                 Wi-Fi or standard Ethernet

        Receiver Pi  <--------------------->  Sender Pi
             |                                    |
       T1S HAT, node 0                      T1S HAT, node 1
             |                                    |
             +---------- 10BASE-T1S --------------+
```

Use a separate management connection for SSH. This keeps the sender accessible
if the T1S link stops working at a low SPI clock.

### Hardware

- Two Raspberry Pis
- Two BE-IIS-HPP-T1S-REVB HATs
- Both HATs configured for the intended instance mode
- Point-to-point T1S wiring
- Correct termination at both ends
- Independent power supplies as required by the setup

### T1S network configuration

Both T1S interfaces must be up and have static IPv4 addresses before starting
the sweep. PLCA must also be configured correctly, for example with node IDs 0
and 1 and a node count of 2.

The existing test scripts in the parent directory can be used for the initial
network setup and connectivity check:

```bash
../test_target1.sh
../test_target2.sh
```

The repository currently uses `beiis-t1s0` in these scripts. Some installations
may expose the interface as `eth1`. Use the actual interface name reported by:

```bash
ip -br link
ip -br address
```

## Software requirements

### Receiver Pi

The receiver runs `t1s_spi_sweep.sh` and therefore needs:

- the complete `be-iis-installer` Git repository;
- `iperf3`;
- `python3`;
- OpenSSH client;
- `iproute2`;
- `make`, `cpp` and `dtc`;
- kernel headers matching the running Raspberry Pi kernel;
- permission to install overlays through `sudo`.

Example basic packages:

```bash
sudo apt update
sudo apt install -y \
    iperf3 python3 openssh-client iproute2 \
    make cpp device-tree-compiler
```

The matching Raspberry Pi kernel headers must also be installed. The overlay
Makefile uses the header tree belonging to `uname -r`.

### Sender Pi

The sender needs:

```bash
sudo apt update
sudo apt install -y iperf3 iproute2 openssh-server
```

The SSH service must be running and reachable over the management network.

## Passwordless SSH setup

Create a dedicated SSH key on the receiver Pi:

```bash
ssh-keygen -t ed25519 \
    -f ~/.ssh/id_ed25519_be_iis_pi \
    -C "t1s-receiver-to-sender"
```

For unattended operation, leave the passphrase empty. Copy the public key to
the sender:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_be_iis_pi.pub \
    philipp@192.168.1.20
```

Verify the connection:

```bash
ssh \
    -i ~/.ssh/id_ed25519_be_iis_pi \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    philipp@192.168.1.20 hostname
```

The command must print the sender hostname without asking for a password.

A convenient SSH configuration is:

```sshconfig
Host t1s-sender
    HostName 192.168.1.20
    User philipp
    IdentityFile ~/.ssh/id_ed25519_be_iis_pi
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
```

The script can then use `t1s-sender` as `SENDER_SSH`.

## Configuration

The script accepts configuration through environment variables. The most
important variables are:

| Variable | Default | Description |
|---|---:|---|
| `SENDER_SSH` | empty | SSH host or `user@address` of the sender Pi |
| `T1S_IFACE` | `eth1` | T1S interface name on both Pis |
| `OVERLAY_NAME` | `BE-IIS-HPP-T1S-I` | Receiver overlay to modify |
| `UDP_RATE` | `10M` | Requested UDP transmit rate |
| `TEST_SECONDS` | `20` | iperf3 measurement duration |
| `OMIT_SECONDS` | `3` | Initial seconds omitted by iperf3 |
| `STEP_HZ` | `1000000` | SPI reduction after a successful test |
| `MIN_HZ` | `1000000` | Lowest SPI clock to prepare |
| `CSV_FILE` | beside script | Result CSV path |
| `SSH_IDENTITY_FILE` | auto-detected | Private key used for sender control |

Example for the BE-IIS interface name:

```bash
export SENDER_SSH=t1s-sender
export T1S_IFACE=beiis-t1s0
export OVERLAY_NAME=BE-IIS-HPP-T1S-I
```

Alternatively, pass the values for one invocation:

```bash
SENDER_SSH=t1s-sender \
T1S_IFACE=beiis-t1s0 \
./t1s_spi_sweep.sh
```

Available overlay instances are normally:

```text
BE-IIS-HPP-T1S-I
BE-IIS-HPP-T1S-II
BE-IIS-HPP-T1S-III
```

Select the overlay that is active on the receiver Pi.

## Running the sweep

Run the script from the receiver Pi as the normal user:

```bash
cd products/BE-IIS-HPP-T1S-REVB/test/spi-speed-sweep
chmod +x t1s_spi_sweep.sh

SENDER_SSH=t1s-sender \
T1S_IFACE=beiis-t1s0 \
./t1s_spi_sweep.sh
```

Do **not** run the complete script with `sudo`:

```bash
# Wrong
sudo ./t1s_spi_sweep.sh
```

The script deliberately keeps the normal user's home directory and SSH
configuration. It requests `sudo` itself only when required for overlay
installation.

After a successful measurement, the script prints:

```text
Bitte jetzt neu starten:

  sudo reboot
```

Reboot the receiver:

```bash
sudo reboot
```

After the reboot, run the same command again. Repeat this cycle until the
minimum frequency is reached or a measurement fails.

## Automatic sequence

For each invocation, the script performs the following sequence:

```text
Read active Device Tree SPI clock
        |
Compare it with the overlay source
        |
Verify passwordless SSH access
        |
Discover both T1S IPv4 addresses
        |
Start receiver-side iperf3 server
        |
Start 10 Mbit/s UDP sender over SSH
        |
Parse receiver-side iperf3 JSON
        |
Append result to CSV
        |
Reduce spi-max-frequency by 1 MHz
        |
Rebuild and install the overlay
        |
Request reboot
```

If the overlay source already contains the next frequency but the running
Device Tree still contains the previous frequency, the script does not perform
another test or reduce the clock again. It asks for the missing reboot instead.

## CSV output

The default output file is:

```text
t1s_spi_sweep.csv
```

Important columns include:

| Column | Meaning |
|---|---|
| `status` | `OK` or `FAILED` |
| `spi_requested_hz` | SPI limit active during the test |
| `spi_requested_mhz` | Same value in MHz |
| `udp_target` | Requested iperf3 UDP rate |
| `received_mbit_s` | Receiver-side measured throughput |
| `lost_percent` | Receiver-side UDP packet loss |
| `jitter_ms` | Receiver-side jitter |
| `packets` | Received packet statistics from iperf3 |
| `receiver_ip` | Receiver T1S IPv4 address |
| `sender_ip` | Sender T1S IPv4 address |
| `note` | Failure information where available |

Example:

```csv
timestamp,status,receiver_host,overlay,spi_requested_hz,spi_requested_mhz,udp_target,received_mbit_s,lost_percent
2026-07-15T09:15:00+02:00,OK,pi1,BE-IIS-HPP-T1S-I,20000000,20.000,10M,9.998100,0
2026-07-15T09:20:00+02:00,OK,pi1,BE-IIS-HPP-T1S-I,19000000,19.000,10M,9.997800,0
```

## Failure behaviour

If an iperf3 measurement fails:

- the failed point is written to the CSV with `status=FAILED`;
- the SPI clock is not reduced further;
- the Device Tree source is not intentionally advanced to the next test point.

If overlay compilation or installation fails, the script restores the previous
DTS source file from a temporary backup.

## Restoring the normal SPI clock

The sweep modifies the selected tracked DTS source file. After the test, restore
the repository version or manually set the required production frequency.

To restore the Git version:

```bash
cd /path/to/be-iis-installer

git restore \
  products/BE-IIS-HPP-T1S-REVB/overlays/src/rpi/BE-IIS-HPP-T1S-I.dts
```

Rebuild and reinstall the overlays:

```bash
make -C \
  products/BE-IIS-HPP-T1S-REVB/overlays/src/rpi \
  clean all install

sudo reboot
```

Adjust the overlay filename when testing instance II or III.

## Repository notes

The sweep changes a tracked Device Tree source file during normal operation.
Before committing, inspect the repository state:

```bash
git status --short
git diff -- products/BE-IIS-HPP-T1S-REVB/overlays/src/rpi
```

Normally commit the test script and documentation, but not the temporary low
SPI frequency left in the overlay source and not the locally generated CSV
unless the measurement results are intentionally part of the repository.
