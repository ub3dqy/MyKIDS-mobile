import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';
import 'package:timezone/timezone.dart' as tz;

import 'calendar_creation_date_test.dart' show fillRequired, pickDate, saveTask;
import 'calendar_navigation_test.dart' show tapVisible;
import 'calendar_test.dart' as calendar_fixture;
import 'resume_refresh_test.dart' show NoResumeUpdates, ResumeBackground;
import 'task_rules_test.dart' show TaskFixture;

class KeepDateFixture extends TaskFixture {
  final DateTime selected;
  bool failNext = false;
  KeepDateFixture(this.selected, {super.userRole}) : super(withTask: true) {
    endpoint = 'https://family.example';
    snapshot!['user']['name'] = 'Проверка';
    snapshot!['server_time'] = 'synthetic';
    snapshot!['schedules'] = [
      {
        ...calendar_fixture.event('Событие для изменения', '11:00', '12:00'),
        'date': dateOnly(selected),
        'kind': 'other',
        'revision': 1,
      },
    ];
    snapshot!['schedule_exceptions'] = <Map<String, dynamic>>[];
    (snapshot!['tasks'] as List).first['due_at'] = DateTime.utc(
      selected.year,
      selected.month,
      selected.day,
      17,
    ).toIso8601String();
  }

  @override
  Future<void> sync() async => notifyListeners();

  @override
  Future<void> reconnect() => sync();

  @override
  Future<List<Map<String, Object?>>> pending() async => [];

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    if (failNext) {
      failNext = false;
      throw ApiFailure(422, 'Проверочное сохранение отклонено');
    }
    mutations.add({'path': path, 'method': method, ...body});
    if (path.startsWith('/v1/tasks')) {
      final tasks = snapshot!['tasks'] as List;
      final row = method == 'PUT'
          ? tasks.first as Map<String, dynamic>
          : (Map<String, dynamic>.from(tasks.first as Map)
              ..['id'] = 'new-task');
      row.addAll(body);
      for (final key in ['is_required', 'require_photo']) {
        row[key] = body[key] == true ? 1 : 0;
      }
      row['version'] = (row['version'] as int) + 1;
      if (method == 'POST') tasks.add(row);
    } else {
      final schedules = snapshot!['schedules'] as List;
      final row = {
        ...body,
        'id': method == 'POST' ? 'new-event' : schedules.first['id'],
        'active': 1,
        'revision': 2,
        'weekdays': jsonEncode(body['weekdays']),
        'activities': jsonEncode(body['activities']),
      };
      if (method == 'POST') {
        schedules.add(row);
      } else {
        schedules[0] = row;
      }
    }
    notifyListeners();
    return {'id': 'saved'};
  }
}

class KeepDateBackground extends ResumeBackground {
  KeepDateBackground(super.repository);

  @override
  Future<void> initialize(void Function(String?) onTap) async {
    openNotification = onTap;
  }
}

Future<KeepDateBackground> openCalendarApp(
  WidgetTester tester,
  KeepDateFixture repo,
) async {
  tester.view.physicalSize = const Size(440, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final background = KeepDateBackground(repo);
  await tester.pumpWidget(
    MyKidsApp(
      repository: repo,
      createBackground: (_) => background,
      createUpdates: NoResumeUpdates.new,
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
  });
  await tester.pumpAndSettle();
  await tester.tap(find.text('Календарь').last);
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(
      TextButton,
      calendarDateLabel(familyClock(repo.snapshot)),
    ),
  );
  await tester.pumpAndSettle();
  await pickDate(tester, repo.selected);
  return background;
}

