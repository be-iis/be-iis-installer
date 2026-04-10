#!/usr/bin/env bash

set -e

REQUIRED_VERSION="6.7"
ETHTOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../tools/ethtool"
BUILD_NEEDED=0

version_ge() {
    [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

echo "[SETUP] Checking ethtool"

if command -v ethtool >/dev/null 2>&1; then
    CURRENT_VERSION="$(ethtool --version | awk '{print $3}')"
    echo "[INFO] Found ethtool version $CURRENT_VERSION"

    if version_ge "$CURRENT_VERSION" "$REQUIRED_VERSION"; then
        echo "[INFO] ethtool version is sufficient"
    else
        echo "[WARN] ethtool version too old ($CURRENT_VERSION < $REQUIRED_VERSION)"
        BUILD_NEEDED=1
    fi
else
    echo "[WARN] ethtool not found"
    BUILD_NEEDED=1
fi

if [ "$BUILD_NEEDED" -eq 1 ]; then
    echo "[SETUP] Building ethtool from source"

    echo "[SETUP] Installing build dependencies"
    sudo apt update
    sudo apt install -y \
        build-essential \
        autoconf \
        automake \
        libtool \
        pkg-config

    pushd "$ETHTOOL_DIR" > /dev/null

    ./autogen.sh
    ./configure
    make
    sudo make install

    popd > /dev/null

    echo "[SETUP] ethtool installed successfully"
fi


if ! command -v iperf3 >/dev/null 2>&1; then
    echo "[SETUP] Installing iperf3"
    sudo apt update
    sudo apt install -y iperf3
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PEER_IP="100.100.100.2"
TEST_TIME=10

echo "[TEST] Configure static IP on beiis-t1s0"
"$SCRIPT_DIR/../../../scripts/net/set_static_ip.sh" beiis-t1s0 100.100.100.1

echo "[TEST] Configure PLCA Node-ID 0"
sudo ethtool --set-plca-cfg beiis-t1s0 enable on node-id 0 node-cnt 2
ethtool --get-plca-cfg beiis-t1s0


echo "[TEST] Ping peer ($PEER_IP)"
ping -c 10 -W 1 "$PEER_IP"

echo
echo "[TEST] UDP throughput and loss test"
echo "----------------------------------------"

for RATE in 1 2 3 4 5 6 7 8 9 10; do
    echo
    echo "[TEST] UDP rate: ${RATE} Mbit/s"
    iperf3 -c "$PEER_IP" -u -b "${RATE}M" -t "$TEST_TIME"
done

echo
echo "[TEST] SUCCESS"