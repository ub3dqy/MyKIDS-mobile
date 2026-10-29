import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/money_screen.dart';

import 'activity_lists_test.dart' show ActivityFixture;
import 'field_layout_test.dart' show mountFields, revealField;

class RewardFixture extends ActivityFixture {
  final commands = <Map<String, dynamic>>[];
  RewardFixture(String role) {
    token = 'synthetic-reward-session';
    snapshot!['user'] = {'id': role, 'role': role};
    snapshot!['balance'] = {'total': 50, 'reserved': 0, 'available': 50};
    snapshot!['penalties'] = [];
    snapshot!['goal'] = {'reward_id': 'gift'};
    change();
  }
  void change({
    String title = 'Конструктор',
    int price = 25,
    bool visible = true,
    bool remove = false,
  }) {
    snapshot!['rewards'] = remove
        ? <Map<String, dynamic>>[]
        : [
            {
              'id': 'gift',
              'title': title,
              'description': 'Описание',
              'price': price,
              'available': visible ? 1 : 0,
            },
          ];
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    commands.add({'path': path, 'method': method, 'body': body});
    if (method == 'DELETE') change(remove: true);
    return {'ok': true};
  }
}

Future<RewardFixture> showRewards(WidgetTester tester, String role) async {
  final repo = RewardFixture(role);
  addTearDown(() {
    repo.client.close();
    repo.dispose();
  });
  await mountFields(
    tester,
    Scaffold(
      body: AnimatedBuilder(
        animation: repo,
        builder: (_, _) => MoneyScreen(
          repository: repo,
          perform: (action) async {
            await action();
          },
        ),
      ),
    ),
    scale: 1.2,
  );
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await revealField(tester, find.text('Конструктор · 25 монет'));
  if (role == 'parent') {
    await tester.tap(find.text('Конструктор · 25 монет'));
    await tester.pumpAndSettle();
  }
  return repo;
}

void main() {
  for (final role in ['parent', 'child']) {
    testWidgets('expanded reward data refreshes for $role', (tester) async {
      final repo = await showRewards(tester, role);
      repo.change(title: 'Большой конструктор', price: 90);
      await tester.pumpAndSettle();
      await revealField(tester, find.text('Большой конструктор · 90 монет'));
      expect(find.text('Конструктор · 25 монет'), findsNothing);
      if (role == 'child') {
        await revealField(tester, find.text('До цели ещё 40 монет'));
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Попросить награду'),
              )
              .onPressed,
          isNull,
        );
        repo.change(price: 40);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Попросить награду'),
              )
              .onPressed,
          isNotNull,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('child visibility follows hide and restore without restarting', (
    tester,
  ) async {
    final repo = await showRewards(tester, 'child');
    repo.change(visible: false);
    await tester.pumpAndSettle();
    expect(find.text('Конструктор · 25 монет'), findsNothing);
    repo.change();
    await tester.pumpAndSettle();
    await revealField(tester, find.text('Конструктор · 25 монет'));
    expect(find.text('Удалить награду'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('parent deletion confirms and sends only selected reward', (
    tester,
  ) async {
    final repo = await showRewards(tester, 'parent');
    await revealField(tester, find.text('Удалить награду'));
    await tester.tap(find.text('Удалить награду'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Уже отправленные заявки сохранят прежнюю стоимость.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(repo.commands.single, {
      'path': '/v1/rewards/gift',
      'method': 'DELETE',
      'body': {},
    });
    expect(find.text('Конструктор · 25 монет'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'open deletion dialog refreshes price and disables after external removal',
    (tester) async {
      final repo = await showRewards(tester, 'parent');
      await revealField(tester, find.text('Удалить награду'));
      await tester.tap(find.text('Удалить награду'));
      await tester.pumpAndSettle();
      repo.change(title: 'Новая награда', price: 90);
      await tester.pumpAndSettle();
      expect(find.textContaining('Новая награда · 90 монет\n'), findsOneWidget);
      repo.change(remove: true);
      await tester.pumpAndSettle();
      expect(
        find.text('Награда уже удалена или доступ изменился'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Удалить'))
            .onPressed,
        isNull,
      );
      expect(repo.commands, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('session change cannot delete through an old confirmation', (
    tester,
  ) async {
    final repo = await showRewards(tester, 'parent');
    await revealField(tester, find.text('Удалить награду'));
    await tester.tap(find.text('Удалить награду'));
    await tester.pumpAndSettle();
    repo.token = 'another-synthetic-session';
    repo.generation++;
    repo.change(title: 'Другая семья');
    await tester.pumpAndSettle();
    expect(find.textContaining('Другая семья · 25 монет\n'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Удалить'), findsNothing);
    expect(find.textContaining('доступ измен'), findsOneWidget);
    expect(repo.commands, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('reward request includes the price displayed to the child', (
    tester,
  ) async {
    final repo = await showRewards(tester, 'child');
    await revealField(tester, find.text('Попросить награду'));
    await tester.tap(find.text('Попросить награду'));
    await tester.pumpAndSettle();
    expect(repo.commands.single, {
      'path': '/v1/redemptions',
      'method': 'POST',
      'body': {'reward_id': 'gift', 'expected_price': 25},
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
