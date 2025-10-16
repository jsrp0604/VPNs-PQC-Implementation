#!/usr/bin/env bash
set -euo pipefail
export LC_NUMERIC=C

SERVER_TUN_IP="${1:-}"; COUNT="${2:-1000}"; PROFILE="${3:-realistic}"
THRU_EVERY="${4:-50}"; IPERF_TIME="${5:-5}"

CSV="/data/metrics.csv"
KEM="${KEM:-MCELIECE460896}"
SIG="${SIG:-static-key-auth}"
SCHEME="${SCHEME:-hybrid}"
PROTOCOL="WireGuard"
CLIENT_CONT="${CLIENT_CONT:-wg_hybrid_cli}"

[[ -n "$SERVER_TUN_IP" ]] || { echo "Usage: $0 <server_tun_ip> [count] [profile] [throughput_every] [iperf_time]"; exit 1; }

[[ -f "$CSV" ]] || echo "timestamp,protocol,scheme,kem,signature,client_ip,server_ip,cond_profile,latency_ms,handshake_ms,throughput_mbps,cpu_pct,mem_mb,sign_ms,verify_ms,encap_ms,decap_ms,packet_loss_pct,energy_joules" >> "$CSV"

echo "[loop] WireGuard+Rosenpass handshakes: $COUNT | profile: $PROFILE"
echo "[loop] KEM: MCELIECE460896 | SIG: static-key-auth | SCHEME: hybrid"

CLIENT_IP="10.31.0.2"

for i in $(seq 1 "$COUNT"); do
    if ! timeout 10s sudo docker restart -t 2 "$CLIENT_CONT" >/dev/null 2>&1; then
        echo "[loop][$i] restart timeout; kill+start"
        sudo docker kill "$CLIENT_CONT" >/dev/null 2>&1 || true
        sudo docker start "$CLIENT_CONT" >/dev/null 2>&1 || true
    fi
    
    START_NS="$(date +%s%N)"
    HANDSHAKE_MS="NA"
    
    for t in $(seq 1 200); do
        if sudo docker exec "$CLIENT_CONT" ping -c1 -W1 "$SERVER_TUN_IP" >/dev/null 2>&1; then
            END_NS="$(date +%s%N)"
            HANDSHAKE_MS="$(awk -v s="$START_NS" -v e="$END_NS" 'BEGIN{printf "%.2f", (e-s)/1000000}')"
            break
        fi
        sleep 0.1
    done

    PING5="$(sudo docker exec "$CLIENT_CONT" ping -c5 -i 0.2 -W2 "$SERVER_TUN_IP" 2>/dev/null || true)"
    LAT="$(echo "$PING5" | awk -F'/' '/^rtt/ {print $5}')"; [[ -z "$LAT" ]] && LAT="NA"
    LOSS="$(echo "$PING5" | sed -n 's/.* \([0-9.]\+\)% packet loss.*/\1/p')"; [[ -z "$LOSS" ]] && LOSS="NA"

    THR="NA"; CPU="NA"; MEM="NA"
    if (( THRU_EVERY > 0 )) && (( i % THRU_EVERY == 0 )); then
        TMP_JSON="$(mktemp)"; TMP_TIME="$(mktemp)"
        /usr/bin/time -v -o "$TMP_TIME" sudo docker exec "$CLIENT_CONT" \
            iperf3 -c "$SERVER_TUN_IP" -B "$CLIENT_IP" -t "$IPERF_TIME" --json > "$TMP_JSON" 2>/dev/null || true
        BPS="$(jq -r '.end.sum_received.bits_per_second // .end.sum_sent.bits_per_second // empty' "$TMP_JSON" 2>/dev/null || true)"
        [[ -n "${BPS:-}" ]] && THR="$(awk -v b="$BPS" 'BEGIN{printf "%.2f", b/1000000}')"
        CPU="$(awk -F': ' '/Percent of CPU/ {gsub("%","",$2); print $2}' "$TMP_TIME" 2>/dev/null || true)"; [[ -z "$CPU" ]] && CPU="NA"
        RSS="$(awk -F': ' '/Maximum resident set size/ {print $2}' "$TMP_TIME" 2>/dev/null || true)"
        [[ -n "$RSS" ]] && MEM="$(awk -v k="$RSS" 'BEGIN{printf "%.2f", k/1024}')"
        rm -f "$TMP_JSON" "$TMP_TIME"
    fi

    NOW="$(date -Iseconds)"
    echo "$NOW,$PROTOCOL,$SCHEME,$KEM,$SIG,$CLIENT_IP,$SERVER_TUN_IP,$PROFILE,$LAT,$HANDSHAKE_MS,$THR,$CPU,$MEM,NA,NA,NA,NA,$LOSS,NA" >> "$CSV"
    
    sleep 0.3
done

echo "[loop] Done. $COUNT rows $CSV"
