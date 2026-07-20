#!/usr/bin/env python3
"""Local CAN-over-TCP gateway testbench.

The runner and responder may execute directly on the two gateway computers:

    Gateway A: bridge + testbench runner
        CAN/SocketCAN -> bridge A == TCP == bridge B -> CAN/SocketCAN
    Gateway B: bridge + testbench responder

A separate TCP control connection coordinates the tests and returns statistics.
The actual test frames still enter and leave the gateway through SocketCAN.

The same program can also be used in the original four-node topology.
Only Python's standard library is required.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import dataclasses
import html
import json
import logging
import math
import random
import socket
import statistics
import struct
import sys
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any, Final

LOG = logging.getLogger("can-gateway-testbench")

VERSION: Final = "0.2"
CONTROL_PROTOCOL_VERSION: Final = 1

# Linux SocketCAN ABI.
CAN_MTU: Final = 16
CANFD_MTU: Final = 72
CAN_MAX_DLEN: Final = 8
CANFD_MAX_DLEN: Final = 64
CAN_EFF_FLAG: Final = 0x80000000
CAN_RTR_FLAG: Final = 0x40000000
CAN_ERR_FLAG: Final = 0x20000000
CAN_SFF_MASK: Final = 0x000007FF
CAN_EFF_MASK: Final = 0x1FFFFFFF
CANFD_BRS: Final = 0x01
SOL_CAN_RAW: Final = getattr(socket, "SOL_CAN_RAW", 101)
CAN_RAW_FILTER: Final = 1
CAN_RAW_FD_FRAMES: Final = 5

CAN_FRAME_STRUCT: Final = struct.Struct("=IBBBB8s")
CANFD_FRAME_STRUCT: Final = struct.Struct("=IBBBB64s")
CAN_FILTER_STRUCT: Final = struct.Struct("=II")

# Test CAN IDs. They can be shifted together with --base-id.
ID_OFFSETS: Final[dict[str, int]] = {
    "ping_request": 0x00,
    "ping_response": 0x01,
    "forward": 0x10,
    "reverse": 0x11,
    "bidi_master": 0x20,
    "bidi_slave": 0x21,
}

PAYLOAD_HEADER: Final = struct.Struct("!HHI")
PAYLOAD_MAGIC: Final = 0xB17E


class TestbenchError(RuntimeError):
    """Expected testbench/runtime error."""


@dataclasses.dataclass(frozen=True, slots=True)
class CanFrame:
    can_id: int
    data: bytes
    is_fd: bool = False
    brs: bool = False

    def pack(self) -> bytes:
        if self.is_fd:
            if len(self.data) > CANFD_MAX_DLEN:
                raise ValueError("CAN-FD payload is longer than 64 bytes")
            flags = CANFD_BRS if self.brs else 0
            return CANFD_FRAME_STRUCT.pack(
                self.can_id,
                len(self.data),
                flags,
                0,
                0,
                self.data.ljust(CANFD_MAX_DLEN, b"\0"),
            )
        if len(self.data) > CAN_MAX_DLEN:
            raise ValueError("Classical CAN payload is longer than 8 bytes")
        return CAN_FRAME_STRUCT.pack(
            self.can_id,
            len(self.data),
            0,
            0,
            0,
            self.data.ljust(CAN_MAX_DLEN, b"\0"),
        )

    @classmethod
    def unpack(cls, raw: bytes) -> "CanFrame":
        if len(raw) == CAN_MTU:
            can_id, length, _pad, _res0, _len8_dlc, data = CAN_FRAME_STRUCT.unpack(raw)
            if length > CAN_MAX_DLEN:
                raise ValueError(f"invalid Classical CAN length {length}")
            return cls(can_id=can_id, data=data[:length], is_fd=False, brs=False)
        if len(raw) == CANFD_MTU:
            can_id, length, flags, _res0, _res1, data = CANFD_FRAME_STRUCT.unpack(raw)
            if length > CANFD_MAX_DLEN:
                raise ValueError(f"invalid CAN-FD length {length}")
            return cls(
                can_id=can_id,
                data=data[:length],
                is_fd=True,
                brs=bool(flags & CANFD_BRS),
            )
        raise ValueError(f"unexpected SocketCAN frame size {len(raw)}")


class CanSocket:
    def __init__(self, interface: str, accepted_ids: list[int]) -> None:
        if not hasattr(socket, "AF_CAN"):
            raise TestbenchError("Python/Linux has no AF_CAN support")
        self.interface = interface
        self.sock = socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW)
        self.sock.setblocking(False)

        try:
            self.sock.setsockopt(SOL_CAN_RAW, CAN_RAW_FD_FRAMES, 1)
            self.fd_enabled = True
        except OSError as exc:
            self.fd_enabled = False
            LOG.warning("CAN-FD socket option unavailable: %s", exc)

        if accepted_ids:
            filters = b"".join(
                CAN_FILTER_STRUCT.pack(can_id, CAN_SFF_MASK | CAN_EFF_FLAG | CAN_RTR_FLAG)
                for can_id in accepted_ids
            )
            self.sock.setsockopt(SOL_CAN_RAW, CAN_RAW_FILTER, filters)

        try:
            self.sock.bind((interface,))
        except OSError:
            self.sock.close()
            raise

    async def recv(self) -> CanFrame:
        loop = asyncio.get_running_loop()
        while True:
            raw = await loop.sock_recv(self.sock, CANFD_MTU)
            try:
                frame = CanFrame.unpack(raw)
            except ValueError as exc:
                LOG.warning("Ignoring malformed CAN frame: %s", exc)
                continue
            if frame.can_id & CAN_ERR_FLAG:
                LOG.debug("Ignoring CAN error frame 0x%08X", frame.can_id)
                continue
            return frame

    async def send(self, frame: CanFrame) -> None:
        if frame.is_fd and not self.fd_enabled:
            raise TestbenchError("CAN-FD was requested but the socket does not support it")
        raw = frame.pack()
        loop = asyncio.get_running_loop()
        while True:
            try:
                sent = self.sock.send(raw)
                if sent != len(raw):
                    raise TestbenchError(f"short CAN write: {sent}/{len(raw)} bytes")
                return
            except BlockingIOError:
                ready = loop.create_future()

                def writable() -> None:
                    if not ready.done():
                        ready.set_result(None)

                loop.add_writer(self.sock.fileno(), writable)
                try:
                    await ready
                finally:
                    loop.remove_writer(self.sock.fileno())

    def close(self) -> None:
        self.sock.close()


def can_ids(base_id: int) -> dict[str, int]:
    ids = {name: base_id + offset for name, offset in ID_OFFSETS.items()}
    for name, value in ids.items():
        if not 0 <= value <= CAN_SFF_MASK:
            raise ValueError(f"CAN ID for {name} is outside 11-bit range: 0x{value:X}")
    return ids


def build_payload(session: int, sequence: int, length: int) -> bytes:
    if not 8 <= length <= CANFD_MAX_DLEN:
        raise ValueError("test payload length must be between 8 and 64 bytes")
    header = PAYLOAD_HEADER.pack(PAYLOAD_MAGIC, session & 0xFFFF, sequence & 0xFFFFFFFF)
    tail = bytes(
        ((session * 13 + sequence * 17 + index * 29) & 0xFF)
        for index in range(length - len(header))
    )
    return header + tail


def parse_payload(data: bytes, expected_length: int | None = None) -> tuple[int, int]:
    if len(data) < PAYLOAD_HEADER.size:
        raise ValueError("payload shorter than test header")
    if expected_length is not None and len(data) != expected_length:
        raise ValueError(f"payload length {len(data)} != expected {expected_length}")
    magic, session, sequence = PAYLOAD_HEADER.unpack_from(data)
    if magic != PAYLOAD_MAGIC:
        raise ValueError("wrong test payload magic")
    if data != build_payload(session, sequence, len(data)):
        raise ValueError("payload pattern mismatch")
    return session, sequence


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * p
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    fraction = position - lower
    return ordered[lower] * (1.0 - fraction) + ordered[upper] * fraction


@dataclasses.dataclass(slots=True)
class SequenceRecorder:
    session: int
    can_id: int
    expected_count: int
    payload_length: int
    started_ns: int = dataclasses.field(default_factory=time.monotonic_ns)
    first_rx_ns: int | None = None
    last_rx_ns: int | None = None
    highest_sequence: int = -1
    unique_sequences: set[int] = dataclasses.field(default_factory=set)
    duplicates: int = 0
    out_of_order: int = 0
    payload_errors: int = 0
    foreign_session: int = 0
    wrong_can_id: int = 0

    def accept(self, frame: CanFrame, timestamp_ns: int) -> bool:
        if frame.can_id != self.can_id:
            self.wrong_can_id += 1
            return False
        try:
            session, sequence = parse_payload(frame.data, self.payload_length)
        except ValueError:
            self.payload_errors += 1
            return True
        if session != self.session:
            self.foreign_session += 1
            return True
        if self.first_rx_ns is None:
            self.first_rx_ns = timestamp_ns
        self.last_rx_ns = timestamp_ns
        if sequence in self.unique_sequences:
            self.duplicates += 1
            return True
        if sequence < self.highest_sequence:
            self.out_of_order += 1
        self.highest_sequence = max(self.highest_sequence, sequence)
        self.unique_sequences.add(sequence)
        return True

    def report(self, test_name: str, elapsed_s: float | None = None) -> dict[str, Any]:
        unique = len(self.unique_sequences)
        missing = max(0, self.expected_count - unique)
        rx_span_s = None
        if self.first_rx_ns is not None and self.last_rx_ns is not None:
            rx_span_s = max(0.0, (self.last_rx_ns - self.first_rx_ns) / 1e9)
        duration_s = elapsed_s if elapsed_s is not None else rx_span_s
        fps = None
        payload_kbit_s = None
        if rx_span_s is not None and rx_span_s > 0 and unique > 1:
            fps = (unique - 1) / rx_span_s
            payload_kbit_s = fps * self.payload_length * 8 / 1000.0
        return {
            "test": test_name,
            "expected": self.expected_count,
            "received_unique": unique,
            "missing": missing,
            "loss_percent": (missing / self.expected_count * 100.0) if self.expected_count else 0.0,
            "duplicates": self.duplicates,
            "out_of_order": self.out_of_order,
            "payload_errors": self.payload_errors,
            "foreign_session": self.foreign_session,
            "duration_s": duration_s,
            "receive_span_s": rx_span_s,
            "receive_fps": fps,
            "payload_kbit_s": payload_kbit_s,
        }


@dataclasses.dataclass(slots=True)
class PingTracker:
    session: int
    can_id: int
    expected_count: int
    payload_length: int
    sent_ns: dict[int, int] = dataclasses.field(default_factory=dict)
    received_sequences: set[int] = dataclasses.field(default_factory=set)
    samples: list[dict[str, Any]] = dataclasses.field(default_factory=list)
    duplicates: int = 0
    payload_errors: int = 0
    foreign_session: int = 0
    unmatched: int = 0

    def mark_sent(self, sequence: int, timestamp_ns: int) -> None:
        self.sent_ns[sequence] = timestamp_ns

    def accept(self, frame: CanFrame, timestamp_ns: int) -> bool:
        if frame.can_id != self.can_id:
            return False
        try:
            session, sequence = parse_payload(frame.data, self.payload_length)
        except ValueError:
            self.payload_errors += 1
            return True
        if session != self.session:
            self.foreign_session += 1
            return True
        if sequence in self.received_sequences:
            self.duplicates += 1
            return True
        sent = self.sent_ns.get(sequence)
        if sent is None:
            self.unmatched += 1
            return True
        self.received_sequences.add(sequence)
        rtt_ms = (timestamp_ns - sent) / 1e6
        self.samples.append(
            {
                "sequence": sequence,
                "send_monotonic_ns": sent,
                "receive_monotonic_ns": timestamp_ns,
                "rtt_ms": rtt_ms,
            }
        )
        return True

    def report(self, elapsed_s: float) -> dict[str, Any]:
        rtts = [float(sample["rtt_ms"]) for sample in self.samples]
        received = len(self.received_sequences)
        missing = max(0, self.expected_count - received)
        return {
            "test": "ping_round_trip",
            "expected": self.expected_count,
            "received_unique": received,
            "missing": missing,
            "loss_percent": (missing / self.expected_count * 100.0) if self.expected_count else 0.0,
            "duplicates": self.duplicates,
            "out_of_order": 0,
            "payload_errors": self.payload_errors,
            "foreign_session": self.foreign_session,
            "unmatched": self.unmatched,
            "duration_s": elapsed_s,
            "receive_span_s": None,
            "receive_fps": received / elapsed_s if elapsed_s > 0 else None,
            "payload_kbit_s": None,
            "rtt_min_ms": min(rtts) if rtts else None,
            "rtt_mean_ms": statistics.fmean(rtts) if rtts else None,
            "rtt_p50_ms": percentile(rtts, 0.50),
            "rtt_p95_ms": percentile(rtts, 0.95),
            "rtt_p99_ms": percentile(rtts, 0.99),
            "rtt_max_ms": max(rtts) if rtts else None,
            "rtt_stddev_ms": statistics.pstdev(rtts) if len(rtts) > 1 else (0.0 if rtts else None),
        }


async def sleep_until(target: float) -> None:
    delay = target - time.monotonic()
    if delay > 0:
        await asyncio.sleep(delay)


async def send_test_stream(
    can: CanSocket,
    *,
    can_id: int,
    session: int,
    count: int,
    rate: float,
    payload_length: int,
    is_fd: bool,
    brs: bool,
    before_send: Callable[[int, int], None] | None = None,
) -> dict[str, Any]:
    start = time.monotonic()
    start_ns = time.monotonic_ns()
    errors = 0
    interval = 1.0 / rate if rate > 0 else 0.0

    for sequence in range(count):
        if interval:
            await sleep_until(start + sequence * interval)
        timestamp_ns = time.monotonic_ns()
        if before_send is not None:
            before_send(sequence, timestamp_ns)
        frame = CanFrame(
            can_id=can_id,
            data=build_payload(session, sequence, payload_length),
            is_fd=is_fd,
            brs=brs,
        )
        try:
            await can.send(frame)
        except (OSError, TestbenchError) as exc:
            errors += 1
            LOG.error("CAN send failed at sequence %d: %s", sequence, exc)
        if not interval and sequence % 256 == 255:
            await asyncio.sleep(0)

    end_ns = time.monotonic_ns()
    elapsed = (end_ns - start_ns) / 1e9
    return {
        "requested": count,
        "send_errors": errors,
        "sent_without_error": count - errors,
        "elapsed_s": elapsed,
        "requested_rate_fps": rate,
        "actual_send_fps": ((count - errors) / elapsed) if elapsed > 0 else None,
    }


async def read_json_line(reader: asyncio.StreamReader) -> dict[str, Any]:
    line = await reader.readline()
    if not line:
        raise EOFError("control connection closed")
    if len(line) > 1_000_000:
        raise TestbenchError("control message too large")
    value = json.loads(line)
    if not isinstance(value, dict):
        raise TestbenchError("control message is not a JSON object")
    return value


async def write_json_line(writer: asyncio.StreamWriter, value: dict[str, Any]) -> None:
    data = json.dumps(value, separators=(",", ":"), allow_nan=False).encode("utf-8") + b"\n"
    writer.write(data)
    await writer.drain()


class SlaveApp:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.ids = can_ids(args.base_id)
        self.can = CanSocket(args.can, list(self.ids.values()))
        self.active_recorder: SequenceRecorder | None = None
        self.recorder_lock = asyncio.Lock()
        self.send_lock = asyncio.Lock()
        self.running = True
        self.echo_count = 0
        self.echo_errors = 0

    async def can_receive_loop(self) -> None:
        while self.running:
            frame = await self.can.recv()
            now_ns = time.monotonic_ns()
            if frame.can_id == self.ids["ping_request"]:
                try:
                    parse_payload(frame.data)
                except ValueError:
                    continue
                response = CanFrame(
                    can_id=self.ids["ping_response"],
                    data=frame.data,
                    is_fd=frame.is_fd,
                    brs=frame.brs,
                )
                try:
                    await self.can.send(response)
                    self.echo_count += 1
                except (OSError, TestbenchError) as exc:
                    self.echo_errors += 1
                    LOG.error("Ping echo failed: %s", exc)
                continue

            recorder = self.active_recorder
            if recorder is not None:
                recorder.accept(frame, now_ns)

    async def handle_control(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        peer = writer.get_extra_info("peername")
        LOG.info("Control connection from %s", peer)
        try:
            while True:
                request = await read_json_line(reader)
                request_id = request.get("request_id")
                command = request.get("command")
                try:
                    result = await self.execute_command(command, request)
                    response = {"request_id": request_id, "ok": True, "result": result}
                except Exception as exc:  # Keep slave alive; report command failure.
                    LOG.exception("Control command %r failed", command)
                    response = {"request_id": request_id, "ok": False, "error": str(exc)}
                await write_json_line(writer, response)
        except (EOFError, ConnectionResetError, BrokenPipeError):
            LOG.info("Control connection from %s closed", peer)
        except json.JSONDecodeError as exc:
            LOG.warning("Invalid JSON from %s: %s", peer, exc)
        finally:
            writer.close()
            await writer.wait_closed()

    async def execute_command(self, command: Any, request: dict[str, Any]) -> dict[str, Any]:
        if command == "hello":
            return {
                "application": "can-gateway-testbench",
                "version": VERSION,
                "control_protocol": CONTROL_PROTOCOL_VERSION,
                "can_interface": self.args.can,
                "base_id": self.args.base_id,
                "ids": self.ids,
                "fd_socket_enabled": self.can.fd_enabled,
            }

        if command == "status":
            recorder = self.active_recorder
            return {
                "echo_count": self.echo_count,
                "echo_errors": self.echo_errors,
                "recorder_active": recorder is not None,
                "recorder_session": recorder.session if recorder else None,
            }

        if command == "prepare_receive":
            async with self.recorder_lock:
                self.active_recorder = SequenceRecorder(
                    session=int(request["session"]),
                    can_id=int(request["can_id"]),
                    expected_count=int(request["count"]),
                    payload_length=int(request["payload_length"]),
                )
            return {"prepared": True}

        if command == "finish_receive":
            async with self.recorder_lock:
                recorder = self.active_recorder
                if recorder is None:
                    raise TestbenchError("no active receive recorder")
                report = recorder.report(str(request.get("test_name", "remote_receive")))
                self.active_recorder = None
            return report

        if command == "send_stream":
            async with self.send_lock:
                return await send_test_stream(
                    self.can,
                    can_id=int(request["can_id"]),
                    session=int(request["session"]),
                    count=int(request["count"]),
                    rate=float(request["rate"]),
                    payload_length=int(request["payload_length"]),
                    is_fd=bool(request["is_fd"]),
                    brs=bool(request["brs"]),
                )

        raise TestbenchError(f"unknown control command {command!r}")

    async def run(self) -> None:
        server = await asyncio.start_server(
            self.handle_control,
            self.args.control_bind,
            self.args.control_port,
            limit=1_100_000,
        )
        addresses = ", ".join(str(sock.getsockname()) for sock in server.sockets or [])
        LOG.info("Slave ready: CAN=%s, control=%s", self.args.can, addresses)
        receive_task = asyncio.create_task(self.can_receive_loop(), name="can-receive")
        try:
            async with server:
                await server.serve_forever()
        finally:
            self.running = False
            receive_task.cancel()
            await asyncio.gather(receive_task, return_exceptions=True)
            self.can.close()


class ControlClient:
    def __init__(self, host: str, port: int) -> None:
        self.host = host
        self.port = port
        self.reader: asyncio.StreamReader | None = None
        self.writer: asyncio.StreamWriter | None = None
        self.request_sequence = 0
        self.lock = asyncio.Lock()

    async def connect(self) -> None:
        self.reader, self.writer = await asyncio.open_connection(self.host, self.port, limit=1_100_000)

    async def request(self, command: str, **kwargs: Any) -> dict[str, Any]:
        async with self.lock:
            if self.reader is None or self.writer is None:
                raise TestbenchError("control client is not connected")
            self.request_sequence += 1
            request_id = self.request_sequence
            request = {"request_id": request_id, "command": command, **kwargs}
            await write_json_line(self.writer, request)
            response = await read_json_line(self.reader)
            if response.get("request_id") != request_id:
                raise TestbenchError("control response ID mismatch")
            if not response.get("ok"):
                raise TestbenchError(str(response.get("error", "remote command failed")))
            result = response.get("result")
            if not isinstance(result, dict):
                raise TestbenchError("control response result is not an object")
            return result

    async def close(self) -> None:
        if self.writer is not None:
            self.writer.close()
            await self.writer.wait_closed()
            self.writer = None
            self.reader = None


class MasterApp:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.ids = can_ids(args.base_id)
        self.can = CanSocket(args.can, list(self.ids.values()))
        self.control = ControlClient(args.slave, args.control_port)
        self.ping_tracker: PingTracker | None = None
        self.sequence_recorder: SequenceRecorder | None = None
        self.running = True
        self.results: list[dict[str, Any]] = []
        self.ping_samples: list[dict[str, Any]] = []
        self.send_reports: dict[str, dict[str, Any]] = {}
        self.session = random.SystemRandom().randrange(1, 0x10000)

    async def can_receive_loop(self) -> None:
        while self.running:
            frame = await self.can.recv()
            now_ns = time.monotonic_ns()
            tracker = self.ping_tracker
            if tracker is not None and tracker.accept(frame, now_ns):
                continue
            recorder = self.sequence_recorder
            if recorder is not None:
                recorder.accept(frame, now_ns)

    def common_stream_args(self, can_id: int) -> dict[str, Any]:
        return {
            "can_id": can_id,
            "session": self.session,
            "count": self.args.count,
            "rate": self.args.rate,
            "payload_length": self.args.payload_length,
            "is_fd": self.args.fd,
            "brs": self.args.brs,
        }

    async def run_ping(self) -> None:
        LOG.info("Test 1/4: round-trip ping (%d frames)", self.args.ping_count)
        tracker = PingTracker(
            session=self.session,
            can_id=self.ids["ping_response"],
            expected_count=self.args.ping_count,
            payload_length=self.args.payload_length,
        )
        self.ping_tracker = tracker
        start_ns = time.monotonic_ns()
        send_report = await send_test_stream(
            self.can,
            can_id=self.ids["ping_request"],
            session=self.session,
            count=self.args.ping_count,
            rate=self.args.ping_rate,
            payload_length=self.args.payload_length,
            is_fd=self.args.fd,
            brs=self.args.brs,
            before_send=tracker.mark_sent,
        )
        self.send_reports["ping_round_trip"] = send_report
        deadline = time.monotonic() + self.args.settle
        while len(tracker.received_sequences) < self.args.ping_count and time.monotonic() < deadline:
            await asyncio.sleep(0.01)
        elapsed_s = (time.monotonic_ns() - start_ns) / 1e9
        self.ping_tracker = None
        result = tracker.report(elapsed_s)
        result["send_errors"] = send_report["send_errors"]
        self.results.append(result)
        self.ping_samples = sorted(tracker.samples, key=lambda row: int(row["sequence"]))
        LOG.info(
            "Ping: %d/%d, loss %.3f%%, p95=%s ms",
            result["received_unique"],
            result["expected"],
            result["loss_percent"],
            format_optional(result.get("rtt_p95_ms"), 3),
        )

    async def run_forward(self) -> None:
        LOG.info("Test 2/4: runner -> responder (%d frames)", self.args.count)
        await self.control.request(
            "prepare_receive",
            session=self.session,
            can_id=self.ids["forward"],
            count=self.args.count,
            payload_length=self.args.payload_length,
        )
        send_report = await send_test_stream(
            self.can,
            **self.common_stream_args(self.ids["forward"]),
        )
        self.send_reports["forward_master_to_slave"] = send_report
        await asyncio.sleep(self.args.settle)
        result = await self.control.request("finish_receive", test_name="forward_master_to_slave")
        result["send_errors"] = send_report["send_errors"]
        self.results.append(result)
        log_sequence_result(result)

    async def run_reverse(self) -> None:
        LOG.info("Test 3/4: responder -> runner (%d frames)", self.args.count)
        recorder = SequenceRecorder(
            session=self.session,
            can_id=self.ids["reverse"],
            expected_count=self.args.count,
            payload_length=self.args.payload_length,
        )
        self.sequence_recorder = recorder
        start_ns = time.monotonic_ns()
        send_report = await self.control.request(
            "send_stream",
            **self.common_stream_args(self.ids["reverse"]),
        )
        self.send_reports["reverse_slave_to_master"] = send_report
        await asyncio.sleep(self.args.settle)
        elapsed_s = (time.monotonic_ns() - start_ns) / 1e9
        self.sequence_recorder = None
        result = recorder.report("reverse_slave_to_master", elapsed_s=elapsed_s)
        result["send_errors"] = send_report["send_errors"]
        self.results.append(result)
        log_sequence_result(result)

    async def run_bidirectional(self) -> None:
        LOG.info("Test 4/4: bidirectional simultaneous traffic")
        await self.control.request(
            "prepare_receive",
            session=self.session,
            can_id=self.ids["bidi_master"],
            count=self.args.count,
            payload_length=self.args.payload_length,
        )
        local_recorder = SequenceRecorder(
            session=self.session,
            can_id=self.ids["bidi_slave"],
            expected_count=self.args.count,
            payload_length=self.args.payload_length,
        )
        self.sequence_recorder = local_recorder
        start_ns = time.monotonic_ns()

        remote_send_task = asyncio.create_task(
            self.control.request(
                "send_stream",
                **self.common_stream_args(self.ids["bidi_slave"]),
            ),
            name="remote-bidirectional-send",
        )
        await asyncio.sleep(self.args.bidi_lead)
        local_send_report = await send_test_stream(
            self.can,
            **self.common_stream_args(self.ids["bidi_master"]),
        )
        remote_send_report = await remote_send_task
        await asyncio.sleep(self.args.settle)
        elapsed_s = (time.monotonic_ns() - start_ns) / 1e9
        self.sequence_recorder = None

        remote_receive_result = await self.control.request(
            "finish_receive", test_name="bidirectional_master_to_slave"
        )
        remote_receive_result["send_errors"] = local_send_report["send_errors"]
        local_receive_result = local_recorder.report(
            "bidirectional_slave_to_master", elapsed_s=elapsed_s
        )
        local_receive_result["send_errors"] = remote_send_report["send_errors"]

        self.send_reports["bidirectional_master_to_slave"] = local_send_report
        self.send_reports["bidirectional_slave_to_master"] = remote_send_report
        self.results.extend([remote_receive_result, local_receive_result])
        log_sequence_result(remote_receive_result)
        log_sequence_result(local_receive_result)

    async def run(self) -> tuple[Path, bool]:
        await self.control.connect()
        hello = await self.control.request("hello")
        if int(hello.get("control_protocol", -1)) != CONTROL_PROTOCOL_VERSION:
            raise TestbenchError("runner/responder control protocol mismatch")
        if int(hello.get("base_id", -1)) != self.args.base_id:
            raise TestbenchError(
                f"base CAN ID mismatch: runner=0x{self.args.base_id:X}, "
                f"responder=0x{int(hello.get('base_id', -1)):X}"
            )
        LOG.info(
            "Connected to responder %s; remote CAN=%s; session=0x%04X",
            self.args.slave,
            hello.get("can_interface"),
            self.session,
        )

        receive_task = asyncio.create_task(self.can_receive_loop(), name="master-can-receive")
        try:
            await self.run_ping()
            await self.run_forward()
            await self.run_reverse()
            await self.run_bidirectional()
        finally:
            self.running = False
            receive_task.cancel()
            await asyncio.gather(receive_task, return_exceptions=True)
            await self.control.close()
            self.can.close()

        output_dir = create_output_directory(self.args.output)
        metadata = {
            "application": "can-gateway-testbench",
            "version": VERSION,
            "created_local": time.strftime("%Y-%m-%d %H:%M:%S %z"),
            "runner_hostname": socket.gethostname(),
            "responder_address": self.args.slave,
            "runner_can_interface": self.args.can,
            "responder_can_interface": hello.get("can_interface"),
            "session": self.session,
            "configuration": {
                "base_id": self.args.base_id,
                "ids": self.ids,
                "can_fd": self.args.fd,
                "brs": self.args.brs,
                "payload_length": self.args.payload_length,
                "ping_count": self.args.ping_count,
                "ping_rate": self.args.ping_rate,
                "stream_count": self.args.count,
                "stream_rate": self.args.rate,
                "settle_s": self.args.settle,
            },
        }
        overall_passed = evaluate_results(self.results, self.args)
        metadata["acceptance"] = {
            "max_loss_percent": self.args.max_loss_percent,
            "max_duplicates": self.args.max_duplicates,
            "max_out_of_order": self.args.max_out_of_order,
            "max_payload_errors": self.args.max_payload_errors,
            "max_p95_rtt_ms": self.args.max_p95_rtt_ms,
            "overall_passed": overall_passed,
        }
        write_results(output_dir, metadata, self.results, self.ping_samples, self.send_reports)
        return output_dir, overall_passed


def create_output_directory(requested: str | None) -> Path:
    if requested:
        path = Path(requested)
    else:
        path = Path("results") / time.strftime("%Y%m%d-%H%M%S")
    path.mkdir(parents=True, exist_ok=False)
    return path


def format_optional(value: Any, digits: int = 2) -> str:
    if value is None:
        return "–"
    if isinstance(value, float):
        return f"{value:.{digits}f}"
    return str(value)


def log_sequence_result(result: dict[str, Any]) -> None:
    LOG.info(
        "%s: %s/%s, loss %.3f%%, dup=%s, reorder=%s, corrupt=%s",
        result.get("test"),
        result.get("received_unique"),
        result.get("expected"),
        float(result.get("loss_percent", 0.0)),
        result.get("duplicates"),
        result.get("out_of_order"),
        result.get("payload_errors"),
    )


def evaluate_results(results: list[dict[str, Any]], args: argparse.Namespace) -> bool:
    overall = True
    for result in results:
        reasons: list[str] = []
        if float(result.get("loss_percent", 0.0)) > args.max_loss_percent:
            reasons.append(
                f"loss {float(result.get('loss_percent', 0.0)):.3f}% > {args.max_loss_percent:.3f}%"
            )
        if int(result.get("duplicates", 0)) > args.max_duplicates:
            reasons.append(
                f"duplicates {int(result.get('duplicates', 0))} > {args.max_duplicates}"
            )
        if int(result.get("out_of_order", 0)) > args.max_out_of_order:
            reasons.append(
                f"out-of-order {int(result.get('out_of_order', 0))} > {args.max_out_of_order}"
            )
        if int(result.get("payload_errors", 0)) > args.max_payload_errors:
            reasons.append(
                f"payload errors {int(result.get('payload_errors', 0))} > {args.max_payload_errors}"
            )
        if int(result.get("send_errors", 0)) > 0:
            reasons.append(f"send errors {int(result.get('send_errors', 0))}")
        if result.get("test") == "ping_round_trip" and args.max_p95_rtt_ms is not None:
            p95 = result.get("rtt_p95_ms")
            if p95 is None or float(p95) > args.max_p95_rtt_ms:
                reasons.append(
                    f"p95 RTT {format_optional(p95, 3)} ms > {args.max_p95_rtt_ms:.3f} ms"
                )
        result["passed"] = not reasons
        result["fail_reasons"] = reasons
        overall = overall and not reasons
    return overall


def write_results(
    output_dir: Path,
    metadata: dict[str, Any],
    results: list[dict[str, Any]],
    ping_samples: list[dict[str, Any]],
    send_reports: dict[str, dict[str, Any]],
) -> None:
    summary = {
        "metadata": metadata,
        "overall_passed": bool(metadata.get("acceptance", {}).get("overall_passed", False)),
        "tests": results,
        "send_reports": send_reports,
    }
    (output_dir / "summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False, allow_nan=False) + "\n",
        encoding="utf-8",
    )

    all_fields: list[str] = []
    for row in results:
        for key in row:
            if key not in all_fields:
                all_fields.append(key)
    with (output_dir / "summary.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=all_fields)
        writer.writeheader()
        writer.writerows(results)

    with (output_dir / "ping_samples.csv").open("w", newline="", encoding="utf-8") as handle:
        fields = ["sequence", "send_monotonic_ns", "receive_monotonic_ns", "rtt_ms"]
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(ping_samples)

    (output_dir / "report.html").write_text(
        build_html_report(metadata, results, ping_samples), encoding="utf-8"
    )


def build_html_report(
    metadata: dict[str, Any],
    results: list[dict[str, Any]],
    ping_samples: list[dict[str, Any]],
) -> str:
    rtts = [float(row["rtt_ms"]) for row in ping_samples]
    histogram = build_histogram_svg(rtts)
    rows = []
    for result in results:
        rows.append(
            "<tr>"
            f"<td>{html.escape(str(result.get('test', '')))}</td>"
            f"<td>{'PASS' if result.get('passed') else 'FAIL'}</td>"
            f"<td>{result.get('expected', '')}</td>"
            f"<td>{result.get('received_unique', '')}</td>"
            f"<td>{format_optional(result.get('loss_percent'), 3)}%</td>"
            f"<td>{result.get('duplicates', '')}</td>"
            f"<td>{result.get('out_of_order', '')}</td>"
            f"<td>{result.get('payload_errors', '')}</td>"
            f"<td>{format_optional(result.get('receive_fps'), 1)}</td>"
            "</tr>"
        )
    ping_result = next((row for row in results if row.get("test") == "ping_round_trip"), {})
    config = metadata["configuration"]
    acceptance = metadata.get("acceptance", {})
    overall_passed = bool(acceptance.get("overall_passed", False))
    overall_text = "PASS" if overall_passed else "FAIL"
    overall_class = "pass" if overall_passed else "fail"
    return f"""<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CAN Gateway Testbench Report</title>
