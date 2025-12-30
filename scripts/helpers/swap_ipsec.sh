#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"

if [[ "$MODE" != "classic" && "$MODE" != "hybrid" ]]; then
  echo "Usage: $0 {classic|hybrid}"
  exit 1
fi

echo "Stopping all IPsec containers"
sudo docker stop ipsec_srv ipsec_cli ipsec_hybrid_srv ipsec_hybrid_cli 2>/dev/null || true
sudo docker rm ipsec_srv ipsec_cli ipsec_hybrid_srv ipsec_hybrid_cli 2>/dev/null || true

echo "Cleaning up IPsec state"
sudo ip xfrm state flush 2>/dev/null || true
sudo ip xfrm policy flush 2>/dev/null || true

echo "Checking kernel modules"
sudo modprobe xfrm_user 2>/dev/null || true
sudo modprobe af_key 2>/dev/null || true

if [[ "$MODE" == "classic" ]]; then
  echo "Ready for ipsec_classic"
else
  echo "Ready for ipsec_hybrid"
fi