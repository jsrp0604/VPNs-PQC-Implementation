#!/usr/bin/env bash
set -euo pipefail
export LC_NUMERIC=C

SERVER_TUN_IP="${1:-}"
COUNT="${2:-1000}"
PROFILE="${3:-realistic}"
THROUGHPUT_EVERY="${4:-50}"
IPERF_TIME="${5:-5}"

KEM_LABEL="${KEM:-ECDHE-P256}"
SIG_LABEL="${SIG:-RSA-2048}"
SCHEME="${SCHEME:-classic}"

CSV="${CSV:-/data/metrics.csv}"
PROTOCOL="IPsec"
CLIENT_CONT="${CLIENT_CONT:-ipsec_cli}"

[[ -f "$CSV" ]] || echo "timestamp,protocol,scheme,kem,signature,client_ip,server_ip,cond_profile,latency_ms,handshake_ms,throughput_mbps,cpu_pct,mem_mb,packet_loss_pct" >> "$CSV"

echo "[loop] IPsec classic handshakes: $COUNT | profile: $PROFILE"
echo "[loop] KEM: $KEM_LABEL | SIG: $SIG_LABEL | SCHEME: $SCHEME"
echo "[loop] throughput_every: $THROUGHPUT_EVERY | iperf_time: ${IPERF_TIME}s"

for i in $(seq 1 "$COUNT"); do
  echo "[loop][$i/$COUNT] Starting handshake"
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
      break
    fi
    sleep 0.2
  done

  docker exec "$CLIENT_CONT" sh -lc "ping -c2 -W1 -I 10.30.0.2 $SERVER_TUN_IP >/dev/null 2>&1" || true
  sleep 0.15

  PING5="$(docker exec "$CLIENT_CONT" sh -lc "ping -c5 -i 0.3 -W2 -I 10.30.0.2 $SERVER_TUN_IP 2>/dev/null" || true)"
  LAT="$(echo "$PING5" | awk -F'/' '/^rtt/ {print $5}')"; [[ -z "$LAT" ]] && LAT="NA"
  LOSS="$(echo "$PING5" | sed -n 's/.* \([0-9.]\+\)% packet loss.*/\1/p')"; [[ -z "$LOSS" ]] && LOSS="NA"

  THR="NA"; CPU="NA"; MEM="NA"
  if (( THROUGHPUT_EVERY > 0 )) && (( i % THROUGHPUT_EVERY == 0 )); then
    TMP_JSON="$(mktemp)"
    TMP_STATS="$(mktemp)"

    # docker stats
    (sudo docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}}" "$CLIENT_CONT" > "$TMP_STATS") &
    STATS_PID=$!

    # iperf3
    sudo docker exec "$CLIENT_CONT" sh -lc "iperf3 -c $SERVER_TUN_IP -B 10.30.0.2 -t $IPERF_TIME --json" > "$TMP_JSON" || true

    kill $STATS_PID 2>/dev/null || true
    wait $STATS_PID 2>/dev/null || true

    # parsing
    BPS="$(jq -r '.end.sum_received.bits_per_second // .end.sum_sent.bits_per_second // empty' "$TMP_JSON" 2>/dev/null || true)"
    [[ -n "${BPS:-}" ]] && THR="$(awk -v b="$BPS" 'BEGIN{printf "%.2f", b/1000000}')"

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

    [[ "$THR" != "NA" ]] && echo -n " thr:${THR}Mbps cpu:${CPU}% mem:${MEM}MB"
  fi

  NOW="$(date -Iseconds)"
  echo "$NOW,$PROTOCOL,$SCHEME,$KEM_LABEL,$SIG_LABEL,$CLIENT_IP,$SERVER_TUN_IP,$PROFILE,$LAT,$HANDSHAKE_MS,$THR,$CPU,$MEM,$LOSS" >> "$CSV"

  sleep 0.2
done

echo "[loop] Logged $COUNT rows to $CSV"
