#!/usr/bin/env python3
"""Conservatively install S2500 modules, preserving the shared OA-TC6 provider."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
KVER = os.uname().release
BUILD = ROOT / "build/s2500"
TARGET = Path("/lib/modules") / KVER / "updates"

def run(*args):
    return subprocess.run(args, text=True, capture_output=True, check=False)

def error(message):
    print("ERROR: " + message, file=sys.stderr)
    return 1

def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(data)
    return h.hexdigest()

def main():
    if os.geteuid() != 0:
        return error("Root permission is required to install modules.")
    modules = ["s2500", "ncn26000"]
    built_tc6 = BUILD / "oa_tc6.ko"
    if not built_tc6.is_file():
        return error("Matching OA-TC6 build is missing.")
    info = run("modinfo", "-k", KVER, "-F", "filename", "oa_tc6")
    if info.returncode != 0:
        return error("Installed OA-TC6 provider is missing.")
    installed_tc6 = info.stdout.strip()
    if installed_tc6 == "(builtin)":
        return error("OA-TC6 is built in; cannot prove ABI compatibility with the external build.")
    installed_tc6 = Path(installed_tc6)
    if not installed_tc6.is_file():
        return error(f"Installed OA-TC6 not found: {installed_tc6}")
    # Comparing vermagic is not enough. Byte identity is a conservative,
    # sufficient check that both vendor drivers use the same OA-TC6 build.
    if sha256(built_tc6) != sha256(installed_tc6):
        return error("Installed OA-TC6 differs from the freshly built provider. "
                     "Refusing to overwrite it because Microchip may depend on it.")
    for module in modules:
        path = BUILD / (module + ".ko")
        if not path.is_file():
            return error(f"Missing built module: {path}")
        ver = run("modinfo", "-F", "vermagic", str(path))
        if ver.returncode or ver.stdout.split()[:1] != [KVER]:
            return error(f"{path.name} vermagic does not match {KVER}")
    # Verify every input before touching the destination.
    TARGET.mkdir(parents=True, exist_ok=True)
    for module in modules:
        source = BUILD / (module + ".ko")
        target = TARGET / source.name
        target.write_bytes(source.read_bytes())
        target.chmod(0o644)
        print(f"Installed {target}")
    result = run("depmod", "-a", KVER)
    if result.returncode:
        return error("depmod failed: " + result.stderr)
    for module in modules:
        result = run("modinfo", "-k", KVER, "-F", "filename", module)
        if result.returncode or not result.stdout.strip():
            return error(f"Installed {module} not visible through modinfo")
    print("S2500 and NCN26000 installed for running kernel; not loaded.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
