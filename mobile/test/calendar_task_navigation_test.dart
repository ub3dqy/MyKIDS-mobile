import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/visuals.dart';

import 'field_layout_test.dart' show revealField;
import 'task_time_labels_test.dart' show TaskTimeFixture;

TaskTimeFixture datedTasks(String role) {
  final repo = TaskTimeFixture(role: role);
  repo.snapshot!['schedules'] = <Map<String, dynamic>>[];
  repo.snapshot!['schedule_exceptions'] = <Map<String, dynamic>>[];
  final base = repo.rows('tasks').first;
  repo.snapshot!['tasks'] = [
    for (final date in [16, 17])
      for (final id in ['morning', 'evening'])
        {
          ...base,
          'id': '$id-$date',
          'title': 'Умывание с чисткой зубов',
          'description': 'Описание $id за $date октября',
          'due_at': '2026-10-${date}T23:00:00+03:00',
          'planned_start':
              '2026-10-${date}T${id == 'morning' ? '07' : '20'}:00:00+03:00',
          'planned_end':
              '2026-10-${date}T${id == 'morning' ? '07' : '20'}:15:00+03:00',
          'recurrence_id': id,
          'occurrence_date': '2026-10-$date',
        },
  ];
  return repo;
}

void main() {
  for (final role in ['parent', 'child', 'relative']) {
    testWidgets(
      'calendar opens exact previous-day task and Back preserves date: $role',
      (tester) async {
        final repo = datedTasks(role);
        addTearDown(() {
          repo.client.close();
          repo.dispose();
        });
        tester.view.physicalSize = const Size(400, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var genericOpens = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: familyTheme(role == 'child'),
            home: Scaffold(
              body: CalendarScreen(
                repository: repo,
                initialDay: DateTime.utc(2026, 10, 16, 12),
                perform: (_) async =>
                    fail('Opening a task must not change data'),
                openTasks: (_) {
                  genericOpens++;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Month mode exposes individual task tiles, including equal task titles.
        await tester.tap(find.widgetWithText(ChoiceChip, 'Месяц'));
        await tester.pumpAndSettle();
        final tile = find.byWidgetPredicate(
          (w) => w is CalendarTile && w.entry.source?['id'] == 'evening-16',
        );
        await revealField(tester, tile);
        await tester.tap(
          find.descendant(
            of: tile,
            matching: find.text('Умывание с чисткой зубов'),
          ),
        );
        await tester.pumpAndSettle();
        expect(genericOpens, 0);
        expect(find.byType(TaskScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('task-evening-16')), findsOneWidget);
        expect(find.byKey(const ValueKey('task-morning-16')), findsNothing);
        expect(find.byKey(const ValueKey('task-evening-17')), findsNothing);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('calendar-task-date')))
              .data,
          'Пт, 16.10.2026',
        );
        expect(repo.mutations, isEmpty);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ChoiceChip, 'Месяц'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is CalendarTile && w.entry.source?['id'] == 'evening-16',
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is CalendarTile && w.entry.source?['id'] == 'evening-17',
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final view in ['День', 'Неделя']) {
    testWidgets('calendar timeline opens selected task from $view', (
      tester,
    ) async {
      final repo = datedTasks('parent');
      repo.snapshot!['tasks'] = repo
          .rows('tasks')
          .where((r) => r['occurrence_date'] == '2026-10-16')
          .toList();
      addTearDown(() {
        repo.client.close();
        repo.dispose();
      });
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarScreen(
              repository: repo,
              initialDay: DateTime.utc(2026, 10, 16, 12),
              perform: (_) async => fail('Navigation must not mutate'),
              openTasks: (_) => fail('Do not open all tasks'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, view));
      await tester.pumpAndSettle();
      final entry = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            (w.properties.label?.startsWith(
                  'Умывание с чисткой зубов, 20:00',
                ) ??
                false),
      );
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: entry, matching: find.byType(InkWell)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-evening-16')), findsOneWidget);
      expect(find.byKey(const ValueKey('task-morning-16')), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 10000));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, view))
            .selected,
        isTrue,
      );
      expect(repo.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final change in ['logout', 'session', 'removed']) {
    testWidgets('focused task does not show other data after $change', (
      tester,
    ) async {
      final repo = datedTasks('parent');
      addTearDown(() {
        repo.client.close();
        repo.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskScreen(
              repository: repo,
              focusTaskId: 'evening-16',
              calendarDay: DateTime.utc(2026, 10, 16, 12),
              perform: (_) async => fail('Viewing must not mutate'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-evening-16')), findsOneWidget);
      if (change == 'logout') {
        repo.token = null;
        repo.snapshot = null;
      } else if (change == 'session') {
        repo.token = 'another-family-session';
        repo.generation++;
        repo.snapshot!['tasks'] = [
          {
            ...repo.rows('tasks').first,
            'id': 'evening-16',
            'title': 'Другая семья',
          },
        ];
      } else {
        repo.snapshot!['tasks'] = repo
            .rows('tasks')
            .where((r) => r['id'] != 'evening-16')
            .toList();
      }
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-evening-16')), findsNothing);
      expect(find.text('Другая семья'), findsNothing);
      expect(find.byKey(const ValueKey('task-morning-16')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'focused past task stays selected during refresh and disappears after cancellation',
    (tester) async {
      final repo = datedTasks('parent');
      addTearDown(() {
        repo.client.close();
        repo.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskScreen(
              repository: repo,
              focusTaskId: 'evening-16',
              calendarDay: DateTime.utc(2026, 10, 16, 12),
              perform: (_) async => fail('Viewing must not mutate'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final target = (repo.snapshot!['tasks'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((r) => r['id'] == 'evening-16');
      target['title'] = 'Исправленное название';
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Исправленное название'), findsOneWidget);
      target['status'] = 'cancelled';
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-evening-16')), findsNothing);
      expect(
        find.text('Задание отменено или больше недоступно.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
