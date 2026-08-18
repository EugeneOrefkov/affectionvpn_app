import 'dart:async';
import 'dart:io';
import 'dart:math';



import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/server_config.dart';
import '../models/subscription_info.dart';
import '../models/update_info.dart';
import '../services/request_log_service.dart';
import '../services/storage_service.dart';
import '../services/subscription_service.dart';
import '../services/tunnel_http.dart';
import '../services/update_service.dart';
import '../services/vpn_service.dart';
import '../core/utils/messenger.dart';
import '../services/linux_tray.dart';

enum ConnectionStatus { disconnected, connecting, connected, disconnecting }

class AppState extends ChangeNotifier {
  /// The currently live state. The native Linux tray "Выход" item reaches the
  /// app through this to stop the tunnel before the process exits.
  static AppState? instance;
  AppState() {
    instance = this;
    VpnService.instance.create(
      onStatusChanged: _onStatusChanged,
    );
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        return;
      }
      unawaited(_measureDelays(method: _storage.pingMethod, force: true));
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
  int _connectGeneration = 0;

  int? _measuringIndex;
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

  int? get measuringIndex => _measuringIndex;
  bool get isConnected => _connectionStatus == ConnectionStatus.connected;

  UpdateInfo? get availableUpdate => _availableUpdate;
  bool get isCheckingUpdate => _isCheckingUpdate;
  bool get isDownloadingUpdate => _isDownloadingUpdate;
  double? get downloadProgress => _downloadProgress;
  String? get downloadedApkPath => _downloadedApkPath;
  String get currentVersion => _currentVersion ?? '1.0.0';

  bool get proxyOnly => _storage.proxyOnly;
  bool get proxyAuthEnabled => _storage.proxyAuthEnabled;
  List<String> get bypassCidrs => _storage.bypassCidrs;
  bool get autoConnect => _storage.autoConnect;
  String get pingMethod => _storage.pingMethod;

  bool get showIp => _storage.showIp;
  bool get requestLogEnabled => _storage.requestLogEnabled;
  bool get autoRefreshSubscription => _storage.autoRefreshSubscription;

