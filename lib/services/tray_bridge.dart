import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Bridges the native Linux tray mode radio items with the Dart app state.
class TrayBridge {
  TrayBridge._();

  static final TrayBridge instance = TrayBridge._();

  static const MethodChannel _channel = MethodChannel('dev.affection.affection_vpn/tray');

  Timer? _debounce;
  bool _initialized = false;

  /// Called when the user clicks a mode radio item in the tray.
  void Function(String mode)? onModeChanged;

  Future<void> init() async {
    if (!Platform.isLinux || _initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'modeChanged') {
      final mode = call.arguments['mode'] as String?;
      _debounce?.cancel();
      _debounce = Timer(Duration.zero, () {
        onModeChanged?.call(mode ?? 'tun');
      });
    }
  }

  /// Tell the native tray which mode is active (sets the radio checkmark).
  Future<void> setMode(String mode) async {
    if (!Platform.isLinux || !_initialized) return;
    try {
      await _channel.invokeMethod('setMode', {'mode': mode});
    } catch (_) {}
  }
}
