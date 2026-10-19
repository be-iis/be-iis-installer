#!/usr/bin/env bash
# Stable entry point for the BE-IIS installation on Raspberry Pi OS / Debian.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

STAGES_OK=()
STAGES_FAIL=()
log() { printf '[INFO] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

print_summary() {
    local report="$ROOT/build/install-report.json"
    local green="" yellow="" red="" kernel="" key="" value=""
    local use_color=0
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then use_color=1; fi
    local reset='' cgreen='' cyellow='' cred=''
    if (( use_color )); then
        reset= 2>&1 || die "sudo is required"
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
        STAGES_FAIL+=("$name")
        print_summary
        die "Installation failed in $name (stopped; no reboot)"
    fi
    STAGES_OK+=("$name")
done

log "Installation steps completed successfully."
print_summary
log "Changes to boot configuration / services may require a reboot."
if [[ -t 0 ]]; then
    read -r -p "Press ENTER to reboot now, or CTRL+C to cancel..."
    sudo reboot
else
    log "Non-interactive run: skipping automatic reboot."
fi
\\033[0m'; cgreen= 2>&1 || die "sudo is required"
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
        STAGES_FAIL+=("$name")
        print_summary
        die "Installation failed in $name (stopped; no reboot)"
    fi
    STAGES_OK+=("$name")
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
\\033[32m'; cyellow= 2>&1 || die "sudo is required"
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
        STAGES_FAIL+=("$name")
        print_summary
        die "Installation failed in $name (stopped; no reboot)"
    fi
    STAGES_OK+=("$name")
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
\\033[33m'; cred= 2>&1 || die "sudo is required"
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
        STAGES_FAIL+=("$name")
        print_summary
        die "Installation failed in $name (stopped; no reboot)"
    fi
    STAGES_OK+=("$name")
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
\\033[31m'
    fi
    printf '\\n========== BE-IIS INSTALLATION SUMMARY ==========\\n'
    printf 'Running kernel: %s\\n' "$(uname -r)"
    if [[ -s "$report" ]]; then
        python3 - "$report" "$use_color" <<'PY'
import json
import sys

path, colors = sys.argv[1], sys.argv[2] == "1"
codes = {"GREEN": "\\033[32m", "YELLOW": "\\033[33m", "RED": "\\033[31m"}
def paint(color, msg):
    return f"{codes[color]}{msg}\\033[0m" if colors else msg
try:
    with open(path, encoding="utf-8") as file:
        report = json.load(file)
except (OSError, ValueError) as exc:
    print(paint("RED", f"Build report cannot be read: {exc}"))
    sys.exit(0)
tasks = report.get("tasks", {})
counts = {"GREEN": 0, "YELLOW": 0, "RED": 0}
print("\\nKernel modules / device-tree builds:")
for name, steps in tasks.items():
    if not steps:
        status, detail = "YELLOW", "no build target / not executed"
    elif any(step.get("status") == "failed" for step in steps):
        status, detail = "RED", "failed"
    elif all(step.get("status") == "ok" for step in steps):
        status, detail = "GREEN", "passed"
    else:
        status, detail = "YELLOW", "incomplete"
    counts[status] += 1
    print(paint(status, f"  [{status}] {name}: {detail}"))
print(f"Build totals: GREEN={counts['GREEN']}  YELLOW={counts['YELLOW']}  RED={counts['RED']}")
print("Build artifacts are not necessarily installed kernel modules.")
PY
    else
        printf '%s\\n' "${cyellow}[YELLOW] No build report available.${reset}"
    fi
    printf '\\nInstallation stages:\\n'
    for key in "${STAGES_OK[@]}"; do printf '%s\\n' "${cgreen}[GREEN]${reset} $key"; done
    for key in "${STAGES_FAIL[@]}"; do printf '%s\\n' "${cred}[RED]${reset} $key"; done
    printf '%s\\n' "Build report: $report"
    printf '=================================================\\n\\n'
}

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
        STAGES_FAIL+=("$name")
        print_summary
        die "Installation failed in $name (stopped; no reboot)"
    fi
    STAGES_OK+=("$name")
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
