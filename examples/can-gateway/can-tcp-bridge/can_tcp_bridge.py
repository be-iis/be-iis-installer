#!/usr/bin/env python3
"""Bidirectional SocketCAN-over-TCP bridge.

Both endpoints run this same program. The normal invocation needs only:

    ./can_tcp_bridge.py <peer-ip> <can-interface>

In automatic mode, the endpoint with the numerically lower IPv4 address acts
as TCP server and the endpoint with the higher address acts as TCP client.

The bridge uses SocketCAN's own-message loopback and MSG_CONFIRM to distinguish
frames injected by the bridge from locally observed CAN traffic. A confirmed
remote CAN transmission is reported to the originating endpoint.
"""

from __future__ import annotations

import argparse
import asyncio
import collections
import contextlib
import dataclasses
import enum
import ipaddress
import logging
import random
import signal
import socket
import struct
import time
from collections.abc import Callable
from typing import Final

LOG = logging.getLogger("can-tcp-bridge")

# Linux SocketCAN ABI constants.
CAN_MTU: Final = 16
CANFD_MTU: Final = 72
CAN_MAX_DLEN: Final = 8
CANFD_MAX_DLEN: Final = 64
CAN_ERR_FLAG: Final = 0x20000000
CAN_ERR_MASK: Final = 0x1FFFFFFF
CAN_ERR_ACK: Final = 0x00000020
CAN_ERR_BUSOFF: Final = 0x00000040
CAN_ERR_RESTARTED: Final = 0x00000100

# Native-endian Linux userspace structures. Both have the same first 8 bytes.
CAN_FRAME_STRUCT: Final = struct.Struct("=IBBBB8s")
CANFD_FRAME_STRUCT: Final = struct.Struct("=IBBBB64s")

MAGIC: Final = b"BCTP"
PROTOCOL_VERSION: Final = 1
APPLICATION_VERSION: Final = "0.1.1"
MAX_PACKET_PAYLOAD: Final = 4096
HEADER_STRUCT: Final = struct.Struct("!4sBBHI")
HELLO_STRUCT: Final = struct.Struct("!Q")
FRAME_STRUCT: Final = struct.Struct("!QQIBBBB64s")
TX_RESULT_STRUCT: Final = struct.Struct("!QQB3x")
PING_STRUCT: Final = struct.Struct("!Q")


class PacketType(enum.IntEnum):
    HELLO = 1
    CAN_FRAME = 2
    TX_RESULT = 3
    PING = 4
    PONG = 5


class FrameKind(enum.IntEnum):
    CLASSIC = 0
    FD = 1


class TxStatus(enum.IntEnum):
    CONFIRMED = 0
    SEND_ERROR = 1
    CONFIRM_TIMEOUT = 2


class RemoteState(enum.Enum):
    ASSUMED_UP = "assumed-up"
    CONFIRMED_UP = "confirmed-up"
    DOWN = "down"


@dataclasses.dataclass(frozen=True, slots=True)
class FrameId:
    origin: int
    sequence: int


