#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
"$ROOT/tools/kernel/adin1140_mod_build.sh"
make -C "$ROOT/products/BE-IIS-HPP-T1S-ADI-REVA/overlays/src/rpi"
