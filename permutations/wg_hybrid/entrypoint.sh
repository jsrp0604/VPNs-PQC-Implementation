#!/usr/bin/env bash
set -euo pipefail

ROLE="${ROLE:-client}"
SERVER_IP="${SERVER_IP:-192.168.76.143}"

echo "[wg_hybrid] Starting role=$ROLE"

if [[ "$ROLE" == "server" ]]; then
    echo "[wg_hybrid] Starting Rosenpass + WireGuard (server mode)"
    
    exec rp exchange \
        public-key /data/wg_hybrid/server/server.rosenpass-public \
        secret-key /data/wg_hybrid/server/server.rosenpass-secret \
        listen 0.0.0.0:9999 \
        peer \
        public-key /data/wg_hybrid/server/client.rosenpass-public \
        outfile /tmp/rosenpass.psk \
        wireguard wg1
else
    echo "[wg_hybrid] Starting Rosenpass + WireGuard (client mode)"
    
    exec rp exchange \
        public-key /data/wg_hybrid/client/client.rosenpass-public \
        secret-key /data/wg_hybrid/client/client.rosenpass-secret \
        peer \
        public-key /data/wg_hybrid/client/server.rosenpass-public \
        endpoint ${SERVER_IP}:9999 \
        outfile /tmp/rosenpass.psk \
        wireguard wg1
fi
