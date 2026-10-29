import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/schedule.dart';
import 'package:timezone/timezone.dart' as tz;

import 'calendar_navigation_test.dart' show mountCalendar, tapVisible;
import 'task_rules_test.dart' show TaskFixture, reveal, showTasks;

tz.TZDateTime selectedDay(TaskFixture repo, int offset) {
  final now = familyClock(repo.snapshot);
  return tz.TZDateTime(now.location, now.year, now.month, now.day + offset, 12);
}

Map<String, dynamic> defaults(WidgetTester tester) => {
  for (final field in tester.widget<FamilyForm>(find.byType(FamilyForm)).fields)
    field.key: field.initial,
};

Future<void> openNewTask(
  WidgetTester tester,
  TaskFixture repo,
  DateTime day, {
  String view = 'Месяц',
  bool nextDay = false,
}) async {
  await mountCalendar(tester, repo, day: day);
  await tester.tap(find.widgetWithText(ChoiceChip, view));
  await tester.pumpAndSettle();
  await tapVisible(tester, find.text('Семейные задания'));
  if (nextDay) {
    await tester.tap(find.byTooltip('Следующий день задания'));
    await tester.pumpAndSettle();
  }
  await tapVisible(tester, find.text('Добавить задание'));
}

Future<void> fillRequired(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('field-title')),
    'Задание на выбранную дату',
  );
  await reveal(tester, find.byKey(const ValueKey('field-penalty')));
  await tester.enterText(find.byKey(const ValueKey('field-penalty')), '1');
}

Future<void> saveTask(WidgetTester tester) async {
  await reveal(tester, find.text('Сохранить'));
  await tester.tap(find.text('Сохранить'));
  await tester.pumpAndSettle();
}

Future<void> pickDate(WidgetTester tester, DateTime day) async {
  final picker = tester.widget<CalendarDatePicker>(
    find.byType(CalendarDatePicker),
  );
  picker.onDateChanged(DateTime(day.year, day.month, day.day));
  await tester.pumpAndSettle();
  final ok = MaterialLocalizations.of(
    tester.element(find.byType(DatePickerDialog)),
  ).okButtonLabel;
  await tester.tap(find.text(ok));
  await tester.pumpAndSettle();
}

Future<void> repeatingEvent(
  WidgetTester tester,
  TaskFixture repo,
  DateTime day,
) async {
  await mountCalendar(tester, repo, day: day);
  await tapVisible(tester, find.text('Добавить событие'));
  await tester.enterText(find.byKey(const ValueKey('event-title')), 'Кружок');
  await tapVisible(tester, find.text('Повторение'));
  await tapVisible(tester, find.text('Повторять по дням недели'));
}

