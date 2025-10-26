#!/usr/bin/env bash
set -euo pipefail
export LC_NUMERIC=C

SERVER_TUN_IP="${1:-}"
COUNT="${2:-1000}"
PROFILE="${3:-realistic}"
THROUGHPUT_EVERY="${4:-50}"
IPERF_TIME="${5:-5}"

KEM_LABEL="${KEM:-ECDHE-X25519}"
SIG_LABEL="${SIG:-RSA-2048}"
SCHEME="${SCHEME:-classic}"

CSV="${CSV:-/data/metrics.csv}"
PROTOCOL="OpenVPN"
CLIENT_CONT="${CLIENT_CONT:-ovpn_cli}"
DEBUG="${DEBUG:-0}"

[[ -n "$SERVER_TUN_IP" ]] || {
  echo "Usage: $0 <server_tun_ip> [count] [profile] [throughput_every] [iperf_time]"
  echo "Example: $0 10.10.0.1 1000 realistic 50 5"
  exit 1
}

[[ -f "$CSV" ]] || echo "timestamp,protocol,scheme,kem,signature,client_ip,server_ip,cond_profile,latency_ms,handshake_ms,throughput_mbps,cpu_pct,mem_mb,packet_loss_pct" >> "$CSV"

echo "[loop] OpenVPN classic handshakes: $COUNT | profile: $PROFILE"
echo "[loop] KEM: $KEM_LABEL | SIG: $SIG_LABEL | SCHEME: $SCHEME"
echo "[loop] throughput_every: $THROUGHPUT_EVERY | iperf_time: ${IPERF_TIME}s"
echo "[loop] Method: Restart client container to force TLS handshake"

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
  LAT="$(echo "$PINGN" | awk -F'/' '/^rtt/ {print $5}')"; [[ -z "$LAT" ]] && LAT="NA"
  LOSS="$(echo "$PINGN" | sed -n 's/.* \([0-9.]\+\)% packet loss.*/\1/p')"; [[ -z "$LOSS" ]] && LOSS="NA"

  THR="NA"; CPU="NA"; MEM="NA"
  if (( THROUGHPUT_EVERY > 0 )) && (( i % THROUGHPUT_EVERY == 0 )) && [[ "$CLIENT_TUN_IP" != "NA" ]]; then
    TMP_JSON="$(mktemp)"
    TMP_STATS="$(mktemp)"

    # Start docker stats in background
    (sudo docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}}" "$CLIENT_CONT" > "$TMP_STATS") &
    STATS_PID=$!

    # Run iperf3
    sudo docker exec "$CLIENT_CONT" sh -lc 'iperf3 -c '"$SERVER_TUN_IP"' -B '"$CLIENT_TUN_IP"' -t '"$IPERF_TIME"' --json' > "$TMP_JSON" || true

    # Wait for stats and clean up
    kill $STATS_PID 2>/dev/null || true
    wait $STATS_PID 2>/dev/null || true

    # Parse throughput
    BPS="$(jq -r '.end.sum_received.bits_per_second // .end.sum_sent.bits_per_second // empty' "$TMP_JSON" 2>/dev/null || true)"
    [[ -n "${BPS:-}" ]] && THR="$(awk -v b="$BPS" 'BEGIN{printf "%.2f", b/1000000}')"

    # Parse docker stats
    if [[ -f "$TMP_STATS" ]] && [[ -s "$TMP_STATS" ]]; then
      CPU="$(cut -d',' -f1 "$TMP_STATS" | tr -d '%' | head -1)"
      MEM_RAW="$(cut -d',' -f2 "$TMP_STATS" | awk '{print $1}' | head -1)"

      # Convert MiB/GiB to MB
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

    [[ "$DEBUG" = "1" ]] && echo "[dbg][$i] thr=$THR cpu=$CPU mem=$MEM"
  fi

  NOW="$(date -Iseconds)"
  echo "$NOW,$PROTOCOL,$SCHEME,$KEM_LABEL,$SIG_LABEL,$CLIENT_TUN_IP,$SERVER_TUN_IP,$PROFILE,$LAT,$HANDSHAKE_MS,$THR,$CPU,$MEM,$LOSS" >> "$CSV"

  sleep 0.2
done

echo "[loop] Done. Logged $COUNT rows to $CSV"
