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
  SubscriptionService();

  static const _userAgent =
      'AffectionVPN/1.0 (Xray; VLESS)';

  Future<SubscriptionResult> fetch(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      throw const FormatException('Некорректная ссылка на подписку');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException('Ссылка должна начинаться с http(s)://');
    }

    final request = http.Request('GET', uri);
    request.headers['User-Agent'] = _userAgent;
    request.headers['Accept'] = '*/*';

    final streamed = await request.send().timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamed);

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
        final link = profile.url;
        final server = ServerConfig.fromLink(link);
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
