#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

REPO_URL="https://github.com/raspberrypi/utils.git"

SRC_DIR="${REPO_ROOT}/build/src/raspberrypi-utils"
BUILD_DIR="${REPO_ROOT}/build/cmake/raspberrypi-utils"
STAGE_DIR="${REPO_ROOT}/build/stage/raspberrypi-utils"

INSTALL_PREFIX="/usr/local"
INSTALL_BIN_DIR="${INSTALL_PREFIX}/bin"

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

log "STEP2: Preparing directories"
mkdir -p "${REPO_ROOT}/build/src"
mkdir -p "${REPO_ROOT}/build/cmake"
mkdir -p "${REPO_ROOT}/build/stage"

log "STEP3: Fetching sources"
if [[ ! -d "${SRC_DIR}/.git" ]]; then
    git clone --depth 1 "${REPO_URL}" "${SRC_DIR}"
else
    git -C "${SRC_DIR}" fetch --depth 1 origin
    git -C "${SRC_DIR}" reset --hard origin/HEAD
fi

[[ -f "${SRC_DIR}/CMakeLists.txt" ]] || die "CMakeLists.txt not found in ${SRC_DIR}"

log "STEP4: Cleaning old build/stage directories"
rm -rf "${BUILD_DIR}" "${STAGE_DIR}"
mkdir -p "${BUILD_DIR}" "${STAGE_DIR}"

log "STEP5: Configuring build"
cmake \
    -S "${SRC_DIR}" \
    -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DCMAKE_C_FLAGS="-Wno-error -Wno-alloc-size-larger-than"

log "STEP6: Building utils"
cmake --build "${BUILD_DIR}" -j"$(nproc)"

log "STEP7: Installing into staging directory"
DESTDIR="${STAGE_DIR}" cmake --install "${BUILD_DIR}"

log "STEP8: Installing selected tools to target"
for f in eepdump eepmake eepflash.sh; do
    [[ -f "${STAGE_DIR}${INSTALL_BIN_DIR}/${f}" ]] || die "Missing built file: ${STAGE_DIR}${INSTALL_BIN_DIR}/${f}"
done

sudo install -m 755 "${STAGE_DIR}${INSTALL_BIN_DIR}/eepdump"    "${INSTALL_BIN_DIR}/eepdump"
sudo install -m 755 "${STAGE_DIR}${INSTALL_BIN_DIR}/eepmake"    "${INSTALL_BIN_DIR}/eepmake"
sudo install -m 755 "${STAGE_DIR}${INSTALL_BIN_DIR}/eepflash.sh" "${INSTALL_BIN_DIR}/eepflash.sh"

log "STEP9: Verifying installation"
require_command eepdump
require_command eepmake
require_command eepflash.sh

log "Installed tools:"
log "  $(command -v eepdump)"
log "  $(command -v eepmake)"
log "  $(command -v eepflash.sh)"

log "Done."