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
# Do not execute arbitrary product install.sh scripts: many are placeholders,
# and some may alter /boot or /lib/modules. Build targets are safe to discover.
DRIVER_BUILDS = {
    "BE-IIS-HPP-T1S-ADI-REVA": ("adin1140", "tools/kernel/adin1140_mod_build.sh"),
    "BE-IIS-HPP-T1S-ONSEMI-REVA": ("s2500", "tools/kernel/s2500_mod_build.sh"),
    "BE-IIS-HPP-T1S-REVB": ("lan865x", "tools/kernel/lan865x_mod_build.sh"),
    "BE-IIS-HPP-T1L-REVB": ("adin1110", "tools/kernel/adin1110_mod_build.sh"),
}
ALIASES = {
    "adi": "BE-IIS-HPP-T1S-ADI-REVA",
    "onsemi": "BE-IIS-HPP-T1S-ONSEMI-REVA",
    "microchip": "BE-IIS-HPP-T1S-REVB",
    "t1l": "BE-IIS-HPP-T1L-REVB",
    "uart": "BE-IIS-HPP-UART-REVB",
}

def discover_tasks():
    """Find every product; run only explicit build scripts and overlay Makefiles."""
    tasks = {}
    for product in sorted((ROOT / "products").iterdir()):
        if not product.is_dir() or not product.name.startswith("BE-IIS-"):
            continue
        key = product.name
        steps = []
        if key in DRIVER_BUILDS:
            name, script = DRIVER_BUILDS[key]
            if (ROOT / script).is_file():
                steps.append((f"{name} kernel module (build only)", ["bash", script]))
        overlay = product / "overlays" / "src" / "rpi" / "Makefile"
        if overlay.is_file():
            steps.append(("Device-tree overlays", ["make", "-C", str(overlay.parent.relative_to(ROOT))]))
        tasks[key] = (product.name, steps)
    return tasks

TASKS = discover_tasks()

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
        icon = "—" if not steps else "✓" if complete and not failed else "!" if failed else "◉" if key in active else "○"
        print(f"{icon} {name} ({len(results)}/{len(steps)} attempted)" if steps else f"— {name} (no build target; skipped)")
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
        env = os.environ.copy()
        env["BEIIS_BUILD_ONLY"] = "1"
        proc = subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
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
    parser.add_argument("tasks", nargs="*", help="Product directory names or legacy aliases (default: all)")
    parser.add_argument("--list", action="store_true", help="List discovered products and build targets")
    parser.add_argument("--report", default="build/install-report.json")
    parser.add_argument("--jobs", type=int, default=3, help="Maximum parallel products (default 3)")
    args = parser.parse_args()
    if args.list:
        for key, (name, steps) in TASKS.items():
            print(f"{key}: " + (", ".join(x[0] for x in steps) if steps else "no build target (skipped)"))
        return 0
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")
    selected = list(dict.fromkeys(ALIASES.get(k, k) for k in (args.tasks or list(TASKS))))
    for key in selected:
        if key not in TASKS:
            parser.error(f"unknown product: {key}")
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
