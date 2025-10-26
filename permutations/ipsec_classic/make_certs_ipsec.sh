#!/usr/bin/env bash
set -euo pipefail

BASE="/data/ipsec_classic"
mkdir -p "$BASE/server/pki/"{cacerts,certs,private} "$BASE/client/pki/"{cacerts,certs,private}

# CA
ipsec pki --gen --type rsa --size 2048 --outform pem > "$BASE/server/pki/private/ca.key"
ipsec pki --self --ca --lifetime 3650 --in "$BASE/server/pki/private/ca.key" --type rsa \
  --dn "CN=ipsec-ca" --outform pem > "$BASE/server/pki/cacerts/ca.crt"
cp "$BASE/server/pki/cacerts/ca.crt" "$BASE/client/pki/cacerts/ca.crt"

# Server
ipsec pki --gen --type rsa --size 2048 --outform pem > "$BASE/server/pki/private/server.key"
ipsec pki --pub --in "$BASE/server/pki/private/server.key" --type rsa \
  | ipsec pki --issue --lifetime 1825 --cacert "$BASE/server/pki/cacerts/ca.crt" --cakey "$BASE/server/pki/private/ca.key" \
    --dn "C=XX, O=Lab, CN=server@lab" --san "server@lab" --flag serverAuth --outform pem > "$BASE/server/pki/certs/server.crt"

# Client
ipsec pki --gen --type rsa --size 2048 --outform pem > "$BASE/client/pki/private/client.key"
ipsec pki --pub --in "$BASE/client/pki/private/client.key" --type rsa \
  | ipsec pki --issue --lifetime 1825 --cacert "$BASE/server/pki/cacerts/ca.crt" --cakey "$BASE/server/pki/private/ca.key" \
    --dn "C=XX, O=Lab, CN=client@lab" --san "client@lab" --flag clientAuth --outform pem > "$BASE/client/pki/certs/client.crt"

chmod 600 "$BASE/server/pki/private/server.key" "$BASE/client/pki/private/client.key"
echo "[pki] done."
