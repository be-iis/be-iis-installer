#!/usr/bin/env python3
"""Independent BE-IIS installation tasks with a shrinking checklist and JSON report."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TASKS = {
    "adi": ("ADI 10BASE-T1S", [
        ("Kernel modules", ["bash", "tools/kernel/adin1140_mod_build.sh"]),
        ("Device-tree overlays", ["make", "-C", "products/BE-IIS-HPP-T1S-ADI-REVA/overlays/src/rpi"]),
    ]),
    "onsemi": ("onsemi 10BASE-T1S", [
        ("Kernel modules", ["bash", "tools/kernel/s2500_mod_build.sh"]),
        ("Device-tree overlays", ["make", "-C", "products/BE-IIS-HPP-T1S-ONSEMI-REVA/overlays/src/rpi"]),
    ]),
    "microchip": ("Microchip 10BASE-T1S", [
        ("Kernel modules", ["bash", "tools/kernel/lan865x_mod_build.sh"]),
    ]),
}

def draw(states, selected):
    if sys.stdout.isatty() and not os.getenv("NO_COLOR"):
        sys.stdout.write("\x1b[2J\x1b[H")
    print("BE-IIS installation  •  " + subprocess.getoutput("uname -r"))
    print()
    for key in selected:
        name, steps = TASKS[key]
        results = states[key]
        done = len(results) == len(steps) and all(r["status"] == "ok" for r in results)
        failed = any(r["status"] == "failed" for r in results)
        mark = "✓" if done else "!" if failed else "○"
        print(f"{mark} {name} ({len(results)}/{len(steps)} attempted)")
        # Completed steps disappear; failures remain visible with status.
        for idx, (label, _) in enumerate(steps):
            if idx < len(results):
                if results[idx]["status"] == "failed":
                    print(f"  ✗ {label} — failed (see report)")
            else:
                print(f"  ☐ {label}")
    print(flush=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tasks", nargs="*", choices=list(TASKS), help="Default: all")
    parser.add_argument("--report", default="build/install-report.json")
    args = parser.parse_args()
    selected = list(dict.fromkeys(args.tasks or list(TASKS)))
    states = {key: [] for key in selected}
    report_path = ROOT / args.report
    report_path.parent.mkdir(parents=True, exist_ok=True)
    draw(states, selected)
    for key in selected:
        for label, command in TASKS[key][1]:
            try:
                proc = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT, check=False)
                code, output = proc.returncode, proc.stdout
            except OSError as exc:
                code, output = 127, str(exc)
            states[key].append({"step": label, "command": command,
                                "status": "ok" if code == 0 else "failed",
                                "returncode": code, "output": output})
            draw(states, selected)
    report = {"timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
              "kernel": subprocess.getoutput("uname -r"), "tasks": states}
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    failed = sum(r["status"] == "failed" for v in states.values() for r in v)
    print(f"Report: {report_path} | Failed steps: {failed}")
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
