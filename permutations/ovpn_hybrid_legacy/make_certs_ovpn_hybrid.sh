#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

BASE="/data/ovpn_hybrid"
SRV="$BASE/server/pki"
CLI="$BASE/client/pki"
mkdir -p "$SRV" "$CLI"

: "${OPENSSL_MODULES:=/usr/local/lib/ossl-modules}"
: "${LD_LIBRARY_PATH:=/usr/local/lib}"
export OPENSSL_MODULES LD_LIBRARY_PATH

OPENSSL_OQS_CNF="$(mktemp)"
cat >"$OPENSSL_OQS_CNF" <<CNF
openssl_conf = openssl_init
[openssl_init]
providers = provider_sect
[provider_sect]
default = default_sect
oqsprovider = oqs_sect
[default_sect]
activate = 1
[oqs_sect]
module = $OPENSSL_MODULES/oqsprovider.so
activate = 1
CNF
export OPENSSL_CONF="$OPENSSL_OQS_CNF"

ossl() { openssl "$@"; }

ossl list -providers | sed 's/^/  /' || true

try_algs=( "mldsa44" "dilithium2" "oqs_sig_dilithium_2" )
SIG_ALG=""

for alg in "${try_algs[@]}"; do
  if ossl genpkey -algorithm "$alg" -out "$SRV/.probe.key" >/dev/null 2>&1; then
    SIG_ALG="$alg"
    rm -f "$SRV/.probe.key"
    break
  fi
done

if [[ -z "$SIG_ALG" ]]; then
  ossl list -public-key-algorithms 2>/dev/null | grep -Ei 'mldsa|dilith|falcon|sphincs|mayo|mlkem|kyber|bikel|frodo|snova|ov_|cross' || true
  rm -f "$OPENSSL_OQS_CNF"
  exit 1
fi

# Root CA
ossl genpkey -algorithm "${SIG_ALG}" -out "$SRV/ca.key"
ossl req -new -x509 -key "$SRV/ca.key" -subj "/CN=ovpn-hybrid-ca" \
  -out "$SRV/ca.crt" -days 3650 -sha256
install -m 0644 "$SRV/ca.crt" "$CLI/ca.crt"

# Server EE
ossl genpkey -algorithm "${SIG_ALG}" -out "$SRV/server.key"
ossl req -new -key "$SRV/server.key" -subj "/CN=ovpn-hybrid-server" -out "$SRV/server.csr"
ossl x509 -req -in "$SRV/server.csr" -CA "$SRV/ca.crt" -CAkey "$SRV/ca.key" \
  -CAcreateserial -out "$SRV/server.crt" -days 1825 -sha256

# Client EE
ossl genpkey -algorithm "${SIG_ALG}" -out "$CLI/client.key"
ossl req -new -key "$CLI/client.key" -subj "/CN=ovpn-hybrid-client" -out "$CLI/client.csr"
ossl x509 -req -in "$CLI/client.csr" -CA "$SRV/ca.crt" -CAkey "$SRV/ca.key" \
  -CAcreateserial -out "$CLI/client.crt" -days 1825 -sha256

echo "[mkcerts] Wrote:"
ls -l "$SRV" "$CLI"

rm -f "$OPENSSL_OQS_CNF"
