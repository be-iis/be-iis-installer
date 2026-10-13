# Independent installer tasks (preview)

Run from the repository root:

```sh
python3 scripts/install_tasks.py
python3 scripts/install_tasks.py adi onsemi
python3 scripts/install_tasks.py --report build/my-install-report.json
```

The terminal view shows one main item per product and only remaining substeps. A
successful step disappears from the sub-list. Failed steps remain marked as
failed and are logged. Each step and each product is attempted independently;
the process exits nonzero **only after** all requested tasks were attempted.
The report includes commands, exit codes, full output, timestamp, and kernel
release. This entry point builds modules and overlays, but it does **not** yet
install modules into /lib/modules, modify config.txt, or reboot.

Source selection policy (in progress):
* Prefer exact running kernel sources from /lib/modules/$(uname -r)/source.
* Use backports only when required functionality is absent.
* Microchip B1 needs a >=6.13 feature baseline; older kernels need a compatible
  backport. Merely downloading a >=6.13 source does not make it compatible with
  a 6.12 kernel. This must be verified by compiling against the target headers.
* Never treat kernel-branch HEAD as an exact match to the running kernel.

Limitations: existing legacy build scripts still use a branch-head/upstream
fallback, and the kernel source resolution has not yet been validated on the
target Raspberry Pi. Docker packaging is not wired into this preview. Kernel
module builds inside Docker require explicit host kernel-header/source mounts
and architecture-matched build dependencies.
