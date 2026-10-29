import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/schedule.dart';

import 'task_rules_test.dart' show TaskFixture, showTasks, reveal;

void main() {
  testWidgets(
    'weekday repeat saves an indefinite local daily deadline and chosen days',
    (tester) async {
      final repo = TaskFixture();
      await showTasks(tester, repo);
      await tester.tap(find.text('Добавить задание'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('field-title')),
        'Убрать игрушки',
      );
      await reveal(tester, find.text('Повторять по дням недели'));
      await tester.tap(find.text('Повторять по дням недели'));
      await tester.pumpAndSettle();
      expect(find.text('Дни повторения'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'Пн'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('field-reward')));
      await tester.enterText(find.byKey(const ValueKey('field-reward')), '30');
      await reveal(tester, find.byKey(const ValueKey('field-penalty')));
      await tester.enterText(find.byKey(const ValueKey('field-penalty')), '15');
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      final body = repo.mutations.single;
      expect(body['weekdays'], [2, 3, 4, 5, 6, 7]);
      expect(body.containsKey('repeat_until'), isFalse);
      expect(body.containsKey('repeat_days'), isFalse);
      expect(body.containsKey('repeat'), isFalse);
      final due = familyClock(
        repo.snapshot,
        DateTime.parse(body['due_at'] as String),
      );
      expect(due.hour, 20);
      expect(dateOnly(due), dateOnly(familyClock(repo.snapshot)));
      expect(tester.takeException(), isNull);
      repo.client.close();
      repo.dispose();
    },
  );

  testWidgets('empty repeat days cannot save and reveal the day choices', (
    tester,
  ) async {
    final repo = TaskFixture();
    await showTasks(tester, repo);
    await tester.tap(find.text('Добавить задание'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('field-title')),
      'Каждый день',
    );
    await reveal(tester, find.text('Повторять по дням недели'));
    await tester.tap(find.text('Повторять по дням недели'));
    await tester.pumpAndSettle();
    for (final day in ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']) {
      await reveal(tester, find.widgetWithText(FilterChip, day));
      await tester.tap(find.widgetWithText(FilterChip, day));
      await tester.pumpAndSettle();
    }
    await reveal(tester, find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Заполните поле «Дни повторения»'), findsOneWidget);
    expect(repo.mutations, isEmpty);
    expect(tester.takeException(), isNull);
    repo.client.close();
    repo.dispose();
  });

  testWidgets(
    'each daily instance appears on its own date and stopping requires confirmation',
    (tester) async {
      final repo = TaskFixture(withTask: true);
      final today = familyClock(repo.snapshot);
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final task = repo.rows('tasks').first;
      repo.snapshot!['tasks'] = [
        {
          ...task,
          'title': 'Сегодня',
          'due_at': '${dateOnly(today)}T20:00:00+03:00',
          'recurrence_id': 'daily',
          'occurrence_date': dateOnly(today),
        },
        {
          ...task,
          'id': 'tomorrow',
          'title': 'Завтра',
          'due_at': '${dateOnly(tomorrow)}T20:00:00+03:00',
          'recurrence_id': 'daily',
          'occurrence_date': dateOnly(tomorrow),
        },
        {
          ...task,
          'id': 'moved',
          'title': 'Перенесено на сегодня',
          'due_at': '${dateOnly(today)}T21:00:00+03:00',
          'recurrence_id': 'daily',
          'occurrence_date': dateOnly(
            DateTime(today.year, today.month, today.day - 1),
          ),
        },
      ];
      repo.snapshot!['task_recurrences'] = [
        {
          'id': 'daily',
          'weekdays': jsonEncode([1, 2, 3, 4, 5, 6, 7]),
          'active': 1,
        },
      ];
      await showTasks(tester, repo);
      expect(find.text('Сегодня'), findsOneWidget);
      expect(find.text('Перенесено на сегодня'), findsOneWidget);
      expect(find.text('Завтра'), findsNothing);
      await tester.tap(find.byTooltip('Следующий день задания'));
      await tester.pumpAndSettle();
      expect(find.text('Сегодня'), findsNothing);
      await tester.tap(find.text('Завтра'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Остановить повторение'));
      await tester.tap(find.text('Остановить повторение'));
      await tester.pumpAndSettle();
      expect(repo.mutations, isEmpty);
      await tester.tap(find.text('Вернуться'));
      await tester.pumpAndSettle();
      expect(repo.mutations, isEmpty);
      await tester.tap(find.text('Остановить повторение'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Остановить повтор'));
      await tester.pumpAndSettle();
      expect(repo.mutations.single['action'], 'stop_repeat');
      expect(repo.mutations.single['path'], '/v1/tasks/tomorrow/actions');
      expect(tester.takeException(), isNull);
      repo.client.close();
      repo.dispose();
    },
  );
}
