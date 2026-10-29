import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/money_screen.dart';

import '../test/field_layout_test.dart' show mountFields;
import '../test/scroll_sections_test.dart'
    show LongActivityFixture, revealSection, sectionScroll;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android child and parent can scroll the complete coin history', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    final results = <String, dynamic>{
      'synthetic_only': true,
      'physical_devices_tested': false,
    };
    for (final role in ['child', 'parent']) {
      final repo = LongActivityFixture(role);
      try {
        await mountFields(
          tester,
          Scaffold(
            appBar: AppBar(title: const Text('Семейные монеты')),
            body: MoneyScreen(
              key: ObjectKey(repo),
              repository: repo,
              perform: (_) async => fail('Viewing must not change coins'),
            ),
          ),
          child: role == 'child',
          scale: 1.6,
          screenSize: null,
        );
        await revealSection(tester, 'money-ledger');
        final top = tester.getTopLeft(
          find.byKey(const ValueKey('money-ledger')),
        );
        expect(find.byKey(const ValueKey('ledger-entry-179')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('ledger-entry-0')),
          1000,
          scrollable: sectionScroll('money-ledger'),
          maxScrolls: 260,
        );
        await tester.pumpAndSettle();
        expect(find.text('-5 · Запись 0'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('money-ledger'))),
          top,
        );
        expect(tester.takeException(), isNull);
        expect(repo.changes, isEmpty);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();
        await binding.takeScreenshot('scroll-coins-$role');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        results[role] = {
          'entries': 180,
          'oldest_reached': true,
          'other_sections_stationary': true,
          'readable_dates': true,
          'no_money_changed': true,
        };
      } finally {
        repo.client.close();
        repo.dispose();
      }
    }
    binding.reportData = {...?binding.reportData, ...results};
  });
}