Future<void> expectSelected(
  WidgetTester tester,
  DateTime day,
  String view,
) async {
  expect(
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, view)).selected,
    isTrue,
  );
  final period = find
      .ancestor(
        of: find.byTooltip('Предыдущий период'),
        matching: find.byType(Row),
      )
      .first;
  await tapVisible(
    tester,
    find.descendant(of: period, matching: find.byType(TextButton)),
  );
  final picker = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
  expect(dateOnly(picker.initialDate!), dateOnly(day));
  final cancel = MaterialLocalizations.of(
    tester.element(find.byType(DatePickerDialog)),
  ).cancelButtonLabel;
  await tester.tap(find.text(cancel));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  for (final view in ['День', 'Неделя', 'Месяц']) {
    for (final action in ['add task', 'edit task', 'add event', 'edit event']) {
      for (final role
          in action.endsWith('task') ? ['parent', 'relative'] : ['parent']) {
        testWidgets(
          '$role $view keeps selected date after $action and section return',
          (tester) async {
            final now = familyClock({
              'family': {'timezone': 'Europe/Moscow'},
            });
            final selected = tz.TZDateTime(
              now.location,
              now.year,
              now.month,
              now.day + (role == 'parent' ? 8 : -8),
            );
            final repo = KeepDateFixture(selected, userRole: role);
            await openCalendarApp(tester, repo);
            await tester.tap(find.widgetWithText(ChoiceChip, view));
            await tester.pumpAndSettle();
            if (action.endsWith('task')) {
              await tapVisible(tester, find.text('Семейные задания'));
              if (action.startsWith('add')) {
                await tapVisible(tester, find.text('Добавить задание'));
                await fillRequired(tester);
              } else {
                await tapVisible(tester, find.text('Убрать игрушки'));
                await tapVisible(tester, find.text('Редактировать задание'));
                await tester.enterText(
                  find.byKey(const ValueKey('field-title')),
                  'Изменённое задание',
                );
              }
              await saveTask(tester);
              await tester.tap(find.byType(BackButton));
              await tester.pumpAndSettle();
            } else {
              if (action.startsWith('add')) {
                await tapVisible(tester, find.text('Добавить событие'));
              } else {
                if (view == 'Месяц') {
                  await tapVisible(tester, find.text('Событие для изменения'));
                } else {
                  await tapVisible(
                    tester,
                    find.byWidgetPredicate(
                      (w) =>
                          w is Semantics &&
                          (w.properties.label?.startsWith(
                                'Событие для изменения,',
                              ) ??
                              false),
                    ),
                  );
                }
                await tapVisible(tester, find.text('Изменить событие'));
              }
              await tester.enterText(
                find.byKey(const ValueKey('event-title')),
                'Сохранённое событие',
              );
              await tapVisible(tester, find.text('Сохранить'));
            }
            expect(repo.mutations, hasLength(1));
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, 10000),
            );
            await tester.pumpAndSettle();
            // Saving and the repository refresh must preserve the visible selection.
            await expectSelected(tester, selected, view);
            // Returning from another section must preserve that same calendar too.
            await tester.tap(find.text('Задания').last);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Календарь').last);
            await tester.pumpAndSettle();
            await expectSelected(tester, selected, view);
          },
        );
      }
    }
  }

  for (final hidden in [false, true]) {
    for (final zone in ['America/Los_Angeles', 'Pacific/Kiritimati']) {
      testWidgets(
        'civil date survives timezone refresh in $zone, hidden: $hidden',
        (tester) async {
          final selected = DateTime.utc(2026, 10, 12, 12);
          final repo = KeepDateFixture(selected);
          await openCalendarApp(tester, repo);
          await tester.tap(find.widgetWithText(ChoiceChip, 'Месяц'));
          await tester.pumpAndSettle();
          if (hidden) {
            await tester.tap(find.text('Задания').last);
            await tester.pumpAndSettle();
          }
          repo.snapshot!['family']['timezone'] = zone;
          repo.notifyListeners();
          await tester.pumpAndSettle();
          if (hidden) {
            await tester.tap(find.text('Календарь').last);
            await tester.pumpAndSettle();
          }
          await expectSelected(tester, selected, 'Месяц');
        },
      );
    }
  }

  for (final task in [false, true]) {
    testWidgets(
      'moving an entry keeps the original calendar selection, task: $task',
      (tester) async {
        final selected = DateTime.utc(2026, 10, 12, 12);
        final moved = DateTime.utc(2026, 11, 20, 12);
        final repo = KeepDateFixture(selected);
        await openCalendarApp(tester, repo);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Месяц'));
        await tester.pumpAndSettle();
        if (task) {
          await tapVisible(tester, find.text('Семейные задания'));
          await tapVisible(tester, find.text('Убрать игрушки'));
          await tapVisible(tester, find.text('Редактировать задание'));
          await tapVisible(
            tester,
            find.byWidgetPredicate(
              (w) =>
                  w is OutlinedButton &&
                  w.child is Text &&
                  ((w.child as Text).data?.startsWith('Срок выполнения:') ??
                      false),
            ),
          );
        } else {
          await tapVisible(tester, find.text('Событие для изменения'));
          await tapVisible(tester, find.text('Изменить событие'));
          await tapVisible(
            tester,
            find.text('Дата: ${calendarDateLabel(selected)}'),
          );
        }
        await pickDate(tester, moved);
        if (task) {
          final ok = MaterialLocalizations.of(
            tester.element(find.byType(TimePickerDialog)),
          ).okButtonLabel;
          await tester.tap(find.text(ok));
          await tester.pumpAndSettle();
        }
        await tapVisible(tester, find.text('Сохранить'));
        if (task) {
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
        }
        final savedDay = task
            ? dateOnly(
                familyClock(
                  repo.snapshot,
                  DateTime.parse(repo.mutations.single['due_at'] as String),
                ),
              )
            : repo.mutations.single['date'];
        expect(savedDay, dateOnly(moved));
        await expectSelected(tester, selected, 'Месяц');
      },
    );
  }

  testWidgets(
    'Today is explicit and remembered, notification still opens its own day',
    (tester) async {
      final repo = KeepDateFixture(DateTime.utc(2026, 10, 12, 12));
      final background = await openCalendarApp(tester, repo);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Месяц'));
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.descendant(
          of: find.byType(CalendarScreen),
          matching: find.text('Сегодня'),
        ),
      );
      final today = familyClock(repo.snapshot);
      await tester.tap(find.text('Задания').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Календарь').last);
      await tester.pumpAndSettle();
      await expectSelected(tester, today, 'Месяц');
      background.openNotification!('calendar:2026-10-12|event:test');
      await tester.pumpAndSettle();
      await expectSelected(tester, repo.selected, 'День');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Месяц'));
      await tester.pumpAndSettle();
      background.openNotification!('calendar:2026-10-12|event:test');
      await tester.pumpAndSettle();
      await expectSelected(tester, repo.selected, 'День');
    },
  );

  for (final hidden in [false, true]) {
    testWidgets(
      'a new family session resets remembered calendar, hidden: $hidden',
      (tester) async {
        final repo = KeepDateFixture(DateTime.utc(2026, 10, 12, 12));
        await openCalendarApp(tester, repo);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Месяц'));
        await tester.pumpAndSettle();
        if (hidden) {
          await tester.tap(find.text('Задания').last);
          await tester.pumpAndSettle();
        }
        repo.generation++;
        repo.token = 'another-synthetic-family';
        repo.notifyListeners();
        await tester.pumpAndSettle();
        if (hidden) {
          await tester.tap(find.text('Календарь').last);
          await tester.pumpAndSettle();
        }
        await expectSelected(tester, familyClock(repo.snapshot), 'День');
      },
    );
  }

  for (final task in [false, true]) {
    testWidgets('failed save and cancelled editor keep date, task: $task', (
      tester,
    ) async {
      final repo = KeepDateFixture(DateTime.utc(2026, 10, 12, 12));
      await openCalendarApp(tester, repo);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Неделя'));
      await tester.pumpAndSettle();
      if (task) {
        await tapVisible(tester, find.text('Семейные задания'));
        await tapVisible(tester, find.text('Добавить задание'));
        await fillRequired(tester);
      } else {
        await tapVisible(tester, find.text('Добавить событие'));
        await tester.enterText(
          find.byKey(const ValueKey('event-title')),
          'Проверка отказа',
        );
      }
      repo.failNext = true;
      await tapVisible(tester, find.text('Сохранить'));
      expect(find.text('Проверочное сохранение отклонено'), findsOneWidget);
      expect(repo.mutations, isEmpty);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      if (task) {
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }
      await expectSelected(tester, repo.selected, 'Неделя');
    });
  }
}
