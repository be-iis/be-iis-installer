# BE-IIS-HPP-MODBUS-REVB Production Test

## Purpose

This test verifies the basic functionality of the RS485 communication channels of the BE-IIS-HPP-MODBUS-REVB board.

The test checks:

- SC16IS752 UART functionality
- RS485 transceiver functionality
- Automatic direction control
- I²C communication to the SC16IS752
- Communication stability over multiple baud rates

---

## Test Setup

### Required Wiring

The two RS485 channels must be connected together:

| Channel A | Channel B |
|---|---|
| A | A |
| B | B |
| GND | GND |

---

## Termination

Both RS485 terminations must be enabled.

Required:

- Channel A termination: ENABLED
- Channel B termination: ENABLED

---

## Test Procedure

1. Boot the Raspberry Pi system.
2. Connect the RS485 channels as described above.
3. Enable both terminations.
4. Execute the UART test script:

```bash
sudo ./test_uart.py
```

The script performs communication tests:

- Channel A → Channel B
- Channel B → Channel A

The following baud rates are tested:

- 9600
- 19200
- 38400
- 57600
- 115200
- 230400
- 460800
- 500000
- 921600
- 1000000

The script transmits test frames and verifies correct reception.

---

## Pass Criteria

The test is considered PASSED if:

- All baud rates report `OK`
- Both directions pass successfully
- No communication errors occur
- TX and RX byte counts match

Example:

```text
115200   |   64 B |   64 B | OK
```

---

## Files

- [test_uart.py](./test_uart.py)

---

## Notes

This is a functional production test and not a long-term stress test.

The test validates:

- Basic RS485 operation
- UART communication
- Automatic driver enable control
- Signal integrity for short production verification

---
