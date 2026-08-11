import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';
import '../core/utils/device_abi.dart';

/// Installs experimental Xray cores built from the Xray-core sources.
///
/// The stable core is bundled in the APK (flutter_vless AAR from Maven
/// Central). Experimental cores are compiled from XTLS/Xray-core by
/// scripts/build_xray_experimental.sh, uploaded to the
/// `experimental-core-v<version>` release of this repo, and downloaded here.
class CoreUpdateService {
  CoreUpdateService._();
  static final CoreUpdateService instance = CoreUpdateService._();

  static const _xrayReleases =
      'https://api.github.com/repos/XTLS/Xray-core/releases';
  static const _headers = {'User-Agent': 'AffectionVPN/1.0'};

  /// ABIs with a source-built experimental core available.
  static const _supportedAbis = {'arm64-v8a', 'x86_64'};

  /// Latest stable Xray-core release tag (without the leading "v").
  Future<String?> fetchLatestVersion() async {
    for (final url in [
      '$_xrayReleases/latest',
      '$_xrayReleases?per_page=10',
    ]) {
      try {
        final response = await http
            .get(Uri.parse(url), headers: _headers)
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          continue;
        }
        final decoded = jsonDecode(response.body);
        final tags = <String>[];
        if (decoded is List) {
          for (final release in decoded) {
            final tag = release['tag_name'] as String?;
            if (tag != null) {
              tags.add(tag);
            }
          }
        } else if (decoded is Map) {
          final tag = decoded['tag_name'] as String?;
          if (tag != null) {
            tags.add(tag);
          }
        }
        for (final tag in tags) {
          final match = RegExp(r'^v?(\d+\.\d+\.\d+)$').firstMatch(tag);
          if (match != null) {
            return match.group(1)!;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<bool> isSupported() async {
    final abi = await deviceAbiKey();
    return _supportedAbis.contains(abi);
  }

  Future<void> install(String version) async {
    final abi = await deviceAbiKey();
    if (!_supportedAbis.contains(abi)) {
      throw Exception('Экспериментальное ядро недоступно для этого устройства');
    }

    final url = Uri.parse(
      'https://github.com/${AppConfig.githubOwner}/${AppConfig.githubRepo}/'
      'releases/download/experimental-core-v$version/'
      'libxray-$abi-$version.so',
    );

    final tempDir = await getTemporaryDirectory();
    final soFile = File('${tempDir.path}/xray_experimental_$version.so');
    await _download(url, soFile);

    try {
      final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/xray_core',
      );
      await dir.create(recursive: true);
      await soFile.copy('${dir.path}/libxray.so');
      await File('${dir.path}/version').writeAsString(version);
    } finally {
      if (soFile.existsSync()) {
        await soFile.delete();
      }
    }
  }

  Future<void> reset() async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/xray_core',
    );
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  Future<String?> installedVersion() async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/xray_core',
    );
    final marker = File('${dir.path}/version');
    if (!marker.existsSync()) {
      return null;
    }
    return marker.readAsStringSync().trim();
  }

  Future<void> _download(Uri url, File target) async {
    final request = http.Request('GET', url);
    request.headers['User-Agent'] = 'AffectionVPN/1.0';
    final streamed = await request.send().timeout(const Duration(seconds: 30));
    if (streamed.statusCode != 200) {
      throw Exception('Скачивание ядра не удалось: ${streamed.statusCode}');
    }
    final sink = target.openWrite();
    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }
}
