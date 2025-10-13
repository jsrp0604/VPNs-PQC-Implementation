#!/usr/bin/env bash
set -euo pipefail
export LC_NUMERIC=C

SERVER_TUN_IP="${1:-10.20.0.1}"
COUNT="${2:-100}"
PROFILE="${3:-realistic}"
THRU_EVERY="${4:-50}"
IPERF_TIME="${5:-5}"

CSV="/data/metrics.csv"
KEM="${KEM:-X25519-MLKEM768}"
SIG="${SIG:-ECDSA-P256}"
SCHEME="${SCHEME:-proxy_pq}"
PROTOCOL="OpenVPN"
CLIENT_CONT_OVPN="${CLIENT_CONT_OVPN:-ovpn_cli_hybrid}"
CLIENT_CONT_PROXY="${CLIENT_CONT_PROXY:-pqtls_cli}"
SERVER_IP="${SERVER_IP:-192.168.76.143}"

[[ -f "$CSV" ]] || echo "timestamp,protocol,scheme,kem,signature,client_ip,server_ip,cond_profile,latency_ms,handshake_ms,throughput_mbps,cpu_pct,mem_mb,sign_ms,verify_ms,encap_ms,decap_ms,packet_loss_pct,energy_joules" >> "$CSV"

echo "[loop] $PROTOCOL/$SCHEME  KEM=$KEM SIG=$SIG  count=$COUNT profile=$PROFILE"

for i in $(seq 1 "$COUNT"); do
  sudo docker stop "$CLIENT_CONT_OVPN" "$CLIENT_CONT_PROXY" 2>/dev/null || true
  sleep 0.5
  
  START_NS="$(date +%s%N)"
  
  sudo docker run -d --rm --name "$CLIENT_CONT_PROXY" --network host \
    -v /data/ovpn_hybrid/transport:/certs:ro \
    -v /data/ovpn_hybrid:/config:ro \
    -e OPENSSL_CONF=/config/openssl-pqtls.cnf \
    -e OPENSSL_MODULES=/usr/local/lib/ossl-modules \
    pqtls_proxy:local \
    socat -d -d TCP-LISTEN:1194,reuseaddr,fork \
      OPENSSL:${SERVER_IP}:1194,cert=/certs/client/cert.pem,key=/certs/client/key.pem,cafile=/certs/client/ca.pem,verify=1,openssl-min-proto-version=TLS1.3 \
    >/dev/null 2>&1
  
  sleep 2
  
  sudo docker run -d --rm --name "$CLIENT_CONT_OVPN" --network host \
    --cap-add NET_ADMIN --device /dev/net/tun --entrypoint openvpn \
    -v /data/ovpn_classic/client/pki:/pki:ro \
    -v /data/ovpn_hybrid/client:/config:ro \
    ovpn_classic:latest \
    --config /config/client_tcp.conf \
    >/dev/null 2>&1
  
  HANDSHAKE_MS="NA"
  for t in $(seq 1 150); do
    if ip addr show tun0 2>/dev/null | grep -q "inet "; then
      if ping -c1 -W1 "$SERVER_TUN_IP" >/dev/null 2>&1; then
        END_NS="$(date +%s%N)"
        HANDSHAKE_MS="$(awk -v s="$START_NS" -v e="$END_NS" 'BEGIN{printf "%.2f", (e-s)/1000000}')"
        break
      fi
    fi
    sleep 0.1
  done
  
  CLIENT_IP="$(ip -4 -o addr show tun0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || echo NA)"
  
  PINGN="$(ping -c5 -i 0.2 -W2 "$SERVER_TUN_IP" 2>/dev/null || true)"
  LAT="$(echo "$PINGN" | awk -F'/' '/^rtt/ {print $5}')"; [[ -z "$LAT" ]] && LAT="NA"
  LOSS="$(echo "$PINGN" | sed -n 's/.* \([0-9.]\+\)% packet loss.*/\1/p')"; [[ -z "$LOSS" ]] && LOSS="NA"
  
  THR="NA"; CPU="NA"; MEM="NA"
  if (( THRU_EVERY > 0 )) && (( i % THRU_EVERY == 0 )) && [[ "$CLIENT_IP" != "NA" ]]; then
    TMP_JSON="$(mktemp)"; TMP_TIME="$(mktemp)"
    /usr/bin/time -v -o "$TMP_TIME" \
      iperf3 -c "$SERVER_TUN_IP" -B "$CLIENT_IP" -t "$IPERF_TIME" --json > "$TMP_JSON" 2>/dev/null || true
    
    BPS="$(jq -r '.end.sum_received.bits_per_second // .end.sum_sent.bits_per_second // empty' "$TMP_JSON" 2>/dev/null || true)"
    [[ -n "${BPS:-}" ]] && THR="$(awk -v b="$BPS" 'BEGIN{printf "%.2f", b/1000000}')"
    
    CPU="$(awk -F': ' '/Percent of CPU/ {gsub("%","",$2); print $2}' "$TMP_TIME" 2>/dev/null || true)"
    [[ -z "$CPU" ]] && CPU="NA"
    
    RSS="$(awk -F': ' '/Maximum resident set size/ {print $2}' "$TMP_TIME" 2>/dev/null || true)"
    [[ -n "$RSS" ]] && MEM="$(awk -v k="$RSS" 'BEGIN{printf "%.2f", k/1024}')" || MEM="NA"
    
    rm -f "$TMP_JSON" "$TMP_TIME"
  fi
  
  NOW="$(date -Iseconds)"
  echo "$NOW,$PROTOCOL,$SCHEME,$KEM,$SIG,$CLIENT_IP,$SERVER_TUN_IP,$PROFILE,$LAT,$HANDSHAKE_MS,$THR,$CPU,$MEM,NA,NA,NA,NA,$LOSS,NA" >> "$CSV"
  
  sleep 0.3
done

echo "[loop] Logged $COUNT rows to $CSV"
