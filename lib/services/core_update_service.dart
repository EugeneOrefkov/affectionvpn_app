import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/utils/device_abi.dart';

/// Downloads and installs an experimental (freshest) Xray core next to the
/// bundled one. The installed core lives in the app files dir under
/// `xray_core/libxray.so`; the native plugin prefers it over the bundled
/// `libxray.so`. Removing the directory reverts to the bundled core.
class CoreUpdateService {
  CoreUpdateService._();
  static final CoreUpdateService instance = CoreUpdateService._();

  static const _repo = 'XTLS/Xray-core';
  static const _headers = {'User-Agent': 'AffectionVPN/1.0'};

  /// Xray-core publishes Android bundles only for these ABIs. Everything else
  /// keeps the bundled core.
  static const _abiAssets = {
    'arm64-v8a': 'Xray-android-arm64-v8a.zip',
    'x86_64': 'Xray-android-amd64.zip',
  };

  /// Latest Xray-core release tag (including prereleases), e.g. "26.7.28".
  /// Null when the version list cannot be reached.
  Future<String?> fetchLatestVersion() async {
    final response = await http
        .get(
          Uri.parse('https://api.github.com/repos/$_repo/releases?per_page=10'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      return null;
    }
    return parseLatestVersion(jsonDecode(response.body) as List<dynamic>);
  }

  /// First Xray version tag in a GitHub releases payload (they are sorted
  /// newest first), or null when none matches.
  @visibleForTesting
  static String? parseLatestVersion(List<dynamic> releases) {
    for (final release in releases) {
      final tag = (release['tag_name'] as String?) ?? '';
      if (RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(tag)) {
        return tag.startsWith('v') ? tag.substring(1) : tag;
      }
    }
    return null;
  }

  /// Whether the device can run an experimental core (Xray publishes Android
  /// bundles only for arm64-v8a and x86_64).
  Future<bool> isSupported() async {
    final abi = await deviceAbiKey();
    return _abiAssets.containsKey(abi);
  }

  /// Installs the given Xray version as the active experimental core.
  Future<void> install(String version) async {
    final abi = await deviceAbiKey();
    final asset = _abiAssets[abi];
    if (asset == null) {
      throw Exception('Экспериментальное ядро недоступно для этого устройства');
    }
    final url =
        'https://github.com/$_repo/releases/download/v$version/$asset';

    final tempDir = await getTemporaryDirectory();
    final zipFile = File('${tempDir.path}/xray_experimental_$version.zip');
    await _download(url, zipFile);

    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final entry = archive.files
          .where((f) => f.isFile)
          .firstWhereOrNull((f) => f.name.endsWith('libxray.so'));
      if (entry == null) {
        throw Exception('В архиве не найден libxray.so');
      }

      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/xray_core');
      await dir.create(recursive: true);
      final target = File('${dir.path}/libxray.so');
      await target.writeAsBytes(entry.content, flush: true);
      await File('${dir.path}/version').writeAsString(version);
    } finally {
      if (zipFile.existsSync()) {
        await zipFile.delete();
      }
    }
  }

  /// Removes the experimental core; the bundled one is used again.
  Future<void> reset() async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/xray_core',
    );
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  /// Version of the installed experimental core, or null when not installed.
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
