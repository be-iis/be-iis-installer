# BE-IIS-HPP-T1S-ONSEMI Rev A test results

**Status: BASIC BRING-UP PASSED (2026-10-16); throughput and stability not yet validated.**

Platform: one Raspberry Pi (Pi2), Debian 13, kernel `6.12.47+rpt-rpi-v8`, with two stacked S2500 HATs on the same SPI controller.

| Check | Status | Observation |
| --- | --- | --- |
| HAT++ EEPROM Instance I | PASS | `BE-IIS-HPP-T1S-ON-I_v0` / Brechel |
| SPI driver binding | PASS | `spi0.0` bound to `s2500` |
| Shared OA-TC6 modules | PASS | `s2500`, `ncn26000`, `oa_tc6` loaded |
| Stacking | PASS | Two onsemi network interfaces, `beiis-t1s-on0` and `beiis-t1s-on1` |
| Bidirectional ping | PASS (short run) | 7/7 received, average 1.226 ms; 5/5 received, average 1.134 ms |
| TCP reverse iperf3 | PARTIAL | 2.73 Mbit/s sender, 2.66 Mbit/s receiver, 263 retransmissions (30 s) |
| UDP `-b 5M` | LOSS | 2.83 Mbit/s receiver, 45% packet loss (interrupted at 9 s) |
| UDP `-b 9M` | LOSS | 2.59 Mbit/s receiver, 69% packet loss (interrupted at 20 s) |
| Long-term stability | PENDING | Not measured |

The tester observed a poorly seated cable during the session. The timing and effect of reseating were not quantified in a controlled receiver-side retest. UDP client sender values above 10 Mbit/s must **not** be interpreted as physical 10BASE-T1S throughput.

Both HATs share one Raspberry Pi SPI controller, which can reduce throughput compared with a test between independent hosts. These observations demonstrate basic functionality, not a guaranteed or maximum data rate.
