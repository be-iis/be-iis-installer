# Device Tree overlay names — compatibility contract

The basename of every Raspberry Pi Device Tree overlay (`.dts` / `.dtbo`) corresponds to the `dt_blob` overlay name assigned in the HAT+ EEPROM or HAT++ identification memory.

**DO NOT RENAME AN OVERLAY.** The overlay name is a stable interface identifier, not a product revision or directory name. Renaming an overlay breaks recognition and automatic loading for already-programmed boards.

The authoritative assignments are maintained in `be-iis/be-iis-sw/HATp/HATp_eeprom/*.txt`. Verify all variants (Node IDs I, II and III) against their `dt_blob` values before changing, adding or releasing overlays. Update the matching EEPROM definition and migration plan explicitly if a rename ever becomes unavoidable.
