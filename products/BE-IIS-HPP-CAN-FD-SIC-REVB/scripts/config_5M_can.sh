#!/bin/bash

IFACE="${1:-beiis-can0}"

echo "[INFO] Configure CAN-FD 5 MBit on ${IFACE}"

sudo ip link set "${IFACE}" down

sudo ip link set "${IFACE}" txqueuelen 1000

sudo ip link set "${IFACE}" up type can \
    bitrate 1000000 \
    sample-point 0.8 \
    dbitrate 5000000 \
    dsample-point 0.75 \
    fd on \
    berr-reporting on

echo
ip -details link show "${IFACE}"

echo
echo "[INFO] CAN-FD 5 MBit ready"
