import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_vless_platform_interface/flutter_vless_platform_interface.dart';
import 'package:path_provider/path_provider.dart';

/// Pure-Dart Linux backend for [VlessPlatform].
///
/// flutter_vless has no native Linux plugin, so this implementation drives the
/// real `xray` binary directly: it writes the runtime config, spawns the core
/// as a child process, reports status/traffic through the Xray stats API, and
/// routes the desktop's system proxy through the tunnel.
///
/// The app's own IP/speed widgets already speak SOCKS5 by hand, so the only
/// inbounds this backend adds are a plain HTTP proxy (for the system proxy and
/// delay probes) and an Xray stats API door.
class LinuxVlessPlatform extends VlessPlatform {
  LinuxVlessPlatform();

  /// Circular buffer of the last 500 xray process log lines.
  static final List<String> logs = [];
  static const int _maxLogLines = 500;

  /// Plain loopback HTTP inbound injected into every runtime config. Desktop
  /// apps use it (HTTP proxies support CONNECT), and the delay probes reuse it.
  static const defaultHttpPort = 10809;

  /// Xray StatsService API door used to report traffic.
  static const defaultApiPort = 10807;

  static const _startTimeout = Duration(seconds: 8);
  static const _connectTimeout = Duration(seconds: 2);

  Process? _process;
  String? _xrayPath;
  String? _assetDir;
  String? _configPath;
  bool _proxyApplied = false;

  int _httpPort = defaultHttpPort;
  int _apiPort = defaultApiPort;
  int _socksPort = 0;

  Timer? _statsTimer;
  void Function(VlessStatus status)? _onStatus;
  DateTime? _connectedAt;
  int _lastUpload = 0;
  int _lastDownload = 0;
  int _lastUploadSpeed = 0;
  int _lastDownloadSpeed = 0;

  static int _probeInFlight = 0;
  static const _maxProbeInFlight = 4;

  @override
  Future<void> initializeVless({
    required void Function(VlessStatus status) onStatusChanged,
    required String notificationIconResourceType,
    required String notificationIconResourceName,
    required String providerBundleIdentifier,
    required String groupIdentifier,
  }) async {
    _onStatus = onStatusChanged;
    _xrayPath = _findXray();
    _assetDir = _findAssetDir(_xrayPath);
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> startVless({
    required String remark,
    required String config,
    required String notificationDisconnectButtonName,
    List<String>? blockedApps,
    List<String>? bypassSubnets,
    bool proxyOnly = false,
  }) async {
    final xray = _xrayPath;
    if (xray == null) {
      throw Exception(
        'Бинарь xray не найден. Установите пакет xray '
        '(pacman -S xray) или положите xray в /usr/lib/affection-vpn/',
      );
    }
    await stopVless();

    final dir = await _runtimeDir();
    final prepared = prepareRuntime(
      config,
      proxyOnly: proxyOnly,
      accessLogPath: '${dir.path}/access.log',
    );
    _httpPort = prepared.httpPort;
    _apiPort = prepared.apiPort;
    _socksPort = prepared.socksPort;

    _configPath = '${dir.path}/config.json';
    File(_configPath!).writeAsStringSync(prepared.config);

    _emit(VlessStatus(state: 'CONNECTING'));
    _process = await Process.start(
      xray,
      ['run', '-config', _configPath!],
      environment: {'XRAY_LOCATION_ASSET': _assetDir ?? ''},
    );
    _process!.stdout.transform(utf8.decoder).listen(_log);
    _process!.stderr.transform(utf8.decoder).listen(_log);
    unawaited(_process!.exitCode.then((_) => _onProcessExit()));

    final ready = await _waitForPort(_socksPort, _startTimeout);
    if (!ready) {
      await stopVless();
      throw Exception('xray не поднял прокси за ${_startTimeout.inSeconds} с');
    }

    _connectedAt = DateTime.now();
    _lastUpload = 0;
    _lastDownload = 0;
    _emit(VlessStatus(state: 'CONNECTED'));

    if (!proxyOnly) {
      _applySystemProxy(httpPort: _httpPort, socksPort: _socksPort);
    }

    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollStats(),
    );
  }

  @override
  Future<void> stopVless() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    final process = _process;
    _process = null;
    if (process != null) {
      try {
        process.kill(ProcessSignal.sigterm);
        await process.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    }
    if (_proxyApplied) {
      _resetSystemProxy();
      _proxyApplied = false;
    }
    _connectedAt = null;
    if (process != null) {
      _emit(VlessStatus(state: 'DISCONNECTED'));
    }
  }

