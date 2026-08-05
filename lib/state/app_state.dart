import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/server_config.dart';
import '../models/subscription_info.dart';
import '../models/update_info.dart';
import '../services/storage_service.dart';
import '../services/subscription_service.dart';
import '../services/tunnel_http.dart';
import '../services/update_service.dart';
import '../services/vpn_service.dart';

enum ConnectionStatus { disconnected, connecting, connected, disconnecting }

class AppState extends ChangeNotifier {
  AppState() {
    VpnService.instance.create(
      onStatusChanged: _onStatusChanged,
    );
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        return;
      }
      unawaited(_measureDelays(method: 'tcp'));
      unawaited(refreshProxyHost());
    });
  }

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  final _storage = StorageService.instance;
  final _subscriptionService = SubscriptionService();

  String? _subscriptionUrl;
  List<ServerConfig> _servers = [];
  SubscriptionInfo? _subscriptionInfo;
  int _selectedIndex = 0;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  VlessStatus _status = VlessStatus();
  bool _isLoadingSubscription = false;
  bool _isMeasuringDelay = false;

  int? _measuringIndex;
  bool _initialized = false;

  static const _autoSelectInterval = Duration(seconds: 60);

  /// If the connected server's HTTP GET ping stays below this, assume it is
  /// healthy and skip the expensive full rescan.
  static const _healthyDelayMs = 500;

  /// Only switch to the fastest server when it is at least this much faster
  /// than the current one, so the connection does not jump around.
  static const _switchDiffMs = 1000;

  UpdateInfo? _availableUpdate;
  bool _isCheckingUpdate = false;
  bool _isDownloadingUpdate = false;
  double? _downloadProgress;
  String? _downloadedApkPath;
  String? _currentVersion;
  String _proxyHost = '127.0.0.1';

  String? get subscriptionUrl => _subscriptionUrl;
  List<ServerConfig> get servers => List.unmodifiable(_servers);
  SubscriptionInfo? get subscriptionInfo => _subscriptionInfo;
  int get selectedIndex => _selectedIndex;
  ConnectionStatus get connectionStatus => _connectionStatus;
  VlessStatus get status => _status;
  bool get isLoadingSubscription => _isLoadingSubscription;
  bool get isMeasuringDelay => _isMeasuringDelay;

  int? get measuringIndex => _measuringIndex;
  bool get isConnected => _connectionStatus == ConnectionStatus.connected;

  UpdateInfo? get availableUpdate => _availableUpdate;
  bool get isCheckingUpdate => _isCheckingUpdate;
  bool get isDownloadingUpdate => _isDownloadingUpdate;
  double? get downloadProgress => _downloadProgress;
  String? get downloadedApkPath => _downloadedApkPath;
  String get currentVersion => _currentVersion ?? '1.0.0';

  bool get proxyOnly => _storage.proxyOnly;
  bool get autoConnect => _storage.autoConnect;
  bool get autoSelectBest => _storage.autoSelectBest;
  String get pingMethod => _storage.pingMethod;

  String get proxyLogin => _storage.proxyLogin;
  String get proxyPassword => _storage.proxyPassword;
  String get proxyHost => _proxyHost;
  int get proxyPort => VpnService.proxyPort;

  ServerConfig? get selectedServer =>
      _servers.isEmpty ? null : _servers[_selectedIndex.clamp(0, _servers.length - 1)];

  bool get hasSubscription => _subscriptionUrl != null && _servers.isNotEmpty;

  Future<void> init() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await _storage.init();
    _subscriptionUrl = _storage.subscriptionUrl;
    _servers = _storage.servers;
    _selectedIndex = _storage.selectedServerIndex;
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
    } catch (_) {}
    await VpnService.instance.initialize();
    notifyListeners();
    unawaited(scheduledUpdateCheck());
    _updateCheckTimer = Timer.periodic(
      const Duration(hours: 4),
      (_) => unawaited(scheduledUpdateCheck()),
    );
    _autoSelectTimer = Timer.periodic(
      _autoSelectInterval,
      (_) => unawaited(_autoSelectMonitor()),
    );
  }

  Timer? _updateCheckTimer;
  Timer? _autoSelectTimer;

  Future<void> scheduledUpdateCheck() async {
    final last = _storage.lastUpdateCheck;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(hours: 22)) {
      return;
    }
    try {
      await checkForUpdates();
    } catch (_) {}
    await _storage.setLastUpdateCheck(DateTime.now());
  }

  Future<void> addSubscription(String url) async {
    if (_isLoadingSubscription) {
      return;
    }
    _isLoadingSubscription = true;
    notifyListeners();
    try {
      final result = await _subscriptionService.fetch(
        url,
        deviceId: await _storage.getOrCreateDeviceId(),
      );
      _subscriptionUrl = url.trim();
      _servers = result.servers;
      _subscriptionInfo = result.info;
      await _storage.setSubscriptionUrl(_subscriptionUrl!);
      await _storage.setServers(_servers);
      _selectedIndex = 0;
      await _storage.setSelectedServerIndex(0);
      _connectionStatus = ConnectionStatus.disconnected;
      await _stopIfNeeded();
      notifyListeners();
      unawaited(_measureDelays(method: 'tcp'));
    } catch (e) {
      rethrow;
    } finally {
      _isLoadingSubscription = false;
      notifyListeners();
    }
  }

  Future<void> refreshSubscription() async {
    final url = _subscriptionUrl;
    if (url == null || _isLoadingSubscription) {
      return;
    }
    _isLoadingSubscription = true;
    notifyListeners();
    try {
      final result = await _subscriptionService.fetch(
        url,
        deviceId: await _storage.getOrCreateDeviceId(),
      );
      _servers = result.servers;
      _subscriptionInfo = result.info;
      if (_selectedIndex >= _servers.length) {
        _selectedIndex = _servers.isNotEmpty ? 0 : 0;
      }
      await _storage.setServers(_servers);
      notifyListeners();
      unawaited(_measureDelays(method: 'tcp'));
    } catch (e) {
      rethrow;
    } finally {
      _isLoadingSubscription = false;
      notifyListeners();
    }
  }

  Future<void> selectServer(int index) async {
    if (index < 0 || index >= _servers.length || index == _selectedIndex) {
      return;
    }
    _selectedIndex = index;
    _storage.setSelectedServerIndex(index);
    notifyListeners();
    if (_connectionStatus == ConnectionStatus.connected ||
        _connectionStatus == ConnectionStatus.connecting) {
      await _stopIfNeeded();
      await _connect();
    }
  }

  Future<void> measureDelays({bool force = false}) => _measureDelays(
        method: _storage.pingMethod,
        force: force,
      );

  /// Measures a single server immediately (used by long-press on a server card).
  Future<void> measureServerDelay(int index) async {
    if (index < 0 || index >= _servers.length) {
      return;
    }
    _measuringIndex = index;
    notifyListeners();
    final server = _servers[index];
    try {
      final delay = await VpnService.instance
          .measureServerDelay(server, method: _storage.pingMethod);
      server.delayMs = delay;
    } catch (_) {
      server.delayMs = null;
    }
    server.delayCheckedAt = DateTime.now();
    _measuringIndex = null;
    notifyListeners();
  }

  Future<void> _measureDelays({
    required String method,
    bool force = false,
  }) async {
    if (_isMeasuringDelay) {
      return;
    }
    _isMeasuringDelay = true;
    notifyListeners();

    final concurrency = 16;
    var next = 0;
    final jobs = <Future<void>>[];
    for (var i = 0; i < concurrency && next < _servers.length; i++) {
      jobs.add(_delayWorker(() => next++, force: force, method: method));
    }
    await Future.wait(jobs);

    _isMeasuringDelay = false;
    if (_storage.autoSelectBest && !isConnected) {
      _autoSelectFastest();
    }
    notifyListeners();
  }

  Future<void> _delayWorker(
    int Function() next, {
    required bool force,
    required String method,
  }) async {
    while (true) {
      final index = next();
      if (index >= _servers.length) {
        return;
      }
      final server = _servers[index];
      final now = DateTime.now();
      if (!force &&
          server.delayCheckedAt != null &&
          now.difference(server.delayCheckedAt!) < const Duration(minutes: 2)) {
        continue;
      }
      try {
        final delay = await VpnService.instance
            .measureServerDelay(server, method: method);
        server.delayMs = delay;
      } catch (_) {
        server.delayMs = null;
      }
      server.delayCheckedAt = DateTime.now();
      notifyListeners();
    }
  }

  void _autoSelectFastest() {
    var bestIndex = -1;
    var bestDelay = 1 << 30;
    for (var i = 0; i < _servers.length; i++) {
      final delay = _servers[i].delayMs;
      if (delay != null && delay > 0 && delay < bestDelay) {
        bestDelay = delay;
        bestIndex = i;
      }
    }
    if (bestIndex >= 0) {
      _selectedIndex = bestIndex;
      _storage.setSelectedServerIndex(bestIndex);
    }
  }

  /// Real-time monitoring while connected: every [_autoSelectInterval] measure
  /// the active server's real HTTP GET ping through the tunnel. If it stays
  /// healthy nothing happens. When it degrades, rescan all servers with the
  /// same HTTP GET method and switch to the fastest one, but only if it is at
  /// least [_switchDiffMs] faster — otherwise the connection would bounce
  /// between servers every minute.
  Future<void> _autoSelectMonitor() async {
    if (!_storage.autoSelectBest || !isConnected || _isMeasuringDelay) {
      return;
    }
    final currentIndex = _selectedIndex;

    int? currentDelay;
    try {
      final raw = await VpnService.instance.getConnectedServerDelay();
      currentDelay = raw > 0 ? raw : null;
    } catch (_) {}
    if (currentDelay != null && currentIndex < _servers.length) {
      _servers[currentIndex].delayMs = currentDelay;
      _servers[currentIndex].delayCheckedAt = DateTime.now();
      notifyListeners();
    }
    if (currentDelay != null && currentDelay < _healthyDelayMs) {
      return;
    }

    await _measureDelays(method: 'get', force: true);
    if (!isConnected) {
      return;
    }

    var bestIndex = -1;
    var bestDelay = 1 << 30;
    for (var i = 0; i < _servers.length; i++) {
      final delay = _servers[i].delayMs;
      if (delay != null && delay > 0 && delay < bestDelay) {
        bestDelay = delay;
        bestIndex = i;
      }
    }
    if (bestIndex < 0 || bestIndex == currentIndex) {
      return;
    }
    final effectiveCurrent = currentDelay ?? _servers[currentIndex].delayMs;
    if (effectiveCurrent == null ||
        bestDelay + _switchDiffMs < effectiveCurrent) {
      await selectServer(bestIndex);
    }
  }

  Future<void> toggleConnection() async {
    switch (_connectionStatus) {
      case ConnectionStatus.disconnected:
        await _connect();
      case ConnectionStatus.connected:
        await _disconnect();
      case ConnectionStatus.connecting:
      case ConnectionStatus.disconnecting:
        break;
    }
  }

  Future<void> _connect() async {
    final server = selectedServer;
    if (server == null) {
      return;
    }
    final vpn = VpnService.instance;
    final proxyOnly = _storage.proxyOnly;

    if (!proxyOnly) {
      final allowed = await vpn.requestPermission();
      if (!allowed) {
        return;
      }
    }

    var config = server.runtimeConfig;
    if (proxyOnly) {
      await _ensureProxyCredentials();
      await refreshProxyHost();
      config = vpn.buildAuthProxyConfig(
        config,
        _storage.proxyLogin,
        _storage.proxyPassword,
      );
    } else {
      config = vpn.buildInternalSocksConfig(config);
    }

    _connectionStatus = ConnectionStatus.connecting;
    notifyListeners();
    try {
      await vpn.start(server, proxyOnly: proxyOnly, config: config);
    } catch (_) {
      _connectionStatus = ConnectionStatus.disconnected;
      notifyListeners();
    }
  }

  Future<void> _ensureProxyCredentials() async {
    if (_storage.proxyLogin.isNotEmpty && _storage.proxyPassword.isNotEmpty) {
      return;
    }
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    String generate() => List.generate(
          6,
          (_) => chars[random.nextInt(chars.length)],
        ).join();
    await _storage.setProxyCredentials(generate(), generate());
  }

  /// Local SOCKS endpoint the app uses to reach the tunnel (IP/speed widgets).
  TunnelHttp get tunnelHttp {
    if (proxyOnly) {
      return TunnelHttp(
        host: '127.0.0.1',
        port: VpnService.proxyPort,
        username: _storage.proxyLogin,
        password: _storage.proxyPassword,
      );
    }
    return TunnelHttp(
      host: '127.0.0.1',
      port: VpnService.instance.lastInternalSocksPort ??
          VpnService.internalSocksPort,
    );
  }

  /// Public IP visible through the active tunnel, or null when disconnected.
  Future<String?> fetchCurrentIp() => tunnelHttp.fetchIp();

  /// Download speed through the tunnel in Mbps, or null when unavailable.
  Future<double?> measureSpeed({Duration duration = const Duration(seconds: 5)}) {
    return tunnelHttp.measureMbps(duration: duration);
  }

  Future<void> refreshProxyHost() async {
    _proxyHost = await _resolveLanIp();
    notifyListeners();
  }

  Future<String> _resolveLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.') ||
              ip.startsWith('169.254.') ||
              ip == '0.0.0.0') {
            continue;
          }
          return ip;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  Future<void> _disconnect() async {
    _connectionStatus = ConnectionStatus.disconnecting;
    notifyListeners();
    try {
      await VpnService.instance.stop();
    } catch (_) {
      _connectionStatus = ConnectionStatus.disconnected;
      notifyListeners();
    }
  }

  Future<void> _stopIfNeeded() async {
    if (_connectionStatus != ConnectionStatus.disconnected) {
      _connectionStatus = ConnectionStatus.disconnected;
      try {
        await VpnService.instance.stop();
      } catch (_) {}
    }
  }

  void _onStatusChanged(VlessStatus status) {
    _status = status;
    switch (status.connectionState) {
      case VlessConnectionState.connected:
        _connectionStatus = ConnectionStatus.connected;
      case VlessConnectionState.connecting:
        _connectionStatus = ConnectionStatus.connecting;
      case VlessConnectionState.disconnected:
      case VlessConnectionState.disconnecting:
      case VlessConnectionState.unknown:
        _connectionStatus = ConnectionStatus.disconnected;
    }
    notifyListeners();
  }

  Future<void> setProxyOnly(bool value) async {
    await _storage.setProxyOnly(value);
    notifyListeners();
  }

  Future<void> setAutoConnect(bool value) async {
    await _storage.setAutoConnect(value);
    notifyListeners();
  }

  Future<void> setAutoSelectBest(bool value) async {
    await _storage.setAutoSelectBest(value);
    notifyListeners();
  }

  Future<void> setPingMethod(String value) async {
    await _storage.setPingMethod(value);
    notifyListeners();
  }

  Future<void> removeSubscription() async {
    await _stopIfNeeded();
    await _storage.clearSubscription();
    _subscriptionUrl = null;
    _servers = [];
    _subscriptionInfo = null;
    _selectedIndex = 0;
    _connectionStatus = ConnectionStatus.disconnected;
    notifyListeners();
  }

  Future<bool> checkForUpdates() async {
    if (_isCheckingUpdate) {
      return false;
    }
    _isCheckingUpdate = true;
    notifyListeners();
    try {
      final update = await UpdateService.instance.checkForUpdate(
        currentVersion: currentVersion,
      );
      _availableUpdate = update;
      if (update == null) {
        _downloadedApkPath = null;
        _downloadProgress = null;
      }
      return update != null;
    } catch (_) {
      _availableUpdate = null;
      rethrow;
    } finally {
      _isCheckingUpdate = false;
      notifyListeners();
    }
  }

  Future<void> downloadUpdate() async {
    final update = _availableUpdate;
    if (update == null || _isDownloadingUpdate) {
      return;
    }
    _isDownloadingUpdate = true;
    _downloadProgress = 0;
    notifyListeners();
    try {
      final path = await UpdateService.instance.download(
        update.apkUrl,
        onProgress: (received, total) {
          if (total > 0) {
            _downloadProgress = received / total;
          }
          notifyListeners();
        },
      );
      _downloadedApkPath = path;
      _downloadProgress = 1;
    } catch (e) {
      _downloadedApkPath = null;
      _downloadProgress = null;
      rethrow;
    } finally {
      _isDownloadingUpdate = false;
      notifyListeners();
    }
  }

  Future<void> installUpdate() async {
    final path = _downloadedApkPath;
    if (path == null) {
      return;
    }
    await UpdateService.instance.install(path);
  }

  void dismissUpdate() {
    _availableUpdate = null;
    _downloadedApkPath = null;
    _downloadProgress = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _updateCheckTimer?.cancel();
    _autoSelectTimer?.cancel();
    super.dispose();
  }
}
