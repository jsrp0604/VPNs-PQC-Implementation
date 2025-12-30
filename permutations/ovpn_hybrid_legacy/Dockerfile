FROM ubuntu:22.04 AS builder
ARG DEBIAN_FRONTEND=noninteractive

ARG OQS_OPT_TARGET=generic
ARG WITH_OQS_BENCH=0

RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake ninja-build build-essential pkg-config \
    libssl-dev libtool autoconf automake libltdl-dev \
    libcap-ng-dev liblz4-dev liblzo2-dev libzstd-dev \
    m4 patch dpkg-dev ca-certificates xz-utils bzip2 \
    python3-docutils \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/liboqs
RUN git clone --depth 1 https://github.com/open-quantum-safe/liboqs.git .
RUN cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DOQS_DIST_BUILD=OFF \
      -DOQS_OPT_TARGET=${OQS_OPT_TARGET} \
      -DOQS_BUILD_ONLY_LIB=ON \
      -DOQS_ENABLE_KEM_KYBER=ON \
      -DOQS_ENABLE_SIG_DILITHIUM=ON \
 && cmake --build build \
 && cmake --install build

RUN if [ "${WITH_OQS_BENCH}" = "1" ]; then \
      cmake -S . -B build-bench -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DOQS_DIST_BUILD=OFF \
        -DOQS_OPT_TARGET=${OQS_OPT_TARGET} \
        -DOQS_BUILD_ONLY_LIB=OFF \
        -DOQS_ENABLE_KEM_KYBER=ON \
        -DOQS_ENABLE_SIG_DILITHIUM=ON \
      && cmake --build build-bench ; \
    fi

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/oqs.conf && ldconfig

WORKDIR /tmp/oqs-provider
RUN git clone --depth 1 https://github.com/open-quantum-safe/oqs-provider.git .
RUN cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_LIBDIR=lib \
 && cmake --build build \
 && cmake --install build

RUN mkdir -p /opt/oqs/ossl-modules && \
    if [ -f /usr/local/lib/ossl-modules/oqsprovider.so ]; then \
      cp /usr/local/lib/ossl-modules/oqsprovider.so /opt/oqs/ossl-modules/oqsprovider.so ; \
    elif [ -f /usr/lib/ossl-modules/oqsprovider.so ]; then \
      cp /usr/lib/ossl-modules/oqsprovider.so /opt/oqs/ossl-modules/oqsprovider.so ; \
    elif [ -f /usr/local/lib64/ossl-modules/oqsprovider.so ]; then \
      cp /usr/local/lib64/ossl-modules/oqsprovider.so /opt/oqs/ossl-modules/oqsprovider.so ; \
    else \
      find / -name oqsprovider.so -maxdepth 6 -print -quit | xargs -r -I{} cp "{}" /opt/oqs/ossl-modules/oqsprovider.so ; \
    fi

WORKDIR /tmp/openvpn
RUN git clone --depth 1 --branch v2.6.10 https://github.com/OpenVPN/openvpn.git .
RUN autoreconf -vi \
 && ./configure --disable-debug --disable-dco --disable-plugin-auth-pam \
 && make -j"$(nproc)" \
 && make install

RUN strip /usr/local/sbin/openvpn || true \
 && strip /usr/local/lib/liboqs*.so* || true \
 && strip /opt/oqs/ossl-modules/oqsprovider.so || true

FROM pqc-base:22.04
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl ca-certificates iproute2 iputils-ping procps jq \
    libcap-ng0 liblz4-1 liblzo2-2 libzstd1 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/lib/liboqs*.so* /usr/local/lib/
RUN mkdir -p /usr/local/lib/ossl-modules
COPY --from=builder /opt/oqs/ossl-modules/oqsprovider.so /usr/local/lib/ossl-modules/oqsprovider.so
COPY --from=builder /usr/local/sbin/openvpn /usr/local/sbin/openvpn

RUN ldconfig
ENV OPENSSL_MODULES=/usr/local/lib/ossl-modules

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
