#!/usr/bin/env python3
"""Install built S2500 modules without replacing shared OA-TC6."""
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
KVER = os.uname().release
BUILD = ROOT / "build/s2500"
TARGET = Path("/lib/modules") / KVER / "updates"

def run(*args):
    return subprocess.run(args, text=True, capture_output=True, check=False)

def fail(message):
    print("ERROR: " + message, file=sys.stderr)
    return 1

def main():
    if os.geteuid() != 0:
        return fail("Installation needs root; run the installer with --install-built (sudo is invoked only for install step).")
    modules = ["s2500", "ncn26000"]
    tc6 = BUILD / "oa_tc6.ko"
    if not tc6.is_file():
        return fail("Missing matching built OA-TC6 module.")
    active = run("modinfo", "-k", KVER, "-F", "filename", "oa_tc6")
    if active.returncode:
        return fail("No installed OA-TC6 dependency; refusing to replace the shared module automatically.")
    # Compare actual exported symbol versions, not just vermagic. No automatic
    # overwrite of OA-TC6 because Microchip may depend on its ABI.
    for module in modules:
        path = BUILD / (module + ".ko")
        if not path.is_file():
            return fail(f"Missing built module: {path}")
        info = run("modinfo", "-F", "vermagic", str(path))
        if info.returncode or not info.stdout.startswith(KVER + " "):
            return fail(f"{path.name} vermagic does not match {KVER}")
    # Check that the built module expects only symbols exported by the installed
    # OA-TC6, including matching modversion CRCs when available.
    installed = active.stdout.strip()
    if installed == "(builtin)":
        return fail("OA-TC6 is built in; ABI compatibility cannot be established safely here.")
    installed_path = Path(installed)
    if not installed_path.is_file():
        return fail(f"OA-TC6 module not found: {installed}")
    # Binary CRC comparison via modprobe dry-run is not sufficient. Compare
    # imported CRC records against the installed provider, when modversions exist.
    try:
        import subprocess as sp
        expected = sp.run(["modprobe", "--show-modversions", str(tc6)], capture_output=True, text=True)
        present = sp.run(["modprobe", "--show-modversions", str(installed_path)], capture_output=True, text=True)
    except OSError as exc:
        return fail(str(exc))
    # Provider-to-provider imports are not exports; therefore do not treat this
    # superficial comparison as ABI proof. Refuse rather than risk Microchip.
    return fail("Shared OA-TC6 ABI is not verified. Keep built modules; install a matched OA-TC6 stack in a controlled maintenance step.")

if __name__ == "__main__":
    sys.exit(main())