@dataclasses.dataclass(frozen=True, slots=True)
class CanFrame:
    can_id: int
    data: bytes
    kind: FrameKind = FrameKind.CLASSIC
    fd_flags: int = 0

    def __post_init__(self) -> None:
        max_len = CAN_MAX_DLEN if self.kind is FrameKind.CLASSIC else CANFD_MAX_DLEN
        if len(self.data) > max_len:
            raise ValueError(f"payload length {len(self.data)} exceeds {max_len}")
        if not 0 <= self.can_id <= 0xFFFFFFFF:
            raise ValueError("CAN ID/flag field must fit in uint32")
        if not 0 <= self.fd_flags <= 0xFF:
            raise ValueError("FD flags must fit in uint8")

    def to_socketcan(self) -> bytes:
        length = len(self.data)
        if self.kind is FrameKind.CLASSIC:
            return CAN_FRAME_STRUCT.pack(
                self.can_id,
                length,
                0,
                0,
                0,
                self.data.ljust(CAN_MAX_DLEN, b"\0"),
            )
        return CANFD_FRAME_STRUCT.pack(
            self.can_id,
            length,
            self.fd_flags,
            0,
            0,
            self.data.ljust(CANFD_MAX_DLEN, b"\0"),
        )

    @classmethod
    def from_socketcan(cls, raw: bytes) -> "CanFrame":
        if len(raw) == CAN_MTU:
            can_id, length, _pad, _res0, _len8_dlc, data = CAN_FRAME_STRUCT.unpack(raw)
            if length > CAN_MAX_DLEN:
                raise ValueError(f"invalid Classical CAN length: {length}")
            return cls(can_id=can_id, data=data[:length], kind=FrameKind.CLASSIC)
        if len(raw) == CANFD_MTU:
            can_id, length, fd_flags, _res0, _res1, data = CANFD_FRAME_STRUCT.unpack(raw)
            if length > CANFD_MAX_DLEN:
                raise ValueError(f"invalid CAN FD length: {length}")
            return cls(can_id=can_id, data=data[:length], kind=FrameKind.FD, fd_flags=fd_flags)
        raise ValueError(f"unexpected SocketCAN frame size: {len(raw)}")

    def to_network_payload(self, frame_id: FrameId) -> bytes:
        return FRAME_STRUCT.pack(
            frame_id.origin,
            frame_id.sequence,
            self.can_id,
            len(self.data),
            int(self.kind),
            self.fd_flags,
            0,
            self.data.ljust(CANFD_MAX_DLEN, b"\0"),
        )

    @classmethod
    def from_network_payload(cls, payload: bytes) -> tuple[FrameId, "CanFrame"]:
        if len(payload) != FRAME_STRUCT.size:
            raise ValueError(f"invalid CAN_FRAME payload size: {len(payload)}")
        origin, sequence, can_id, length, kind_raw, fd_flags, _reserved, data = FRAME_STRUCT.unpack(payload)
        try:
            kind = FrameKind(kind_raw)
        except ValueError as exc:
            raise ValueError(f"unknown frame kind: {kind_raw}") from exc
        max_len = CAN_MAX_DLEN if kind is FrameKind.CLASSIC else CANFD_MAX_DLEN
        if length > max_len:
            raise ValueError(f"invalid payload length {length} for {kind.name}")
        return FrameId(origin, sequence), cls(can_id, data[:length], kind, fd_flags)


@dataclasses.dataclass(slots=True)
class Stats:
    local_can_rx: int = 0
    remote_can_tx_queued: int = 0
    remote_can_tx_confirmed: int = 0
    remote_can_tx_failed: int = 0
    network_frames_rx: int = 0
    network_frames_tx: int = 0
    duplicates_rx: int = 0
    dropped_outbound: int = 0
    protocol_errors: int = 0


@dataclasses.dataclass(slots=True)
class QueueItem:
    packet_type: PacketType
    payload: bytes
    frame_id: FrameId | None = None


class OutboundBuffer:
    """Bounded packet queue with control-message priority."""

    def __init__(self, max_data_packets: int) -> None:
        self._control: collections.deque[QueueItem] = collections.deque()
        self._data: collections.deque[QueueItem] = collections.deque()
        self._max_data_packets = max_data_packets
        self._queued_frame_ids: set[FrameId] = set()
        self._event = asyncio.Event()

    def put_nowait(self, item: QueueItem, *, priority: bool = False) -> bool:
        if priority:
            self._control.append(item)
            self._event.set()
            return True
        if item.packet_type is PacketType.CAN_FRAME and item.frame_id is None:
            raise ValueError("CAN_FRAME queue items require frame_id")
        if item.frame_id is not None and item.frame_id in self._queued_frame_ids:
            return True
        if len(self._data) >= self._max_data_packets:
            return False
        self._data.append(item)
        if item.frame_id is not None:
            self._queued_frame_ids.add(item.frame_id)
        self._event.set()
        return True

    def putleft(self, item: QueueItem, *, priority: bool = False) -> None:
        if priority or item.packet_type is not PacketType.CAN_FRAME:
            self._control.appendleft(item)
        else:
            if item.frame_id is not None and item.frame_id in self._queued_frame_ids:
                return
            self._data.appendleft(item)
            if item.frame_id is not None:
                self._queued_frame_ids.add(item.frame_id)
        self._event.set()

    async def get(self) -> QueueItem:
        while True:
            if self._control:
                return self._control.popleft()
            if self._data:
                item = self._data.popleft()
                if item.frame_id is not None:
                    self._queued_frame_ids.discard(item.frame_id)
                return item
            self._event.clear()
            if self._control or self._data:
                self._event.set()
                continue
            await self._event.wait()

    def __len__(self) -> int:
        return len(self._control) + len(self._data)


