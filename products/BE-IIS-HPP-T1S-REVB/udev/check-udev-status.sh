#!/usr/bin/env bash
# Check status of udev and list applied rules for troubleshooting

set -e

echo "[INFO] udev service status:"
systemctl status udev || echo "[WARN] Could not get udev service status."

echo -e "\n[INFO] Active udev rules in /etc/udev/rules.d/:"
ls -l /etc/udev/rules.d/

echo -e "\n[INFO] Last 20 udev log lines:"
journalctl -u systemd-udevd --no-pager -n 20 || echo "[WARN] Could not read systemd-udevd logs."
