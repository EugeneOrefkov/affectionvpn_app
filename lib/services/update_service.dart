import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';
import '../core/utils/device_abi.dart';
import '../models/update_info.dart';
import 'installer_service.dart';

class UnknownSourceInstallException implements Exception {
  const UnknownSourceInstallException();

  @override
  String toString() => 'Установка из неизвестных источников заблокирована';
}

class ChecksumMismatchException implements Exception {
  const ChecksumMismatchException();

  @override
  String toString() => 'Проверка целостности APK не пройдена';
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _repo = '${AppConfig.githubOwner}/${AppConfig.githubRepo}';
  static const _headers = {
    'User-Agent': 'AffectionVPN/1.0 (Xray; VLESS)',
  };

  /// The release manifest is served as the `latest.json` asset of the latest
  /// GitHub release, so it is read without hitting the rate-limited GitHub
  /// API: https://github.com/{owner}/{repo}/releases/latest/download/latest.json
  static const _manifestUrl =
      'https://github.com/$_repo/releases/latest/download/latest.json';

  Future<UpdateInfo?> checkForUpdate({required String currentVersion}) async {
    final response = await http
        .get(Uri.parse(_manifestUrl), headers: _headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw Exception('Проверка обновлений ответила: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final abi = await deviceAbiKey();
    return parseManifest(data, currentVersion: currentVersion, abi: abi);
  }

  /// Turns a decoded `latest.json` manifest into an [UpdateInfo] for the given
  /// device ABI, falling back to the universal asset. Null when the manifest
  /// is not newer than [currentVersion] or carries no usable APK.
  @visibleForTesting
  static UpdateInfo? parseManifest(
    Map<String, dynamic> data, {
    required String currentVersion,
    required String abi,
  }) {
    final version = normalizeVersion((data['version'] as String?) ?? '');
    if (version.isEmpty || !_isNewer(version, currentVersion)) {
      return null;
    }

    final assets = data['assets'] as Map<String, dynamic>? ?? const {};
    Map<String, dynamic>? asset;
    var assetKey = abi;
    if (assets[abi] is Map<String, dynamic>) {
      asset = assets[abi] as Map<String, dynamic>;
    } else {
      assetKey = 'universal';
      if (assets['universal'] is Map<String, dynamic>) {
        asset = assets['universal'] as Map<String, dynamic>;
      }
    }
    if (asset == null) {
      return null;
    }

    final downloadUrl = (abi == 'linux-x64'
            ? (asset['tar_url'] as String?)
            : (asset['apk_url'] as String?)) ??
        (asset['apk_url'] as String?);
    if (downloadUrl == null || downloadUrl.isEmpty) {
      return null;
    }

    final published = data['published_at'] as String?;
    return UpdateInfo(
      version: version,
      apkUrl: downloadUrl,
      tagName: data['tag'] as String?,
      changelog: data['changelog'] as String?,
      publishedAt: published != null ? DateTime.tryParse(published) : null,
      size: (asset['size'] as num?)?.toInt(),
      sha256: asset['sha256'] as String?,
      assetKey: assetKey,
    );
  }

  Future<String> download(
    String url, {
    void Function(int received, int total)? onProgress,
    String? expectedSha256,
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
      await file.delete();
      throw Exception('Загрузка прервана');
    }

    if (!await _verifySha256(path, expectedSha256)) {
      await file.delete();
      throw const ChecksumMismatchException();
    }
    return path;
  }

  Future<void> install(String path) async {
    try {
      final installed = await InstallerService.instance.installApk(path);
      if (installed) {
        return;
      }
    } on PlatformException catch (e) {
      _log('PackageInstaller failed: ${e.code} ${e.message}');
    } catch (e) {
      _log('PackageInstaller failed: $e');
    }

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
        throw const UnknownSourceInstallException();
      case ResultType.error:
        throw Exception('Не удалось запустить установщик');
    }
  }

  Future<bool> _verifySha256(String path, String? expected) async {
    if (expected == null || expected.trim().isEmpty) {
      return true;
    }
    final bytes = await File(path).readAsBytes();
    return sha256Hex(bytes) == expected.trim().toLowerCase();
  }

  /// SHA-256 of [bytes] as a lower-case hex string.
  @visibleForTesting
  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  static void _log(String message) {
    debugPrint(message);
  }

  @visibleForTesting
  static String normalizeVersion(String tag) {
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

  static bool _isNewer(String candidate, String current) {
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

  static List<int>? _parse(String version) {
    final parts = version.split('.').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) {
      return null;
    }
    return parts.cast<int>();
  }
}
