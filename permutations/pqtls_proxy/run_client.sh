#!/usr/bin/env bash
set -euo pipefail

ALGO="${1:-x25519_mlkem768}"
SERVER_IP="${SERVER_IP:-192.168.76.143}"

echo "[client] Starting OpenVPN Hybrid Stack"
echo "        PQ Algorithm: ${ALGO}"
echo "        Server: ${SERVER_IP}:1194"

sudo docker stop ovpn_cli_hybrid pqtls_cli 2>/dev/null || true
sleep 1

echo "[client] Starting PQ-TLS proxy to ${SERVER_IP}:1194"
sudo docker run -d --rm \
  --name pqtls_cli \
  --network host \
  -v /data/ovpn_hybrid/transport:/certs:ro \
  -v /data/ovpn_hybrid:/config:ro \
  -e OPENSSL_CONF=/config/openssl-pqtls.cnf \
  -e OPENSSL_MODULES=/usr/local/lib/ossl-modules \
  pqtls_proxy:local \
  socat -d -d \
    TCP-LISTEN:1194,reuseaddr,fork \
    OPENSSL:${SERVER_IP}:1194,cert=/certs/client/cert.pem,key=/certs/client/key.pem,cafile=/certs/client/ca.pem,verify=1,openssl-min-proto-version=TLS1.3

sleep 3
echo "[client] ✓ TLS proxy ready on localhost:1194"

echo "[client] Starting OpenVPN TCP client"
sudo docker run -d --rm \
  --name ovpn_cli_hybrid \
  --network host \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  --entrypoint openvpn \
  -v /data:/data:ro \
  ovpn_classic:latest \
  --config /data/ovpn_hybrid/client/client_tcp.conf

sleep 5

if ip addr show tun0 2>/dev/null | grep -q "inet "; then
  TUN_IP=$(ip -4 -o addr show tun0 | awk '{print $4}' | cut -d/ -f1)
  echo "[client] ✓ Tunnel UP: $TUN_IP"
  
  if ping -c2 -W2 10.20.0.1 >/dev/null 2>&1; then
    echo "[client] ✓ Server reachable: 10.20.0.1"
  else
    echo "[client] ⚠ Warning: Server not responding to ping"
  fi
else
  echo "[client] ⚠ Warning: tun0 interface not up yet"
fi

echo ""
echo "Status:"
sudo docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E 'NAMES|ovpn_cli_hybrid|pqtls_cli'
echo ""
echo "Test: ping 10.20.0.1"
echo "Logs:"
echo "  OpenVPN: sudo docker logs -f ovpn_cli_hybrid"
echo "  Proxy:   sudo docker logs -f pqtls_cli"
