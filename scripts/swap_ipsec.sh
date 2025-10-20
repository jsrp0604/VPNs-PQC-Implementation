#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"

if [[ "$MODE" != "classic" && "$MODE" != "hybrid" ]]; then
  echo "Usage: $0 {classic|hybrid}"
  echo "  Cleanly stops one IPsec implementation and prepares for the other"
  exit 1
fi

echo "[swap] Stopping all IPsec containers..."
sudo docker stop ipsec_srv ipsec_cli ipsec_hybrid_srv ipsec_hybrid_cli 2>/dev/null || true
sudo docker rm ipsec_srv ipsec_cli ipsec_hybrid_srv ipsec_hybrid_cli 2>/dev/null || true

echo "[swap] Cleaning up IPsec state..."
sudo ip xfrm state flush 2>/dev/null || true
sudo ip xfrm policy flush 2>/dev/null || true

echo "[swap] Checking kernel modules..."
sudo modprobe xfrm_user 2>/dev/null || true
sudo modprobe af_key 2>/dev/null || true

if [[ "$MODE" == "classic" ]]; then
  echo "[swap] Ready for ipsec_classic"
  echo ""
  echo "SERVER: sudo docker run -d --name ipsec_srv --network host --cap-add NET_ADMIN --device /dev/net/tun -v /data:/data -e ROLE=server ipsec_classic"
  echo "CLIENT: sudo docker run -d --name ipsec_cli --network host --cap-add NET_ADMIN --device /dev/net/tun -v /data:/data -e ROLE=client ipsec_classic"
else
  echo "[swap] Ready for ipsec_hybrid"
fi