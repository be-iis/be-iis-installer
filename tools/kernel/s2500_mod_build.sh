#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/t1s_source_common.sh"

KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"
TC6="$REPO_ROOT/build/oa_tc6"
OUT="$REPO_ROOT/build/s2500"

[[ -d "$KDIR" ]] || t1s_die "Kernel headers not found: $KDIR"

# Skip the external build when the running kernel already provides the
# driver. FORCE_BUILD=1 is intended for development and compatibility tests.
if modinfo s2500 >/dev/null 2>&1 && [[ "${FORCE_BUILD:-0}" != "1" ]]; then
    t1s_note "Running kernel already provides s2500."
    t1s_note "Use FORCE_BUILD=1 to build the external S2500 module anyway."
    exit 0
fi

if [[ "${FORCE_BUILD:-0}" == "1" ]]; then
    t1s_note "FORCE_BUILD=1: building external S2500 module even if the kernel provides one."
fi

t1s_ensure_tc6_build "$REPO_ROOT"
SRC="$(t1s_prepare_s2500_v8_minimal "$REPO_ROOT")"

rm -rf "$OUT"
mkdir -p "$OUT"

cp "$SRC/drivers/net/ethernet/onsemi/s2500/s2500_main.c" "$OUT/"
cp "$SRC/drivers/net/ethernet/onsemi/s2500/s2500_ethtool.c" "$OUT/"
cp "$SRC/drivers/net/ethernet/onsemi/s2500/s2500_ptp.c" "$OUT/"
cp "$SRC/drivers/net/ethernet/onsemi/s2500/s2500_hw_def.h" "$OUT/"
cp "$SRC/drivers/net/phy/ncn26000.c" "$OUT/"
cp "$TC6/include/linux/oa_tc6.h" "$OUT/oa_tc6_local.h"

for src in "$OUT"/s2500_main.c "$OUT"/s2500_ethtool.c "$OUT"/s2500_ptp.c; do
    sed -i 's@#include <linux/oa_tc6.h>@#include "oa_tc6_local.h"@' "$src"
done

cat > "$OUT/Makefile" <<'EOF'
obj-m := s2500.o ncn26000.o
s2500-y := s2500_main.o s2500_ethtool.o s2500_ptp.o
ccflags-y += -I$(M)
EOF

TC6_MAKE_ARGS=()
if [[ -f "$TC6/.external" ]]; then
    TC6_MAKE_ARGS+=(KBUILD_EXTRA_SYMBOLS="$TC6/Module.symvers")
fi

make -C "$KDIR" M="$OUT" "${TC6_MAKE_ARGS[@]}" modules ||
    t1s_die "S2500 build failed against shared OA-TC6 baseline"

[[ -f "$OUT/s2500.ko" ]] || t1s_die "s2500.ko was not created"
[[ -f "$OUT/ncn26000.ko" ]] || t1s_die "ncn26000.ko was not created"

t1s_note "Built S2500 modules in $OUT"
