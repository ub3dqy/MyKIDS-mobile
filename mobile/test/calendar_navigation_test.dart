import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/school_screen.dart';
import 'package:mykids_family/task_screen.dart';

import 'calendar_task_navigation_test.dart' show datedTasks;
import 'field_layout_test.dart' show mountFields, revealField;
import 'support/calendar_results_fixture.dart';

Future<void> mountCalendar(
  WidgetTester tester,
  FamilyRepository repo, {
  DateTime? day,
  ValueNotifier<DateTime>? focus,
  Future<void> Function(Future<Map<String, dynamic>> Function())? perform,
}) async {
  addTearDown(() {
    repo.client.close();
    repo.dispose();
  });
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Future<void> run(Future<Map<String, dynamic>> Function() action) async {
    if (perform != null) {
      await perform(action);
    } else {
      fail('Navigation must not mutate');
    }
  }

  Widget calendar(BuildContext context, DateTime selected) => CalendarScreen(
    repository: repo,
    initialDay: selected,
    perform: run,
    openTasks: (selected) => openCalendarTasks(context, repo, run, selected),
  );

  await mountFields(
    tester,
    Scaffold(
      body: Builder(
        builder: (context) => focus == null
            ? calendar(context, day ?? DateTime.utc(2026, 10, 16, 12))
            : ValueListenableBuilder<DateTime>(
                valueListenable: focus,
                builder: (context, selected, _) => calendar(context, selected),
              ),
      ),
    ),
    scale: 1,
    screenSize: const Size(400, 1400),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await revealField(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final role in ['parent', 'child', 'relative']) {
    for (final view in ['День', 'Неделя', 'Месяц']) {
      testWidgets('$view family tasks keeps selected date and Back for $role', (
        tester,
      ) async {
        final repo = datedTasks(role);
        await mountCalendar(tester, repo);
        await tester.tap(find.widgetWithText(ChoiceChip, view));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Семейные задания'));
        expect(find.text('Пт, 16.10.2026'), findsOneWidget);
        expect(find.byKey(const ValueKey('task-evening-16')), findsOneWidget);
        expect(find.byKey(const ValueKey('task-morning-16')), findsOneWidget);
        expect(find.byKey(const ValueKey('task-evening-17')), findsNothing);
        await tester.tap(find.byTooltip('Следующий день задания'));
        await tester.pumpAndSettle();
        expect(find.text('Сб, 17.10.2026'), findsOneWidget);
        expect(find.byKey(const ValueKey('task-evening-17')), findsOneWidget);
        expect(find.byKey(const ValueKey('task-evening-16')), findsNothing);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, 10000),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, view))
              .selected,
          isTrue,
        );
        // Reopening uses the calendar date, not the date changed in the task list.
        await tapVisible(tester, find.text('Семейные задания'));
        expect(find.text('Пт, 16.10.2026'), findsOneWidget);
        expect(find.byKey(const ValueKey('task-evening-16')), findsOneWidget);
        expect(repo.mutations, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
    'dated task list includes one-off, overlapping and deadline tasks',
    (tester) async {
      final repo = datedTasks('parent');
      final base = repo.rows('tasks').first;
      repo.snapshot!['task_recurrences'] = <Map<String, dynamic>>[];
      repo.snapshot!['tasks'] = [
        {...base, 'id': 'one-off', 'recurrence_id': null},
        {
          ...base,
          'id': 'overlap',
          'planned_start': '2026-10-15T23:00:00+03:00',
          'planned_end': '2026-10-17T00:00:00+03:00',
          'due_at': '2026-10-18T20:00:00+03:00',
        },
        {
          ...base,
          'id': 'deadline',
          'planned_start': '2026-10-15T07:00:00+03:00',
          'planned_end': '2026-10-15T07:15:00+03:00',
        },
        {...base, 'id': 'cancelled', 'status': 'cancelled'},
        {
          ...base,
          'id': 'other-day',
          'recurrence_id': null,
          'due_at': '2026-10-18T20:00:00+03:00',
          'planned_start': null,
          'planned_end': null,
        },
      ];
      await mountCalendar(tester, repo);
      await tapVisible(tester, find.text('Семейные задания'));
      for (final id in ['one-off', 'overlap', 'deadline']) {
        expect(find.byKey(ValueKey('task-$id')), findsOneWidget);
      }
      for (final id in ['other-day', 'cancelled']) {
        expect(find.byKey(ValueKey('task-$id')), findsNothing);
      }
      // Date navigation remains available even without recurring tasks.
      expect(find.byTooltip('Следующий день задания'), findsOneWidget);
      await tester.tap(find.byTooltip('Предыдущий день задания'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Предыдущий день задания'));
      await tester.pumpAndSettle();
      expect(find.text('На выбранную дату заданий нет.'), findsOneWidget);
      expect(find.byKey(const ValueKey('task-other-day')), findsNothing);
      expect(repo.mutations, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('future date and family timezone survive task list arrows', (
    tester,
  ) async {
    final repo = datedTasks('parent');
    repo.snapshot!['family']['timezone'] = 'America/Los_Angeles';
    final base = repo.rows('tasks').first;
    repo.snapshot!['tasks'] = [
      for (final date in [20, 21])
        {
          ...base,
          'id': 'future-$date',
          'due_at': '2026-10-${date}T00:30:00-07:00',
          'planned_start': null,
          'planned_end': null,
        },
    ];
    await mountCalendar(tester, repo, day: DateTime.utc(2026, 10, 20, 12));
    await tapVisible(tester, find.text('Семейные задания'));
    expect(find.text('Вт, 20.10.2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-future-20')), findsOneWidget);
    await tester.tap(find.byTooltip('Следующий день задания'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-future-20')), findsNothing);
    expect(find.byKey(const ValueKey('task-future-21')), findsOneWidget);
    expect(find.text('Ср, 21.10.2026'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('month date selection reaches the same day in tasks and grades', (
    tester,
  ) async {
    final repo = datedTasks('parent');
    await mountCalendar(tester, repo);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Месяц'));
    await tester.pumpAndSettle();
    await tapVisible(
      tester,
      find.byKey(const ValueKey('calendar-day-2026-10-17')),
    );
    await tapVisible(tester, find.text('Семейные задания'));
    expect(find.text('Сб, 17.10.2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-evening-17')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-evening-16')), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Предметы и оценки'));
    expect(find.text('Сб, 17.10.2026'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('result-task:evening-17')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('result-task:evening-16')), findsNothing);
    expect(repo.mutations, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final change in ['refresh', 'cancel', 'session', 'logout']) {
    testWidgets('dated task list handles $change without opening today', (
      tester,
    ) async {
      final repo = datedTasks('parent');
      await mountCalendar(tester, repo);
      await tapVisible(tester, find.text('Семейные задания'));
      if (change == 'refresh') {
        repo.snapshot!['tasks'] = repo
            .rows('tasks')
            .map((row) => {...row, 'title': 'Обновлено ${row['id']}'})
            .toList();
      } else if (change == 'cancel') {
        repo.snapshot!['tasks'] = repo
            .rows('tasks')
            .map(
              (row) => {
                ...row,
                if (row['occurrence_date'] == '2026-10-16')
                  'status': 'cancelled',
              },
            )
            .toList();
      } else if (change == 'session') {
        repo.token = 'another-family';
        repo.generation++;
      } else {
        repo.token = null;
        repo.snapshot = null;
      }
      repo.notifyListeners();
      await tester.pumpAndSettle();
      if (change == 'refresh') {
        expect(find.text('Обновлено evening-16'), findsOneWidget);
      } else {
        expect(find.byKey(const ValueKey('task-evening-16')), findsNothing);
      }
      expect(find.byKey(const ValueKey('task-evening-17')), findsNothing);
      expect(repo.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final role in ['parent', 'child', 'relative']) {
    testWidgets(
      'calendar grades and child photo task preserve date for $role',
      (tester) async {
        final repo = datedTasks(role);
        repo.snapshot!['schedules'] = [
          {
            ...ResultsFixture.schoolEvent(),
            'weekdays': '[5]',
            'title': 'Математика',
            'activities': '[]',
          },
        ];
        repo.snapshot!['tasks'] = repo
            .rows('tasks')
            .map((row) => {...row, 'require_photo': 1})
            .toList();
        await mountCalendar(tester, repo);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Месяц'));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Предметы и оценки'));
        expect(find.byType(SchoolScreen), findsOneWidget);
        expect(find.text('Пт, 16.10.2026'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('result-task:evening-16')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('result-task:evening-17')),
          findsNothing,
        );
        if (role == 'child') {
          final result = find.byKey(const ValueKey('result-task:evening-16'));
          await tapVisible(
            tester,
            find.descendant(
              of: result,
              matching: find.text('Отправить результат с фотографией'),
            ),
          );
          expect(find.byKey(const ValueKey('task-evening-16')), findsOneWidget);
          expect(find.byKey(const ValueKey('task-morning-16')), findsNothing);
          expect(find.byKey(const ValueKey('task-evening-17')), findsNothing);
          expect(find.text('Пт, 16.10.2026'), findsOneWidget);
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(find.text('Пт, 16.10.2026'), findsOneWidget);
        }
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Предметы и оценки'));
        expect(find.text('Пт, 16.10.2026'), findsOneWidget);
        expect(repo.mutations, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('grade editor saves the calendar date and returns to that day', (
    tester,
  ) async {
    final repo = ResultsFixture();
    await mountCalendar(tester, repo, day: DateTime.utc(2026, 10, 12, 12));
    await tapVisible(tester, find.text('Предметы и оценки'));
    await tapVisible(
      tester,
      find.byKey(
        const ValueKey('result-grade-schedule:school:2026-10-12:$mathIdentity'),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Сохранить'));
    expect(repo.changes.single['body']['date'], '2026-10-12');
    expect(repo.changes.single['body']['activity_id'], mathIdentity);
    expect(find.byType(FamilyForm), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Предметы и оценки'));
    expect(find.text('Пн, 12.10.2026'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final operation in ['create', 'edit', 'single', 'cancel']) {
    testWidgets(
      'event $operation pins clicked date while calendar focus changes',
      (tester) async {
        final repo = ResultsFixture();
        repo.snapshot!['tasks'] = <Map<String, dynamic>>[];
        repo.snapshot!['schedules'] = [
          for (final id in ['other', 'chosen'])
            {
              ...ResultsFixture.schoolEvent(),
              'id': id,
              'title': 'Одинаковые события',
              'kind': 'other',
              'start': id == 'chosen' ? '15:00' : '09:00',
              'end': id == 'chosen' ? '16:00' : '10:00',
              'activities': '[]',
              'revision': 'a' * 64,
            },
        ];
        final focus = ValueNotifier(DateTime.utc(2026, 10, 12, 12));
        addTearDown(focus.dispose);
        await mountCalendar(
          tester,
          repo,
          focus: focus,
          perform: (action) async {
            await action();
          },
        );
        if (operation == 'create') {
          await tapVisible(tester, find.text('Добавить событие'));
          await tester.enterText(
            find.byType(TextFormField).first,
            'Новое событие',
          );
        } else {
          await tester.tap(find.widgetWithText(ChoiceChip, 'Месяц'));
          await tester.pumpAndSettle();
          final tile = find.byWidgetPredicate(
            (w) => w is CalendarTile && w.entry.source?['id'] == 'chosen',
          );
          await tapVisible(tester, tile);
          final label = switch (operation) {
            'edit' => 'Изменить событие и повторения',
            'single' => 'Изменить только этот день',
            _ => 'Отменить только этот день',
          };
          await tapVisible(tester, find.text(label));
        }
        if (operation == 'cancel') {
          expect(find.text('Отменить на Пн, 12.10.2026?'), findsOneWidget);
        } else {
          expect(
            dateOnly(
              tester.widget<CalendarEditor>(find.byType(CalendarEditor)).day,
            ),
            '2026-10-12',
          );
        }
        focus.value = DateTime.utc(2026, 10, 13, 12);
        await tester.pumpAndSettle();
        await tapVisible(
          tester,
          find.text(operation == 'cancel' ? 'Подтвердить' : 'Сохранить'),
        );
        expect(repo.changes, hasLength(1));
        final change = repo.changes.single;
        expect(
          change['path'],
          operation == 'create'
              ? '/v1/schedules'
              : '/v1/schedules/chosen${operation == 'edit' ? '' : '/exceptions'}',
        );
        if (operation != 'edit') {
          expect(change['body']['date'], '2026-10-12');
        }
        if (operation == 'single') {
          expect(change['body']['replacement']['date'], '2026-10-12');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
