import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Bridge to the Linux GTK window. On non-Linux platforms the calls are
/// silently ignored — the OS-drawn title bar handles drag and close there.
///
/// The custom Flutter title bar we draw inside the app (instead of using the
/// GTK client-side decorations) fires [drag] on pointer move and [close] on
/// the close button, both of which route into native GTK via this channel.
class LinuxWindowBridge {
  const LinuxWindowBridge._();

  static const _channel = MethodChannel('dev.affection.affection_vpn/window');

  /// Returns false silently on non-Linux platforms.
  static bool get isAvailable => Platform.isLinux;

  static Future<void> drag() async {
    if (!isAvailable) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('dragWindow');
    } on MissingPluginException {
      // Channel not wired up (e.g. running in unit tests) — ignore.
    } on PlatformException {
      // Drag refused by the window manager — ignore.
    }
  }

  static Future<void> close() async {
    if (!isAvailable) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('closeWindow');
    } on MissingPluginException {
      // ignore
    }
  }
}
