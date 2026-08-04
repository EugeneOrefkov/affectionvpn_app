import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';
import '../models/update_info.dart';

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _repo = '${AppConfig.githubOwner}/${AppConfig.githubRepo}';
  static const _headers = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'AffectionVPN/1.0 (Xray; VLESS)',
  };

  Future<UpdateInfo?> checkForUpdate({required String currentVersion}) async {
    final url = 'https://api.github.com/repos/$_repo/releases/latest';
    final response = await http
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw Exception('GitHub ответил: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    String? apkUrl;
    int? size;
    for (final asset in data['assets'] as List? ?? const []) {
      final name = ((asset as Map<String, dynamic>)['name'] as String?) ?? '';
      if (name.toLowerCase().endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        size = asset['size'] as int?;
        break;
      }
    }
    if (apkUrl == null || apkUrl.isEmpty) {
      return null;
    }

    final tag = (data['tag_name'] as String?) ?? '';
    final version = _normalizeVersion(tag);
    if (version.isEmpty || !_isNewer(version, currentVersion)) {
      return null;
    }

    final published = data['published_at'] as String?;
    return UpdateInfo(
      version: version,
      apkUrl: apkUrl,
      tagName: tag,
      changelog: data['body'] as String?,
      publishedAt: published != null ? DateTime.tryParse(published) : null,
      size: size,
    );
  }

  Future<String> download(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/affection_vpn_update.apk';

    final request = http.Request('GET', Uri.parse(url));
    request.headers['User-Agent'] = 'AffectionVPN/1.0 (Xray; VLESS)';

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    if (streamed.statusCode != 200) {
      throw Exception('Скачивание не удалось: ${streamed.statusCode}');
    }

    final total = streamed.contentLength ?? 0;
    final file = File(path);
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (total > 0 && received < total) {
      throw Exception('Загрузка прервана');
    }
    return path;
  }

  Future<void> install(String path) async {
    final result = await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
    switch (result.type) {
      case ResultType.done:
        return;
      case ResultType.fileNotFound:
        throw Exception('Файл APK не найден');
      case ResultType.noAppToOpen:
        throw Exception('Установщик APK не найден');
      case ResultType.permissionDenied:
        throw Exception('Нет разрешения на установку из этого источника');
      case ResultType.error:
        throw Exception('Не удалось запустить установщик');
    }
  }

  String _normalizeVersion(String tag) {
    var v = tag.trim().toLowerCase();
    if (v.startsWith('v')) {
      v = v.substring(1);
    }
    final match = RegExp(r'^(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(v);
    if (match == null) {
      return '';
    }
    return '${match.group(1) ?? '0'}.${match.group(2) ?? '0'}.'
        '${match.group(3) ?? '0'}';
  }

  bool _isNewer(String candidate, String current) {
    final c = _parse(candidate);
    final cur = _parse(current);
    if (c == null || cur == null) {
      return false;
    }
    for (var i = 0; i < 3; i++) {
      if (c[i] != cur[i]) {
        return c[i] > cur[i];
      }
    }
    return false;
  }

  List<int>? _parse(String version) {
    final parts = version.split('.').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) {
      return null;
    }
    return parts.cast<int>();
  }
}
