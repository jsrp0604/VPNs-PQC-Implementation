FROM pqc-base:22.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      strongswan strongswan-swanctl strongswan-pki \
      iproute2 tcpdump kmod \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/log && touch /var/log/strongswan.log

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
