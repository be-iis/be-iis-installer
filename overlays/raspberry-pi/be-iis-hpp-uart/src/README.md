# Purpose
Device Tree Source (DTS) files for configuring BE-IIS-HPP-UART hardware overlays on Raspberry Pi platforms.

# Files
- **BE-IIS-HPP-UART-I.dts**: Device tree source for UART hardware variant I.
- **BE-IIS-HPP-UART-II.dts**: Device tree source for UART hardware variant II.
- **BE-IIS-HPP-UART-III.dts**: Device tree source for UART hardware variant III.

# Usage
Convert the desired `.dts` file to a `.dtbo` (device tree blob overlay) with:

```sh
dtc -@ -I dts -O dtb -o <output>.dtbo <input>.dts
```
Copy the resulting `.dtbo` file to `/boot/overlays/` on the Raspberry Pi system.
Enable the overlay by adding a relevant line to `/boot/config.txt`:

```
dtoverlay=<output>  # Without .dtbo extension
```

# Notes
- Select the device tree file that matches the hardware variant in use.
- Editing DTS files requires appropriate knowledge of the Raspberry Pi hardware and overlay structure.
- For documentation or board-specific details, refer to the parent `docs` directory or board hardware manuals.
