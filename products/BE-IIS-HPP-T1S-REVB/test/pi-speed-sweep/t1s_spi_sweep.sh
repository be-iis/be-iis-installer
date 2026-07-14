#!/usr/bin/env bash
#
# Measure 10BASE-T1S UDP throughput at the currently active SPI frequency,
# append the result to a CSV file, reduce spi-max-frequency by 1 MHz,
# rebuild/install the Raspberry Pi overlay, and request a reboot.
#
# Run this script on the RECEIVER Raspberry Pi.
# The sender is controlled over SSH, preferably via Wi-Fi or normal Ethernet.
#
# One-time setup example:
#   sudo apt install iperf3 device-tree-compiler build-essential linux-headers-rpi-v8
#   ssh-copy-id philipp@192.168.178.52
#
# Configure either the variables below or export them before running.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SENDER_SSH=""
T1S_IFACE="beiis-t1s0"
OVERLAY_NAME="BE-IIS-HPP-T1S-I"

###############################################################################
# Configuration
###############################################################################

# Path to the local be-iis-installer clone. The script first tries the Git
# repository containing itself, then ~/Documents/be-iis-installer.
if [[ -z "${REPO_ROOT:-}" ]]; then
    if command -v git >/dev/null 2>&1 && \
       AUTO_REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
        REPO_ROOT="$AUTO_REPO_ROOT"
    elif [[ -d "$HOME/Documents/be-iis-installer" ]]; then
        REPO_ROOT="$HOME/Documents/be-iis-installer"
    else
        REPO_ROOT="$HOME/be-iis-installer"
    fi
fi

# Overlay used by the receiver HAT: I, II, or III.
OVERLAY_NAME="${OVERLAY_NAME:-BE-IIS-HPP-T1S-I}"

# SSH management address of the SENDER Pi.
# Prefer Wi-Fi / normal Ethernet so SSH remains available if T1S stops working.
# Example: SENDER_SSH=philipp@192.168.178.52
SENDER_SSH="${SENDER_SSH:-}"

# T1S network interface name on both Raspberry Pis.
T1S_IFACE="${T1S_IFACE:-eth1}"

# iperf3 settings.
UDP_RATE="${UDP_RATE:-10M}"
TEST_SECONDS="${TEST_SECONDS:-20}"
OMIT_SECONDS="${OMIT_SECONDS:-3}"
IPERF_PORT="${IPERF_PORT:-5201}"

# SPI sweep settings.
STEP_HZ="${STEP_HZ:-1000000}"
MIN_HZ="${MIN_HZ:-1000000}"

# Result file. An absolute path is recommended.
CSV_FILE="${CSV_FILE:-$SCRIPT_DIR/t1s_spi_sweep.csv}"

# SSH options. BatchMode prevents password prompts during the automated test.
SSH_OPTIONS=(
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o ServerAliveInterval=5
    -o ServerAliveCountMax=3
)

###############################################################################
# Derived paths
###############################################################################

DTS_DIR="$REPO_ROOT/products/BE-IIS-HPP-T1S-REVB/overlays/src/rpi"
DTS_FILE="$DTS_DIR/$OVERLAY_NAME.dts"
INSTALLED_DTBO="/boot/firmware/overlays/$OVERLAY_NAME.dtbo"

TMP_DIR=""
IPERF_SERVER_PID=""

###############################################################################
# Helpers
###############################################################################

