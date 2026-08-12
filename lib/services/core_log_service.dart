import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'linux_vless_platform.dart';

/// Single source of truth for the raw xray core output shown in
/// Settings → "Логи ядра".
///
///  - Linux: reflects [LinuxVlessPlatform.logs], which the platform backend
///    fills from the spawned core's stdout/stderr.
///  - Android: the core runs in a separate daemon process, so the vendored
///    plugin forwards every line to this process and streams it here over the
///    `flutter_vless/core_log` event channel (with the native backlog replayed
///    on subscribe, so nothing emitted before the UI subscribed is lost).
class CoreLogService extends ChangeNotifier {
  CoreLogService._();

  static final CoreLogService instance = CoreLogService._();

  static const _methodChannel = MethodChannel('flutter_vless');
  static const _eventChannel = EventChannel('flutter_vless/core_log');

  static const _maxLines = 2000;
  final List<String> _androidLogs = [];
  StreamSubscription<dynamic>? _subscription;
  bool _initialized = false;

  /// Platform-appropriate log lines (oldest first).
  List<String> get logs =>
      Platform.isLinux ? LinuxVlessPlatform.logs : List.unmodifiable(_androidLogs);

  bool get isEmpty => logs.isEmpty;

  /// Starts receiving core logs. On Android this subscribes to the event
  /// channel the vendored plugin exposes; on Linux the logs are already
  /// accumulated by [LinuxVlessPlatform]. Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    if (!Platform.isAndroid) {
      return;
    }
    _subscription = _eventChannel.receiveBroadcastStream().listen(
          (event) {
            if (event is String && event.isNotEmpty) {
              _append(event);
            }
          },
          onError: (Object error) {
            debugPrint('Core log stream error: $error');
          },
        );
  }

  void _append(String line) {
    _androidLogs.add(line);
    if (_androidLogs.length > _maxLines) {
      _androidLogs.removeRange(0, _androidLogs.length - _maxLines);
    }
    notifyListeners();
  }

  /// Clears the accumulated logs. On Android the native buffer is cleared too
  /// so a later replay cannot resurrect already-dismissed lines.
  Future<void> clear() async {
    _androidLogs.clear();
    notifyListeners();
    if (Platform.isAndroid) {
      try {
        await _methodChannel.invokeMethod<void>('clearCoreLogs');
      } catch (_) {
        // The channel is unavailable (e.g. not attached yet); the Dart-side
        // buffer is cleared regardless.
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
