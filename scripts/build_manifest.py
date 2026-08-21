#!/usr/bin/env python3
"""Builds the update manifest (latest.json) from release artifacts.

Scans a directory of downloaded release assets, computes sizes and sha256
checksums, points every URL at the public update server and prints the
manifest JSON to stdout.

Usage:
  build_manifest.py <dist-dir> <base-url> <version> <tag> <published-at> <changelog-file>
"""
import hashlib
import json
import os
import re
import sys

dist, base, version, tag, published_at, changelog_file = sys.argv[1:7]
base = base.rstrip('/')


def entry(name, field):
    path = os.path.join(dist, name)
    return {
        field: f'{base}/{name}',
        'size': os.path.getsize(path),
        'sha256': hashlib.sha256(open(path, 'rb').read()).hexdigest(),
    }


assets = {}
apks = []
for name in sorted(os.listdir(dist)):
    if re.fullmatch(r'affection_vpn-[\d.]+-(.+)\.apk', name):
        abi = re.fullmatch(r'affection_vpn-[\d.]+-(.+)\.apk', name).group(1)
        apks.append((abi, name))
    elif re.fullmatch(r'affection-vpn-[\d.]+-linux-x64\.tar\.gz', name):
        assets['linux-x64'] = entry(name, 'tar_url')
    elif re.fullmatch(r'affection-vpn_[\d.]+_amd64\.deb', name):
        assets['linux-deb'] = entry(name, 'deb_url')

# Per-ABI APKs first, universal last as the fallback entry.
for abi, name in sorted(apks, key=lambda x: x[0] == 'universal'):
    assets[abi] = entry(name, 'apk_url')

if not assets:
    sys.exit('no known artifacts found in ' + dist)

with open(changelog_file, encoding='utf-8') as f:
    changelog = f.read()

print(json.dumps({
    'version': version,
    'tag': tag,
    'published_at': published_at,
    'changelog': changelog,
    'assets': assets,
}, ensure_ascii=False))
