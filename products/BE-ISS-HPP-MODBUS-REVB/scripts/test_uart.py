#!/usr/bin/env python3

import os
import time
import termios
import select
import hashlib

BAUDRATES = [
    9600,
    19200,
    38400,
    57600,
    115200,
    230400,
    460800,
    500000,
    921600,
    1000000
]

PAYLOAD_SIZE = 64

BAUD_MAP = {
    9600: termios.B9600,
    19200: termios.B19200,
    38400: termios.B38400,
    57600: termios.B57600,
    115200: termios.B115200,
    230400: termios.B230400,
    460800: termios.B460800,
    500000: termios.B500000,
    921600: termios.B921600,
    1000000: termios.B1000000,
}


def open_uart(path, baud):
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)

    attrs = termios.tcgetattr(fd)

    attrs[0] = 0
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0
    attrs[4] = BAUD_MAP[baud]
    attrs[5] = BAUD_MAP[baud]

    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)

    return fd


def make_payload(direction, baud):
    text = f"BE-IIS-UART-{direction}-{baud}-"
    data = (text * 20).encode()
    return data[:PAYLOAD_SIZE]


def write_all(fd, data):
    pos = 0

    while pos < len(data):
        _, w, _ = select.select([], [fd], [], 1.0)

        if fd in w:
            try:
                n = os.write(fd, data[pos:])
                pos += n
            except BlockingIOError:
                pass

    termios.tcdrain(fd)


def read_exact(fd, size, timeout_s):
    end = time.time() + timeout_s
    data = b""

    while len(data) < size and time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.02)

        if fd in r:
            try:
                chunk = os.read(fd, size - len(data))
                if chunk:
                    data += chunk
            except BlockingIOError:
                pass

    return data


def calc_timeout(size, baud):
    t = (size * 10 / baud) + 0.5
    return max(t, 1.0)


def test_direction(tx_port, rx_port, direction):
    print()
    print(f"=== {direction} ===")
    print()

    print("Baud     | TX     | RX     | Result")
    print("---------+--------+--------+--------")

    results = []

    for baud in BAUDRATES:

        tx = open_uart(tx_port, baud)
        rx = open_uart(rx_port, baud)

        payload = make_payload(direction, baud)

        tx_hash = hashlib.sha256(payload).hexdigest()

        timeout_s = calc_timeout(len(payload), baud)

        time.sleep(0.05)

        write_all(tx, payload)

        received = read_exact(rx, len(payload), timeout_s)

        rx_hash = hashlib.sha256(received).hexdigest()

        os.close(tx)
        os.close(rx)

        ok = tx_hash == rx_hash

        results.append(ok)

        print(
            f"{baud:<8} | "
            f"{len(payload):>4} B | "
            f"{len(received):>4} B | "
            f"{'OK' if ok else 'FAIL'}"
        )

    return all(results)


ok1 = test_direction(
    "/dev/ttySC0",
    "/dev/ttySC1",
    "SC0->SC1"
)

ok2 = test_direction(
    "/dev/ttySC1",
    "/dev/ttySC0",
    "SC1->SC0"
)

print()
print("Summary")
print("=======")

if ok1 and ok2:
    print("All tests passed.")
else:
    print("Some tests failed.")