void main() {
  for (final role in ['parent', 'relative']) {
    for (final view in ['День', 'Неделя', 'Месяц']) {
      testWidgets(
        '$role creates planned task on the selected past date from $view',
        (tester) async {
          final repo = TaskFixture(userRole: role);
          final day = selectedDay(repo, -2);
          await openNewTask(tester, repo, day, view: view);
          final fields = defaults(tester);
          for (final key in [
            'due_at',
            'planned_start',
            'planned_end',
            'repeat_starts_on',
          ]) {
            expect(
              dateOnly(fields[key] as DateTime),
              dateOnly(day),
              reason: key,
            );
          }
          expect((fields['due_at'] as DateTime).hour, 20);
          expect((fields['planned_start'] as DateTime).hour, 17);
          expect((fields['planned_end'] as DateTime).hour, 18);
          await reveal(tester, find.text('Назначить время в календаре'));
          await tester.tap(find.text('Назначить время в календаре'));
          await tester.pumpAndSettle();
          await fillRequired(tester);
          await saveTask(tester);
          expect(repo.mutations, hasLength(1));
          final body = repo.mutations.single;
          for (final key in ['due_at', 'planned_start', 'planned_end']) {
            expect(
              dateOnly(
                familyClock(repo.snapshot, DateTime.parse(body[key] as String)),
              ),
              dateOnly(day),
              reason: key,
            );
          }
          expect(body['path'], '/v1/tasks');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final zone in [
    'Europe/Moscow',
    'America/Los_Angeles',
    'Pacific/Kiritimati',
  ]) {
    testWidgets(
      'future task uses changed list date and family timezone: $zone',
      (tester) async {
        final repo = TaskFixture();
        repo.snapshot!['family']['timezone'] = zone;
        final day = selectedDay(repo, 40);
        final changed = tz.TZDateTime(
          day.location,
          day.year,
          day.month,
          day.day + 1,
          12,
        );
        await openNewTask(tester, repo, day, nextDay: true);
        final fields = defaults(tester);
        for (final key in [
          'due_at',
          'planned_start',
          'planned_end',
          'repeat_starts_on',
        ]) {
          expect(
            dateOnly(fields[key] as DateTime),
            dateOnly(changed),
            reason: key,
          );
        }
        expect(
          dateOnly(fields['repeat_until'] as DateTime),
          dateOnly(
            tz.TZDateTime(
              day.location,
              changed.year,
              changed.month,
              changed.day + 30,
            ),
          ),
        );
        await fillRequired(tester);
        await saveTask(tester);
        expect(
          dateOnly(
            familyClock(
              repo.snapshot,
              DateTime.parse(repo.mutations.single['due_at'] as String),
            ),
          ),
          dateOnly(changed),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('future repeating task starts and plans work on selected date', (
    tester,
  ) async {
    final repo = TaskFixture();
    final day = selectedDay(repo, 40);
    await openNewTask(tester, repo, day);
    await reveal(tester, find.text('Повторять по дням недели'));
    await tester.tap(find.text('Повторять по дням недели'));
    await tester.pumpAndSettle();
    expect(
      find.text('Начинать с: ${day.day}.${day.month}.${day.year}'),
      findsOneWidget,
    );
    await reveal(tester, find.text('Указать последний день повторения'));
    await tester.tap(find.text('Указать последний день повторения'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Назначить время в календаре'));
    await tester.tap(find.text('Назначить время в календаре'));
    await tester.pumpAndSettle();
    await fillRequired(tester);
    await saveTask(tester);
    final body = repo.mutations.single;
    for (final key in ['due_at', 'planned_start', 'planned_end']) {
      expect(
        dateOnly(
          familyClock(repo.snapshot, DateTime.parse(body[key] as String)),
        ),
        dateOnly(day),
        reason: key,
      );
    }
    expect(
      body['repeat_until'],
      dateOnly(tz.TZDateTime(day.location, day.year, day.month, day.day + 30)),
    );
    expect(body['weekdays'], [1, 2, 3, 4, 5, 6, 7]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'past repeat stays on chosen date and retains the existing validation',
    (tester) async {
      final repo = TaskFixture();
      final day = selectedDay(repo, -2);
      await openNewTask(tester, repo, day);
      await tester.enterText(
        find.byKey(const ValueKey('field-title')),
        'Повтор',
      );
      await reveal(tester, find.text('Повторять по дням недели'));
      await tester.tap(find.text('Повторять по дням недели'));
      await tester.pumpAndSettle();
      expect(
        find.text('Начинать с: ${day.day}.${day.month}.${day.year}'),
        findsOneWidget,
      );
      await fillRequired(tester);
      await saveTask(tester);
      expect(repo.mutations, isEmpty);
      expect(
        find.text('Начните повторение с сегодняшнего дня или будущей даты'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('ordinary task creation keeps its existing defaults', (
    tester,
  ) async {
    final repo = TaskFixture();
    addTearDown(() {
      repo.client.close();
      repo.dispose();
    });
    final now = familyClock(repo.snapshot);
    await showTasks(tester, repo);
    await tester.tap(find.text('Добавить задание'));
    await tester.pumpAndSettle();
    final fields = defaults(tester);
    expect(
      dateOnly(fields['due_at'] as DateTime),
      dateOnly(now.add(const Duration(days: 1))),
    );
    expect(dateOnly(fields['repeat_starts_on'] as DateTime), dateOnly(now));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final view in ['День', 'Неделя', 'Месяц']) {
    for (final offset in [-2, 40]) {
      testWidgets('$view creates event on selected date offset $offset', (
        tester,
      ) async {
        final repo = TaskFixture();
        final day = selectedDay(repo, offset);
        await mountCalendar(tester, repo, day: day);
        await tester.tap(find.widgetWithText(ChoiceChip, view));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Добавить событие'));
        expect(find.text('Дата: ${calendarDateLabel(day)}'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('event-title')),
          'Событие на выбранный день',
        );
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        expect(repo.mutations.single['date'], dateOnly(day));
        expect(repo.mutations.single['path'], '/v1/schedules');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('new recurring event begins on the selected calendar date', (
    tester,
  ) async {
    final repo = TaskFixture();
    final day = selectedDay(repo, 40);
    await mountCalendar(tester, repo, day: day);
    await tapVisible(tester, find.text('Добавить событие'));
    await tester.enterText(find.byKey(const ValueKey('event-title')), 'Кружок');
    await tapVisible(tester, find.text('Повторение'));
    await tapVisible(tester, find.text('Повторять по дням недели'));
    expect(find.text('С даты: ${dateOnly(day)}'), findsOneWidget);
    await tapVisible(
      tester,
      find.widgetWithText(FilterChip, calendarWeekdays[day.weekday - 1]),
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repo.mutations.single['date'], isNull);
    expect(repo.mutations.single['starts_on'], dateOnly(day));
    expect(repo.mutations.single['weekdays'], [day.weekday]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final zone in ['America/Los_Angeles', 'Pacific/Kiritimati']) {
    testWidgets(
      'recurring event allows the same first and last civil date: $zone',
      (tester) async {
        final repo = TaskFixture();
        repo.snapshot!['family']['timezone'] = zone;
        final day = selectedDay(repo, 40);
        await repeatingEvent(tester, repo, day);
        await tapVisible(
          tester,
          find.widgetWithText(FilterChip, calendarWeekdays[day.weekday - 1]),
        );
        await tapVisible(tester, find.byKey(const ValueKey('event-until')));
        await pickDate(tester, day);
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        expect(repo.mutations, hasLength(1));
        expect(repo.mutations.single['starts_on'], dateOnly(day));
        expect(repo.mutations.single['until'], dateOnly(day));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'changing a new event date also moves its default repetition start',
    (tester) async {
      final repo = TaskFixture();
      final day = selectedDay(repo, 40);
      final changed = tz.TZDateTime(
        day.location,
        day.year,
        day.month,
        day.day + 1,
        12,
      );
      await mountCalendar(tester, repo, day: day);
      await tapVisible(tester, find.text('Добавить событие'));
      await tapVisible(tester, find.text('Дата: ${calendarDateLabel(day)}'));
      await pickDate(tester, changed);
      await tapVisible(tester, find.text('Повторение'));
      await tapVisible(tester, find.text('Повторять по дням недели'));
      expect(find.text('С даты: ${dateOnly(changed)}'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('recurring event still rejects an end date before its start', (
    tester,
  ) async {
    final repo = TaskFixture();
    final day = selectedDay(repo, 40);
    await repeatingEvent(tester, repo, day);
    await tapVisible(
      tester,
      find.widgetWithText(FilterChip, calendarWeekdays[day.weekday - 1]),
    );
    await tapVisible(tester, find.byKey(const ValueKey('event-until')));
    await pickDate(
      tester,
      tz.TZDateTime(day.location, day.year, day.month, day.day - 1),
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repo.mutations, isEmpty);
    expect(
      find.text('Конечная дата повторения должна быть не раньше начальной'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'explicitly removing the new event repetition start stays unlimited',
    (tester) async {
      final repo = TaskFixture();
      final day = selectedDay(repo, 40);
      await repeatingEvent(tester, repo, day);
      await tapVisible(tester, find.text('Сбросить ограничение').first);
      expect(find.text('С даты: без ограничения'), findsOneWidget);
      await tapVisible(tester, find.text('Повторять по дням недели'));
      await tapVisible(tester, find.text('Повторять по дням недели'));
      expect(find.text('С даты: без ограничения'), findsOneWidget);
      await tapVisible(
        tester,
        find.widgetWithText(FilterChip, calendarWeekdays[day.weekday - 1]),
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.mutations.single['starts_on'], isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final offset in [0, -7]) {
    testWidgets(
      'explicit repetition start survives a main date change: $offset',
      (tester) async {
        final repo = TaskFixture();
        final day = selectedDay(repo, 40);
        final explicit = tz.TZDateTime(
          day.location,
          day.year,
          day.month,
          day.day + offset,
          12,
        );
        final changed = tz.TZDateTime(
          day.location,
          day.year,
          day.month,
          day.day + 1,
          12,
        );
        await repeatingEvent(tester, repo, day);
        await tapVisible(tester, find.byKey(const ValueKey('event-starts-on')));
        await pickDate(tester, explicit);
        await tapVisible(tester, find.text('Дата: ${calendarDateLabel(day)}'));
        await pickDate(tester, changed);
        await tapVisible(tester, find.byKey(const ValueKey('event-starts-on')));
        expect(
          tester
              .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
              .initialDate,
          DateTime(explicit.year, explicit.month, explicit.day),
        );
        await tester.tap(
          find.text(
            MaterialLocalizations.of(
              tester.element(find.byType(DatePickerDialog)),
            ).cancelButtonLabel,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('С даты: ${dateOnly(explicit)}'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'editing an existing unlimited repetition does not add a start date',
    (tester) async {
      final repo = TaskFixture();
      final day = selectedDay(repo, 40);
      repo.snapshot!['schedules'] = [
        {
          'id': 'existing',
          'title': 'Прежнее событие',
          'date': null,
          'weekdays': '[${day.weekday}]',
          'start': '09:00',
          'end': '10:00',
          'kind': 'other',
          'active': 1,
          'starts_on': null,
        },
      ];
      await mountCalendar(tester, repo, day: day);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Месяц'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Прежнее событие'));
      await tapVisible(tester, find.text('Изменить событие и повторения'));
      await tapVisible(tester, find.byKey(const ValueKey('event-starts-on')));
      await tester.tap(
        find.text(
          MaterialLocalizations.of(
            tester.element(find.byType(DatePickerDialog)),
          ).cancelButtonLabel,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('С даты: без ограничения'), findsOneWidget);
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.mutations.single['path'], '/v1/schedules/existing');
      expect(repo.mutations.single['starts_on'], isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('an empty cell in another week day prefills its date and hour', (
    tester,
  ) async {
    final repo = TaskFixture();
    final day = selectedDay(repo, 40);
    final target = tz.TZDateTime(
      day.location,
      day.year,
      day.month,
      day.day - day.weekday + (day.weekday == 2 ? 3 : 2),
      12,
    );
    await mountCalendar(tester, repo, day: day);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Неделя'));
    await tester.pumpAndSettle();
    final cell = find.byKey(ValueKey('calendar-cell-${dateOnly(target)}-15'));
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(find.text('Дата: ${calendarDateLabel(target)}'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('event-title')),
      'Встреча',
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repo.mutations.single['date'], dateOnly(target));
    expect(repo.mutations.single['start'], '15:00');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
