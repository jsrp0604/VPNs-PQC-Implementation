#!/usr/bin/env bash
set -euo pipefail

echo "[ipsec_hybrid] Starting IPsec hybrid server stack..."

sudo docker stop ipsec_hybrid_srv 2>/dev/null || true
sudo docker rm ipsec_hybrid_srv 2>/dev/null || true

echo "[ipsec_hybrid] Starting server container..."
sudo docker run -d --name ipsec_hybrid_srv \
  --privileged --network host \
  -e ROLE=server \
  -v /data:/data \
  ipsec_hybrid:local

echo "[ipsec_hybrid] Waiting for server to be ready..."
sleep 5

if ! sudo docker ps | grep -q ipsec_hybrid_srv; then
  echo "[ipsec_hybrid] FATAL: Server container exited"
  sudo docker logs ipsec_hybrid_srv
  exit 1
fi

echo "[ipsec_hybrid] Server container running"

if sudo docker exec ipsec_hybrid_srv pgrep -x charon >/dev/null; then
  echo "[ipsec_hybrid] charon daemon running"
else
  echo "[ipsec_hybrid] WARNING: charon not running"
fi

echo "[ipsec_hybrid] Loaded connections:"
sudo docker exec ipsec_hybrid_srv swanctl --list-conns | sed 's/^/  /'

echo "[ipsec_hybrid] ML-KEM algorithms:"
sudo docker exec ipsec_hybrid_srv swanctl --list-algs | grep -i mlkem | sed 's/^/  /' || echo "  (none found - check OpenSSL version)"

echo "[ipsec_hybrid] Starting iperf3 server on 10.30.0.1..."
sudo docker exec -d ipsec_hybrid_srv iperf3 -s -B 10.30.0.1

sleep 1

if sudo docker exec ipsec_hybrid_srv ss -tlnp | grep -q 5201; then
  echo "[ipsec_hybrid]  iperf3 listening on port 5201"
else
  echo "[ipsec_hybrid] WARNING: iperf3 not listening"
fi

echo ""
echo "[ipsec_hybrid]  Server stack ready"
echo ""