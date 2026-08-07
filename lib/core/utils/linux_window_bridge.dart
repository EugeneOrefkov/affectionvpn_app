import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class LinuxWindowBridge {
  const LinuxWindowBridge._();

  static const _channel = MethodChannel('dev.affection.affection_vpn/window');

  static bool get isAvailable => Platform.isLinux;

  static Future<void> drag() async {
    if (!isAvailable) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('dragWindow');
    } on MissingPluginException {
    } on PlatformException {
    }
  }

  static Future<void> minimize() async {
    if (!isAvailable) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('minimizeWindow');
    } on MissingPluginException {
    }
  }

  static Future<void> close() async {
    if (!isAvailable) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('closeWindow');
    } on MissingPluginException {
    }
  }
}
