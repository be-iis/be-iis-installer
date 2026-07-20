#!/usr/bin/env python3
import asyncio
import unittest

from can_tcp_bridge import (
    CanFrame,
    FrameId,
    FrameKind,
    OutboundBuffer,
    PacketType,
    QueueItem,
    TxStatus,
    TX_RESULT_STRUCT,
    choose_role,
    encode_packet,
    read_packet,
)


class CodecTests(unittest.TestCase):
    def test_classic_socketcan_roundtrip(self):
        frame = CanFrame(0x123, bytes.fromhex("1122334455667788"))
        self.assertEqual(CanFrame.from_socketcan(frame.to_socketcan()), frame)

    def test_fd_socketcan_roundtrip(self):
        frame = CanFrame(0x18DAF110 | 0x80000000, bytes(range(64)), FrameKind.FD, 0x01)
        self.assertEqual(CanFrame.from_socketcan(frame.to_socketcan()), frame)

    def test_network_roundtrip(self):
        frame_id = FrameId(0x1122334455667788, 42)
        frame = CanFrame(0x321, b"abc")
        decoded_id, decoded_frame = CanFrame.from_network_payload(
            frame.to_network_payload(frame_id)
        )
        self.assertEqual(decoded_id, frame_id)
        self.assertEqual(decoded_frame, frame)

    def test_packet_header(self):
        payload = TX_RESULT_STRUCT.pack(1, 2, int(TxStatus.CONFIRMED))
        packet = encode_packet(PacketType.TX_RESULT, payload)
        self.assertGreater(len(packet), len(payload))

    def test_auto_role(self):
        self.assertEqual(choose_role("auto", "192.168.1.10", "192.168.1.20"), "server")
        self.assertEqual(choose_role("auto", "192.168.1.20", "192.168.1.10"), "client")


class AsyncTests(unittest.IsolatedAsyncioTestCase):
    async def test_packet_stream_roundtrip(self):
        reader = asyncio.StreamReader()
        payload = b"hello"
        reader.feed_data(encode_packet(PacketType.PING, payload))
        reader.feed_eof()
        packet_type, decoded = await read_packet(reader)
        self.assertEqual(packet_type, PacketType.PING)
        self.assertEqual(decoded, payload)

    async def test_outbound_frame_deduplication(self):
        queue = OutboundBuffer(4)
        frame_id = FrameId(1, 2)
        item = QueueItem(PacketType.CAN_FRAME, b"frame", frame_id)
        self.assertTrue(queue.put_nowait(item))
        self.assertTrue(queue.put_nowait(item))
        self.assertEqual(len(queue), 1)
        self.assertEqual(await queue.get(), item)
        self.assertEqual(len(queue), 0)


if __name__ == "__main__":
    unittest.main()
