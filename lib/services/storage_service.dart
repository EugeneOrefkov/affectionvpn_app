import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_config.dart';

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const _kSubscriptionUrl = 'subscription_url';
  static const _kServers = 'servers';
  static const _kSelectedIndex = 'selected_server_index';
  static const _kProxyOnly = 'proxy_only';
  static const _kAutoConnect = 'auto_connect';
  static const _kAutoSelectBest = 'auto_select_best';
  static const _kLastUpdateCheck = 'last_update_check';
  static const _kProxyLogin = 'proxy_login';
  static const _kProxyPassword = 'proxy_password';
  static const _kPingMethod = 'ping_method';
  static const _kDeviceId = 'device_id';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String? get subscriptionUrl => _prefs.getString(_kSubscriptionUrl);

  Future<void> setSubscriptionUrl(String url) async {
    await _prefs.setString(_kSubscriptionUrl, url);
  }

  List<ServerConfig> get servers {
    final raw = _prefs.getString(_kServers);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => _serverFromJson(e as Map<String, dynamic>))
          .whereType<ServerConfig>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> setServers(List<ServerConfig> servers) async {
    final list = servers.map(_serverToJson).toList();
    await _prefs.setString(_kServers, jsonEncode(list));
  }

  int get selectedServerIndex {
    final idx = _prefs.getInt(_kSelectedIndex);
    if (idx == null || idx < 0 || idx >= servers.length) {
      return 0;
    }
    return idx;
  }

  Future<void> setSelectedServerIndex(int index) async {
    await _prefs.setInt(_kSelectedIndex, index);
  }

  bool get proxyOnly => _prefs.getBool(_kProxyOnly) ?? false;

  Future<void> setProxyOnly(bool value) async {
    await _prefs.setBool(_kProxyOnly, value);
  }

  bool get autoConnect => _prefs.getBool(_kAutoConnect) ?? false;

  Future<void> setAutoConnect(bool value) async {
    await _prefs.setBool(_kAutoConnect, value);
  }

  bool get autoSelectBest => _prefs.getBool(_kAutoSelectBest) ?? false;

  Future<void> setAutoSelectBest(bool value) async {
    await _prefs.setBool(_kAutoSelectBest, value);
  }

  DateTime? get lastUpdateCheck {
    final millis = _prefs.getInt(_kLastUpdateCheck);
    if (millis == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> setLastUpdateCheck(DateTime time) async {
    await _prefs.setInt(_kLastUpdateCheck, time.millisecondsSinceEpoch);
  }

  String get proxyLogin => _prefs.getString(_kProxyLogin) ?? '';

  String get proxyPassword => _prefs.getString(_kProxyPassword) ?? '';

  Future<void> setProxyCredentials(String login, String password) async {
    await _prefs.setString(_kProxyLogin, login);
    await _prefs.setString(_kProxyPassword, password);
  }

  String get pingMethod => _prefs.getString(_kPingMethod) == 'tcp' ? 'tcp' : 'get';

  Future<void> setPingMethod(String value) async {
    await _prefs.setString(_kPingMethod, value == 'tcp' ? 'tcp' : 'get');
  }

  /// Persistent device identifier reported to the subscription server as
  /// `X-Hwid`. Generated once and reused so the server can track the device.
  String? get deviceId => _prefs.getString(_kDeviceId);

  Future<String> getOrCreateDeviceId() async {
    final existing = _prefs.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final id = generateDeviceId();
    await _prefs.setString(_kDeviceId, id);
    return id;
  }

  /// Remnawave accepts HWIDs matching `^[a-zA-Z0-9=-]{10,64}$`.
  static String generateDeviceId({int length = 32}) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789=-';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  Future<void> clearSubscription() async {
    await _prefs.remove(_kSubscriptionUrl);
    await _prefs.remove(_kServers);
    await _prefs.remove(_kSelectedIndex);
  }

  Map<String, dynamic> _serverToJson(ServerConfig s) {
    return {
      'link': s.link,
      'remark': s.remark,
      'address': s.address,
      'port': s.port,
      'protocol': s.protocol,
      'config': s.config,
      'delayMs': s.delayMs,
      'delayCheckedAt': s.delayCheckedAt?.millisecondsSinceEpoch,
    };
  }

  ServerConfig? _serverFromJson(Map<String, dynamic> json) {
    final config = json['config'] as String?;
    if (config == null || config.isEmpty) {
      return null;
    }
    return ServerConfig(
      link: json['link'] as String? ?? '',
      remark: json['remark'] as String? ?? '',
      address: json['address'] as String? ?? '',
      port: json['port'] as int? ?? 443,
      protocol: json['protocol'] as String? ?? 'vless',
      config: config,
      delayMs: json['delayMs'] as int?,
      delayCheckedAt: json['delayCheckedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              json['delayCheckedAt'] as int,
            )
          : null,
    );
  }
}
