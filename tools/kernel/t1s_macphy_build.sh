#!/usr/bin/env bash
# Build one T1S MAC-PHY group against the independently built OA-TC6 provider.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"
OUT="$ROOT/build/t1s-unified"
CORE="$OUT/oa-tc6"

[[ $# == 1 ]] || { echo "Usage: $0 {adi|onsemi|microchip}" >&2; exit 2; }
[[ -d "$KDIR" && -s "$CORE/Module.symvers" ]] || {
    echo "ERROR: build the independent OA-TC6 provider first" >&2
    exit 1
}

case "$1" in
  adi)
    name="ADIN1140"; directory="$OUT/adin1140"
    modules=(adin1140 adin1140-phy)
    ;;
  onsemi)
    name="onsemi S2500/NCN26000"; directory="$OUT/onsemi"
    modules=(s2500 ncn26000)
    ;;
  microchip)
    name="Microchip LAN865x"; directory="$OUT/microchip"
    modules=(lan865x microchip_t1s)
    ;;
  *) echo "Usage: $0 {adi|onsemi|microchip}" >&2; exit 2 ;;
esac

[[ -f "$directory/Makefile" ]] || {
    echo "ERROR: prepared $name sources are missing; run t1s_unified_build.sh --core-only first" >&2
    exit 1
}

printf 'Building %s MAC-PHY modules against OA-TC6 Module.symvers\n' "$name"
make -C "$KDIR" M="$directory" KBUILD_EXTRA_SYMBOLS="$CORE/Module.symvers" modules
for module in "${modules[@]}"; do
    cp "$directory/$module.ko" "$OUT/$module.ko"
done
printf '%s MAC-PHY modules built\n' "$name"
