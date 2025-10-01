#!/bin/bash
set -euo pipefail

ROLE=${ROLE:-server}   
IFACE=wg0

if [[ "$ROLE" == "server" ]]; then
    echo "[wg_classic] Starting server..."
    wg-quick up $IFACE
    tail -f /dev/null  
else
    echo "[wg_classic] Starting client..."
    wg-quick up $IFACE
    tail -f /dev/null
fi
