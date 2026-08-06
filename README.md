# Affection VPN

Native Xray (VLESS) VPN client for Android and Linux with subscription
support, real-time server switching, auto-select of the fastest server, and
traffic stats.

## Platforms

### Android

The Android app bundles the Xray core (`flutter_vless`) and installs a real
VPN tunnel. Build with:

```
flutter build apk --release
```

### Linux (Arch / Manjaro)

The Linux build is a native desktop client. It does not bundle Xray — the core
and geo databases come from the system packages:

```
yay -S xray            # AUR: /usr/bin/xray + /usr/share/v2ray assets
```

Then install the app from the PKGBUILD in `packaging/arch/`:

```
cd packaging/arch
makepkg -si
```

The app finds the core at `/usr/bin/xray` and the geo data under
`/usr/share/v2ray` automatically. When connected it drives the desktop's
system proxy (GNOME/KDE/XFCE) through a local Xray HTTP inbound and reports
per-server ping and traffic via the Xray stats API.

To override the core location, set `FLUTTER_VLESS_XRAY` to a path, or drop a
binary at `/usr/lib/affection-vpn/xray` with `geoip.dat`/`geosite.dat`
alongside.

Release tarballs (`affection-vpn-<version>-linux-x64.tar.gz`) are built by
GitHub Actions and attached to each GitHub release.
