import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';
import '../core/utils/device_abi.dart';

/// Installs experimental Xray cores built from the Xray-core sources.
///
/// The stable core is bundled with the app (flutter_vless AAR from Maven
/// Central on Android, the staged `xray` binary on Linux). Experimental cores
/// track upstream XTLS/Xray-core releases:
///   - Android: built from sources by scripts/build_xray_experimental.sh and
///     published to the `experimental-core` branch of this repo, downloaded
///     via raw.githubusercontent.com (no GitHub release involved);
///   - Linux: the official Xray-linux-64.zip is downloaded straight from the
///     upstream release and unpacked (it carries the xray binary plus
///     geoip.dat/geosite.dat).
class CoreUpdateService {
  CoreUpdateService._();
  static final CoreUpdateService instance = CoreUpdateService._();

  static const _xrayReleases =
      'https://api.github.com/repos/XTLS/Xray-core/releases';
  static const _headers = {'User-Agent': 'AffectionVPN/1.0'};

  /// Platforms with an experimental core available.
  static const _supportedAbis = {'arm64-v8a', 'x86_64', 'linux-x64'};

  /// Latest Xray-core release tag (without the leading "v").
  ///
  /// XTLS marks every current Xray-core release as a prerelease, so
  /// `releases/latest` (which only returns non-prereleases) lags behind.
  /// The experimental panel is meant to track the newest upstream build, so
  /// the first release tag is used regardless of its prerelease flag.
  Future<String?> fetchLatestVersion() async {
    for (final url in [
      '$_xrayReleases?per_page=10',
      '$_xrayReleases/latest',
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

    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/xray_core',
    );
    await dir.create(recursive: true);

    if (abi == 'linux-x64') {
      await _installLinux(dir, version);
    } else {
      await _installAndroid(dir, version, abi);
    }
    await File('${dir.path}/version').writeAsString(version);
  }

  /// Android: download the source-built libxray.so from the
  /// `experimental-core` branch of this repo.
  Future<void> _installAndroid(Directory dir, String version, String abi) async {
    final url = Uri.parse(
      'https://raw.githubusercontent.com/${AppConfig.githubOwner}/'
      '${AppConfig.githubRepo}/experimental-core/'
      'libxray-$abi-$version.so',
    );
    final tempDir = await getTemporaryDirectory();
    final soFile = File('${tempDir.path}/xray_experimental_$version.so');
    await _download(url, soFile);
    try {
      await soFile.copy('${dir.path}/libxray.so');
    } finally {
      if (soFile.existsSync()) {
        await soFile.delete();
      }
    }
  }

  /// Linux: unpack the official Xray-linux-64.zip (xray + geoip.dat +
  /// geosite.dat) straight from the upstream release.
  Future<void> _installLinux(Directory dir, String version) async {
    final url = Uri.parse(
      'https://github.com/XTLS/Xray-core/releases/download/'
      'v$version/Xray-linux-64.zip',
    );
    final tempDir = await getTemporaryDirectory();
    final zipFile = File('${tempDir.path}/xray_experimental_$version.zip');
    await _download(url, zipFile);

    try {
      final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
      const wanted = {'xray', 'geoip.dat', 'geosite.dat'};
      var foundXray = false;
      for (final entry in archive.files) {
        if (!entry.isFile || !wanted.contains(entry.name)) {
          continue;
        }
        if (entry.name == 'xray') {
          foundXray = true;
        }
        await File('${dir.path}/${entry.name}')
            .writeAsBytes(entry.content, flush: true);
      }
      final xray = File('${dir.path}/xray');
      if (!foundXray || !xray.existsSync()) {
        throw Exception('В архиве Xray не найден бинарь xray');
      }
      try {
        await Process.run('chmod', ['755', xray.path]);
      } catch (_) {}
    } finally {
      if (zipFile.existsSync()) {
        await zipFile.delete();
      }
    }
  }

  Future<void> reset() async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/xray_core',
    );
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  Future<String?> installedVersion() async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/xray_core',
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
