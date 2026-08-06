#!/usr/bin/env bash
# Build the pinned Xray-core version into a local xray-android AAR override
# and publish it into android/xray-maven.
#
# The app pins flutterVlessXrayRuntimeVersion in android/gradle.properties,
# which is normally the latest dev.tfox.fluttervless:xray-android published by
# the flutter_vless plugin author on Maven Central. When the author has not yet
# published the pinned version (e.g. right after an upstream Xray-core release),
# Gradle would fail to resolve it. This script builds libxray.so from the
# Xray-core sources for all four ABIs and swaps it into the latest base AAR
# (keeping its geoip.dat/geosite.dat and libtun2socks.so), then drops the
# result into a local Maven repo that android/build.gradle.kts resolves first.
#
# Prerequisites:
#   - Go >= 1.26
#   - Android NDK 28.x (set ANDROID_NDK_HOME, default ~/Android/Sdk/ndk/28.2.13676358)
#   - python3 (for AAR repackaging)
#
# Usage:
#   scripts/build_xray_android.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_PROPERTIES="$ROOT/android/gradle.properties"
OUT_REPO="$ROOT/android/xray-maven"
XRAY_REPO_URL="https://github.com/XTLS/Xray-core"
MAVEN_METADATA="https://repo1.maven.org/maven2/dev/tfox/fluttervless/xray-android/maven-metadata.xml"
NDK_PATH="${ANDROID_NDK_HOME:-$HOME/Android/Sdk/ndk/28.2.13676358}"

VERSION="$(grep '^flutterVlessXrayRuntimeVersion=' "$GRADLE_PROPERTIES" | cut -d= -f2 | tr -d '[:space:]')"
if [ -z "$VERSION" ]; then
    echo "error: flutterVlessXrayRuntimeVersion not found in $GRADLE_PROPERTIES"
    exit 1
fi

if ! command -v go >/dev/null; then
    echo "error: Go toolchain not found (go >= 1.26 required)"
    exit 1
fi
if ! command -v python3 >/dev/null; then
    echo "error: python3 is required for AAR repackaging"
    exit 1
fi
if [ ! -d "$NDK_PATH" ]; then
    echo "error: NDK not found at $NDK_PATH"
    echo "       install it or set ANDROID_NDK_HOME"
    exit 1
fi

case "$(uname -s)" in
    Linux) TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64" ;;
    Darwin) TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/darwin-x86_64" ;;
    *) echo "error: unsupported host OS $(uname -s)"; exit 1 ;;
esac
if [ ! -d "$TOOLCHAIN" ]; then
    echo "error: NDK toolchain not found at $TOOLCHAIN"
    exit 1
fi

echo "Xray version:  $VERSION"
echo "Go:            $(go version)"
echo "NDK toolchain: $TOOLCHAIN"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

publish_aar() {
    local aar=$1
    local aar_dir="$OUT_REPO/dev/tfox/fluttervless/xray-android/${VERSION}"
    mkdir -p "$aar_dir"
    cp "$aar" "$aar_dir/xray-android-${VERSION}.aar"
    cat > "$aar_dir/xray-android-${VERSION}.pom" <<POM
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>dev.tfox.fluttervless</groupId>
  <artifactId>xray-android</artifactId>
  <version>${VERSION}</version>
  <packaging>aar</packaging>
</project>
POM
    echo "Done: $aar_dir/xray-android-${VERSION}.aar"
}

# If the pinned version is already on Maven Central (plugin author caught up),
# reuse it instead of rebuilding the core from source.
if curl -fsSL --max-time 60 -o "$WORK/xray-android-${VERSION}.aar" \
    "https://repo1.maven.org/maven2/dev/tfox/fluttervless/xray-android/${VERSION}/xray-android-${VERSION}.aar" 2>/dev/null; then
    echo "Version ${VERSION} is already published on Maven Central, reusing it."
    publish_aar "$WORK/xray-android-${VERSION}.aar"
    exit 0
fi

echo "Cloning Xray-core at v${VERSION}..."
git clone --depth 1 --branch "v${VERSION}" "$XRAY_REPO_URL" "$WORK/Xray-core" >/dev/null 2>&1
if ! git -C "$WORK/Xray-core" rev-parse --short HEAD >/dev/null 2>&1; then
    echo "error: tag v${VERSION} not found in $XRAY_REPO_URL"
    exit 1
fi

build_xray() {
    local arch=$1
    local goarch=$2
    local goarm=$3
    local target=$4
    local out="$WORK/jniLibs/$arch"
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
}

if [ "${XRAY_BUILD_ARM64:-1}" = "1" ]; then
    build_xray "arm64-v8a" "arm64" "" "aarch64-linux-android21"
fi
if [ "${XRAY_BUILD_ARMV7:-1}" = "1" ]; then
    build_xray "armeabi-v7a" "arm" "7" "armv7a-linux-androideabi21"
fi
if [ "${XRAY_BUILD_X86:-1}" = "1" ]; then
    build_xray "x86" "386" "" "i686-linux-android21"
fi
if [ "${XRAY_BUILD_X86_64:-1}" = "1" ]; then
    build_xray "x86_64" "amd64" "" "x86_64-linux-android21"
fi

echo "Fetching latest base AAR from Maven Central..."
BASE_VERSION="$(curl -fsSL --max-time 30 "$MAVEN_METADATA" | grep -o '<latest>[^<]*</latest>' | head -1 | sed 's/<[^>]*>//g')"
if [ -z "$BASE_VERSION" ]; then
    BASE_VERSION="$VERSION"
fi
BASE_URL="https://repo1.maven.org/maven2/dev/tfox/fluttervless/xray-android/${BASE_VERSION}/xray-android-${BASE_VERSION}.aar"
curl -fsSL --max-time 120 -o "$WORK/base.aar" "$BASE_URL"

echo "Repackaging xray-android-${VERSION}.aar..."
python3 - "$WORK/base.aar" "$WORK" "$VERSION" <<'PY'
import os
import shutil
import sys
import zipfile

base_aar, work, version = sys.argv[1], sys.argv[2], sys.argv[3]
base = os.path.join(work, "base")
out = os.path.join(work, f"xray-android-{version}.aar")
abis = ("arm64-v8a", "armeabi-v7a", "x86", "x86_64")

with zipfile.ZipFile(base_aar) as z:
    z.extractall(base)

for abi in abis:
    shutil.copy(
        os.path.join(work, "jniLibs", abi, "libxray.so"),
        os.path.join(base, "jni", abi, "libxray.so"),
    )

if os.path.exists(out):
    os.remove(out)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(base):
        for f in files:
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, base))
PY

publish_aar "$WORK/xray-android-${VERSION}.aar"
