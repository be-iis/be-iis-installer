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
# T1S compatibility is delegated once, after ordinary product tasks.
DRIVER_BUILDS = {
    "BE-IIS-HPP-T1L-REVB": ("adin1110", ["adin1110"]),
}
T1S_PRODUCTS = {"BE-IIS-HPP-T1S-ADI-REVA": "adi", "BE-IIS-HPP-T1S-ONSEMI-REVA": "onsemi", "BE-IIS-HPP-T1S-REVB": "microchip"}
# A single independent worker owns each driver build directory.
# Product tasks only build when outputs are missing, unless --rebuild is used.
PRODUCT_MODULES = {
    "BE-IIS-HPP-T1L-REVB": ("adin1110", "tools/kernel/adin1110_mod_build.sh", ("adin1110.ko",)),
    "BE-IIS-HPP-UART-REVB": ("sc16is752", "tools/kernel/sc16is7xx_mod_build.sh", ("sc16is7xx.ko", "sc16is7xx_spi.ko")),
    "BE-IIS-HPP-CAN-FD-SIC-REVB": ("mcp251xfd", "tools/kernel/mcp251xfd_mod_build.sh", ("mcp251xfd.ko",)),
    "BE-IIS-HPP-LAN-REVB": ("ksz8851", "tools/kernel/ksz8851_mod_build.sh", ("ks8851.ko",)),
    "BE-IIS-HPP-SPE-NOISE": ("machxo2-fpga-manager", "tools/kernel/machxo2_fpga_mgr_build.sh",
                               ("fpga-mgr.ko", "fpga-bridge.ko", "fpga-region.ko", "of-fpga-region.ko", "machxo2-spi.ko")),
}
T1S_OUTPUTS = ("oa_tc6.ko", "lan865x.ko", "microchip_t1s.ko",
               "adin1140.ko", "adin1140-phy.ko", "s2500.ko", "ncn26000.ko")

def have_outputs(directory, filenames):
    return all((ROOT / "build" / directory / name).is_file() for name in filenames)

def product_build_command(key, rebuild):
    if key not in PRODUCT_MODULES:
        return None
    directory, script, outputs = PRODUCT_MODULES[key]
    if not rebuild and have_outputs(directory, outputs):
        return None
    return ["bash", script]


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
        overlay = product / "overlays" / "src" / "rpi" / "Makefile"
        if overlay.is_file():
            steps.append(("Device-tree overlays", ["make", "-C", str(overlay.parent.relative_to(ROOT))]))
        tasks[key] = (product.name, steps)
    return tasks

TASKS = discover_tasks()

SPINNER = "/-\\|"

def draw(states, active, selected, frame, plans, started, final=False):
    """Show completed-step percentage; never guess compiler substep progress."""
    interactive = sys.stdout.isatty() and not os.getenv("NO_COLOR")
    total = sum(len(plans[k]) for k in selected) + sum(k in T1S_PRODUCTS for k in selected)
    completed = sum(len(states[k]) for k in selected)
    percent = round(100 * completed / total) if total else 100
    elapsed = int(time.monotonic() - started)
    lines = [
        f"BE-IIS build | Kernel {KERNEL} | {percent}% ({completed}/{total} tasks) | {elapsed}s elapsed",
        "",
    ]
    for key in selected:
        tasks = states[key]
        planned = len(plans[key]) + (1 if key in T1S_PRODUCTS else 0)
        done = len(tasks)
        failed = any(t["status"] == "failed" for t in tasks)
        if not planned:
            symbol, status = "-", "No build target"
        elif done >= planned:
            symbol, status = ("FAIL", "Failed") if failed else ("OK", "Completed")
        elif key in active:
            symbol = "RUN"
            label, phase = active[key]
            status = f"{label}: {phase}"
        else:
            symbol, status = "WAIT", "Queued"
        lines.append(f"[{symbol}] {key}: {done}/{planned} | {status}")
    lines.append("")
    if not final:
        lines.append("Progress counts completed tasks, not internal compiler work.")
    if interactive:
        sys.stdout.write("\x1b[2J\x1b[H")
    else:
        # Periodic snapshots also work in pipes and captured logs.
        lines.append("")
    print("\n".join(lines), flush=True)

