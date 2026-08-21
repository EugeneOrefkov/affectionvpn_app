// ignore_for_file: avoid_print
import 'dart:io';
import 'package:affection_vpn/models/server_config.dart';
import 'package:affection_vpn/services/linux_vless_platform.dart';
import 'package:affection_vpn/services/vpn_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const cfg = '''
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
  final testDataHome = Directory.systemTemp.createTempSync('affection-vpn-runtime').path;
  PathProviderPlatform.instance = PathProviderLinux.private(environment: {
    'XDG_DATA_HOME': testDataHome,
  });

  test('runtime config generation', () {
    final balancer = ServerConfig.fromProfile(FlutterVless.parse(cfg))!;
    var config = ServerConfig.prepareRuntimeConfig(balancer.config);
    config = VpnService.instance.buildInternalSocksConfig(config);
    final prepared = LinuxVlessPlatform().prepareRuntime(config, proxyOnly: false);
    print('===== RUNTIME CONFIG =====');
    print(prepared.config);
    print('==========================');
  });
}
