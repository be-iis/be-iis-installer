#!/usr/bin/env python3
"""Run independent BE-IIS product installers concurrently with progress and JSON reports."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[1]
KERNEL = os.uname().release
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
SPINNER = "/-\\|"

def draw(states, active, selected, frame):
    interactive = sys.stdout.isatty() and not os.getenv("NO_COLOR")
    if interactive:
        sys.stdout.write("\x1b[2J\x1b[H")
    print(f"BE-IIS installation  •  {KERNEL}  •  parallel tasks")
    print()
    for key in selected:
        name, steps = TASKS[key]
        results = states[key]
        failed = any(x["status"] == "failed" for x in results)
        complete = len(results) == len(steps)
        icon = "✓" if complete and not failed else "!" if failed else "◉" if key in active else "○"
        print(f"{icon} {name} ({len(results)}/{len(steps)} attempted)")
        if key in active:
            label, status = active[key]
            spin = SPINNER[frame % len(SPINNER)] if interactive else ">"
            print(f"  {spin} {label}: {status}")
        for index, (label, _) in enumerate(steps):
            if index < len(results):
                if results[index]["status"] == "failed":
                    print(f"  ✗ {label} — failed (see report)")
            elif key not in active or active[key][0] != label:
                print(f"  ☐ {label}")
    print(flush=True)

def run_command(command, progress):
    try:
        proc = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, bufsize=1)
    except OSError as exc:
        return 127, str(exc)
    output = []
    try:
        for line in proc.stdout:
            output.append(line)
            low = line.lower()
            if any(word in low for word in ("downloading", "fetching", "grabbing thread", "source", "patch")):
                progress("Downloading / preparing kernel sources")
            elif any(word in low for word in ("cc [m]", "ld [m]", "building", "  cc ", "  ld ")):
                progress("Compiling kernel modules")
            elif "entering directory" in low:
                progress("Building device-tree overlays")
    except Exception as exc:
        output.append(f"Installer stream error: {exc}\n")
    return proc.wait(), "".join(output)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tasks", nargs="*", choices=list(TASKS), help="Default: all")
    parser.add_argument("--report", default="build/install-report.json")
    parser.add_argument("--jobs", type=int, default=3, help="Maximum parallel products (default 3)")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")
    selected = list(dict.fromkeys(args.tasks or list(TASKS)))
    states = {key: [] for key in selected}
    active = {}
    lock = threading.Lock()
    report_path = ROOT / args.report
    report_path.parent.mkdir(parents=True, exist_ok=True)

    def worker(key):
        for label, command in TASKS[key][1]:
            with lock:
                active[key] = (label, "Starting")
            def progress(status):
                with lock:
                    active[key] = (label, status)
            try:
                code, output = run_command(command, progress)
            except Exception as exc:
                code, output = 127, str(exc)
            with lock:
                states[key].append({"step": label, "command": command,
                                    "status": "ok" if code == 0 else "failed",
                                    "returncode": code, "output": output})
                active.pop(key, None)

    frame = 0
    with ThreadPoolExecutor(max_workers=min(args.jobs, len(selected))) as pool:
        futures = [pool.submit(worker, key) for key in selected]
        while not all(f.done() for f in futures):
            with lock:
                draw(states, active, selected, frame)
            frame += 1
            time.sleep(0.2)
        for future in futures:
            future.result()
    draw(states, active, selected, frame)
    report = {"timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
              "kernel": KERNEL, "tasks": states}
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    failed = sum(x["status"] == "failed" for group in states.values() for x in group)
    print(f"Report: {report_path} | Failed steps: {failed}")
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
