# Unified T1S installation and recovery

The installer stages the coherent seven-module package without unloading kernel modules.
Staging is **not** equivalent to a working driver: test boot, SPI binding, link and LAN865x regression separately.

```sh
python3 scripts/t1s_stack_install.py check
sudo python3 scripts/t1s_stack_install.py stage
```

Before rebooting, ensure console or alternate network access; the OA-TC6 module used by Microchip is replaced **on disk**. Existing loaded modules continue running until reboot. Save the backup directory printed by the stage command. Do not activate on production devices until validated on a test Pi.

After reboot:
```sh
uname -r
lsmod | grep -E 'oa_tc6|lan865x|s2500|adin1140'
readlink -f /sys/bus/spi/devices/spi0.0/driver
ip -br link
sudo dmesg | grep -Ei 'oa.tc6|s2500|ncn26000' | tail -60
```

If the device does not boot properly, recover via alternate boot or filesystem access and restore the backed-up modules before booting again. If it boots with the same kernel, rollback the printed path:

```sh
sudo python3 scripts/t1s_stack_install.py rollback /var/lib/be-iis/t1s-backups/<backup-id>
sudo reboot
```

Safety boundaries: `stage` first verifies expected modules and CRCs, backs up **existing files in updates/**, copies complete package, runs depmod, checks resolution, and rolls back if anything fails. It does not automatically reboot. Backups are kernel-release scoped; do not reuse on a different kernel.

Limitation: this early installer does not capture modules installed outside `updates/`; if `modinfo` resolves to another directory, staging aborts and restores. Review the loaded modules and original paths before staging. Never stage while another package manager or kernel update is touching /lib/modules.
