# Affection VPN — Arch Linux

## Сборка из PKGBUILD

```bash
git clone https://github.com/EugeneOrefkov/affectionvpn_app.git
cd affectionvpn_app/packaging/arch
makepkg -si
```

## Зависимости

Xray-core устанавливается автоматически как зависимость пакета (`xray`, `v2ray-geoip`, `v2ray-domain-list-community` из AUR/extra).

## Запуск

После установки приложение появится в меню приложений как **Affection VPN**. Также можно запустить из терминала:

```bash
affection-vpn
```
