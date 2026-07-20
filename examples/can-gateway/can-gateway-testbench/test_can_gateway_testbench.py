import tempfile
import unittest
from pathlib import Path

import can_gateway_testbench as tb


class PayloadTests(unittest.TestCase):
    def test_classic_payload_roundtrip(self):
        data = tb.build_payload(0x1234, 42, 8)
        self.assertEqual(len(data), 8)
        self.assertEqual(tb.parse_payload(data), (0x1234, 42))

    def test_fd_payload_roundtrip(self):
        data = tb.build_payload(0xABCD, 0x12345678, 64)
        self.assertEqual(len(data), 64)
        self.assertEqual(tb.parse_payload(data, 64), (0xABCD, 0x12345678))

    def test_corruption_is_detected(self):
        data = bytearray(tb.build_payload(1, 2, 16))
        data[-1] ^= 0x01
        with self.assertRaises(ValueError):
            tb.parse_payload(bytes(data))


class FrameTests(unittest.TestCase):
    def test_classic_frame_pack(self):
        frame = tb.CanFrame(0x123, b"12345678")
        decoded = tb.CanFrame.unpack(frame.pack())
        self.assertEqual(decoded, frame)

    def test_fd_frame_pack(self):
        frame = tb.CanFrame(0x321, bytes(range(64)), is_fd=True, brs=True)
        decoded = tb.CanFrame.unpack(frame.pack())
        self.assertEqual(decoded, frame)


class RecorderTests(unittest.TestCase):
    def test_duplicate_reorder_and_missing(self):
        recorder = tb.SequenceRecorder(7, 0x610, 5, 8)
        now = 1_000_000_000
        for index, sequence in enumerate([0, 2, 1, 2, 4]):
            frame = tb.CanFrame(0x610, tb.build_payload(7, sequence, 8))
            recorder.accept(frame, now + index * 1_000_000)
        report = recorder.report("test")
        self.assertEqual(report["received_unique"], 4)
        self.assertEqual(report["missing"], 1)
        self.assertEqual(report["duplicates"], 1)
        self.assertEqual(report["out_of_order"], 1)

    def test_payload_error_not_counted_as_unique(self):
        recorder = tb.SequenceRecorder(7, 0x610, 1, 8)
        bad = bytearray(tb.build_payload(7, 0, 8))
        bad[0] ^= 0xFF
        recorder.accept(tb.CanFrame(0x610, bytes(bad)), 1)
        report = recorder.report("test")
        self.assertEqual(report["payload_errors"], 1)
        self.assertEqual(report["received_unique"], 0)
        self.assertEqual(report["missing"], 1)


class StatisticsTests(unittest.TestCase):
    def test_percentile(self):
        values = [1.0, 2.0, 3.0, 4.0]
        self.assertEqual(tb.percentile(values, 0.0), 1.0)
        self.assertEqual(tb.percentile(values, 1.0), 4.0)
        self.assertEqual(tb.percentile(values, 0.5), 2.5)

    def test_html_report(self):
        metadata = {
            "created_local": "now",
            "master_hostname": "pi1",
            "slave_address": "pi4",
            "master_can_interface": "can0",
            "slave_can_interface": "can0",
            "session": 1,
            "configuration": {
                "base_id": 0x600,
                "can_fd": False,
                "brs": False,
                "payload_length": 8,
            },
        }
        result = {
            "test": "ping_round_trip",
            "expected": 1,
            "received_unique": 1,
            "loss_percent": 0.0,
            "duplicates": 0,
            "out_of_order": 0,
            "payload_errors": 0,
            "receive_fps": 1.0,
            "rtt_mean_ms": 1.0,
            "rtt_p50_ms": 1.0,
            "rtt_p95_ms": 1.0,
            "rtt_max_ms": 1.0,
        }
        output = tb.build_html_report(metadata, [result], [{"rtt_ms": 1.0}])
        self.assertIn("CAN Gateway Testbench", output)
        self.assertIn("1.000 ms", output)


class _FakeCanSocket:
    endpoints = {}

    def __init__(self, interface, accepted_ids):
        import asyncio

        self.interface = interface
        self.accepted_ids = set(accepted_ids)
        self.queue = asyncio.Queue()
        self.fd_enabled = True
        self.closed = False
        self.__class__.endpoints[interface] = self

    async def recv(self):
        return await self.queue.get()

    async def send(self, frame):
        peer_name = "slave0" if self.interface == "master0" else "master0"
        peer = self.__class__.endpoints.get(peer_name)
        if peer is None or peer.closed:
            raise OSError("fake CAN peer unavailable")
        if frame.can_id in peer.accepted_ids:
            await peer.queue.put(frame)

    def close(self):
        self.closed = True


class FullSuiteIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def test_complete_suite_with_fake_can_link(self):
        import argparse
        import asyncio
        import json
        import socket
        from unittest.mock import patch

        _FakeCanSocket.endpoints = {}
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]

        slave_args = argparse.Namespace(
            role="slave",
            can="slave0",
            base_id=0x600,
            control_port=port,
            control_bind="127.0.0.1",
            verbose=False,
        )

        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "results"
            master_args = argparse.Namespace(
                role="master",
                can="master0",
                base_id=0x600,
                control_port=port,
                slave="127.0.0.1",
                count=20,
                rate=2000.0,
                ping_count=20,
                ping_rate=1000.0,
                settle=0.03,
                bidi_lead=0.001,
                fd=False,
                brs=False,
                payload_length=8,
                output=str(output),
                max_loss_percent=0.0,
                max_duplicates=0,
                max_out_of_order=0,
                max_payload_errors=0,
                max_p95_rtt_ms=None,
                no_fail_exit=False,
                verbose=False,
            )

            with patch.object(tb, "CanSocket", _FakeCanSocket):
                slave_app = tb.SlaveApp(slave_args)
                slave_task = asyncio.create_task(slave_app.run())
                await asyncio.sleep(0.03)
                master_app = tb.MasterApp(master_args)
                result_dir, passed = await master_app.run()
                self.assertTrue(passed)
                self.assertEqual(result_dir, output)
                summary = json.loads((output / "summary.json").read_text())
                self.assertTrue(summary["overall_passed"])
                self.assertEqual(len(summary["tests"]), 5)
                self.assertTrue((output / "report.html").exists())
                slave_task.cancel()
                await asyncio.gather(slave_task, return_exceptions=True)


if __name__ == "__main__":
    unittest.main()
