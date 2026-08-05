import 'dart:convert';

import 'package:affection_vpn/services/vpn_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