class CanEndpoint:
    def __init__(
        self,
        interface: str,
        confirm_timeout: float,
        on_local_frame: Callable[[CanFrame], None],
        on_tx_result: Callable[[FrameId, TxStatus], None],
        on_error_frame: Callable[[CanFrame], None],
    ) -> None:
        self.interface = interface
        self.confirm_timeout = confirm_timeout
        self.on_local_frame = on_local_frame
        self.on_tx_result = on_tx_result
        self.on_error_frame = on_error_frame
        self.loop = asyncio.get_running_loop()
        self.socket = self._open_socket(interface)
        self._tx_queue: collections.deque[tuple[FrameId, bytes]] = collections.deque()
        self._pending_by_raw: dict[bytes, collections.deque[FrameId]] = {}
        self._pending_deadline: dict[FrameId, tuple[bytes, float]] = {}
        self._timeout_task: asyncio.Task[None] | None = None
        self._closed = False

    @staticmethod
    def _open_socket(interface: str) -> socket.socket:
        can_sock = socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW)
        can_sock.setblocking(False)
        can_sock.setsockopt(socket.SOL_CAN_RAW, socket.CAN_RAW_LOOPBACK, 1)
        can_sock.setsockopt(socket.SOL_CAN_RAW, socket.CAN_RAW_RECV_OWN_MSGS, 1)
        try:
            can_sock.setsockopt(socket.SOL_CAN_RAW, socket.CAN_RAW_FD_FRAMES, 1)
        except OSError as exc:
            LOG.warning("CAN FD socket option unavailable: %s", exc)
        if hasattr(socket, "CAN_RAW_ERR_FILTER"):
            can_sock.setsockopt(
                socket.SOL_CAN_RAW,
                socket.CAN_RAW_ERR_FILTER,
                struct.pack("=I", CAN_ERR_MASK),
            )
        try:
            can_sock.bind((interface,))
        except Exception:
            can_sock.close()
            raise
        return can_sock

    def start(self) -> None:
        self.loop.add_reader(self.socket.fileno(), self._on_readable)
        self._timeout_task = asyncio.create_task(self._timeout_loop(), name="can-confirm-timeouts")

    def queue_remote_frame(self, frame_id: FrameId, frame: CanFrame) -> None:
        self._tx_queue.append((frame_id, frame.to_socketcan()))
        self._flush_tx()

    def _flush_tx(self) -> None:
        if self._closed:
            return
        while self._tx_queue:
            frame_id, raw = self._tx_queue[0]
            try:
                sent = self.socket.send(raw)
            except BlockingIOError:
                self.loop.add_writer(self.socket.fileno(), self._on_writable)
                return
            except OSError as exc:
                self._tx_queue.popleft()
                LOG.error("CAN send failed for %s:%s: %s", frame_id.origin, frame_id.sequence, exc)
                self.on_tx_result(frame_id, TxStatus.SEND_ERROR)
                continue
            if sent != len(raw):
                self._tx_queue.popleft()
                LOG.error("short CAN write: %d of %d bytes", sent, len(raw))
                self.on_tx_result(frame_id, TxStatus.SEND_ERROR)
                continue
            self._tx_queue.popleft()
            self._pending_by_raw.setdefault(raw, collections.deque()).append(frame_id)
            self._pending_deadline[frame_id] = (raw, time.monotonic() + self.confirm_timeout)
        with contextlib.suppress(Exception):
            self.loop.remove_writer(self.socket.fileno())

    def _on_writable(self) -> None:
        self._flush_tx()

    def _on_readable(self) -> None:
        while True:
            try:
                raw, _ancdata, msg_flags, _address = self.socket.recvmsg(CANFD_MTU)
            except BlockingIOError:
                return
            except OSError as exc:
                if not self._closed:
                    LOG.error("CAN receive failed: %s", exc)
                return

            try:
                frame = CanFrame.from_socketcan(raw)
            except ValueError as exc:
                LOG.warning("discarding malformed SocketCAN frame: %s", exc)
                continue

            if msg_flags & socket.MSG_CONFIRM:
                self._handle_tx_confirmation(raw)
                continue

            if frame.can_id & CAN_ERR_FLAG:
                self.on_error_frame(frame)
                continue

            # Physical bus frames and successful transmissions from other local
            # SocketCAN applications are both forwarded. Frames sent by this
            # bridge are consumed above through MSG_CONFIRM.
            self.on_local_frame(frame)

    def _handle_tx_confirmation(self, raw: bytes) -> None:
        frame_ids = self._pending_by_raw.get(raw)
        if not frame_ids:
            LOG.debug("unmatched CAN transmission confirmation")
            return
        while frame_ids:
            frame_id = frame_ids.popleft()
            if frame_id in self._pending_deadline:
                self._pending_deadline.pop(frame_id, None)
                if not frame_ids:
                    self._pending_by_raw.pop(raw, None)
                self.on_tx_result(frame_id, TxStatus.CONFIRMED)
                return
        self._pending_by_raw.pop(raw, None)

    async def _timeout_loop(self) -> None:
        try:
            while True:
                await asyncio.sleep(min(0.25, max(0.05, self.confirm_timeout / 4)))
                now = time.monotonic()
                expired = [
                    frame_id
                    for frame_id, (_raw, deadline) in self._pending_deadline.items()
                    if deadline <= now
                ]
                for frame_id in expired:
                    self._pending_deadline.pop(frame_id, None)
                    self.on_tx_result(frame_id, TxStatus.CONFIRM_TIMEOUT)
        except asyncio.CancelledError:
            raise

    async def close(self) -> None:
        self._closed = True
        with contextlib.suppress(Exception):
            self.loop.remove_reader(self.socket.fileno())
        with contextlib.suppress(Exception):
            self.loop.remove_writer(self.socket.fileno())
        if self._timeout_task is not None:
            self._timeout_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._timeout_task
        self.socket.close()


