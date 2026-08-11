#!/usr/bin/env bash
# Build libxray.so from the Xray-core sources for the ABIs supported by the
# experimental core panel (arm64-v8a + x86_64) and drop the .so files into
# build/experimental/ for publication to the experimental-core branch.
#
# The stable core bundled in the APK comes from the
# dev.tfox.fluttervless:xray-android AAR on Maven Central. Experimental cores
# are built straight from XTLS/Xray-core so they can track upstream releases
# (including prereleases, which is how XTLS ships every new build).
#
# Usage:
#   scripts/build_xray_experimental.sh [VERSION]
#
#   VERSION is a Xray-core release, with or without the leading "v"
#   (e.g. "1.8.24" or "v1.8.24"). Defaults to the latest release tag.
#
# Output (override with XRAY_OUT_DIR):
#   build/experimental/libxray-arm64-v8a-<version>.so
#   build/experimental/libxray-x86_64-<version>.so
#
# Env knobs:
#   XRAY_BUILD_ARM64=0   skip the arm64-v8a build
#   XRAY_BUILD_X86_64=0  skip the x86_64 build
#
# Prerequisites:
#   - Go >= 1.26
#   - Android NDK 28.x (set ANDROID_NDK_HOME, default ~/Android/Sdk/ndk/28.2.13676358)
#   - python3 (for resolving the latest release tag)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${XRAY_OUT_DIR:-$ROOT/build/experimental}"
XRAY_REPO_URL="https://github.com/XTLS/Xray-core"
NDK_PATH="${ANDROID_NDK_HOME:-$HOME/Android/Sdk/ndk/28.2.13676358}"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    # XTLS marks every current Xray-core release as a prerelease, so
    # /releases/latest lags behind. Take the first release tag instead.
    VERSION="$(curl -fsSL --max-time 60 \
        "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=10" \
        | python3 -c "
import json, sys
for r in json.load(sys.stdin):
    t = r.get('tag_name', '')
    p = t.lstrip('v').split('.')
    if len(p) == 3 and all(x.isdigit() for x in p):
        print('.'.join(p))
        break
")"
fi
VERSION="${VERSION#v}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: not a Xray-core release version: $VERSION" >&2
    exit 1
fi
echo "Xray version: v$VERSION"

if ! command -v go >/dev/null; then
    echo "error: Go toolchain not found (go >= 1.26 required)" >&2
    exit 1
fi
if [ ! -d "$NDK_PATH" ]; then
    echo "error: NDK not found at $NDK_PATH" >&2
    echo "       install it or set ANDROID_NDK_HOME" >&2
    exit 1
fi

case "$(uname -s)" in
    Linux) TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64" ;;
    Darwin) TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/darwin-x86_64" ;;
    *) echo "error: unsupported host OS $(uname -s)" >&2; exit 1 ;;
esac
if [ ! -d "$TOOLCHAIN" ]; then
    echo "error: NDK toolchain not found at $TOOLCHAIN" >&2
    exit 1
fi

echo "Go:            $(go version)"
echo "NDK toolchain: $TOOLCHAIN"
echo "Output dir:    $OUT_DIR"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Cloning Xray-core at v${VERSION}..."
git clone --depth 1 --branch "v${VERSION}" "$XRAY_REPO_URL" "$WORK/Xray-core" >/dev/null 2>&1
if ! git -C "$WORK/Xray-core" rev-parse --short HEAD >/dev/null 2>&1; then
    echo "error: tag v${VERSION} not found in $XRAY_REPO_URL" >&2
    exit 1
fi

build_xray() {
    local arch=$1
    local goarch=$2
    local goarm=$3
    local target=$4
    local out="$WORK/$arch"
    mkdir -p "$out"
    echo "Building libxray.so for $arch..."
    (
        cd "$WORK/Xray-core"
        CGO_ENABLED=1 GOOS=android GOARCH="$goarch" GOARM="$goarm" \
        CC="$TOOLCHAIN/bin/${target}-clang" \
        CXX="$TOOLCHAIN/bin/${target}-clang++" \
        go build -trimpath -buildvcs=false \
            -gcflags "all=-l=4" \
            -ldflags "-X github.com/xtls/xray-core/core.build=v${VERSION} -s -w -buildid= -checklinkname=0 -linkmode=external -extldflags=-Wl,-z,max-page-size=16384" \
            -buildmode=pie \
            -o "$out/libxray.so" ./main
    )
    mkdir -p "$OUT_DIR"
    cp "$out/libxray.so" "$OUT_DIR/libxray-${arch}-${VERSION}.so"
    echo "Done: $OUT_DIR/libxray-${arch}-${VERSION}.so"
}

if [ "${XRAY_BUILD_ARM64:-1}" != "1" ]; then
    echo "Skipping arm64-v8a (XRAY_BUILD_ARM64=0)"
else
    build_xray "arm64-v8a" "arm64" "" "aarch64-linux-android21"
fi

if [ "${XRAY_BUILD_X86_64:-1}" != "1" ]; then
    echo "Skipping x86_64 (XRAY_BUILD_X86_64=0)"
else
    build_xray "x86_64" "amd64" "" "x86_64-linux-android21"
fi

echo "Build finished."
echo "Upload these files to a GitHub release tagged experimental-core-v${VERSION}:"
ls -1 "$OUT_DIR" 2>/dev/null || true
