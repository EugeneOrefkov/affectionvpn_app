// ignore_for_file: avoid_print
import 'dart:io';
import 'package:affection_vpn/models/server_config.dart';
import 'package:affection_vpn/services/linux_vless_platform.dart';
import 'package:affection_vpn/services/vpn_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const realCfg = '''
{
  "remarks": "Real Server",
  "inbounds": [],
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {"vnext": [{"address": "1.2.3.4", "port": 443, "users": [{"id": "00000000-0000-0000-0000-000000000000", "encryption": "none"}]}]}}
  ]
}
''';

const balCfg = '''
{
  "remarks": "Virtual Host",
  "routing": {
    "rules": [
      {"protocol": ["bittorrent"], "outboundTag": "direct"},
      {"network": "tcp,udp", "balancerTag": "Super_Balancer"}
    ],
    "balancers": [
      {
        "tag": "Super_Balancer",
        "selector": ["proxy"],
        "strategy": {"type": "leastLoad", "settings": {"maxRTT": "1s", "expected": 2, "baselines": ["1s"], "tolerance": 0.01}},
        "fallbackTag": "direct"
      }
    ],
    "domainMatcher": "hybrid",
    "domainStrategy": "IPIfNonMatch"
  },
  "inbounds": [
    {"tag": "socks", "port": 10808, "listen": "127.0.0.1", "protocol": "socks", "settings": {"udp": true, "auth": "noauth"}},
    {"tag": "http", "port": 10809, "listen": "127.0.0.1", "protocol": "http", "settings": {"allowTransparent": false}}
  ],
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {"vnext": [{"address": "1.2.3.4", "port": 443, "users": [{"id": "00000000-0000-0000-0000-000000000000", "encryption": "none"}]}]}},
    {"tag": "proxy-2", "protocol": "vless", "settings": {"vnext": [{"address": "5.6.7.8", "port": 443, "users": [{"id": "00000000-0000-0000-0000-000000000000", "encryption": "none"}]}]}},
    {"tag": "proxy-3", "protocol": "vless", "settings": {"vnext": [{"address": "9.9.9.9", "port": 443, "users": [{"id": "00000000-0000-0000-0000-000000000000", "encryption": "none"}]}]}},
    {"tag": "direct", "protocol": "freedom", "settings": {}},
    {"tag": "block", "protocol": "blackhole", "settings": {}}
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final testDataHome = Directory.systemTemp.createTempSync('affection-vpn-switch').path;
  PathProviderPlatform.instance = PathProviderLinux.private(environment: {
    'XDG_DATA_HOME': testDataHome,
  });

  test('switch real -> balancer auto-starts CONNECTED', () async {
    final statuses = <VlessStatus>[];
    final tunnel = LinuxVlessPlatform();
    await tunnel.initializeVless(
      onStatusChanged: statuses.add,
      notificationIconResourceType: 'mipmap',
      notificationIconResourceName: 'ic_launcher',
      providerBundleIdentifier: 'dev.affection.affection_vpn',
      groupIdentifier: 'group.dev.affection.affection_vpn',
    );

    Future<void> startServer(String raw) async {
      final s = ServerConfig.fromProfile(FlutterVless.parse(raw))!;
      var config = ServerConfig.prepareRuntimeConfig(s.config);
      config = VpnService.instance.buildInternalSocksConfig(config);
      await tunnel.startVless(
        remark: s.displayName,
        config: config,
        notificationDisconnectButtonName: 'Disconnect',
        proxyOnly: false,
      );
    }

    try {
      await startServer(realCfg);
      print('AFTER REAL: ${statuses.map((s) => s.state).toList()}');
      statuses.clear();
      await startServer(balCfg);
      print('AFTER BAL: ${statuses.map((s) => s.state).toList()}');
      await Future<void>.delayed(const Duration(seconds: 2));
      print('FINAL: ${statuses.map((s) => s.state).toList()}');
    } on Exception catch (e) {
      if (e.toString().contains('xray не найден')) {
        markTestSkipped('xray binary is not installed');
        return;
      }
      rethrow;
    } finally {
      await tunnel.stopVless();
    }
  });
}
