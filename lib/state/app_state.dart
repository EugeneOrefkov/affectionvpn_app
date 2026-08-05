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
      unawaited(_measureDelays());
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
  bool _initialized = false;

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
  }

  Timer? _updateCheckTimer;

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
      final result = await _subscriptionService.fetch(url);
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
      unawaited(_measureDelays());
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
      final result = await _subscriptionService.fetch(url);
      _servers = result.servers;
      _subscriptionInfo = result.info;
      if (_selectedIndex >= _servers.length) {
        _selectedIndex = _servers.isNotEmpty ? 0 : 0;
      }
      await _storage.setServers(_servers);
      notifyListeners();
      unawaited(_measureDelays());
    } catch (e) {
      rethrow;
    } finally {
      _isLoadingSubscription = false;
      notifyListeners();
    }
  }

  void selectServer(int index) {
    if (index < 0 || index >= _servers.length) {
      return;
    }
    _selectedIndex = index;
    _storage.setSelectedServerIndex(index);
    notifyListeners();
  }

  Future<void> measureDelays() => _measureDelays();

  Future<void> _measureDelays() async {
    if (_isMeasuringDelay) {
      return;
    }
    _isMeasuringDelay = true;
    notifyListeners();

    const concurrency = 16;
    var next = 0;
    final jobs = <Future<void>>[];
    for (var i = 0; i < concurrency && next < _servers.length; i++) {
      jobs.add(_delayWorker(() => next++));
    }
    await Future.wait(jobs);

    _isMeasuringDelay = false;
    if (_storage.autoSelectBest && !isConnected) {
      _autoSelectFastest();
    }
    notifyListeners();
  }

  Future<void> _delayWorker(int Function() next) async {
    while (true) {
      final index = next();
      if (index >= _servers.length) {
        return;
      }
      final server = _servers[index];
      final now = DateTime.now();
      if (server.delayCheckedAt != null &&
          now.difference(server.delayCheckedAt!) < const Duration(minutes: 2)) {
        continue;
      }
      try {
        final delay = await VpnService.instance.measureServerDelay(server);
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

    var config = server.config;
    if (proxyOnly) {
      await _ensureProxyCredentials();
      await refreshProxyHost();
      config = vpn.buildAuthProxyConfig(
        config,
        _storage.proxyLogin,
        _storage.proxyPassword,
      );
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
    final password = List.generate(
      12,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    await _storage.setProxyCredentials('affection', password);
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
    super.dispose();
  }
}
