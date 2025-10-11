#!/usr/bin/env bash
set -euo pipefail
export LC_NUMERIC=C

# Usage: loop_handshakes_wg.sh <server_tunnel_ip> [count] [profile_label] [throughput_every] [iperf_time]
SERVER_TUN_IP="${1:-}"
COUNT="${2:-1000}"
PROFILE_LABEL="${3:-realistic}"
THROUGHPUT_EVERY="${4:-50}"   
IPERF_TIME="${5:-5}"   

KEM_LABEL=ECDH-X25519
SIG_LABEL=none

if [[ -z "$SERVER_TUN_IP" ]]; then
  echo "Usage: $(basename "$0") <server_tunnel_ip> [count] [profile_label] [throughput_every] [iperf_time]"
  exit 1
fi

CSV="/data/metrics.csv"
CLIENT_CONF="/data/wg_classic/client/wg0.conf"
PROTOCOL="WireGuard"
SCHEME="classic"

if [[ ! -f "$CSV" ]]; then
  echo "timestamp,protocol,scheme,kem,signature,client_ip,server_ip,cond_profile,latency_ms,handshake_ms,throughput_mbps,cpu_pct,mem_mb,sign_ms,verify_ms,encap_ms,decap_ms,packet_loss_pct,energy_joules" >> "$CSV"
fi

if ! ip link show wg0 >/dev/null 2>&1; then
  echo "[err] wg0 interface not found. Start containers first."; exit 1
fi
CLIENT_TUN_IP="$(ip -4 -o addr show wg0 | awk '{print $4}' | cut -d/ -f1)"

TMP_STRIPPED="$(mktemp)"
wg-quick strip "$CLIENT_CONF" > "$TMP_STRIPPED"

echo "[loop] Handshakes: $COUNT | profile: $PROFILE_LABEL | throughput_every: $THROUGHPUT_EVERY | iperf_time: ${IPERF_TIME}s"
echo "[loop] Client wg0: $CLIENT_TUN_IP  | Server wg0: $SERVER_TUN_IP"

for i in $(seq 1 "$COUNT"); do
  sudo wg syncconf wg0 "$TMP_STRIPPED"

  PING1="$(ping -c1 -W2 "$SERVER_TUN_IP" 2>/dev/null || true)"
  HANDSHAKE_MS="$(echo "$PING1" | awk '/time=/{for(i=1;i<=NF;i++) if ($i ~ /^time=/){sub("time=","",$i); print $i; exit}}')"
  [[ -z "${HANDSHAKE_MS:-}" ]] && HANDSHAKE_MS="NA"

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
      MEM_MB="$(awk -v kb="$MAX_RSS_KB" 'BEGIN {printf "%.2f", kb/1024}')"
    fi
    rm -f "$TMP_JSON" "$TMP_TIME"
  fi

  NOW="$(date -Iseconds)"
  echo "$NOW,$PROTOCOL,$SCHEME,$KEM_LABEL,$SIG_LABEL,$CLIENT_IP,$SERVER_TUN_IP,$PROFILE,$LAT,$HANDSHAKE_MS,$THR,$CPU,$MEM,NA,NA,NA,NA,$LOSS,NA" >> "$CSV"

  sleep 0.15
done

rm -f "$TMP_STRIPPED"
echo "[loop] Done. Logged $COUNT rows to $CSV"
