#!/usr/bin/env bash
# Stable entry point for the BE-IIS installation on Raspberry Pi OS / Debian.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

log() { printf '[INFO] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

command -v sudo >/dev/null 2>&1 || die "sudo is required"
command -v apt-get >/dev/null 2>&1 || die "apt-get is required (Raspberry Pi OS / Debian)"

# Python is needed by the new parallel build orchestrator. Install all base
# dependencies BEFORE attempting to start Python or any compilation.
log "STEP 1/3: Installing system packages"
sudo apt-get update
sudo apt-get install -y \
    python3 \
    git cmake make gcc build-essential \
    device-tree-compiler libncurses-dev libfdt-dev libgnutls28-dev \
    pkg-config wget curl bc kmod automake autoconf libtool \
    i2c-tools
command -v python3 >/dev/null 2>&1 || die "python3 is unavailable after package installation"

log "STEP 2/3: Preparing kernel build environment"
"$ROOT/scripts/bootstrap/prepare-rpi-build-env.sh"

log "STEP 3/3: Running BE-IIS installation"
# Run explicit stages in order. Never enumerate every .sh script: that would
# run old standalone driver builders instead of the Python orchestrator.
for name in \
    01_install_eepdump.sh \
    02_install-mods.sh \
    03_install-overlays.sh \
    04_install_hatpp_service.sh \
    05_install-udev-rules.sh \
    06_I2C_VC_ena.sh; do
    log "Running $name"
    if ! bash "$SCRIPT_DIR/$name"; then
        die "Installation failed in $name (stopped; no reboot)"
    fi
done

log "Installation steps completed successfully."
log "Build report: $ROOT/build/install-report.json"
log "Changes to boot configuration / services may require a reboot."
if [[ -t 0 ]]; then
    read -r -p "Press ENTER to reboot now, or CTRL+C to cancel..."
    sudo reboot
else
    log "Non-interactive run: skipping automatic reboot."
fi
