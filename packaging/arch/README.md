# Affection VPN — Arch Linux

## Сборка из PKGBUILD

```bash
git clone https://github.com/EugeneOrefkov/affectionvpn_app.git
cd affectionvpn_app/packaging/arch
makepkg -si
```

## Зависимости

Пакет тянет `gtk3` и `libayatana-appindicator` (трей). Xray-core и базы geoip/geosite вшиты в тарбол, отдельная установка не нужна.

Опционально можно поставить свежие базы из системных репозиториев (`v2ray-geoip`, `v2ray-domain-list-community`) — приложение предпочитает их, когда они есть в `/usr/share/v2ray`.

## Запуск

После установки приложение появится в меню приложений как **Affection VPN**. Также можно запустить из терминала:

```bash
affection-vpn
```
