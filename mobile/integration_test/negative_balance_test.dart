import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/visuals.dart';

import '../test/activity_lists_test.dart' show ActivityFixture;
import '../test/field_layout_test.dart' show mountFields, revealField;
import '../test/task_review_navigation_test.dart' show reviewFixture;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('full penalty at zero and child debt are clear on Android', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    final repo = ActivityFixture();
    Future<void> show() async {
      await mountFields(
        tester,
        Scaffold(
          appBar: AppBar(
            title: Text(
              'MyKIDS · ${repo.role == 'child' ? 'Ребёнок' : 'Папа'}',
            ),
          ),
          body: MoneyScreen(
            repository: repo,
            perform: (action) async {
              await action();
            },
          ),
        ),
        scale: 1.4,
        screenSize: null,
      );
      await tester.runAsync(
        () => precacheFamilyArtwork(tester.element(find.byType(Scaffold))),
      );
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await binding.takeScreenshot('negative-balance-$name');
      expect(tester.takeException(), isNull);
    }

    await show();
    await revealField(
      tester,
      find.textContaining('При подтверждении спишется: 500'),
    );
    await capture('full-fine');
    await revealField(tester, find.text('Применить'));
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Спишется вся сумма: 500 монет'),
      findsOneWidget,
    );
    await capture('confirmation');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    repo.snapshot!['user']['role'] = 'child';
    repo.snapshot!['balance'] = {
      'total': -500,
      'reserved': 0,
      'available': -500,
    };
    await show();
    expect(find.text('-500'), findsOneWidget);
    expect(find.textContaining('Баланс отрицательный.'), findsOneWidget);
    await capture('child-debt');
    await revealField(tester, find.text('Обменять монеты на рубли'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Обменять монеты на рубли'),
          )
          .onPressed,
      isNull,
    );
    expect(repo.changes, isEmpty);
    binding.reportData = {
      ...?binding.reportData,
      'synthetic_only': true,
      'full_fine_at_zero_shown': true,
      'full_fine_confirmation': true,
      'negative_child_balance_visible': true,
      'new_exchange_disabled': true,
      'text_scale': 1.4,
    };
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
  });
  testWidgets('the waiting result identifies and opens the evening task', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    final repo = reviewFixture();
    Future<void> perform(Future<Map<String, dynamic>> Function() action) async {
      await action();
    }

    await mountFields(
      tester,
      Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('MyKIDS · Папа')),
          body: TodayScreen(
            repository: repo,
            openPage: (_) {},
            onReviewTask: (id) => openTaskReview(context, repo, perform, id),
          ),
        ),
      ),
      scale: 1.4,
      screenSize: null,
    );
    await tester.pumpAndSettle();
    final waiting = find.byKey(const ValueKey('today-review-evening'));
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('today-review-card-evening'))),
      alignment: .35,
    );
    await tester.pumpAndSettle();
    await binding.takeScreenshot('negative-balance-review-today');
    await tester.tap(waiting);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-morning')), findsNothing);
    await revealField(tester, find.text('Результат: Вечером всё сделано'));
    await binding.takeScreenshot('negative-balance-review-result');
    expect(repo.mutations, isEmpty);
    expect(tester.takeException(), isNull);
    binding.reportData = {
      ...?binding.reportData,
      'waiting_task_identified': true,
      'specific_evening_result_opened': true,
      'navigation_did_not_approve': true,
    };
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
  });
}
