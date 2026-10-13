#!/usr/bin/env python3
"""Check native drivers shipped for the running kernel. Never fetch or backport."""
import os
import subprocess
import sys

def main():
    modules = sys.argv[1:]
    if not modules:
        print("ERROR: no driver modules specified", file=sys.stderr)
        return 2
    kernel = os.uname().release
    missing = []
    for module in modules:
        result = subprocess.run(["modinfo", "-k", kernel, "-F", "filename", module],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, check=False)
        location = result.stdout.strip() if result.returncode == 0 else ""
        native = location == "(builtin)" or (location.startswith(f"/lib/modules/{kernel}/kernel/"))
        if result.returncode == 0 and native:
            print(f"OK: {module} provided by running kernel {kernel} ({location})")
        else:
            print(f"ERROR: {module} is not available for kernel {kernel}.")
            missing.append(module)
    if missing:
        print(f"ERROR: The running kernel {kernel} is too old or was built "
              "without the required driver(s): " + ", ".join(missing) + ".")
        print("Install a kernel version that includes these drivers; "
              "no backport or external kernel sources will be used.")
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
