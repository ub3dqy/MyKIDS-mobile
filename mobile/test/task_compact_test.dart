import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/child_today.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/task_summary.dart';

import 'field_layout_test.dart' show mountFields, revealField;
import 'task_time_labels_test.dart' show TaskTimeFixture;

TaskTimeFixture compactFixture(String role) {
  final repo = TaskTimeFixture(role: role);
  for (final task in repo.snapshot!['tasks'] as List) {
    task.addAll({'status': 'completed', 'awarded_reward': 5});
  }
  repo.snapshot!['submissions'] = [
    {
      'task_id': 'morning',
      'note': '',
      'accepted': 1,
      'attachment_ids': '[]',
      'marked_at': '2026-10-14T20:53:19.182731+00:00',
      'received_at': '2026-10-14T20:53:20.915079+00:00',
    },
  ];
  return repo;
}

void main() {
  for (final role in ['child', 'parent']) {
    testWidgets(
      '$role completed card stays compact and details use readable dates',
      (tester) async {
        final repo = compactFixture(role);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final before = jsonEncode(repo.snapshot);
        await mountFields(
          tester,
          Scaffold(
            body: TaskScreen(
              repository: repo,
              perform: (_) async =>
                  fail('Viewing details must not change the task'),
            ),
          ),
          scale: 1.6,
        );
        await tester.pumpAndSettle();
        final card = find.byKey(const ValueKey('task-morning'));
        await revealField(tester, card);
        expect(tester.getSize(card).height, lessThan(320));
        expect(find.textContaining('Штраф за невыполнение'), findsNothing);
        expect(find.textContaining('Проверяет:'), findsNothing);
        expect(find.textContaining('Повтор:'), findsNothing);
        expect(find.textContaining('Отмечено:'), findsNothing);
        expect(find.text('+5 монет'), findsNWidgets(2));
        await tester.tap(
          find.descendant(of: card, matching: find.text('Подробнее')),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Проверяет: мама или папа'), findsOneWidget);
        expect(find.textContaining('Повтор: каждый день'), findsOneWidget);
        expect(find.text('Отмечено: 14.10.2026 23:53'), findsOneWidget);
        expect(find.text('Получено: 14.10.2026 23:53'), findsOneWidget);
        expect(find.textContaining('2026-10-14T'), findsNothing);
        expect(find.text('Результат: '), findsNothing);
        await revealField(tester, find.text('Скрыть подробности'));
        await tester.tap(find.text('Скрыть подробности'));
        await tester.pumpAndSettle();
        expect(tester.getSize(card).height, lessThan(320));
        expect(repo.mutations, isEmpty);
        expect(jsonEncode(repo.snapshot), before);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        repo.client.close();
        repo.dispose();
      },
    );
  }

  testWidgets('child can submit without opening extra information', (
    tester,
  ) async {
    final repo = TaskTimeFixture(role: 'child');
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountFields(
      tester,
      Scaffold(
        body: TaskScreen(
          repository: repo,
          perform: (_) async => fail('Opening the form must not send a result'),
        ),
      ),
      scale: 2,
    );
    await tester.pumpAndSettle();
    final submit = find.descendant(
      of: find.byKey(const ValueKey('task-morning')),
      matching: find.text('Готово — отправить на проверку'),
    );
    await revealField(tester, submit);
    expect(find.textContaining('Штраф за невыполнение'), findsNothing);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Отправить результат'), findsOneWidget);
    expect(repo.mutations, isEmpty);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
  });

  testWidgets(
    'child Today preview retains time and reward without long terms',
    (tester) async {
      final repo = TaskTimeFixture(role: 'child');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChildToday(repository: repo, openPage: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TaskSummary), findsNWidgets(2));
      expect(find.textContaining('Штраф за невыполнение'), findsNothing);
      expect(find.textContaining('Срок выполнения:'), findsNothing);
      expect(find.text(repo.morningLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
    },
  );

  test(
    'zero earned coins and tiered rewards have honest compact summaries',
    () {
      expect(
        taskCompactRewardText({
          'status': 'completed',
          'reward': 50,
          'awarded_reward': 0,
        }),
        'Без монет',
      );
      expect(
        taskCompactRewardText({
          'status': 'assigned',
          'reward': 50,
          'reward_options': {
            'total': 6,
            'tiers': [
              {'minimum': 6, 'coins': 50},
            ],
          },
        }),
        'До 50 монет',
      );
      expect(
        taskCompactRewardText({'status': 'not_completed', 'reward': 50}),
        '',
      );
    },
  );
  test(
    'compact time keeps both days across midnight and shows other years',
    () {
      final snapshot = {
        'family': {'timezone': 'Europe/Moscow'},
      };
      final year = familyClock(snapshot).year;
      expect(
        taskCompactTimeText(snapshot, {
          'planned_start': '$year-10-13T20:50:00Z',
          'planned_end': '$year-10-13T21:10:00Z',
        }),
        '13.10 23:50–14.10 00:10',
      );
      expect(
        taskCompactTimeText(snapshot, {
          'due_at': '${year + 1}-10-13T20:00:00Z',
        }),
        'До 13.10.${year + 1} 23:00',
      );
    },
  );
  testWidgets('parent can still create a program from the compact menu', (
    tester,
  ) async {
    final repo = compactFixture('parent');
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountFields(
      tester,
      Scaffold(
        body: TaskScreen(
          repository: repo,
          perform: (operation) async {
            await operation();
          },
        ),
      ),
      scale: 1.6,
    );
    await tester.pumpAndSettle();
    expect(find.text('Создать программу из заданий'), findsNothing);
    await tester.tap(find.byTooltip('Другие действия с заданиями'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать программу из заданий'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('field-title')),
      'Математика на месяц',
    );
    await revealField(tester, find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repo.mutations.single['path'], '/v1/programs');
    expect(repo.mutations.single['title'], 'Математика на месяц');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
  });
}