class Bridge:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.boot_id = random.SystemRandom().getrandbits(64)
        self.sequence = 0
        self.stats = Stats()
        self.outbound = OutboundBuffer(args.queue)
        self.remote_state = RemoteState.ASSUMED_UP
        self._session_lock = asyncio.Lock()
        self._active_writer: asyncio.StreamWriter | None = None
        self._stop_event = asyncio.Event()
        self._seen: collections.OrderedDict[FrameId, TxStatus | None] = collections.OrderedDict()
        self._seen_limit = args.dedupe_cache
        self._awaiting_remote: collections.OrderedDict[FrameId, QueueItem] = collections.OrderedDict()
        self.can: CanEndpoint | None = None
        self._stats_task: asyncio.Task[None] | None = None

    async def run(self) -> None:
        self.can = CanEndpoint(
            self.args.interface,
            self.args.tx_confirm_timeout,
            self._on_local_can_frame,
            self._on_can_tx_result,
            self._on_can_error_frame,
        )
        self.can.start()
        self._stats_task = asyncio.create_task(self._stats_loop(), name="stats")

        peer_ip = resolve_ipv4(self.args.peer)
        local_ip = discover_local_ipv4(peer_ip, self.args.port)
        role = choose_role(self.args.role, local_ip, peer_ip)
        LOG.info(
            "started: CAN=%s local=%s peer=%s:%d role=%s mode=optimistic boot=%016x",
            self.args.interface,
            local_ip,
            peer_ip,
            self.args.port,
            role,
            self.boot_id,
        )

        try:
            if role == "server":
                await self._run_server(peer_ip)
            else:
                await self._run_client(peer_ip)
        finally:
            if self._stats_task is not None:
                self._stats_task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await self._stats_task
            await self.can.close()

    async def stop(self) -> None:
        self._stop_event.set()
        if self._active_writer is not None:
            self._active_writer.close()

    async def _run_server(self, peer_ip: str) -> None:
        server = await asyncio.start_server(
            lambda r, w: asyncio.create_task(self._accept_connection(r, w, peer_ip)),
            host=self.args.bind,
            port=self.args.port,
            family=socket.AF_INET,
            reuse_address=True,
        )
        addresses = ", ".join(str(sock.getsockname()) for sock in server.sockets or [])
        LOG.info("listening on %s", addresses)
        async with server:
            await self._stop_event.wait()

    async def _accept_connection(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        expected_peer_ip: str,
    ) -> None:
        peername = writer.get_extra_info("peername")
        actual_ip = peername[0] if peername else None
        if actual_ip != expected_peer_ip and not self.args.allow_any_peer:
            LOG.warning("rejecting unexpected peer %s; expected %s", actual_ip, expected_peer_ip)
            writer.close()
            await writer.wait_closed()
            return
        if self._session_lock.locked():
            LOG.warning("rejecting additional TCP connection from %s", actual_ip)
            writer.close()
            await writer.wait_closed()
            return
        await self._handle_session(reader, writer)

    async def _run_client(self, peer_ip: str) -> None:
        delay = 0.25
        while not self._stop_event.is_set():
            try:
                reader, writer = await asyncio.open_connection(peer_ip, self.args.port)
                set_tcp_options(writer)
                await self._handle_session(reader, writer)
                delay = 0.25
            except asyncio.CancelledError:
                raise
            except (ConnectionError, OSError, asyncio.IncompleteReadError) as exc:
                if not self._stop_event.is_set():
                    LOG.warning("TCP connection unavailable: %s; reconnecting", exc)
            try:
                await asyncio.wait_for(self._stop_event.wait(), timeout=delay)
            except asyncio.TimeoutError:
                pass
            delay = min(delay * 2, self.args.reconnect_max)

    async def _handle_session(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        async with self._session_lock:
            self._active_writer = writer
            set_tcp_options(writer)
            peername = writer.get_extra_info("peername")
            LOG.info("TCP connected to %s", peername)
            self.remote_state = RemoteState.ASSUMED_UP

            try:
                await write_packet(writer, PacketType.HELLO, HELLO_STRUCT.pack(self.boot_id))
                packet_type, payload = await asyncio.wait_for(
                    read_packet(reader), timeout=self.args.handshake_timeout
                )
                if packet_type is not PacketType.HELLO or len(payload) != HELLO_STRUCT.size:
                    raise ProtocolError("expected HELLO as first packet")
                (peer_boot_id,) = HELLO_STRUCT.unpack(payload)
                LOG.info("peer handshake complete: boot=%016x", peer_boot_id)
                self._requeue_unconfirmed_frames()

                reader_task = asyncio.create_task(self._network_reader(reader), name="tcp-reader")
                writer_task = asyncio.create_task(self._network_writer(writer), name="tcp-writer")
                ping_task = asyncio.create_task(self._ping_loop(), name="tcp-ping")
                done, pending = await asyncio.wait(
                    {reader_task, writer_task, ping_task},
                    return_when=asyncio.FIRST_EXCEPTION,
                )
                for task in pending:
                    task.cancel()
                for task in pending:
                    with contextlib.suppress(asyncio.CancelledError):
                        await task
                for task in done:
                    exc = task.exception()
                    if exc is not None:
                        raise exc
            except asyncio.CancelledError:
                raise
            except (ConnectionError, OSError, asyncio.IncompleteReadError, ProtocolError, asyncio.TimeoutError) as exc:
                if not self._stop_event.is_set():
                    LOG.warning("TCP session ended: %s", exc)
            finally:
                self.remote_state = RemoteState.DOWN
                self._active_writer = None
                writer.close()
                with contextlib.suppress(Exception):
                    await writer.wait_closed()
                LOG.info("TCP disconnected")

    async def _network_writer(self, writer: asyncio.StreamWriter) -> None:
        while True:
            item = await self.outbound.get()
            sent = False
            try:
                await write_packet(writer, item.packet_type, item.payload)
                sent = True
                if item.packet_type is PacketType.CAN_FRAME:
                    self.stats.network_frames_tx += 1
            finally:
                if not sent:
                    self.outbound.putleft(
                        item,
                        priority=item.packet_type is not PacketType.CAN_FRAME,
                    )

    async def _network_reader(self, reader: asyncio.StreamReader) -> None:
        while True:
            packet_type, payload = await read_packet(reader)
            if packet_type is PacketType.CAN_FRAME:
                await self._handle_network_can_frame(payload)
            elif packet_type is PacketType.TX_RESULT:
                self._handle_network_tx_result(payload)
            elif packet_type is PacketType.PING:
                if len(payload) != PING_STRUCT.size:
                    raise ProtocolError("invalid PING payload")
                self.outbound.put_nowait(
                    QueueItem(PacketType.PONG, payload), priority=True
                )
            elif packet_type is PacketType.PONG:
                if len(payload) != PING_STRUCT.size:
                    raise ProtocolError("invalid PONG payload")
            elif packet_type is PacketType.HELLO:
                raise ProtocolError("unexpected HELLO after handshake")
            else:
                raise ProtocolError(f"unsupported packet type {packet_type}")

    async def _handle_network_can_frame(self, payload: bytes) -> None:
        try:
            frame_id, frame = CanFrame.from_network_payload(payload)
        except ValueError as exc:
            self.stats.protocol_errors += 1
            raise ProtocolError(str(exc)) from exc

        self.stats.network_frames_rx += 1
        previous = self._seen.get(frame_id, "missing")
        if previous != "missing":
            self.stats.duplicates_rx += 1
            self._seen.move_to_end(frame_id)
            if isinstance(previous, TxStatus):
                self._queue_tx_result(frame_id, previous)
            return

        self._seen[frame_id] = None
        self._trim_seen_cache()
        assert self.can is not None
        self.can.queue_remote_frame(frame_id, frame)
        self.stats.remote_can_tx_queued += 1

    def _handle_network_tx_result(self, payload: bytes) -> None:
        if len(payload) != TX_RESULT_STRUCT.size:
            raise ProtocolError("invalid TX_RESULT payload")
        origin, sequence, status_raw = TX_RESULT_STRUCT.unpack(payload)
        try:
            status = TxStatus(status_raw)
        except ValueError as exc:
            raise ProtocolError(f"unknown TX_RESULT status {status_raw}") from exc
        frame_id = FrameId(origin, sequence)
        self._awaiting_remote.pop(frame_id, None)
        if status is TxStatus.CONFIRMED:
            if self.remote_state is not RemoteState.CONFIRMED_UP:
                LOG.info("remote CAN segment confirmed reachable")
            self.remote_state = RemoteState.CONFIRMED_UP
            LOG.debug("remote TX confirmed for %016x:%d", origin, sequence)
        else:
            self.remote_state = RemoteState.DOWN
            LOG.warning(
                "remote CAN transmission not confirmed for %016x:%d: %s",
                origin,
                sequence,
                status.name,
            )

    async def _ping_loop(self) -> None:
        while True:
            await asyncio.sleep(self.args.keepalive)
            timestamp_ns = time.monotonic_ns() & 0xFFFFFFFFFFFFFFFF
            self.outbound.put_nowait(
                QueueItem(PacketType.PING, PING_STRUCT.pack(timestamp_ns)), priority=True
            )

    def _on_local_can_frame(self, frame: CanFrame) -> None:
        self.stats.local_can_rx += 1
        self.sequence = (self.sequence + 1) & 0xFFFFFFFFFFFFFFFF
        frame_id = FrameId(self.boot_id, self.sequence)
        item = QueueItem(
            PacketType.CAN_FRAME,
            frame.to_network_payload(frame_id),
            frame_id=frame_id,
        )
        if len(self._awaiting_remote) >= self.args.queue or not self.outbound.put_nowait(item):
            self.stats.dropped_outbound += 1
            LOG.error(
                "outbound/in-flight limit reached; dropping CAN frame id=0x%08x len=%d",
                frame.can_id,
                len(frame.data),
            )
            return
        self._awaiting_remote[frame_id] = item

    def _requeue_unconfirmed_frames(self) -> None:
        requeued = 0
        for item in self._awaiting_remote.values():
            if self.outbound.put_nowait(item):
                requeued += 1
        if requeued:
            LOG.info("queued %d unconfirmed frame(s) after TCP reconnect", requeued)

    def _on_can_tx_result(self, frame_id: FrameId, status: TxStatus) -> None:
        if status is TxStatus.CONFIRMED:
            self.stats.remote_can_tx_confirmed += 1
        else:
            self.stats.remote_can_tx_failed += 1
        if frame_id in self._seen:
            self._seen[frame_id] = status
            self._seen.move_to_end(frame_id)
        self._queue_tx_result(frame_id, status)

    def _queue_tx_result(self, frame_id: FrameId, status: TxStatus) -> None:
        payload = TX_RESULT_STRUCT.pack(frame_id.origin, frame_id.sequence, int(status))
        self.outbound.put_nowait(QueueItem(PacketType.TX_RESULT, payload), priority=True)

    def _on_can_error_frame(self, frame: CanFrame) -> None:
        error_class = frame.can_id & CAN_ERR_MASK
        if error_class & CAN_ERR_BUSOFF:
            LOG.error("local CAN controller entered BUS-OFF")
        elif error_class & CAN_ERR_RESTARTED:
            LOG.info("local CAN controller restarted")
        elif error_class & CAN_ERR_ACK:
            LOG.warning("local CAN ACK error")
        else:
            LOG.debug("local CAN error frame: class=0x%08x data=%s", error_class, frame.data.hex())

    def _trim_seen_cache(self) -> None:
        while len(self._seen) > self._seen_limit:
            frame_id, status = next(iter(self._seen.items()))
            # Prefer retaining still-pending entries. If the oldest is pending,
            # scan for the oldest completed one instead.
            if status is None:
                completed = next(
                    ((fid, st) for fid, st in self._seen.items() if st is not None),
                    None,
                )
                if completed is None:
                    break
                frame_id = completed[0]
            self._seen.pop(frame_id, None)

    async def _stats_loop(self) -> None:
        while True:
            await asyncio.sleep(self.args.stats_interval)
            LOG.info(
                "state=%s tcpq=%d pending=%d can-rx=%d net-tx=%d net-rx=%d "
                "remote-confirmed=%d remote-failed=%d duplicates=%d dropped=%d",
                self.remote_state.value,
                len(self.outbound),
                len(self._awaiting_remote),
                self.stats.local_can_rx,
                self.stats.network_frames_tx,
                self.stats.network_frames_rx,
                self.stats.remote_can_tx_confirmed,
                self.stats.remote_can_tx_failed,
                self.stats.duplicates_rx,
                self.stats.dropped_outbound,
            )


class ProtocolError(Exception):
    pass


def encode_packet(packet_type: PacketType, payload: bytes) -> bytes:
    if len(payload) > MAX_PACKET_PAYLOAD:
        raise ValueError("packet payload too large")
    return HEADER_STRUCT.pack(MAGIC, PROTOCOL_VERSION, int(packet_type), 0, len(payload)) + payload


async def write_packet(
    writer: asyncio.StreamWriter, packet_type: PacketType, payload: bytes
) -> None:
    writer.write(encode_packet(packet_type, payload))
    await writer.drain()


async def read_packet(reader: asyncio.StreamReader) -> tuple[PacketType, bytes]:
    header = await reader.readexactly(HEADER_STRUCT.size)
    magic, version, packet_type_raw, _flags, payload_len = HEADER_STRUCT.unpack(header)
    if magic != MAGIC:
        raise ProtocolError("invalid protocol magic")
    if version != PROTOCOL_VERSION:
        raise ProtocolError(f"unsupported protocol version {version}")
    if payload_len > MAX_PACKET_PAYLOAD:
        raise ProtocolError(f"oversized packet payload {payload_len}")
    try:
        packet_type = PacketType(packet_type_raw)
    except ValueError as exc:
        raise ProtocolError(f"unknown packet type {packet_type_raw}") from exc
    payload = await reader.readexactly(payload_len)
    return packet_type, payload


def resolve_ipv4(peer: str) -> str:
    infos = socket.getaddrinfo(peer, None, socket.AF_INET, socket.SOCK_STREAM)
    if not infos:
        raise OSError(f"could not resolve peer {peer!r}")
    return infos[0][4][0]


def discover_local_ipv4(peer_ip: str, port: int) -> str:
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect((peer_ip, port))
        return probe.getsockname()[0]
    finally:
        probe.close()


def choose_role(requested: str, local_ip: str, peer_ip: str) -> str:
    if requested in {"server", "client"}:
        return requested
    local = ipaddress.ip_address(local_ip)
    peer = ipaddress.ip_address(peer_ip)
    if local == peer:
        raise ValueError("auto role cannot be used when local and peer IP are equal; use --role")
    return "server" if local < peer else "client"


def set_tcp_options(writer: asyncio.StreamWriter) -> None:
    sock = writer.get_extra_info("socket")
    if sock is None:
        return
    with contextlib.suppress(OSError):
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    with contextlib.suppress(OSError):
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    if hasattr(socket, "TCP_KEEPIDLE"):
        with contextlib.suppress(OSError):
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, 10)
    if hasattr(socket, "TCP_KEEPINTVL"):
        with contextlib.suppress(OSError):
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPINTVL, 3)
    if hasattr(socket, "TCP_KEEPCNT"):
        with contextlib.suppress(OSError):
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPCNT, 3)


