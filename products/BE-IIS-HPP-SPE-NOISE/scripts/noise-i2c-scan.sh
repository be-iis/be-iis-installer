#!/usr/bin/env bash
set -euo pipefail

BUS="${1:-1}"
ADDRESS="${2:-0x2a}"

echo "Probing BE-IIS HPP SPE NOISE on I2C bus ${BUS}, address ${ADDRESS}"
sudo i2cdetect -y "${BUS}" "${ADDRESS}" "${ADDRESS}"
