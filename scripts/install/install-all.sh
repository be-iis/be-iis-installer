#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$(basename "$0")"

log() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

count_total=0
count_ok=0
count_fail=0

shopt -s nullglob

for script in "$SCRIPT_DIR"/*.sh; do
    name="$(basename "$script")"

    # Skip itself
    if [[ "$name" == "$SELF" ]]; then
        continue
    fi

    ((count_total+=1))

    log "Running $name"

    chmod +x "$script"

    if "$script"; then
        log "OK: $name"
        ((count_ok+=1))
    else
        warn "FAILED: $name"
        ((count_fail+=1))
    fi
done

log "Done"
log "Total scripts : $count_total"
log "Successful    : $count_ok"
log "Failed        : $count_fail"

if [[ $count_fail -ne 0 ]]; then
    exit 1
fi

echo
log "--------------------------------------------------"
log "Installation complete."
log "The following changes will become active after reboot:"
log "  - systemd service"
log "  - udev rules"
log "  - module autoload / runtime setup"
log "--------------------------------------------------"
echo

read -rp "Press ENTER to reboot now or CTRL+C to cancel..."

log "Rebooting..."
sudo reboot