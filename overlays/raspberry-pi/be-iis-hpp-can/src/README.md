# Purpose
Device Tree Source (DTS) files for configuring BE-IIS HPP CAN hardware overlays on Raspberry Pi platforms.

# Files
- `BE-IIS-HPP-CAN-SIC-I.dts`   
- `BE-IIS-HPP-CAN-SIC-II.dts`  
- `BE-IIS-HPP-CAN-SIC-III.dts` 

Each file provides a device tree overlay for a specific hardware configuration variant (SIC I, II, III) of the BE-IIS HPP CAN add-on.

# Usage
1. Compile the desired `.dts` file to a `.dtbo` binary overlay using the Device Tree Compiler:
   ```sh
   dtc -I dts -O dtb -o <output>.dtbo <input>.dts
   ```
2. Copy the resulting `.dtbo` file to `/boot/overlays/` on the Raspberry Pi OS filesystem.
3. Add the appropriate `dtoverlay` directive to `/boot/config.txt`, matching the overlay.

# Notes
- File naming follows the convention: `BE-IIS-HPP-CAN-SIC-<variant>.dts`.
- Ensure the overlay corresponds with the BE-IIS HPP CAN hardware variant in use.
- Root access is required to modify `/boot/` contents.
- See parent and sibling `README.md` files for further integration and test details.
