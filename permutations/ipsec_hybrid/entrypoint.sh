#!/usr/bin/env bash
set -euo pipefail

ROLE="${ROLE:-client}"
LOG="/var/log/strongswan.log"

sync_role_configs() {
  local role="$1"
  
  mkdir -p /etc/strongswan /etc/swanctl/{x509ca,x509,private}
  
  if [ -f "/data/ipsec_hybrid/${role}/strongswan.conf" ]; then
    cp -f "/data/ipsec_hybrid/${role}/strongswan.conf" /etc/strongswan/strongswan.conf
  fi
  
  if [ -f "/data/ipsec_hybrid/${role}/swanctl.conf" ]; then
    cp -f "/data/ipsec_hybrid/${role}/swanctl.conf" /etc/swanctl/swanctl.conf
  fi
  
  cp -f /data/ipsec_hybrid/${role}/pki/cacerts/* /etc/swanctl/x509ca/ 2>/dev/null || true
  cp -f /data/ipsec_hybrid/${role}/pki/certs/* /etc/swanctl/x509/ 2>/dev/null || true
  cp -f /data/ipsec_hybrid/${role}/pki/private/* /etc/swanctl/private/ 2>/dev/null || true
  
  chmod 600 /etc/swanctl/private/* 2>/dev/null || true  
}

: > "$LOG"
sync_role_configs "$ROLE"

echo "[ipsec_hybrid] Starting charon daemon" | tee -a "$LOG"
/usr/libexec/ipsec/charon &

for t in $(seq 1 60); do
  if [ -S /var/run/charon.vici ]; then
    echo "[ipsec_hybrid] charon daemon ready" | tee -a "$LOG"
    break
  fi
  sleep 0.2
done

if [ ! -S /var/run/charon.vici ]; then
  echo "[ipsec_hybrid] FATAL: charon.vici socket not found after 12s" | tee -a "$LOG"
  exit 1
fi

for t in $(seq 1 5); do
  if swanctl --load-all 2>&1 | tee -a "$LOG"; then
    echo "[ipsec_hybrid] Configuration loaded" | tee -a "$LOG"
    break
  fi
  echo "[ipsec_hybrid] Retry $t/5" | tee -a "$LOG"
  sleep 0.5
done

if swanctl --list-algs 2>/dev/null | grep -q "ML_KEM"; then
    echo "[ipsec_hybrid] ML-KEM algorithms available:" | tee -a "$LOG"
    swanctl --list-algs | grep "ML_KEM" | sed 's/^/  /' | tee -a "$LOG"
else
    echo "[ipsec_hybrid] WARNING: ML-KEM not found in available algorithms" | tee -a "$LOG"
    echo "[ipsec_hybrid] Available DH groups:" | tee -a "$LOG"
    swanctl --list-algs 2>/dev/null | grep "MODP\|ECP\|CURVE" | head -10 | sed 's/^/  /' | tee -a "$LOG"
fi

if [ "$ROLE" = "server" ]; then
  ip addr add 10.30.0.1/32 dev lo 2>/dev/null || true
  echo "[ipsec_hybrid] Server tunnel IP: 10.30.0.1" | tee -a "$LOG"
else
  ip addr add 10.30.0.2/32 dev lo 2>/dev/null || true
  echo "[ipsec_hybrid] Client tunnel IP: 10.30.0.2" | tee -a "$LOG"
fi

echo "[ipsec_hybrid] Loaded connections:" | tee -a "$LOG"
swanctl --list-conns 2>&1 | sed 's/^/  /' | tee -a "$LOG"

echo "[ipsec_hybrid] Monitoring logs" | tee -a "$LOG"
exec tail -F "$LOG"