#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BIN_SRC="$REPO_ROOT/platform/raspberry-pi-os/bin/apply-hat-overlays.sh"
SERVICE_SRC="$REPO_ROOT/platform/raspberry-pi-os/systemd/be-iis-hatpp.service"

BIN_DST="/usr/local/bin/apply-hat-overlays.sh"
SERVICE_DST="/etc/systemd/system/be-iis-hatpp.service"

log() {
    printf '[INFO] %s\n' "$*"
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

# -----------------------------------------------------------------------------
# Checks
# -----------------------------------------------------------------------------

[[ -f "$BIN_SRC" ]] || die "Missing script: $BIN_SRC"
[[ -f "$SERVICE_SRC" ]] || die "Missing service: $SERVICE_SRC"

if [[ $EUID -ne 0 ]]; then
    log "Re-running with sudo..."
    exec sudo "$0" "$@"
fi

# -----------------------------------------------------------------------------
# Install binary
# -----------------------------------------------------------------------------

log "Installing apply-hat-overlays.sh"
install -m 755 "$BIN_SRC" "$BIN_DST"

# -----------------------------------------------------------------------------
# Install systemd service
# -----------------------------------------------------------------------------

log "Installing systemd service"
install -m 644 "$SERVICE_SRC" "$SERVICE_DST"

# -----------------------------------------------------------------------------
# Reload systemd
# -----------------------------------------------------------------------------

log "Reloading systemd"
systemctl daemon-reload

# -----------------------------------------------------------------------------
# Enable service for next boot only
# -----------------------------------------------------------------------------

log "Enabling service for next boot"
systemctl enable be-iis-hatpp.service

log "Service installed."
log "It will start automatically after the next reboot."
log "To start it manually later, run:"
log "  sudo systemctl start be-iis-hatpp.service"
log "To check status after reboot, run:"
log "  systemctl status be-iis-hatpp.service --no-pager"

log "Done."