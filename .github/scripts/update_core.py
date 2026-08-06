#!/usr/bin/env python3
"""Auto-bump the Xray core runtime version and the app version.

The core is a Maven artifact (dev.tfox.fluttervless:xray-android) published by
the flutter_vless plugin author. This script compares the version currently
pinned in android/gradle.properties with the latest published one, and when a
newer build exists bumps both the pin and the app version in pubspec.yaml.

Usage:
  update_core.py                 # real run: bump files when newer core exists
  update_core.py --dry-run       # only print what would change, exit 0
  update_core.py --metadata URL  # override the Maven metadata source
"""

import argparse
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET

GRADLE_PROPERTIES = "android/gradle.properties"
PUBSPEC = "pubspec.yaml"
CORE_PROPERTY = "flutterVlessXrayRuntimeVersion"
MAVEN_METADATA = (
    "https://repo1.maven.org/maven2/dev/tfox/fluttervless/"
    "xray-android/maven-metadata.xml"
)


def parse_version(value):
    parts = value.split(".")
    numbers = []
    for part in parts:
        m = re.match(r"^(\d+)", part)
        numbers.append(int(m.group(1)) if m else 0)
    return numbers


def fetch_latest_core(metadata_source):
    try:
        if metadata_source.startswith("http://") or metadata_source.startswith("https://"):
            with urllib.request.urlopen(metadata_source, timeout=30) as response:
                root = ET.fromstring(response.read())
        else:
            with open(metadata_source, encoding="utf-8") as f:
                root = ET.fromstring(f.read())
    except Exception as exc:
        print(f"update_core: cannot fetch metadata: {exc}")
        return None
    versioning = root.find("versioning")
    if versioning is None:
        print("update_core: no <versioning> in metadata")
        return None
    latest = versioning.find("latest")
    if latest is None or not latest.text:
        print("update_core: no <latest> in metadata")
        return None
    return latest.text.strip()


def read_core_pin():
    with open(GRADLE_PROPERTIES, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith(CORE_PROPERTY + "="):
                return line.split("=", 1)[1].strip()
    return None


def set_core_pin(version):
    with open(GRADLE_PROPERTIES, encoding="utf-8") as f:
        content = f.read()
    content = re.sub(
        re.compile(rf"^{re.escape(CORE_PROPERTY)}=.*$", re.MULTILINE),
        f"{CORE_PROPERTY}={version}",
        content,
    )
    with open(GRADLE_PROPERTIES, "w", encoding="utf-8") as f:
        f.write(content)


def read_app_version():
    with open(PUBSPEC, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^version:\s*(\d+)\.(\d+)\.(\d+)(\+\d+)?\s*$", line)
            if m:
                return m.group(1), m.group(2), m.group(3), m.group(4) or ""
    raise SystemExit("update_core: cannot parse version in pubspec.yaml")


def set_app_version(new_version):
    with open(PUBSPEC, encoding="utf-8") as f:
        content = f.read()
    content = re.sub(
        re.compile(r"^version:\s*\S+$", re.MULTILINE),
        f"version: {new_version}",
        content,
        count=1,
    )
    with open(PUBSPEC, "w", encoding="utf-8") as f:
        f.write(content)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--metadata", default=MAVEN_METADATA)
    args = parser.parse_args()

    current_core = read_core_pin()
    if current_core is None:
        raise SystemExit(
            f"update_core: {CORE_PROPERTY} not found in {GRADLE_PROPERTIES}"
        )
    latest_core = fetch_latest_core(args.metadata)
    if latest_core is None:
        print("update_core: skipping (metadata unavailable)")
        return

    major, minor, patch, build = read_app_version()
    current_app = f"{major}.{minor}.{patch}{build}"
    next_app = f"{major}.{minor}.{int(patch) + 1}{build or '+1'}"

    if parse_version(latest_core) <= parse_version(current_core):
        print(
            f"update_core: no update (pinned {current_core}, latest {latest_core})"
        )
        return

    print(f"update_core: {current_core} -> {latest_core}")
    print(f"update_core: app {current_app} -> {next_app}")
    if args.dry_run:
        return

    set_core_pin(latest_core)
    set_app_version(next_app)
    print(f"NEW_VERSION={next_app}")
    print(f"TAG_VERSION={next_app.split('+', 1)[0]}")


if __name__ == "__main__":
    sys.exit(main())
