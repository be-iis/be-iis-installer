#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
"$ROOT/tools/kernel/s2500_mod_build.sh"
make -C "$ROOT/products/BE-IIS-HPP-T1S-ONSEMI-REVA/overlays/src/rpi"
