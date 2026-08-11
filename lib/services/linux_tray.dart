import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/utils/messenger.dart';
import '../state/app_state.dart';

/// Bridges the native Linux status-notifier tray menu to the Dart [AppState].
///
/// The tray menu lives in native GTK code (`linux/runner/my_application.cc`).
/// It is rebuilt whenever Dart pushes a new snapshot via [push], and native
/// actions (toggle connection, pick a server, refresh subscription) come back
/// through the same method channel.
class LinuxTray {
  LinuxTray._();

  static final LinuxTray instance = LinuxTray._();

  static const _channel = MethodChannel('dev.affection.affection_vpn/tray');

  bool _initialized = false;
  String? _lastPayload;

  bool get initialized => _initialized;

  /// Installs the native -> Dart handler and pushes the current state so the
  /// tray shows the right status, server list and toggle label.
  void init(AppState state) {
    if (!Platform.isLinux || _initialized) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'toggleConnection':
          await state.toggleConnection();
        case 'selectServer':
          final index = (call.arguments as Map?)?['index'] as int? ?? 0;
          await state.selectServer(index);
        case 'refreshSubscription':
          await _refreshSubscription(state);
      }
    });
    push(state);
  }

  /// Sends a snapshot of the current [state] to the native tray, skipping the
  /// update when nothing that the tray shows actually changed.
  void push(AppState state) {
    if (!_initialized) {
      return;
    }
    final payload = _buildPayload(state);
    final serialized = jsonEncode(payload);
    if (serialized == _lastPayload) {
      return;
    }
    _lastPayload = serialized;
    unawaited(_channel.invokeMethod<void>('updateMenu', payload));
  }

  Future<void> _refreshSubscription(AppState state) async {
    final messenger = scaffoldMessengerKey.currentState;
    try {
      await state.refreshSubscription();
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Подписка обновлена'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Ошибка обновления: $e'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Map<String, dynamic> _buildPayload(AppState state) {
    final servers = state.servers.map((s) => s.displayName).toList();
    return {
      'connected': state.connectionStatus == ConnectionStatus.connected,
      'connecting': state.connectionStatus == ConnectionStatus.connecting,
      'disconnecting': state.connectionStatus == ConnectionStatus.disconnecting,
      'hasSubscription': state.hasSubscription,
      'currentServer': state.selectedServer?.displayName,
      'selected': state.selectedIndex,
      'servers': servers,
    };
  }
}
