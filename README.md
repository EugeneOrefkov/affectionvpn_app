# Affection VPN

[![CI](https://github.com/EugeneOrefkov/affectionvpn_app/actions/workflows/ci.yml/badge.svg)](https://github.com/EugeneOrefkov/affectionvpn_app/actions/workflows/ci.yml)

Native Xray (VLESS) VPN client for Android and Linux with subscription
support, real-time server switching, auto-select of the fastest server, and
traffic stats.

## Platforms

### Android

APKs are published on the update server: [update.affectiion.ru](https://update.affectiion.ru/latest.json)
lists the current release with download URLs and checksums (this is the same
manifest the in-app updater consumes). Direct link pattern:
`https://update.affectiion.ru/affection_vpn-<version>-<abi>.apk`.
The app bundles the Xray core and installs a real VPN tunnel.

### Linux

The Linux build is a native desktop client. It does not bundle Xray —
the core and geo databases must be installed separately.

#### Arch Linux

```bash
yay -S xray v2ray-geoip v2ray-domain-list-community
git clone https://github.com/EugeneOrefkov/affectionvpn_app.git
cd affectionvpn_app/packaging/arch
makepkg -si
```

Удаление:

```bash
sudo pacman -R affection-vpn
```

The app finds Xray at `/usr/bin/xray` and geo data under `/usr/share/v2ray`.
To override the core location, set `FLUTTER_VLESS_XRAY` to a path, or drop a
binary at `/usr/lib/affection-vpn/xray` with `geoip.dat`/`geosite.dat`
alongside.

#### Other distros (Debian / Ubuntu / Fedora)

Download the `.deb` package from the update server:

```bash
wget https://update.affectiion.ru/affection-vpn_<version>_amd64.deb
sudo dpkg -i affection-vpn_<version>_amd64.deb
```

Install Xray manually:

```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```

#### Portable tarball

Every release includes `affection-vpn-<version>-linux-x64.tar.gz` on the
update server. Extract anywhere and run `./affection_vpn`:

```bash
wget https://update.affectiion.ru/affection-vpn-1.3.5-linux-x64.tar.gz
tar -xzf affection-vpn-1.3.5-linux-x64.tar.gz
cd bundle
./affection_vpn
```

### Build from source

```bash
flutter pub get

# Android
flutter build apk --release

# Linux
flutter build linux --release
make -f linux/Makefile deb   # optional: build .deb package
```
