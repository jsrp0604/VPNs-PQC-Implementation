#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="${SERVER_IP:-192.168.76.143}"

echo "[server] Starting OpenVPN Hybrid Stack"

sudo docker stop ovpn_srv_hybrid pqtls_srv 2>/dev/null || true
sleep 1

sudo docker run -d --rm \
  --name ovpn_srv_hybrid \
  --network host \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  --entrypoint openvpn \
  -v /data/ovpn_classic/server/pki:/pki:ro \
  -v /data/ovpn_hybrid/server:/config:ro \
  ovpn_classic:latest \
  --config /config/server_tcp.conf

sleep 3

if ! sudo docker ps | grep -q ovpn_srv_hybrid; then
  echo "[server] ERROR: OpenVPN failed"
  exit 1
fi

echo "[server] ✓ OpenVPN on localhost:11194"

sudo docker run -d --rm \
  --name pqtls_srv \
  --network host \
  -v /data/ovpn_hybrid/transport:/certs:ro \
  -v /data/ovpn_hybrid:/config:ro \
  -e OPENSSL_CONF=/config/openssl-pqtls.cnf \
  -e OPENSSL_MODULES=/usr/local/lib/ossl-modules \
  pqtls_proxy:local \
  bash -c 'socat -d -d -d -d \
    OPENSSL-LISTEN:1194,cert=/certs/server/cert.pem,key=/certs/server/key.pem,cafile=/certs/server/ca.pem,verify=1,reuseaddr,fork,openssl-min-proto-version=TLS1.3 \
    TCP:127.0.0.1:11194 2>&1 | tee /data/ovpn_hybrid/pqtls_server_debug.log'

sleep 2
echo "[server] ✓ PQ-TLS proxy (debug mode) on ${SERVER_IP}:1194"

sudo docker exec -d ovpn_srv_hybrid iperf3 -s -B 10.20.0.1

echo "[server] ✓ iperf3 server on 10.20.0.1"
echo "[server] Debug log: /data/ovpn_hybrid/pqtls_server_debug.log"
sudo docker ps | grep -E 'ovpn_srv_hybrid|pqtls_srv'
