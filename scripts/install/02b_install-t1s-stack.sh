#!/usr/bin/env bash
# Install the complete unified T1S kernel module stack after a successful build.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Never report a successful installation when the modules only compiled.
# The existing staging helper validates all seven modules and kernel vermagic,
# backs up existing update modules, installs atomically, runs depmod and checks
# modinfo resolution. It restores the backup if any of those steps fail.
python3 compatibility/t1s/install.py check
sudo python3 compatibility/t1s/install.py stage

echo "[INFO] Unified T1S kernel modules installed for $(uname -r); active after reboot."
