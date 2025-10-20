#!/usr/bin/env bash
set -euo pipefail
export LC_NUMERIC=C

SERVER_TUN_IP="${1:-}"
COUNT="${2:-1000}"
PROFILE="${3:-realistic}"
THRU_EVERY="${4:-50}"
IPERF_TIME="${5:-5}"

KEM_LABEL="${KEM:-ECP384-MLKEM768}"
SIG_LABEL="${SIG:-ECDSA-P256}"
SCHEME="${SCHEME:-hybrid}"

CSV="/data/metrics.csv"
PROTOCOL="IPsec"
CLIENT_CONT="${CLIENT_CONT:-ipsec_hybrid_cli}"

[[ -n "$SERVER_TUN_IP" ]] || {
  echo "Usage: $0 <server_tun_ip> [count] [profile] [throughput_every] [iperf_time]"
  echo "Example: $0 10.30.0.1 1000 realistic 50 5"
  exit 1
}

[[ -f "$CSV" ]] || echo "timestamp,protocol,scheme,kem,signature,client_ip,server_ip,cond_profile,latency_ms,handshake_ms,throughput_mbps,cpu_pct,mem_mb,sign_ms,verify_ms,encap_ms,decap_ms,packet_loss_pct,energy_joules" >> "$CSV"

echo "[loop] IPsec hybrid handshakes: $COUNT | profile: $PROFILE"
echo "[loop] KEM: $KEM_LABEL | SIG: $SIG_LABEL | SCHEME: $SCHEME"
echo "[loop] throughput_every: $THRU_EVERY | iperf_time: ${IPERF_TIME}s"
echo "[loop] Method: Restart client container to force new IKE SA"

CLIENT_IP="10.30.0.2"

if ! sudo docker ps -a | grep -q "$CLIENT_CONT"; then
  echo "[loop] Creating initial client container..."
  sudo docker run -d --name "$CLIENT_CONT" \
    --privileged --network host \
    --cap-add=NET_ADMIN \
    --cap-add=NET_RAW \
    --device=/dev/net/tun \
    -e ROLE=client \
    -v /data:/data \
    ipsec_hybrid:local
  sleep 3
fi

for i in $(seq 1 "$COUNT"); do
  sudo docker stop "$CLIENT_CONT" >/dev/null 2>&1 || true
  sudo docker start "$CLIENT_CONT" >/dev/null 2>&1 || true
  sleep 3
    
  START_NS="$(date +%s%N)"
  HANDSHAKE_MS="NA"
  
  for t in $(seq 1 100); do
    if sudo docker exec "$CLIENT_CONT" ping -c1 -W1 -I 10.30.0.2 "$SERVER_TUN_IP" >/dev/null 2>&1; then
      END_NS="$(date +%s%N)"
      HANDSHAKE_MS="$(awk -v s="$START_NS" -v e="$END_NS" 'BEGIN{printf "%.2f", (e-s)/1000000}')"
      break
    fi
    sleep 0.2
  done
  
  if [[ "$HANDSHAKE_MS" != "NA" ]]; then
    echo -n "[loop][$i] hs:${HANDSHAKE_MS}ms"
  else
    echo -n "[loop][$i] FAIL"
  fi
  
  sudo docker exec "$CLIENT_CONT" ping -c2 -W1 -I 10.30.0.2 "$SERVER_TUN_IP" >/dev/null 2>&1 || true
  sleep 0.15
  
  PING5="$(sudo docker exec "$CLIENT_CONT" ping -c5 -i 0.3 -W2 -I 10.30.0.2 "$SERVER_TUN_IP" 2>/dev/null || true)"
  LAT="$(echo "$PING5" | awk -F'/' '/^rtt/ {print $5}')"
  [[ -z "$LAT" ]] && LAT="NA"
  LOSS="$(echo "$PING5" | sed -n 's/.* \([0-9.]\+\)% packet loss.*/\1/p')"
  [[ -z "$LOSS" ]] && LOSS="NA"
  
  [[ "$LAT" != "NA" ]] && echo -n " lat:${LAT}ms" || echo -n " lat:NA"
  
  THR="NA"; CPU="NA"; MEM="NA"
  if (( THRU_EVERY > 0 )) && (( i % THRU_EVERY == 0 )) && [[ "$HANDSHAKE_MS" != "NA" ]]; then
    TMP_JSON="$(mktemp)"
    TMP_TIME="$(mktemp)"
    
    /usr/bin/time -v -o "$TMP_TIME" \
      sudo docker exec "$CLIENT_CONT" sh -lc "iperf3 -c $SERVER_TUN_IP -B 10.30.0.2 -t $IPERF_TIME --json" > "$TMP_JSON" || true
    
    BPS="$(jq -r '.end.sum_received.bits_per_second // .end.sum_sent.bits_per_second // empty' "$TMP_JSON" 2>/dev/null || true)"
    [[ -n "${BPS:-}" ]] && THR="$(awk -v b="$BPS" 'BEGIN{printf "%.2f", b/1000000}')"
    
    CPU="$(awk -F': ' '/Percent of CPU/ {gsub("%","",$2); print $2}' "$TMP_TIME" 2>/dev/null || true)"
    [[ -z "$CPU" ]] && CPU="NA"
    
    RSS="$(awk -F': ' '/Maximum resident set size/ {print $2}' "$TMP_TIME" 2>/dev/null || true)"
    [[ -n "$RSS" ]] && MEM="$(awk -v k="$RSS" 'BEGIN{printf "%.2f", k/1024}')"
    
    rm -f "$TMP_JSON" "$TMP_TIME"
    
    [[ "$THR" != "NA" ]] && echo -n " thr:${THR}Mbps"
  fi
  
  echo ""  
  
  NOW="$(date -Iseconds)"
  echo "$NOW,$PROTOCOL,$SCHEME,$KEM_LABEL,$SIG_LABEL,$CLIENT_IP,$SERVER_TUN_IP,$PROFILE,$LAT,$HANDSHAKE_MS,$THR,$CPU,$MEM,NA,NA,NA,NA,$LOSS,NA" >> "$CSV"
  
  sleep 0.2
done

echo "[loop] Done. Logged $COUNT rows to $CSV"