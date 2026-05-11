#!/usr/bin/env python3

import argparse
import socket
import struct
import time

CAN_IF_DEFAULT = "beiis-can0"

SOL_CAN_RAW = 101
CAN_RAW_FD_FRAMES = 5

CAN_MTU = 16
CANFD_MTU = 72
CANFD_BRS = 0x01

TX_ID = 0x123
RX_ID = 0x124

CLASSIC_PAYLOAD_SIZE = 8
FD_PAYLOAD_SIZE = 64


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
    payload += bytes(CLASSIC_PAYLOAD_SIZE - 4)

    return struct.pack(
        "=IB3x8s",
        can_id,
        CLASSIC_PAYLOAD_SIZE,
        payload,
    )


def build_fd_frame(can_id, counter):
    payload = struct.pack("<I", counter)
    payload += bytes(FD_PAYLOAD_SIZE - 4)

    return struct.pack(
        "=IBB2x64s",
        can_id,
        FD_PAYLOAD_SIZE,
        CANFD_BRS,
        payload,
    )


def parse_frame(frame):
    if len(frame) == CANFD_MTU:
        can_id, length, flags, data = struct.unpack(
            "=IBB2x64s",
            frame,
        )

        counter = struct.unpack("<I", data[:4])[0]

        return can_id, counter, True

    can_id, length, data = struct.unpack(
        "=IB3x8s",
        frame[:CAN_MTU],
    )

    counter = struct.unpack("<I", data[:4])[0]

    return can_id, counter, False


def server(iface):
    s = open_socket(iface)

    print(f"[SERVER] Listening on {iface}")

    total = 0
    last_total = 0
    last_time = time.time()

    while True:
        frame = s.recv(CANFD_MTU)

        can_id, counter, is_fd = parse_frame(frame)

        if can_id != TX_ID:
            continue

        if is_fd:
            reply = build_fd_frame(RX_ID, counter)
            payload_size = FD_PAYLOAD_SIZE
        else:
            reply = build_classic_frame(RX_ID, counter)
            payload_size = CLASSIC_PAYLOAD_SIZE

        s.send(reply)

        total += 1

        now = time.time()

        if now - last_time >= 1.0:
            fps = total - last_total

            mbit = (
                fps
                * payload_size
                * 8
                / 1_000_000
            )

            print(
                f"[SERVER] "
                f"{fps:8d} frames/s  "
                f"{mbit:.3f} MBit/s  "
                f"total={total}"
            )

            last_total = total
            last_time = now


def client(iface, duration, classic):
    s = open_socket(iface)

    mode = "Classic CAN" if classic else "CAN-FD"

    print(
        f"[CLIENT] "
        f"{mode} on {iface} "
        f"for {duration:.1f} s"
    )

    tx_counter = 0
    ok = 0
    lost = 0

    start = time.time()

    while True:
        if time.time() - start >= duration:
            break

        if classic:
            frame = build_classic_frame(
                TX_ID,
                tx_counter,
            )

            payload_size = CLASSIC_PAYLOAD_SIZE

        else:
            frame = build_fd_frame(
                TX_ID,
                tx_counter,
            )

            payload_size = FD_PAYLOAD_SIZE

        s.send(frame)

        while True:
            rx = s.recv(CANFD_MTU)

            can_id, rx_counter, is_fd = parse_frame(rx)

            if can_id != RX_ID:
                continue

            break

        if rx_counter == tx_counter:
            ok += 1
        else:
            lost += 1

        tx_counter += 1

    elapsed = time.time() - start

    fps = ok / elapsed

    mbit = (
        fps
        * payload_size
        * 8
        / 1_000_000
    )

    print()
    print("=== CLIENT RESULT ===")
    print(f"Interface : {iface}")
    print(f"Mode      : {mode}")
    print(f"Duration  : {elapsed:.2f} s")
    print(f"OK        : {ok}")
    print(f"Lost      : {lost}")
    print(f"Frames/s  : {fps:.1f}")
    print(f"Payload   : {mbit:.3f} MBit/s")


def main():
    parser = argparse.ArgumentParser(
        description="CAN/CAN-FD request-response test"
    )

    group = parser.add_mutually_exclusive_group(
        required=True,
    )

    group.add_argument(
        "-s",
        "--server",
        action="store_true",
    )

    group.add_argument(
        "-c",
        "--client",
        action="store_true",
    )

    parser.add_argument(
        "--classic",
        action="store_true",
        help="Use Classic CAN frames",
    )

    parser.add_argument(
        "-i",
        "--interface",
        default=CAN_IF_DEFAULT,
    )

    parser.add_argument(
        "-t",
        "--time",
        type=float,
        default=10.0,
    )

    args = parser.parse_args()

    if args.server:
        server(args.interface)

    else:
        client(
            args.interface,
            args.time,
            args.classic,
        )


if __name__ == "__main__":
    main()
