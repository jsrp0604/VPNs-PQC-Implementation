#!/usr/bin/env bash
set -euo pipefail

echo "[config] Generating WireGuard keys"

# Generate WireGuard server keys
sudo docker run --rm --entrypoint "" \
  -v /data/wg_hybrid/server:/keys \
  -w /keys \
  wg_hybrid:local \
  sh -c 'wg genkey > wg_private.key && cat wg_private.key | wg pubkey > wg_public.key'

# Generate WireGuard client keys
sudo docker run --rm --entrypoint "" \
  -v /data/wg_hybrid/client:/keys \
  -w /keys \
  wg_hybrid:local \
  sh -c 'wg genkey > wg_private.key && cat wg_private.key | wg pubkey > wg_public.key'

echo "[config] WireGuard keys generated"
sudo ls -lh /data/wg_hybrid/server/wg_*.key
sudo ls -lh /data/wg_hybrid/client/wg_*.key

# Read keys for config generation
SERVER_WG_PRIV=$(sudo cat /data/wg_hybrid/server/wg_private.key)
SERVER_WG_PUB=$(sudo cat /data/wg_hybrid/server/wg_public.key)
CLIENT_WG_PRIV=$(sudo cat /data/wg_hybrid/client/wg_private.key)
CLIENT_WG_PUB=$(sudo cat /data/wg_hybrid/client/wg_public.key)

echo "[config] Creating WireGuard config files"

# Server WireGuard config - DIFFERENT SUBNET (10.31.x.x instead of 10.30.x.x)
sudo tee /data/wg_hybrid/server/wg1.conf > /dev/null <<WGCONF
[Interface]
PrivateKey = ${SERVER_WG_PRIV}
Address = 10.31.0.1/24
ListenPort = 51821

[Peer]
PublicKey = ${CLIENT_WG_PUB}
AllowedIPs = 10.31.0.2/32
WGCONF

# Client WireGuard config - DIFFERENT SUBNET
sudo tee /data/wg_hybrid/client/wg1.conf > /dev/null <<WGCONF
[Interface]
PrivateKey = ${CLIENT_WG_PRIV}
Address = 10.31.0.2/24

[Peer]
PublicKey = ${SERVER_WG_PUB}
Endpoint = 192.168.76.143:51821
AllowedIPs = 10.31.0.1/32
PersistentKeepalive = 25
WGCONF

sudo chmod 600 /data/wg_hybrid/server/wg_private.key /data/wg_hybrid/client/wg_private.key

echo "[config] ✓ WireGuard configs created with subnet 10.31.0.0/24"
tree /data/wg_hybrid/
