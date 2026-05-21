#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-$HOME/be-iis-installer}"
PRODUCTS_DIR="$REPO_ROOT/products"

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
    die "No overlay directory found (expected /boot/firmware/overlays or /boot/overlays)"
fi

log "Using overlay destination: $OVERLAY_DST"

[[ -d "$PRODUCTS_DIR" ]] || die "Products directory not found: $PRODUCTS_DIR"

# -----------------------------------------------------------------------------
# Copy product overlays
# -----------------------------------------------------------------------------

count=0
products_seen=0

for product_dir in "$PRODUCTS_DIR"/BE-IIS*; do
    [[ -d "$product_dir" ]] || continue

    overlay_build_dir="$product_dir/overlays/build/rpi"

    [[ -d "$overlay_build_dir" ]] || continue

    product_name="$(basename "$product_dir")"
    log "Processing $product_name"

    products_seen=$((products_seen + 1))

    found_dtbo=0

    for dtbo in "$overlay_build_dir"/*.dtbo; do
        [[ -e "$dtbo" ]] || continue

        found_dtbo=1

        log "Copying $(basename "$dtbo")"
        sudo install -D -m 0644 "$dtbo" "$OVERLAY_DST/$(basename "$dtbo")"

        count=$((count + 1))
    done

    if [[ "$found_dtbo" -eq 0 ]]; then
        warn "No .dtbo files found in: $overlay_build_dir"
    fi
done

log "Done"
log "Products with overlay build dir : $products_seen"
log "Overlays copied                 : $count"