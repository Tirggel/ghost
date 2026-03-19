##############################################################
# Dockerfile
#
# Dieser Build compiliert:
#  1. Den Dart-Backend-Daemon (headless, läuft dauerhaft in Docker)
#  2. Die Flutter Desktop-App (als native Linux-Binary für den Host)
#
# Nutze 'docker-compose up -d' für den Gateway.
# Nutze 'docker-compose run --rm builder' um die App zu bauen.
##############################################################

# --- Stage 1: Build the backend daemon ---
FROM dart:stable AS backend-build

WORKDIR /app
COPY . .
RUN dart pub get
RUN dart compile exe bin/ghost.dart -o ghost-daemon

# --- Stage 2: Build the Flutter Desktop App ---
FROM ubuntu:22.04 AS frontend-build
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    curl git unzip xz-utils zip libglu1-mesa \
    clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev libstdc++-12-dev lld binutils \
    && rm -rf /var/lib/apt/lists/*

# Install Flutter SDK (stable)
RUN git clone https://github.com/flutter/flutter.git -b stable /flutter
ENV PATH="/flutter/bin:${PATH}"
RUN flutter config --no-analytics && flutter config --enable-linux-desktop

# Build the Flutter app
WORKDIR /src
COPY . .
WORKDIR /src/app
RUN flutter pub get
RUN flutter build linux --release

# --- Stage 3: Runtime Image for Gateway (headless) ---
FROM debian:stable-slim AS gateway

# Install runtime dependencies for the compiled Dart binary and ObjectBox
RUN apt-get update && apt-get install -y ca-certificates curl && \
    curl -L https://github.com/objectbox/objectbox-c/releases/download/v5.1.0/objectbox-linux-x64.tar.gz | tar xz -C /usr/lib libobjectbox.so && \
    apt-get purge -y curl && apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=backend-build /app/ghost-daemon ./

ENV GHOST_PORT=3000
ENV GHOST_HOST=0.0.0.0

# Run the backend daemon as a gateway server
CMD ["./ghost-daemon", "gateway"]

# --- Stage 4: Helper image to export the Flutter build bundle ---
FROM ubuntu:22.04 AS builder-export
COPY --from=frontend-build /src/app/build/linux/x64/release/bundle/ /output/
