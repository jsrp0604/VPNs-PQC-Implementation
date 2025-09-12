FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates iproute2 iperf3 iputils-ping net-tools ethtool tcpdump socat curl wget gnupg make gcc g++ \
    python3 python3-venv python3-pip openssl libssl-dev chrony sudo \
 && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --no-cache-dir psutil

COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /app
ENTRYPOINT ["/entrypoint.sh"]
