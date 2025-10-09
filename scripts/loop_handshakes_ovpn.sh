#!/usr/bin/env bash
set -euo pipefail
export LC_NUMERIC=C

SERVER_TUN_IP="${1:-}"
COUNT="${2:-1000}"
PROFILE_LABEL="${3:-realistic}"
THROUGHPUT_EVERY="${4:-50}"
IPERF_TIME="${5:-5}"

if [[ -z "$SERVER_TUN_IP" ]]; then
  echo "Usage: $(basename "$0") <server_tun_ip> [count] [profile_label] [throughput_every] [iperf_time]"
  exit 1
fi

CSV="/data/metrics.csv"
PROTOCOL="OpenVPN"
SCHEME="classic"
CLIENT_CONT="ovpn_c"
CLIENT_LOG="/var/log/openvpn.log"

if [[ ! -f "$CSV" ]]; then
  echo "timestamp,protocol,scheme,kem,signature,client_ip,server_ip,cond_profile,latency_ms,handshake_ms,throughput_mbps,cpu_pct,mem_mb,sign_ms,verify_ms,encap_ms,decap_ms,packet_loss_pct,energy_joules" >> "$CSV"
fi

echo "[loop] OpenVPN handshakes: $COUNT | profile: $PROFILE_LABEL | throughput_every: $THROUGHPUT_EVERY | iperf_time: ${IPERF_TIME}s"

for i in $(seq 1 "$COUNT"); do
  echo "[loop][$i] restarting client container to force TLS handshake"
  docker restart "$CLIENT_CONT" >/dev/null

  START_NS="$(date +%s%N)"
  HANDSHAKE_MS="NA"
  for t in $(seq 1 100); do
    LINE="$(docker exec "$CLIENT_CONT" /bin/sh -c "grep -m1 'Initialization Sequence Completed' '$CLIENT_LOG' || true")"
    if [[ -n "$LINE" ]]; then
      END_NS="$(date +%s%N)"
      HANDSHAKE_MS="$(awk -v start="$START_NS" -v end="$END_NS" 'BEGIN{printf \"%.2f\", (end-start)/1000000}')"
      break
    fi
    sleep 0.1
  done

  CLIENT_TUN_IP="$(ip -4 -o addr show tun0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)"
  if [[ -z "${CLIENT_TUN_IP:-}" ]]; then
    sleep 0.2
    CLIENT_TUN_IP="$(ip -4 -o addr show tun0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)"
  fi

  PINGN="$(ping -c5 -i 0.2 -W2 "$SERVER_TUN_IP" 2>/dev/null || true)"
  LATENCY_MS="$(echo "$PINGN" | awk -F'/' '/^rtt/ {print $5}')"
  [[ -z "${LATENCY_MS:-}" ]] && LATENCY_MS="NA"
  LOSS_PCT="$(echo "$PINGN" | awk -F', *' '/packet loss/ {gsub("%","",$3); print $3}')"
  [[ -z "${LOSS_PCT:-}" ]] && LOSS_PCT="NA"

  THROUGHPUT="NA"; CPU_PCT="NA"; MEM_MB="NA"
  if (( THROUGHPUT_EVERY > 0 )) && (( i % THROUGHPUT_EVERY == 0 )); then
    TMP_JSON="$(mktemp)"
    TMP_TIME="$(mktemp)"

    /usr/bin/time -v -o "$TMP_TIME" \
      iperf3 -c "$SERVER_TUN_IP" -B "$CLIENT_TUN_IP" -t "$IPERF_TIME" --json > "$TMP_JSON" || true

    RAW_BPS="$(jq -r '.end.sum_received.bits_per_second // .end.sum_sent.bits_per_second // empty' "$TMP_JSON" 2>/dev/null || true)"
    if [[ -n "${RAW_BPS:-}" ]]; then
      THROUGHPUT="$(awk -v bps="$RAW_BPS" 'BEGIN {printf "%.2f", bps/1000000}')"
    fi
    CPU_PCT="$(awk -F': ' '/Percent of CPU this job got/ {gsub("%","",$2); print $2}' "$TMP_TIME" 2>/dev/null || true)"
    [[ -z "${CPU_PCT:-}" ]] && CPU_PCT="NA"
    MAX_RSS_KB="$(awk -F': ' '/Maximum resident set size/ {print $2}' "$TMP_TIME" 2>/dev/null || true)"
    if [[ -n "${MAX_RSS_KB:-}" ]]; then
      MEM_MB="$(awk -v kb="$MAX_RSS_KB" 'BEGIN {printf \"%.2f\", kb/1024}')"
    fi
    rm -f "$TMP_JSON" "$TMP_TIME"
  fi

  NOW="$(date -Iseconds)"
  echo "$NOW,$PROTOCOL,$SCHEME,NA,NA,$CLIENT_TUN_IP,$SERVER_TUN_IP,$PROFILE_LABEL,$LATENCY_MS,$HANDSHAKE_MS,$THROUGHPUT,$CPU_PCT,$MEM_MB,NA,NA,NA,NA,$LOSS_PCT,NA" >> "$CSV"

  sleep 0.2
done

echo "[loop] Done. Logged $COUNT rows to $CSV"
