# Purpose
Device overlay support for the BE-IIS-HPP-T1S module on Raspberry Pi platforms.

# Files
- `docs/` : Documentation relevant to this overlay.
- `src/BE-IIS-HPP-T1S-I.dts` : Device tree source for variant I.
- `src/BE-IIS-HPP-T1S-II.dts` : Device tree source for variant II.
- `src/BE-IIS-HPP-T1S-III.dts` : Device tree source for variant III.
- `src/README.md` : Additional details on device trees.
- `tests/` : Test documentation and validation instructions.

# Usage
1. Select and compile the required `.dts` file for your hardware variant:
   - `BE-IIS-HPP-T1S-I.dts`, `BE-IIS-HPP-T1S-II.dts`, or `BE-IIS-HPP-T1S-III.dts`.
2. Apply the compiled device tree overlay (`.dtbo`) to the Raspberry Pi per project documentation.
3. For system integration steps, refer to the root-level and `docs/` guides.

# Notes
- Ensure compatibility between the selected device tree and the BE-IIS-HPP-T1S variant.
- Testing information and examples are located within the `tests/` and `docs/` subdirectories.
- No runtime scripts or service files are present in this directory.
