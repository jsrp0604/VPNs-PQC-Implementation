#!/usr/bin/env bash
set -euo pipefail

ROOT="/data/ovpn_classic"
EASYRSA_SRC="/usr/share/easy-rsa"         
EASYRSA_WORK="$ROOT/easyrsa"              

if ! command -v openvpn >/dev/null 2>&1 || [ ! -d "$EASYRSA_SRC" ]; then
  sudo apt-get update -y
  sudo apt-get install -y openvpn easy-rsa
fi

mkdir -p "$EASYRSA_WORK"
if [ ! -x "$EASYRSA_WORK/easyrsa" ]; then
  sudo cp -a "$EASYRSA_SRC/." "$EASYRSA_WORK/"
  sudo chmod +x "$EASYRSA_WORK/easyrsa"
fi

cd "$EASYRSA_WORK"

export EASYRSA_BATCH=1

cat > vars <<'EOF'
set_var EASYRSA_BATCH "1"
set_var EASYRSA_REQ_CN  "ovpn-ca"
EOF

if [ -d pki ]; then
  rm -rf pki
fi

./easyrsa init-pki
./easyrsa build-ca nopass
./easyrsa build-server-full server nopass
./easyrsa build-client-full client nopass

openvpn --genkey secret ta.key

install -d "$ROOT/server/pki/issued" "$ROOT/server/pki/private" \
           "$ROOT/client/pki/issued" "$ROOT/client/pki/private"

install -m 0644 pki/ca.crt                       "$ROOT/server/pki/ca.crt"
install -m 0644 pki/issued/server.crt            "$ROOT/server/pki/issued/server.crt"
install -m 0600 pki/private/server.key           "$ROOT/server/pki/private/server.key"

install -m 0644 pki/ca.crt                       "$ROOT/client/pki/ca.crt"
install -m 0644 pki/issued/client.crt            "$ROOT/client/pki/issued/client.crt"
install -m 0600 pki/private/client.key           "$ROOT/client/pki/private/client.key"

install -m 0600 ta.key                           "$ROOT/server/ta.key"
install -m 0600 ta.key                           "$ROOT/client/ta.key"