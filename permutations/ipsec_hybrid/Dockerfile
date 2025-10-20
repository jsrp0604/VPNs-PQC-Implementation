FROM ubuntu:22.04 AS builder
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake ninja-build build-essential pkg-config autoconf automake libtool \
    libssl-dev libcurl4-openssl-dev libjson-c-dev \
    bison flex gettext gperf \
    ca-certificates wget \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/openssl
RUN wget https://github.com/openssl/openssl/releases/download/openssl-3.5.0/openssl-3.5.0.tar.gz && \
    tar xzf openssl-3.5.0.tar.gz && \
    cd openssl-3.5.0 && \
    ./Configure --prefix=/usr/local/openssl-3.5 --openssldir=/usr/local/openssl-3.5 shared && \
    make -j$(nproc) && \
    make install

ENV PKG_CONFIG_PATH=/usr/local/openssl-3.5/lib64/pkgconfig:/usr/local/openssl-3.5/lib/pkgconfig
ENV LD_LIBRARY_PATH=/usr/local/openssl-3.5/lib64:/usr/local/openssl-3.5/lib

WORKDIR /tmp/strongswan
RUN wget --no-check-certificate https://download.strongswan.org/strongswan-6.0.2.tar.bz2 && \
    tar xjf strongswan-6.0.2.tar.bz2 && \
    cd strongswan-6.0.2 && \
    ./configure \
      --prefix=/usr \
      --sysconfdir=/etc \
      --enable-openssl \
      --enable-ml \
      --enable-eap-identity \
      --enable-eap-md5 \
      --enable-eap-dynamic \
      --enable-eap-tls \
      --enable-vici \
      --enable-swanctl \
      --disable-stroke \
      --disable-scepclient \
      --with-openssl-lib=/usr/local/openssl-3.5/lib64 \
      --with-openssl-include=/usr/local/openssl-3.5/include \
 && make -j$(nproc) \
 && make install DESTDIR=/tmp/strongswan-install

RUN find /tmp/strongswan-install -type f -executable -exec strip --strip-unneeded {} + 2>/dev/null || true

FROM pqc-base:22.04
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    iproute2 iptables iputils-ping tcpdump jq kmod \
    libcurl4 libjson-c5 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/openssl-3.5 /usr/local/openssl-3.5
COPY --from=builder /tmp/strongswan-install/usr/lib /usr/lib
COPY --from=builder /tmp/strongswan-install/usr/sbin /usr/sbin
COPY --from=builder /tmp/strongswan-install/usr/bin /usr/bin
COPY --from=builder /tmp/strongswan-install/usr/libexec /usr/libexec
COPY --from=builder /tmp/strongswan-install/etc /etc

RUN echo "/usr/local/openssl-3.5/lib64" > /etc/ld.so.conf.d/openssl-3.5.conf && \
    echo "/usr/local/openssl-3.5/lib" >> /etc/ld.so.conf.d/openssl-3.5.conf && \
    ldconfig

RUN mkdir -p /etc/swanctl/{x509ca,x509,private,rsa,ecdsa,pkcs12} \
             /var/log \
             /var/run && \
    touch /var/log/strongswan.log

ENV LD_LIBRARY_PATH=/usr/local/openssl-3.5/lib64:/usr/local/openssl-3.5/lib
ENV PATH=/usr/local/openssl-3.5/bin:$PATH

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /app
ENTRYPOINT ["/entrypoint.sh"]