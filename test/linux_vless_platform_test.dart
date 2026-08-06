import 'dart:convert';
import 'dart:io';

import 'package:affection_vpn/services/linux_vless_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _baseConfig = '''
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "tag": "socks-app",
      "listen": "127.0.0.1",
      "port": 10900,
      "protocol": "socks",
      "settings": {"auth": "noauth", "udp": true}
    }
  ],
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {}},
    {"tag": "direct", "protocol": "freedom", "settings": {}}
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = LinuxVlessPlatform();

  group('prepareRuntime', () {
    test('keeps existing socks-app inbound and injects http + api doors', () {
      final result = platform.prepareRuntime(_baseConfig, proxyOnly: false);
      final map = jsonDecode(result.config) as Map<String, dynamic>;
      final inbounds = (map['inbounds'] as List).cast<Map>();

      expect(result.socksPort, 10900);

      final tags = inbounds.map((e) => e['tag']).toSet();
      expect(tags, containsAll(['socks-app', 'http', 'api']));

      final http = inbounds.firstWhere((e) => e['tag'] == 'http');
      expect(http['listen'], '127.0.0.1');
      expect(http['protocol'], 'http');
      expect(result.httpPort, http['port']);

      final api = inbounds.firstWhere((e) => e['tag'] == 'api');
      expect(api['protocol'], 'dokodemo-door');
      expect(result.apiPort, api['port']);

      expect(map['api'], {'tag': 'api', 'services': ['StatsService']});
    });

    test('picks the first free ports when config already owns them', () {
      const config = '''
{
  "inbounds": [
    {"tag": "socks-app", "port": 10900, "protocol": "socks"},
    {"tag": "http", "port": 10809, "protocol": "http"},
    {"tag": "api", "port": 10807, "protocol": "dokodemo-door"}
  ],
  "outbounds": [{"tag": "direct", "protocol": "freedom", "settings": {}}]
}
''';
      final result = platform.prepareRuntime(config, proxyOnly: false);
      final map = jsonDecode(result.config) as Map<String, dynamic>;
      final inbounds = (map['inbounds'] as List).cast<Map>();

      // All three preferred ports are taken, so each new inbound steps up.
      final httpPorts = inbounds
          .where((e) => e['protocol'] == 'http')
          .map((e) => e['port'])
          .toSet();
      expect(result.httpPort, 10810);
      expect(httpPorts, {10809, 10810});

      expect(result.socksPort, 10900);
      // Reuses the existing api inbound instead of adding a second one.
      expect(result.apiPort, 10807);
      expect(inbounds.where((e) => e['tag'] == 'api'), hasLength(1));
    });

    test('adds a routing rule for the injected api door', () {
      const config = '''
{
  "inbounds": [
    {"tag": "in", "port": 10800, "protocol": "socks"}
  ],
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {}},
    {"tag": "direct", "protocol": "freedom", "settings": {}}
  ],
  "routing": {
    "rules": [
      {"type": "field", "inboundTag": ["in"], "outboundTag": "proxy"}
    ]
  }
}
''';
      final result = platform.prepareRuntime(config, proxyOnly: false);
      final map = jsonDecode(result.config) as Map<String, dynamic>;
      final routing = map['routing'] as Map<String, dynamic>;
      final rules = (routing['rules'] as List).cast<Map>();

      final apiRule = rules.firstWhere(
        (r) => ((r['inboundTag'] as List?) ?? const []).contains('api'),
      );
      expect(apiRule['outboundTag'], 'api');

      // dokodemo-door is inbound-only; no api outbound may be injected.
      final outbounds = (map['outbounds'] as List).cast<Map>();
      expect(outbounds.where((o) => o['tag'] == 'api'), isEmpty);
    });

    test('points log.access at the given path when access logging is enabled',
        () {
      final result = platform.prepareRuntime(
        _baseConfig,
        proxyOnly: false,
        accessLogPath: '/tmp/access.log',
      );
      final map = jsonDecode(result.config) as Map<String, dynamic>;
      final log = map['log'] as Map<String, dynamic>;
      expect(log['access'], '/tmp/access.log');
      expect(log['loglevel'], 'info');
    });

    test('leaves log untouched when no access log path is given', () {
      final result = platform.prepareRuntime(_baseConfig, proxyOnly: false);
      final map = jsonDecode(result.config) as Map<String, dynamic>;
      final log = map['log'] as Map<String, dynamic>;
      expect(log, {'loglevel': 'warning'});
    });
  });

  group('xray integration', () {
    late String testDataHome;
    setUpAll(() {
      testDataHome = Directory.systemTemp.createTempSync('affection-vpn-test').path;
      PathProviderPlatform.instance = PathProviderLinux.private(
        environment: {
          'XDG_DATA_HOME': testDataHome,
        },
      );
    });

    test('reports the installed core version', () async {
      await platform.initializeVless(
        onStatusChanged: (_) {},
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
        providerBundleIdentifier: 'dev.affection.affection_vpn',
        groupIdentifier: 'group.dev.affection.affection_vpn',
      );
      final version = await platform.getCoreVersion();
      if (version == 'xray not found') {
        markTestSkipped('xray binary is not installed');
        return;
      }
      expect(version, isNot('unknown'));
      expect(version.toLowerCase(), contains('xray'));
    });

    test('probes a local target through a spawned core', () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) {
        request.response.statusCode = HttpStatus.noContent;
        request.response.close();
      });
      addTearDown(() => server.close(force: true));

      const config = '''
{
  "log": {"loglevel": "warning"},
  "outbounds": [
    {"tag": "direct", "protocol": "freedom", "settings": {}}
  ]
}
''';
      final delay = await platform.getServerDelay(
        config: config,
        url: 'http://127.0.0.1:${server.port}/generate_204',
      );
      if (delay < 0) {
        markTestSkipped('xray binary is not installed');
        return;
      }
      expect(delay, greaterThan(0));
    });
  });
}
