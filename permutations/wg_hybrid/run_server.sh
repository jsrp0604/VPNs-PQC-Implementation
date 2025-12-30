#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="${SERVER_IP:-192.168.76.143}"
CLIENT_IP="${CLIENT_IP:-192.168.76.144}"

echo "[server] Starting WireGuard + Rosenpass"

sudo docker stop wg_srv_hybrid 2>/dev/null || true
sudo ip link del wg0 2>/dev/null || true
sleep 1

if [ ! -f /data/wg_hybrid/server/secret.key ]; then
  echo "[server] ERROR: Server secret key not found"
  exit 1
fi

sudo touch /data/wg_hybrid/server/public.key
sudo touch /data/wg_hybrid/client/public.key
sudo chmod 644 /data/wg_hybrid/server/public.key /data/wg_hybrid/client/public.key

echo "[server] Starting Rosenpass daemon"
sudo docker run -d --rm \
  --name wg_srv_hybrid \
  --network host \
  --cap-add NET_ADMIN \
  --entrypoint rp \
  -v /data/wg_hybrid:/keys \
  wg_hybrid:local \
  exchange \
    public-key /keys/server/public.key \
    secret-key /keys/server/secret.key \
    listen 0.0.0.0:9999 \
    verbose \
  peer \
    public-key /keys/client/public.key \
    endpoint ${CLIENT_IP}:9999 \
    wireguard wg0 rosenpass-peer

sleep 3

if ! sudo docker ps | grep -q wg_srv_hybrid; then
  echo "[server] ERROR: Container exited"
  sudo docker logs wg_srv_hybrid
  exit 1
fi

echo "[server] Waiting for WireGuard interface..."
for i in {1..10}; do
  if ip link show wg0 >/dev/null 2>&1; then
    echo "[server] wg0 interface created"
    break
  fi
  sleep 1
done

sudo ip addr add 10.30.0.1/24 dev wg0 2>/dev/null || true
sudo ip link set wg0 up

sudo docker exec -d wg_srv_hybrid iperf3 -s -B 10.30.0.1 2>/dev/null || true

echo "[server] Stack ready"