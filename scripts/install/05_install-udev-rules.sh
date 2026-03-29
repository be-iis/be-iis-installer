#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="${REPO_ROOT}/platform/raspberry-pi-os/udev/rules.d"
DST_DIR="/etc/udev/rules.d"

log() {
    printf '[INFO] %s\n' "$*"
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

if [[ ! -d "${SRC_DIR}" ]]; then
    die "Source directory not found: ${SRC_DIR}"
fi

log "Installing udev rules"
log "Source:      ${SRC_DIR}"
log "Destination: ${DST_DIR}"

sudo mkdir -p "${DST_DIR}"

shopt -s nullglob
rules=( "${SRC_DIR}"/* )
shopt -u nullglob

if [[ ${#rules[@]} -eq 0 ]]; then
    die "No rule files found in ${SRC_DIR}"
fi

for file in "${rules[@]}"; do
    if [[ -f "${file}" ]]; then
        log "Installing $(basename "${file}")"
        sudo install -m 0644 "${file}" "${DST_DIR}/"
    fi
done

log "udev rules installed"
log "They will become active after the next reboot."
log "If you want to activate them manually later, run:"
log "  sudo udevadm control --reload-rules"
log "  sudo udevadm trigger"

log "Done."