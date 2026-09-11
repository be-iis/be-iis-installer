#!/usr/bin/env bash
set -euo pipefail

BUS="${1:-1}"
ADDRESS="${2:-0x2a}"

echo -n "DEVICE_ID: "
sudo i2ctransfer -f -y "${BUS}" w1@"${ADDRESS}" 0x00 r1
echo -n "VERSION:   "
sudo i2ctransfer -f -y "${BUS}" w1@"${ADDRESS}" 0x01 r1
echo -n "STATUS:    "
sudo i2ctransfer -f -y "${BUS}" w1@"${ADDRESS}" 0x08 r1