<style>
body {{ font-family: system-ui, sans-serif; margin: 2rem auto; max-width: 1100px; line-height: 1.45; color: #202124; }}
h1, h2 {{ line-height: 1.15; }}
.cards {{ display: grid; grid-template-columns: repeat(auto-fit,minmax(190px,1fr)); gap: 1rem; }}
.card {{ border: 1px solid #dadce0; border-radius: 10px; padding: 1rem; }}
.value {{ font-size: 1.6rem; font-weight: 700; }}
table {{ border-collapse: collapse; width: 100%; margin: 1rem 0 2rem; }}
th, td {{ border-bottom: 1px solid #dadce0; text-align: right; padding: .55rem; }}
th:first-child, td:first-child {{ text-align: left; }}
code {{ background: #f1f3f4; padding: .1rem .3rem; border-radius: 4px; }}
.small {{ color: #5f6368; font-size: .92rem; }}
.status {{ display: inline-block; padding: .25rem .65rem; border-radius: 999px; font-weight: 700; }}
.pass {{ background: #d7f5dd; color: #137333; }}
.fail {{ background: #fce8e6; color: #a50e0e; }}
svg {{ width: 100%; height: auto; border: 1px solid #dadce0; border-radius: 8px; }}
</style>
</head>
<body>
<h1>CAN Gateway Testbench <span class="status {overall_class}">{overall_text}</span></h1>
<p class="small">Erzeugt {html.escape(str(metadata['created_local']))} · Master {html.escape(str(metadata['runner_hostname']))} · Slave {html.escape(str(metadata['responder_address']))}</p>

<h2>Konfiguration</h2>
<p><code>{html.escape(str(metadata['runner_can_interface']))}</code> ↔ Gateway ↔ Gateway ↔ <code>{html.escape(str(metadata['responder_can_interface']))}</code>, Session <code>0x{int(metadata['session']):04X}</code>, Basis-ID <code>0x{int(config['base_id']):03X}</code>, Payload {int(config['payload_length'])} Byte, CAN-FD {str(bool(config['can_fd'])).lower()}, BRS {str(bool(config['brs'])).lower()}.</p>

<h2>Ergebnisübersicht</h2>
<table>
<thead><tr><th>Test</th><th>Status</th><th>Gesendet</th><th>Empfangen</th><th>Verlust</th><th>Duplikate</th><th>Reihenfolge</th><th>Datenfehler</th><th>Frames/s</th></tr></thead>
<tbody>{''.join(rows)}</tbody>
</table>

<h2>Round-Trip-Latenz</h2>
<div class="cards">
<div class="card"><div class="small">Mittelwert</div><div class="value">{format_optional(ping_result.get('rtt_mean_ms'), 3)} ms</div></div>
<div class="card"><div class="small">Median</div><div class="value">{format_optional(ping_result.get('rtt_p50_ms'), 3)} ms</div></div>
<div class="card"><div class="small">95. Perzentil</div><div class="value">{format_optional(ping_result.get('rtt_p95_ms'), 3)} ms</div></div>
<div class="card"><div class="small">Maximum</div><div class="value">{format_optional(ping_result.get('rtt_max_ms'), 3)} ms</div></div>
</div>
{histogram}
<p class="small">Die Latenz ist die vollständige Runde Pi 1 → CAN → beide Gateways → CAN → Pi 4 → Echo → zurück zu Pi 1.</p>

<h2>Dateien</h2>
<p><code>summary.json</code> enthält alle Rohkennzahlen, <code>summary.csv</code> die tabellarische Übersicht und <code>ping_samples.csv</code> jeden einzelnen RTT-Messwert.</p>
</body>
</html>
"""


def build_histogram_svg(values: list[float], bins: int = 30) -> str:
    if not values:
        return "<p>Keine gültigen RTT-Messwerte vorhanden.</p>"
    low = min(values)
    high = max(values)
    if math.isclose(low, high):
        high = low + 1.0
    counts = [0] * bins
    for value in values:
        index = min(bins - 1, int((value - low) / (high - low) * bins))
        counts[index] += 1
    width, height = 900, 260
    margin_left, margin_right, margin_top, margin_bottom = 55, 20, 20, 42
    chart_w = width - margin_left - margin_right
    chart_h = height - margin_top - margin_bottom
    max_count = max(counts) or 1
    bar_w = chart_w / bins
    bars = []
    for index, count in enumerate(counts):
        bar_h = chart_h * count / max_count
        x = margin_left + index * bar_w
        y = margin_top + chart_h - bar_h
        bars.append(
            f'<rect x="{x:.2f}" y="{y:.2f}" width="{max(1.0, bar_w - 1):.2f}" height="{bar_h:.2f}" fill="currentColor" opacity="0.75" />'
        )
    return f"""
<svg viewBox="0 0 {width} {height}" role="img" aria-label="RTT-Histogramm">
<line x1="{margin_left}" y1="{margin_top + chart_h}" x2="{margin_left + chart_w}" y2="{margin_top + chart_h}" stroke="currentColor" />
<line x1="{margin_left}" y1="{margin_top}" x2="{margin_left}" y2="{margin_top + chart_h}" stroke="currentColor" />
{''.join(bars)}
<text x="{margin_left}" y="{height - 12}" font-size="13">{low:.3f} ms</text>
<text x="{margin_left + chart_w}" y="{height - 12}" font-size="13" text-anchor="end">{high:.3f} ms</text>
<text x="15" y="{margin_top + 12}" font-size="13">{max_count}</text>
<text x="{width / 2}" y="{height - 12}" font-size="13" text-anchor="middle">Round-Trip-Zeit</text>
</svg>
"""


def add_common_can_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--can", default="can0", help="SocketCAN interface (default: can0)")
    parser.add_argument(
        "--base-id",
        type=lambda value: int(value, 0),
        default=0x600,
        help="base CAN ID for test frames (default: 0x600)",
    )
    parser.add_argument("--control-port", type=int, default=29600, help="WLAN control TCP port")


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Local or four-node testbench for a transparent CAN-over-TCP gateway pair"
    )
    parser.add_argument("--verbose", action="store_true", help="enable debug logging")
    subparsers = parser.add_subparsers(dest="role", required=True)

    slave = subparsers.add_parser(
        "responder", aliases=["slave"],
        help="run on the remote gateway/test endpoint",
    )
    slave.set_defaults(role_kind="slave")
    add_common_can_arguments(slave)
    slave.add_argument(
        "--control-bind",
        default="0.0.0.0",
        help="address for the control server (default: 0.0.0.0)",
    )

    master = subparsers.add_parser(
        "run", aliases=["master"],
        help="run the complete suite from this gateway/test endpoint",
    )
    master.set_defaults(role_kind="master")
    add_common_can_arguments(master)
    master.add_argument(
        "--peer", "--slave", dest="slave", required=True,
        help="responder IP address or hostname",
    )
    master.add_argument("--count", type=int, default=5000, help="frames per stream test")
    master.add_argument("--rate", type=float, default=500.0, help="stream frames/s; 0 = unpaced")
    master.add_argument("--ping-count", type=int, default=1000, help="round-trip ping frames")
    master.add_argument("--ping-rate", type=float, default=100.0, help="ping frames/s")
    master.add_argument("--settle", type=float, default=2.0, help="wait after each test in seconds")
    master.add_argument(
        "--bidi-lead",
        type=float,
        default=0.05,
        help="head start for responder in bidirectional test",
    )
    master.add_argument("--fd", action="store_true", help="send CAN-FD frames")
    master.add_argument("--brs", action="store_true", help="set CAN-FD bit-rate-switch flag")
    master.add_argument(
        "--payload-length",
        type=int,
        default=8,
        help="payload bytes: 8 for Classical CAN, 8..64 for CAN-FD",
    )
    master.add_argument("--output", help="new result directory; default: results/TIMESTAMP")
    master.add_argument(
        "--max-loss-percent", type=float, default=0.0,
        help="maximum accepted loss per test (default: 0)",
    )
    master.add_argument(
        "--max-duplicates", type=int, default=0,
        help="maximum accepted duplicates per test (default: 0)",
    )
    master.add_argument(
        "--max-out-of-order", type=int, default=0,
        help="maximum accepted sequence-order errors per test (default: 0)",
    )
    master.add_argument(
        "--max-payload-errors", type=int, default=0,
        help="maximum accepted payload errors per test (default: 0)",
    )
    master.add_argument(
        "--max-p95-rtt-ms", type=float,
        help="optional maximum accepted ping p95 RTT in milliseconds",
    )
    master.add_argument(
        "--no-fail-exit", action="store_true",
        help="return exit status 0 even when acceptance criteria fail",
    )
    return parser


def validate_arguments(args: argparse.Namespace) -> None:
    can_ids(args.base_id)
    if args.role_kind == "master":
        for name in ("count", "ping_count"):
            if getattr(args, name) <= 0:
                raise TestbenchError(f"--{name.replace('_', '-')} must be greater than zero")
        for name in ("rate", "ping_rate", "settle", "bidi_lead", "max_loss_percent"):
            if getattr(args, name) < 0:
                raise TestbenchError(f"--{name.replace('_', '-')} must not be negative")
        if args.fd:
            if not 8 <= args.payload_length <= CANFD_MAX_DLEN:
                raise TestbenchError("CAN-FD payload length must be 8..64")
        else:
            if args.payload_length != CAN_MAX_DLEN:
                raise TestbenchError("Classical CAN test payload length must be exactly 8")
            if args.brs:
                raise TestbenchError("--brs requires --fd")
        for name in ("max_duplicates", "max_out_of_order", "max_payload_errors"):
            if getattr(args, name) < 0:
                raise TestbenchError(f"--{name.replace('_', '-')} must not be negative")
        if args.max_p95_rtt_ms is not None and args.max_p95_rtt_ms < 0:
            raise TestbenchError("--max-p95-rtt-ms must not be negative")


async def async_main(args: argparse.Namespace) -> int:
    if args.role_kind == "slave":
        await SlaveApp(args).run()
        return 0
    output_dir, passed = await MasterApp(args).run()
    print(f"\nTest complete: {'PASS' if passed else 'FAIL'}")
    print(f"Results: {output_dir.resolve()}")
    print(f"HTML report: {output_dir.joinpath('report.html').resolve()}")
    return 0 if passed or args.no_fail_exit else 1


def main() -> int:
    parser = build_argument_parser()
    args = parser.parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    try:
        validate_arguments(args)
        return asyncio.run(async_main(args))
    except KeyboardInterrupt:
        return 130
    except (OSError, TestbenchError, ValueError) as exc:
        LOG.error("%s", exc)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
