#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

CLASSICAL_REPEATS="${1:-750}"
PQC_REPEATS="${2:-750}"
PQC_DURATION="${3:-3}"  
CSV="/data/crypto_algorithms.csv"
DBG="/data/crypto_algorithms_debug.txt"

# CSV header
echo "timestamp,algorithm,class,operation,time_ms,ops_per_sec,notes" > "$CSV"
> "$DBG"

echo "Classical algorithms: $CLASSICAL_REPEATS repetitions (3s each)" | tee -a "$DBG"
echo "PQC algorithms: $PQC_REPEATS repetitions (${PQC_DURATION}s each)" | tee -a "$DBG"
echo "" | tee -a "$DBG"

now() { date -Iseconds; }
emit_row() {
    printf "%s,%s,%s,%s,%.4f,%.2f,%s\n" "$1" "$2" "$3" "$4" "$5" "$6" "$7" >> "$CSV"
}
ops_to_ms() {
    awk -v o="$1" 'BEGIN{printf "%.4f", (o>0? 1000.0/o : 0)}'
}

# Classical Algos
echo "[1/9] X25519 (ECDH)" | tee -a "$DBG"
for i in $(seq 1 "$CLASSICAL_REPEATS"); do
    OUTPUT=$(openssl speed -seconds 3 ecdhx25519 2>&1)
    echo "$OUTPUT" >> "$DBG"
    OPS=$(echo "$OUTPUT" | grep -i "x25519\|ecdh" | grep -o '[0-9][0-9.]*' | tail -1)
    if [[ -n "$OPS" ]]; then
        MS=$(ops_to_ms "$OPS")
        emit_row "$(now)" "X25519" "ecdh" "ecdh" "$MS" "$OPS" "classical"
    fi
done

echo "[2/9] P-256 (ECDH)" | tee -a "$DBG"
for i in $(seq 1 "$CLASSICAL_REPEATS"); do
    OUTPUT=$(openssl speed -seconds 3 ecdhp256 2>&1)
    echo "$OUTPUT" >> "$DBG"
    OPS=$(echo "$OUTPUT" | grep -i "prime256v1\|ecdh\|p256\|256 bit" | grep -o '[0-9][0-9.]*' | tail -1)
    if [[ -n "$OPS" ]]; then
        MS=$(ops_to_ms "$OPS")
        emit_row "$(now)" "P-256" "ecdh" "ecdh" "$MS" "$OPS" "classical"
    fi
done

echo "[3/9] RSA-2048 (Signature)" | tee -a "$DBG"
for i in $(seq 1 "$CLASSICAL_REPEATS"); do
    OUTPUT=$(openssl speed -seconds 3 rsa2048 2>&1)
    echo "$OUTPUT" >> "$DBG"
    SUMMARY_LINE=$(echo "$OUTPUT" | grep "^rsa 2048 bits")
    SIGN_OPS=$(echo "$SUMMARY_LINE" | awk '{print $(NF-1)}')
    VERIFY_OPS=$(echo "$SUMMARY_LINE" | awk '{print $NF}')

    if [[ -n "$SIGN_OPS" ]] && [[ "$SIGN_OPS" != "2048" ]]; then
        MS=$(ops_to_ms "$SIGN_OPS")
        emit_row "$(now)" "RSA-2048" "sig" "sign" "$MS" "$SIGN_OPS" "classical"
    fi
    if [[ -n "$VERIFY_OPS" ]] && [[ "$VERIFY_OPS" != "2048" ]]; then
        MS=$(ops_to_ms "$VERIFY_OPS")
        emit_row "$(now)" "RSA-2048" "sig" "verify" "$MS" "$VERIFY_OPS" "classical"
    fi
done

echo "[4/9] Ed25519 (Signature)" | tee -a "$DBG"
for i in $(seq 1 "$CLASSICAL_REPEATS"); do
    OUTPUT=$(openssl speed -seconds 3 ed25519 2>&1)
    echo "$OUTPUT" >> "$DBG"
    SUMMARY_LINE=$(echo "$OUTPUT" | grep "EdDSA (Ed25519)")
    SIGN_OPS=$(echo "$SUMMARY_LINE" | awk '{print $(NF-1)}')
    VERIFY_OPS=$(echo "$SUMMARY_LINE" | awk '{print $NF}')

    if [[ -n "$SIGN_OPS" ]]; then
        MS=$(ops_to_ms "$SIGN_OPS")
        emit_row "$(now)" "Ed25519" "sig" "sign" "$MS" "$SIGN_OPS" "classical"
    fi
    if [[ -n "$VERIFY_OPS" ]]; then
        MS=$(ops_to_ms "$VERIFY_OPS")
        emit_row "$(now)" "Ed25519" "sig" "verify" "$MS" "$VERIFY_OPS" "classical"
    fi
done

