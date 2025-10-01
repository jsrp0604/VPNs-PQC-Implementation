FROM pqc-base:22.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wireguard \
        wireguard-tools \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY wg0.conf /etc/wireguard/wg0.conf
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
