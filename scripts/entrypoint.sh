set -euo pipefail

ROLE="${ROLE:-client}"
COND="${COND:-local}"
SERVER_IP="${SERVER_IP:-unset}"

echo "permutation=$(basename "$(pwd)") role=$ROLE cond=$COND server_ip=$SERVER_IP"

tail -f /dev/null
