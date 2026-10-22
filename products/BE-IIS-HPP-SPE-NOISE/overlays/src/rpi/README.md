# Raspberry Pi overlay source

Reserved for a later overlay if a kernel-visible function is added.

## Critical: stable EEPROM overlay name

The overlay basename (`.dts` / `.dtbo`) must match the `dt_blob` name assigned in the HAT+ EEPROM or HAT++ identification memory. **DO NOT RENAME OVERLAYS** or derive their names from the product revision. Existing programmed boards depend on this identifier. The authoritative assignments are in `be-iis/be-iis-sw/HATp/HATp_eeprom/*.txt` (Node IDs I, II and III). Verify the EEPROM value before any changes.
