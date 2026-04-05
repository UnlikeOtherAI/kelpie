# Kelpie Linux Headless Browser — Development Build
#
# Multi-stage build:
#   Stage 1: Build the C++ app with CEF
#   Stage 2: Slim runtime image
#
# Usage:
#   docker build -t kelpie-linux -f apps/linux/Dockerfile .
#   docker run -p 8420:8420 kelpie-linux

# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential cmake ninja-build wget tar pkg-config \
    libx11-dev libxcomposite-dev libxdamage-dev libxext-dev libxfixes-dev \
    libxrandr-dev libatk1.0-dev libatk-bridge2.0-dev libcups2-dev \
    libdrm-dev libgbm-dev libgtk-3-dev libpango1.0-dev libasound2-dev \
    libnspr4-dev libnss3-dev libavahi-client-dev libdbus-1-dev nlohmann-json3-dev \
    libcpp-httplib-dev \
    && rm -rf /var/lib/apt/lists/*

# Download CEF binary distribution (minimal)
# Using CEF 120 stable for Linux 64-bit
ARG CEF_VERSION=120.2.7+g4bc6a59+chromium-120.0.6099.234
ARG CEF_PLATFORM=linux64_minimal
RUN arch="$(dpkg --print-architecture)" && \
    mkdir -p /opt/cef && \
    if [ "$arch" = "amd64" ]; then \
      wget -q "https://cef-builds.spotifycdn.com/cef_binary_${CEF_VERSION}_${CEF_PLATFORM}.tar.bz2" \
        -O /tmp/cef.tar.bz2 || true; \
      if [ -f /tmp/cef.tar.bz2 ] && [ -s /tmp/cef.tar.bz2 ]; then \
        tar -xjf /tmp/cef.tar.bz2 -C /opt/cef --strip-components=1; \
      else \
        echo "CEF download failed — build will use stub headers"; \
        mkdir -p /opt/cef/include /opt/cef/Release /opt/cef/Resources; \
      fi; \
    else \
      echo "Skipping CEF download on unsupported architecture: $arch"; \
      mkdir -p /opt/cef/include /opt/cef/Release /opt/cef/Resources; \
    fi && \
    rm -f /tmp/cef.tar.bz2

# Build CEF wrapper library if real CEF was downloaded
RUN if [ "$(uname -m)" = "x86_64" ] && [ -f /opt/cef/CMakeLists.txt ]; then \
      cd /opt/cef && \
      cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSE_SANDBOX=OFF \
        -DCEF_RUNTIME_LIBRARY_FLAG="/MD" && \
      cmake --build build --target libcef_dll_wrapper; \
    fi

WORKDIR /src
COPY native/ native/
COPY apps/linux/ apps/linux/

# Build the Linux app and the native core in one configure step.
RUN cmake -B apps/linux/build -S apps/linux -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCEF_ROOT=/opt/cef && \
    cmake --build apps/linux/build

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    libx11-6 libxcomposite1 libxdamage1 libxext6 libxfixes3 \
    libxrandr2 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
    libdrm2 libgbm1 libgtk-3-0 libpango-1.0-0 libasound2 \
    libnspr4 libnss3 xvfb avahi-daemon dbus \
    libavahi-client3 \
    && rm -rf /var/lib/apt/lists/*

# Copy built app and CEF runtime
COPY --from=builder /src/apps/linux/build/kelpie-linux /opt/kelpie/kelpie-linux
COPY --from=builder /opt/cef/Release/ /opt/kelpie/
COPY --from=builder /opt/cef/Resources/ /opt/kelpie/

WORKDIR /opt/kelpie

# Create profile directory
RUN mkdir -p /data/kelpie

ENV DISPLAY=:99
ENV KELPIE_PROFILE_DIR=/data/kelpie
EXPOSE 8420

# Start Xvfb for offscreen rendering, dbus for avahi, then the browser
CMD ["sh", "-c", "\
  dbus-daemon --system --fork 2>/dev/null; \
  avahi-daemon --daemonize --no-chroot 2>/dev/null; \
  Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp & \
  sleep 1 && \
  exec ./kelpie-linux --headless --port 8420 --profile-dir /data/kelpie \
"]
