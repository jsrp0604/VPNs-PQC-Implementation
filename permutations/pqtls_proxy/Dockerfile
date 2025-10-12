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

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl ca-certificates iproute2 iputils-ping \
    procps socat time jq bc && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/lib/liboqs*.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/ossl-modules/oqsprovider.so \
                    /usr/local/lib/ossl-modules/oqsprovider.so
COPY --from=builder /usr/local/include/oqs /usr/local/include/oqs

RUN ldconfig

ENV OPENSSL_MODULES=/usr/local/lib/ossl-modules
ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

WORKDIR /app
CMD ["/bin/bash"]