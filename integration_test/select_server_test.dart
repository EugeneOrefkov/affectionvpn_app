import 'package:affection_vpn/main.dart' as app;
import 'package:affection_vpn/screens/home/main_shell.dart';
import 'package:affection_vpn/screens/home/widgets/server_card.dart';
import 'package:affection_vpn/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

/// Regression test for the Linux server-selection bug: the tray menu rebuild
/// used to emit a spurious "activate" on the first radio item, which sent a
/// `selectServer(0)` back to Dart and instantly reverted any selection made in
/// the UI. The selection must now persist after tapping a server card.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Timed out waiting for $finder');
  }

  testWidgets('server card tap updates the selected server', (tester) async {
    app.main();

    await pumpUntil(tester, find.byIcon(Icons.public));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byIcon(Icons.public));
    await tester.pump(const Duration(milliseconds: 800));

    final cards = find.byType(ServerCard);
    expect(cards, findsWidgets, reason: 'servers list should be rendered');

    final state =
        tester.element(find.byType(MainShell)).read<AppState>();
    final before = state.selectedIndex;

    final targetIndex = before == 0 ? 1 : 0;
    await tester.tap(cards.at(targetIndex), warnIfMissed: true);
    await tester.pump(const Duration(milliseconds: 800));

    expect(state.selectedIndex, targetIndex,
        reason: 'selecting a server must not be reverted by the tray');
  });
}
