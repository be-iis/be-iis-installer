#!/usr/bin/env bash
# Build kernel modules and overlays using the current Python task orchestrator.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
    echo "[ERROR] Python 3 is missing. Run scripts/install/install-all.sh first." >&2
    exit 1
}
cd "$ROOT"
exec python3 scripts/install_tasks.py "$@"
