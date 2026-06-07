#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BIN_SRC_DIR="$REPO_ROOT/platform/raspberry-pi-os/bin"
SBIN_SRC_DIR="$REPO_ROOT/platform/raspberry-pi-os/sbin"
SERVICE_SRC_DIR="$REPO_ROOT/platform/raspberry-pi-os/systemd"

BIN_DST_DIR="/usr/local/bin"
SBIN_DST_DIR="/usr/local/sbin"
SERVICE_DST_DIR="/etc/systemd/system"

log() {
    printf '[INFO] %s\n' "$*"
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

install_files_from_dir() {
    local src_dir="$1"
    local dst_dir="$2"
    local mode="$3"
    local label="$4"

    if [[ ! -d "$src_dir" ]]; then
        log "Skipping $label: directory not found: $src_dir"
        return 0
    fi

    log "Installing $label from $src_dir to $dst_dir"
    install -d -m 755 "$dst_dir"

    shopt -s nullglob
    local files=("$src_dir"/*)
    shopt -u nullglob

    if (( ${#files[@]} == 0 )); then
        log "No files found in $src_dir"
        return 0
    fi

    local file
    for file in "${files[@]}"; do
        [[ -f "$file" ]] || continue
        log "Installing $(basename "$file")"
        install -m "$mode" "$file" "$dst_dir/$(basename "$file")"
    done
}

# -----------------------------------------------------------------------------
# Privilege check
# -----------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    log "Re-running with sudo..."
    exec sudo "$0" "$@"
fi

# -----------------------------------------------------------------------------
# Basic checks
# -----------------------------------------------------------------------------

[[ -d "$BIN_SRC_DIR" || -d "$SBIN_SRC_DIR" ]] || die "No bin/sbin source directory found"
[[ -d "$SERVICE_SRC_DIR" ]] || die "Missing service directory: $SERVICE_SRC_DIR"

# -----------------------------------------------------------------------------
# Install files
# -----------------------------------------------------------------------------

install_files_from_dir "$BIN_SRC_DIR" "$BIN_DST_DIR" 755 "user tools"
install_files_from_dir "$SBIN_SRC_DIR" "$SBIN_DST_DIR" 755 "system scripts"
install_files_from_dir "$SERVICE_SRC_DIR" "$SERVICE_DST_DIR" 644 "systemd services"

# -----------------------------------------------------------------------------
# Reload systemd
# -----------------------------------------------------------------------------

log "Reloading systemd"
systemctl daemon-reload

# -----------------------------------------------------------------------------
# Enable all installed services
# -----------------------------------------------------------------------------

shopt -s nullglob
services=("$SERVICE_SRC_DIR"/*.service)
shopt -u nullglob

if (( ${#services[@]} == 0 )); then
    log "No systemd service files found in $SERVICE_SRC_DIR"
else
    for service_path in "${services[@]}"; do
        service_name="$(basename "$service_path")"

        log "Enabling $service_name"
        systemctl enable "$service_name"
    done
fi

log "Installation complete."
log "Installed user tools:    $BIN_DST_DIR"
log "Installed system tools:  $SBIN_DST_DIR"
log "Installed services:      $SERVICE_DST_DIR"
log ""
log "To start a service manually:"
log "  sudo systemctl start <service-name>.service"
log ""
log "To check status:"
log "  systemctl status <service-name>.service --no-pager"