echo "[5/9] ECDSA-P256 (Signature)" | tee -a "$DBG"
for i in $(seq 1 "$CLASSICAL_REPEATS"); do
    OUTPUT=$(openssl speed -seconds 3 ecdsap256 2>&1)
    echo "$OUTPUT" >> "$DBG"
    SUMMARY_LINE=$(echo "$OUTPUT" | grep "ecdsa (nistp256)")
    SIGN_OPS=$(echo "$SUMMARY_LINE" | awk '{print $(NF-1)}')
    VERIFY_OPS=$(echo "$SUMMARY_LINE" | awk '{print $NF}')

    if [[ -n "$SIGN_OPS" ]]; then
        MS=$(ops_to_ms "$SIGN_OPS")
        emit_row "$(now)" "ECDSA-P256" "sig" "sign" "$MS" "$SIGN_OPS" "classical"
    fi
    if [[ -n "$VERIFY_OPS" ]]; then
        MS=$(ops_to_ms "$VERIFY_OPS")
        emit_row "$(now)" "ECDSA-P256" "sig" "verify" "$MS" "$VERIFY_OPS" "classical"
    fi
done

# PQC Algos 
# check for oqs 
if command -v speed_kem >/dev/null 2>&1 && command -v speed_sig >/dev/null 2>&1; then
    echo "" | tee -a "$DBG"
    echo "Post-Quantum Algorithms" | tee -a "$DBG"

    # parse speed_kem/speed_sig output
    parse_pqc_bench() {
        local tool="$1"
        local alg="$2"
        local label="$3"
        local class="$4"

        for rep in $(seq 1 "$PQC_REPEATS"); do
            OUTPUT=$($tool --duration "$PQC_DURATION" "$alg" 2>&1)
            echo "Repetition $rep" >> "$DBG"
            echo "$OUTPUT" >> "$DBG"


            if [[ "$class" == "kem" ]]; then
                # kems: keygen, encaps, decaps times in ms
                KEYGEN_US=$(echo "$OUTPUT" | grep "^keygen" | awk '{print $7}')
                ENCAPS_US=$(echo "$OUTPUT" | grep "^encaps" | awk '{print $7}')
                DECAPS_US=$(echo "$OUTPUT" | grep "^decaps" | awk '{print $7}')

                if [[ -n "$KEYGEN_US" ]]; then
                    MS=$(echo "scale=4; $KEYGEN_US / 1000" | bc)
                    OPS=$(echo "scale=2; 1000000 / $KEYGEN_US" | bc)
                    emit_row "$(now)" "$label" "kem" "keygen" "$MS" "$OPS" "pqc"
                fi

                if [[ -n "$ENCAPS_US" ]]; then
                    MS=$(echo "scale=4; $ENCAPS_US / 1000" | bc)
                    OPS=$(echo "scale=2; 1000000 / $ENCAPS_US" | bc)
                    emit_row "$(now)" "$label" "kem" "encap" "$MS" "$OPS" "pqc"
                fi

                if [[ -n "$DECAPS_US" ]]; then
                    MS=$(echo "scale=4; $DECAPS_US / 1000" | bc)
                    OPS=$(echo "scale=2; 1000000 / $DECAPS_US" | bc)
                    emit_row "$(now)" "$label" "kem" "decap" "$MS" "$OPS" "pqc"
                fi
            else
                # signatures: keypair, sign, verify
                KEYGEN_US=$(echo "$OUTPUT" | grep "^keypair" | awk '{print $7}')
                SIGN_US=$(echo "$OUTPUT" | grep "^sign" | awk '{print $7}')
                VERIFY_US=$(echo "$OUTPUT" | grep "^verify" | awk '{print $7}')

                if [[ -n "$KEYGEN_US" ]]; then
                    MS=$(echo "scale=4; $KEYGEN_US / 1000" | bc)
                    OPS=$(echo "scale=2; 1000000 / $KEYGEN_US" | bc)
                    emit_row "$(now)" "$label" "sig" "keygen" "$MS" "$OPS" "pqc"
                fi

                if [[ -n "$SIGN_US" ]]; then
                    MS=$(echo "scale=4; $SIGN_US / 1000" | bc)
                    OPS=$(echo "scale=2; 1000000 / $SIGN_US" | bc)
                    emit_row "$(now)" "$label" "sig" "sign" "$MS" "$OPS" "pqc"
                fi

                if [[ -n "$VERIFY_US" ]]; then
                    MS=$(echo "scale=4; $VERIFY_US / 1000" | bc)
                    OPS=$(echo "scale=2; 1000000 / $VERIFY_US" | bc)
                    emit_row "$(now)" "$label" "sig" "verify" "$MS" "$OPS" "pqc"
                fi
            fi
        done  # 

        echo "Completed $PQC_REPEATS repetitions for $label" | tee -a "$DBG"
    }

    echo "[6/9] ML-KEM-768 (KEM)" | tee -a "$DBG"
    parse_pqc_bench "speed_kem" "ML-KEM-768" "ML-KEM-768" "kem"

    echo "[7/9] Classic-McEliece-460896 (KEM)" | tee -a "$DBG"
    parse_pqc_bench "speed_kem" "Classic-McEliece-460896" "Classic-McEliece-460896" "kem"

    echo "[8/9] ML-DSA-65 (Signature)" | tee -a "$DBG"
    parse_pqc_bench "speed_sig" "ML-DSA-65" "ML-DSA-65" "sig"
else
    echo "" | tee -a "$DBG"
    echo "WARNING: PQC benchmark tools not found" | tee -a "$DBG"
fi

echo "" | tee -a "$DBG"
echo "Benchmark Complete" | tee -a "$DBG"
echo "Results: $CSV" | tee -a "$DBG"
echo "Debug log: $DBG" | tee -a "$DBG"
echo "Total entries: $(tail -n +2 "$CSV" | wc -l)" | tee -a "$DBG"
