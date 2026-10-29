import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/forms.dart';

import 'activity_lists_test.dart' show ActivityFixture;

class QuickMoneyFixture extends ActivityFixture {
  final writes = <Map<String, dynamic>>[];
  QuickMoneyFixture(String action) {
    token = 'synthetic-quick-money-owner';
    snapshot!['user']['role'] = ['goal', 'cancel'].contains(action)
        ? 'child'
        : 'parent';
    snapshot!['penalties'] = action == 'waive' ? snapshot!['penalties'] : [];
    snapshot!['rewards'] = action == 'goal'
        ? [
            {
              'id': 'reward',
              'title': 'Велосипед',
              'description': 'Для прогулок',
              'price': 100,
              'available': 1,
            },
          ]
        : [];
    snapshot!['redemptions'] =
        ['cancel', 'claim', 'release', 'reject'].contains(action)
        ? [
            {
              'id': 'request',
              'title': 'Просьба о награде',
              'amount': 25,
              'status': ['release', 'reject'].contains(action)
                  ? 'claimed'
                  : 'pending',
              'claimed_by': 'dad',
            },
          ]
        : [];
  }
  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    writes.add({
      'path': path,
      'body': body,
      'user': userId,
      'generation': generation,
    });
    return {'ok': true};
  }
}

const labels = {
  'goal': 'Копить на это',
  'waive': 'Отменить',
  'cancel': 'Отменить заявку',
  'claim': 'Взять для выдачи',
  'release': 'Ещё не выдал — вернуть в ожидание',
  'reject': 'Отклонить до выдачи',
};

