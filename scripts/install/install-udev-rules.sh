#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="${REPO_ROOT}/platform/raspberry-pi-os/udev/rules.d"
DST_DIR="/etc/udev/rules.d"

if [[ ! -d "${SRC_DIR}" ]]; then
    echo "Error: source directory not found: ${SRC_DIR}" >&2
    exit 1
fi

echo "Installing udev rules..."
echo "Source:      ${SRC_DIR}"
echo "Destination: ${DST_DIR}"

sudo mkdir -p "${DST_DIR}"

shopt -s nullglob
rules=( "${SRC_DIR}"/* )
shopt -u nullglob

if [[ ${#rules[@]} -eq 0 ]]; then
    echo "Error: no rule files found in ${SRC_DIR}" >&2
    exit 1
fi

for file in "${rules[@]}"; do
    if [[ -f "${file}" ]]; then
        echo "  -> $(basename "${file}")"
        sudo install -m 0644 "${file}" "${DST_DIR}/"
    fi
done

echo "Reloading udev rules..."
sudo udevadm control --reload-rules
sudo udevadm trigger

echo "Done."