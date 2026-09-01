# BE-IIS-HPP-UART examples

Small, runnable examples for the BE-IIS-HPP-UART HAT.

| Example | What it verifies |
| --- | --- |
| [01_usb_c_isolated_uart.sh](01_usb_c_isolated_uart.sh) | The isolated USB-C UART (port `a`) can transmit data to a PC. |

## UART port assignment

For every HAT++ instance:

- `/dev/beiis-uart-<instance>-a`: galvanically isolated USB-C UART
- `/dev/beiis-uart-<instance>-b`: UART on the HAT header, not isolated

The examples use HAT instance IV by default. Pass another device path as the first argument if needed.
