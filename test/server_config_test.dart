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

    test('extracts address and port from flat VLESS JSON settings', () {
      const flatJson = '''
{
  "remarks": "Universal Node",
  "log": {"loglevel": "error"},
  "inbounds": [],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "address": "universal.example.com",
        "port": 8443,
        "id": "11111111-2222-3333-4444-555555555555",
        "encryption": "none",
        "flow": ""
      },
      "streamSettings": {"network": "tcp", "security": "none"}
    },
    {"tag": "direct", "protocol": "freedom", "settings": {}},
    {"tag": "block", "protocol": "blackhole", "settings": {}}
  ]
}
''';

      final server = ServerConfig.fromProfile(FlutterVless.parse(flatJson));

      expect(server, isNotNull);
      expect(server!.remark, 'Universal Node');
      expect(server.address, 'universal.example.com');
      expect(server.port, 8443);
      expect(server.protocol, 'vless');
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
    test('handles Remnawave injectHosts final config end-to-end', () {
      const config = '''
{
  "remarks": "Virtual Host",
  "dns": {"servers": ["1.1.1.1", "1.0.0.1"], "queryStrategy": "UseIP"},
  "routing": {
    "rules": [
      {"protocol": ["bittorrent"], "outboundTag": "direct"},
      {"network": "tcp,udp", "balancerTag": "Super_Balancer"}
    ],
    "balancers": [
      {
        "tag": "Super_Balancer",
        "selector": ["proxy"],
        "strategy": {
          "type": "leastLoad",
          "settings": {"maxRTT": "1s", "expected": 2, "baselines": ["1s"], "tolerance": 0.01}
        },
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
    {"tag": "proxy", "protocol": "vless", "settings": {"vnext": [{"address": "1.2.3.4", "port": 443, "users": [{"id": "11111111-2222-3333-4444-555555555555", "encryption": "none"}]}]}},
    {"tag": "proxy-2", "protocol": "vless", "settings": {"vnext": [{"address": "5.6.7.8", "port": 443, "users": [{"id": "11111111-2222-3333-4444-555555555555", "encryption": "none"}]}]}},
    {"tag": "proxy-3", "protocol": "vless", "settings": {"vnext": [{"address": "9.9.9.9", "port": 443, "users": [{"id": "11111111-2222-3333-4444-555555555555", "encryption": "none"}]}]}},
    {"tag": "direct", "protocol": "freedom", "settings": {}},
    {"tag": "block", "protocol": "blackhole", "settings": {}}
  ],
  "burstObservatory": {
    "pingConfig": {
      "timeout": "3s",
      "interval": "1m",
      "sampling": 1,
      "destination": "http://www.gstatic.com/generate_204",
      "connectivity": ""
    },
    "subjectSelector": ["proxy"]
  }
}
''';

      final profiles = FlutterVless.parseMany(config);
      final server = ServerConfig.fromProfile(profiles.single);

      expect(server, isNotNull);
      expect(server!.remark, 'Virtual Host');
      expect(server.address, '1.2.3.4');
      expect(server.port, 443);
      expect(server.config, contains('"balancers"'));

      final runtime = ServerConfig.prepareRuntimeConfig(server.config);
      final map = jsonDecode(runtime) as Map<String, dynamic>;
      final routing = map['routing'] as Map<String, dynamic>;
      final rules = (routing['rules'] as List).cast<Map>();

      // Plugin injects socks_1/http_1 (config already owns socks/http tags).
      for (final tag in ['socks', 'http', 'socks_1', 'http_1', 'socks-auth']) {
        final rule = rules.firstWhere(
          (r) => ((r['inboundTag'] as List?) ?? const []).contains(tag),
        );
        expect(rule['balancerTag'], 'Super_Balancer');
      }
      // The injectHosts outbounds keep prefix-matched by the balancer selector.
      final balancer = (routing['balancers'] as List).cast<Map>().first;
      expect(balancer['selector'], ['proxy']);
      expect(map['burstObservatory'], isA<Map>());
    });

    test('points burst observatory at a reliable probe URL', () {
      const config = '''
{
  "inbounds": [
    {"tag": "socks", "listen": "127.0.0.1", "port": 10808, "protocol": "socks"},
    {"tag": "http", "listen": "127.0.0.1", "port": 10809, "protocol": "http"}
  ],
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {}},
    {"tag": "proxy-2", "protocol": "vless", "settings": {}},
    {"tag": "direct", "protocol": "freedom", "settings": {}}
  ],
  "routing": {
    "balancers": [
      {
        "tag": "Super_Balancer",
        "selector": ["proxy"],
        "strategy": {"type": "leastLoad", "settings": {}}
      }
    ],
    "rules": []
  },
  "burstObservatory": {
    "pingConfig": {
      "timeout": "3s",
      "interval": "1m",
      "sampling": 1,
      "destination": "http://www.gstatic.com/generate_204",
      "connectivity": ""
    },
    "subjectSelector": ["proxy"]
  }
}
''';

      final result = ServerConfig.prepareRuntimeConfig(config);
      final map = jsonDecode(result) as Map<String, dynamic>;
      final pingConfig =
          (map['burstObservatory'] as Map)['pingConfig'] as Map;
      expect(pingConfig['destination'], ServerConfig.observatoryProbeUrl);
      expect(pingConfig['probeType'], 'tcp');
      expect(pingConfig['interval'], '30s');
      expect(pingConfig['timeout'], '1s');
    });

    test('adds a burst observatory for leastLoad balancers without one', () {
      const config = '''
{
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {}},
    {"tag": "proxy-2", "protocol": "vless", "settings": {}},
    {"tag": "direct", "protocol": "freedom", "settings": {}}
  ],
  "routing": {
    "balancers": [
      {"tag": "lb", "selector": ["proxy"], "strategy": {"type": "leastLoad"}}
    ],
    "rules": []
  }
}
''';

      final result = ServerConfig.prepareRuntimeConfig(config);
      final map = jsonDecode(result) as Map<String, dynamic>;
      final observatory = map['burstObservatory'] as Map;
      final pingConfig = observatory['pingConfig'] as Map;
      expect(pingConfig['destination'], ServerConfig.observatoryProbeUrl);
      expect(observatory['subjectSelector'], ['proxy']);
    });

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

    test('routes plugin-injected socks_1/http_1 inbounds through the balancer',
        () {
      const config = '''
{
  "inbounds": [
    {"tag": "socks", "listen": "127.0.0.1", "port": 10808, "protocol": "socks"},
    {"tag": "http", "listen": "127.0.0.1", "port": 10809, "protocol": "http"}
  ],
  "outbounds": [
    {"tag": "out_1", "protocol": "vless", "settings": {}},
    {"tag": "out_2", "protocol": "vless", "settings": {}},
    {"tag": "direct", "protocol": "freedom", "settings": {}}
  ],
  "routing": {
    "rules": [
      {"type": "field", "inboundTag": ["socks"], "balancerTag": "lb"},
      {"type": "field", "inboundTag": ["http"], "balancerTag": "lb"}
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

      for (final tag in ['socks_1', 'http_1']) {
        final rule = rules.firstWhere(
          (r) => ((r['inboundTag'] as List?) ?? const []).contains(tag),
        );
        expect(rule['balancerTag'], 'lb');
      }
    });

    test('routes plugin-injected tags regardless of collision count', () {
      const config = '''
{
  "inbounds": [
    {"tag": "socks", "listen": "127.0.0.1", "port": 10801, "protocol": "socks"},
    {"tag": "socks_1", "listen": "127.0.0.1", "port": 10802, "protocol": "socks"},
    {"tag": "socks_2", "listen": "127.0.0.1", "port": 10803, "protocol": "socks"},
    {"tag": "http", "listen": "127.0.0.1", "port": 10804, "protocol": "http"},
    {"tag": "http_1", "listen": "127.0.0.1", "port": 10805, "protocol": "http"},
    {"tag": "http_2", "listen": "127.0.0.1", "port": 10806, "protocol": "http"},
    {"tag": "http_3", "listen": "127.0.0.1", "port": 10807, "protocol": "http"},
    {"tag": "http_4", "listen": "127.0.0.1", "port": 10808, "protocol": "http"}
  ],
  "outbounds": [
    {"tag": "out_1", "protocol": "vless", "settings": {}},
    {"tag": "out_2", "protocol": "vless", "settings": {}},
    {"tag": "direct", "protocol": "freedom", "settings": {}}
  ],
  "routing": {
    "rules": [
      {"type": "field", "inboundTag": ["socks"], "balancerTag": "lb"},
      {"type": "field", "inboundTag": ["http"], "balancerTag": "lb"}
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

      // Plugin picks the first free tag: socks_3 and http_5 here.
      for (final tag in ['socks_3', 'http_5']) {
        final rule = rules.firstWhere(
          (r) => ((r['inboundTag'] as List?) ?? const []).contains(tag),
        );
        expect(rule['balancerTag'], 'lb');
      }
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

  group('injectBypassRules', () {
    test('returns config unchanged when cidrs is empty', () {
      const config = '{"inbounds":[],"outbounds":[],"routing":{"rules":[]}}';
      expect(ServerConfig.injectBypassRules(config, []), config);
    });

    test('injects bypass rule at position 0', () {
      const config =
          '{"inbounds":[],"outbounds":[{"tag":"direct","protocol":"freedom","settings":{}}],"routing":{"rules":[{"type":"field","inboundTag":["in"],"outboundTag":"proxy"}]}}';

      final result =
          ServerConfig.injectBypassRules(config, ['192.168.0.0/16']);
      final map = jsonDecode(result) as Map<String, dynamic>;
      final rules =
          (map['routing']['rules'] as List).cast<Map<String, dynamic>>();

      expect(rules.first['type'], 'field');
      expect(rules.first['ip'], ['192.168.0.0/16']);
      expect(rules.first['outboundTag'], 'direct');
      expect(rules.first['_appBypass'], true);
    });

    test('ensures freedom outbound exists', () {
      const config =
          '{"inbounds":[],"outbounds":[{"tag":"proxy","protocol":"vless","settings":{}}],"routing":{"rules":[]}}';

      final result =
          ServerConfig.injectBypassRules(config, ['10.0.0.0/8']);
      final map = jsonDecode(result) as Map<String, dynamic>;
      final outbounds =
          (map['outbounds'] as List).cast<Map<String, dynamic>>();

      final direct = outbounds.firstWhere((o) => o['tag'] == 'direct');
      expect(direct['protocol'], 'freedom');
    });

    test('creates routing section if missing', () {
      const config = '{"inbounds":[],"outbounds":[]}';

      final result =
          ServerConfig.injectBypassRules(config, ['172.16.0.0/12']);
      final map = jsonDecode(result) as Map<String, dynamic>;
      final rules =
          (map['routing']['rules'] as List).cast<Map<String, dynamic>>();

      expect(rules.first['ip'], ['172.16.0.0/12']);
    });

    test('handles malformed JSON gracefully', () {
      expect(ServerConfig.injectBypassRules('not json', ['10.0.0.0/8']),
          'not json');
    });

    test('deduplicates previous bypass rules', () {
      const config =
          '{"inbounds":[],"outbounds":[{"tag":"direct","protocol":"freedom","settings":{}}],'
          '"routing":{"rules":[{"_appBypass":true,"type":"field","ip":["1.1.1.0/24"],"outboundTag":"direct"}]}}';

      final result =
          ServerConfig.injectBypassRules(config, ['10.0.0.0/8']);
      final map = jsonDecode(result) as Map<String, dynamic>;
      final rules =
          (map['routing']['rules'] as List).cast<Map<String, dynamic>>();

      // Old rule removed, new rule added
      expect(rules.length, 1);
      expect(rules.first['ip'], ['10.0.0.0/8']);
    });
  });
}
