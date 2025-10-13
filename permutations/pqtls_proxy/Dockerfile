FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git ninja-build ca-certificates \
    libssl-dev wget

WORKDIR /build/liboqs
RUN git clone --depth 1 --branch 0.11.0 \
    https://github.com/open-quantum-safe/liboqs.git . && \
    mkdir build && cd build && \
    cmake -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DBUILD_SHARED_LIBS=ON \
      -DOQS_USE_OPENSSL=ON \
      .. && \
    ninja && ninja install

WORKDIR /build/oqsprovider
RUN git clone --depth 1 --branch 0.7.0 \
    https://github.com/open-quantum-safe/oqs-provider.git . && \
    cmake -S . -B _build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DOQS_PROVIDER_BUILD_STATIC=OFF && \
    cmake --build _build && \
    cmake --install _build

RUN mkdir -p /opt/oqs-provider && \
    if [ -f /usr/local/lib/ossl-modules/oqsprovider.so ]; then \
      cp /usr/local/lib/ossl-modules/oqsprovider.so /opt/oqs-provider/oqsprovider.so; \
    elif [ -f /usr/lib/x86_64-linux-gnu/ossl-modules/oqsprovider.so ]; then \
      cp /usr/lib/x86_64-linux-gnu/ossl-modules/oqsprovider.so /opt/oqs-provider/oqsprovider.so; \
    elif [ -f /usr/local/lib64/ossl-modules/oqsprovider.so ]; then \
      cp /usr/local/lib64/ossl-modules/oqsprovider.so /opt/oqs-provider/oqsprovider.so; \
    else \
      echo "ERROR: oqsprovider.so not found in expected paths"; \
      find /usr -name oqsprovider.so 2>/dev/null; \
      exit 1; \
    fi

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl ca-certificates iproute2 iputils-ping \
    procps socat time jq bc && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/lib/liboqs*.so* /usr/local/lib/
COPY --from=builder /opt/oqs-provider/oqsprovider.so /usr/local/lib/ossl-modules/oqsprovider.so
COPY --from=builder /usr/local/include/oqs /usr/local/include/oqs

RUN mkdir -p /usr/local/lib/ossl-modules && \
    ldconfig

ENV OPENSSL_MODULES=/usr/local/lib/ossl-modules
ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

RUN openssl version && \
    openssl list -providers -provider oqsprovider -provider default 2>&1 | tee /tmp/provider-check.log && \
    grep -q "name: OpenSSL OQS Provider" /tmp/provider-check.log || \
    (echo "ERROR: oqsprovider not loading correctly"; cat /tmp/provider-check.log; exit 1)

WORKDIR /app
CMD ["/bin/bash"]