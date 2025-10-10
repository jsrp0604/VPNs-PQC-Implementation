#!/usr/bin/env bash
set -euo pipefail

ROLE="${ROLE:-client}"       
LOG="/var/log/strongswan.log"

sync_role_configs() {
  local role="$1"
  mkdir -p /etc/swanctl/x509ca /etc/swanctl/x509 /etc/swanctl/private
  mkdir -p /etc/strongswan
  cp -f "/data/ipsec_classic/${role}/strongswan.conf" /etc/strongswan/strongswan.conf

  cp -f "/data/ipsec_classic/${role}/swanctl.conf" /etc/swanctl/swanctl.conf
  cp -f "/data/ipsec_classic/${role}/pki/cacerts/"* /etc/swanctl/x509ca/ 2>/dev/null || true
  test -f "/data/ipsec_classic/${role}/pki/certs/${role}.crt" && cp -f "/data/ipsec_classic/${role}/pki/certs/${role}.crt" /etc/swanctl/x509/
  test -f "/data/ipsec_classic/${role}/pki/certs/server.crt" && cp -f "/data/ipsec_classic/${role}/pki/certs/server.crt" /etc/swanctl/x509/
  test -f "/data/ipsec_classic/${role}/pki/certs/client.crt" && cp -f "/data/ipsec_classic/${role}/pki/certs/client.crt" /etc/swanctl/x509/

  test -f "/data/ipsec_classic/${role}/pki/private/${role}.key" && cp -f "/data/ipsec_classic/${role}/pki/private/${role}.key" /etc/swanctl/private/
  test -f "/data/ipsec_classic/${role}/pki/private/server.key" && cp -f "/data/ipsec_classic/${role}/pki/private/server.key" /etc/swanctl/private/
  test -f "/data/ipsec_classic/${role}/pki/private/client.key" && cp -f "/data/ipsec_classic/${role}/pki/private/client.key" /etc/swanctl/private/

  chmod 600 /etc/swanctl/private/*.key 2>/dev/null || true
}

trap 'swanctl --terminate 2>/dev/null || true; pkill -TERM -x charon 2>/dev/null || true' EXIT INT TERM

: > "$LOG"
sync_role_configs "$ROLE"

/usr/lib/ipsec/charon &   
sleep 0.5
swanctl --load-all

if [ "$ROLE" = "client" ]; then
  swanctl --initiate --child net || true
fi

exec tail -F "$LOG"
