#!/usr/bin/env python3
"""Validate a unified T1S build against one OA-TC6 provider; read-only."""
from pathlib import Path
import subprocess
import sys

MODULES = ("oa_tc6", "lan865x", "microchip_t1s", "adin1140",
           "adin1140-phy", "s2500", "ncn26000")

def output(*argv):
    p = subprocess.run(argv, capture_output=True, text=True, check=False)
    if p.returncode:
        raise RuntimeError(f"{' '.join(map(str, argv))}: {p.stderr.strip()}")
    return p.stdout

def symbols(path):
    found = {}
    for line in output("modprobe", "--show-modversions", str(path)).splitlines():
        words = line.split()
        if len(words) == 2 and words[1].startswith("oa_tc6_"):
            found[words[1]] = words[0].lower()
    return found

def exports(path):
    result = {}
    for line in path.read_text().splitlines():
        cols = line.split()
        if (len(cols) >= 4 and cols[1].startswith("oa_tc6_")
                and Path(cols[2]).name.removesuffix(".ko").removesuffix(".o") == "oa_tc6"):
            result[cols[1]] = cols[0].lower()
    return result

def main():
    if len(sys.argv) != 2:
        print("Usage: check_t1s_stack.py BUILD_DIRECTORY", file=sys.stderr)
        return 2
    root = Path(sys.argv[1]).resolve()
    try:
        for name in MODULES:
            file = root / (name + ".ko")
            if not file.is_file():
                raise RuntimeError(f"Missing module: {file}")
            print(f"FOUND {name}: {output('modinfo', '-F', 'vermagic', str(file)).strip()}")
        available = exports(root / "Module.symvers")
        if not available:
            raise RuntimeError("No OA-TC6 exports found in the unified Module.symvers")
        consumers = ("lan865x", "adin1140", "s2500")
        for name in consumers:
            needed = symbols(root / (name + ".ko"))
            if not needed:
                raise RuntimeError(f"{name} references no OA-TC6 symbols; inspect build")
            for symbol, crc in needed.items():
                if symbol not in available:
                    raise RuntimeError(f"{name}: OA-TC6 export {symbol} missing")
                if available[symbol] != crc:
                    raise RuntimeError(f"{name}: CRC mismatch for {symbol}: {crc} vs {available[symbol]}")
            print(f"OK {name}: {len(needed)} OA-TC6 symbol CRCs match")
        print("PASS: single-build symbol compatibility; no modules installed")
        return 0
    except (OSError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
