import 'dart:io';

import 'package:flutter_vless/flutter_vless.dart';

import '../models/server_config.dart';

class VpnService {
  VpnService._();
  static final VpnService instance = VpnService._();

  late final FlutterVless _vless;

  void create({required void Function(VlessStatus status) onStatusChanged}) {
    _vless = FlutterVless(onStatusChanged: onStatusChanged);
  }

  Future<void> initialize() async {
    await _vless.initializeVless(
      notificationIconResourceType: 'mipmap',
      notificationIconResourceName: 'ic_launcher',
      providerBundleIdentifier: 'dev.affection.affection_vpn',
      groupIdentifier: 'group.dev.affection.affection_vpn',
    );
  }

  Future<bool> requestPermission() {
    return _vless.requestPermission();
  }

  Future<void> start(ServerConfig server, {bool proxyOnly = false}) {
    return _vless.startVless(
      remark: server.displayName,
      config: server.config,
      proxyOnly: proxyOnly,
      notificationDisconnectButtonName: 'ОТКЛЮЧИТЬ',
    );
  }

  Future<void> stop() => _vless.stopVless();

  Future<int> getServerDelay(ServerConfig server) {
    return _vless.getServerDelay(config: server.config);
  }

  Future<int> getConnectedServerDelay() {
    return _vless.getConnectedServerDelay();
  }

  Future<String> getCoreVersion() => _vless.getCoreVersion();

  static const _probeTimeout = Duration(seconds: 2);

  Future<int?> measureServerDelay(ServerConfig server) {
    if (server.address.isNotEmpty && server.port > 0) {
      return measureTcpDelay(server.address, server.port);
    }
    return getServerDelay(server).then(
      (delay) => delay > 0 ? delay : null,
      onError: (_) => null,
    );
  }

  Future<int?> measureTcpDelay(String address, int port) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        address,
        port,
        timeout: _probeTimeout,
      );
      await socket.close();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }
}
