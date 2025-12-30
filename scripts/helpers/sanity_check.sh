set -euo pipefail
SERVER_IP="${1:-}"
if [[ -z "$SERVER_IP" ]]; then
  echo "Usage: $(basename "$0") <server_ip>"; exit 1
fi

echo "Pinging $SERVER_IP"
ping -c 5 "$SERVER_IP" || true

echo "iperf3 TCP test"
iperf3 -c "$SERVER_IP" -t 10 || true

echo "done"
