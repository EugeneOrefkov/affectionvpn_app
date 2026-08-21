import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:affection_vpn/services/linux_vless_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless_platform_interface/flutter_vless_platform_interface.dart';
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

    test('reuses an existing http inbound instead of adding a duplicate', () {
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

      // The config already owns an `http` inbound; its port is reused and no
      // second inbound with the same tag is injected, otherwise Xray aborts
      // startup with "existing tag found: http".
      expect(result.httpPort, 10809);
      expect(inbounds.where((e) => e['tag'] == 'http'), hasLength(1));

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

    test('creates a routing section and api rule when the config has none', () {
      const config = '''
{
  "inbounds": [
    {"tag": "in", "port": 10800, "protocol": "socks"}
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom", "settings": {}}
  ]
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
      // The api rule must come first so it wins over any catch-all rule.
      expect(rules.first, apiRule);
    });

    test('puts the api rule first so provider catch-all rules cannot hijack '
        'the stats door', () {
      const config = '''
{
  "inbounds": [
    {"tag": "in", "port": 10800, "protocol": "socks"}
  ],
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {}}
  ],
  "routing": {
    "rules": [
      {"type": "field", "network": "tcp,udp", "balancerTag": "Balancer"},
      {"type": "field", "inboundTag": ["in"], "outboundTag": "proxy"}
    ]
  }
}
''';
      final result = platform.prepareRuntime(config, proxyOnly: false);
      final map = jsonDecode(result.config) as Map<String, dynamic>;
      final rules = (map['routing']['rules'] as List).cast<Map>();

      // The catch-all `network: tcp,udp` rule (Remnawave load-balancer nodes)
      // matches every connection including the api door's; the api rule must
      // come first or the stats requests are tunnelled through the proxy.
      expect(rules.first['inboundTag'], ['api']);
      expect(rules.first['outboundTag'], 'api');
    });

    test('registers the stats counter manager and enables traffic counters '
        'even when the config has no policy section', () {
      final result = platform.prepareRuntime(_baseConfig, proxyOnly: false);
      final map = jsonDecode(result.config) as Map<String, dynamic>;

      // `api.services` only exposes the gRPC service; the top-level `stats`
      // section is what actually registers the counter manager in Xray.
      expect(map['stats'], isEmpty);

      final system = (map['policy'] as Map)['system'] as Map;
      expect(system['statsInboundUplink'], isTrue);
      expect(system['statsInboundDownlink'], isTrue);
      expect(system['statsOutboundUplink'], isTrue);
      expect(system['statsOutboundDownlink'], isTrue);
    });

    test('preserves an existing policy section while enabling traffic '
        'counters', () {
      const config = '''
{
  "inbounds": [
    {"tag": "socks-app", "port": 10900, "protocol": "socks"}
  ],
  "outbounds": [{"tag": "direct", "protocol": "freedom", "settings": {}}],
  "policy": {"levels": {"0": {"connIdle": 300}}}
}
''';
      final result = platform.prepareRuntime(config, proxyOnly: false);
      final map = jsonDecode(result.config) as Map<String, dynamic>;
      final policy = map['policy'] as Map<String, dynamic>;

      expect((policy['levels'] as Map)['0'], {'connIdle': 300});
      final system = policy['system'] as Map;
      expect(system['statsOutboundUplink'], isTrue);
      expect(system['statsOutboundDownlink'], isTrue);
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

    test('reports tunnel traffic through the stats api door', () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) {
        request.response.statusCode = HttpStatus.ok;
        request.response.add(List<int>.filled(1024, 0x41));
        request.response.close();
      });
      addTearDown(() => server.close(force: true));

      const config = '''
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {"tag": "socks-app", "listen": "127.0.0.1", "port": 10900, "protocol": "socks", "settings": {"auth": "noauth", "udp": true}}
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom", "settings": {}}
  ]
}
''';

      final statuses = <VlessStatus>[];
      final tunnel = LinuxVlessPlatform();
      await tunnel.initializeVless(
        onStatusChanged: statuses.add,
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
        providerBundleIdentifier: 'dev.affection.affection_vpn',
        groupIdentifier: 'group.dev.affection.affection_vpn',
      );
      try {
        await tunnel.startVless(
          remark: 'stats test',
          config: config,
          notificationDisconnectButtonName: 'Disconnect',
          proxyOnly: true,
        );
      } on Exception catch (e) {
        if (e.toString().contains('xray не найден')) {
          markTestSkipped('xray binary is not installed');
          return;
        }
        rethrow;
      }
      addTearDown(() => tunnel.stopVless());

      await _fetchThroughSocks(10900, server.port);

      // The core reports stats asynchronously; under CI load (parallel test
      // isolates, cold caches) the first report can lag several seconds.
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(deadline)) {
        final reported = statuses.where((s) => s.download > 0).toList();
        if (reported.isNotEmpty) {
          expect(reported.last.upload, greaterThan(0));
          expect(reported.last.download, greaterThan(0));
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      fail('no tunnel traffic reported within timeout; statuses: $statuses');
    });
  });
}

/// Pulls one HTTP response through a SOCKS5 no-auth proxy (the tunnel's own
/// socks-app inbound) so real bytes flow in both directions.
Future<void> _fetchThroughSocks(int socksPort, int targetPort) async {
  final socket = await Socket.connect('127.0.0.1', socksPort);
  final iterator = StreamIterator(socket);
  Future<List<int>> readN(int n) async {
    final builder = BytesBuilder();
    while (builder.length < n) {
      if (!await iterator.moveNext().timeout(const Duration(seconds: 5))) {
        throw StateError('socket closed while reading $n bytes');
      }
      builder.add(iterator.current);
    }
    return builder.takeBytes();
  }

  try {
    socket.add([0x05, 0x01, 0x00]); // greeting, no-auth
    await socket.flush();
    await readN(2);
    socket.add([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, targetPort >> 8, targetPort & 0xff]);
    await socket.flush();
    await readN(10); // CONNECT reply
    socket.add(utf8.encode('GET /stats HTTP/1.0\r\n\r\n'));
    await socket.flush();
    var total = 0;
    while (total < 8192) {
      if (!await iterator.moveNext().timeout(const Duration(seconds: 3))) {
        break;
      }
      total += iterator.current.length;
    }
    expect(total, greaterThan(0));
  } finally {
    socket.destroy();
  }
}