void main() {
  testWidgets('delayed reward request cannot use a replacement session', (
    tester,
  ) async {
    final repo = QuickMoneyFixture('goal');
    repo.snapshot!['balance'] = {
      'available': 1000,
      'total': 1000,
      'reserved': 0,
    };
    final gate = Completer<void>();
    final errors = <Object>[];
    addTearDown(() async {
      if (!gate.isCompleted) gate.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoneyScreen(
            repository: repo,
            perform: (action) async {
              try {
                await gate.future;
                await action();
              } catch (error) {
                errors.add(error);
              }
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Велосипед · 100 монет'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Велосипед · 100 монет'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Попросить награду'));
    await tester.tap(find.text('Попросить награду'));
    await tester.pump();
    repo.generation++;
    repo.token = 'replacement-request-session';
    repo.notifyListeners();
    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  const interactions = {
    'exchange': 'Обменять монеты на рубли',
    'rules': 'Настроить суммы за оценки',
    'add': 'Добавить награду',
    'edit': 'Изменить награду',
    'delete': 'Удалить награду',
    'request': 'Попросить награду',
    'fine': 'Применить',
    'payout': 'Уже выдал — подтвердить',
  };
  for (final entry in interactions.entries) {
    testWidgets(
      'old ${entry.key} interaction cannot open a form for a new session',
      (tester) async {
        final repo = QuickMoneyFixture(
          entry.key == 'fine'
              ? 'waive'
              : entry.key == 'payout'
              ? 'release'
              : 'goal',
        );
        repo.snapshot!['user']['role'] =
            ['exchange', 'request'].contains(entry.key) ? 'child' : 'parent';
        repo.snapshot!['balance'] = {
          'available': 1000,
          'total': 1000,
          'reserved': 0,
        };
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          repo.client.close();
          repo.dispose();
        });
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
        if (['edit', 'delete', 'request', 'payout'].contains(entry.key)) {
          final title = find.text(
            entry.key == 'payout'
                ? 'Просьба о награде · 25'
                : 'Велосипед · 100 монет',
          );
          await tester.scrollUntilVisible(
            title,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(title);
          await tester.pumpAndSettle();
        }
        final label = find.text(entry.value);
        await tester.scrollUntilVisible(
          label,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(label);
        final button = tester.widget(
          find
              .ancestor(
                of: label,
                matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
              )
              .first,
        ) as ButtonStyleButton;
        final callback = button.onPressed!;
        repo.token = 'another-synthetic-money-session';
        repo.generation++;
        repo.notifyListeners();
        callback();
        await tester.pumpAndSettle();
        expect(find.byType(FamilyForm), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(repo.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  Future<VoidCallback> button(WidgetTester tester, String action) async {
    if (action != 'waive') {
      final title = find.text(
        action == 'goal' ? 'Велосипед · 100 монет' : 'Просьба о награде · 25',
      );
      await tester.scrollUntilVisible(
        title,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(title);
      await tester.pumpAndSettle();
    }
    final label = find.text(labels[action]!);
    await tester.scrollUntilVisible(
      label,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(label);
    final widget = tester.widget(
      find
          .ancestor(
            of: label,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .first,
    ) as ButtonStyleButton;
    return widget.onPressed!;
  }

  for (final action in labels.keys) {
    for (final covered in [false, true]) {
      testWidgets(
        '$action works only on the visible current view; covered=$covered',
        (tester) async {
          final repo = QuickMoneyFixture(action);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            repo.client.close();
            repo.dispose();
          });
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
          final callback = await button(tester, action);
          if (covered) {
            unawaited(
              tester
                  .state<NavigatorState>(find.byType(Navigator))
                  .push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const Scaffold(body: Text('Экран поверх монет')),
                    ),
                  ),
            );
            await tester.pumpAndSettle();
          }
          callback();
          await tester.pumpAndSettle();
          expect(repo.writes, hasLength(covered ? 0 : 1));
          if (covered) expect(find.text('Экран поверх монет'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'temporary role revocation invalidates an old quick-action callback',
    (tester) async {
      final repo = QuickMoneyFixture('goal');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        repo.client.close();
        repo.dispose();
      });
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
      final callback = await button(tester, 'goal');
      repo.snapshot!['user']['role'] = 'parent';
      repo.notifyListeners();
      repo.snapshot!['user']['role'] = 'child';
      repo.notifyListeners();
      callback();
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
    },
  );

  testWidgets(
    'fresh money view works after replacement while its old callback stays invalid',
    (tester) async {
      final first = QuickMoneyFixture('goal'),
          second = QuickMoneyFixture('goal');
      second.snapshot!['user']['id'] = 'second-child';
      final selection = ValueNotifier(first);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        selection.dispose();
        for (final repo in [first, second]) {
          repo.client.close();
          repo.dispose();
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<QuickMoneyFixture>(
              valueListenable: selection,
              builder: (_, repo, _) => MoneyScreen(
                repository: repo,
                perform: (action) async {
                  await action();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final old = await button(tester, 'goal');
      selection.value = second;
      await tester.pumpAndSettle();
      old();
      await tester.pumpAndSettle();
      expect(first.writes, isEmpty);
      expect(second.writes, isEmpty);
      final current = find.ancestor(
        of: find.text('Копить на это'),
        matching: find.byType(TextButton),
      );
      await tester.ensureVisible(current);
      tester.widget<TextButton>(current).onPressed!();
      await tester.pumpAndSettle();
      expect(second.writes.single['user'], 'second-child');
    },
  );

  for (final action in labels.keys) {
    for (final deferred in [false, true]) {
      testWidgets('$action cannot act for a new owner; deferred=$deferred', (
        tester,
      ) async {
        final repo = QuickMoneyFixture(action);
        final failures = <Object>[];
        final gate = Completer<void>();
        addTearDown(() async {
          if (!gate.isCompleted) gate.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          repo.client.close();
          repo.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MoneyScreen(
                repository: repo,
                perform: (operation) async {
                  try {
                    if (deferred) await gate.future;
                    await operation();
                  } catch (failure) {
                    failures.add(failure);
                  }
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (action != 'waive') {
          final title = find.text(
            action == 'goal'
                ? 'Велосипед · 100 монет'
                : 'Просьба о награде · 25',
          );
          await tester.scrollUntilVisible(
            title,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(title);
          await tester.pumpAndSettle();
        }
        final button = find.text(labels[action]!);
        await tester.scrollUntilVisible(
          button,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(button);
        final ancestor = find.ancestor(
          of: button,
          matching: find.byType(TextButton),
        );
        final filled = find.ancestor(
          of: button,
          matching: find.byType(FilledButton),
        );
        final outlined = find.ancestor(
          of: button,
          matching: find.byType(OutlinedButton),
        );
        final VoidCallback callback = ancestor.evaluate().isNotEmpty
            ? tester.widget<TextButton>(ancestor).onPressed!
            : filled.evaluate().isNotEmpty
            ? tester.widget<FilledButton>(filled).onPressed!
            : tester.widget<OutlinedButton>(outlined).onPressed!;
        if (deferred) {
          callback();
          await tester.pump();
        }
        repo.token = 'new-synthetic-quick-money-owner';
        repo.generation++;
        repo.notifyListeners();
        if (!deferred) callback();
        gate.complete();
        await tester.pumpAndSettle();
        expect(repo.writes, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
