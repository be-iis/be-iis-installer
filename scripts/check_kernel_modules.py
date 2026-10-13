#!/usr/bin/env python3
"""Check installed drivers for the running kernel, without fetching or building."""
import os
from pathlib import Path
import subprocess
import sys

def info(kernel, module, field):
    return subprocess.run(["modinfo", "-k", kernel, "-F", field, module],
                          capture_output=True, text=True, check=False)

def main():
    modules = sys.argv[1:]
    if not modules:
        print("ERROR: no driver modules specified", file=sys.stderr)
        return 2
    kernel = os.uname().release
    missing = []
    for module in modules:
        result = info(kernel, module, "filename")
        location = result.stdout.strip() if result.returncode == 0 else ""
        base = Path("/lib/modules") / kernel
        path = Path(location)
        installed = location == "(builtin)" or (
            result.returncode == 0 and path.is_absolute()
            and path.is_file() and path.resolve().is_relative_to(base.resolve())
        )
        vermagic = info(kernel, module, "vermagic")
        release = vermagic.stdout.strip().split(maxsplit=1)[0] if vermagic.returncode == 0 and vermagic.stdout.strip() else ""
        compatible = location == "(builtin)" or release == kernel
        if installed and compatible:
            print(f"OK: {module} installed for running kernel {kernel} ({location})")
        else:
            reason = ("not installed" if not installed else
                      f"module vermagic release {release or 'unknown'} differs from {kernel}")
            print(f"ERROR: {module}: {reason}")
            missing.append(module)
    if missing:
        print(f"ERROR: Required modules unavailable for running kernel {kernel}: "
              + ", ".join(missing))
        print("Use a kernel with the required drivers or install compatible modules separately. "
              "This installer does not download or backport them.")
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
