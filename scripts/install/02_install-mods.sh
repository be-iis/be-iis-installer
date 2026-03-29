#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
KERNEL_TOOLS_DIR="$REPO_ROOT/tools/kernel"

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

[[ -d "$KERNEL_TOOLS_DIR" ]] || die "Kernel tools directory not found: $KERNEL_TOOLS_DIR"

shopt -s nullglob

scripts=("$KERNEL_TOOLS_DIR"/*.sh)

if [[ ${#scripts[@]} -eq 0 ]]; then
    die "No shell scripts found in: $KERNEL_TOOLS_DIR"
fi

count_total=0
count_ok=0
count_fail=0

for script in "${scripts[@]}"; do
    ((count_total+=1))
    name="$(basename "$script")"

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
