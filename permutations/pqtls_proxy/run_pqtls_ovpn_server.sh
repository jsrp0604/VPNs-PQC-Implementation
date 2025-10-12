#!/usr/bin/env bash
set -euo pipefail

ALGO="${1:-x25519_mlkem768}"  
PROXY_PORT="1194"
OVPN_PORT="11194"
SERVER_IP="192.168.76.143"

echo "[server] Starting PQ-TLS proxy (${ALGO}) + OpenVPN TCP server"

docker run -d --rm \
  --name ovpn_srv_hybrid \
  --network host \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  -v /data:/data:ro \
  -v /data/ovpn_classic/server:/etc/openvpn:ro \
  -e ROLE=server \
  ovpn_classic:local \
  openvpn --config /etc/openvpn/server.conf \
    --proto tcp-server \
    --port ${OVPN_PORT} \
    --local 127.0.0.1 \
    --log /data/ovpn_hybrid/ovpn_server.log \
    --daemon

sleep 3

docker run -d --rm \
  --name pqtls_proxy_srv \
  --network host \
  -v /data/ovpn_hybrid/transport:/certs:ro \
  -e OPENSSL_MODULES=/usr/local/lib/ossl-modules \
  pqtls_proxy:local \
  bash -c "
    socat -v \
      OPENSSL-LISTEN:${PROXY_PORT},\
cert=/certs/server/cert.pem,\
key=/certs/server/key.pem,\
cafile=/certs/server/ca.pem,\
verify=1,\
reuseaddr,\
fork,\
openssl-min-proto-version=TLS1.3,\
openssl-ciphersuites=TLS_AES_256_GCM_SHA384,\
cipher=${ALGO} \
      TCP:127.0.0.1:${OVPN_PORT} \
      2>&1 | tee /data/ovpn_hybrid/proxy_server_${ALGO}.log
  "

echo "[server] Proxy listening on ${SERVER_IP}:${PROXY_PORT} → OpenVPN on localhost:${OVPN_PORT}"
echo "[server] Algorithm: ${ALGO}"