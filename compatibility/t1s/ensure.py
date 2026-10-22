#!/usr/bin/env python3
"""T1S-only compatibility dispatcher. Build-only; never installs modules."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
NEEDS = {
    "adi": ("adin1140", "adin1140-phy", "oa_tc6"),
    "onsemi": ("s2500", "ncn26000", "oa_tc6"),
    "microchip": ("lan865x", "microchip_t1s", "oa_tc6"),
}

def available(module):
    p = subprocess.run(["modinfo", "-k", os.uname().release, "-F", "filename", module],
                       capture_output=True, text=True)
    if p.returncode:
        return False
    name = p.stdout.strip()
    if name == "(builtin)":
        return True
    path = Path(name)
    return path.is_absolute() and path.is_file() and (
        subprocess.run(["modinfo", "-F", "vermagic", str(path)],
                       capture_output=True, text=True).stdout.split()[:1] == [os.uname().release]
    )

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("products", nargs="+", choices=sorted(NEEDS))
    args = parser.parse_args()
    selected = tuple(dict.fromkeys(args.products))
    missing = sorted({m for p in selected for m in NEEDS[p] if not available(m)})
    if not missing:
        print("T1S: required native/installed modules available; backport skipped")
        return 0
    print(f"T1S: missing modules: {', '.join(missing)}", flush=True)
    print("T1S: building unified compatibility stack (NOT installing)", flush=True)
    build = subprocess.run(["bash", str(ROOT / "tools/kernel/t1s_unified_build.sh")], cwd=ROOT)
    if build.returncode:
        return build.returncode
    print("T1S: unified modules built; use compatibility/t1s/install.py for guarded staging", flush=True)
    return 0

if __name__ == "__main__":
    sys.exit(main())
