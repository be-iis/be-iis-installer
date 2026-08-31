#!/usr/bin/env python3
"""Send Goethe's Zauberlehrling through a SocketCAN gateway as readable ASCII."""

import argparse
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("interface", nargs="?", default="can0")
parser.add_argument("--can-id", default="700")
parser.add_argument("--delay-ms", type=float, default=5.0)
args = parser.parse_args()

data = Path(__file__).with_name("zauberlehrling.txt").read_bytes()
for offset in range(0, len(data), 8):
    chunk = data[offset : offset + 8]
    subprocess.run(
        ["cansend", args.interface, f"{args.can_id}#{chunk.hex().upper()}"],
        check=True,
    )
    time.sleep(args.delay_ms / 1000)
print(f"Sent {len(data)} ASCII bytes in {(len(data) + 7) // 8} CAN frames.")
