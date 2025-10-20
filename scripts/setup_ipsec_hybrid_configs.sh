#!/usr/bin/env bash
set -euo pipefail

BASE="/data/ipsec_hybrid"
mkdir -p "$BASE/server/pki/"{cacerts,certs,private}
mkdir -p "$BASE/client/pki/"{cacerts,certs,private}

echo "[setup] Creating IPsec hybrid configuration files..."

cat > "$BASE/server/strongswan.conf" <<'EOF'
charon {
  load_modular = yes
  plugins {
    include strongswan.d/charon/*.conf
  }
  syslog {
    daemon {
      default = 1
    }
    auth {
      default = 1
    }
  }
}

include strongswan.d/*.conf
EOF

echo "[setup] server/strongswan.conf"

cat > "$BASE/server/swanctl.conf" <<'EOF'
connections {
  ipsec-hybrid {
    local_addrs = 192.168.76.143
    remote_addrs = 192.168.76.144

    local {
      auth  = pubkey
      certs = server.crt
      id    = "C=EC, O=VPN-PQC, CN=ipsec-hybrid-server"
    }

    remote {
      auth = pubkey
      id   = "C=EC, O=VPN-PQC, CN=ipsec-hybrid-client"
    }

    children {
      net-net {
        local_ts   = 10.30.0.1/32
        remote_ts  = 10.30.0.2/32

        esp_proposals = aes256gcm16-esn,aes256gcm16-noesn

        start_action = trap
        close_action = trap

        rekey_time = 3600
        life_time  = 3900
      }
    }

    version     = 2
    mobike      = no
    reauth_time = 7200
    rekey_time  = 7200

    proposals = aes256gcm16-prfsha384-curve25519-ke1_mlkem768,aes256gcm16-prfsha384-ecp256-ke1_mlkem768,aes256gcm16-prfsha256-ecp256
  }
}

secrets {
}
EOF

echo "[setup] server/swanctl.conf"

cat > "$BASE/client/strongswan.conf" <<'EOF'
charon {
  load_modular = yes
  plugins {
    include strongswan.d/charon/*.conf
  }
  syslog {
    daemon {
      default = 1
    }
    auth {
      default = 1
    }
  }
}

include strongswan.d/*.conf
EOF

echo "[setup] client/strongswan.conf"

cat > "$BASE/client/swanctl.conf" <<'EOF'
connections {
  ipsec-hybrid {
    local_addrs = 192.168.76.144
    remote_addrs = 192.168.76.143

    local {
      auth  = pubkey
      certs = client.crt
      id    = "C=EC, O=VPN-PQC, CN=ipsec-hybrid-client"
    }

    remote {
      auth = pubkey
      id   = "C=EC, O=VPN-PQC, CN=ipsec-hybrid-server"
    }

    children {
      net-net {
        # Client end: 10.30.0.2/32 <-> 10.30.0.1/32
        local_ts   = 10.30.0.2/32
        remote_ts  = 10.30.0.1/32

        esp_proposals = aes256gcm16-esn,aes256gcm16-noesn

        start_action = trap    
        close_action = none

        rekey_time = 3600
        life_time  = 3900
      }
    }

    version     = 2
    mobike      = no
    reauth_time = 7200
    rekey_time  = 7200

    proposals = aes256gcm16-prfsha384-curve25519-ke1_mlkem768,aes256gcm16-prfsha384-ecp256-ke1_mlkem768,aes256gcm16-prfsha256-ecp256
  }
}

secrets {
}
EOF

echo "[setup] client/swanctl.conf"

echo ""
echo "[setup] Configuration files created successfully"
echo ""
echo "Directory structure:"
tree -L 3 "$BASE" 2>/dev/null || find "$BASE" -type f | sed 's|^|  |'
echo ""