def acquire_instance_lock(interface: str, port: int) -> socket.socket:
    """Prevent multiple bridge processes from using one CAN interface/port.

    A Linux abstract UNIX socket is used as a process-lifetime lock. It has no
    filesystem permissions or stale lock file and disappears automatically when
    the process exits.
    """
    safe_interface = "".join(ch if ch.isalnum() or ch in "_.-" else "_" for ch in interface)
    lock_name = f"\0can-tcp-bridge:{safe_interface}:{port}"
    lock_sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    try:
        lock_sock.bind(lock_name)
    except OSError as exc:
        lock_sock.close()
        if exc.errno in {98, 48}:  # EADDRINUSE on Linux/macOS
            raise RuntimeError(
                f"another can-tcp-bridge already uses interface {interface!r} "
                f"and port {port}; stop the old process first"
            ) from exc
        raise
    return lock_sock


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Bidirectional CAN/CAN-FD bridge over one persistent TCP connection"
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {APPLICATION_VERSION}")
    parser.add_argument("peer", help="IPv4 address or hostname of the opposite gateway")
    parser.add_argument("interface", help="preconfigured SocketCAN interface, e.g. can0")
    parser.add_argument("--port", type=int, default=29536, help="TCP port (default: 29536)")
    parser.add_argument(
        "--role",
        choices=("auto", "server", "client"),
        default="auto",
        help="TCP role; auto compares local and peer IPv4 addresses",
    )
    parser.add_argument("--bind", default="0.0.0.0", help="server bind address")
    parser.add_argument(
        "--allow-any-peer",
        action="store_true",
        help="server accepts a connection from an IP other than the configured peer",
    )
    parser.add_argument("--queue", type=int, default=4096, help="maximum queued CAN frames")
    parser.add_argument(
        "--dedupe-cache",
        type=int,
        default=65536,
        help="remembered network frame IDs for reconnect deduplication",
    )
    parser.add_argument(
        "--tx-confirm-timeout",
        type=float,
        default=5.0,
        help="seconds to wait for SocketCAN MSG_CONFIRM",
    )
    parser.add_argument(
        "--handshake-timeout", type=float, default=5.0, help="TCP HELLO timeout"
    )
    parser.add_argument(
        "--keepalive", type=float, default=3.0, help="application PING interval"
    )
    parser.add_argument(
        "--reconnect-max", type=float, default=5.0, help="maximum reconnect delay"
    )
    parser.add_argument(
        "--stats-interval", type=float, default=10.0, help="statistics log interval"
    )
    parser.add_argument(
        "--log-level",
        choices=("DEBUG", "INFO", "WARNING", "ERROR"),
        default="INFO",
    )
    return parser


