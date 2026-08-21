# Reproducible Linux build: the exact Flutter version and toolchain are pinned
# by the base image, so a build on any machine produces the same bundle.
#
#   docker build -t affection-vpn-builder .
#   docker run --rm -v "$PWD/out:/out" affection-vpn-builder
#
# The GUI itself needs an X server to display; this image is primarily an
# artifact factory (and the source of the bundle for the update-server image).

FROM ghcr.io/cirruslabs/flutter:3.44.8 AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
      libgtk-3-dev libayatana-appindicator3-dev liblzma-dev \
      ninja-build clang cmake pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Dependencies first: this layer is cached until pubspec files change.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build linux --release

FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
      libgtk-3-0t64 libayatana-appindicator3-1 liblzma5 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/build/linux/x64/release/bundle /app

WORKDIR /app
ENTRYPOINT ["/app/affection_vpn"]
