#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

REPEATS="${1:-10}"
TAG=""   

CSV="/data/crypto_microbench.csv"
DBG="/data/crypto_microbench_debug.txt"
[[ -f "$CSV" ]] || echo "timestamp,algorithm,class,operation,p50_ms,notes" >> "$CSV"

now() { date -Iseconds; }
emit_row() { printf "%s,%s,%s,%s,%.4f,%s\n" "$1" "$2" "$3" "$4" "$5" "$6" >> "$CSV"; }
ops_to_ms() { awk -v o="$1" 'BEGIN{printf "%.4f", (o>0? 1000.0/o : 0)}'; }

ossl3() { openssl version 2>/dev/null | grep -q 'OpenSSL 3'; }
ossl_speed() { openssl speed -seconds 3 "$1" 2>/dev/null || true; }

bench_rsa() {
  local bits="$1" notes="$2"
  ossl3 || { echo "[warn] OpenSSL 3 required (RSA-$bits)" | tee -a "$DBG" >/dev/null; return 0; }
  local out; out="$(ossl_speed "rsa$bits")"
  echo "[dbg] ========= rsa$bits =========" >> "$DBG"; echo "$out" | head -n 200 >> "$DBG"
  local sign_ops="" verify_ops=""

  if echo "$out" | grep -q 'sign/s' && echo "$out" | grep -q 'verify/s'; then
    read -r sign_ops verify_ops < <(
      echo "$out" | awk '
        /sign\/s/ && /verify\/s/ {hdr=1; next}
        hdr && $1 ~ /^rsa$/ && $2 ~ /^'"$bits"'$/ {
          for(i=NF;i>0;i--) if($i ~ /^[0-9.]+$/){v2=$i; break}
          for(j=i-1;j>0;j--) if($j ~ /^[0-9.]+$/){v1=$j; break}
          if (v1!="" && v2!="") {print v1, v2; exit}
        }'
    )
  fi
  if [[ -z "${sign_ops:-}" || -z "${verify_ops:-}" ]]; then
    local line; line="$(echo "$out" | awk '/^rsa .*bits/ {print; exit}')"
    if [[ -n "$line" ]]; then
      sign_ops="$(echo "$line"   | awk '{for(i=1;i<=NF;i++) if($i ~ /sign\/s/)   {for(j=i-1;j>0;j--) if($j ~ /^[0-9.]+$/){print $j; break}}}')"
      verify_ops="$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /verify\/s/) {for(j=i-1;j>0;j--) if($j ~ /^[0-9.]+$/){print $j; break}}}')"
    fi
  fi
  [[ -z "${sign_ops:-}"   ]] && sign_ops="$(echo "$out" | awk '/private/ {for(i=NF;i>0;i--) if($i ~ /^[0-9.]+$/){print $i; exit}}')"
  [[ -z "${verify_ops:-}" ]] && verify_ops="$(echo "$out" | awk '/public/  {for(i=NF;i>0;i--) if($i ~ /^[0-9.]+$/){print $i; exit}}')"

  [[ -n "${sign_ops:-}"   ]] && emit_row "$(now)" "RSA-$bits" "sig" "sign"   "$(ops_to_ms "$sign_ops")"   "$notes"
  [[ -n "${verify_ops:-}" ]] && emit_row "$(now)" "RSA-$bits" "sig" "verify" "$(ops_to_ms "$verify_ops")" "$notes"
}

bench_ecdh() {
  local label="$1" alg1="$2" alg2="$3" notes="$4"
  ossl3 || { echo "[warn] OpenSSL 3 required ($label)" | tee -a "$DBG" >/dev/null; return 0; }
  local out; out="$(ossl_speed "$alg1")"; [[ -z "$out" ]] && out="$(ossl_speed "$alg2")"
  echo "[dbg] ========= $label ($alg1|$alg2) =========" >> "$DBG"; echo "$out" | head -n 200 >> "$DBG"
  local ops; ops="$(
    echo "$out" | awk -v a="$alg1" -v b="$alg2" '
      $0 ~ a || $0 ~ b { for(i=NF;i>0;i--) if($i ~ /^[0-9.]+$/){print $i; exit} }' | head -n1
  )"
  [[ -n "${ops:-}" ]] && emit_row "$(now)" "$label" "ecdh" "ecdh" "$(ops_to_ms "$ops")" "$notes"
}

bench_kem() {
  local alg="$1" notes="$2"
  ossl3 || return 0
  local out; out="$(ossl_speed "$alg")"
  echo "[dbg] ========= $alg =========" >> "$DBG"; echo "$out" | head -n 200 >> "$DBG"
  local enc_ops dec_ops
  enc_ops="$(echo "$out" | awk '/encap/ {for(i=NF;i>0;i--) if($i ~ /^[0-9.]+$/){print $i; exit}}' | head -n1)"
  dec_ops="$(echo "$out" | awk '/decap/ {for(i=NF;i>0;i--) if($i ~ /^[0-9.]+$/){print $i; exit}}' | head -n1)"
  [[ -n "${enc_ops:-}" ]] && emit_row "$(now)" "${alg^^}" "kem" "encap" "$(ops_to_ms "$enc_ops")" "$notes"
  [[ -n "${dec_ops:-}" ]] && emit_row "$(now)" "${alg^^}" "kem" "decap" "$(ops_to_ms "$dec_ops")" "$notes"
}

bench_sig() {
  local alg="$1" notes="$2"
  ossl3 || return 0
  local out; out="$(ossl_speed "$alg")"
  echo "[dbg] ========= $alg =========" >> "$DBG"; echo "$out" | head -n 200 >> "$DBG"
  local sign_ops verify_ops
  sign_ops="$(echo "$out"   | awk '/sign/   {for(i=NF;i>0;i--) if($i ~ /^[0-9.]+$/){print $i; exit}}' | head -n1)"
  verify_ops="$(echo "$out" | awk '/verify/ {for(i=NF;i>0;i--) if($i ~ /^[0-9.]+$/){print $i; exit}}' | head -n1)"
  [[ -n "${sign_ops:-}"   ]] && emit_row "$(now)" "${alg^^}" "sig" "sign"   "$(ops_to_ms "$sign_ops")"   "$notes"
  [[ -n "${verify_ops:-}" ]] && emit_row "$(now)" "${alg^^}" "sig" "verify" "$(ops_to_ms "$verify_ops")" "$notes"
}

run_repeat() { local fn="$1"; shift; for _ in $(seq 1 "$REPEATS"); do "$fn" "$@"; done; }

# classic 
run_repeat bench_rsa  2048 "$TAG"
run_repeat bench_ecdh "X25519" "x25519" "ecdhx25519" "$TAG"
run_repeat bench_ecdh "P-256"  "ecdhp256" "prime256v1" "$TAG"

# pqc 
run_repeat bench_kem kyber768   "$TAG"
run_repeat bench_sig dilithium2 "$TAG"

echo "[microbench] wrote to $CSV; debug -> $DBG"
