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
# The first pass checks installed modules; only onsemi and Microchip can\n# retry with a sequential backport build. The Microchip script keeps its B1 logic.
DRIVER_BUILDS = {
    "BE-IIS-HPP-T1S-ADI-REVA": ("adin1140", ["adin1140", "adin1140-phy", "oa_tc6"]),
    "BE-IIS-HPP-T1S-ONSEMI-REVA": ("s2500", ["s2500", "ncn26000", "oa_tc6"]),
    "BE-IIS-HPP-T1L-REVB": ("adin1110", ["adin1110"]),
}
MICROCHIP_SCRIPT = "tools/kernel/lan865x_mod_build.sh"
RETRY_BUILDS = {
    "BE-IIS-HPP-T1S-ONSEMI-REVA": ("s2500 backport build", ["bash", "tools/kernel/s2500_mod_build.sh"]),
    "BE-IIS-HPP-T1S-REVB": ("Microchip B1 compatibility build", ["bash", MICROCHIP_SCRIPT]),
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
            name, modules = DRIVER_BUILDS[key]
            steps.append((f"{name} native kernel driver check", [
                sys.executable, "scripts/check_kernel_modules.py", *modules
            ]))
        elif key == "BE-IIS-HPP-T1S-REVB":
            steps.append(("Microchip installed kernel driver check", [
                sys.executable, "scripts/check_kernel_modules.py", "lan865x", "microchip_t1s", "oa_tc6"
            ]))
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
        failed = any(x["status"] == "failed" and not x.get("recovered") for x in results)
        complete = len([x for x in results if not x.get("retry")]) >= len(steps)
        icon = "—" if not steps else "✓" if complete and not failed else "!" if failed else "◉" if key in active else "○"
        print(f"{icon} {name} ({len([x for x in results if not x.get('retry')])}/{len(steps)} attempted)" if steps else f"— {name} (no build target; skipped)")
        if key in active:
            label, status = active[key]
            spin = SPINNER[frame % len(SPINNER)] if interactive else ">"
            print(f"  {spin} {label}: {status}")
        for retry in (x for x in results if x.get("retry")):
            print(f"  {'✓' if retry['status'] == 'ok' else '✗'} {retry['step']} — " + ("built, not installed" if retry["status"] == "ok" else "failed"))
        for index, (label, _) in enumerate(steps):
            if index < len(results):
                if results[index]["status"] == "failed":
                    symbol = "↻" if results[index].get("recovered") else "✗"
                    print(f"  {symbol} {label} — " + ("backport compiled, not installed" if results[index].get("backport_built") else "failed (see report)"))
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
    # Phase 2: only retry failed native-driver checks for onsemi/Microchip.
    # No parallel backport builds. Do not retry unrelated overlay failures.
    for key in selected:
        if key not in RETRY_BUILDS or not states[key]:
            continue
        original = states[key][0]
        if original["status"] != "failed":
            continue
        label, command = RETRY_BUILDS[key]
        if not (ROOT / command[1]).is_file():
            states[key].append({"step": label, "command": command, "status": "failed",
                                "returncode": 127, "output": "Backport build script missing", "retry": True})
            continue
        with lock:
            active[key] = (label, "Trying kernel compatibility backport")
        def retry_progress(status):
            with lock:
                active[key] = (label, status)
        try:
            code, output = run_command(command, retry_progress)
        except Exception as exc:
            code, output = 127, str(exc)
        states[key].append({"step": label, "command": command,
                            "status": "ok" if code == 0 else "failed",
                            "returncode": code, "output": output, "retry": True})
        if code == 0:
            original["backport_built"] = True
            # Build-only is not installation: the native module check remains failed.
        with lock:
            active.pop(key, None)
            draw(states, active, selected, frame)
    draw(states, active, selected, frame)
    report = {"timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
              "kernel": KERNEL, "tasks": states}
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    failed = sum(x["status"] == "failed" and not x.get("recovered") for group in states.values() for x in group)
    print(f"Report: {report_path} | Failed steps: {failed}")
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
