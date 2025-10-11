#!/usr/bin/env bash
set -euo pipefail

ROLE="${ROLE:-client}"               
LOG="/var/log/strongswan.log"

sync_role_configs() {
  local role="$1"

  mkdir -p /etc/strongswan
  mkdir -p /etc/swanctl/{x509ca,x509,private}

  if [ -f "/data/ipsec_classic/${role}/strongswan.conf" ]; then
    cp -f "/data/ipsec_classic/${role}/strongswan.conf" /etc/strongswan/strongswan.conf
  fi

  if [ -f "/data/ipsec_classic/${role}/swanctl.conf" ]; then
    cp -f "/data/ipsec_classic/${role}/swanctl.conf" /etc/swanctl/swanctl.conf
  fi

  cp -f /data/ipsec_classic/${role}/pki/cacerts/*   /etc/swanctl/x509ca/  2>/dev/null || true
  cp -f /data/ipsec_classic/${role}/pki/certs/*     /etc/swanctl/x509/    2>/dev/null || true
  cp -f /data/ipsec_classic/${role}/pki/private/*   /etc/swanctl/private/ 2>/dev/null || true
  chmod 600 /etc/swanctl/private/* 2>/dev/null || true
}

: > "$LOG"
sync_role_configs "$ROLE"

 /usr/lib/ipsec/charon &

for t in $(seq 1 60); do
  if [ -S /var/run/charon.vici ]; then break; fi
  sleep 0.2
done

for t in $(seq 1 5); do
  if swanctl --load-all; then break; fi
  sleep 0.5
done

if [ "$ROLE" = "server" ]; then
  ip addr add 10.30.0.1/32 dev lo 2>/dev/null || true
else
  ip addr add 10.30.0.2/32 dev lo 2>/dev/null || true
fi


if [ "$ROLE" = "client" ]; then
  swanctl --initiate --child net || true
fi

exec tail -F "$LOG"
