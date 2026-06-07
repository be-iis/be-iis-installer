#!/usr/bin/env python3
import argparse
import serial
import sys
import time
from datetime import datetime


def main() -> int:
    parser = argparse.ArgumentParser(description="BE-IIS HPP UART test tool")
    parser.add_argument(
        "-d",
        "--device",
        default="/dev/beiis-uart-iv-a",
        help="UART device, e.g. /dev/beiis-uart-iv-a",
    )
    parser.add_argument(
        "-b",
        "--baudrate",
        type=int,
        default=115200,
        help="Baudrate",
    )
    parser.add_argument(
        "-i",
        "--interval",
        type=float,
        default=1.0,
        help="Send interval in seconds",
    )

    args = parser.parse_args()

    print(f"Opening {args.device} at {args.baudrate} baud")
    print("Press Ctrl+C to stop")
    print()

    try:
        ser = serial.Serial(
            port=args.device,
            baudrate=args.baudrate,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.05,
            write_timeout=1.0,
        )
    except serial.SerialException as e:
        print(f"ERROR: Cannot open {args.device}: {e}", file=sys.stderr)
        return 1

    counter = 0
    last_send = 0.0
    rx_buffer = bytearray()

    try:
        while True:
            now = time.monotonic()

            # Send cyclic test message.
            if now - last_send >= args.interval:
                timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                msg = f"BE-IIS UART test {counter} @ {timestamp}\r\n"
                ser.write(msg.encode("ascii"))
                ser.flush()
                print(f"TX: {msg.strip()}")
                counter += 1
                last_send = now

            # Read all available data.
            data = ser.read(256)
            if data:
                rx_buffer.extend(data)

                # Print complete lines.
                while b"\n" in rx_buffer:
                    line, _, rx_buffer = rx_buffer.partition(b"\n")
                    line = line.rstrip(b"\r")
                    try:
                        text = line.decode("utf-8", errors="replace")
                    except Exception:
                        text = repr(line)
                    print(f"RX: {text}")

                # If data arrives without newline, show it after a short while.
                if len(rx_buffer) > 0 and len(rx_buffer) >= 64:
                    print(f"RX raw: {rx_buffer.hex(' ')}")
                    rx_buffer.clear()

    except KeyboardInterrupt:
        print("\nStopping")
    finally:
        ser.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
