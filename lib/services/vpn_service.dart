import 'dart:convert';
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

  Future<void> start(
    ServerConfig server, {
    bool proxyOnly = false,
    String? config,
  }) {
    return _vless.startVless(
      remark: server.displayName,
      config: config ?? server.config,
      proxyOnly: proxyOnly,
      notificationDisconnectButtonName: 'ОТКЛЮЧИТЬ',
    );
  }

  Future<void> stop() => _vless.stopVless();

  Future<int> getServerDelay(ServerConfig server) {
    return _vless.getServerDelay(config: server.runtimeConfig, url: probeUrl);
  }

  Future<int> getConnectedServerDelay() {
    return _vless.getConnectedServerDelay(url: probeUrl);
  }

  Future<String> getCoreVersion() => _vless.getCoreVersion();

  /// Lightweight endpoint reachable in most regions; returns 204.
  /// HTTPS is required: the probe runs through the native `HttpURLConnection`
  /// and Android blocks cleartext to non-loopback hosts by default.
  static const probeUrl = 'https://cp.cloudflare.com/generate_204';

  /// TCP connect is a fast latency probe (network RTT, no tunnel overhead).
  /// Servers that do not answer within this window are treated as unreachable.
  static const _tcpProbeTimeout = Duration(seconds: 1);
  static const proxyPort = 10810;

  Future<int?> measureServerDelay(
    ServerConfig server, {
    required String method,
  }) {
    if (method == 'get') {
      return getServerDelay(server).then(
        (delay) => delay > 0 ? delay : null,
        onError: (_) => null,
      );
    }
    if (server.address.isNotEmpty && server.port > 0) {
      return measureTcpDelay(server.address, server.port);
    }
    return getServerDelay(server).then(
      (delay) => delay > 0 ? delay : null,
      onError: (_) => null,
    );
  }

  String buildAuthProxyConfig(
    String config,
    String login,
    String password,
  ) {
    final map = jsonDecode(config) as Map<String, dynamic>;
    final inbounds = <Map<String, dynamic>>[];
    final usedPorts = <int>{};
    for (final item in (map['inbounds'] as List? ?? const [])) {
      if (item is Map) {
        inbounds.add(Map<String, dynamic>.from(item));
        final port = item['port'];
        if (port is int) {
          usedPorts.add(port);
        }
      }
    }
    var port = proxyPort;
    while (usedPorts.contains(port)) {
      port++;
    }
    inbounds.add({
      'tag': 'socks-auth',
      'port': port,
      'listen': '0.0.0.0',
      'protocol': 'socks',
      'settings': {
        'auth': 'password',
        'udp': true,
        'accounts': [
          {'user': login, 'pass': password},
        ],
      },
      'sniffing': {
        'enabled': true,
        'destOverride': ['http', 'tls'],
      },
    });
    map['inbounds'] = inbounds;
    return jsonEncode(map);
  }

  Future<int?> measureTcpDelay(String address, int port) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        address,
        port,
        timeout: _tcpProbeTimeout,
      );
      await socket.close();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }
}
