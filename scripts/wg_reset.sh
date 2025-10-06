#!/usr/bin/env bash
set -euo pipefail

sudo docker stop wg_srv >/dev/null 2>&1 || true
sudo docker rm   wg_srv >/dev/null 2>&1 || true

sudo wg-quick down wg0 2>/dev/null || true
sudo ip link del wg0 2>/dev/null || true
echo "[wg_reset] host clean."
