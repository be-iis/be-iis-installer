#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/raspberrypi/utils.git"
WORK_DIR="/tmp/raspberrypi-utils"
BUILD_DIR="$WORK_DIR/build"

log() {
    printf '[INFO] %s\n' "$*"
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

log "STEP1: Installing prerequisites"
sudo apt-get update
sudo apt-get install -y \
    git \
    cmake \
    make \
    gcc \
    device-tree-compiler \
    libncurses-dev \
    libfdt-dev \
    libgnutls28-dev \
    build-essential

require_command git
require_command cmake
require_command make
require_command gcc
require_command sudo

log "STEP2: Preparing work directory"
rm -rf "$WORK_DIR"
git clone --depth 1 "$REPO_URL" "$WORK_DIR"

[[ -f "$WORK_DIR/CMakeLists.txt" ]] || die "CMakeLists.txt not found in $WORK_DIR"

log "STEP3: Configuring build"
cmake -S "$WORK_DIR" -B "$BUILD_DIR"

log "STEP4: Building utils"
cmake --build "$BUILD_DIR" -j"$(nproc)"

log "STEP5: Installing utils"
sudo cmake --install "$BUILD_DIR"

log "STEP6: Verifying installation"
require_command eepdump
require_command eepmake
require_command eepflash.sh

log "Installed tools:"
log "  $(command -v eepdump)"
log "  $(command -v eepmake)"
log "  $(command -v eepflash.sh)"

log "Done."