import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/school_screen.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/schedule.dart';

import '../test/field_layout_test.dart' show mountFields, revealField;
import '../test/support/calendar_results_fixture.dart' show ResultsFixture;
import '../test/task_rules_test.dart' show TaskFixture;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'school lessons only and daily family tasks on Android with large text',
    (tester) async {
      await binding.convertFlutterSurfaceToImage();
      Future<void> show(Widget widget) => mountFields(
        tester,
        Scaffold(body: widget),
        scale: 1.5,
        screenSize: null,
      );
      Future<void> reveal(Finder finder) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 100));
        await revealField(tester, finder);
      }

      Future<void> capture(String name) async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await binding.takeScreenshot('school-repeat-$name');
        expect(tester.takeException(), isNull);
      }

      final grades = ResultsFixture();
      grades.snapshot!['schedules'][0]['kind'] = 'other';
      await show(
        SchoolScreen(
          repository: grades,
          gradesOnly: true,
          initialDay: DateTime(2026, 10, 12),
          perform: (action) async {
            await action();
          },
        ),
      );
      expect(find.text('Школа'), findsNothing);
      expect(find.text('Математика'), findsOneWidget);
      await capture('school-subjects');

      final tasks = TaskFixture();
      await show(
        TaskScreen(
          repository: tasks,
          perform: (action) async {
            await action();
          },
        ),
      );
      await tester.tap(find.text('Добавить задание'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('field-title')),
        'Убрать игрушки',
      );
      await reveal(find.text('Повторять по дням недели'));
      await tester.tap(find.text('Повторять по дням недели'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'Вс'), findsOneWidget);
      await capture('daily-form');
      await reveal(find.byKey(const ValueKey('field-reward')));
      await tester.enterText(find.byKey(const ValueKey('field-reward')), '30');
      await reveal(find.byKey(const ValueKey('field-penalty')));
      await tester.enterText(find.byKey(const ValueKey('field-penalty')), '15');
      await reveal(find.text('Сохранить'));
      await capture('save-visible');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(tasks.mutations.single['weekdays'], [1, 2, 3, 4, 5, 6, 7]);
      expect(tasks.mutations.single.containsKey('repeat_until'), isFalse);

      final daily = TaskFixture(withTask: true);
      final today = familyClock(daily.snapshot);
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final original = daily.rows('tasks').first;
      daily.snapshot!['tasks'] = [
        {
          ...original,
          'title': 'Игрушки сегодня',
          'due_at': '${dateOnly(today)}T20:00:00+03:00',
          'recurrence_id': 'daily',
          'occurrence_date': dateOnly(today),
        },
        {
          ...original,
          'id': 'tomorrow',
          'title': 'Игрушки завтра',
          'due_at': '${dateOnly(tomorrow)}T20:00:00+03:00',
          'recurrence_id': 'daily',
          'occurrence_date': dateOnly(tomorrow),
        },
      ];
      daily.snapshot!['task_recurrences'] = [
        {
          'id': 'daily',
          'weekdays': jsonEncode([1, 2, 3, 4, 5, 6, 7]),
          'active': 1,
        },
      ];
      await show(
        TaskScreen(
          repository: daily,
          perform: (action) async {
            await action();
          },
        ),
      );
      expect(find.text('Игрушки сегодня'), findsOneWidget);
      expect(find.text('Игрушки завтра'), findsNothing);
      await capture('today');
      await tester.tap(find.byTooltip('Следующий день задания'));
      await tester.pumpAndSettle();
      expect(find.text('Игрушки сегодня'), findsNothing);
      await tester.tap(find.text('Игрушки завтра'));
      await tester.pumpAndSettle();
      await reveal(find.text('Остановить повторение'));
      await tester.tap(find.text('Остановить повторение'));
      await tester.pumpAndSettle();
      expect(daily.mutations, isEmpty);
      await capture('stop-confirmation');
      await tester.tap(find.text('Остановить повтор'));
      await tester.pumpAndSettle();
      expect(daily.mutations.single['action'], 'stop_repeat');
      binding.reportData = {
        ...?binding.reportData,
        'synthetic_only': true,
        'school_container_has_no_grade': true,
        'large_text_scale': 1.5,
        'all_seven_days_saved': true,
        'indefinite_repeat': true,
        'separate_daily_instances': true,
        'stop_requires_confirmation': true,
      };
      await tester.pumpWidget(const SizedBox.shrink());
      for (final repo in [grades, tasks, daily]) {
        repo.client.close();
        repo.dispose();
      }
    },
  );
}
