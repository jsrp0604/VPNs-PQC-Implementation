#!/usr/bin/env bash
set -euo pipefail

echo "[setup] Generating Rosenpass keys"

sudo rm -rf /data/wg_hybrid
sudo mkdir -p /data/wg_hybrid/{server,client}

# Generate server keys
echo "[setup] Server keys..."
sudo docker run --rm --entrypoint "" \
  -v /data/wg_hybrid/server:/workdir \
  -w /workdir \
  wg_hybrid:local \
  rp gen-keys --public-key server.rosenpass-public --secret-key server.rosenpass-secret

# Generate client keys
echo "[setup] Client keys..."
sudo docker run --rm --entrypoint "" \
  -v /data/wg_hybrid/client:/workdir \
  -w /workdir \
  wg_hybrid:local \
  rp gen-keys --public-key client.rosenpass-public --secret-key client.rosenpass-secret

# Exchange public keys
echo "[setup] Exchanging public keys..."
sudo cp /data/wg_hybrid/server/server.rosenpass-public /data/wg_hybrid/client/
sudo cp /data/wg_hybrid/client/client.rosenpass-public /data/wg_hybrid/server/

echo "[setup] ✓ Rosenpass keys generated"
tree /data/wg_hybrid/
