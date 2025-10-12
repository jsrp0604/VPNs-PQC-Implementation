#!/usr/bin/env bash
set -euo pipefail

BASE="/data/ovpn_hybrid/transport"
mkdir -p "$BASE"/{server,client}

openssl ecparam -name prime256v1 -genkey -out "$BASE/ca-key.pem"
openssl req -new -x509 -key "$BASE/ca-key.pem" \
  -out "$BASE/ca-cert.pem" -days 3650 -sha256 \
  -subj "/C=EC/O=VPN-Lab/CN=PQ-TLS-CA"

cat > "$BASE/server-ext.cnf" <<'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
[req_distinguished_name]
[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = IP:192.168.76.143
EOF

openssl ecparam -name prime256v1 -genkey -out "$BASE/server/key.pem"
openssl req -new -key "$BASE/server/key.pem" \
  -out "$BASE/server/csr.pem" -sha256 \
  -subj "/C=EC/O=VPN-Lab/CN=vpn-server" \
  -config "$BASE/server-ext.cnf"
  
openssl x509 -req -in "$BASE/server/csr.pem" \
  -CA "$BASE/ca-cert.pem" -CAkey "$BASE/ca-key.pem" \
  -CAcreateserial -out "$BASE/server/cert.pem" \
  -days 1825 -sha256 \
  -extfile "$BASE/server-ext.cnf" -extensions v3_req

cat > "$BASE/client-ext.cnf" <<'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
[req_distinguished_name]
[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = clientAuth
EOF

openssl ecparam -name prime256v1 -genkey -out "$BASE/client/key.pem"
openssl req -new -key "$BASE/client/key.pem" \
  -out "$BASE/client/csr.pem" -sha256 \
  -subj "/C=EC/O=VPN-Lab/CN=vpn-client" \
  -config "$BASE/client-ext.cnf"
  
openssl x509 -req -in "$BASE/client/csr.pem" \
  -CA "$BASE/ca-cert.pem" -CAkey "$BASE/ca-key.pem" \
  -CAcreateserial -out "$BASE/client/cert.pem" \
  -days 1825 -sha256 \
  -extfile "$BASE/client-ext.cnf" -extensions v3_req

cp "$BASE/ca-cert.pem" "$BASE/server/ca.pem"
cp "$BASE/ca-cert.pem" "$BASE/client/ca.pem"

chmod 600 "$BASE"/server/key.pem "$BASE"/client/key.pem

echo "[pqtls-certs] Generated ECDSA P-256 certificates in $BASE"
ls -lh "$BASE"/{server,client}/