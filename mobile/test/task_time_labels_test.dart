import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/activity_lists.dart';
import 'package:mykids_family/child_today.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/task_summary.dart';
import 'package:mykids_family/visuals.dart';

import 'task_rules_test.dart' show TaskFixture;

class TaskTimeFixture extends TaskFixture {
  late final String morningLabel, eveningLabel;
  TaskTimeFixture({String role = 'parent'})
    : super(userRole: role, withTask: true) {
    final day = dateOnly(familyClock(snapshot));
    final base = rows('tasks').single;
    Map<String, dynamic> task(String id, String hour) => {
      ...base,
      'id': id,
      'title': 'Умывание с чисткой зубов',
      'due_at': '${day}T23:00:00+03:00',
      'planned_start': '${day}T$hour:00:00+03:00',
      'planned_end': '${day}T$hour:15:00+03:00',
      'recurrence_id': id,
      'occurrence_date': day,
      'reward': 5,
      'penalty': 500,
    };
    snapshot!['tasks'] = [task('evening', '20'), task('morning', '07')];
    snapshot!['task_recurrences'] = [
      for (final id in ['morning', 'evening'])
        {
          'id': id,
          'active': 1,
          'weekdays': jsonEncode([1, 2, 3, 4, 5, 6, 7]),
          'until': null,
        },
    ];
    snapshot!['balance'] = {'available': 0};
    morningLabel = taskCompactTimeText(snapshot, rows('tasks').last);
    eveningLabel = taskCompactTimeText(snapshot, rows('tasks').first);
  }

  @override
  Future<List<Map<String, Object?>>> pending() async => [];
}

void main() {
  test('calendar time uses family timezone and includes both dates across midnight', () {
    final snapshot = {
      'family': {'timezone': 'Europe/Moscow'},
    };
    expect(
      taskCalendarTimeText(snapshot, {
        'planned_start': '2026-10-13T04:00:00Z',
        'planned_end': '2026-10-13T04:15:00Z',
      }),
      'В календаре: 13.10.2026 07:00 – 07:15',
    );
    expect(
      taskCalendarTimeText(snapshot, {
        'planned_start': '2026-10-13T20:50:00Z',
        'planned_end': '2026-10-13T21:10:00Z',
      }),
      'В календаре: 13.10.2026 23:50 – 14.10.2026 00:10',
    );
    expect(
      taskCalendarTimeText(snapshot, {'due_at': '2026-10-13T20:00:00Z'}),
      isNull,
    );
    expect(
      taskCalendarTimeText(snapshot, {'planned_start': '2026-10-13T04:00:00Z'}),
      isNull,
    );
  });

  test('task ordering compares actual instants, falls back to deadline, and preserves original data', () {
    final rows = <Map<String, dynamic>>[
      {
        'id': 'late',
        'planned_start': '2026-10-13T20:00:00+03:00',
        'due_at': '2026-10-13T23:00:00+03:00',
      },
      {'id': 'no-plan', 'due_at': '2026-10-13T18:00:00+03:00'},
      {
        'id': 'early',
        'planned_start': '2026-10-13T04:00:00Z',
        'due_at': '2026-10-13T23:00:00+03:00',
      },
    ];
    final before = jsonEncode(rows);
    final sorted = [...rows]..sort(compareTaskTime);
    expect(sorted.map((row) => row['id']), ['early', 'no-plan', 'late']);
    expect(jsonEncode(rows), before);
  });

  for (final role in ['parent', 'relative', 'child']) {
    testWidgets(
      '$role distinguishes compact cards by time and keeps the full deadline in details',
      (tester) async {
        final repo = TaskTimeFixture(role: role);
        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: familyTheme(role == 'child'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: TaskScreen(
                repository: repo,
                perform: (action) async {
                  await action();
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final scrollable = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text(repo.morningLabel),
          200,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        expect(find.text(repo.morningLabel), findsOneWidget);
        final position = tester.state<ScrollableState>(scrollable).position;
        final morningPosition =
            tester.getTopLeft(find.text(repo.morningLabel)).dy +
            position.pixels;
        final deadline =
            'Отметить в приложении до: ${familyDateTimeText(repo.snapshot, repo.rows('tasks').first['due_at'])}';
        expect(
          find.descendant(
            of: find
                .ancestor(
                  of: find.text(repo.morningLabel),
                  matching: find.byType(TaskCompactCard),
                )
                .first,
            matching: find.textContaining(deadline),
          ),
          findsNothing,
        );
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('task-morning')),
            matching: find.text('Подробнее'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(deadline), findsOneWidget);
        await tester.tap(find.text('Скрыть подробности'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(repo.eveningLabel),
          200,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        expect(find.text(repo.eveningLabel), findsOneWidget);
        expect(
          morningPosition,
          lessThan(
            tester.getTopLeft(find.text(repo.eveningLabel)).dy +
                position.pixels,
          ),
        );
        expect(
          find.descendant(
            of: find
                .ancestor(
                  of: find.text(repo.eveningLabel),
                  matching: find.byType(TaskCompactCard),
                )
                .first,
            matching: find.textContaining(deadline),
          ),
          findsNothing,
        );
        expect(find.text('Редактировать задание'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        repo.client.close();
        repo.dispose();
      },
    );
  }

  testWidgets(
    'Today shows both calendar intervals for parent and child without changing child section order',
    (tester) async {
      for (final role in ['parent', 'child']) {
        final repo = TaskTimeFixture(role: role);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: role == 'child'
                  ? ChildToday(repository: repo, openPage: (_) {})
                  : ListView(
                      children: [
                        TodayTaskList(repository: repo, onOpen: () {}),
                      ],
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(repo.morningLabel), findsOneWidget);
        expect(find.text(repo.eveningLabel), findsOneWidget);
        if (role == 'child') {
          expect(
            tester.getTopLeft(find.text('Твой день')).dy,
            lessThan(tester.getTopLeft(find.text('Мои задания')).dy),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        repo.client.close();
        repo.dispose();
      }
    },
  );
}
