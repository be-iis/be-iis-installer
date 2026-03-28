#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-$HOME/be-iis-installer}"
OVERLAY_SRC="$REPO_ROOT/overlays/raspberry-pi"

log() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

# -----------------------------------------------------------------------------
# Detect overlay target directory
# -----------------------------------------------------------------------------

if [[ -d /boot/firmware/overlays ]]; then
    OVERLAY_DST="/boot/firmware/overlays"
elif [[ -d /boot/overlays ]]; then
    OVERLAY_DST="/boot/overlays"
else
    die "No overlay directory found (expected /boot/overlays or /boot/firmware/overlays)"
fi

log "Using overlay destination: $OVERLAY_DST"

[[ -d "$OVERLAY_SRC" ]] || die "Overlay source not found: $OVERLAY_SRC"

# -----------------------------------------------------------------------------
# Copy overlays
# -----------------------------------------------------------------------------

count=0

for dir in "$OVERLAY_SRC"/*; do
    [[ -d "$dir/build" ]] || continue

    log "Processing $(basename "$dir")"

    for dtbo in "$dir"/build/*.dtbo; do
        [[ -e "$dtbo" ]] || continue

        log "Copying $(basename "$dtbo")"
        sudo cp -f "$dtbo" "$OVERLAY_DST/"
        ((count+=1))
    done
done

log "Done. Copied $count overlay(s)."
