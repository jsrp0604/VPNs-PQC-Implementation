#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

BASE="/data/ipsec_hybrid"
SRV="$BASE/server/pki"
CLI="$BASE/client/pki"

mkdir -p "$SRV/"{cacerts,certs,private} "$CLI/"{cacerts,certs,private}

ipsec pki --gen --type ecdsa --size 256 --outform pem > "$SRV/private/ca.key"
ipsec pki --self --ca --lifetime 3650 \
  --in "$SRV/private/ca.key" --type ecdsa \
  --dn "CN=ipsec-hybrid-ca" \
  --outform pem > "$SRV/cacerts/ca.crt"

cp "$SRV/cacerts/ca.crt" "$CLI/cacerts/ca.crt"

ipsec pki --gen --type ecdsa --size 256 --outform pem > "$SRV/private/server.key"
ipsec pki --pub --in "$SRV/private/server.key" --type ecdsa \
  | ipsec pki --issue --lifetime 1825 \
    --cacert "$SRV/cacerts/ca.crt" \
    --cakey "$SRV/private/ca.key" \
    --dn "C=EC, O=VPN-PQC, CN=ipsec-hybrid-server" \
    --san "ipsec-hybrid-server" \
    --flag serverAuth --flag ikeIntermediate \
    --outform pem > "$SRV/certs/server.crt"

ipsec pki --gen --type ecdsa --size 256 --outform pem > "$CLI/private/client.key"
ipsec pki --pub --in "$CLI/private/client.key" --type ecdsa \
  | ipsec pki --issue --lifetime 1825 \
    --cacert "$SRV/cacerts/ca.crt" \
    --cakey "$SRV/private/ca.key" \
    --dn "C=EC, O=VPN-PQC, CN=ipsec-hybrid-client" \
    --san "ipsec-hybrid-client" \
    --flag clientAuth --flag ikeIntermediate \
    --outform pem > "$CLI/certs/client.crt"

chmod 600 "$SRV/private/ca.key" "$SRV/private/server.key" "$CLI/private/client.key"