# Legacy 10BASE-T1S compatibility

The standard product installer only checks whether the required driver modules are already available. It delegates **missing T1S support** to this directory, without assuming that a particular kernel release (e.g. 7.2) necessarily includes every driver.

## Entrypoint (build-only)

```sh
python3 compatibility/t1s/ensure.py adi
python3 compatibility/t1s/ensure.py onsemi microchip
```

If all required modules exist for the running kernel, no build is performed. If any required T1S component is missing, it builds a **coherent seven-module package** using the existing, tested source/backport helpers in `tools/kernel/`. A missing driver is not considered installed just because compilation succeeds.

## Explicit guarded installation

```sh
python3 compatibility/t1s/install.py check
sudo python3 compatibility/t1s/install.py stage
```

Staging replaces modules **on disk**, backs up existing update-module files, and requires an operator-controlled reboot. Ensure independent recovery access first. The historic `scripts/t1s_stack_install.py` remains available while consumers migrate.

## Current transitional dependencies

The tested kernel-specific C source transforms still reside in `tools/kernel/{s2500,adin1140,lan865x}_mod_build.sh`, and the unified build still resides in `tools/kernel/t1s_unified_build.sh`. They are implementation details of this T1S-only compatibility subsystem. Do not delete them before extracting their source transforms; preserving known-working kernel 6.12 and 6.18 builds is more important than a mechanical move.

No user-facing product install script loads or overwrites `oa_tc6` implicitly. Kernel support is feature/module-detected, not guessed solely from release number.
