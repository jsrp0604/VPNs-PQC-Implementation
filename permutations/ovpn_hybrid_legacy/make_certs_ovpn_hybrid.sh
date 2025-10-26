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

# Activate OQS provider via a temp openssl.cnf (works reliably on OpenSSL 3.0.x)
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

echo "[mkcerts] OPENSSL_MODULES=${OPENSSL_MODULES}"
echo "[mkcerts] LD_LIBRARY_PATH=${LD_LIBRARY_PATH}"
echo "[mkcerts] OPENSSL_CONF=${OPENSSL_CONF}"
ossl list -providers | sed 's/^/  /' || true

# --- choose signature algorithm by actually *trying* to gen a key ---
try_algs=( "mldsa44" "dilithium2" "oqs_sig_dilithium_2" )
SIG_ALG=""

for alg in "${try_algs[@]}"; do
  echo "[mkcerts] Probing keygen with: $alg"
  if ossl genpkey -algorithm "$alg" -out "$SRV/.probe.key" >/dev/null 2>&1; then
    SIG_ALG="$alg"
    rm -f "$SRV/.probe.key"
    break
  fi
done

if [[ -z "$SIG_ALG" ]]; then
  echo "[err] Could not generate a key with any of: ${try_algs[*]}"
  echo "      Available public-key algs (truncated to PQ keywords):"
  ossl list -public-key-algorithms 2>/dev/null | grep -Ei 'mldsa|dilith|falcon|sphincs|mayo|mlkem|kyber|bikel|frodo|snova|ov_|cross' || true
  rm -f "$OPENSSL_OQS_CNF"
  exit 1
fi

echo "[mkcerts] Using signature algorithm: ${SIG_ALG}"

# 1) Root CA
ossl genpkey -algorithm "${SIG_ALG}" -out "$SRV/ca.key"
ossl req -new -x509 -key "$SRV/ca.key" -subj "/CN=ovpn-hybrid-ca" \
  -out "$SRV/ca.crt" -days 3650 -sha256
install -m 0644 "$SRV/ca.crt" "$CLI/ca.crt"

# 2) Server EE
ossl genpkey -algorithm "${SIG_ALG}" -out "$SRV/server.key"
ossl req -new -key "$SRV/server.key" -subj "/CN=ovpn-hybrid-server" -out "$SRV/server.csr"
ossl x509 -req -in "$SRV/server.csr" -CA "$SRV/ca.crt" -CAkey "$SRV/ca.key" \
  -CAcreateserial -out "$SRV/server.crt" -days 1825 -sha256

# 3) Client EE
ossl genpkey -algorithm "${SIG_ALG}" -out "$CLI/client.key"
ossl req -new -key "$CLI/client.key" -subj "/CN=ovpn-hybrid-client" -out "$CLI/client.csr"
ossl x509 -req -in "$CLI/client.csr" -CA "$SRV/ca.crt" -CAkey "$SRV/ca.key" \
  -CAcreateserial -out "$CLI/client.crt" -days 1825 -sha256

echo "[mkcerts] Wrote:"
ls -l "$SRV" "$CLI"

rm -f "$OPENSSL_OQS_CNF"
