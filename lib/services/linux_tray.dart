import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';

import '../state/app_state.dart';

class LinuxTray with TrayListener {
  LinuxTray._();

  static final LinuxTray instance = LinuxTray._();

  bool _initialized = false;

  Future<void> init(AppState state) async {
    if (!Platform.isLinux || _initialized) return;
    _initialized = true;

    trayManager.addListener(this);

    await trayManager.setIcon(
      Platform.isLinux ? 'assets/app_icon.png' : '',
    );
    await trayManager.setToolTip('Affection VPN');

    await _updateMenu(state);
  }

  Future<void> _updateMenu(AppState state) async {
    final isProxy = state.proxyOnly;

    final menu = Menu(
      items: [
        MenuItem(label: 'Открыть', onClick: (_) {
          windowManager.show();
          windowManager.focus();
        }),
        MenuItem.separator(),
        MenuItem.checkbox(
          label: 'Системное прокси',
          checked: isProxy,
          onClick: (_) {
            state.setProxyOnly(true);
            _updateMenu(state);
          },
        ),
        MenuItem.checkbox(
          label: 'TUN',
          checked: !isProxy,
          onClick: (_) {
            state.setProxyOnly(false);
            _updateMenu(state);
          },
        ),
        MenuItem.separator(),
        MenuItem(label: 'Выход', onClick: (_) {
          _quit(state);
        }),
      ],
    );

    await trayManager.setContextMenu(menu);
  }

  Future<void> _quit(AppState state) async {
    await state.shutdown();
    exit(0);
  }
}