  @override
  Future<int> getServerDelay({
    required String config,
    String url = 'https://cp.cloudflare.com/generate_204',
  }) async {
    final xray = _xrayPath;
    if (xray == null) {
      return -1;
    }
    await _probeLock();
    Process? process;
    try {
      final prepared = prepareRuntime(config, proxyOnly: false);
      final dir = await _runtimeDir();
      final configPath =
          '${dir.path}/delay_${prepared.httpPort}_${DateTime.now().microsecondsSinceEpoch}.json';
      File(configPath).writeAsStringSync(prepared.config);

      process = await Process.start(
        xray,
        ['run', '-config', configPath],
        environment: {'XRAY_LOCATION_ASSET': _assetDir ?? ''},
      );
      process.stdout.transform(utf8.decoder).listen((_) {});
      process.stderr.transform(utf8.decoder).listen((_) {});

      await _waitForPort(prepared.httpPort, const Duration(seconds: 5));

      // A leastLoad balancer only routes after its observatory has recorded the
      // first probe; retry a few times so the warm-up becomes a valid ping.
      var delay = -1;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
        delay = await _probeHttp(prepared.httpPort, url);
        if (delay >= 0) {
          break;
        }
      }
      return delay;
    } catch (_) {
      return -1;
    } finally {
      process?.kill(ProcessSignal.sigkill);
      _probeUnlock();
    }
  }

  @override
  Future<int> getConnectedServerDelay(String url) async {
    if (_process == null || _httpPort == 0) {
      return -1;
    }
    return _probeHttp(_httpPort, url);
  }

  @override
  Future<String> getCoreVersion() async {
    final xray = _xrayPath;
    if (xray == null) {
      return 'xray not found';
    }
    try {
      final result = await Process.run(xray, ['version']);
      final firstLine = (result.stdout as String).trim().split('\n').first;
      return firstLine.isEmpty ? 'unknown' : firstLine;
    } catch (_) {
      return 'unknown';
    }
  }

  // ---- config preparation -------------------------------------------------

  /// Injects the app's SOCKS inbound, a plain HTTP inbound, and the Xray stats
  /// API door into [config]. Exposed so the injection logic is unit-testable
  /// without spawning a real core.
  ///
  /// When [accessLogPath] is given, `log.access` is pointed there so the
  /// request log can tail the tunnel's connections; `loglevel` is forced to
  /// `info`, since `none` would silently disable the access log.
  @visibleForTesting
  ({String config, int httpPort, int apiPort, int socksPort}) prepareRuntime(
    String config, {
    required bool proxyOnly,
    String? accessLogPath,
  }) {
    final map = jsonDecode(config) as Map<String, dynamic>;
    final inbounds =
        (map['inbounds'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    final usedPorts = inbounds
        .map((e) => e['port'])
        .whereType<int>()
        .toSet();

    // The app injects the SOCKS inbound it talks to. Find its port.
    var socksPort = 0;
    for (final inbound in inbounds) {
      final tag = inbound['tag'];
      if (tag == 'socks-app' || tag == 'socks-auth') {
        socksPort = inbound['port'] as int? ?? 0;
        break;
      }
    }
    if (socksPort == 0) {
      // No app SOCKS inbound found, add one on the app's well-known port.
      socksPort = _nextFree(10900, usedPorts);
      usedPorts.add(socksPort);
      inbounds.add({
        'tag': 'socks-app',
        'port': socksPort,
        'listen': '127.0.0.1',
        'protocol': 'socks',
        'settings': {'auth': 'noauth', 'udp': true},
      });
    }

    // Plain loopback HTTP inbound (CONNECT-capable) for the system proxy and
    // the delay probes.
    final httpPort = _nextFree(defaultHttpPort, usedPorts);
    usedPorts.add(httpPort);
    inbounds.add({
      'tag': 'http',
      'port': httpPort,
      'listen': '127.0.0.1',
      'protocol': 'http',
    });

    // Xray stats API door.
    var apiPort = defaultApiPort;
    if (inbounds.any((e) => (e['tag'] as String?) == 'api')) {
      apiPort =
          inbounds.firstWhere((e) => (e['tag'] as String?) == 'api')['port']
              as int? ??
              apiPort;
    } else {
      apiPort = _nextFree(apiPort, usedPorts);
      usedPorts.add(apiPort);
      inbounds.add({
        'tag': 'api',
        'port': apiPort,
        'listen': '127.0.0.1',
        'protocol': 'dokodemo-door',
        'settings': {'address': '127.0.0.1'},
      });
      final routing = map['routing'];
      if (routing is Map) {
        final rules = ((routing['rules'] as List?) ?? const []).toList();
        rules.add({
          'type': 'field',
          'inboundTag': ['api'],
          'outboundTag': 'api',
        });
        routing['rules'] = rules;
      }
      // dokodemo-door is inbound-only; the api inbound is answered by the
      // StatsService itself via the routing rule above, so no outbound is added.
      map['api'] = {'tag': 'api', 'services': ['StatsService']};
    }

    final policy = map['policy'];
    if (policy is Map) {
      final system = policy['system'];
      if (system is Map) {
        system['statsInboundUplink'] = true;
        system['statsInboundDownlink'] = true;
        system['statsOutboundUplink'] = true;
        system['statsOutboundDownlink'] = true;
      }
    }

    if (accessLogPath != null && accessLogPath.isNotEmpty) {
      final log = map['log'];
      if (log is Map) {
        log['access'] = accessLogPath;
        log['loglevel'] = 'info';
      } else {
        map['log'] = {'access': accessLogPath, 'loglevel': 'info'};
      }
    }

    map['inbounds'] = inbounds;
    return (
      config: jsonEncode(map),
      httpPort: httpPort,
      apiPort: apiPort,
      socksPort: socksPort,
    );
  }

  int _nextFree(int preferred, Set<int> used) {
    var port = preferred;
    while (used.contains(port)) {
      port++;
    }
    return port;
  }

  // ---- xray discovery -----------------------------------------------------

  String? _findXray() {
    final env = Platform.environment['FLUTTER_VLESS_XRAY'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) {
      return env;
    }
    const candidates = [
      '/usr/lib/affection-vpn/xray',
      '/opt/affection-vpn/xray',
      '/usr/bin/xray',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    try {
      final result = Process.runSync('which', ['xray']);
      final path = (result.stdout as String).trim();
      if (result.exitCode == 0 && path.isNotEmpty && File(path).existsSync()) {
        return path;
      }
    } catch (_) {}
    return null;
  }

  String? _findAssetDir(String? xrayPath) {
    if (xrayPath == null) {
      return null;
    }
    final candidates = [
      '/usr/lib/affection-vpn',
      // Arch: xray package → /usr/share/xray/, AUR → /usr/share/v2ray/
      '/usr/share/xray',
      '/usr/share/v2ray',
      File(xrayPath).parent.path,
      Platform.environment['XRAY_LOCATION_ASSET'],
    ];
    for (final dir in candidates) {
      if (dir == null || dir.isEmpty) {
        continue;
      }
      if (File('$dir/geoip.dat').existsSync() ||
          File('$dir/geosite.dat').existsSync()) {
        return dir;
      }
    }
    return null;
  }

  Future<Directory> _runtimeDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/xray');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  // ---- probing ------------------------------------------------------------

  Future<void> _probeLock() async {
    while (_probeInFlight >= _maxProbeInFlight) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _probeInFlight++;
  }

  void _probeUnlock() {
    if (_probeInFlight > 0) {
      _probeInFlight--;
    }
  }

  Future<bool> _waitForPort(int port, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 300),
        );
        await socket.close();
        return true;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 75));
      }
    }
    return false;
  }

  Future<int> _probeHttp(int httpPort, String url) async {
    final uri = Uri.parse(url);
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    client.findProxy = (_) => 'PROXY 127.0.0.1:$httpPort;DIRECT';
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client.headUrl(uri).timeout(_connectTimeout);
      final response = await request.close().timeout(_connectTimeout);
      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;
      response.drain<void>();
      return elapsed;
    } catch (_) {
      return -1;
    } finally {
      client.close(force: true);
    }
  }

  // ---- stats / status -----------------------------------------------------

  void _emit(VlessStatus status) {
    _onStatus?.call(status);
  }

  void _log(String line) {
    logs.add(line);
    if (logs.length > _maxLogLines) {
      logs.removeRange(0, logs.length - _maxLogLines);
    }
  }

  Future<void> _pollStats() async {
    if (_process == null || _apiPort == 0) {
      return;
    }
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final request =
          await client
              .getUrl(Uri.parse('http://127.0.0.1:$_apiPort/stats/outbound?reset=true'))
              .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 2));
      final body = await response.transform(utf8.decoder).join();
      client.close(force: true);

      final json = jsonDecode(body) as Map<String, dynamic>;
      var upload = 0;
      var download = 0;
      for (final stat in (json['stat'] as List? ?? const [])) {
        if (stat is Map) {
          final name = stat['name']?.toString() ?? '';
          final value = (stat['value'] as num?)?.toInt() ?? 0;
          if (name.contains('>>>traffic>>>uplink')) {
            upload += value;
          } else if (name.contains('>>>traffic>>>downlink')) {
            download += value;
          }
        }
      }
      final now = DateTime.now();
      final duration =
          _connectedAt == null ? 0 : now.difference(_connectedAt!).inSeconds;
      _lastUploadSpeed = upload - _lastUpload;
      _lastDownloadSpeed = download - _lastDownload;
      _lastUpload = upload;
      _lastDownload = download;
      _emit(
        VlessStatus(
          duration: duration,
          upload: upload,
          download: download,
          uploadSpeed: _lastUploadSpeed < 0 ? 0 : _lastUploadSpeed,
          downloadSpeed: _lastDownloadSpeed < 0 ? 0 : _lastDownloadSpeed,
          state: 'CONNECTED',
        ),
      );
    } catch (_) {}
  }

  void _onProcessExit() {
    _statsTimer?.cancel();
    _statsTimer = null;
    if (_proxyApplied) {
      _resetSystemProxy();
      _proxyApplied = false;
    }
    if (_process == null) {
      _emit(VlessStatus(state: 'DISCONNECTED'));
    }
  }

  // ---- system proxy (best effort, per desktop environment) ----------------

  Future<void> _applySystemProxy({
    required int httpPort,
    required int socksPort,
  }) async {
    final setter = _proxySetter(httpPort, socksPort);
    for (final cmd in setter) {
      try {
        await Process.run(cmd[0], cmd.sublist(1));
      } catch (_) {}
    }
    _proxyApplied = true;
  }

  Future<void> _resetSystemProxy() async {
    for (final cmd in _proxyReset()) {
      try {
        await Process.run(cmd[0], cmd.sublist(1));
      } catch (_) {}
    }
  }

  List<List<String>> _proxySetter(int httpPort, int socksPort) {
    final commands = <List<String>>[];
    if (_have('gsettings')) {
      commands.addAll([
        ['gsettings', 'set', 'org.gnome.system.proxy', 'mode', 'manual'],
        ['gsettings', 'set', 'org.gnome.system.proxy.http', 'host', '127.0.0.1'],
        ['gsettings', 'set', 'org.gnome.system.proxy.http', 'port', '$httpPort'],
        ['gsettings', 'set', 'org.gnome.system.proxy.https', 'host', '127.0.0.1'],
        ['gsettings', 'set', 'org.gnome.system.proxy.https', 'port', '$httpPort'],
        ['gsettings', 'set', 'org.gnome.system.proxy.socks', 'host', '127.0.0.1'],
        ['gsettings', 'set', 'org.gnome.system.proxy.socks', 'port', '$socksPort'],
      ]);
    }
    if (_have('kwriteconfig5')) {
      commands.addAll([
        ['kwriteconfig5', '--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'ProxyType', '1'],
        ['kwriteconfig5', '--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'httpProxy', '127.0.0.1 $httpPort'],
        ['kwriteconfig5', '--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'httpsProxy', '127.0.0.1 $httpPort'],
        ['kwriteconfig5', '--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'socksProxy', '127.0.0.1 $socksPort'],
      ]);
    }
    if (_have('xfconf-query')) {
      commands.addAll([
        ['xfconf-query', '-c', 'proxies', '-p', '/mode', '-s', 'manual'],
        ['xfconf-query', '-c', 'proxies', '-p', '/httpProxy', '-s', 'http://127.0.0.1:$httpPort'],
        ['xfconf-query', '-c', 'proxies', '-p', '/httpsProxy', '-s', 'http://127.0.0.1:$httpPort'],
        ['xfconf-query', '-c', 'proxies', '-p', '/socksProxy', '-s', 'socks://127.0.0.1:$socksPort'],
      ]);
    }
    return commands;
  }

  List<List<String>> _proxyReset() {
    final commands = <List<String>>[];
    if (_have('gsettings')) {
      commands.add(['gsettings', 'set', 'org.gnome.system.proxy', 'mode', 'none']);
    }
    if (_have('kwriteconfig5')) {
      commands.add([
        'kwriteconfig5',
        '--file',
        'kioslaverc',
        '--group',
        'Proxy Settings',
        '--key',
        'ProxyType',
        '0',
      ]);
    }
    if (_have('xfconf-query')) {
      commands.add(['xfconf-query', '-c', 'proxies', '-p', '/mode', '-s', 'none']);
    }
    return commands;
  }

  bool _have(String tool) {
    try {
      final result = Process.runSync('which', [tool]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
