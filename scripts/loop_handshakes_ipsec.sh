#!/usr/bin/env bash
set -euo pipefail
export LC_NUMERIC=C

SERVER_TUN_IP="${1:-}"; COUNT="${2:-1000}"; PROFILE="${3:-realistic}"
THRU_EVERY="${4:-50}"; IPERF_TIME="${5:-5}"
CSV="/data/metrics.csv"; PROTOCOL="IPsec"; SCHEME="classic"
CLIENT_CONT="${CLIENT_CONT:-ipsec_cli}"

KEM_LABEL=ECDHE-P256
SIG_LABEL=RSA-2048 

[[ -n "$SERVER_TUN_IP" ]] || { echo "Usage: $0 <server_tun_ip> [count] [profile] [throughput_every] [iperf_time]"; exit 1; }
[[ -f "$CSV" ]] || echo "timestamp,protocol,scheme,kem,signature,client_ip,server_ip,cond_profile,latency_ms,handshake_ms,throughput_mbps,cpu_pct,mem_mb,sign_ms,verify_ms,encap_ms,decap_ms,packet_loss_pct,energy_joules" >> "$CSV"

echo "[loop] IPsec handshakes: $COUNT | profile: $PROFILE | throughput_every: $THRU_EVERY | iperf_time: ${IPERF_TIME}s"

for i in $(seq 1 "$COUNT"); do
  if ! timeout 8s docker restart -t 1 "$CLIENT_CONT" >/dev/null 2>&1; then
    echo "[loop][$i] WARN: restart lento; kill+start fallback"
    docker kill -s KILL "$CLIENT_CONT" >/dev/null 2>&1 || true
    docker start "$CLIENT_CONT" >/dev/null 2>&1 || true
    sleep 0.5
  fi

  START_NS="$(date +%s%N)"
  HANDSHAKE_MS="NA"
  CLIENT_IP="10.30.0.2"

  for t in $(seq 1 100); do
    if docker exec "$CLIENT_CONT" sh -lc "ping -c1 -W1 -I 10.30.0.2 $SERVER_TUN_IP >/dev/null 2>&1"; then
      END_NS="$(date +%s%N)"
      HANDSHAKE_MS="$(awk -v s="$START_NS" -v e="$END_NS" 'BEGIN{printf "%.2f", (e-s)/1000000}')"
      sleep 0.20

      break
    fi
    sleep 0.1
  done

  docker exec "$CLIENT_CONT" sh -lc "ping -c2 -W1 -I 10.30.0.2 $SERVER_TUN_IP >/dev/null 2>&1" || true
  sleep 0.15
  
  PING5="$(docker exec "$CLIENT_CONT" sh -lc "ping -c5 -i 0.3 -W2 -I 10.30.0.2 $SERVER_TUN_IP 2>/dev/null" || true)"
  LAT="$(echo "$PING5" | awk -F'/' '/^rtt/ {print $5}')"; [[ -z "$LAT" ]] && LAT="NA"
  LOSS="$(echo "$PING5" | sed -n 's/.* \([0-9.]\+\)% packet loss.*/\1/p')"; [[ -z "$LOSS" ]] && LOSS="NA"


  THR="NA"; CPU="NA"; MEM="NA"
  if (( THRU_EVERY > 0 )) && (( i % THRU_EVERY == 0 )); then
    TMP_JSON="$(mktemp)"; TMP_TIME="$(mktemp)"
    /usr/bin/time -v -o "$TMP_TIME" docker exec "$CLIENT_CONT" sh -lc "iperf3 -c $SERVER_TUN_IP -B 10.30.0.2 -t $IPERF_TIME --json" > "$TMP_JSON" || true
    BPS="$(jq -r '.end.sum_received.bits_per_second // .end.sum_sent.bits_per_second // empty' "$TMP_JSON" 2>/dev/null || true)"
    [[ -n "${BPS:-}" ]] && THR="$(awk -v b="$BPS" 'BEGIN{printf "%.2f", b/1000000}')"
    CPU="$(awk -F': ' '/Percent of CPU/ {gsub("%","",$2); print $2}' "$TMP_TIME" 2>/dev/null || true)"; [[ -z "$CPU" ]] && CPU="NA"
    RSS="$(awk -F': ' '/Maximum resident set size/ {print $2}' "$TMP_TIME" 2>/dev/null || true)"; [[ -n "$RSS" ]] && MEM="$(awk -v k="$RSS" 'BEGIN{printf "%.2f", k/1024}')"
    rm -f "$TMP_JSON" "$TMP_TIME"
  fi

  NOW="$(date -Iseconds)"
  echo "$NOW,$PROTOCOL,$SCHEME,$KEM_LABEL,$SIG_LABEL,$CLIENT_IP,$SERVER_TUN_IP,$PROFILE,$LAT,$HANDSHAKE_MS,$THR,$CPU,$MEM,NA,NA,NA,NA,$LOSS,NA" >> "$CSV"

  sleep 0.2
done

echo "[loop] done"
