import 'package:affection_vpn/services/core_log_service.dart';
import 'package:affection_vpn/services/linux_vless_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoreLogService', () {
    tearDown(() {
      LinuxVlessPlatform.logs.clear();
    });

    test('reflects the linux platform core logs on Linux', () async {
      await CoreLogService.instance.init();
      expect(CoreLogService.instance.isEmpty, isTrue);

      LinuxVlessPlatform.logs.add('Xray 26.7.11 started');
      expect(CoreLogService.instance.logs, contains('Xray 26.7.11 started'));
      expect(CoreLogService.instance.logs.length, 1);
      expect(CoreLogService.instance.isEmpty, isFalse);
    });

    test('init is idempotent and safe to call repeatedly', () async {
      await CoreLogService.instance.init();
      await CoreLogService.instance.init();
      expect(CoreLogService.instance.isEmpty, isTrue);
    });
  });
}
