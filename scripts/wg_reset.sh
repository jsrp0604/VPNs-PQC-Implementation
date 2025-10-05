#!/usr/bin/env bash
set -euo pipefail
sudo wg-quick down wg0 2>/dev/null || true
sudo ip link del wg0 2>/dev/null || true
