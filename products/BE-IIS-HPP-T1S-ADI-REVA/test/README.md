# ADIN1140 Rev A bring-up tests

Hardware bring-up is **pending**. These checks are separate from the previously successful onsemi S2500 measurements.

## Single HAT discovery (read-only)

Power off the Pi before moving any HAT. After boot:

```sh
bash products/BE-IIS-HPP-T1S-ADI-REVA/test/check_bringup.sh
```

Validate HAT++ EEPROM identification, the live `adi,adin1140` SPI node, SPI driver binding, IRQ routing and a newly registered Ethernet interface. Device Tree presence alone does not demonstrate that the driver probe succeeds.

Instance mapping: I = `spi0.0` / GPIO6 IRQ; II = `spi0.1` / GPIO5; III = `spi0.2` / GPIO12. The existing Instance-I DTS uses 20 MHz maximum SPI clock.

The unified driver package was built previously for Linux 6.12.47+rpt-rpi-v8; this is not yet an ADI hardware validation.

## Optional stacking test

Use two ADI boards connected with an appropriate 10BASE-T1S cable, and ensure PLCA configuration is appropriate for both PHYs. Do not move a management interface into a test namespace. The script moves real network interfaces; WLAN/eth0 are not touched.

```sh
sudo bash products/BE-IIS-HPP-T1S-ADI-REVA/test/stack_netns.sh setup
sudo ip netns exec t1s0 ping -c 20 -I beiis-t1s-adi0 192.168.78.2
sudo ip netns exec t1s1 ping -c 20 -I beiis-t1s-adi1 192.168.78.1
```

Throughput test using two terminals (first server, then client):

```sh
sudo ip netns exec t1s1 iperf3 -s -B 192.168.78.2
sudo ip netns exec t1s0 iperf3 -c 192.168.78.2 -B 192.168.78.1 -t 30
sudo ip netns exec t1s0 iperf3 -c 192.168.78.2 -B 192.168.78.1 -u -b 2M -t 30 --get-server-output
```

Judge the receiver throughput and packet loss rather than sender-only UDP rates. Two MAC-PHYs on a shared Raspberry Pi SPI controller do not represent a two-host standalone throughput test.

After testing:

```sh
sudo bash products/BE-IIS-HPP-T1S-ADI-REVA/test/stack_netns.sh cleanup
```

Record measured results in [RESULTS.md](RESULTS.md).
