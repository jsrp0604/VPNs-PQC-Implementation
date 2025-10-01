set -euo pipefail

export LC_NUMERIC=C

if [[ $# -lt 2 ]]; then
  echo "Usage: $(basename "$0") <server_ip> <profile>"
  exit 1
fi

SERVER_IP="$1"
PROFILE="$2"

CLIENT_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date -Iseconds)

echo "[run_test] Running test: profile=$PROFILE server=$SERVER_IP"

LATENCY=$(ping -c 5 "$SERVER_IP" | awk -F'/' 'END{print $5}')  # avg in ms
: "${LATENCY:=NA}"

IPERF_JSON=$(iperf3 -c "$SERVER_IP" -t 10 --json || true)

THROUGHPUT=$(echo "$IPERF_JSON" | jq -r '.end.sum_received.bits_per_second' 2>/dev/null || echo "NA")

if [[ "$THROUGHPUT" != "NA" && "$THROUGHPUT" != "null" ]]; then
  THROUGHPUT=$(awk -v bps="$THROUGHPUT" 'BEGIN {printf "%.2f", bps/1000000}')
else
  THROUGHPUT="NA"
fi


CSV="bench/metrics.csv"
echo "$TIMESTAMP,NA,NA,NA,NA,$CLIENT_IP,$SERVER_IP,$PROFILE,$LATENCY,NA,$THROUGHPUT,NA,NA,NA,NA,NA,NA,NA" >> "$CSV"

echo "[run_test] Result appended to $CSV"
