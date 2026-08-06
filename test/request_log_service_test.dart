import 'package:affection_vpn/services/request_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RequestLogService.parseAccessLine', () {
    test('parses an accepted connection with inbound -> outbound path', () {
      final entry = RequestLogService.parseAccessLine(
        '2026/08/06 12:34:56.123 [Info] [Access] '
        'tcp:example.com:443 accepted tcp:127.0.0.1:53210 [socks-app -> proxy]',
      );

      expect(entry, isNotNull);
      expect(entry!.kind, RequestLogKind.tunnel);
      expect(entry.target, 'example.com');
      expect(entry.via, 'socks-app -> proxy');
      expect(entry.status, 'accepted');
      expect(entry.time.year, 2026);
    });

    test('extracts the sniffed hostname instead of the loopback local addr',
        () {
      final entry = RequestLogService.parseAccessLine(
        '2026/08/06 12:34:56 [Info] [Access] '
        'tcp:www.some-site.net:443 accepted tcp:127.0.0.1:41123 [http -> proxy]',
      );

      expect(entry, isNotNull);
      expect(entry!.target, 'www.some-site.net');
      expect(entry.via, 'http -> proxy');
    });

    test('parses a rejected connection', () {
      final entry = RequestLogService.parseAccessLine(
        '2026/08/06 12:34:56 [Info] [Access] '
        'tcp:blocked.example:443 rejected [socks -> block]',
      );

      expect(entry, isNotNull);
      expect(entry!.target, 'blocked.example');
      expect(entry.status, 'rejected');
    });

    test('handles IPv6 literal targets', () {
      final entry = RequestLogService.parseAccessLine(
        '2026/08/06 12:34:56 [Info] [Access] '
        'tcp:[2001:db8::1]:443 accepted tcp:127.0.0.1:51000 [socks -> proxy]',
      );

      expect(entry, isNotNull);
      expect(entry!.target, '2001:db8::1');
    });

    test('parses udp connections', () {
      final entry = RequestLogService.parseAccessLine(
        '2026/08/06 12:34:56 [Info] [Access] '
        'udp:dns.google:53 accepted udp:127.0.0.1:45000 [socks -> proxy]',
      );

      expect(entry, isNotNull);
      expect(entry!.target, 'dns.google');
    });

    test('ignores connection-from bookkeeping lines', () {
      final entry = RequestLogService.parseAccessLine(
        '2026/08/06 12:34:56 [Info] [Access] connection from 127.0.0.1:53210',
      );

      expect(entry, isNull);
    });

    test('ignores non-access lines', () {
      expect(
        RequestLogService.parseAccessLine(
          '2026/08/06 12:34:56 [Info] [Warning] '
          'tcp:example.com:443 accepted [socks -> proxy]',
        ),
        isNull,
      );
      expect(RequestLogService.parseAccessLine('random noise'), isNull);
    });
  });
}
