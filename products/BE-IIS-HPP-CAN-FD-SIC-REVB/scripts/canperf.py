#!/usr/bin/env python3

import argparse
import socket
import struct
import time
import select

CAN_IF_DEFAULT = "beiis-can0"

SOL_CAN_RAW = 101
CAN_RAW_FD_FRAMES = 5

CAN_MTU = 16
CANFD_MTU = 72

CANFD_BRS = 0x01

DEFAULT_CAN_ID = 0x123
DEFAULT_PAYLOAD_SIZE = 64

MAX_PAYLOAD = 64
MIN_PAYLOAD = 1


def open_socket(iface):
    s = socket.socket(socket.PF_CAN, socket.SOCK_RAW, socket.CAN_RAW)

    s.setsockopt(
        SOL_CAN_RAW,
        CAN_RAW_FD_FRAMES,
        1,
    )

    s.bind((iface,))

    return s


def build_classic_frame(can_id, counter):
    payload = struct.pack("<I", counter)
    payload += bytes(8 - 4)

    return struct.pack(
        "=IB3x8s",
        can_id,
        8,
        payload,
    )


def build_fd_frame(can_id, counter, payload_size):
    payload = struct.pack("<I", counter)

    pattern_len = payload_size - 4

    for i in range(pattern_len):
        payload += bytes([(counter + i) & 0xFF])

    payload += bytes(MAX_PAYLOAD - payload_size)

    return struct.pack(
        "=IBB2x64s",
        can_id,
        payload_size,
        CANFD_BRS,
        payload,
    )


def parse_frame(frame):
    if len(frame) == CANFD_MTU:
        can_id, length, flags, data = struct.unpack(
            "=IBB2x64s",
            frame,
        )

        payload = data[:length]

        return can_id, length, payload, True

    can_id, length, data = struct.unpack(
        "=IB3x8s",
        frame[:CAN_MTU],
    )

    payload = data[:length]

    return can_id, length, payload, False


def verify_payload(counter, payload):
    expected = struct.pack("<I", counter)

    pattern_len = len(payload) - 4

    for i in range(pattern_len):
        expected += bytes([(counter + i) & 0xFF])

    return payload == expected


def tx_mode(iface, can_id, payload_size, duration, rate, classic):
    s = open_socket(iface)

    print(f"[TX] Interface      : {iface}")
    print(f"[TX] CAN ID         : 0x{can_id:X}")
    print(f"[TX] Payload size   : {payload_size}")
    print(f"[TX] Duration       : {duration:.1f} s")

    if classic:
        print(f"[TX] Mode           : Classic CAN")
    else:
        print(f"[TX] Mode           : CAN-FD")

    if rate <= 0:
        print(f"[TX] Rate           : MAX")
    else:
        print(f"[TX] Rate           : {rate:.1f} fps")

    if classic and payload_size > 8:
        raise ValueError("Classic CAN max payload is 8")

    counter = 0

    start = time.time()
    last_stat = start
    last_counter = 0

    next_send = start

    while True:
        now = time.time()

        if now - start >= duration:
            break

        if classic:
            frame = build_classic_frame(
                can_id,
                counter,
            )

            effective_payload_size = 8

        else:
            frame = build_fd_frame(
                can_id,
                counter,
                payload_size,
            )

            effective_payload_size = payload_size

        s.send(frame)

        counter += 1

        if rate > 0:
            next_send += 1.0 / rate

            sleep_time = next_send - time.time()

            if sleep_time > 0:
                time.sleep(sleep_time)

        now = time.time()

        if now - last_stat >= 1.0:
            delta = counter - last_counter

            payload_mbit = (
                delta
                * effective_payload_size
                * 8
                / 1_000_000
            )

            print(
                f"[TX] "
                f"{delta:8d} fps  "
                f"{payload_mbit:.3f} MBit/s payload  "
                f"total={counter}"
            )

            last_counter = counter
            last_stat = now

    elapsed = time.time() - start

    fps = counter / elapsed

    payload_mbit = (
        fps
        * effective_payload_size
        * 8
        / 1_000_000
    )

    print()
    print("=== TX RESULT ===")
    print(f"Frames sent     : {counter}")
    print(f"Duration        : {elapsed:.2f} s")
    print(f"Frames/s        : {fps:.1f}")
    print(f"Payload MBit/s  : {payload_mbit:.3f}")


