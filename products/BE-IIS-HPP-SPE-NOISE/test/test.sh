#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PRODUCT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

test -x "${PRODUCT_DIR}/scripts/noise-i2c-scan.sh"
test -x "${PRODUCT_DIR}/scripts/noise-status.sh"
grep -q 'DEVICE_ID' "${PRODUCT_DIR}/docs/I2C_INTERFACE.md"
echo "Product skeleton checks passed. Hardware I2C test is intentionally manual."
