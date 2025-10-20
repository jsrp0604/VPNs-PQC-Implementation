#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

BASE="/data/ipsec_hybrid"
SRV="$BASE/server/pki"
CLI="$BASE/client/pki"

mkdir -p "$SRV/"{cacerts,certs,private} "$CLI/"{cacerts,certs,private}

echo "[ipsec_hybrid_pki] Generating certificates for IPsec hybrid implementation"
echo "[ipsec_hybrid_pki] Using ECDSA P-256 (classical signatures)"
echo "[ipsec_hybrid_pki] ML-KEM will be used for IKEv2 key exchange"

echo "[ipsec_hybrid_pki] 1/3 Generating CA..."
ipsec pki --gen --type ecdsa --size 256 --outform pem > "$SRV/private/ca.key"
ipsec pki --self --ca --lifetime 3650 \
  --in "$SRV/private/ca.key" --type ecdsa \
  --dn "CN=ipsec-hybrid-ca" \
  --outform pem > "$SRV/cacerts/ca.crt"

cp "$SRV/cacerts/ca.crt" "$CLI/cacerts/ca.crt"
echo "[ipsec_hybrid_pki] CA certificate: $SRV/cacerts/ca.crt"

echo "[ipsec_hybrid_pki] 2/3 Generating server certificate..."
ipsec pki --gen --type ecdsa --size 256 --outform pem > "$SRV/private/server.key"
ipsec pki --pub --in "$SRV/private/server.key" --type ecdsa \
  | ipsec pki --issue --lifetime 1825 \
    --cacert "$SRV/cacerts/ca.crt" \
    --cakey "$SRV/private/ca.key" \
    --dn "C=EC, O=VPN-PQC, CN=ipsec-hybrid-server" \
    --san "ipsec-hybrid-server" \
    --flag serverAuth --flag ikeIntermediate \
    --outform pem > "$SRV/certs/server.crt"
echo "[ipsec_hybrid_pki] Server certificate: $SRV/certs/server.crt"

echo "[ipsec_hybrid_pki] 3/3 Generating client certificate..."
ipsec pki --gen --type ecdsa --size 256 --outform pem > "$CLI/private/client.key"
ipsec pki --pub --in "$CLI/private/client.key" --type ecdsa \
  | ipsec pki --issue --lifetime 1825 \
    --cacert "$SRV/cacerts/ca.crt" \
    --cakey "$SRV/private/ca.key" \
    --dn "C=EC, O=VPN-PQC, CN=ipsec-hybrid-client" \
    --san "ipsec-hybrid-client" \
    --flag clientAuth --flag ikeIntermediate \
    --outform pem > "$CLI/certs/client.crt"
echo "[ipsec_hybrid_pki] Client certificate: $CLI/certs/client.crt"

chmod 600 "$SRV/private/ca.key" "$SRV/private/server.key" "$CLI/private/client.key"

echo "[ipsec_hybrid_pki] Certificate generation complete"
echo ""
echo "Summary:"
echo "  CA:     $SRV/cacerts/ca.crt"
echo "  Server: $SRV/certs/server.crt + $SRV/private/server.key"
echo "  Client: $CLI/certs/client.crt + $CLI/private/client.key"
echo ""
echo "Note: Using ECDSA P-256 for signatures (classical)"
echo "      ML-KEM-768 will be negotiated during IKEv2 handshake"