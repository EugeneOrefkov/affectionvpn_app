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
  /// Because all probes run concurrently, the whole sweep finishes within one
  /// probe timeout.
  static const _tcpProbeTimeout = Duration(milliseconds: 900);
  static const proxyPort = 10810;

  /// Port of the app's internal loopback SOCKS inbound, injected into every
  /// config (except proxy-only mode, which reuses [proxyPort]) so the app can
  /// reach the internet through the tunnel for the IP/speed widgets.
  static const internalSocksPort = 10900;

  /// The actual port picked for the internal socks inbound by the last
  /// [buildInternalSocksConfig] call.
  int? lastInternalSocksPort;

  /// Injects a no-auth SOCKS inbound on 127.0.0.1 used only by the app itself.
  String buildInternalSocksConfig(String config) {
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
    var port = internalSocksPort;
    while (usedPorts.contains(port)) {
      port++;
    }
    lastInternalSocksPort = port;
    inbounds.add({
      'tag': 'socks-app',
      'port': port,
      'listen': '127.0.0.1',
      'protocol': 'socks',
      'settings': {'auth': 'noauth', 'udp': true},
    });
    map['inbounds'] = inbounds;
    return jsonEncode(map);
  }

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
    // startConnect returns a cancellable ConnectionTask, so a probe that hits
    // the timeout is torn down immediately and does not leave a half-open
    // socket behind. Combined with measuring every server concurrently this
    // bounds the whole sweep by a single [_tcpProbeTimeout].
    final task = await Socket.startConnect(address, port);
    try {
      final socket = await task.socket.timeout(_tcpProbeTimeout);
      await socket.close();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      task.cancel();
      return null;
    }
  }
}
