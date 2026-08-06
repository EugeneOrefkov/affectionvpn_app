import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:http/http.dart' as http;

import '../models/server_config.dart';
import '../models/subscription_info.dart';

class SubscriptionResult {
  const SubscriptionResult({
    required this.servers,
    required this.info,
  });

  final List<ServerConfig> servers;
  final SubscriptionInfo? info;
}

class SubscriptionService {
  SubscriptionService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _userAgent =
      'AffectionVPN/1.0 (Xray; VLESS)';

  /// Headers used by Remnawave to identify the requesting device when the
  /// device limit feature is enabled. Only `X-Hwid` is mandatory; the model
  /// and OS version are reported separately so the panel shows them correctly.
  static Map<String, String> hwidHeaders(
    String deviceId, {
    String? osVersion,
    String? deviceModel,
  }) {
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      _ => 'Other',
    };
    return {
      'X-Hwid': deviceId,
      'X-Device-Os': platform,
      if (osVersion != null && osVersion.isNotEmpty) 'X-Ver-Os': osVersion,
      if (deviceModel != null && deviceModel.isNotEmpty)
        'X-Device-Model': deviceModel,
    };
  }

  /// Real device model and OS version reported to the panel. Falls back to
  /// empty values when the platform is unknown or the plugin is unavailable
  /// (e.g. in unit tests), so the subscription request never breaks on it.
  static Future<({String osVersion, String deviceModel})>
      _collectDeviceInfo() async {
    try {
      final info = await DeviceInfoPlugin().deviceInfo;
      if (info is AndroidDeviceInfo) {
        return (osVersion: info.version.release, deviceModel: info.model);
      }
      if (info is IosDeviceInfo) {
        return (
          osVersion: info.systemVersion,
          deviceModel: info.utsname.machine,
        );
      }
      if (info is LinuxDeviceInfo) {
        return (
          osVersion: info.versionId ?? '',
          deviceModel: info.prettyName,
        );
      }
    } catch (_) {}
    return (osVersion: '', deviceModel: '');
  }

  Future<SubscriptionResult> fetch(String url, {String? deviceId}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      throw const FormatException('Некорректная ссылка на подписку');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException('Ссылка должна начинаться с http(s)://');
    }

    // Remnawave serves load-balancer nodes only through the XRAY_JSON
    // subscription type (`/json` path segment) — plain share links carry the
    // virtual host with a placeholder address instead. Try `/json` first so
    // balancer configs reach the app; fall back to the plain format when the
    // panel does not support it (empty or unparseable response).
    final jsonUri = _withClientType(uri, 'json');
    if (jsonUri != uri) {
      try {
        final result = await _fetchUri(jsonUri, deviceId: deviceId);
        if (result.servers.isNotEmpty) {
          return result;
        }
      } catch (_) {
        // Non-Remnawave panel or no XRAY_JSON template; retry without suffix.
      }
    }
    return _fetchUri(uri, deviceId: deviceId);
  }

  /// Appends a client type to the subscription path: `.../sub/<uuid>` →
  /// `.../sub/<uuid>/json`. Returns [uri] unchanged when it already carries
  /// the client type, so the suffix is never appended twice.
  static Uri _withClientType(Uri uri, String clientType) {
    final path = uri.path;
    if (path.endsWith('/$clientType') || path.endsWith('/$clientType/')) {
      return uri;
    }
    final trimmed =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    return uri.replace(path: '$trimmed/$clientType');
  }

  Future<SubscriptionResult> _fetchUri(Uri uri, {String? deviceId}) async {
    final headers = <String, String>{
      'User-Agent': _userAgent,
      'Accept': '*/*',
    };
    if (deviceId != null && deviceId.isNotEmpty) {
      final info = await _collectDeviceInfo();
      headers.addAll(
        hwidHeaders(
          deviceId,
          osVersion: info.osVersion,
          deviceModel: info.deviceModel,
        ),
      );
    }

    final response = await _client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Сервер ответил: ${response.statusCode}');
    }

    SubscriptionInfo? info;
    final userInfo = response.headers['subscription-userinfo'];
    if (userInfo != null && userInfo.isNotEmpty) {
      info = SubscriptionInfo.fromUserInfoHeader(userInfo);
    }

    final servers = <ServerConfig>[];
    try {
      final profiles = FlutterVless.parseMany(response.body);
      for (final profile in profiles) {
        final server = ServerConfig.fromProfile(profile);
        if (server != null) {
          servers.add(server);
        }
      }
    } catch (e) {
      throw Exception('Не удалось разобрать подписку: $e');
    }

    if (servers.isEmpty) {
      throw Exception('В подписке не найдено ни одного сервера');
    }

    return SubscriptionResult(servers: servers, info: info);
  }
}
