# BE-IIS-HPP-T1S-ADI Rev A validation record

**Hardware status: BASIC BRING-UP PASSED (2026-10-17).**

Two ADI ADIN1140 HATs were tested on **two separate Raspberry Pis**, each running Debian 13 (trixie).

| Check | Status | Actual observation |
| --- | --- | --- |
| HAT++ EEPROM product / instance | PASS | `BE-IIS-HPP-T1S-ADI-I_v0` on Pi3; Instance I |
| Effective SPI Device Tree | PASS | `spi0.0` appeared after applying `BE-IIS-HPP-T1S-ADI-REVA-I` manually |
| Automatic HAT+ overlay loading | PASS (user confirmed) | Correct EEPROM-named `BE-IIS-HPP-T1S-ADI-I.dtbo` deployed; later boot worked automatically |
| `adin1140` bound to SPI device | PASS | `adin1140 spi0.0 eth0` reported by kernel |
| Shared `oa_tc6` and PHY dependency | PASS | Unified stack compiled and ABI checked on both kernels; PHY attach reported |
| PHY link | PASS | `Link is Up - 10Mbps/Half - flow control off` (Pi3) |
| Stable udev name | PASS | `beiis-t1s-adi0` reported on Pi2 and Pi3 |
| Communication between two Pis | PASS | Throughput test completed (user report) |
| Throughput | PASS (initial) | Approximately **7 Mbit/s**, user reported; full iperf3 transcript not recorded |
| Two-board stack on one Pi | Not tested | Separate-Pi ADI test only |
| Ping RTT / packet loss | Not recorded | |
| TCP retransmissions | Not recorded | |
| UDP receive rate / packet loss | Not recorded | |
| Long-duration stability | Pending | |

## Test systems

- **Pi2:** kernel `6.12.47+rpt-rpi-v8`.
- **Pi3:** kernel `6.18.34+rpt-rpi-v8`.
- Both used the shared BE-IIS T1S driver stack built for their respective kernels.

## Notes

The initial manual `sudo dtoverlay BE-IIS-HPP-T1S-ADI-REVA-I` test proved SPI driver binding and PHY link-up on Pi3. Subsequently the correctly named EEPROM overlay was deployed; automatic startup was reported working.

The approximately 7 Mbit/s figure is a preliminary measured throughput reported during testing, not a guaranteed product throughput. Repeat with archived client/server iperf3 output to document direction, TCP retransmissions, UDP loss and stability.
