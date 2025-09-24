set -euo pipefail

detect_iface() {
  for dev in eth0 ens33 enp0s3 eno1; do
    if ip link show "$dev" >/dev/null 2>&1; then echo "$dev"; return 0; fi
  done
  ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

apply() {
  local iface="$1" prof="$2"
  tc qdisc del dev "$iface" root 2>/dev/null || true
  case "$prof" in
    local)
      tc qdisc add dev "$iface" root netem delay 1.5ms 0.5ms distribution normal ;;
    realistic)
      tc qdisc add dev "$iface" root handle 1: htb default 11
      tc class add dev "$iface" parent 1: classid 1:1 htb rate 10mbit burst 15k
      tc qdisc add dev "$iface" parent 1:1 handle 10: netem delay 50ms 10ms distribution normal ;;
    adverse)
      tc qdisc add dev "$iface" root handle 1: htb default 11
      tc class add dev "$iface" parent 1: classid 1:1 htb rate 5mbit burst 10k
      tc qdisc add dev "$iface" parent 1:1 handle 10: netem delay 150ms loss 2.5% ;;
    highlat)
      tc qdisc add dev "$iface" root handle 1: htb default 11
      tc class add dev "$iface" parent 1: classid 1:1 htb rate 2mbit burst 8k
      tc qdisc add dev "$iface" parent 1:1 handle 10: netem delay 300ms loss 5% ;;
    *)
      echo "Usage: $0 {local|realistic|adverse|highlat|clear|status}"; exit 1;;
  esac
  echo "[netem] applied $prof on $iface"
}

case "${1:-}" in
  local|realistic|adverse|highlat)
    IFACE="${IFACE:-$(detect_iface)}"; apply "$IFACE" "$1";;
  clear)
    IFACE="${IFACE:-$(detect_iface)}"; tc qdisc del dev "$IFACE" root 2>/dev/null || true; echo "[netem] cleared on $IFACE";;
  status)
    IFACE="${IFACE:-$(detect_iface)}"; tc qdisc show dev "$IFACE"; tc class show dev "$IFACE";;
  *)
    echo "Usage: $0 {local|realistic|adverse|highlat|clear|status}"; exit 1;;
esac
