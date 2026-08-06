import 'package:affection_vpn/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final hwidRegex = RegExp(r'^[a-zA-Z0-9=-]{10,64}$');

  test('generateDeviceId matches Remnawave HWID format', () {
    for (var i = 0; i < 20; i++) {
      final id = StorageService.generateDeviceId();
      expect(id, hasLength(32));
      expect(hwidRegex.hasMatch(id), isTrue,
          reason: 'invalid HWID charset: $id');
    }
  });

  test('generateDeviceId accepts custom length within limits', () {
    expect(StorageService.generateDeviceId(length: 10), hasLength(10));
    expect(StorageService.generateDeviceId(length: 64), hasLength(64));
  });

  test('getOrCreateDeviceId persists a single id', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService.instance;
    await storage.init();

    final first = await storage.getOrCreateDeviceId();
    final second = await storage.getOrCreateDeviceId();

    expect(first, second);
    expect(storage.deviceId, first);
    expect(hwidRegex.hasMatch(first), isTrue);
  });

  test('ping method defaults to HTTP GET', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService.instance;
    await storage.init();

    expect(storage.pingMethod, 'get');

    await storage.setPingMethod('get');
    expect(storage.pingMethod, 'get');
  });

  test('showIp defaults to visible and toggles off', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService.instance;
    await storage.init();

    expect(storage.showIp, isTrue);

    await storage.setShowIp(false);
    expect(storage.showIp, isFalse);
  });

  test('request logging is disabled by default and toggles on', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService.instance;
    await storage.init();

    expect(storage.requestLogEnabled, isFalse);

    await storage.setRequestLogEnabled(true);
    expect(storage.requestLogEnabled, isTrue);
  });
}
