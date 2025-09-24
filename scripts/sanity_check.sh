set -euo pipefail
SERVER_IP="${1:-}"
if [[ -z "$SERVER_IP" ]]; then
  echo "Usage: $(basename "$0") <server_ip>"; exit 1
fi

echo "[sanity] Pinging $SERVER_IP ..."
ping -c 5 "$SERVER_IP" || true

echo "[sanity] iperf3 TCP test (10s) ..."
iperf3 -c "$SERVER_IP" -t 10 || true

echo "[sanity] done."
