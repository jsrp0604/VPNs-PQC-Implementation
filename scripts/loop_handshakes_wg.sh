#!/usr/bin/env bash
set -euo pipefail
export LC_NUMERIC=C

SERVER_TUN_IP="${1:-}"
COUNT="${2:-1000}"
PROFILE="${3:-realistic}"
THROUGHPUT_EVERY="${4:-50}"
IPERF_TIME="${5:-5}"

KEM_LABEL="${KEM:-X25519}"
SIG_LABEL="${SIG:-Ed25519}"
SCHEME="${SCHEME:-classic}"

CSV="/data/metrics.csv"
PROTOCOL="WireGuard"
CLIENT_CONT="${CLIENT_CONT:-wg_cli}"
CLIENT_CONF="/data/wg_classic/client/wg0.conf"

[[ -f "$CSV" ]] || echo "timestamp,protocol,scheme,kem,signature,client_ip,server_ip,cond_profile,latency_ms,handshake_ms,throughput_mbps,cpu_pct,mem_mb,packet_loss_pct" >> "$CSV"

if ! ip link show wg0 >/dev/null 2>&1; then
  echo "[err] wg0 interface not found. Start containers first."; exit 1
fi
CLIENT_IP="$(ip -4 -o addr show wg0 | awk '{print $4}' | cut -d/ -f1)"

TMP_STRIPPED="$(mktemp)"
wg-quick strip "$CLIENT_CONF" > "$TMP_STRIPPED"

echo "[loop] WireGuard classic handshakes: $COUNT | profile: $PROFILE"
echo "[loop] KEM: $KEM_LABEL | SIG: $SIG_LABEL | SCHEME: $SCHEME"
echo "[loop] throughput_every: $THROUGHPUT_EVERY | iperf_time: ${IPERF_TIME}s"

for i in $(seq 1 "$COUNT"); do
  sudo wg syncconf wg0 "$TMP_STRIPPED"

  PING1="$(ping -c1 -W2 "$SERVER_TUN_IP" 2>/dev/null || true)"
  HANDSHAKE_MS="$(echo "$PING1" | awk '/time=/{for(i=1;i<=NF;i++) if ($i ~ /^time=/){sub("time=","",$i); print $i; exit}}')"
  [[ -z "${HANDSHAKE_MS:-}" ]] && HANDSHAKE_MS="NA"

  PINGN="$(ping -c5 -i 0.2 -W2 "$SERVER_TUN_IP" 2>/dev/null || true)"
  LATENCY_MS="$(echo "$PINGN" | awk -F'/' '/^rtt/ {print $5}')"
  [[ -z "${LATENCY_MS:-}" ]] && LATENCY_MS="NA"
  LOSS_PCT="$(echo "$PINGN" | sed -n 's/.* \([0-9.]\+\)% packet loss.*/\1/p')"; [[ -z "$LOSS_PCT" ]] && LOSS_PCT="NA"
  [[ -z "${LOSS_PCT:-}" ]] && LOSS_PCT="NA"

  THR="NA"; CPU="NA"; MEM="NA"
  if (( THROUGHPUT_EVERY > 0 )) && (( i % THROUGHPUT_EVERY == 0 )); then
    TMP_JSON="$(mktemp)"
    TMP_STATS="$(mktemp)"

    # docker stats 
    (sudo docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}}" "$CLIENT_CONT" > "$TMP_STATS") &
    STATS_PID=$!

    # iperf3 
    sudo docker exec "$CLIENT_CONT" sh -lc "iperf3 -c $SERVER_TUN_IP -B $CLIENT_IP -t $IPERF_TIME --json" > "$TMP_JSON" || true

    kill $STATS_PID 2>/dev/null || true
    wait $STATS_PID 2>/dev/null || true

    # parsing
    BPS="$(jq -r '.end.sum_received.bits_per_second // .end.sum_sent.bits_per_second // empty' "$TMP_JSON" 2>/dev/null || true)"
    [[ -n "${BPS:-}" ]] && THR="$(awk -v b="$BPS" 'BEGIN{printf "%.2f", b/1000000}')"

    # docker stats
    if [[ -f "$TMP_STATS" ]] && [[ -s "$TMP_STATS" ]]; then
      CPU="$(cut -d',' -f1 "$TMP_STATS" | tr -d '%' | head -1)"
      MEM_RAW="$(cut -d',' -f2 "$TMP_STATS" | awk '{print $1}' | head -1)"

      if echo "$MEM_RAW" | grep -qi "GiB"; then
        MEM="$(echo "$MEM_RAW" | sed 's/GiB//' | awk '{printf "%.2f", $1 * 1024}')"
      elif echo "$MEM_RAW" | grep -qi "MiB"; then
        MEM="$(echo "$MEM_RAW" | sed 's/MiB//' | awk '{printf "%.2f", $1}')"
      else
        MEM="NA"
      fi
    fi

    [[ -z "$CPU" ]] && CPU="NA"
    [[ -z "$MEM" ]] && MEM="NA"

    rm -f "$TMP_JSON" "$TMP_STATS"
  fi

  NOW="$(date -Iseconds)"
  echo "$NOW,$PROTOCOL,$SCHEME,$KEM_LABEL,$SIG_LABEL,$CLIENT_IP,$SERVER_TUN_IP,$PROFILE,$LATENCY_MS,$HANDSHAKE_MS,$THR,$CPU,$MEM,$LOSS_PCT" >> "$CSV"

  sleep 0.15
done

rm -f "$TMP_STRIPPED"
echo "[loop] Logged $COUNT rows to $CSV"
