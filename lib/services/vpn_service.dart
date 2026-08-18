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

  /// Port of the app's internal loopback HTTP (CONNECT) inbound, injected
  /// next to [internalSocksPort]. Unlike SOCKS, it can be used by `dart:io`
  /// via [HttpClient.findProxy], which is how the in-app update reaches GitHub
  /// through the tunnel even when direct access is blocked.
  static const internalHttpPort = 10901;

  /// Port of the app's internal loopback authenticated HTTP (CONNECT) inbound
  /// used in proxy-only mode (the counterpart of [proxyPort]'s SOCKS inbound).
  static const authHttpPort = 10811;

  /// The actual port picked for the internal socks inbound by the last
  /// [buildInternalSocksConfig] call.
  int? lastInternalSocksPort;

  /// The actual port picked for the internal http inbound by the last
  /// [buildInternalSocksConfig] call.
  int? lastInternalHttpPort;

  /// The actual port picked for the authenticated http inbound by the last
  /// [buildAuthProxyConfig] call.
  int? lastAuthHttpPort;

  /// Injects no-auth SOCKS5 and HTTP (CONNECT) inbounds on 127.0.0.1 used only
  /// by the app itself.
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
    var socksPort = internalSocksPort;
    while (usedPorts.contains(socksPort)) {
      socksPort++;
    }
    usedPorts.add(socksPort);
    lastInternalSocksPort = socksPort;
    inbounds.add({
      'tag': 'socks-app',
      'port': socksPort,
      'listen': '127.0.0.1',
      'protocol': 'socks',
      'settings': {'auth': 'noauth', 'udp': true},
    });

    var httpPort = internalHttpPort;
    while (usedPorts.contains(httpPort)) {
      httpPort++;
    }
    usedPorts.add(httpPort);
    lastInternalHttpPort = httpPort;
    inbounds.add({
      'tag': 'http-app',
      'port': httpPort,
      'listen': '127.0.0.1',
      'protocol': 'http',
    });

    map['inbounds'] = inbounds;
    return jsonEncode(_ensureAccessLog(map));
  }

  /// Points `log.access` at the core's access log so [RequestLogService] can
  /// tail tunnel connections. On Android the vendored plugin rewrites the path
  /// to `<files>/access.log`; on Linux [LinuxVlessPlatform.prepareRuntime]
  /// overrides it with the absolute app-support path. `loglevel` is forced to
  /// `info`, since `none` would silently disable the access log.
  Map<String, dynamic> _ensureAccessLog(Map<String, dynamic> map) {
    final log = map['log'];
    if (log is Map) {
      log['access'] = 'access.log';
      log['loglevel'] = 'info';
    } else {
      map['log'] = {'access': 'access.log', 'loglevel': 'info'};
    }
    return map;
  }

  Future<int?> measureServerDelay(
    ServerConfig server, {
    required String method,
  }) {
    if (method == 'get' || server.address.isEmpty || server.port <= 0) {
      return getServerDelay(server)
          .timeout(getProbeTimeout, onTimeout: () => -1)
          .then(
            (delay) => delay > 0 ? delay : null,
            onError: (_) => null,
          );
    }
    return measureTcpDelay(server.address, server.port);
  }

  /// Upper bound for a native GET probe (core start + up to 4 HEAD retries).
  /// Guards the delay sweep against a hung native call, which would otherwise
  /// leave [_isMeasuringDelay] stuck toggled on forever.
  static const getProbeTimeout = Duration(seconds: 20);

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
    var socksPort = proxyPort;
    while (usedPorts.contains(socksPort)) {
      socksPort++;
    }
    usedPorts.add(socksPort);
    inbounds.add({
      'tag': 'socks-auth',
      'port': socksPort,
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

    var httpPort = authHttpPort;
    while (usedPorts.contains(httpPort)) {
      httpPort++;
    }
    usedPorts.add(httpPort);
    lastAuthHttpPort = httpPort;
    inbounds.add({
      'tag': 'http-auth',
      'port': httpPort,
      'listen': '127.0.0.1',
      'protocol': 'http',
      'settings': {
        'accounts': [
          {'user': login, 'pass': password},
        ],
      },
    });

    map['inbounds'] = inbounds;
    return jsonEncode(_ensureAccessLog(map));
  }

  /// Injects no-auth SOCKS5 and HTTP (CONNECT) inbounds on 0.0.0.0 / 127.0.0.1
  /// for proxy-only mode without login/password authentication.
  String buildNoAuthProxyConfig(String config) {
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
    var socksPort = proxyPort;
    while (usedPorts.contains(socksPort)) {
      socksPort++;
    }
    usedPorts.add(socksPort);
    inbounds.add({
      'tag': 'socks-auth',
      'port': socksPort,
      'listen': '0.0.0.0',
      'protocol': 'socks',
      'settings': {'auth': 'noauth', 'udp': true},
      'sniffing': {
        'enabled': true,
        'destOverride': ['http', 'tls'],
      },
    });

    var httpPort = authHttpPort;
    while (usedPorts.contains(httpPort)) {
      httpPort++;
    }
    usedPorts.add(httpPort);
    lastAuthHttpPort = httpPort;
    inbounds.add({
      'tag': 'http-auth',
      'port': httpPort,
      'listen': '127.0.0.1',
      'protocol': 'http',
    });

    map['inbounds'] = inbounds;
    return jsonEncode(_ensureAccessLog(map));
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
