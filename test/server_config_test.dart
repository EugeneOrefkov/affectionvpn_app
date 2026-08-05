import 'dart:convert';

import 'package:affection_vpn/models/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless/flutter_vless.dart';

const _balancerJson = '''
{
  "remarks": "🇩🇪 DE LoadBalancer",
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "tag": "in_proxy",
      "listen": "127.0.0.1",
      "port": 10807,
      "protocol": "socks",
      "settings": {"auth": "noauth", "udp": true}
    }
  ],
  "outbounds": [
    {
      "tag": "out_1",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "1.2.3.4",
            "port": 443,
            "users": [
              {
                "id": "11111111-2222-3333-4444-555555555555",
                "encryption": "none",
                "flow": "",
                "level": 8
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "example.com",
          "fingerprint": "chrome",
          "publicKey": "abcd",
          "shortId": "ef12",
          "spiderX": ""
        }
      }
    },
    {
      "tag": "out_2",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "5.6.7.8",
            "port": 8443,
            "users": [
              {
                "id": "11111111-2222-3333-4444-555555555555",
                "encryption": "none",
                "flow": "",
                "level": 8
              }
            ]
          }
        ]
      },
      "streamSettings": {"network": "tcp", "security": "none"}
    },
    {"tag": "direct", "protocol": "freedom", "settings": {}},
    {"tag": "block", "protocol": "blackhole", "settings": {}}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type": "field", "inboundTag": ["in_proxy"], "balancerTag": "lb"},
      {"type": "field", "ip": ["geoip:private"], "outboundTag": "direct"}
    ],
    "balancers": [
      {
        "tag": "lb",
        "selector": ["out_1", "out_2"],
        "strategy": {"type": "random"}
      }
    ]
  }
}
''';

void main() {
  group('ServerConfig.fromProfile', () {
    test('keeps Xray JSON balancer config with routing.balancers', () {
      final profile = FlutterVless.parse(_balancerJson);
      final server = ServerConfig.fromProfile(profile);

      expect(server, isNotNull);
      expect(server!.remark, '🇩🇪 DE LoadBalancer');
      expect(server.address, '1.2.3.4');
      expect(server.port, 443);
      expect(server.protocol, 'vless');
      expect(server.config, contains('"balancers"'));

      final config = jsonDecode(server.config) as Map<String, dynamic>;
      final routing = config['routing'] as Map<String, dynamic>;
      final balancers = routing['balancers'] as List<dynamic>;
      expect(balancers, hasLength(1));
      expect((balancers.first as Map)['tag'], 'lb');
    });

    test('parses share link the same way as fromLink', () {
      const link =
          'vless://11111111-2222-3333-4444-555555555555@example.com:443'
          '?security=reality&encryption=none&fp=chrome'
          '&pbk=abcd&sid=ef12&sni=example.com&type=tcp#MyServer';

      final server = ServerConfig.fromProfile(FlutterVless.parseFromURL(link));

      expect(server, isNotNull);
      expect(server!.remark, 'MyServer');
      expect(server.address, 'example.com');
      expect(server.port, 443);
      expect(server.protocol, 'vless');
    });

    test('fromLink still works for share links', () {
      const link =
          'vless://11111111-2222-3333-4444-555555555555@example.com:443'
          '?type=tcp#Legacy';
      final server = ServerConfig.fromLink(link);
      expect(server, isNotNull);
      expect(server!.remark, 'Legacy');
    });
  });

  test('parseMany decodes base64 JSON array from Remnawave', () {
    const simpleJson = '''
{
  "remarks": "🇺🇸 US Node",
  "log": {"loglevel": "error"},
  "inbounds": [
    {
      "tag": "in_proxy",
      "listen": "127.0.0.1",
      "port": 10807,
      "protocol": "socks",
      "settings": {"auth": "noauth", "udp": true}
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "9.9.9.9",
            "port": 8443,
            "users": [
              {
                "id": "11111111-2222-3333-4444-555555555555",
                "encryption": "none",
                "flow": "",
                "level": 8
              }
            ]
          }
        ]
      },
      "streamSettings": {"network": "tcp", "security": "none"}
    },
    {"tag": "direct", "protocol": "freedom", "settings": {}},
    {"tag": "block", "protocol": "blackhole", "settings": {}}
  ]
}
''';
    final jsonArray = '[$simpleJson,$_balancerJson]';
    final payload = base64Encode(utf8.encode(jsonArray));

    final profiles = FlutterVless.parseMany(payload);

    expect(profiles, hasLength(2));

    final servers = profiles
        .map(ServerConfig.fromProfile)
        .whereType<ServerConfig>()
        .toList();
    expect(servers, hasLength(2));
    expect(servers[0].remark, '🇺🇸 US Node');
    expect(servers[0].address, '9.9.9.9');
    expect(servers[0].port, 8443);
    expect(servers[1].remark, '🇩🇪 DE LoadBalancer');
    expect(servers[1].config, contains('"balancers"'));
  });

  group('prepareRuntimeConfig', () {
    test('routes injected socks/http inbounds through the balancer', () {
      const config = '''
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {"tag": "in_proxy", "listen": "127.0.0.1", "port": 10807, "protocol": "socks"}
  ],
  "outbounds": [
    {"tag": "out_1", "protocol": "vless", "settings": {}},
    {"tag": "out_2", "protocol": "vless", "settings": {}},
    {"tag": "direct", "protocol": "freedom", "settings": {}}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type": "field", "inboundTag": ["in_proxy"], "balancerTag": "lb"},
      {"type": "field", "ip": ["geoip:private"], "outboundTag": "direct"}
    ],
    "balancers": [
      {"tag": "lb", "selector": ["out_1", "out_2"], "strategy": {"type": "random"}}
    ]
  }
}
''';

      final result = ServerConfig.prepareRuntimeConfig(config);
      final map = jsonDecode(result) as Map<String, dynamic>;
      final routing = map['routing'] as Map<String, dynamic>;
      final rules = (routing['rules'] as List).cast<Map>();

      final socksRule = rules.firstWhere(
        (r) => ((r['inboundTag'] as List?) ?? const []).contains('socks'),
      );
      expect(socksRule['balancerTag'], 'lb');
      final httpRule = rules.firstWhere(
        (r) => ((r['inboundTag'] as List?) ?? const []).contains('http'),
      );
      expect(httpRule['balancerTag'], 'lb');

      final lbRules = rules
          .where((r) => r['balancerTag'] == 'lb')
          .map((r) => r['inboundTag'])
          .expand((e) => (e as List?) ?? const [])
          .toSet();
      expect(lbRules, containsAll(['in_proxy', 'socks', 'http', 'socks-auth']));
      expect(rules.length, 5);
    });

    test('leaves non-balancer configs untouched', () {
      const config = '''
{
  "inbounds": [{"tag": "in", "port": 10807, "protocol": "socks"}],
  "outbounds": [{"tag": "proxy", "protocol": "vless", "settings": {}}],
  "routing": {"rules": [{"type": "field", "inboundTag": ["in"], "outboundTag": "proxy"}]}
}
''';
      expect(ServerConfig.prepareRuntimeConfig(config), config);
    });

    test('handles malformed JSON gracefully', () {
      expect(ServerConfig.prepareRuntimeConfig('not json'), 'not json');
    });
  });
}
