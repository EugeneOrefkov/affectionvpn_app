import 'package:affection_vpn/services/subscription_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hwidHeaders sends X-Hwid and platform', () {
    final headers = SubscriptionService.hwidHeaders('aBc123-4567');

    expect(headers['X-Hwid'], 'aBc123-4567');
    expect(headers.containsKey('X-Device-Os'), isTrue);
    expect(headers['X-Device-Os'], isNotEmpty);
  });
}
