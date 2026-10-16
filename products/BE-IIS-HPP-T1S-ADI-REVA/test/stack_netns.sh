#!/usr/bin/env bash
# Move two ADIN1140 interfaces into independent namespaces for cable testing.
set -euo pipefail
[[ "$EUID" -eq 0 ]] || { echo "ERROR: run as root" >&2; exit 1; }
ACTION="${1:-}"
IF0="beiis-t1s-adi0"
IF1="beiis-t1s-adi1"
case "$ACTION" in
  setup)
    if ip netns list | grep -Eq '^(t1s0|t1s1)( |$)'; then
      echo "ERROR: test namespaces already exist" >&2
      exit 1
    fi
    ip link show dev "$IF0" >/dev/null
    ip link show dev "$IF1" >/dev/null
    ip netns add t1s0
    ip netns add t1s1
    ip link set "$IF0" netns t1s0
    ip link set "$IF1" netns t1s1
    ip -n t1s0 addr add 192.168.78.1/24 dev "$IF0"
    ip -n t1s1 addr add 192.168.78.2/24 dev "$IF1"
    ip -n t1s0 link set lo up
    ip -n t1s1 link set lo up
    ip -n t1s0 link set "$IF0" up
    ip -n t1s1 link set "$IF1" up
    echo "READY: interfaces isolated for physical link testing"
    ;;
  cleanup)
    for ns in t1s0 t1s1; do
      if ip netns list | grep -Eq "^$ns( |$)"; then
        ip netns del "$ns"
        echo "REMOVED: $ns"
      fi
    done
    ;;
  *)
    echo "Usage: sudo bash $0 {setup|cleanup}" >&2
    exit 2
    ;;
esac
