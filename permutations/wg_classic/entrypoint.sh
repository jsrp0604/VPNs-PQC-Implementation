#!/usr/bin/env bash
set -euo pipefail

IFACE="${IFACE:-wg0}"                 
CONF_PATH="${CONF_PATH:-/etc/wireguard/wg0.conf}"

cleanup() {
  wg-quick down "${IFACE}" 2>/dev/null || true
  ip link del "${IFACE}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

cleanup

wg-quick up "${IFACE}"

tail -f /dev/null
