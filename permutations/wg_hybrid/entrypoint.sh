#!/usr/bin/env bash
set -euo pipefail

ROLE="${ROLE:-client}"
SERVER_IP="${SERVER_IP:-192.168.76.143}"

if [[ "$ROLE" == "server" ]]; then
    ip link del wg1 2>/dev/null || true
    
    if [[ ! -f /data/wg_hybrid/server/wg_private.key ]]; then
        wg genkey | tee /data/wg_hybrid/server/wg_private.key | wg pubkey > /data/wg_hybrid/server/wg_public.key
    fi
    
    ip link add wg1 type wireguard
    ip addr add 10.31.0.1/24 dev wg1
    wg set wg1 listen-port 10000 private-key /data/wg_hybrid/server/wg_private.key
    
    if [[ -f /data/wg_hybrid/client/wg_public.key ]]; then
        CLIENT_WG_PUB=$(cat /data/wg_hybrid/client/wg_public.key)
        wg set wg1 peer "$CLIENT_WG_PUB" allowed-ips 10.31.0.2/32
    else
        echo "[wg_hybrid] WARNING: Client WG public key not found!"
    fi
    
    ip link set wg1 up
    
    echo "[wg_hybrid] Starting Rosenpass PSK updater"
    
    rp exchange \
        public-key /data/wg_hybrid/server/server.rosenpass-public \
        secret-key /data/wg_hybrid/server/server.rosenpass-secret \
        listen 0.0.0.0:9999 \
        peer \
        public-key /data/wg_hybrid/server/client.rosenpass-public \
        outfile /tmp/wg1.psk &
    
    RP_PID=$!
    
    while true; do
        sleep 2
        if [[ -f /tmp/wg1.psk ]] && [[ -n "${CLIENT_WG_PUB:-}" ]]; then
            wg set wg1 peer "$CLIENT_WG_PUB" preshared-key /tmp/wg1.psk 2>/dev/null || true
        fi
    done
else    
    ip link del wg1 2>/dev/null || true
    
    if [[ ! -f /data/wg_hybrid/client/wg_private.key ]]; then
        wg genkey | tee /data/wg_hybrid/client/wg_private.key | wg pubkey > /data/wg_hybrid/client/wg_public.key
    fi
    
    ip link add wg1 type wireguard
    ip addr add 10.31.0.2/24 dev wg1
    wg set wg1 private-key /data/wg_hybrid/client/wg_private.key
    
    if [[ -f /data/wg_hybrid/server/wg_public.key ]]; then
        SERVER_WG_PUB=$(cat /data/wg_hybrid/server/wg_public.key)
        wg set wg1 peer "$SERVER_WG_PUB" endpoint ${SERVER_IP}:10000 allowed-ips 10.31.0.1/32 persistent-keepalive 25
    else
        echo "[wg_hybrid] WARNING: Server WG public key not found!"
    fi
    
    ip link set wg1 up
    
    echo "[wg_hybrid] Starting Rosenpass PSK updater"
    
    rp exchange \
        public-key /data/wg_hybrid/client/client.rosenpass-public \
        secret-key /data/wg_hybrid/client/client.rosenpass-secret \
        peer \
        public-key /data/wg_hybrid/client/server.rosenpass-public \
        endpoint ${SERVER_IP}:9999 \
        outfile /tmp/wg1.psk &
    
    RP_PID=$!
    
    while true; do
        sleep 2
        if [[ -f /tmp/wg1.psk ]] && [[ -n "${SERVER_WG_PUB:-}" ]]; then
            wg set wg1 peer "$SERVER_WG_PUB" preshared-key /tmp/wg1.psk 2>/dev/null || true
        fi
    done
fi
