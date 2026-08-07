import 'package:affection_vpn/services/request_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RequestLogService.parseAccessLine', () {
    test('parses an accepted http request with inbound >> outbound path', () {
      final entry = RequestLogService.parseAccessLine(
        '2026/08/07 08:46:15.370176 from 127.0.0.1:37148 '
        'accepted http://example.com/ [http >> direct]',
      );

      expect(entry, isNotNull);
      expect(entry!.kind, RequestLogKind.tunnel);
      expect(entry.target, 'example.com');
      expect(entry.via, 'http >> direct');
      expect(entry.status, 'accepted');
      expect(entry.time.year, 2026);
    });

    test('parses a CONNECT target (//host:port) keeping the port', () {
      final entry = RequestLogService.parseAccessLine(
        '2026/08/07 08:46:15.451468 from 127.0.0.1:37150 '
        'accepted //example.com:443 [http >> direct]',
      );

      expect(entry, isNotNull);
      expect(entry!.target, 'example.com:443');
      expect(entry.via, 'http >> direct');
    });

    test('strips the path from an http URL', () {
      final entry = RequestLogService.parseAccessLine(
        '2026/08/07 08:46:15.000000 from 127.0.0.1:37160 '
        'accepted http://www.some-site.net/page?x=1 [socks >> proxy]',
      );

      expect(entry, isNotNull);
      expect(entry!.target, 'www.some-site.net');
      expect(entry.via, 'socks >> proxy');
    });

    test('parses a rejected connection', () {
      final entry = RequestLogService.parseAccessLine(
        '2026/08/07 08:46:32.682055 from 127.0.0.1:54718 '
        'rejected tcp:blocked.example:443 [http -> blocked]',
      );

      expect(entry, isNotNull);
      expect(entry!.target, 'blocked.example:443');
      expect(entry.status, 'rejected');
    });

    test('handles IPv6 literal targets', () {
      final entry = RequestLogService.parseAccessLine(
        '2026/08/07 08:46:15.000000 from [::1]:51000 '
        'accepted tcp:[2001:db8::1]:443 [socks >> proxy]',
      );

      expect(entry, isNotNull);
      expect(entry!.target, '2001:db8::1');
    });

    test('parses udp connections', () {
      final entry = RequestLogService.parseAccessLine(
        '2026/08/07 08:46:15.000000 from 127.0.0.1:45000 '
        'accepted udp:dns.google:53 [socks >> proxy]',
      );

      expect(entry, isNotNull);
      expect(entry!.target, 'dns.google:53');
    });

    test('parses a line without a detour and with a reason tail', () {
      final entry = RequestLogService.parseAccessLine(
        '2026/08/07 08:46:15.000000 from 127.0.0.1:53210 '
        'accepted tcp:example.com:80 reason: some detail',
      );

      expect(entry, isNotNull);
      expect(entry!.target, 'example.com:80');
      expect(entry.via, '');
    });

    test('ignores non-access lines', () {
      expect(
        RequestLogService.parseAccessLine(
          '2026/08/07 08:45:54.949942 [Info] [4078325853] proxy/http: '
          'request to Method [GET] Host [example.com]',
        ),
        isNull,
      );
      expect(
        RequestLogService.parseAccessLine(
          '2026/08/07 08:45:54.949942 from 127.0.0.1:54200 connected',
        ),
        isNull,
      );
      expect(RequestLogService.parseAccessLine('random noise'), isNull);
      expect(RequestLogService.parseAccessLine(''), isNull);
    });
  });
}
