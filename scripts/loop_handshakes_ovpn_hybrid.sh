#!/usr/bin/env bash
set -euo pipefail
export LC_NUMERIC=C

SERVER_TUN_IP="${1:-10.8.0.1}"
COUNT="${2:-100}"
PROFILE="${3:-realistic}"
ALGO="${4:-x25519_mlkem768}"  
THRU_EVERY="${5:-50}"
IPERF_TIME="${6:-5}"

CSV="/data/metrics.csv"
PROTOCOL="OpenVPN"
SCHEME="proxy_pq"
KEM_LABEL="${ALGO^^}"  
SIG_LABEL="ECDSA-P256"

[[ -f "$CSV" ]] || echo "timestamp,protocol,scheme,kem,signature,client_ip,server_ip,cond_profile,latency_ms,handshake_ms,throughput_mbps,cpu_pct,mem_mb,sign_ms,verify_ms,encap_ms,decap_ms,packet_loss_pct,energy_joules" >> "$CSV"

echo "[loop] OpenVPN hybrid handshakes: $COUNT | profile: $PROFILE | algo: $ALGO"

for i in $(seq 1 "$COUNT"); do
  echo "[loop][$i] Restarting containers to force TLS+OpenVPN handshake"
  
  docker stop ovpn_cli_hybrid pqtls_proxy_cli >/dev/null 2>&1 || true
  docker stop ovpn_srv_hybrid pqtls_proxy_srv >/dev/null 2>&1 || true
  sleep 1
  
  bash scripts/run_pqtls_ovpn_server.sh "$ALGO" >/dev/null 2>&1 &
  sleep 2
  
  START_NS="$(date +%s%N)"
  bash scripts/run_pqtls_ovpn_client.sh "$ALGO" >/dev/null 2>&1 &
  
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
  
  CLIENT_TUN_IP="$(ip -4 -o addr show tun0 | awk '{print $4}' | cut -d/ -f1)"
  
  PINGN="$(ping -c5 -i 0.2 -W2 "$SERVER_TUN_IP" 2>/dev/null || true)"
  LAT="$(echo "$PINGN" | awk -F'/' '/^rtt/ {print $5}')"; [[ -z "$LAT" ]] && LAT="NA"
  LOSS="$(echo "$PINGN" | sed -n 's/.* \([0-9.]\+\)% packet loss.*/\1/p')"; [[ -z "$LOSS" ]] && LOSS="NA"
  
  THR="NA"; CPU="NA"; MEM="NA"
  if (( THRU_EVERY > 0 )) && (( i % THRU_EVERY == 0 )); then
    TMP_JSON="$(mktemp)"; TMP_TIME="$(mktemp)"
    /usr/bin/time -v -o "$TMP_TIME" \
      iperf3 -c "$SERVER_TUN_IP" -B "$CLIENT_TUN_IP" -t "$IPERF_TIME" --json > "$TMP_JSON" || true
    BPS="$(jq -r '.end.sum_received.bits_per_second // .end.sum_sent.bits_per_second // empty' "$TMP_JSON" 2>/dev/null || true)"
    [[ -n "${BPS:-}" ]] && THR="$(awk -v b="$BPS" 'BEGIN{printf "%.2f", b/1000000}')"
    CPU="$(awk -F': ' '/Percent of CPU/ {gsub("%","",$2); print $2}' "$TMP_TIME" 2>/dev/null || true)"
    [[ -z "$CPU" ]] && CPU="NA"
    RSS="$(awk -F': ' '/Maximum resident set size/ {print $2}' "$TMP_TIME" 2>/dev/null || true)"
    [[ -n "$RSS" ]] && MEM="$(awk -v k="$RSS" 'BEGIN{printf "%.2f", k/1024}')"
    rm -f "$TMP_JSON" "$TMP_TIME"
  fi
  
  NOW="$(date -Iseconds)"
  echo "$NOW,$PROTOCOL,$SCHEME,$KEM_LABEL,$SIG_LABEL,$CLIENT_TUN_IP,$SERVER_TUN_IP,$PROFILE,$LAT,$HANDSHAKE_MS,$THR,$CPU,$MEM,NA,NA,NA,NA,$LOSS,NA" >> "$CSV"
  
  sleep 0.2
done

echo "[loop] Done. Logged $COUNT rows to $CSV"