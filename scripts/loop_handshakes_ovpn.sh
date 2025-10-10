#!/usr/bin/env bash
set -euo pipefail
export LC_NUMERIC=C

SERVER_TUN_IP="${1:-}"; COUNT="${2:-1000}"; PROFILE_LABEL="${3:-realistic}"
THROUGHPUT_EVERY="${4:-50}"; IPERF_TIME="${5:-5}"
DEBUG="${DEBUG:-0}"                         

if [[ -z "$SERVER_TUN_IP" ]]; then
  echo "Usage: $(basename "$0") <server_tunnel_ip> [count] [profile_label] [throughput_every] [iperf_time]"
  exit 1
fi

CSV="/data/metrics.csv"
PROTOCOL="OpenVPN"; SCHEME="classic"
CLIENT_CONT="${CLIENT_CONT:-ovpn_cli}"

[[ -f "$CSV" ]] || echo "timestamp,protocol,scheme,kem,signature,client_ip,server_ip,cond_profile,latency_ms,handshake_ms,throughput_mbps,cpu_pct,mem_mb,sign_ms,verify_ms,encap_ms,decap_ms,packet_loss_pct,energy_joules" >> "$CSV"

echo "[loop] OpenVPN handshakes: $COUNT | profile: $PROFILE_LABEL | throughput_every: $THROUGHPUT_EVERY | iperf_time: ${IPERF_TIME}s"

for i in $(seq 1 "$COUNT"); do
  echo "[loop][$i] restarting client container to force TLS handshake"

  if ! timeout 8s docker restart -t 1 "$CLIENT_CONT" >/dev/null 2>&1; then
    echo "[loop][$i] WARN: restart slow; kill+start fallback"
    docker kill -s KILL "$CLIENT_CONT" >/dev/null 2>&1 || true
    docker start "$CLIENT_CONT" >/dev/null 2>&1 || true
    sleep 0.5
  fi

  START_NS="$(date +%s%N)"
  HANDSHAKE_MS="NA"; CLIENT_TUN_IP=""

  for t in $(seq 1 150); do
    CLIENT_TUN_IP="$(docker exec "$CLIENT_CONT" sh -lc 'ip -4 -o addr show tun0 2>/dev/null | awk "{print \$4}" | cut -d/ -f1' || true)"
    [[ "$DEBUG" = "1" ]] && echo "[dbg][$i] t=$t tun0 ip=$CLIENT_TUN_IP"
    if [[ -n "$CLIENT_TUN_IP" ]]; then
      if docker exec "$CLIENT_CONT" sh -lc 'ping -c1 -W1 -I tun0 '"$SERVER_TUN_IP"' >/dev/null 2>&1'; then
        END_NS="$(date +%s%N)"
        HANDSHAKE_MS="$(awk -v s="$START_NS" -v e="$END_NS" 'BEGIN{printf "%.2f", (e-s)/1000000}')"
        [[ "$DEBUG" = "1" ]] && echo "[dbg][$i] handshake_ms=$HANDSHAKE_MS"
        break                                  
      fi
    fi
    sleep 0.1
  done

  CLIENT_TUN_IP="${CLIENT_TUN_IP:-NA}"

  PINGN="$(docker exec "$CLIENT_CONT" sh -lc 'ping -c5 -i 0.2 -W2 '"$SERVER_TUN_IP"' 2>/dev/null' || true)"
  LATENCY_MS="$(echo "$PINGN" | awk -F'/' '/^rtt/ {print $5}')"; [[ -z "$LATENCY_MS" ]] && LATENCY_MS="NA"
  LOSS_PCT="$(echo "$PINGN" | sed -n 's/.* \([0-9.]\+\)% packet loss.*/\1/p')"; [[ -z "$LOSS_PCT" ]] && LOSS_PCT="NA"

  THROUGHPUT="NA"; CPU_PCT="NA"; MEM_MB="NA"
  if (( THROUGHPUT_EVERY > 0 )) && (( i % THROUGHPUT_EVERY == 0 )) && [[ "$CLIENT_TUN_IP" != "NA" ]]; then
    TMP_JSON="$(mktemp)"; TMP_TIME="$(mktemp)"
    /usr/bin/time -v -o "$TMP_TIME" \
      docker exec "$CLIENT_CONT" sh -lc 'iperf3 -c '"$SERVER_TUN_IP"' -B '"$CLIENT_TUN_IP"' -t '"$IPERF_TIME"' --json' > "$TMP_JSON" || true
    RAW_BPS="$(jq -r '.end.sum_received.bits_per_second // .end.sum_sent.bits_per_second // empty' "$TMP_JSON" 2>/dev/null || true)"
    [[ -n "${RAW_BPS:-}" ]] && THROUGHPUT="$(awk -v bps="$RAW_BPS" 'BEGIN {printf "%.2f", bps/1000000}')"
    CPU_PCT="$(awk -F': ' '/Percent of CPU this job got/ {gsub("%","",$2); print $2}' "$TMP_TIME" 2>/dev/null || true)"; [[ -z "$CPU_PCT" ]] && CPU_PCT="NA"
    MAX_RSS_KB="$(awk -F': ' '/Maximum resident set size/ {print $2}' "$TMP_TIME" 2>/dev/null || true)"
    [[ -n "${MAX_RSS_KB:-}" ]] && MEM_MB="$(awk -v kb="$MAX_RSS_KB" 'BEGIN {printf "%.2f", kb/1024}')"
    rm -f "$TMP_JSON" "$TMP_TIME"
    [[ "$DEBUG" = "1" ]] && echo "[dbg][$i] thr=$THROUGHPUT cpu=$CPU_PCT mem=$MEM_MB"
  fi

  NOW="$(date -Iseconds)"
  echo "$NOW,$PROTOCOL,$SCHEME,NA,NA,$CLIENT_TUN_IP,$SERVER_TUN_IP,$PROFILE_LABEL,$LATENCY_MS,$HANDSHAKE_MS,$THROUGHPUT,$CPU_PCT,$MEM_MB,NA,NA,NA,NA,$LOSS_PCT,NA" >> "$CSV"

  sleep 0.2
done

echo "[loop] Done. Logged $COUNT rows to $CSV"
