#!/usr/bin/env bash
set -euo pipefail

ALGO="${1:-x25519_mlkem768}"
SERVER_IP="192.168.76.143"
PROXY_PORT="1194"
LOCAL_PORT="1194"

echo "[client] Starting TLS proxy (${ALGO}) + OpenVPN TCP client"

docker run -d --rm \
  --name pqtls_proxy_cli \
  --network host \
  -v /data/ovpn_hybrid/transport:/certs:ro \
  -e OPENSSL_MODULES=/usr/local/lib/ossl-modules \
  pqtls_proxy:local \
  bash -c "
    socat -v \
      TCP-LISTEN:${LOCAL_PORT},reuseaddr,fork \
      OPENSSL:${SERVER_IP}:${PROXY_PORT},\
cert=/certs/client/cert.pem,\
key=/certs/client/key.pem,\
cafile=/certs/client/ca.pem,\
verify=1,\
openssl-min-proto-version=TLS1.3,\
openssl-ciphersuites=TLS_AES_256_GCM_SHA384,\
cipher=${ALGO} \
      2>&1 | tee /data/ovpn_hybrid/proxy_client_${ALGO}.log
  "

sleep 3

docker run -d --rm \
  --name ovpn_cli_hybrid \
  --network host \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  -v /data:/data:ro \
  -v /data/ovpn_classic/client:/etc/openvpn:ro \
  -e ROLE=client \
  ovpn_classic:local \
  openvpn --config /etc/openvpn/client.ovpn \
    --proto tcp-client \
    --remote 127.0.0.1 ${LOCAL_PORT} \
    --log /data/ovpn_hybrid/ovpn_client.log \
    --daemon

echo "[client] Connected to ${SERVER_IP}:${PROXY_PORT} via ${ALGO}"