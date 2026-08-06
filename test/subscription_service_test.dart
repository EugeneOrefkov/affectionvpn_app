import 'package:affection_vpn/services/subscription_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _balancerJsonArray = '''
[
  {
    "remarks": "DE LoadBalancer",
    "outbounds": [
      {
        "tag": "proxy",
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
                  "flow": ""
                }
              ]
            }
          ]
        },
        "streamSettings": {"network": "tcp", "security": "none"}
      },
      {"tag": "direct", "protocol": "freedom"},
      {"tag": "block", "protocol": "blackhole"}
    ],
    "routing": {
      "balancers": [{"tag": "lb", "selector": ["proxy"]}]
    }
  }
]
''';

const _plainLink =
    'vless://11111111-2222-3333-4444-555555555555@example.com:443'
    '?security=reality&encryption=none&fp=chrome'
    '&pbk=abcd&sid=ef12&sni=example.com&type=tcp#MyServer';

void main() {
  test('hwidHeaders sends X-Hwid, platform, OS version and model', () {
    final headers = SubscriptionService.hwidHeaders(
      'aBc123-4567',
      osVersion: '14',
      deviceModel: 'Pixel 8',
    );

    expect(headers['X-Hwid'], 'aBc123-4567');
    expect(headers.containsKey('X-Device-Os'), isTrue);
    expect(headers['X-Device-Os'], isNotEmpty);
    expect(headers['X-Ver-Os'], '14');
    expect(headers['X-Device-Model'], 'Pixel 8');
  });

  test('hwidHeaders omits OS version and model when not provided', () {
    final headers = SubscriptionService.hwidHeaders('aBc123-4567');

    expect(headers.containsKey('X-Ver-Os'), isFalse);
    expect(headers.containsKey('X-Device-Model'), isFalse);
  });

  group('SubscriptionService.fetch', () {
    test('requests the XRAY_JSON /json variant first and uses it', () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.path);
        return http.Response(
          _balancerJsonArray,
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = SubscriptionService(client: client);
      final result = await service.fetch('https://panel.example/sub/abc123');

      expect(requested, ['/sub/abc123/json']);
      expect(result.servers, hasLength(1));
      expect(result.servers.first.remark, 'DE LoadBalancer');
      expect(result.servers.first.address, '1.2.3.4');
      expect(result.servers.first.config, contains('"balancers"'));
    });

    test('falls back to the plain format when /json returns empty', () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.path);
        if (request.url.path.endsWith('/json')) {
          return http.Response('[]', 200);
        }
        return http.Response(_plainLink, 200);
      });

      final service = SubscriptionService(client: client);
      final result = await service.fetch('https://panel.example/sub/abc123');

      expect(requested, ['/sub/abc123/json', '/sub/abc123']);
      expect(result.servers, hasLength(1));
      expect(result.servers.first.remark, 'MyServer');
    });

    test('falls back to the plain format when /json responds with an error',
        () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.path);
        if (request.url.path.endsWith('/json')) {
          return http.Response('not found', 404);
        }
        return http.Response(_plainLink, 200);
      });

      final service = SubscriptionService(client: client);
      final result = await service.fetch('https://panel.example/sub/abc123');

      expect(requested, ['/sub/abc123/json', '/sub/abc123']);
      expect(result.servers, hasLength(1));
    });

    test('does not append /json when the URL already ends with it', () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.path);
        return http.Response(_balancerJsonArray, 200);
      });

      final service = SubscriptionService(client: client);
      final result =
          await service.fetch('https://panel.example/sub/abc123/json');

      expect(requested, ['/sub/abc123/json']);
      expect(result.servers, hasLength(1));
    });

    test('keeps query parameters when appending /json', () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add('${request.url.path}?${request.url.query}');
        return http.Response(_balancerJsonArray, 200);
      });

      final service = SubscriptionService(client: client);
      await service.fetch('https://panel.example/sub/abc123?token=secret');

      expect(requested, ['/sub/abc123/json?token=secret']);
    });
  });
}
