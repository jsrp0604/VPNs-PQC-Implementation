#!/usr/bin/env bash
set -euo pipefail

ROLE="${ROLE:-client}"   
OVPN_CONFIG="${OVPN_CONFIG:-/etc/openvpn/openvpn.conf}"
LOG_PATH="${LOG_PATH:-/var/log/openvpn.log}"
IFACE="${IFACE:-tun0}"

cleanup() {
  echo "[ovpn] cleanup: stopping OpenVPN and removing ${IFACE} if present"
  pkill -TERM -x openvpn 2>/dev/null || true
  ip link del "${IFACE}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "$(dirname "$LOG_PATH")"
: > "$LOG_PATH"

echo "[ovpn] starting role=$ROLE using config=$OVPN_CONFIG"
openvpn --config "$OVPN_CONFIG" --daemon --writepid /var/run/openvpn.pid \
        --log "$LOG_PATH" --suppress-timestamps

touch /tmp/.ready
tail -F "$LOG_PATH"
