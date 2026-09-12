#!/usr/bin/env bash
# Program the MachXO2 non-volatile configuration flash through FPGA region0.
set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

[ "${EUID}" -eq 0 ] || die "run as root: sudo bash $0 <bitstream>"
[ "$#" -eq 1 ] || die "usage: sudo bash $0 <bitstream-file>"

bitstream="$1"
[ -r "$bitstream" ] || die "cannot read bitstream: $bitstream"

size="$(stat -c %s "$bitstream")"
[ "$size" -gt 0 ] || die "bitstream is empty"
[ "$((size % 16))" -eq 0 ] || die "bitstream size must be a multiple of 16 bytes"

[ -e /sys/class/fpga_manager/fpga0 ] || die "fpga0 is not available"
[ -e /sys/class/fpga_region/region0 ] || die "region0 is not available (install Instance-I FPGA region first)"

mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config

firmware_name="$(basename "$bitstream")"
install -D -m 0644 "$bitstream" "/lib/firmware/$firmware_name"

tmp_dts="$(mktemp --suffix=.dts)"
tmp_dtbo="${tmp_dts%.dts}.dtbo"
overlay_dir="/sys/kernel/config/device-tree/overlays/beiis-machxo2-load"
trap 'rm -f "$tmp_dts" "$tmp_dtbo"' EXIT

cat > "$tmp_dts" <<EOF
/dts-v1/;
/plugin/;

/ {
    fragment@0 {
        target-path = "/fpga-region";
        __overlay__ {
            firmware-name = "$firmware_name";
        };
    };
};
EOF

dtc -@ -I dts -O dtb -o "$tmp_dtbo" "$tmp_dts"

if [ -d "$overlay_dir" ]; then
    rmdir "$overlay_dir"
fi
mkdir "$overlay_dir"
cat "$tmp_dtbo" > "$overlay_dir/dtbo"

state="$(cat /sys/class/fpga_manager/fpga0/state)"
[ "$state" = "operating" ] || die "programming failed; FPGA state: $state"

echo "MachXO2 programmed successfully: $firmware_name"
