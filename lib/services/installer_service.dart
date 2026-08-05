import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class InstallerService {
  InstallerService._();
  static final InstallerService instance = InstallerService._();

  static const _channel =
      MethodChannel('dev.affection.affection_vpn/installer');

  bool get isAndroidSupported =>
      !kIsWeb && Platform.isAndroid;

  /// Whether the user already allowed this app to install unknown apps.
  Future<bool> canInstallUnknownApps() async {
    if (!isAndroidSupported) {
      return true;
    }
    final allowed = await _channel.invokeMethod<bool>('canInstallUnknownApps');
    return allowed ?? true;
  }

  /// Opens the per-app "Install unknown apps" settings page.
  Future<void> openUnknownSourcesSettings() async {
    if (!isAndroidSupported) {
      return;
    }
    await _channel.invokeMethod<void>('openUnknownSourcesSettings');
  }

  /// Installs an APK through the native PackageInstaller.
  ///
  /// Uses a signature-matched self-update session, which installs without the
  /// "unknown source" confirmation on most devices. Returns `false` when the
  /// platform does not support this path, and throws on install failure.
  Future<bool> installApk(String path) async {
    if (!isAndroidSupported) {
      return false;
    }
    final ok =
        await _channel.invokeMethod<bool>('installApk', {'path': path});
    return ok ?? false;
  }
}
