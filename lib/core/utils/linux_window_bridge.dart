import 'dart:io';

import 'package:window_manager/window_manager.dart';

class LinuxWindowBridge {
  const LinuxWindowBridge._();

  static bool get isAvailable => Platform.isLinux;

  static Future<void> startDrag() async {
    if (!isAvailable) {
      return;
    }
    await windowManager.startDragging();
  }

  static Future<void> minimize() async {
    if (!isAvailable) {
      return;
    }
    await windowManager.minimize();
  }

  static Future<void> close() async {
    if (!isAvailable) {
      return;
    }
    await windowManager.close();
  }
}
