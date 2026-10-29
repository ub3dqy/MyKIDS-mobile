import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/child_today.dart';
import 'package:mykids_family/money_screen.dart';

import 'activity_lists_test.dart' show ActivityFixture;

Future<void> showNegativeBalance(
  WidgetTester tester,
  ActivityFixture repo,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MoneyScreen(
          repository: repo,
          perform: (action) async {
            await action();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'full pending penalty is readable at zero and negative balances and confirmation explains full debit',
    (tester) async {
      for (final amount in [0, -500]) {
        final repo = ActivityFixture()..token = 'synthetic-negative-balance-owner';
        repo.snapshot!['balance'] = {
          'total': amount,
          'reserved': 0,
          'available': amount,
        };
        await showNegativeBalance(tester, repo);
        final text = find.textContaining('При подтверждении спишется: 500');
        await tester.ensureVisible(text);
        await tester.pumpAndSettle();
        expect(text, findsOneWidget);
        await tester.ensureVisible(find.text('Применить'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Применить'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            'Спишется вся сумма: 500 монет, даже при нулевом балансе',
          ),
          findsOneWidget,
        );
        expect(repo.changes, isEmpty);
        await tester.tap(find.text('Отмена'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        repo.client.close();
        repo.dispose();
      }
    },
  );

  testWidgets(
    'child sees debt, goal progress stays zero, and new exchanges are disabled until balance recovers',
    (tester) async {
      final repo = ActivityFixture()..token = 'synthetic-child-balance-owner';
      repo.snapshot!['user']['role'] = 'child';
      repo.snapshot!['balance'] = {
        'total': -500,
        'reserved': 0,
        'available': -500,
      };
      repo.snapshot!['rewards'] = [
        {
          'id': 'goal',
          'title': 'Книга',
          'price': 100,
          'available': 1,
          'description': '',
        },
      ];
      repo.snapshot!['goal'] = {'reward_id': 'goal'};
      await showNegativeBalance(tester, repo);
      expect(find.text('-500'), findsOneWidget);
      expect(find.textContaining('Баланс отрицательный.'), findsOneWidget);
      await tester.ensureVisible(find.text('Обменять монеты на рубли'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Обменять монеты на рубли'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Попросить награду'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Попросить награду'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0,
      );
      expect(repo.changes, isEmpty);
      repo.snapshot!['balance'] = {
        'total': 100,
        'reserved': 0,
        'available': 100,
      };
      await showNegativeBalance(tester, repo);
      await tester.ensureVisible(find.text('Попросить награду'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Попросить награду'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Попросить награду'));
      await tester.pumpAndSettle();
      expect(repo.changes, ['/v1/redemptions']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
    },
  );

  testWidgets('child header coin button retains the negative sign', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              FamilyCoinButton(amount: -500, online: true, onPressed: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('-500'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
