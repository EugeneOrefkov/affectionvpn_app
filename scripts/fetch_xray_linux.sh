#!/usr/bin/env bash
# Stage the pinned Xray-core Linux build + geo databases into the Flutter
# Linux release bundle so the packaged app (deb / tar.gz / PKGBUILD) is fully
# self-contained and needs no manual xray install.
#
# The pinned version comes from flutterVlessXrayRuntimeVersion in
# android/gradle.properties (the same core the Android build uses). The
# official Xray-core release zip carries the linux binary and the
# geoip.dat/geosite.dat databases; its sha256 is verified against the
# companion .dgst file before extraction.
#
# The app already discovers a core at /opt/affection-vpn/xray and looks for
# geoip.dat/geosite.dat next to it (linux_vless_platform.dart), so no Dart
# change is required once these files are placed in the bundle root.
#
# Usage:
#   scripts/fetch_xray_linux.sh [--out DIR]   (default: build/linux/x64/release/bundle)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_PROPERTIES="$ROOT/android/gradle.properties"
OUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --out)
            OUT="$2"
            shift 2
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$OUT" ]; then
    OUT="$ROOT/build/linux/x64/release/bundle"
fi

VERSION="$(grep '^flutterVlessXrayRuntimeVersion=' "$GRADLE_PROPERTIES" | cut -d= -f2 | tr -d '[:space:]')"
if [ -z "$VERSION" ]; then
    echo "error: flutterVlessXrayRuntimeVersion not found in $GRADLE_PROPERTIES"
    exit 1
fi

# Idempotent: a core for this version is already staged, skip the download so
# repeated builds (and local `make` runs) stay fast and offline-safe.
if [ -f "$OUT/xray" ] && [ -f "$OUT/xray-version" ] && \
   [ "$(cat "$OUT/xray-version")" = "$VERSION" ]; then
    echo "xray $VERSION already staged in $OUT, skipping download."
    exit 0
fi

BASE="https://github.com/XTLS/Xray-core/releases/download/v$VERSION"
ZIP="Xray-linux-64.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading $BASE/$ZIP ..."
curl -fsSL --max-time 300 -o "$WORK/$ZIP" "$BASE/$ZIP"
curl -fsSL --max-time 60 -o "$WORK/$ZIP.dgst" "$BASE/$ZIP.dgst"

echo "Verifying sha256 against $ZIP.dgst ..."
EXPECTED="$(grep '^SHA2-256=' "$WORK/$ZIP.dgst" | sed 's/^SHA2-256=[[:space:]]*//' | tr -d '[:space:]')"
ACTUAL="$(sha256sum "$WORK/$ZIP" | awk '{print $1}')"
if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "error: sha256 mismatch for $ZIP" >&2
    echo "  expected: $EXPECTED" >&2
    echo "  actual:   $ACTUAL" >&2
    exit 1
fi

echo "Extracting xray + geo assets into $OUT ..."
mkdir -p "$OUT"
python3 - "$WORK/$ZIP" "$OUT" <<'PY'
import shutil, sys, zipfile
zip_path, out = sys.argv[1], sys.argv[2]
wanted = ("xray", "geoip.dat", "geosite.dat", "LICENSE")
with zipfile.ZipFile(zip_path) as z:
    for name in z.namelist():
        base = name.rsplit("/", 1)[-1]
        if base in wanted and not name.endswith("/"):
            with z.open(name) as src, open(out + "/" + base, "wb") as dst:
                shutil.copyfileobj(src, dst)
PY

chmod 755 "$OUT/xray"
chmod 644 "$OUT/geoip.dat" "$OUT/geosite.dat" "$OUT/LICENSE"
printf '%s' "$VERSION" > "$OUT/xray-version"

echo "Done: staged xray $VERSION + geo assets."
