import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:affection_vpn/services/core_update_service.dart';
import 'package:affection_vpn/services/update_service.dart';

Map<String, dynamic> _asset(String abi, {String? apkUrl}) {
  return {
    'apk_url': apkUrl ?? 'https://github.com/x/y/releases/download/v2.0.0/affection_vpn-2.0.0-$abi.apk',
    'size': 12345,
    'sha256': 'a' * 64,
  };
}

void main() {
  group('UpdateService.parseManifest', () {
    Map<String, dynamic> manifest({
      String version = '2.0.0',
      Map<String, dynamic>? assets,
    }) {
      return {
        'version': version,
        'tag': 'v$version',
        'published_at': '2026-08-06T10:00:00Z',
        'changelog': 'changelog line',
        'assets': assets ?? {'arm64-v8a': _asset('arm64-v8a')},
      };
    }

    test('picks the asset matching the device ABI', () {
      final info = UpdateService.parseManifest(
        manifest(),
        currentVersion: '1.0.16',
        abi: 'arm64-v8a',
      );
      expect(info, isNotNull);
      expect(info!.version, '2.0.0');
      expect(info.assetKey, 'arm64-v8a');
      expect(info.sha256, 'a' * 64);
      expect(info.changelog, 'changelog line');
      expect(info.publishedAt, DateTime.parse('2026-08-06T10:00:00Z'));
    });

    test('falls back to universal when the ABI asset is absent', () {
      final info = UpdateService.parseManifest(
        manifest(assets: {'universal': _asset('universal')}),
        currentVersion: '1.0.16',
        abi: 'x86_64',
      );
      expect(info, isNotNull);
      expect(info!.assetKey, 'universal');
      expect(info.apkUrl, endsWith('affection_vpn-2.0.0-universal.apk'));
    });

    test('returns null when the version is not newer', () {
      final info = UpdateService.parseManifest(
        manifest(version: '1.0.16'),
        currentVersion: '1.0.16',
        abi: 'arm64-v8a',
      );
      expect(info, isNull);
    });

    test('returns null when no asset is usable', () {
      final info = UpdateService.parseManifest(
        manifest(assets: const {}),
        currentVersion: '1.0.16',
        abi: 'arm64-v8a',
      );
      expect(info, isNull);
    });

    test('returns null when the asset has no apk_url', () {
      final info = UpdateService.parseManifest(
        manifest(assets: {
          'arm64-v8a': {'size': 10},
        }),
        currentVersion: '1.0.16',
        abi: 'arm64-v8a',
      );
      expect(info, isNull);
    });
  });

  group('UpdateService version helpers', () {
    test('normalizeVersion strips a leading v and pads to three parts', () {
      expect(UpdateService.normalizeVersion('v1.0.17'), '1.0.17');
      expect(UpdateService.normalizeVersion('1.2'), '1.2.0');
      expect(UpdateService.normalizeVersion(''), '');
      expect(UpdateService.normalizeVersion('abc'), '');
    });
  });

  group('UpdateService.sha256Hex', () {
    test('matches the known digest of "hello"', () {
      final bytes = utf8.encode('hello');
      expect(
        UpdateService.sha256Hex(bytes),
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      );
    });
  });

  group('CoreUpdateService.parseLatestVersion', () {
    test('picks the first matching version tag, stripping the v', () {
      final releases = [
        {'tag_name': 'v26.7.28'},
        {'tag_name': 'v26.3.27'},
      ];
      expect(CoreUpdateService.parseLatestVersion(releases), '26.7.28');
    });

    test('skips non-version tags', () {
      final releases = [
        {'tag_name': 'config'},
        {'tag_name': 'v26.3.27'},
      ];
      expect(CoreUpdateService.parseLatestVersion(releases), '26.3.27');
    });

    test('returns null when nothing matches', () {
      expect(CoreUpdateService.parseLatestVersion(const []), isNull);
      expect(
        CoreUpdateService.parseLatestVersion(const [
          {'tag_name': 'foo'},
        ]),
        isNull,
      );
    });
  });
}
