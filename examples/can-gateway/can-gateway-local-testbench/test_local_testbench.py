import argparse
import importlib.util
import pathlib
import sys
import unittest

MODULE_PATH = pathlib.Path(__file__).with_name("can_gateway_local_testbench.py")
spec = importlib.util.spec_from_file_location("local_tb", MODULE_PATH)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


class LocalTestbenchTests(unittest.TestCase):
    def test_classic_payload_roundtrip(self):
        payload = mod.build_payload(0x1234, 99, 8)
        self.assertEqual(mod.parse_payload(payload), (0x1234, 99))

    def test_fd_frame_roundtrip(self):
        original = mod.CanFrame(0x620, bytes(range(64)), is_fd=True, brs=True)
        decoded = mod.CanFrame.unpack(original.pack())
        self.assertEqual(decoded, original)

    def test_new_run_cli(self):
        parser = mod.build_argument_parser()
        args = parser.parse_args(["run", "--peer", "10.10.10.3"])
        self.assertEqual(args.role_kind, "master")
        self.assertEqual(args.slave, "10.10.10.3")

    def test_new_responder_cli(self):
        parser = mod.build_argument_parser()
        args = parser.parse_args(["responder"])
        self.assertEqual(args.role_kind, "slave")

    def test_legacy_cli_aliases(self):
        parser = mod.build_argument_parser()
        master = parser.parse_args(["master", "--slave", "10.10.10.3"])
        slave = parser.parse_args(["slave"])
        self.assertEqual(master.role_kind, "master")
        self.assertEqual(slave.role_kind, "slave")


if __name__ == "__main__":
    unittest.main()