def validate_args(args: argparse.Namespace) -> None:
    if not 1 <= args.port <= 65535:
        raise ValueError("port must be between 1 and 65535")
    for name in (
        "queue",
        "dedupe_cache",
    ):
        if getattr(args, name) <= 0:
            raise ValueError(f"{name.replace('_', '-')} must be positive")
    for name in (
        "tx_confirm_timeout",
        "handshake_timeout",
        "keepalive",
        "reconnect_max",
        "stats_interval",
    ):
        if getattr(args, name) <= 0:
            raise ValueError(f"{name.replace('_', '-')} must be positive")


async def async_main(args: argparse.Namespace) -> int:
    bridge = Bridge(args)
    loop = asyncio.get_running_loop()

    # Leave SIGINT to asyncio.run(), which cancels the main task reliably when
    # Ctrl-C is pressed. Handle SIGTERM explicitly for systemd/service use.
    with contextlib.suppress(NotImplementedError):
        loop.add_signal_handler(signal.SIGTERM, lambda: asyncio.create_task(bridge.stop()))

    await bridge.run()
    return 0


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        validate_args(args)
    except ValueError as exc:
        parser.error(str(exc))

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    try:
        instance_lock = acquire_instance_lock(args.interface, args.port)
    except (OSError, RuntimeError) as exc:
        LOG.error("startup failed: %s", exc)
        return 1

    try:
        return asyncio.run(async_main(args))
    except KeyboardInterrupt:
        LOG.info("stopped by Ctrl-C")
        return 130
    except (OSError, ValueError, RuntimeError) as exc:
        LOG.error("startup failed: %s", exc)
        return 1
    finally:
        instance_lock.close()


if __name__ == "__main__":
    raise SystemExit(main())
