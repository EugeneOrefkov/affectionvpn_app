import 'dart:convert';

import 'package:affection_vpn/services/vpn_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe URL is HTTPS (cleartext is blocked on Android)', () {
    expect(VpnService.probeUrl, startsWith('https://'));
  });

  test('buildAuthProxyConfig adds authenticated SOCKS5 inbound', () {
    const baseConfig =
        '{"inbounds":[{"tag":"in","port":10807,"protocol":"socks"}],'
        '"outbounds":[{"tag":"proxy","protocol":"freedom","settings":{}}]}';

    final result = VpnService.instance
        .buildAuthProxyConfig(baseConfig, 'affection', 'secret123');

    final map = jsonDecode(result) as Map<String, dynamic>;
    final inbounds = (map['inbounds'] as List).cast<Map<String, dynamic>>();
    final auth = inbounds.lastWhere((e) => e['tag'] == 'socks-auth');

    expect(auth['listen'], '0.0.0.0');
    expect(auth['port'], VpnService.proxyPort);
    expect(auth['protocol'], 'socks');
    final settings = auth['settings'] as Map<String, dynamic>;
    expect(settings['auth'], 'password');
    final accounts = (settings['accounts'] as List).cast<Map>();
    expect(accounts.first['user'], 'affection');
    expect(accounts.first['pass'], 'secret123');
  });

  test('buildAuthProxyConfig picks a free port', () {
    const baseConfig =
        '{"inbounds":[{"port":10810,"protocol":"socks"}],"outbounds":[]}';

    final result =
        VpnService.instance.buildAuthProxyConfig(baseConfig, 'u', 'p');

    final map = jsonDecode(result) as Map<String, dynamic>;
    final inbounds = (map['inbounds'] as List).cast<Map<String, dynamic>>();
    final auth = inbounds.lastWhere((e) => e['tag'] == 'socks-auth');
    expect(auth['port'], 10811);
  });

  test('buildAuthProxyConfig points the core access log for the request log', () {
    const baseConfig = '{"inbounds":[],"outbounds":[]}';

    final result =
        VpnService.instance.buildAuthProxyConfig(baseConfig, 'u', 'p');

    final map = jsonDecode(result) as Map<String, dynamic>;
    final log = map['log'] as Map<String, dynamic>;
    expect(log['access'], isNotEmpty);
    expect(log['loglevel'], 'info');
  });

  test('buildAuthProxyConfig adds authenticated HTTP inbound for the app', () {
    const baseConfig = '{"inbounds":[],"outbounds":[]}';

    final result =
        VpnService.instance.buildAuthProxyConfig(baseConfig, 'u', 'p');

    final map = jsonDecode(result) as Map<String, dynamic>;
    final inbounds = (map['inbounds'] as List).cast<Map<String, dynamic>>();
    final http = inbounds.lastWhere((e) => e['tag'] == 'http-auth');

    expect(http['listen'], '127.0.0.1');
    expect(http['port'], VpnService.authHttpPort);
    expect(http['protocol'], 'http');
    final accounts =
        ((http['settings'] as Map)['accounts'] as List).cast<Map>();
    expect(accounts.first['user'], 'u');
    expect(accounts.first['pass'], 'p');
    expect(VpnService.instance.lastAuthHttpPort, VpnService.authHttpPort);
  });

  test('buildAuthProxyConfig picks a free HTTP port', () {
    const baseConfig = '{"inbounds":[{"port":10811,"protocol":"http"}],"outbounds":[]}';

    final result =
        VpnService.instance.buildAuthProxyConfig(baseConfig, 'u', 'p');

    final map = jsonDecode(result) as Map<String, dynamic>;
    final inbounds = (map['inbounds'] as List).cast<Map<String, dynamic>>();
    final http = inbounds.lastWhere((e) => e['tag'] == 'http-auth');
    expect(http['port'], 10812);
  });

  test('buildNoAuthProxyConfig adds no-auth SOCKS5 inbound', () {
    const baseConfig =
        '{"inbounds":[{"tag":"in","port":10807,"protocol":"socks"}],'
        '"outbounds":[{"tag":"proxy","protocol":"freedom","settings":{}}]}';

    final result = VpnService.instance.buildNoAuthProxyConfig(baseConfig);

    final map = jsonDecode(result) as Map<String, dynamic>;
    final inbounds = (map['inbounds'] as List).cast<Map<String, dynamic>>();
    final socks = inbounds.lastWhere((e) => e['tag'] == 'socks-auth');

    expect(socks['listen'], '0.0.0.0');
    expect(socks['port'], VpnService.proxyPort);
    expect(socks['protocol'], 'socks');
    final settings = socks['settings'] as Map<String, dynamic>;
    expect(settings['auth'], 'noauth');
    expect(settings.containsKey('accounts'), isFalse);
  });

  test('buildNoAuthProxyConfig adds no-auth HTTP inbound', () {
    const baseConfig = '{"inbounds":[],"outbounds":[]}';

    final result = VpnService.instance.buildNoAuthProxyConfig(baseConfig);

    final map = jsonDecode(result) as Map<String, dynamic>;
    final inbounds = (map['inbounds'] as List).cast<Map<String, dynamic>>();
    final http = inbounds.lastWhere((e) => e['tag'] == 'http-auth');

    expect(http['listen'], '127.0.0.1');
    expect(http['port'], VpnService.authHttpPort);
    expect(http['protocol'], 'http');
    expect(http.containsKey('settings'), isFalse);
  });

  test('buildNoAuthProxyConfig picks free ports avoiding collisions', () {
    const baseConfig =
        '{"inbounds":[{"port":10810,"protocol":"socks"},{"port":10811,"protocol":"http"}],"outbounds":[]}';

    final result = VpnService.instance.buildNoAuthProxyConfig(baseConfig);

    final map = jsonDecode(result) as Map<String, dynamic>;
    final inbounds = (map['inbounds'] as List).cast<Map<String, dynamic>>();
    final socks = inbounds.lastWhere((e) => e['tag'] == 'socks-auth');
    final http = inbounds.lastWhere((e) => e['tag'] == 'http-auth');

    expect(socks['port'], 10812);
    expect(http['port'], 10813);
  });

  test('buildInternalSocksConfig points the core access log for the request log',
      () {
    const baseConfig = '{"inbounds":[],"outbounds":[]}';

    final result = VpnService.instance.buildInternalSocksConfig(baseConfig);

    final map = jsonDecode(result) as Map<String, dynamic>;
    final log = map['log'] as Map<String, dynamic>;
    expect(log['access'], isNotEmpty);
    expect(log['loglevel'], 'info');
  });

  test('buildInternalSocksConfig overrides a none loglevel config', () {
    const baseConfig =
        '{"log":{"access":"","loglevel":"none"},"inbounds":[],"outbounds":[]}';

    final result = VpnService.instance.buildInternalSocksConfig(baseConfig);

    final map = jsonDecode(result) as Map<String, dynamic>;
    final log = map['log'] as Map<String, dynamic>;
    expect(log['access'], isNotEmpty);
    expect(log['loglevel'], 'info');
  });

  test('buildInternalSocksConfig adds a no-auth HTTP inbound for the app', () {
    const baseConfig = '{"inbounds":[],"outbounds":[]}';

    final result = VpnService.instance.buildInternalSocksConfig(baseConfig);

    final map = jsonDecode(result) as Map<String, dynamic>;
    final inbounds = (map['inbounds'] as List).cast<Map<String, dynamic>>();
    final http = inbounds.lastWhere((e) => e['tag'] == 'http-app');

    expect(http['listen'], '127.0.0.1');
    expect(http['port'], VpnService.internalHttpPort);
    expect(http['protocol'], 'http');
    expect(VpnService.instance.lastInternalHttpPort, VpnService.internalHttpPort);
  });

  test('buildInternalSocksConfig picks free ports avoiding collisions', () {
    const baseConfig =
        '{"inbounds":[{"tag":"x","port":10900,"protocol":"socks"}],"outbounds":[]}';

    final result = VpnService.instance.buildInternalSocksConfig(baseConfig);

    final map = jsonDecode(result) as Map<String, dynamic>;
    final inbounds = (map['inbounds'] as List).cast<Map<String, dynamic>>();
    final socks = inbounds.lastWhere((e) => e['tag'] == 'socks-app');
    final http = inbounds.lastWhere((e) => e['tag'] == 'http-app');

    expect(socks['port'], 10901);
    expect(http['port'], 10902);
  });
}
