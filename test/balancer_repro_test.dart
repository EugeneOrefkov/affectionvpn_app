import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:affection_vpn/models/server_config.dart';
import 'package:affection_vpn/services/linux_vless_platform.dart';
import 'package:affection_vpn/services/vpn_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:flutter_vless_platform_interface/flutter_vless_platform_interface.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _balancerNoObsJson = '''
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
    {"tag": "proxy", "protocol": "freedom", "settings": {}},
    {"tag": "proxy-2", "protocol": "freedom", "settings": {}},
    {"tag": "proxy-3", "protocol": "freedom", "settings": {}},
    {"tag": "direct", "protocol": "freedom", "settings": {}},
    {"tag": "block", "protocol": "blackhole", "settings": {}}
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final testDataHome = Directory.systemTemp.createTempSync('affection-vpn-test6').path;
  PathProviderPlatform.instance = PathProviderLinux.private(environment: {
    'XDG_DATA_HOME': testDataHome,
  });

  test('balancer without existing observatory starts via startVless', () async {
    final statuses = <VlessStatus>[];
    final tunnel = LinuxVlessPlatform();
    await tunnel.initializeVless(
      onStatusChanged: statuses.add,
      notificationIconResourceType: 'mipmap',
      notificationIconResourceName: 'ic_launcher',
      providerBundleIdentifier: 'dev.affection.affection_vpn',
      groupIdentifier: 'group.dev.affection.affection_vpn',
    );

    final balancer = ServerConfig.fromProfile(FlutterVless.parse(_balancerNoObsJson))!;
    var config = ServerConfig.prepareRuntimeConfig(balancer.config);
    config = VpnService.instance.buildInternalSocksConfig(config);
    try {
      await tunnel.startVless(
        remark: balancer.displayName,
        config: config,
        notificationDisconnectButtonName: 'Disconnect',
        proxyOnly: false,
      );
    } on Exception catch (e) {
      if (e.toString().contains('xray не найден')) {
        markTestSkipped('xray binary is not installed');
        return;
      }
      rethrow;
    }
    addTearDown(() => tunnel.stopVless());
    final states = statuses.map((s) => s.state).toList();
    print('STATES: $states');
    expect(states, contains('CONNECTED'));
  });
}
