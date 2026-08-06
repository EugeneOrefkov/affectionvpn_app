import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/utils/device_abi.dart';

class CoreUpdateService {
  CoreUpdateService._();
  static final CoreUpdateService instance = CoreUpdateService._();

  static const _mavenGroup = 'dev.tfox.fluttervless';
  static const _mavenArtifact = 'xray-android';
  static const _mavenMetadata =
      'https://repo1.maven.org/maven2/$_mavenGroup/$_mavenArtifact/maven-metadata.xml';
  static const _githubReleases =
      'https://api.github.com/repos/XTLS/Xray-core/releases?per_page=10';
  static const _headers = {'User-Agent': 'AffectionVPN/1.0'};

  static const _abiAssets = {
    'arm64-v8a': 'arm64-v8a',
    'x86_64': 'x86_64',
  };

  Future<String?> fetchLatestVersion() async {
    try {
      final response = await http
          .get(Uri.parse(_mavenMetadata), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final version = RegExp(r'<latest>([^<]+)</latest>')
            .firstMatch(response.body)
            ?.group(1);
        if (version != null && version.isNotEmpty) {
          return version;
        }
      }
    } catch (_) {}
    // Fallback: GitHub API if Maven Central is unreachable.
    try {
      final response = await http
          .get(Uri.parse(_githubReleases), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final releases = jsonDecode(response.body) as List<dynamic>;
        for (final release in releases) {
          final tag = (release['tag_name'] as String?) ?? '';
          if (RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(tag)) {
            return tag.startsWith('v') ? tag.substring(1) : tag;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> isSupported() async {
    final abi = await deviceAbiKey();
    return _abiAssets.containsKey(abi);
  }

  Future<void> install(String version) async {
    final abi = await deviceAbiKey();
    final jniAbi = _abiAssets[abi];
    if (jniAbi == null) {
      throw Exception('Экспериментальное ядро недоступно для этого устройства');
    }

    final aarUrl =
        'https://repo1.maven.org/maven2/$_mavenGroup/$_mavenArtifact/$version/$_mavenArtifact-$version.aar';

    final tempDir = await getTemporaryDirectory();
    final aarFile = File('${tempDir.path}/xray_experimental_$version.aar');
    await _download(aarUrl, aarFile);

    try {
      final bytes = await aarFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final entry = archive.files.firstWhereOrNull(
        (f) => f.isFile && f.name == 'jni/$jniAbi/libxray.so',
      );
      if (entry == null) {
        throw Exception('В AAR не найден libxray.so для $abi');
      }

      final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/xray_core',
      );
      await dir.create(recursive: true);
      final target = File('${dir.path}/libxray.so');
      await target.writeAsBytes(entry.content, flush: true);
      await File('${dir.path}/version').writeAsString(version);
    } finally {
      if (aarFile.existsSync()) {
        await aarFile.delete();
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

  Future<void> _download(String url, File target) async {
    final request = http.Request('GET', Uri.parse(url));
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

extension _FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final element in this) {
      if (test(element)) {
        return element;
      }
    }
    return null;
  }
}