def run_command(command, progress):
    try:
        env = os.environ.copy()
        env["BEIIS_BUILD_ONLY"] = "1"
        env["BEIIS_FORCE_BUILD"] = "1"
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
                progress("Running make")
            elif "nothing to be done" in low:
                progress("Up to date")
    except Exception as exc:
        output.append(f"Installer stream error: {exc}\n")
    return proc.wait(), "".join(output)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tasks", nargs="*", help="Product directory names or legacy aliases (default: all)")
    parser.add_argument("--list", action="store_true", help="List discovered products and build targets")
    parser.add_argument("--report", default="build/install-report.json")
    parser.add_argument("--jobs", type=int, default=3, help="Maximum parallel build workers (default 3)")
    parser.add_argument("--rebuild", action="store_true", help="Rebuild all selected kernel modules and overlays even if already built")
    args = parser.parse_args()
    if args.list:
        for key, (name, steps) in TASKS.items():
            extra = ["Kernel module build"] if key in PRODUCT_MODULES else []
            extra += ["Shared T1S build/check"] if key in T1S_PRODUCTS else []
            labels = extra + [x[0] for x in steps if not x[0].endswith("native kernel driver check")]
            print(f"{key}: " + (", ".join(labels) if labels else "no build target (skipped)"))
        return 0
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")
    selected = list(dict.fromkeys(ALIASES.get(k, k) for k in (args.tasks or list(TASKS))))
    for key in selected:
        if key not in TASKS:
            parser.error(f"unknown product: {key}")
    # Prepare execution plans before starting any parallel workers.
    plans = {}
    for key in selected:
        plans[key] = []
        command = product_build_command(key, args.rebuild)
        if command:
            plans[key].append(("Kernel module build", command))
        for label, command in TASKS[key][1]:
            # Native module availability is not a build target. The module
            # builder above is authoritative for T1L; keep overlays.
            if label.endswith("native kernel driver check"):
                continue
            if args.rebuild and label == "Device-tree overlays":
                plans[key].append(("Device-tree clean", ["make", "-C", command[-1], "clean"]))
            plans[key].append((label, command))
    t1s_keys = [k for k in selected if k in T1S_PRODUCTS]
    t1s_products = [T1S_PRODUCTS[k] for k in t1s_keys]
    t1s_missing = bool(t1s_keys and args.rebuild)
    states = {key: [] for key in selected}
    active = {}
    lock = threading.Lock()
    report_path = ROOT / args.report
    report_path.parent.mkdir(parents=True, exist_ok=True)

    def worker(key):
        for label, command in plans[key]:
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

    def shared_t1s_worker():
        if not t1s_keys:
            return
        label = "Shared T1S kernel module rebuild" if t1s_missing else "Shared T1S native check / compatibility build"
        command = (["bash", "tools/kernel/t1s_unified_build.sh"] if t1s_missing
                   else [sys.executable, "compatibility/t1s/ensure.py", *t1s_products])
        with lock:
            for key in t1s_keys:
                active[key] = (label, "Starting")
        def progress(status):
            with lock:
                for key in t1s_keys:
                    active[key] = (label, status)
        code, output = run_command(command, progress)
        with lock:
            for key in t1s_keys:
                states[key].append({"step": label, "command": command,
                                    "status": "ok" if code == 0 else "failed",
                                    "returncode": code, "output": output,
                                    "compatibility": True})
                active.pop(key, None)

    frame = 0
    started = time.monotonic()
    draw(states, active, selected, frame, plans, started)
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(worker, key) for key in selected]
        if t1s_keys:
            futures.append(pool.submit(shared_t1s_worker))
        while not all(f.done() for f in futures):
            with lock:
                if frame % 5 == 0 or sys.stdout.isatty():
                    draw(states, active, selected, frame, plans, started)
            frame += 1
            time.sleep(1.0)
        for future in futures:
            future.result()
    draw(states, active, selected, frame, plans, started, final=True)
    report = {"timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
              "kernel": KERNEL, "tasks": states}
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    failed = sum(x["status"] == "failed" and not x.get("recovered") for group in states.values() for x in group)
    print(f"Report: {report_path} | Failed steps: {failed}")
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
