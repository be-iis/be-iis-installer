#!/usr/bin/env bash
# BE-IIS installer: stable, customer-facing entry point.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STAGES=(
    01_install_eepdump.sh
    02_install-mods.sh
    03_install-overlays.sh
    04_install_hatpp_service.sh
    05_install-udev-rules.sh
    06_I2C_VC_ena.sh
)
SUCCESSFUL=0
FAILED=0
FAILED_STAGE=""
GREEN='' RED='' YELLOW='' RESET=''
if [[ -t 1 && -z "\${NO_COLOR:-}" ]]; then
    GREEN=$'\033[32m'; RED=$'\033[31m'
    YELLOW=$'\033[33m'; RESET=$'\033[0m'
fi
log() { printf '[INFO] %s\n' "$*"; }
fail() { printf '%s[ERROR] %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

print_build_summary() {
    local report="$ROOT/build/install-report.json"
    [[ -f "$report" ]] || { printf '%s[WARN] No build report found%s\n' "$YELLOW" "$RESET"; return; }
    python3 - "$report" "$([[ -t 1 && -z "\${NO_COLOR:-}" ]] && echo yes || echo no)" <<'PY'
import json
import sys

palette = {"PASS": "\033[32m", "SKIP": "\033[33m", "FAIL": "\033[31m"}
color = sys.argv[2] == "yes"
try:
    with open(sys.argv[1], encoding="utf-8") as fp:
        tasks = json.load(fp)["tasks"]
except (OSError, KeyError, ValueError) as exc:
    print("[WARN] Cannot display build report:", exc)
else:
    counts = {"PASS": 0, "SKIP": 0, "FAIL": 0}
    print("\n[INFO] Product build summary:")
    for name, steps in tasks.items():
        state = ("SKIP" if not steps else
                 "FAIL" if any(step.get("status") == "failed" for step in steps) else
                 "PASS" if all(step.get("status") == "ok" for step in steps) else "SKIP")
        counts[state] += 1
        line = f"  [{state}] {name}"
        if color:
            line = palette[state] + line + "\033[0m"
        print(line)
    print(f"[INFO] Builds passed: {counts['PASS']} | skipped: {counts['SKIP']} | failed: {counts['FAIL']}")
    print("[INFO] Note: build success does not by itself confirm kernel-module installation.")
PY
}

print_final_summary() {
    printf '\n'
    log '--------------------------------------------------'
    if (( FAILED == 0 && SUCCESSFUL == \${#STAGES[@]} )); then
        printf '%s[INFO] Installation complete.%s\n' "$GREEN" "$RESET"
    else
        printf '%s[ERROR] Installation incomplete.%s\n' "$RED" "$RESET"
    fi
    log "Total scripts : \${#STAGES[@]}"
    log "Successful    : $SUCCESSFUL"
    log "Failed        : $FAILED"
    if [[ -n "$FAILED_STAGE" ]]; then
        printf '%s[ERROR] Failed script: %s%s\n' "$RED" "$FAILED_STAGE" "$RESET"
    fi
    print_build_summary
    if (( FAILED == 0 )); then
        log 'Changes active after reboot:'
        log '  - systemd service'
        log '  - udev rules'
        log '  - module autoload / runtime setup'
    fi
    log '--------------------------------------------------'
    printf '\n'
}

command -v sudo >/dev/null 2>&1 || fail "sudo is required"
command -v apt-get >/dev/null 2>&1 || fail "apt-get is required (Debian / Raspberry Pi OS)"

log 'Installing system packages (including Python 3)'
sudo apt-get update
sudo apt-get install -y \
    python3 git cmake make gcc build-essential \
    device-tree-compiler libncurses-dev libfdt-dev libgnutls28-dev \
    pkg-config wget curl bc kmod automake autoconf libtool i2c-tools
command -v python3 >/dev/null 2>&1 || fail 'Python 3 is missing'
log 'Preparing kernel build environment'
bash "$ROOT/scripts/bootstrap/prepare-rpi-build-env.sh"

for name in "\${STAGES[@]}"; do
    log "Running $name"
    if bash "$SCRIPT_DIR/$name"; then
        SUCCESSFUL=$((SUCCESSFUL + 1))
        printf '%s[INFO] OK: %s%s\n' "$GREEN" "$name" "$RESET"
    else
        FAILED=$((FAILED + 1))
        FAILED_STAGE="$name"
        print_final_summary
        fail "Installation stopped (no reboot)"
    fi
done

print_final_summary
if [[ -t 0 ]]; then
    read -r -p 'Press ENTER to reboot now or CTRL+C to cancel ...'
    sudo reboot
else
    log 'Non-interactive run: reboot not requested.'
fi
