#!/usr/bin/env bash
set -euo pipefail
export LC_NUMERIC=C

SERVER_TUN_IP="$1"      
PROFILE="$2"            
PROTOCOL="WireGuard"
SCHEME="classic"

CLIENT_TUN_IP="$(ip -4 -o addr show dev wg0 | awk '{print $4}' | cut -d/ -f1)"
TIMESTAMP="$(date -Iseconds)"

echo "[run_wg] Testing $PROTOCOL/$SCHEME  $CLIENT_TUN_IP -> $SERVER_TUN_IP  profile=$PROFILE"

PING_OUT="$(ping -c 5 "$SERVER_TUN_IP" || true)"
LATENCY_MS="$(echo "$PING_OUT" | awk -F'/' '/^rtt/ {print $5}')"
[[ -z "${LATENCY_MS:-}" ]] && LATENCY_MS="NA"
LOSS_PCT="$(echo "$PING_OUT" | awk -F', *' '/packet loss/ {gsub("%","",$3); print $3}')"
[[ -z "${LOSS_PCT:-}" ]] && LOSS_PCT="NA"

HANDSHAKE_MS="$(echo "$PING_OUT" | awk '/time=/{for(i=1;i<=NF;i++) if ($i ~ /^time=/){gsub("time=","",$i); print $i; exit}}')"
[[ -z "${HANDSHAKE_MS:-}" ]] && HANDSHAKE_MS="NA"

TMP_JSON="$(mktemp)"
TMP_TIME="$(mktemp)"

/usr/bin/time -v -o "$TMP_TIME" \
  iperf3 -c "$SERVER_TUN_IP" -B "$CLIENT_TUN_IP" -t 10 --json > "$TMP_JSON" || true

RAW_BPS="$(jq -r '.end.sum_received.bits_per_second // .end.sum_sent.bits_per_second // empty' "$TMP_JSON" || true)"
if [[ -z "${RAW_BPS:-}" ]]; then
  THROUGHPUT_MBPS="NA"
else
  THROUGHPUT_MBPS="$(awk -v bps="$RAW_BPS" 'BEGIN {printf "%.2f", bps/1000000}')"
fi

CPU_PCT="$(awk -F': ' '/Percent of CPU this job got/ {gsub("%","",$2); print $2}' "$TMP_TIME" 2>/dev/null || true)"
[[ -z "${CPU_PCT:-}" ]] && CPU_PCT="NA"

MAX_RSS_KB="$(awk -F': ' '/Maximum resident set size/ {print $2}' "$TMP_TIME" 2>/dev/null || true)"
if [[ -z "${MAX_RSS_KB:-}" ]]; then
  MEM_MB="NA"
else
  MEM_MB="$(awk -v kb="$MAX_RSS_KB" 'BEGIN {printf "%.2f", kb/1024}')"
fi

CSV="/data/metrics.csv"
echo "$TIMESTAMP,$PROTOCOL,$SCHEME,NA,NA,$CLIENT_TUN_IP,$SERVER_TUN_IP,$PROFILE,$LATENCY_MS,$HANDSHAKE_MS,$THROUGHPUT_MBPS,$CPU_PCT,$MEM_MB,NA,NA,NA,NA,$LOSS_PCT,NA" >> "$CSV"
echo "[run_wg] Logged to $CSV"

rm -f "$TMP_JSON" "$TMP_TIME"
