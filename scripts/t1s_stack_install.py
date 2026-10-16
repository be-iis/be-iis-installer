#!/usr/bin/env python3
"""Stage, verify and optionally restore the unified T1S modules.

Does not load/unload modules or reboot the machine.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

MODULES = ("oa_tc6", "lan865x", "microchip_t1s", "adin1140",
           "adin1140-phy", "s2500", "ncn26000")
ROOT = Path(__file__).resolve().parents[1]
KVER = os.uname().release
TARGET = Path("/lib/modules") / KVER / "updates"
BACKUPS = Path("/var/lib/be-iis/t1s-backups")
MANIFEST = "manifest.json"


def run(*args):
    proc = subprocess.run(args, text=True, capture_output=True, check=False)
    if proc.returncode:
        raise RuntimeError(f"{' '.join(map(str, args))}: {proc.stderr.strip()}")
    return proc.stdout.strip()


def require_root():
    if os.geteuid():
        raise RuntimeError("Use sudo for stage or rollback")


def verify_build(build):
    run(sys.executable, str(ROOT / "scripts/check_t1s_stack.py"), str(build))
    for module in MODULES:
        path = build / (module + ".ko")
        if not path.is_file():
            raise RuntimeError(f"Missing {path}")
        ver = run("modinfo", "-F", "vermagic", str(path)).split()
        if not ver or ver[0] != KVER:
            raise RuntimeError(f"Kernel vermagic mismatch: {path}")


def verify_installed(build):
    for module in MODULES:
        source = build / (module + ".ko")
        dest = TARGET / source.name
        if not dest.is_file() or source.read_bytes() != dest.read_bytes():
            raise RuntimeError(f"Installed file verification failed: {dest}")


def backup_current(path):
    import uuid
    BACKUPS.mkdir(parents=True, exist_ok=True)
    label = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    dest = BACKUPS / (label + "-" + uuid.uuid4().hex[:8])
    dest.mkdir(mode=0o700)
    manifest = {"kernel": KVER, "files": {}, "status": "backup-created"}
    # Preserve the selected target directory AND existing modules in other
    # module subdirectories that modinfo resolves, without changing them.
    for module in MODULES:
        name = module + ".ko"
        target = TARGET / name
        file_entry = {"target": str(target), "existed": target.exists()}
        if target.exists():
            backup = dest / name
            shutil.copy2(target, backup)
            file_entry["backup"] = name
        manifest["files"][module] = file_entry
    (dest / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n")
    return dest, manifest


def restore_files(folder, manifest):
    if manifest["kernel"] != KVER:
        raise RuntimeError("Backup kernel does not match running kernel")
    for module in MODULES:
        entry = manifest["files"][module]
        dest = Path(entry["target"])
        if dest != TARGET / (module + ".ko"):
            raise RuntimeError("Unsafe backup destination")
        if entry["existed"]:
            src = folder / entry["backup"]
            if not src.is_file():
                raise RuntimeError(f"Backup file missing: {src}")
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
        else:
            dest.unlink(missing_ok=True)
    run("depmod", "-a", KVER)


def stage(build):
    require_root()
    verify_build(build)
    backup, manifest = backup_current(build)
    try:
        TARGET.mkdir(parents=True, exist_ok=True)
        for module in MODULES:
            src = build / (module + ".ko")
            dest = TARGET / src.name
            temp = TARGET / (src.name + ".beiis-new")
            shutil.copy2(src, temp)
            temp.chmod(0o644)
            os.replace(temp, dest)
        run("depmod", "-a", KVER)
        verify_installed(build)
        # Verify resolution points to our package, not another competing path.
        for module in MODULES:
            resolved = run("modinfo", "-k", KVER, "-F", "filename", module)
            if Path(resolved).resolve() != (TARGET / (module + ".ko")).resolve():
                raise RuntimeError(f"{module} resolves to {resolved}, not staged module")
    except Exception:
        restore_files(backup, manifest)
        raise
    manifest["status"] = "staged"
    (backup / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"STAGED: {len(MODULES)} modules; backup: {backup}")
    print("NOTICE: Loaded kernel modules are unchanged. Reboot manually after arranging recovery access.")
    print(f"Rollback (same running kernel): sudo python3 scripts/t1s_stack_install.py rollback {backup}")


def rollback(folder):
    require_root()
    folder = folder.resolve()
    if BACKUPS.resolve() not in folder.parents:
        raise RuntimeError("Rollback path must be inside the managed backup directory")
    manifest = json.loads((folder / MANIFEST).read_text())
    restore_files(folder, manifest)
    print("RESTORED: previous module files. Reboot required for previously loaded modules.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("check", "stage", "rollback"))
    parser.add_argument("backup", nargs="?", type=Path)
    parser.add_argument("--build", type=Path, default=ROOT / "build/t1s-unified")
    args = parser.parse_args()
    try:
        if args.action == "rollback":
            if args.backup is None:
                parser.error("rollback requires a backup directory")
            rollback(args.backup)
        else:
            if args.backup is not None:
                parser.error("backup path only applies to rollback")
            build = args.build.resolve()
            if args.action == "check":
                verify_build(build)
                print("PASS: build can be staged; no files changed")
            else:
                stage(build)
    except (RuntimeError, OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