  Future<void> setAutoRefreshSubscription(bool value) async {
    await _storage.setAutoRefreshSubscription(value);
    notifyListeners();
  }

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
    await _ensureProxyCredentials();
    _subscriptionUrl = _storage.subscriptionUrl;
    _servers = _storage.servers;
    _selectedIndex = _storage.selectedServerIndex;
    await RequestLogService.instance.init();
    RequestLogService.instance.setEnabled(_storage.requestLogEnabled);
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
    } catch (_) {}
    await VpnService.instance.initialize();
    notifyListeners();
    unawaited(_measureDelays(method: _storage.pingMethod));
    unawaited(scheduledUpdateCheck());
    unawaited(_refreshSubscriptionOnStartup());
    _updateCheckTimer = Timer.periodic(
      const Duration(hours: 4),
      (_) => unawaited(scheduledUpdateCheck()),
    );
    _subscriptionRefreshTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => unawaited(_scheduledSubscriptionRefresh()),
    );
  }

  Timer? _updateCheckTimer;
  Timer? _subscriptionRefreshTimer;

  Future<void> _scheduledSubscriptionRefresh() async {
    if (!_storage.autoRefreshSubscription || _subscriptionUrl == null) {
      return;
    }
    try {
      await refreshSubscription();
    } catch (_) {
      // A failed background refresh must not disturb the user.
    }
  }

  /// Triggered once at app launch when a saved subscription URL is present.
  /// The hourly background refresh fires too late to satisfy the home screen
  /// ("Информация о трафике недоступна" was shown until the user hit the
  /// manual refresh button), so we fetch up-front and let errors fail
  /// silently: a one-off startup failure must not surface a snackbar.
  Future<void> _refreshSubscriptionOnStartup() async {
    if (_subscriptionUrl == null) {
      return;
    }
    try {
      await refreshSubscription();
    } catch (_) {
      // Keep the cached servers/info; the user can retry from the UI.
    }
  }

  Future<void> scheduledUpdateCheck() async {
    final last = _storage.lastUpdateCheck;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(hours: 22)) {
      return;
    }
    try {
      await checkForUpdates();
      await _storage.setLastUpdateCheck(DateTime.now());
    } catch (_) {
      // Don't stamp on failure so the next check (timer or manual) can retry.
    }
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
      unawaited(_measureDelays(method: _storage.pingMethod));
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
      unawaited(_measureDelays(method: _storage.pingMethod));
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

    // TCP probes are cheap and cancellable, so fire every server at once and
    // the whole sweep ends within a single probe timeout (~1s). The native GET
    // probe starts a core per server through an 8-thread pool, so keep a
    // modest Dart-side concurrency that keeps the pool saturated.
    final concurrency = method == 'tcp' ? _servers.length.clamp(1, 128) : 16;
    var next = 0;
    final jobs = <Future<void>>[];
    for (var i = 0; i < concurrency && next < _servers.length; i++) {
      jobs.add(_delayWorker(() => next++, force: force, method: method));
    }
    await Future.wait(jobs);

    _isMeasuringDelay = false;
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
    final cidrs = _storage.bypassCidrs;
    if (cidrs.isNotEmpty) {
      config = ServerConfig.injectBypassRules(config, cidrs);
    }
    if (proxyOnly) {
      await refreshProxyHost();
      if (_storage.proxyAuthEnabled) {
        await _ensureProxyCredentials();
        config = vpn.buildAuthProxyConfig(
          config,
          _storage.proxyLogin,
          _storage.proxyPassword,
        );
      } else {
        config = vpn.buildNoAuthProxyConfig(config);
      }
    } else {
      config = vpn.buildInternalSocksConfig(config);
    }

    final gen = ++_connectGeneration;
    _statusGeneration++;
    _connectionStatus = ConnectionStatus.connecting;
    notifyListeners();
    try {
      await vpn.start(server, proxyOnly: proxyOnly, config: config);
    } catch (e) {
      if (gen != _connectGeneration) return;
      _connectionStatus = ConnectionStatus.disconnected;
      notifyListeners();
      // Surface the actual reason instead of leaving the user staring at a
      // "Connecting…" spinner that quietly flips back to "Disconnected".
      // On Linux this is the difference between "the app just doesn't work"
      // and a clear instruction like "install xray" or "fix config".
      unawaited(_showConnectionFailure(e.toString()));
    }
  }

  Future<void> _ensureProxyCredentials() async {
    // Rotate the credentials on every proxy session so a leaked login cannot
    // be reused across connections.
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    String generate() => List.generate(
          12,
          (_) => chars[random.nextInt(chars.length)],
        ).join();
    await _storage.setProxyCredentials(generate(), generate());
  }

  /// Client for the IP/speed widgets. When the tunnel is up it goes through
  /// the app's local SOCKS inbound (auth proxy mode reuses [VpnService.proxyPort]);
  /// when the tunnel is off it connects directly, which yields the real IP and
  /// the plain internet speed.
  TunnelHttp get _networkHttp {
    if (!isConnected) {
      return TunnelHttp.direct();
    }
    if (proxyOnly) {
      return TunnelHttp(
        host: '127.0.0.1',
        port: VpnService.proxyPort,
        username: proxyAuthEnabled ? _storage.proxyLogin : null,
        password: proxyAuthEnabled ? _storage.proxyPassword : null,
      );
    }
    return TunnelHttp(
      host: '127.0.0.1',
      port: VpnService.instance.lastInternalSocksPort ??
          VpnService.internalSocksPort,
    );
  }

  /// HTTP (CONNECT) proxy endpoint the app can route its own `dart:io`
  /// requests through while the tunnel is active, so the in-app update keeps
  /// working even when direct access to GitHub is blocked. Null when
  /// disconnected. Uses the app-local inbounds injected by [VpnService].
  ({String host, int port, String? username, String? password})?
      get activeTunnelProxy {
    if (!isConnected) {
      return null;
    }
    if (proxyOnly) {
      return (
        host: '127.0.0.1',
        port: VpnService.instance.lastAuthHttpPort ?? VpnService.authHttpPort,
        username: proxyAuthEnabled ? _storage.proxyLogin : null,
        password: proxyAuthEnabled ? _storage.proxyPassword : null,
      );
    }
    return (
      host: '127.0.0.1',
      port: VpnService.instance.lastInternalHttpPort ??
          VpnService.internalHttpPort,
      username: null,
      password: null,
    );
  }

  /// Public IP visible from the network (through the tunnel when connected,
  /// otherwise the real IP). Null on any failure.
  Future<String?> fetchCurrentIp() => _networkHttp.fetchIp();

  /// Download speed in Mbps (through the tunnel when connected, otherwise the
  /// plain internet speed). Null on failure.
  Future<double?> measureSpeed({Duration duration = const Duration(seconds: 5)}) {
    return _networkHttp.measureMbps(duration: duration);
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
    } catch (e) {
      _connectionStatus = ConnectionStatus.disconnected;
      notifyListeners();
      unawaited(_showConnectionFailure(e.toString()));
    }
  }

  /// Bridge to the global ScaffoldMessenger so connection errors that fire
  /// without a BuildContext (e.g. when the platform start throws inside
  /// [_connect]) still reach the user as a snackbar.
  Future<void> _showConnectionFailure(String message) async {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) {
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Не удалось подключиться: $message'),
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _stopIfNeeded() async {
    if (_connectionStatus != ConnectionStatus.disconnected) {
      _connectionStatus = ConnectionStatus.disconnected;
      try {
        await VpnService.instance.stop();
      } catch (_) {}
    }
  }

  /// Stops the tunnel and background work before the app process exits.
  /// Invoked from the native Linux tray "Выход" item via the shutdown bridge.
  Future<void> shutdown() => _stopIfNeeded();

  /// Generation counter bumped every time [toggleConnection] fires so that
  /// stale DISCONNECTED broadcasts from a previous connection are ignored.
  int _statusGeneration = 0;

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
        // On Android, stopCore() fires a DISCONNECTED broadcast that can
        // arrive after a new _connect() has already set status to connecting.
        // Ignore stale broadcasts so the new connection isn't killed.
        if (_connectionStatus == ConnectionStatus.connecting) {
          final gen = _statusGeneration;
          Future.delayed(const Duration(seconds: 2), () {
            if (gen == _statusGeneration &&
                _connectionStatus == ConnectionStatus.connecting) {
              _connectionStatus = ConnectionStatus.disconnected;
              notifyListeners();
            }
          });
          return;
        }
        _connectionStatus = ConnectionStatus.disconnected;
    }
    notifyListeners();
  }

  Future<void> setProxyOnly(bool value) async {
    await _storage.setProxyOnly(value);
    notifyListeners();
  }

  Future<void> setProxyAuthEnabled(bool value) async {
    await _storage.setProxyAuthEnabled(value);
    notifyListeners();
  }

  Future<void> addBypassCidr(String cidr) async {
    final list = List<String>.from(_storage.bypassCidrs);
    if (!list.contains(cidr)) {
      list.add(cidr);
      await _storage.setBypassCidrs(list);
      notifyListeners();
    }
  }

  Future<void> removeBypassCidr(String cidr) async {
    final list = List<String>.from(_storage.bypassCidrs);
    if (list.remove(cidr)) {
      await _storage.setBypassCidrs(list);
      notifyListeners();
    }
  }

  Future<void> setAutoConnect(bool value) async {
    await _storage.setAutoConnect(value);
    notifyListeners();
  }

  Future<void> setPingMethod(String value) async {
    await _storage.setPingMethod(value);
    notifyListeners();
  }

  Future<void> setShowIp(bool value) async {
    await _storage.setShowIp(value);
    notifyListeners();
  }

  Future<void> setRequestLogEnabled(bool value) async {
    await _storage.setRequestLogEnabled(value);
    RequestLogService.instance.setEnabled(value);
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
      final dir = await getApplicationDocumentsDirectory();
      final ext = Platform.isAndroid ? '.apk' : '.tar.gz';
      final destPath = '${dir.path}/affection_vpn_update$ext';

      // Always use UpdateService which routes through _tunnelClient()
      // (HTTP CONNECT proxy) — handles HTTPS, redirects, and tunnel
      // routing correctly. The raw TunnelHttp SOCKS client doesn't
      // support TLS or 302 redirects from GitHub release assets.
      await UpdateService.instance.download(update.apkUrl,
          onProgress: (received, total) {
            if (total > 0) {
              _downloadProgress = received / total;
            }
            notifyListeners();
          },
          expectedSha256: update.sha256,
          destPath: destPath);

      _downloadedApkPath = destPath;
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
    if (Platform.isLinux) {
      await _installLinuxUpdate(path);
      return;
    }
    await UpdateService.instance.install(path);
  }

  Future<void> _installLinuxUpdate(String path) async {
    final dir = Directory(path).parent;
    final extractDir = '${dir.path}/update_extracted';
    if (Directory(extractDir).existsSync()) {
      Directory(extractDir).deleteSync(recursive: true);
    }
    Directory(extractDir).createSync();
    final result = await Process.run(
      'tar',
      ['-xzf', path, '-C', extractDir],
    );
    if (result.exitCode != 0) {
      throw Exception('Ошибка распаковки: ${result.stderr}');
    }
    final result2 = await Process.run(
      'pkexec',
      ['cp', '-r', '$extractDir/.', '/opt/affection-vpn/'],
    );
    if (result2.exitCode != 0) {
      throw Exception('Установка требует права root. '
          'Запустите: sudo cp -r $extractDir/. /opt/affection-vpn/');
    }
    Directory(extractDir).deleteSync(recursive: true);

    // Останавливаем туннель и снимаем системный прокси, чтобы свежий
    // экземпляр стартовал с чистого состояния сети.
    await _stopIfNeeded();

    // Перезапускаем только что установленный бинарник, чтобы обновление
    // применилось сразу. Приложение однопанельное (GApplication), поэтому
    // замене даётся секунда на освобождение D-Bus имени текущим процессом.
    final exe = Platform.resolvedExecutable;
    var relaunched = false;
    if (File(exe).existsSync()) {
      try {
        await Process.start('sh', ['-c', r'sleep 1; exec "$0"', exe],
            mode: ProcessStartMode.detached);
        relaunched = true;
      } catch (_) {
        relaunched = false;
      }
    }
    if (!relaunched) {
      throw Exception('Обновление установлено. Запустите приложение заново.');
    }
    exit(0);
  }

  void dismissUpdate() {
    _availableUpdate = null;
    _downloadedApkPath = null;
    _downloadProgress = null;
    notifyListeners();
  }

  /// Keeps the native Linux tray in sync. Every state change the tray displays
  /// (connection status, selected server, server list) flows through
  /// [ChangeNotifier.notifyListeners], so this single hook is enough.
  @override
  void notifyListeners() {
    super.notifyListeners();
    if (Platform.isLinux) {
      LinuxTray.instance.push(this);
    }
  }

  @override
  void dispose() {
    if (instance == this) {
      instance = null;
    }
    _connectivitySub?.cancel();
    _updateCheckTimer?.cancel();
    _subscriptionRefreshTimer?.cancel();
    super.dispose();
  }
}
