# ====== BUILDER STAGE =======
FROM rust:1.75-slim AS builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential cmake pkg-config \
    libsodium-dev ca-certificates \
    clang libclang-dev llvm-dev \
 && rm -rf /var/lib/apt/lists/*

# Build Rosenpass
WORKDIR /build/rosenpass
RUN git clone --depth 1 --branch v0.2.2 \
    https://github.com/rosenpass/rosenpass.git . && \
    cargo build --release

# ====== RUNTIME STAGE =======
FROM pqc-base:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    wireguard wireguard-tools iproute2 iputils-ping \
    libsodium23 procps jq && \
    rm -rf /var/lib/apt/lists/*

# Copy Rosenpass binaries from builder
COPY --from=builder /build/rosenpass/target/release/rosenpass /usr/local/bin/rosenpass
COPY --from=builder /build/rosenpass/target/release/rp /usr/local/bin/rp

# Set correct permissions
RUN chmod +x /usr/local/bin/rosenpass /usr/local/bin/rp

# Verify installation
RUN rosenpass --version && \
    rp --version && \
    wg --version

WORKDIR /app

# Override the problematic entrypoint from pqc-base
ENTRYPOINT []
CMD ["/bin/bash"]
