#!/usr/bin/env bash
set -euo pipefail

ROLE="${ROLE:-client}"
CONF_DIR="/data/ovpn_hybrid/${ROLE}"
CONF_FILE="${CONF_DIR}/$( [ "$ROLE" = "server" ] && echo server.conf || echo client.conf )"
LOG_DIR="/var/log"
LOG="${LOG_DIR}/ovpn_${ROLE}.log"
mkdir -p "$LOG_DIR"
: > "$LOG"

echo "[entrypoint] OpenSSL providers:" | tee -a "$LOG"
openssl list -providers 2>&1 | tee -a "$LOG" || true

echo "[entrypoint] TLS 1.3 groups (default provider):" | tee -a "$LOG"
openssl list -groups 2>&1 | tee -a "$LOG" || true

echo "[entrypoint] TLS 1.3 groups (oqsprovider):" | tee -a "$LOG"
openssl list -groups -provider oqsprovider 2>&1 | tee -a "$LOG" || true

GROUP_CANDIDATES=("X25519:kyber768" "x25519_kyber768" "p256_kyber768" "P-256:kyber768")
SELECTED_GROUP=""
for g in "${GROUP_CANDIDATES[@]}"; do
  if openssl list -groups -provider oqsprovider 2>/dev/null | grep -q "$g"; then
    SELECTED_GROUP="$g"; break
  fi
done

if [[ -z "$SELECTED_GROUP" ]]; then
  echo "[entrypoint][WARN] No known X25519/Kyber768 hybrid group found in oqsprovider; continuing anyway." | tee -a "$LOG"
fi

if [[ ! -f "$CONF_FILE" ]]; then
  echo "[entrypoint][FATAL] Missing $CONF_FILE" | tee -a "$LOG"
  exit 22
fi

EXTRA_ARGS=()
if [[ -n "$SELECTED_GROUP" ]]; then
  EXTRA_ARGS+=( "--tls-groups" "$SELECTED_GROUP" )
fi

exec openvpn \
  --config "$CONF_FILE" \
  --log-append "$LOG" \
  --status /tmp/openvpn_status 10 \
  "${EXTRA_ARGS[@]:-}"