info()  { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
    if [[ -n "${IPERF_SERVER_PID:-}" ]] && kill -0 "$IPERF_SERVER_PID" 2>/dev/null; then
        kill "$IPERF_SERVER_PID" 2>/dev/null || true
        wait "$IPERF_SERVER_PID" 2>/dev/null || true
    fi
    [[ -n "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

need_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

hz_to_mhz() {
    python3 - "$1" <<'PY'
import sys
print(f"{int(sys.argv[1]) / 1_000_000:.3f}")
PY
}

read_source_spi_hz() {
    python3 - "$DTS_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
pattern = re.compile(
    r"^\s*spi-max-frequency\s*=\s*<\s*(\d+)\s*>\s*;",
    re.MULTILINE,
)
values = pattern.findall(text)
if len(values) != 1:
    raise SystemExit(
        f"Expected exactly one active spi-max-frequency property in {path}, "
        f"found {len(values)}"
    )
print(values[0])
PY
}

read_active_spi_hz() {
    # Read the running kernel's flattened device tree. Device-tree integer
    # properties are stored as big-endian 32-bit values.
    python3 <<'PY'
from pathlib import Path
import sys

base = Path("/sys/firmware/devicetree/base")
if not base.exists():
    raise SystemExit("/sys/firmware/devicetree/base does not exist")

matches = []
for compatible in base.rglob("compatible"):
    try:
        raw = compatible.read_bytes()
    except OSError:
        continue

    if b"microchip,lan8651" not in raw and b"microchip,lan8650" not in raw:
        continue

    status_file = compatible.parent / "status"
    if status_file.is_file():
        status = status_file.read_bytes().rstrip(b"\x00")
        if status not in (b"okay", b"ok"):
            continue

    speed_file = compatible.parent / "spi-max-frequency"
    if not speed_file.is_file():
        continue

    raw_speed = speed_file.read_bytes()
    if len(raw_speed) < 4:
        continue

    speed = int.from_bytes(raw_speed[:4], byteorder="big", signed=False)
    matches.append((compatible.parent, speed))

if not matches:
    raise SystemExit(
        "No active LAN8650/LAN8651 device-tree node with spi-max-frequency found"
    )

if len(matches) > 1:
    details = "\n".join(f"  {path}: {speed} Hz" for path, speed in matches)
    raise SystemExit(
        "Multiple active LAN865x nodes found. This script currently expects one "
        f"T1S HAT on the receiver:\n{details}"
    )

print(matches[0][1])
PY
}

get_local_t1s_ip() {
    ip -4 -o addr show dev "$T1S_IFACE" scope global \
        | awk 'NR == 1 { split($4, a, "/"); print a[1] }'
}

get_remote_t1s_ip() {
    ssh "${SSH_OPTIONS[@]}" "$SENDER_SSH" \
        "ip -4 -o addr show dev '$T1S_IFACE' scope global" \
        | awk 'NR == 1 { split($4, a, "/"); print a[1] }'
}

wait_for_server() {
    local retries=50
    local i

    for ((i = 0; i < retries; i++)); do
        if ! kill -0 "$IPERF_SERVER_PID" 2>/dev/null; then
            return 1
        fi

        if ss -ltn 2>/dev/null \
            | awk -v port=":$IPERF_PORT" '$4 ~ port "$" { found=1 } END { exit !found }'; then
            return 0
        fi

        sleep 0.1
    done

    return 1
}

parse_server_json() {
    python3 - "$1" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
end = data.get("end", {})

# iperf3 versions differ slightly in their UDP JSON layout.
summary = None
for key in ("sum_received", "sum", "sum_sent"):
    candidate = end.get(key)
    if isinstance(candidate, dict) and "bits_per_second" in candidate:
        summary = candidate
        break

if summary is None:
    error = data.get("error")
    if error:
        raise SystemExit(f"iperf3 error: {error}")
    raise SystemExit("No UDP receive summary found in iperf3 JSON")

bps = float(summary.get("bits_per_second", 0.0))
received_mbit = bps / 1_000_000.0
lost_percent = summary.get("lost_percent", "")
jitter_ms = summary.get("jitter_ms", "")
packets = summary.get("packets", "")
lost_packets = summary.get("lost_packets", "")

print(
    f"{received_mbit:.6f}|{lost_percent}|{jitter_ms}|"
    f"{packets}|{lost_packets}"
)
PY
}

append_csv() {
    local timestamp="$1"
    local status="$2"
    local active_hz="$3"
    local received_mbit="$4"
    local lost_percent="$5"
    local jitter_ms="$6"
    local packets="$7"
    local lost_packets="$8"
    local receiver_ip="$9"
    local sender_ip="${10}"
    local note="${11}"

    python3 - \
        "$CSV_FILE" "$timestamp" "$status" "$(hostname)" "$OVERLAY_NAME" \
        "$active_hz" "$(hz_to_mhz "$active_hz")" "$UDP_RATE" \
        "$received_mbit" "$lost_percent" "$jitter_ms" "$packets" \
        "$lost_packets" "$TEST_SECONDS" "$OMIT_SECONDS" \
        "$T1S_IFACE" "$receiver_ip" "$sender_ip" "$SENDER_SSH" "$note" <<'PY'
import csv
import sys
from pathlib import Path

(
    csv_name,
    timestamp,
    status,
    receiver_host,
    overlay,
    spi_hz,
    spi_mhz,
    udp_target,
    received_mbit,
    lost_percent,
    jitter_ms,
    packets,
    lost_packets,
    test_seconds,
    omit_seconds,
    interface,
    receiver_ip,
    sender_ip,
    sender_ssh,
    note,
) = sys.argv[1:]

path = Path(csv_name).expanduser()
path.parent.mkdir(parents=True, exist_ok=True)
new_file = not path.exists() or path.stat().st_size == 0

header = [
    "timestamp",
    "status",
    "receiver_host",
    "overlay",
    "spi_requested_hz",
    "spi_requested_mhz",
    "udp_target",
    "received_mbit_s",
    "lost_percent",
    "jitter_ms",
    "packets",
    "lost_packets",
    "test_seconds",
    "omit_seconds",
    "interface",
    "receiver_ip",
    "sender_ip",
    "sender_ssh",
    "note",
]

row = [
    timestamp,
    status,
    receiver_host,
    overlay,
    spi_hz,
    spi_mhz,
    udp_target,
    received_mbit,
    lost_percent,
    jitter_ms,
    packets,
    lost_packets,
    test_seconds,
    omit_seconds,
    interface,
    receiver_ip,
    sender_ip,
    sender_ssh,
    note,
]

with path.open("a", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    if new_file:
        writer.writerow(header)
    writer.writerow(row)
PY
}

set_source_spi_hz() {
    local new_hz="$1"

    python3 - "$DTS_FILE" "$new_hz" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
new_hz = int(sys.argv[2])
text = path.read_text(encoding="utf-8")
pattern = re.compile(
    r"(^\s*spi-max-frequency\s*=\s*<\s*)\d+(\s*>\s*;)",
    re.MULTILINE,
)
new_text, count = pattern.subn(
    lambda match: f"{match.group(1)}{new_hz}{match.group(2)}",
    text,
    count=1,
)
if count != 1:
    raise SystemExit(
        f"Expected exactly one spi-max-frequency replacement in {path}, "
        f"changed {count}"
    )
path.write_text(new_text, encoding="utf-8")
PY
}

###############################################################################
# Validation
###############################################################################

need_command ip
need_command iperf3
need_command make
need_command python3
need_command ssh
need_command ss
need_command sudo
need_command timeout

[[ -n "$SENDER_SSH" ]] || die \
    "SENDER_SSH is empty. Set it near the top of the script or run: SENDER_SSH=user@management-ip $0"
[[ -d "$REPO_ROOT/.git" ]] || warn \
    "$REPO_ROOT does not look like a Git clone; continuing because the files may still be valid"
[[ -d "$DTS_DIR" ]] || die "Overlay source directory not found: $DTS_DIR"
[[ -f "$DTS_FILE" ]] || die "Overlay source not found: $DTS_FILE"
[[ "$STEP_HZ" =~ ^[0-9]+$ ]] && (( STEP_HZ > 0 )) || die "Invalid STEP_HZ: $STEP_HZ"
[[ "$MIN_HZ" =~ ^[0-9]+$ ]] && (( MIN_HZ > 0 )) || die "Invalid MIN_HZ: $MIN_HZ"
[[ "$TEST_SECONDS" =~ ^[0-9]+$ ]] && (( TEST_SECONDS > 0 )) || die "Invalid TEST_SECONDS"
[[ "$OMIT_SECONDS" =~ ^[0-9]+$ ]] || die "Invalid OMIT_SECONDS"
[[ "$IPERF_PORT" =~ ^[0-9]+$ ]] || die "Invalid IPERF_PORT"

info "Checking sudo permission for the later overlay installation"
sudo -v || die "sudo authentication failed"

TMP_DIR="$(mktemp -d)"
SERVER_JSON="$TMP_DIR/iperf-server.json"
SERVER_ERR="$TMP_DIR/iperf-server.err"
CLIENT_JSON="$TMP_DIR/iperf-client.json"
CLIENT_ERR="$TMP_DIR/iperf-client.err"

###############################################################################
# Confirm that the installed/booted overlay matches the source
###############################################################################

SOURCE_HZ="$(read_source_spi_hz)" || die "Could not read SPI frequency from $DTS_FILE"
ACTIVE_HZ="$(read_active_spi_hz)" || die "Could not read active SPI frequency"

info "SPI frequency"
printf '  Active device tree : %s Hz (%s MHz)\n' "$ACTIVE_HZ" "$(hz_to_mhz "$ACTIVE_HZ")"
printf '  Overlay source     : %s Hz (%s MHz)\n' "$SOURCE_HZ" "$(hz_to_mhz "$SOURCE_HZ")"

if [[ "$ACTIVE_HZ" != "$SOURCE_HZ" ]]; then
    warn "The running device tree and the overlay source do not match."
    warn "Most likely the previous step has already installed a new overlay, but the Pi has not rebooted yet."
    warn "A dtoverlay speed=... override in config.txt can also cause this mismatch."
    printf '\nBitte jetzt neu starten:\n\n  sudo reboot\n\n'
    exit 2
fi

###############################################################################
# Discover T1S addresses and verify the sender
###############################################################################

RECEIVER_T1S_IP="$(get_local_t1s_ip)"
[[ -n "$RECEIVER_T1S_IP" ]] || die \
    "No IPv4 address found on receiver interface $T1S_IFACE"

info "Checking sender over SSH: $SENDER_SSH"
ssh "${SSH_OPTIONS[@]}" "$SENDER_SSH" \
    "command -v iperf3 >/dev/null && command -v ip >/dev/null && command -v timeout >/dev/null" \
    || die "Cannot reach sender or iperf3/ip/timeout is missing on the sender"

LOCAL_IPERF_VERSION="$(iperf3 --version 2>&1 | sed -n '1p')"
REMOTE_IPERF_VERSION="$(ssh "${SSH_OPTIONS[@]}" "$SENDER_SSH" "iperf3 --version 2>&1 | sed -n '1p'")"
printf '  Local iperf3       : %s\n' "$LOCAL_IPERF_VERSION"
printf '  Remote iperf3      : %s\n' "$REMOTE_IPERF_VERSION"
if [[ "$LOCAL_IPERF_VERSION" != "$REMOTE_IPERF_VERSION" ]]; then
    warn "Local and remote iperf3 versions differ. Throughput is still usable, but loss statistics may differ between versions."
fi

SENDER_T1S_IP="$(get_remote_t1s_ip)"
[[ -n "$SENDER_T1S_IP" ]] || die \
    "No IPv4 address found on sender interface $T1S_IFACE"

printf '  Receiver T1S IP    : %s\n' "$RECEIVER_T1S_IP"
printf '  Sender T1S IP      : %s\n' "$SENDER_T1S_IP"
printf '  UDP target         : %sbit/s\n' "$UDP_RATE"
printf '  Measurement        : %ss, omit first %ss\n' "$TEST_SECONDS" "$OMIT_SECONDS"

###############################################################################
# Run one UDP measurement
###############################################################################

info "Starting local iperf3 receiver"
iperf3 \
    -s \
    -1 \
    -J \
    -4 \
    -B "$RECEIVER_T1S_IP" \
    -p "$IPERF_PORT" \
    >"$SERVER_JSON" 2>"$SERVER_ERR" &
IPERF_SERVER_PID=$!

if ! wait_for_server; then
    cat "$SERVER_ERR" >&2 || true
    die "iperf3 server did not start on $RECEIVER_T1S_IP:$IPERF_PORT"
fi

ok "iperf3 server is listening"
info "Starting UDP sender remotely"

# The SSH connection should preferably use a separate management network.
# The iperf3 data connection is explicitly bound to the sender's T1S IP.
REMOTE_TIMEOUT=$((TEST_SECONDS + OMIT_SECONDS + 30))
REMOTE_COMMAND=(
    timeout "${REMOTE_TIMEOUT}s"
    iperf3
    -4
    -c "$RECEIVER_T1S_IP"
    -B "$SENDER_T1S_IP"
    -u
    -b "$UDP_RATE"
    -t "$TEST_SECONDS"
    -O "$OMIT_SECONDS"
    -J
    -p "$IPERF_PORT"
)
printf -v REMOTE_COMMAND_Q '%q ' "${REMOTE_COMMAND[@]}"

TEST_TIMESTAMP="$(date --iso-8601=seconds)"

if ! timeout "$((REMOTE_TIMEOUT + 5))s" \
    ssh "${SSH_OPTIONS[@]}" "$SENDER_SSH" "$REMOTE_COMMAND_Q" \
    >"$CLIENT_JSON" 2>"$CLIENT_ERR"; then
    warn "Remote iperf3 client failed"
    cat "$CLIENT_ERR" >&2 || true

    if kill -0 "$IPERF_SERVER_PID" 2>/dev/null; then
        kill "$IPERF_SERVER_PID" 2>/dev/null || true
    fi
    wait "$IPERF_SERVER_PID" 2>/dev/null || true
    IPERF_SERVER_PID=""

    append_csv \
        "$TEST_TIMESTAMP" "FAILED" "$ACTIVE_HZ" "" "" "" "" "" \
        "$RECEIVER_T1S_IP" "$SENDER_T1S_IP" "remote iperf3 client failed"

    die "Measurement failed. The failed point was written to $CSV_FILE; SPI frequency was not changed."
fi

if ! wait "$IPERF_SERVER_PID"; then
    IPERF_SERVER_PID=""
    warn "iperf3 server exited with an error"
    cat "$SERVER_ERR" >&2 || true

    append_csv \
        "$TEST_TIMESTAMP" "FAILED" "$ACTIVE_HZ" "" "" "" "" "" \
        "$RECEIVER_T1S_IP" "$SENDER_T1S_IP" "local iperf3 server failed"

    die "Measurement failed. The failed point was written to $CSV_FILE; SPI frequency was not changed."
fi
IPERF_SERVER_PID=""

if ! RESULT="$(parse_server_json "$SERVER_JSON")"; then
    warn "Could not parse receiver-side iperf3 result"
    cat "$SERVER_JSON" >&2 || true

    append_csv \
        "$TEST_TIMESTAMP" "FAILED" "$ACTIVE_HZ" "" "" "" "" "" \
        "$RECEIVER_T1S_IP" "$SENDER_T1S_IP" "could not parse iperf3 JSON"

    die "Measurement result was invalid; SPI frequency was not changed."
fi

IFS='|' read -r RECEIVED_MBIT LOST_PERCENT JITTER_MS PACKETS LOST_PACKETS <<<"$RESULT"

append_csv \
    "$TEST_TIMESTAMP" "OK" "$ACTIVE_HZ" "$RECEIVED_MBIT" \
    "$LOST_PERCENT" "$JITTER_MS" "$PACKETS" "$LOST_PACKETS" \
    "$RECEIVER_T1S_IP" "$SENDER_T1S_IP" ""

ok "Measurement completed"
printf '  Requested SPI speed: %s MHz\n' "$(hz_to_mhz "$ACTIVE_HZ")"
printf '  Received throughput: %s Mbit/s\n' "$RECEIVED_MBIT"
printf '  Packet loss        : %s %%\n' "${LOST_PERCENT:-n/a}"
printf '  Jitter             : %s ms\n' "${JITTER_MS:-n/a}"
printf '  CSV                 : %s\n' "$CSV_FILE"

###############################################################################
# Prepare the next SPI frequency
###############################################################################

if (( ACTIVE_HZ <= MIN_HZ )); then
    warn "Minimum SPI frequency reached. No lower overlay will be prepared."
    exit 0
fi

NEXT_HZ=$((ACTIVE_HZ - STEP_HZ))
if (( NEXT_HZ < MIN_HZ )); then
    NEXT_HZ=$MIN_HZ
fi

info "Preparing next SPI frequency: $(hz_to_mhz "$NEXT_HZ") MHz"

SOURCE_BACKUP="$TMP_DIR/$(basename "$DTS_FILE").backup"
cp -- "$DTS_FILE" "$SOURCE_BACKUP"

set_source_spi_hz "$NEXT_HZ"

restore_source() {
    cp -- "$SOURCE_BACKUP" "$DTS_FILE"
}

if ! make -C "$DTS_DIR" clean all; then
    restore_source
    die "Overlay build failed. The original DTS source was restored."
fi

if ! make -C "$DTS_DIR" install; then
    restore_source
    die "Overlay installation failed. The original DTS source was restored."
fi

[[ -f "$INSTALLED_DTBO" ]] || die \
    "Build reported success, but installed overlay was not found: $INSTALLED_DTBO"

NEW_SOURCE_HZ="$(read_source_spi_hz)"
[[ "$NEW_SOURCE_HZ" == "$NEXT_HZ" ]] || die \
    "Unexpected source frequency after build: $NEW_SOURCE_HZ Hz"

ok "Overlay rebuilt and installed"
printf '  Current requested SPI speed: %s MHz\n' "$(hz_to_mhz "$ACTIVE_HZ")"
printf '  Next requested SPI speed   : %s MHz\n' "$(hz_to_mhz "$NEXT_HZ")"
printf '  Installed overlay          : %s\n' "$INSTALLED_DTBO"

printf '\n\033[1;33mBitte jetzt neu starten:\033[0m\n\n  sudo reboot\n\n'
printf 'Nach dem Neustart dasselbe Skript erneut aufrufen.\n'