def rx_mode(iface, can_id):
    s = open_socket(iface)

    print(f"[RX] Interface : {iface}")
    print(f"[RX] CAN ID    : 0x{can_id:X}")

    expected_counter = None

    total = 0
    lost = 0
    corrupt = 0
    reordered = 0

    total_bytes = 0

    last_total = 0
    last_bytes = 0

    last_time = time.time()

    while True:
        ready, _, _ = select.select([s], [], [], 1.0)

        if not ready:
            now = time.time()

            if now - last_time >= 1.0:
                delta_frames = total - last_total
                delta_bytes = total_bytes - last_bytes

                payload_mbit = (
                    delta_bytes
                    * 8
                    / 1_000_000
                )

                print(
                    f"[RX] "
                    f"{delta_frames:8d} fps  "
                    f"{payload_mbit:.3f} MBit/s payload  "
                    f"lost={lost}  "
                    f"corrupt={corrupt}  "
                    f"reordered={reordered}"
                )

                last_total = total
                last_bytes = total_bytes
                last_time = now

            continue

        frame = s.recv(CANFD_MTU)

        can_id_rx, length, payload, is_fd = parse_frame(frame)

        if can_id_rx != can_id:
            continue

        if length < 4:
            corrupt += 1
            continue

        counter = struct.unpack("<I", payload[:4])[0]

        if is_fd and not verify_payload(counter, payload):
            corrupt += 1

        if expected_counter is not None:
            if counter > expected_counter:
                lost += counter - expected_counter

            elif counter < expected_counter:
                reordered += 1

        expected_counter = counter + 1

        total += 1
        total_bytes += length

        now = time.time()

        if now - last_time >= 1.0:
            delta_frames = total - last_total
            delta_bytes = total_bytes - last_bytes

            payload_mbit = (
                delta_bytes
                * 8
                / 1_000_000
            )

            print(
                f"[RX] "
                f"{delta_frames:8d} fps  "
                f"{payload_mbit:.3f} MBit/s payload  "
                f"lost={lost}  "
                f"corrupt={corrupt}  "
                f"reordered={reordered}"
            )

            last_total = total
            last_bytes = total_bytes
            last_time = now


def main():
    parser = argparse.ArgumentParser(
        description="CAN/CAN-FD performance tool"
    )

    sub = parser.add_subparsers(
        dest="mode",
        required=True,
    )

    tx = sub.add_parser("tx")

    tx.add_argument(
        "-i",
        "--interface",
        default=CAN_IF_DEFAULT,
    )

    tx.add_argument(
        "--id",
        type=lambda x: int(x, 0),
        default=DEFAULT_CAN_ID,
    )

    tx.add_argument(
        "--size",
        type=int,
        default=DEFAULT_PAYLOAD_SIZE,
    )

    tx.add_argument(
        "--time",
        type=float,
        default=10.0,
    )

    tx.add_argument(
        "--rate",
        type=float,
        default=0,
        help="0 = maximum speed",
    )

    tx.add_argument(
        "--classic",
        action="store_true",
        help="Use Classic CAN frames",
    )

    rx = sub.add_parser("rx")

    rx.add_argument(
        "-i",
        "--interface",
        default=CAN_IF_DEFAULT,
    )

    rx.add_argument(
        "--id",
        type=lambda x: int(x, 0),
        default=DEFAULT_CAN_ID,
    )

    args = parser.parse_args()

    if args.mode == "tx":
        if args.size < MIN_PAYLOAD:
            raise ValueError("Payload too small")

        if args.size > MAX_PAYLOAD:
            raise ValueError("Payload too large")

        tx_mode(
            args.interface,
            args.id,
            args.size,
            args.time,
            args.rate,
            args.classic,
        )

    elif args.mode == "rx":
        rx_mode(
            args.interface,
            args.id,
        )


if __name__ == "__main__":
    main()
