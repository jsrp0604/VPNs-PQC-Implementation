FROM pqc-base:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
      openvpn easy-rsa jq && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /dev/net || true && \
    [ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200 || true

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /app
ENTRYPOINT ["/entrypoint.sh"]
