#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-both}"

if [[ "$ROLE" == "server" ]] || [[ "$ROLE" == "both" ]]; then
  echo "[stop] Stopping server containers"
  sudo docker stop ovpn_srv_hybrid pqtls_srv 2>/dev/null || true
fi

if [[ "$ROLE" == "client" ]] || [[ "$ROLE" == "both" ]]; then
  echo "[stop] Stopping client containers"
  sudo docker stop ovpn_cli_hybrid pqtls_cli 2>/dev/null || true
fi

echo "[stop] Done"
